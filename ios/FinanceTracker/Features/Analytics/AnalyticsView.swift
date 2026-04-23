//
//  AnalyticsView.swift
//  Native Swift Charts: daily bars + category donut + budget progress.
//

import SwiftUI
import Charts

struct AnalyticsView: View {
    @Environment(\.appTheme) private var theme
    @State private var period: Period = .month

    enum Period: String, CaseIterable { case day, week, month, year
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 18) {
                    periodPicker
                    totalCard
                    dailyChartCard
                    donutCard
                    budgetsCard
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Analytics")
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(Period.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOTAL SPENDING").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
                Text(String(format: "%.2f", MockData.totalThisMonth)).font(theme.font.heroNumeral).foregroundStyle(theme.textPrimary)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.right")
                Text("12% below last month")
            }
            .font(theme.font.caption).foregroundStyle(theme.positive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private var dailyChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending over time").font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            Chart {
                ForEach(MockData.dailyLast14) { d in
                    BarMark(
                        x: .value("Day", d.date, unit: .day),
                        y: .value("Amount", d.amount)
                    )
                    .cornerRadius(6)
                    .foregroundStyle(
                        LinearGradient(colors: [theme.accent, theme.accent.opacity(0.4)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(theme.textTertiary.opacity(0.2))
                    AxisValueLabel().foregroundStyle(theme.textTertiary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(theme.textTertiary)
                }
            }
            .frame(height: 200)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private var donutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By category").font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            HStack(alignment: .top, spacing: 18) {
                Chart {
                    ForEach(MockData.spendByCategory) { slice in
                        SectorMark(angle: .value("Amount", slice.amount),
                                   innerRadius: .ratio(0.62),
                                   angularInset: 2.0)
                        .cornerRadius(4)
                        .foregroundStyle(slice.color)
                    }
                }
                .chartLegend(.hidden)
                .frame(width: 140, height: 140)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(MockData.spendByCategory.prefix(5)) { slice in
                        HStack {
                            Circle().fill(slice.color).frame(width: 8, height: 8)
                            Text(slice.categoryName).font(theme.font.caption).foregroundStyle(theme.textSecondary)
                            Spacer()
                            Text("$\(Int(slice.amount))").font(theme.font.captionMedium).foregroundStyle(theme.textPrimary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private var budgetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget status").font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            VStack(spacing: 10) {
                ForEach(MockData.categories.filter { $0.monthlyBudget != nil }) { cat in
                    budgetRow(cat)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private func budgetRow(_ cat: Category) -> some View {
        let spent = MockData.spendByCategory.first { $0.categoryName == cat.name }?.amount ?? 0
        let budget = cat.monthlyBudget ?? 1
        let pct = min(spent / budget, 1.5)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: cat.iconSystemName).foregroundStyle(cat.color)
                Text(cat.name).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                Spacer()
                Text("$\(Int(spent)) / $\(Int(budget))").font(theme.font.caption).foregroundStyle(theme.textSecondary)
            }
            ProgressView(value: min(pct, 1.0))
                .tint(pct > 1 ? theme.negative : (pct > 0.9 ? theme.negative.opacity(0.8) : cat.color))
        }
    }
}

#Preview("Analytics — Liquid Glass") {
    NavigationStack { AnalyticsView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
