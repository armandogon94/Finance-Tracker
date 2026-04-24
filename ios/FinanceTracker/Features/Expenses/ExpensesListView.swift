//
//  ExpensesListView.swift
//  Full expense log with search, filters, grouped sections by date.
//

import SwiftUI

struct ExpensesListView: View {
    @Environment(\.appTheme) private var theme
    @Environment(ExpensesService.self) private var svc
    @Environment(CategoriesService.self) private var cats
    @State private var searchText = ""
    @State private var showFilters = false
    @State private var deleteError: String?
    @State private var deletedStamp = 0
    @State private var errorStamp = 0

    /// Only use MockData as a skeleton when we're in -skipAuth preview mode
    /// and the service hasn't tried to load yet. Never for signed-in users.
    private var useMock: Bool {
        UserDefaults.standard.bool(forKey: "FinanceTracker.skipAuth") && svc.state == .idle
    }
    private var sourceExpenses: [Expense] {
        useMock ? MockData.expenses : svc.expenses
    }
    private var sourceCategories: [Category] {
        useMock ? MockData.categories : cats.categories
    }
    private func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return sourceCategories.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                themedBackdrop
                // Use a List so SwiftUI's `.swipeActions` works. The visual
                // is kept card-ish by hiding list row separators + clearing
                // row backgrounds so our ThemedBackdrop shows through.
                List {
                    Section {
                        filterPills
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(groupedExpenses, id: \.label) { group in
                        Section {
                            ForEach(group.items) { e in
                                rowLink(for: e)
                            }
                        } header: {
                            Text(group.label.uppercased())
                                .font(theme.font.captionMedium)
                                .tracking(1.2)
                                .foregroundStyle(theme.textTertiary)
                                .padding(.leading, 4)
                        }
                    }
                    if let deleteError {
                        Text(deleteError)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.negative)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .navigationDestination(for: Expense.self) { ExpenseDetailView(initial: $0) }
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
            .sensoryFeedback(.warning, trigger: deletedStamp)
            .sensoryFeedback(.error, trigger: errorStamp)
        }
    }

    private func rowLink(for e: Expense) -> some View {
        NavigationLink(value: e) {
            ExpenseRow(expense: e, category: category(for: e.categoryId))
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowBackground(
            RoundedRectangle(cornerRadius: theme.radii.card - 4, style: .continuous)
                .fill(theme.cardBackground())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        )
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                delete(e)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func delete(_ e: Expense) {
        deleteError = nil
        Task {
            let ok = await svc.deleteExpense(id: e.id)
            if ok {
                deletedStamp += 1
            } else {
                errorStamp += 1
                deleteError = "Couldn't delete \(e.merchantName ?? e.description ?? "expense"). Try again."
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
        for e in sourceExpenses {
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

}

struct ExpenseRow: View {
    @Environment(\.appTheme) private var theme
    let expense: Expense
    let category: Category?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((category?.color ?? theme.textTertiary).opacity(0.22))
                CategoryIcon(
                    name: category?.iconSystemName,
                    color: category?.color ?? theme.textSecondary
                )
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
                Text((category?.name ?? "Uncategorized") + " · " + dayLabel)
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
        .environment(ExpensesService(api: APIClient()))
        .environment(CategoriesService(api: APIClient()))
        .preferredColorScheme(.dark)
}
