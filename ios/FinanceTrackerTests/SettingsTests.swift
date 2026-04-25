//
//  SettingsTests.swift
//  Slice 5 — verifies ThemeStore persistence + launch-arg override,
//  AuthService.signOut idempotence + cache reset, and UserDTO decoding
//  with the createdAt field surfaced for the "Member since" copy.
//

import XCTest
@testable import FinanceTracker

@MainActor
final class SettingsTests: XCTestCase {

    // MARK: - ThemeStore

    func testThemeStorePersistsSelection() {
        let suite = isolatedDefaults("ft.theme.persist")
        // First instance writes a non-default selection.
        let first = ThemeStore(defaults: suite, launchArgs: [])
        first.apply(.healthCards)

        // A fresh instance reading from the same defaults should pick it up.
        let second = ThemeStore(defaults: suite, launchArgs: [])
        XCTAssertEqual(second.current.id, .healthCards)
    }

    func testThemeStoreDefaultsToLiquidGlassWhenUnset() {
        let suite = isolatedDefaults("ft.theme.default")
        let store = ThemeStore(defaults: suite, launchArgs: [])
        XCTAssertEqual(store.current.id, .liquidGlass)
    }

    func testThemeStoreRespectsLaunchArgOverride() {
        let suite = isolatedDefaults("ft.theme.launch")
        // Persisted choice says liquidGlass, launch arg overrides to healthCards.
        suite.set(ThemeID.liquidGlass.rawValue, forKey: "FinanceTracker.selectedTheme")
        let store = ThemeStore(defaults: suite, launchArgs: ["FinanceTracker", "-theme=healthCards"])
        XCTAssertEqual(store.current.id, .healthCards)
        // Launch-arg overrides should NOT clobber the persisted preference, so a
        // subsequent "real" launch (no launch arg) reads the original value.
        let realLaunch = ThemeStore(defaults: suite, launchArgs: [])
        XCTAssertEqual(realLaunch.current.id, .liquidGlass)
    }

    // MARK: - AuthService.signOut

    func testAuthServiceSignOutClearsKeychainAndResetsState() async throws {
        let store = InMemoryTokenStore()
        try store.save(access: "fake-access", refresh: "fake-refresh")
        let auth = AuthService(tokenStore: store)
        // Pretend we're signed in: call the test-only seed helper to push a UserDTO.
        auth._test_seedSignedIn(user: SettingsTests.fixtureUser())

        XCTAssertTrue(auth.isAuthenticated)
        XCTAssertNotNil(store.loadAccessToken())

        auth.signOut()

        XCTAssertFalse(auth.isAuthenticated)
        if case .signedIn = auth.status { XCTFail("status should be signedOut after signOut") }
        XCTAssertNil(store.loadAccessToken())
        XCTAssertNil(store.loadRefreshToken())

        // Idempotent: calling again should not crash or change state.
        auth.signOut()
        XCTAssertNil(store.loadAccessToken())
    }

    // MARK: - UserDTO decoding

    func testCurrentUserDTODecodesWithCreatedAt() throws {
        let json = """
        {
          "id": "9d8b9f8d-3f6f-4dba-8fe2-cb5b0f8c33e1",
          "email": "claude@example.com",
          "display_name": "Claude Test",
          "currency": "USD",
          "timezone": "America/New_York",
          "is_active": true,
          "is_superuser": false,
          "created_at": "2026-04-23T02:50:00.000000Z"
        }
        """.data(using: .utf8)!

        let user = try APIClient.makeDecoder().decode(UserDTO.self, from: json)
        XCTAssertEqual(user.email, "claude@example.com")
        XCTAssertEqual(user.displayName, "Claude Test")
        XCTAssertNotNil(user.createdAt, "UserDTO should expose createdAt for the Account 'Member since' line")
    }

    // MARK: - Helpers

    /// A throwaway UserDefaults suite scoped to a single test, so tests don't
    /// leak preferences into each other or the real .standard defaults.
    private func isolatedDefaults(_ name: String) -> UserDefaults {
        let id = "\(name).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: id)!
        d.removePersistentDomain(forName: id)
        return d
    }

    static func fixtureUser() -> UserDTO {
        // Decode from JSON so we exercise the same path as production.
        let json = """
        {
          "id": "9d8b9f8d-3f6f-4dba-8fe2-cb5b0f8c33e1",
          "email": "fixture@example.com",
          "display_name": "Fixture",
          "currency": "USD",
          "timezone": "America/New_York",
          "is_active": true,
          "is_superuser": false,
          "created_at": "2026-04-23T02:50:00.000000Z"
        }
        """.data(using: .utf8)!
        return try! APIClient.makeDecoder().decode(UserDTO.self, from: json)
    }
}

// MARK: - In-memory token store for tests

final class InMemoryTokenStore: TokenStore, TokenProvider, @unchecked Sendable {
    private var access: String?
    private var refresh: String?

    func loadAccessToken() -> String? { access }
    func loadRefreshToken() -> String? { refresh }
    func save(access: String?, refresh: String?) throws {
        self.access = access
        self.refresh = refresh
    }
    func wipe() {
        access = nil
        refresh = nil
    }
    func currentAccessToken() -> String? { access }
    func updateAccessToken(_ token: String?) async { access = token }
}
