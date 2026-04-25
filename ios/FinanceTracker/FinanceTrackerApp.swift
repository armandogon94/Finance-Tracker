//
//  FinanceTrackerApp.swift
//  Finance Tracker — native SwiftUI app targeting iOS 26+.
//
//  The app boots into RootView, which hosts a tab bar. The overall visual
//  language is swappable via the AppTheme environment, configurable at
//  runtime from Settings → Design Playground.
//

import SwiftUI

@main
struct FinanceTrackerApp: App {
    @State private var themeStore = ThemeStore()
    @State private var auth = AuthService()
    @State private var expenses: ExpensesService
    @State private var categories: CategoriesService
    @State private var analytics: AnalyticsService

    init() {
        // Preview harness launch args (see docs/ios-design-previews/capture.sh):
        //   -theme=<liquidGlass|healthCards>    override persisted theme
        //   -skipAuth                           bypass login (uses mock data)
        let args = ProcessInfo.processInfo.arguments
        for a in args where a.hasPrefix("-theme=") {
            let raw = String(a.dropFirst("-theme=".count))
            if let id = ThemeID(rawValue: raw) {
                UserDefaults.standard.set(id.rawValue, forKey: "FinanceTracker.selectedTheme")
            }
        }
        if args.contains("-skipAuth") {
            UserDefaults.standard.set(true, forKey: "FinanceTracker.skipAuth")
        }

        // Construct AuthService first so the other services can reuse its
        // APIClient (same actor = same token provider = one keychain read).
        let authService = AuthService()
        let expensesService = ExpensesService(api: authService.api)
        let categoriesService = CategoriesService(api: authService.api)
        let analyticsService = AnalyticsService(api: authService.api)

        // On signOut, wipe in-memory caches so the next user starts clean.
        // AuthService doesn't import these services directly — keeps the
        // dependency arrow pointing one way (services → auth, not the inverse).
        authService.onSignOut = { [
            weak expensesService,
            weak categoriesService,
            weak analyticsService
        ] in
            expensesService?.reset()
            categoriesService?.reset()
            analyticsService?.reset()
        }

        self._auth = State(initialValue: authService)
        self._expenses = State(initialValue: expensesService)
        self._categories = State(initialValue: categoriesService)
        self._analytics = State(initialValue: analyticsService)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appTheme, themeStore.current)
                .environment(themeStore)
                .environment(auth)
                .environment(expenses)
                .environment(categories)
                .environment(analytics)
                .preferredColorScheme(themeStore.current.preferredColorScheme)
                .task {
                    await auth.restoreSession()
                }
        }
    }
}
