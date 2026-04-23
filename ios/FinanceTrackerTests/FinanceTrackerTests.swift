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

    func testThemeStoreDefaultsToLiquidGlass() {
        let store = ThemeStore()
        XCTAssertEqual(store.current.id, .liquidGlass)
    }
}
