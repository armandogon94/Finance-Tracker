//
//  AnalyticsService.swift
//  Loads the two analytics endpoints we render today and exposes derived
//  helpers for the hero card. Endpoints in play (verified via openapi probe
//  on 2026-04-24):
//
//    GET /api/v1/analytics/monthly?year=YYYY
//      → { year: Int, data: [{ month: 1..12, total: Double, count: Int }] }
//      Returns 12 rows even when months have zero spend, so we don't need
//      to worry about gaps. Drives the hero "spent this month" + the
//      6-month bar trend.
//
//    GET /api/v1/analytics/by-category?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
//      → { data: [{ category_id, category_name, color, icon, total, count, percentage }], grand_total }
//      `category_id` is null for the "Uncategorized" bucket.
//
//  Partial-failure semantics: if at least one of the two calls succeeds, the
//  service lands in `.partial(message)` and the caches for the failed half
//  stay empty. Only when BOTH fail do we land in `.failed`. This way the UI
//  can keep rendering whatever data is available.
//

import Foundation
import Observation

@Observable @MainActor
final class AnalyticsService {
    enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case partial(String)
        case failed(String)
    }

    private(set) var state: LoadState = .idle

    /// Year currently held in `monthly`. Defaults to the current calendar year.
    private(set) var year: Int = Calendar.current.component(.year, from: Date())
    /// 12 rows (or empty if not yet loaded). Sorted by month ascending.
    private(set) var monthly: [MonthlyAnalyticsRowDTO] = []

    /// Per-category spend for the current calendar month.
    private(set) var byCategory: [CategoryBreakdownRowDTO] = []
    private(set) var grandTotal: Double = 0

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Loading

    /// Fan out to both endpoints concurrently. The current month range is
    /// derived from `Date()`; tests don't go through this entry point.
    func loadAll(now: Date = Date()) async {
        state = .loading
        let cal = Calendar(identifier: .iso8601)
        let year = cal.component(.year, from: now)
        let monthInterval = cal.dateInterval(of: .month, for: now)!
        let f = DateFormatter.yyyyMMddUTC
        let start = f.string(from: monthInterval.start)
        // dateInterval's end is the START of the next month (exclusive).
        // The backend treats end_date as inclusive, so back off by one day.
        let endDate = cal.date(byAdding: .day, value: -1, to: monthInterval.end)!
        let end = f.string(from: endDate)

        async let monthlyTask: MonthlyAnalyticsResponseDTO = api.get(
            "/api/v1/analytics/monthly",
            query: ["year": String(year)]
        )
        async let byCategoryTask: CategoryBreakdownResponseDTO = api.get(
            "/api/v1/analytics/by-category",
            query: ["start_date": start, "end_date": end]
        )

        // Wait for both, but capture each as Result so a failure in one
        // doesn't cancel the other (Result init that takes an async closure
        // would, but Swift forbids capturing `async let` in a closure).
        let monthlyResult: Result<MonthlyAnalyticsResponseDTO, Error>
        do { monthlyResult = .success(try await monthlyTask) }
        catch { monthlyResult = .failure(error) }

        let byCategoryResult: Result<CategoryBreakdownResponseDTO, Error>
        do { byCategoryResult = .success(try await byCategoryTask) }
        catch { byCategoryResult = .failure(error) }

        switch (monthlyResult, byCategoryResult) {
        case (.success(let m), .success(let c)):
            self.year = m.year
            self.monthly = m.data.sorted { $0.month < $1.month }
            self.byCategory = c.data
            self.grandTotal = c.grandTotal
            self.state = .loaded

        case (.success(let m), .failure):
            self.year = m.year
            self.monthly = m.data.sorted { $0.month < $1.month }
            self.byCategory = []
            self.grandTotal = 0
            self.state = .partial("Couldn't load category breakdown.")

        case (.failure, .success(let c)):
            self.year = year
            self.monthly = []
            self.byCategory = c.data
            self.grandTotal = c.grandTotal
            self.state = .partial("Couldn't load monthly trend.")

        case (.failure(let mErr), .failure):
            self.state = .failed((mErr as? APIError)?.errorDescription ?? "Couldn't load analytics.")
        }
    }

    /// Wipe everything back to idle. Called from AuthService.onSignOut so the
    /// next signed-in user doesn't briefly see the previous user's charts.
    func reset() {
        state = .idle
        monthly = []
        byCategory = []
        grandTotal = 0
        year = Calendar.current.component(.year, from: Date())
    }

    // MARK: - Derived helpers (hero card)

    /// Spend total for the calendar month containing `now`. Returns 0 if
    /// the year doesn't match (caller hit a stale cache).
    func spentThisMonth(now: Date = Date()) -> Double {
        let cal = Calendar(identifier: .iso8601)
        guard cal.component(.year, from: now) == year else { return 0 }
        let m = cal.component(.month, from: now)
        return monthly.first(where: { $0.month == m })?.total ?? 0
    }

    /// Spend total for the previous calendar month. Crosses the year boundary
    /// gracefully — if `now` is January, this returns 0 (we don't have prev
    /// year's data cached unless someone called loadAll(year: y - 1) which we
    /// don't do today). Acceptable v1 behaviour; revisit if Mom complains.
    func spentLastMonth(now: Date = Date()) -> Double {
        let cal = Calendar(identifier: .iso8601)
        let m = cal.component(.month, from: now)
        let prev = m - 1
        guard prev >= 1, cal.component(.year, from: now) == year else { return 0 }
        return monthly.first(where: { $0.month == prev })?.total ?? 0
    }

    /// (this - last) / last * 100. Returns 0 when last month is 0 — avoids
    /// "infinity%" labels when the user just started tracking.
    func percentChange(now: Date = Date()) -> Double {
        let last = spentLastMonth(now: now)
        guard last > 0 else { return 0 }
        return ((spentThisMonth(now: now) - last) / last) * 100
    }

    /// The most recent N months of `monthly`, in chronological order. Used by
    /// the bar chart. If we have fewer than N months populated (e.g. early in
    /// the year), pads from the start.
    func trailingMonths(_ count: Int = 6, now: Date = Date()) -> [MonthlyAnalyticsRowDTO] {
        let cal = Calendar(identifier: .iso8601)
        let m = cal.component(.month, from: now)
        let lo = max(1, m - count + 1)
        return monthly.filter { $0.month >= lo && $0.month <= m }
    }

    // MARK: - Test hooks

    /// Test-only: seed the service with canned data so derived helpers can
    /// be verified without going through the network.
    func _test_seed(
        year: Int,
        monthly: [MonthlyAnalyticsRowDTO],
        byCategory: [CategoryBreakdownRowDTO],
        grandTotal: Double
    ) {
        self.year = year
        self.monthly = monthly.sorted { $0.month < $1.month }
        self.byCategory = byCategory
        self.grandTotal = grandTotal
        self.state = .loaded
    }

    /// Test-only: drive the partial/failed branch of `loadAll`. Mirrors the
    /// real switch statement so the same state-transition logic is exercised.
    func _test_finalize(
        monthlySucceeded: Bool,
        byCategorySucceeded: Bool,
        year: Int,
        monthly: [MonthlyAnalyticsRowDTO],
        byCategory: [CategoryBreakdownRowDTO],
        grandTotal: Double
    ) {
        switch (monthlySucceeded, byCategorySucceeded) {
        case (true, true):
            _test_seed(year: year, monthly: monthly, byCategory: byCategory, grandTotal: grandTotal)
        case (true, false):
            self.year = year
            self.monthly = monthly.sorted { $0.month < $1.month }
            self.byCategory = []
            self.grandTotal = 0
            self.state = .partial("Couldn't load category breakdown.")
        case (false, true):
            self.year = year
            self.monthly = []
            self.byCategory = byCategory
            self.grandTotal = grandTotal
            self.state = .partial("Couldn't load monthly trend.")
        case (false, false):
            self.state = .failed("Couldn't load analytics.")
        }
    }
}

// MARK: - Helpers

private extension DateFormatter {
    /// `yyyy-MM-dd` in UTC, en_US_POSIX. Lives here so we don't keep
    /// re-creating one on every loadAll call. Static lazy init = thread-safe.
    static let yyyyMMddUTC: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
