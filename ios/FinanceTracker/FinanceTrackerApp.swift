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

    init() {
        // Preview harness launch args (used by simctl for design comparison shots):
        //   -theme=<liquidGlass|editorial|darkTerminal|warmPaper|healthCards>
        //   -skipAuth    → start already "signed in"
        let args = ProcessInfo.processInfo.arguments
        for a in args {
            if a.hasPrefix("-theme=") {
                let raw = String(a.dropFirst("-theme=".count))
                if let id = ThemeID(rawValue: raw) {
                    UserDefaults.standard.set(id.rawValue, forKey: "FinanceTracker.selectedTheme")
                }
            }
        }
        if args.contains("-skipAuth") {
            UserDefaults.standard.set(true, forKey: "FinanceTracker.skipAuth")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appTheme, themeStore.current)
                .environment(themeStore)
                .preferredColorScheme(themeStore.current.preferredColorScheme)
        }
    }
}
