//
//  HomeView.swift
//  Dashboard — hero total, day/week/month cards, recent expenses.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.appTheme) private var theme
    @State private var showQuickAdd = false

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()
                ScrollView {
                    VStack(spacing: 18) {
                        hero
                        statRow
                        recentExpensesCard
                        Spacer(minLength: 80)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                }
                .scrollContentBackground(.hidden)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        quickAddButton
                            .padding(.trailing, 20)
                            .padding(.bottom, 12)
                    }
                }
            }
            .navigationTitle("Hi, \(MockData.user.name.components(separatedBy: " ").first ?? "")")
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showQuickAdd) {
                QuickAddSheet()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(theme.id == .liquidGlass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(theme.background))
            }
        }
    }

    // MARK: - Hero total this month

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SPENT THIS MONTH")
                .font(theme.font.captionMedium)
                .tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$")
                    .font(theme.font.title)
                    .foregroundStyle(theme.textSecondary)
                Text(String(format: "%.2f", MockData.totalThisMonth))
                    .font(theme.font.heroNumeral)
                    .foregroundStyle(theme.textPrimary)
            }
            Text("$600 remaining of $1,500 budget")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
            ProgressView(value: min(MockData.totalThisMonth, 1500), total: 1500)
                .tint(theme.accent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .fill(theme.cardBackground())
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.radii.card, style: .continuous)
                .strokeBorder(Color.white.opacity(theme.id == .liquidGlass ? 0.14 : 0.0), lineWidth: 1)
        )
        .shadow(color: .black.opacity(theme.id == .liquidGlass ? 0.35 : 0.05), radius: 18, y: 10)
    }

    // MARK: - Today / Week / Month stat row

    private var statRow: some View {
        HStack(spacing: 12) {
            statCard(label: "Today",     value: MockData.totalToday,      icon: "sun.max.fill",      tint: theme.accent)
            statCard(label: "This Week", value: MockData.totalThisWeek,   icon: "calendar",          tint: theme.accentSecondary)
            statCard(label: "Month",     value: MockData.totalThisMonth,  icon: "chart.line.uptrend.xyaxis", tint: theme.positive)
        }
    }

    private func statCard(label: String, value: Double, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.18), in: Circle())
            Text(label)
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
            Text("$\(Int(value))")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.card - 4, style: .continuous)
                .fill(theme.cardBackground())
        )
    }

    // MARK: - Recent expenses

    private var recentExpensesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent expenses")
                    .font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                NavigationLink("See all") { ExpensesListView() }
                    .font(theme.font.caption)
                    .foregroundStyle(theme.accent)
            }
            VStack(spacing: 10) {
                ForEach(MockData.expenses.prefix(5)) { expense in
                    HomeExpenseRow(expense: expense)
                    if expense.id != MockData.expenses.prefix(5).last?.id {
                        Divider().opacity(0.2)
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

    private var quickAddButton: some View {
        Button(action: { showQuickAdd = true }) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.black)
                .frame(width: 60, height: 60)
                .background(Circle().fill(theme.accent))
                .shadow(color: theme.accent.opacity(0.55), radius: 18, y: 8)
        }
    }
}

private struct HomeExpenseRow: View {
    @Environment(\.appTheme) private var theme
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            let cat = MockData.categories.first { $0.id == expense.categoryId }
            ZStack {
                Circle().fill((cat?.color ?? theme.textTertiary).opacity(0.2))
                Image(systemName: cat?.iconSystemName ?? "questionmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(cat?.color ?? theme.textSecondary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchantName ?? expense.description ?? "Expense")
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                Text((cat?.name ?? "Uncategorized") + " · " + dayLabel)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Text("$" + String(format: "%.2f", expense.amount))
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
        }
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: expense.expenseDate)
    }
}

#Preview("Home — Liquid Glass") {
    HomeView()
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
