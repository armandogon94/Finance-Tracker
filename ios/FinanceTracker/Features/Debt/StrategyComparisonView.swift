//
//  StrategyComparisonView.swift
//  Compares payoff strategies with a what-if slider and a line chart.
//

import SwiftUI
import Charts

struct StrategyComparisonView: View {
    @Environment(\.appTheme) private var theme
    @State private var monthlyBudget: Double = 600

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 18) {
                    sliderCard
                    chartCard
                    ForEach(MockData.strategies) { strategyCard($0) }
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Strategy comparison")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var sliderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MONTHLY BUDGET").font(theme.font.captionMedium).tracking(1.2)
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Text("$\(Int(monthlyBudget))/mo")
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
            }
            Slider(value: $monthlyBudget, in: 300...2000, step: 25)
                .tint(theme.accent)
            Text("Minimum needed: $\(Int(MockData.totalMinPayment))")
                .font(theme.font.caption).foregroundStyle(theme.textSecondary)
        }
        .padding(18)
        .themedCard()
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time to zero debt").font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            Chart {
                ForEach(MockData.strategies) { s in
                    ForEach(payoffCurve(months: s.monthsToFreedom), id: \.self) { p in
                        LineMark(x: .value("Month", p.month), y: .value("Debt", p.remaining))
                            .foregroundStyle(by: .value("Strategy", s.name))
                    }
                }
            }
            .chartForegroundStyleScale([
                "Avalanche": theme.accent,
                "Snowball": theme.accentSecondary,
                "Hybrid": theme.positive,
                "Minimum only": theme.negative,
            ])
            .chartLegend(position: .bottom)
            .frame(height: 200)
        }
        .padding(18)
        .themedCard()
    }

    private struct Pt: Hashable { let month: Int; let remaining: Double }

    private func payoffCurve(months: Int) -> [Pt] {
        let total = MockData.totalDebt
        return (0...months).map { m in
            // Simple exponential decay approximation for visualization
            let frac = Double(m) / Double(months)
            let remaining = total * (1 - pow(frac, 1.4))
            return Pt(month: m, remaining: max(0, remaining))
        }
    }

    private func strategyCard(_ s: PayoffStrategy) -> some View {
        let isBest = s.name == "Avalanche"
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(colorFor(s.name)).frame(width: 10, height: 10)
                    Text(s.name).font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
                }
                Spacer()
                if isBest {
                    Text("RECOMMENDED").font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(theme.positive.opacity(0.22)))
                        .foregroundStyle(theme.positive)
                }
            }
            HStack {
                statTile(label: "Months", value: "\(s.monthsToFreedom)")
                statTile(label: "Interest", value: "$\(Int(s.totalInterest))")
                statTile(label: "Total paid", value: "$\(Int(s.totalPaid))")
            }
            Text("Order: " + s.payoffOrder.joined(separator: " → "))
                .font(theme.font.caption).foregroundStyle(theme.textSecondary)
        }
        .padding(18)
        .themedCard()
    }

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "Avalanche": theme.accent
        case "Snowball": theme.accentSecondary
        case "Hybrid": theme.positive
        default: theme.negative
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(theme.font.caption).foregroundStyle(theme.textSecondary)
            Text(value).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surfaceSecondary)
        )
    }
}

#Preview("Strategies — Liquid Glass") {
    NavigationStack { StrategyComparisonView() }
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
