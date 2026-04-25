//
//  AnalyticsView.swift
//  Slice 6 — three real charts driven by AnalyticsService:
//   - Hero: spent this month + delta vs last month
//   - Category breakdown: SectorMark donut for the current month
//   - 6-month trend: BarMark, current month accented
//  Pull-to-refresh re-runs analytics.loadAll(). Empty / loading / partial /
//  failed states each get a dedicated rendering so the page never looks
//  blank without explanation.
//

import SwiftUI
import Charts

struct AnalyticsView: View {
    @Environment(\.appTheme) private var theme
    @Environment(AnalyticsService.self) private var analytics

    @State private var refreshStamp = 0

    private var now: Date { Date() }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 16) {
                    switch analytics.state {
                    case .idle:
                        loadingCard
                    case .loading where analytics.monthly.isEmpty && analytics.byCategory.isEmpty:
                        loadingCard
                    case .failed(let msg):
                        errorCard(msg)
                    case .loaded, .partial, .loading:
                        if isEmpty {
                            emptyState
                        } else {
                            heroCard
                            if !analytics.byCategory.isEmpty {
                                donutCard
                            }
                            if !analytics.monthly.isEmpty {
                                trendCard
                            }
                            if case .partial(let msg) = analytics.state {
                                partialBanner(msg)
                            }
                        }
                    }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                refreshStamp += 1
                await analytics.loadAll()
            }
        }
        .navigationTitle("Analytics")
        .toolbarBackground(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: refreshStamp)
    }

    // MARK: - Empty / loading / error

    private var isEmpty: Bool {
        analytics.byCategory.isEmpty && analytics.monthly.allSatisfy { $0.total == 0 }
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(theme.accent)
            Text("Loading your spending…")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(24)
        .themedCard()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(theme.textTertiary)
            Text("No spending yet")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Text("Add your first expense and your charts will show up here.")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(24)
        .themedCard()
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(theme.negative)
            Text("Couldn't load analytics")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Text(msg)
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await analytics.loadAll() }
            } label: {
                Text("Try again")
                    .font(theme.font.bodyMedium)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(theme.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .themedCard()
    }

    private func partialBanner(_ msg: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(theme.accent)
            Text(msg)
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Hero

    private var heroCard: some View {
        let spent = analytics.spentThisMonth(now: now)
        let last = analytics.spentLastMonth(now: now)
        let pct = analytics.percentChange(now: now)
        return VStack(alignment: .leading, spacing: 6) {
            Text(monthLong(now).uppercased())
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
                Text(currencyShort.string(from: NSNumber(value: spent)) ?? "0.00")
                    .font(theme.font.heroNumeral)
                    .foregroundStyle(theme.textPrimary)
            }
            heroDelta(pct: pct, last: last)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .themedCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spent this month: \(currencyVoice.string(from: NSNumber(value: spent)) ?? "$0"). \(deltaA11y(pct: pct, last: last))")
    }

    @ViewBuilder
    private func heroDelta(pct: Double, last: Double) -> some View {
        let isUp = pct > 0
        let isFlat = abs(pct) < 0.01
        let color = isFlat ? theme.textTertiary : (isUp ? theme.negative : theme.positive)
        let arrow = isFlat ? "minus" : (isUp ? "arrow.up.right" : "arrow.down.right")
        HStack(spacing: 6) {
            Image(systemName: arrow)
            if last == 0 {
                Text("First month tracking")
            } else {
                Text(String(format: "%.0f%% vs last month", abs(pct)))
            }
        }
        .font(theme.font.caption)
        .foregroundStyle(color)
    }

    // MARK: - Donut

    private var donutCard: some View {
        let total = analytics.grandTotal
        return VStack(alignment: .leading, spacing: 12) {
            Text("By category").font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            HStack(alignment: .top, spacing: 18) {
                Chart {
                    ForEach(analytics.byCategory.filter { $0.total > 0 }) { row in
                        SectorMark(
                            angle: .value("Amount", row.total),
                            innerRadius: .ratio(0.62),
                            angularInset: 2.0
                        )
                        .cornerRadius(4)
                        .foregroundStyle(rowColor(row))
                    }
                }
                .chartLegend(.hidden)
                .frame(width: 140, height: 140)
                .overlay(
                    VStack(spacing: 0) {
                        Text("$\(currencyShort.string(from: NSNumber(value: total)) ?? "0")")
                            .font(theme.font.titleCompact)
                            .foregroundStyle(theme.textPrimary)
                        Text("this month")
                            .font(theme.font.caption)
                            .foregroundStyle(theme.textTertiary)
                    }
                )
                .accessibilityLabel(donutA11y)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(analytics.byCategory.filter { $0.total > 0 }.prefix(5)) { row in
                        HStack(spacing: 8) {
                            Circle().fill(rowColor(row)).frame(width: 8, height: 8)
                            Text(row.categoryName)
                                .font(theme.font.caption)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(row.percentage))%")
                                .font(theme.font.captionMedium)
                                .foregroundStyle(theme.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .themedCard()
    }

    private var donutA11y: String {
        let parts = analytics.byCategory.filter { $0.total > 0 }.prefix(5).map {
            "\($0.categoryName) \(Int($0.percentage)) percent"
        }
        return "Category breakdown: " + parts.joined(separator: ", ")
    }

    // MARK: - Trend

    private var trendCard: some View {
        let rows = analytics.trailingMonths(6, now: now)
        let cur = Calendar(identifier: .iso8601).component(.month, from: now)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 6 months").font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            Chart {
                ForEach(rows, id: \.month) { row in
                    BarMark(
                        x: .value("Month", monthShort(row.month, year: analytics.year)),
                        y: .value("Amount", row.total)
                    )
                    .cornerRadius(6)
                    .foregroundStyle(row.month == cur ? theme.accent : theme.textTertiary.opacity(0.55))
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(theme.textTertiary.opacity(0.2))
                    AxisValueLabel().foregroundStyle(theme.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().foregroundStyle(theme.textTertiary)
                }
            }
            .frame(height: 180)
            .accessibilityLabel(trendA11y(rows))
        }
        .padding(18)
        .themedCard()
    }

    private func trendA11y(_ rows: [MonthlyAnalyticsRowDTO]) -> String {
        let parts = rows.map {
            "\(monthShort($0.month, year: analytics.year)) \(currencyVoice.string(from: NSNumber(value: $0.total)) ?? "0")"
        }
        return "Last six months trend: " + parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    private func rowColor(_ row: CategoryBreakdownRowDTO) -> Color {
        if let c = Color(hex: row.color) { return c }
        return theme.accent
    }

    private func monthLong(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "LLLL yyyy"
        return f.string(from: date)
    }

    private func monthShort(_ month: Int, year: Int) -> String {
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        let d = Calendar(identifier: .iso8601).date(from: c) ?? Date()
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "LLL"
        return f.string(from: d)
    }

    /// `1234.56` → `"1,234.56"`. Single instance per render, not one per call.
    private var currencyShort: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale.current
        return f
    }

    private var currencyVoice: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale.current
        return f
    }

    private func deltaA11y(pct: Double, last: Double) -> String {
        if last == 0 { return "First month tracking spending." }
        if abs(pct) < 0.01 { return "Same as last month." }
        return pct > 0
            ? String(format: "Up %.0f percent versus last month.", abs(pct))
            : String(format: "Down %.0f percent versus last month.", abs(pct))
    }
}

// MARK: - Color from hex

private extension Color {
    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7 else { return nil }
        let scanner = Scanner(string: String(hex.dropFirst()))
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else { return nil }
        self = Color(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}

#Preview("Analytics — Liquid Glass") {
    NavigationStack { AnalyticsView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(AnalyticsService(api: APIClient()))
        .preferredColorScheme(.dark)
}
