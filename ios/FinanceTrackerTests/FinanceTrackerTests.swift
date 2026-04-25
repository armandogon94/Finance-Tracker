//
//  FinanceTrackerTests.swift
//  Placeholder test target so xcodegen produces a complete scheme.
//  Real logic tests will land once the APIClient and view models are in.
//

import XCTest
@testable import FinanceTracker

final class FinanceTrackerTests: XCTestCase {
    func testMockDataHasCategories() {
        XCTAssertEqual(MockData.categories.count, 9)
        XCTAssertNotNil(MockData.category(named: "Food & Dining"))
    }

    func testTotalDebtIsSumOfLinesItems() {
        let expected = MockData.creditCards.reduce(0) { $0 + $1.currentBalance }
                     + MockData.loans.reduce(0) { $0 + $1.currentBalance }
        XCTAssertEqual(MockData.totalDebt, expected, accuracy: 0.01)
    }

    @MainActor
    func testThemeStoreDefaultsToLiquidGlass() {
        // Use a throwaway suite so a real-device launch that switched to D5
        // doesn't leak into this regression test (we hit that exact bug
        // during slice 6 — the test ran against UserDefaults.standard which
        // a sim run had already mutated).
        let suite = "ft.theme.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ThemeStore(defaults: defaults, launchArgs: [])
        XCTAssertEqual(store.current.id, .liquidGlass)
    }
}
