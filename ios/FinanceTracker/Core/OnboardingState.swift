//
//  OnboardingState.swift
//  Slice 10 — gates the WelcomeView. Mirrors the slice 5 ThemeStore
//  pattern: UserDefaults-backed via injected suite so tests don't touch
//  the real shared defaults. Intentionally NOT wired into AuthService's
//  onSignOut callback — once a user has dismissed the welcome screen,
//  signing out and back in shouldn't replay it.
//

import Foundation
import Observation

@Observable
final class OnboardingState {
    private(set) var hasSeenWelcome: Bool

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let storageKey = "FinanceTracker.hasSeenWelcome"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasSeenWelcome = defaults.bool(forKey: storageKey)
    }

    func markSeen() {
        hasSeenWelcome = true
        defaults.set(true, forKey: storageKey)
    }

    /// Test-only escape hatch — re-enables the welcome flow as if this
    /// were a fresh install. Not exposed to production callers.
    func _test_clear() {
        hasSeenWelcome = false
        defaults.removeObject(forKey: storageKey)
    }
}
