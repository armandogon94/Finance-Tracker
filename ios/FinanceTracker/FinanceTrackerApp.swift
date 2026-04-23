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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appTheme, themeStore.current)
                .environment(themeStore)
                .preferredColorScheme(themeStore.current.preferredColorScheme)
        }
    }
}
