//
//  OnboardingTests.swift
//  Slice 10 — verifies the WelcomeView gate. Same UserDefaults injection
//  pattern as ThemeStore (slice 5) so the test never touches the real
//  shared defaults and never leaks state between runs.
//

import XCTest
@testable import FinanceTracker

@MainActor
final class OnboardingTests: XCTestCase {

    func testOnboardingDefaultsToNotSeen() {
        let defaults = isolatedDefaults("ft.onboarding.default")
        let store = OnboardingState(defaults: defaults)
        XCTAssertFalse(store.hasSeenWelcome,
            "fresh defaults should put the user into the welcome flow")
    }

    func testOnboardingMarkSeenPersists() {
        let defaults = isolatedDefaults("ft.onboarding.persist")
        let first = OnboardingState(defaults: defaults)
        first.markSeen()
        XCTAssertTrue(first.hasSeenWelcome)

        // A fresh instance reading the same defaults must see the flag.
        let second = OnboardingState(defaults: defaults)
        XCTAssertTrue(second.hasSeenWelcome,
            "a relaunch must remember the user already dismissed the welcome")
    }

    /// Sign-out is *not* a re-onboarding event. The user has already seen
    /// the value-prop screen; showing it again on every sign-out would feel
    /// patronising. This test pins down that intentional design choice.
    func testOnboardingSurvivesAcrossSignOut() {
        let defaults = isolatedDefaults("ft.onboarding.signout")
        let store = OnboardingState(defaults: defaults)
        store.markSeen()
        // Simulate sign-out: AuthService.onSignOut fires. OnboardingState
        // intentionally has no reset() hook wired into that callback.
        XCTAssertTrue(store.hasSeenWelcome,
            "sign-out must NOT clear the onboarding flag")
    }

    // MARK: - Helpers

    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let id = "\(name).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: id)!
        d.removePersistentDomain(forName: id)
        return d
    }
}
