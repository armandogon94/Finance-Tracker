//
//  HomeView.swift
//  Dashboard — hero total, day/week/month cards, recent expenses.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.appTheme) private var theme
    @Environment(ExpensesService.self) private var svc
    @Environment(CategoriesService.self) private var cats
    @State private var showQuickAdd = false

    /// If the service has loaded real data (even an empty list) we render
    /// that. MockData only shows when the user is in -skipAuth mode so
    /// design-comparison screenshots aren't empty.
    private var useMock: Bool {
        UserDefaults.standard.bool(forKey: "FinanceTracker.skipAuth") && svc.state == .idle
    }
    private var displayExpenses: [Expense] {
        useMock ? MockData.expenses : svc.expenses
    }
    private var displayTotalMonth: Double {
        useMock ? MockData.totalThisMonth : svc.totalThisMonth
    }
    private var displayTotalToday: Double {
        useMock ? MockData.totalToday : svc.totalToday
    }
    private var displayTotalWeek: Double {
        useMock ? MockData.totalThisWeek : svc.totalThisWeek
    }
    private var displayCategories: [Category] {
        useMock ? MockData.categories : cats.categories
    }
    private func lookup(_ id: UUID?) -> Category? {
        guard let id else { return nil }
        return displayCategories.first { $0.id == id }
    }

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
                Text(String(format: "%.2f", displayTotalMonth))
                    .font(theme.font.heroNumeral)
                    .foregroundStyle(theme.textPrimary)
            }
            Text("$\(Int(max(0, 1500 - displayTotalMonth))) remaining of $1,500 budget")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
            ProgressView(value: min(displayTotalMonth, 1500), total: 1500)
                .tint(theme.accent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .themedCard()
    }

    // MARK: - Today / Week / Month stat row

    private var statRow: some View {
        HStack(spacing: 12) {
            statCard(label: "Today",     value: displayTotalToday,  icon: "sun.max.fill",              tint: theme.accent)
            statCard(label: "This Week", value: displayTotalWeek,   icon: "calendar",                   tint: theme.accentSecondary)
            statCard(label: "Month",     value: displayTotalMonth,  icon: "chart.line.uptrend.xyaxis",  tint: theme.positive)
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
        .themedCard(radius: theme.radii.card - 4)
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
                let rows = Array(displayExpenses.prefix(5))
                ForEach(rows) { expense in
                    HomeExpenseRow(expense: expense, category: lookup(expense.categoryId))
                    if expense.id != rows.last?.id {
                        Divider().opacity(0.2)
                    }
                }
            }
        }
        .padding(18)
        .themedCard()
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
    let category: Category?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((category?.color ?? theme.textTertiary).opacity(0.2))
                CategoryIcon(
                    name: category?.iconSystemName,
                    color: category?.color ?? theme.textSecondary
                )
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.merchantName ?? expense.description ?? "Expense")
                    .font(theme.font.bodyMedium)
                    .foregroundStyle(theme.textPrimary)
                Text((category?.name ?? "Uncategorized") + " · " + dayLabel)
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
        .environment(ExpensesService(api: APIClient()))
        .environment(CategoriesService(api: APIClient()))
        .preferredColorScheme(.dark)
}
