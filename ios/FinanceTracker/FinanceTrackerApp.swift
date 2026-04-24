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
        self._auth = State(initialValue: authService)
        self._expenses = State(initialValue: ExpensesService(api: authService.api))
        self._categories = State(initialValue: CategoriesService(api: authService.api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appTheme, themeStore.current)
                .environment(themeStore)
                .environment(auth)
                .environment(expenses)
                .environment(categories)
                .preferredColorScheme(themeStore.current.preferredColorScheme)
                .task {
                    await auth.restoreSession()
                }
        }
    }
}
