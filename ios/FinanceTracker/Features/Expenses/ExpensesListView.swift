//
//  ExpensesListView.swift
//  Full expense log with search, filters, grouped sections by date.
//

import SwiftUI

struct ExpensesListView: View {
    @Environment(\.appTheme) private var theme
    @State private var searchText = ""
    @State private var showFilters = false

    var body: some View {
        NavigationStack {
            ZStack {
                themedBackdrop
                ScrollView {
                    VStack(spacing: 16) {
                        filterPills
                        ForEach(groupedExpenses, id: \.label) { group in
                            sectionCard(group: group)
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Expenses")
            .searchable(text: $searchText, prompt: "Search merchant, category…")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters.toggle() } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder private var themedBackdrop: some View {
        ThemedBackdrop()
    }

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["All", "This Week", "Food & Dining", "Bills", "Shopping"], id: \.self) { label in
                    Text(label)
                        .font(theme.font.captionMedium)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(label == "All" ? theme.accent.opacity(0.25) : theme.surface)
                        )
                        .foregroundStyle(label == "All" ? theme.accent : theme.textSecondary)
                }
            }
        }
    }

    private var groupedExpenses: [(label: String, items: [Expense])] {
        let cal = Calendar.current
        var buckets: [(String, [Expense])] = []
        var byKey: [String: [Expense]] = [:]
        let today = Date()
        for e in MockData.expenses {
            let label: String
            if cal.isDateInToday(e.expenseDate) { label = "Today" }
            else if cal.isDateInYesterday(e.expenseDate) { label = "Yesterday" }
            else if cal.isDate(e.expenseDate, equalTo: today, toGranularity: .weekOfYear) { label = "This Week" }
            else { label = "Earlier" }
            byKey[label, default: []].append(e)
        }
        for key in ["Today", "Yesterday", "This Week", "Earlier"] {
            if let items = byKey[key], !items.isEmpty {
                buckets.append((key, items))
            }
        }
        return buckets
    }

    private func sectionCard(group: (label: String, items: [Expense])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.label.uppercased())
                .font(theme.font.captionMedium)
                .tracking(1.2)
                .foregroundStyle(theme.textTertiary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(group.items) { e in
                    NavigationLink(value: e) {
                        ExpenseRow(expense: e)
                    }
                    .buttonStyle(.plain)
                    if e.id != group.items.last?.id {
                        Divider().opacity(0.15)
                    }
                }
            }
            .padding(4)
            .themedCard()
        }
        .navigationDestination(for: Expense.self) { ExpenseDetailView(expense: $0) }
    }
}

struct ExpenseRow: View {
    @Environment(\.appTheme) private var theme
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            let cat = MockData.categories.first { $0.id == expense.categoryId }
            ZStack {
                Circle().fill((cat?.color ?? theme.textTertiary).opacity(0.22))
                Image(systemName: cat?.iconSystemName ?? "questionmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(cat?.color ?? theme.textSecondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(expense.merchantName ?? expense.description ?? "Expense")
                        .font(theme.font.bodyMedium)
                        .foregroundStyle(theme.textPrimary)
                    if expense.hasReceipt {
                        Image(systemName: "doc.text.viewfinder")
                            .font(.caption)
                            .foregroundStyle(theme.accent)
                    }
                }
                Text((cat?.name ?? "Uncategorized") + " · " + dayLabel)
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Text("$" + String(format: "%.2f", expense.amount))
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
        }
        .padding(12)
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: expense.expenseDate)
    }
}

#Preview("Expenses — Liquid Glass") {
    ExpensesListView()
        .environment(\.appTheme, LiquidGlassTheme())
        .preferredColorScheme(.dark)
}
