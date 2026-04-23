//
//  ExpenseDetailView.swift
//  Single-expense surface. Takes a "stale" Expense for the nav transition
//  (so the view has something to render the instant it pushes), then
//  always prefers the live version from ExpensesService for subsequent
//  renders. That way after an Edit saves, the detail reflects the new
//  values immediately without a reload.
//

import SwiftUI

struct ExpenseDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(ExpensesService.self) private var svc
    @Environment(\.dismiss) private var dismiss

    let initial: Expense

    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var actionError: String?
    @State private var deletedStamp = 0
    @State private var errorStamp = 0

    /// Always prefer the live row from the service; fall back to the
    /// stale copy only for the instant between push and first render.
    private var expense: Expense {
        svc.expenses.first(where: { $0.id == initial.id }) ?? initial
    }

    private var category: Category? {
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
                    if let actionError {
                        Text(actionError)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.negative)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
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
                Button("Edit") { showEditSheet = true }
                    .foregroundStyle(theme.accent)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            ExpenseEditSheet(original: expense)
                .presentationDetents([.large])
                .presentationBackground(theme.id == .liquidGlass
                                        ? AnyShapeStyle(.ultraThinMaterial)
                                        : AnyShapeStyle(theme.background))
        }
        .alert("Delete this expense?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: performDelete)
        } message: {
            Text("This removes it from your history and updates your monthly total. This can't be undone.")
        }
        .sensoryFeedback(.warning, trigger: deletedStamp)
        .sensoryFeedback(.error, trigger: errorStamp)
    }

    // MARK: - Cards

    private var heroCard: some View {
        VStack(spacing: 8) {
            if let cat = category {
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
            fieldRow("Currency", value: expense.currency)
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
                if let m = expense.ocrMethod {
                    Text(m.capitalized)
                        .font(theme.font.captionMedium)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(theme.accent.opacity(0.22)))
                        .foregroundStyle(theme.accent)
                }
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
            Button {
                showEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
                    .font(theme.font.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                            .fill(theme.surface)
                    )
                    .foregroundStyle(theme.textPrimary)
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 6) {
                    if isDeleting {
                        ProgressView().tint(theme.negative)
                    } else {
                        Image(systemName: "trash")
                    }
                    Text(isDeleting ? "Deleting…" : "Delete")
                }
                .font(theme.font.bodyMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                        .fill(theme.negative.opacity(0.18))
                )
                .foregroundStyle(theme.negative)
            }
            .disabled(isDeleting)
        }
    }

    // MARK: - Actions

    private func performDelete() {
        isDeleting = true
        actionError = nil
        Task {
            let ok = await svc.deleteExpense(id: expense.id)
            isDeleting = false
            if ok {
                deletedStamp += 1
                try? await Task.sleep(for: .milliseconds(140))
                dismiss()
            } else {
                errorStamp += 1
                actionError = "Couldn't delete. Check your connection and try again."
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
        ExpenseDetailView(initial: MockData.expenses[0])
    }
    .environment(\.appTheme, LiquidGlassTheme())
    .environment(ExpensesService(api: APIClient()))
    .preferredColorScheme(.dark)
}
