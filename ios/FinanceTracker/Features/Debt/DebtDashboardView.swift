//
//  DebtDashboardView.swift
//  Total debt + minimums, CC and loan cards, link into the strategy
//  comparison. Uses Swift Charts for the small donut preview.
//

import SwiftUI
import Charts

struct DebtDashboardView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()
                ScrollView {
                    VStack(spacing: 18) {
                        summaryCard
                        cardsSection
                        loansSection
                        strategyLink
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Debt")
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TOTAL DEBT")
                    .font(theme.font.captionMedium).tracking(1.2)
                    .foregroundStyle(theme.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
                    Text(String(format: "%.0f", MockData.totalDebt))
                        .font(theme.font.heroNumeral)
                        .foregroundStyle(theme.textPrimary)
                }
                Text("Minimum: $\(Int(MockData.totalMinPayment))/mo")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            debtDonut
                .frame(width: 96, height: 96)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private var debtDonut: some View {
        let slices: [(String, Double, Color)] = [
            ("Credit cards", MockData.creditCards.reduce(0) { $0 + $1.currentBalance }, theme.accent),
            ("Loans",        MockData.loans.reduce(0) { $0 + $1.currentBalance },        theme.accentSecondary),
        ]
        return Chart {
            ForEach(slices, id: \.0) { slice in
                SectorMark(
                    angle: .value("amount", slice.1),
                    innerRadius: .ratio(0.66),
                    angularInset: 2.5
                )
                .cornerRadius(4)
                .foregroundStyle(slice.2)
            }
        }
        .chartLegend(.hidden)
    }

    // MARK: - Credit cards

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "creditcard.fill")
                Text("Credit cards").font(theme.font.titleCompact)
                Spacer()
                Text("\(MockData.creditCards.count)").font(theme.font.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(theme.surface))
            }
            .foregroundStyle(theme.textPrimary)

            VStack(spacing: 10) {
                ForEach(MockData.creditCards) { cc in ccRow(cc) }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private func ccRow(_ cc: CreditCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cc.cardName).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                    Text("•••• \(cc.lastFour ?? "0000")").font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(Int(cc.currentBalance))").font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                    Text(String(format: "%.2f%% APR", cc.aprPercent)).font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
            }
            ProgressView(value: cc.utilization, total: 1.0)
                .tint(cc.utilization > 0.5 ? theme.negative : theme.positive)
            HStack {
                Text(String(format: "%.0f%% utilization", cc.utilization * 100))
                    .font(theme.font.caption).foregroundStyle(theme.textSecondary)
                Spacer()
                Text("Limit $\(Int(cc.creditLimit ?? 0))").font(theme.font.caption).foregroundStyle(theme.textTertiary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card - 8, style: .continuous)
                .fill(theme.surfaceSecondary)
        )
    }

    // MARK: - Loans

    private var loansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "building.columns.fill")
                Text("Loans").font(theme.font.titleCompact)
                Spacer()
                Text("\(MockData.loans.count)").font(theme.font.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(theme.surface))
            }
            .foregroundStyle(theme.textPrimary)

            VStack(spacing: 10) {
                ForEach(MockData.loans) { loan in loanRow(loan) }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    private func loanRow(_ loan: Loan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loan.loanName).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                    Text(loan.lender ?? loan.loanType.capitalized).font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(Int(loan.currentBalance))").font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                    Text(String(format: "%.1f%% rate", loan.interestRatePercent)).font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
            }
            ProgressView(value: max(0, min(loan.progressPercent / 100, 1)))
                .tint(theme.positive)
            Text(String(format: "%.1f%% paid off", loan.progressPercent))
                .font(theme.font.caption).foregroundStyle(theme.textSecondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card - 8, style: .continuous)
                .fill(theme.surfaceSecondary)
        )
    }

    // MARK: - Strategy link

    private var strategyLink: some View {
        NavigationLink { StrategyComparisonView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.accent.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Payoff strategy comparison")
                        .font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                    Text("Avalanche vs Snowball vs Hybrid — see the math")
                        .font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(theme.textTertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                    .fill(theme.cardBackground())
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview("Debt — Liquid Glass") {
    DebtDashboardView()
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
