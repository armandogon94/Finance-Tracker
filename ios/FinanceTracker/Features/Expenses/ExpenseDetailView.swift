//
//  ExpenseDetailView.swift
//  Read + edit a single expense. Skeleton shows the layout; the edit
//  sheet and delete action are visual only.
//

import SwiftUI

struct ExpenseDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(ExpensesService.self) private var svc
    let expense: Expense
    @State private var isEditing = false

    private var lookupCategory: Category? {
        let pool = svc.categories.isEmpty ? MockData.categories : svc.categories
        return pool.first { $0.id == expense.categoryId }
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    fieldCard
                    if expense.hasReceipt { receiptCard }
                    actionCard
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing.toggle() }
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private var heroCard: some View {
        VStack(spacing: 8) {
            let cat = lookupCategory
            if let cat {
                HStack(spacing: 6) {
                    Image(systemName: cat.iconSystemName)
                    Text(cat.name)
                }
                .font(theme.font.captionMedium)
                .foregroundStyle(cat.color)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(cat.color.opacity(0.18)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
                Text(String(format: "%.2f", expense.amount))
                    .font(theme.font.heroNumeral)
                    .foregroundStyle(theme.textPrimary)
            }
            Text(expense.merchantName ?? expense.description ?? "Expense")
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .themedCard()
    }

    private var fieldCard: some View {
        VStack(spacing: 0) {
            fieldRow("Date", value: dateLabel)
            Divider().opacity(0.15).padding(.horizontal, 16)
            fieldRow("Description", value: expense.description ?? "—")
            Divider().opacity(0.15).padding(.horizontal, 16)
            fieldRow("Merchant", value: expense.merchantName ?? "—")
            Divider().opacity(0.15).padding(.horizontal, 16)
            fieldRow("Payment", value: "Credit card")
        }
        .themedCard()
    }

    private func fieldRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.textSecondary)
            Spacer()
            Text(value).foregroundStyle(theme.textPrimary)
        }
        .font(theme.font.body)
        .padding(16)
    }

    private var receiptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.viewfinder")
                    .foregroundStyle(theme.accent)
                Text("Receipt").font(theme.font.titleCompact)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("Claude")
                    .font(theme.font.captionMedium)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(theme.accent.opacity(0.22)))
                    .foregroundStyle(theme.accent)
            }
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.surfaceSecondary)
                .frame(height: 180)
                .overlay(
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(theme.textTertiary)
                )
        }
        .padding(18)
        .themedCard()
    }

    private var actionCard: some View {
        HStack(spacing: 12) {
            Button(action: {}) {
                Label("Duplicate", systemImage: "doc.on.doc")
                    .font(theme.font.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                            .fill(theme.surface)
                    )
                    .foregroundStyle(theme.textPrimary)
            }
            Button(role: .destructive, action: {}) {
                Label("Delete", systemImage: "trash")
                    .font(theme.font.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                            .fill(theme.negative.opacity(0.18))
                    )
                    .foregroundStyle(theme.negative)
            }
        }
    }

    private var dateLabel: String {
        let f = DateFormatter(); f.dateStyle = .medium
        return f.string(from: expense.expenseDate)
    }
}

#Preview("ExpenseDetail — Liquid Glass") {
    NavigationStack {
        ExpenseDetailView(expense: MockData.expenses[0])
    }
    .environment(\.appTheme, LiquidGlassTheme())
    .environment(ExpensesService(api: APIClient()))
    .preferredColorScheme(.dark)
}
