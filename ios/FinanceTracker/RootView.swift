//
//  RootView.swift
//  Tab-bar root for the logged-in experience. Pre-login, LoginView is shown.
//

import SwiftUI

struct RootView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AuthService.self) private var auth
    @Environment(ExpensesService.self) private var expenses
    @Environment(CategoriesService.self) private var categories
    @Environment(AnalyticsService.self) private var analytics
    @Environment(DebtService.self) private var debt
    @Environment(AppNavigation.self) private var nav
    @Environment(OnboardingState.self) private var onboarding

    @State private var showWelcome = false

    /// Dev harness: pass `-startTab=expenses|home|scan|debt|chat|more` to
    /// open that tab on launch. Handy for isolated screenshots. Returns nil
    /// when the arg is absent so we don't clobber AppNavigation's default.
    private static func launchArgTab() -> Tab? {
        for a in ProcessInfo.processInfo.arguments where a.hasPrefix("-startTab=") {
            let raw = String(a.dropFirst("-startTab=".count))
            switch raw {
            case "home":     return .home
            case "expenses": return .expenses
            case "scan":     return .scan
            case "debt":     return .debt
            case "chat":     return .chat
            case "more":     return .more
            default: break
            }
        }
        return nil
    }

    private var skipAuth: Bool {
        // skipAuth + MockData fallbacks are dev-only conveniences from
        // slice 0. In Release builds (TestFlight, App Store) auth is
        // strictly required — no launch arg can bypass it.
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "FinanceTracker.skipAuth")
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if auth.isAuthenticated || skipAuth {
                mainTabView
                    .task {
                        // All three loads share the APIClient actor and hit
                        // independent endpoints — fan out so the user sees a
                        // populated Home, Analytics tab, and category chips
                        // in roughly the time of the slowest single request.
                        async let a: Void = expenses.loadAll()
                        async let b: Void = categories.loadAll()
                        async let c: Void = analytics.loadAll()
                        async let d: Void = debt.loadAll()
                        _ = await (a, b, c, d)
                    }
                    .onAppear {
                        // Honour the -startTab=… launch arg only on first
                        // appearance. Subsequent tab switches go through
                        // AppNavigation (e.g. ScanView post-save).
                        if let initial = RootView.launchArgTab() {
                            nav.selectedTab = initial
                        }
                    }
            } else {
                LoginView()
            }
        }
        .animation(.smooth, value: auth.isAuthenticated)
        .onAppear {
            // Defer the sheet to the next runloop tick so it doesn't fight
            // the cold-launch transition. iOS 26 doesn't always paint the
            // background view if a sheet presents synchronously on appear.
            if !onboarding.hasSeenWelcome { showWelcome = true }
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeView()
                .presentationDetents([.large])
                .presentationBackgroundInteraction(.disabled)
        }
    }

    private var mainTabView: some View {
        // @Bindable lets us derive a binding off the environment-injected
        // @Observable AppNavigation so TabView's selection can be two-way.
        @Bindable var navB = nav
        return TabView(selection: $navB.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)

            ExpensesListView()
                .tabItem { Label("Expenses", systemImage: "list.bullet.rectangle") }
                .tag(Tab.expenses)

            ScanView()
                .tabItem { Label("Scan", systemImage: "viewfinder") }
                .tag(Tab.scan)

            DebtDashboardView()
                .tabItem { Label("Debt", systemImage: "creditcard.fill") }
                .tag(Tab.debt)

            ChatView()
                .tabItem { Label("Chat", systemImage: "sparkles") }
                .tag(Tab.chat)

            MoreMenuView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(Tab.more)
        }
        .tint(theme.accent)
    }
}

enum Tab: Hashable {
    case home, expenses, scan, debt, chat, more
}

// MARK: - More tab: a landing menu for Analytics / Categories / Settings

struct MoreMenuView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(MoreMenuItem.allCases, id: \.self) { item in
                        NavigationLink(value: item) {
                            moreRow(for: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("More")
            // Sign Out lives inside SettingsView — keeping it in one place
            // avoids "wait, why are there two?" moments and leaves room here
            // for future cells (Help, Send feedback, etc.).
            .navigationDestination(for: MoreMenuItem.self) { item in
                switch item {
                case .analytics: AnalyticsView()
                case .categories: CategoriesView()
                case .settings: SettingsView()
                }
            }
        }
    }

    private func moreRow(for item: MoreMenuItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 40, height: 40)
                .background(theme.accent.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                Text(item.subtitle).font(theme.font.caption).foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radii.card))
    }
}

enum MoreMenuItem: CaseIterable, Hashable {
    case analytics, categories, settings

    var title: String {
        switch self {
        case .analytics: "Analytics"
        case .categories: "Categories"
        case .settings: "Settings"
        }
    }
    var subtitle: String {
        switch self {
        case .analytics: "Charts, trends, breakdowns"
        case .categories: "Organize your spending"
        case .settings: "Theme, account, sign out"
        }
    }
    var icon: String {
        switch self {
        case .analytics: "chart.line.uptrend.xyaxis"
        case .categories: "square.grid.2x2.fill"
        case .settings: "gearshape.fill"
        }
    }
}

#Preview {
    RootView()
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(ThemeStore())
        .environment(AuthService())
        .environment(ExpensesService(api: APIClient()))
        .environment(CategoriesService(api: APIClient()))
        .environment(AnalyticsService(api: APIClient()))
        .environment(ScanService(uploader: { _ in fatalError() }, confirmer: { _ in fatalError() }, onCreated: { _ in }))
        .environment(DebtService.previewStub())
        .environment(ChatService(conversationFactory: { UUID() }, streamer: { _, _ in AsyncThrowingStream { c in c.finish() } }))
        .environment(AppNavigation())
        .environment(OnboardingState())
}
