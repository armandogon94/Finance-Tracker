//
//  ThemeStore.swift
//  Persistent theme selection. Drop this into the Environment at the app
//  entry; views call themeStore.apply(.liquidGlass) to switch designs.
//

import SwiftUI
import Observation

@Observable
final class ThemeStore {
    private(set) var current: any AppTheme = LiquidGlassTheme()

    @ObservationIgnored
    private let storageKey = "FinanceTracker.selectedTheme"

    init() {
        // Launch-arg override wins over persisted value — used for the
        // `simctl launch … -theme=<id>` design-comparison flow.
        for a in ProcessInfo.processInfo.arguments where a.hasPrefix("-theme=") {
            let raw = String(a.dropFirst("-theme=".count))
            if let id = ThemeID(rawValue: raw) {
                apply(id, persist: false)
                return
            }
        }
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let id = ThemeID(rawValue: raw) {
            apply(id, persist: false)
        }
    }

    func apply(_ id: ThemeID, persist: Bool = true) {
        current = Self.theme(for: id)
        if persist {
            UserDefaults.standard.set(id.rawValue, forKey: storageKey)
        }
    }

    static func theme(for id: ThemeID) -> any AppTheme {
        switch id {
        case .liquidGlass: LiquidGlassTheme()
        case .healthCards: HealthCardsTheme()
        }
    }
}

// MARK: - Environment plumbing

private struct AppThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: any AppTheme = LiquidGlassTheme()
}

extension EnvironmentValues {
    var appTheme: any AppTheme {
        get { self[AppThemeEnvironmentKey.self] }
        set { self[AppThemeEnvironmentKey.self] = newValue }
    }
}
