//
//  ThemeStore.swift
//  Persistent theme selection. Drop this into the Environment at the app
//  entry; views call themeStore.apply(.liquidGlass) to switch designs.
//
//  Defaults source and launch arguments are injected so unit tests can
//  exercise persistence and the `-theme=<id>` override path without
//  polluting the user's real UserDefaults.
//

import SwiftUI
import Observation

@Observable
final class ThemeStore {
    private(set) var current: any AppTheme = LiquidGlassTheme()

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let storageKey = "FinanceTracker.selectedTheme"

    /// - Parameters:
    ///   - defaults: where the persisted theme id lives. Inject a custom suite
    ///     in tests to keep state isolated.
    ///   - launchArgs: the process arguments to scan for `-theme=<id>`.
    ///     Defaults to the live process; tests pass an explicit array.
    init(
        defaults: UserDefaults = .standard,
        launchArgs: [String] = ProcessInfo.processInfo.arguments
    ) {
        self.defaults = defaults
        // Launch-arg override wins over persisted value — used for the
        // `simctl launch … -theme=<id>` design-comparison flow. Crucially
        // we DON'T persist the override, so the next "real" launch reads
        // back the user's actual saved preference.
        for a in launchArgs where a.hasPrefix("-theme=") {
            let raw = String(a.dropFirst("-theme=".count))
            if let id = ThemeID(rawValue: raw) {
                applyInternal(id, persist: false)
                return
            }
        }
        if let raw = defaults.string(forKey: storageKey),
           let id = ThemeID(rawValue: raw) {
            applyInternal(id, persist: false)
        }
    }

    /// Public switch — persists the choice so the next launch starts here.
    func apply(_ id: ThemeID) {
        applyInternal(id, persist: true)
    }

    private func applyInternal(_ id: ThemeID, persist: Bool) {
        current = Self.theme(for: id)
        if persist {
            defaults.set(id.rawValue, forKey: storageKey)
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
