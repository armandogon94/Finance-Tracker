//
//  AnalyticsTests.swift
//  Slice 6 — verifies analytics DTO decoding (matches the real backend
//  shapes discovered via openapi probe), the derived helpers used by
//  the hero card (spentThisMonth / spentLastMonth / percentChange),
//  and AnalyticsService's partial-failure semantics.
//
//  Endpoints in play:
//    GET /api/v1/analytics/monthly?year=YYYY      → { year, data: [{month,total,count}] }
//    GET /api/v1/analytics/by-category?start=&end= → { data: [...], grand_total }
//

import XCTest
@testable import FinanceTracker

@MainActor
final class AnalyticsTests: XCTestCase {

    // MARK: - DTO decoding

    func testMonthlyAnalyticsResponseDTODecodes() throws {
        let json = """
        {
          "year": 2026,
          "data": [
            {"month": 1, "total": 0.0, "count": 0},
            {"month": 4, "total": 78.54, "count": 5},
            {"month": 12, "total": 1200.0, "count": 42}
          ]
        }
        """.data(using: .utf8)!

        let resp = try APIClient.makeDecoder().decode(MonthlyAnalyticsResponseDTO.self, from: json)
        XCTAssertEqual(resp.year, 2026)
        XCTAssertEqual(resp.data.count, 3)
        XCTAssertEqual(resp.data[1].month, 4)
        XCTAssertEqual(resp.data[1].total, 78.54, accuracy: 0.001)
        XCTAssertEqual(resp.data[1].count, 5)
    }

    func testCategoryBreakdownResponseDTODecodesIncludingNullCategoryId() throws {
        // The backend returns `category_id: null` for the synthetic
        // "Uncategorized" bucket. Make sure that decodes as nil, not crashes.
        let json = """
        {
          "data": [
            {
              "category_id": "d12e0ed2-3bc2-4cb8-aae7-f464ff99ce57",
              "category_name": "Food & Dining",
              "color": "#EF4444",
              "icon": "utensils",
              "total": 55.55,
              "count": 2,
              "percentage": 70.7
            },
            {
              "category_id": null,
              "category_name": "Uncategorized",
              "color": "#6B7280",
              "icon": "receipt",
              "total": 22.99,
              "count": 3,
              "percentage": 29.3
            }
          ],
          "grand_total": 78.54,
          "start_date": "2026-04-01",
          "end_date": "2026-04-30"
        }
        """.data(using: .utf8)!

        let resp = try APIClient.makeDecoder().decode(CategoryBreakdownResponseDTO.self, from: json)
        XCTAssertEqual(resp.grandTotal, 78.54, accuracy: 0.001)
        XCTAssertEqual(resp.data.count, 2)
        XCTAssertNotNil(resp.data[0].categoryId)
        XCTAssertNil(resp.data[1].categoryId)
        XCTAssertEqual(resp.data[1].categoryName, "Uncategorized")
        XCTAssertEqual(resp.data[0].percentage, 70.7, accuracy: 0.001)
    }

    // MARK: - Derived helpers

    func testAnalyticsServiceDerivesSpentThisMonthFromMonthly() {
        let service = AnalyticsService(api: APIClient())
        // Seed with a fake April 2026 dataset.
        service._test_seed(
            year: 2026,
            monthly: [
                .init(month: 1, total: 0, count: 0),
                .init(month: 2, total: 0, count: 0),
                .init(month: 3, total: 200, count: 3),
                .init(month: 4, total: 78.54, count: 5)
            ],
            byCategory: [],
            grandTotal: 0
        )
        let aprilFifteenth = Self.date(2026, 4, 15)
        XCTAssertEqual(service.spentThisMonth(now: aprilFifteenth), 78.54, accuracy: 0.001)
        XCTAssertEqual(service.spentLastMonth(now: aprilFifteenth), 200.0, accuracy: 0.001)
    }

    func testAnalyticsServiceDerivesPercentChangeFromMonthly() {
        let service = AnalyticsService(api: APIClient())
        service._test_seed(
            year: 2026,
            monthly: [
                .init(month: 3, total: 100, count: 1),
                .init(month: 4, total: 75, count: 1) // 25% less than last month
            ],
            byCategory: [],
            grandTotal: 0
        )
        let april = Self.date(2026, 4, 15)
        // (75 - 100) / 100 * 100 = -25.0
        XCTAssertEqual(service.percentChange(now: april), -25.0, accuracy: 0.001)
    }

    // MARK: - Partial failure

    func testAnalyticsServicePartialStateWhenOneEndpointMissing() {
        let service = AnalyticsService(api: APIClient())
        // Simulate "monthly succeeded, by-category failed" by seeding only the
        // monthly side and calling the test hook that finalises the state.
        service._test_finalize(
            monthlySucceeded: true,
            byCategorySucceeded: false,
            year: 2026,
            monthly: [.init(month: 4, total: 50, count: 1)],
            byCategory: [],
            grandTotal: 0
        )

        if case .partial(let msg) = service.state {
            XCTAssertFalse(msg.isEmpty, "partial state should carry a non-empty message")
        } else {
            XCTFail("expected .partial, got \(service.state)")
        }

        // The successful slice's data should still be populated.
        XCTAssertEqual(service.monthly.count, 1)
        XCTAssertTrue(service.byCategory.isEmpty)
    }

    // MARK: - Helpers

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .iso8601).date(from: c)!
    }
}
