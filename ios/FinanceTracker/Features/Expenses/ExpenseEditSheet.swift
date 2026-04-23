//
//  ExpenseEditSheet.swift
//  Pre-fills from the passed Expense; on Save diffs against the original
//  so the PATCH body only contains the fields the user actually changed.
//  ExpensesService handles in-place replacement on success + error on
//  failure, so callers just present and dismiss.
//

import SwiftUI

struct ExpenseEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(ExpensesService.self) private var svc

    let original: Expense

    @State private var amountText: String = ""
    @State private var description: String = ""
    @State private var merchant: String = ""
    @State private var categoryId: UUID?
    @State private var expenseDate: Date = Date()
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedStamp = 0
    @State private var errorStamp = 0

    private var categories: [Category] {
        svc.categories.isEmpty ? MockData.categories : svc.categories
    }
    private var parsedAmount: Double? { Double(amountText.replacingOccurrences(of: ",", with: ".")) }
    private var canSave: Bool { !isSaving && (parsedAmount ?? 0) > 0 }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 16) {
                    grabber
                    header

                    amountCard
                    detailsCard
                    categoryCard
                    dateCard

                    if let saveError {
                        Text(saveError)
                            .font(theme.font.caption)
                            .foregroundStyle(theme.negative)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    saveButton
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)
        }
        .onAppear(perform: prefill)
        .sensoryFeedback(.success, trigger: savedStamp)
        .sensoryFeedback(.error, trigger: errorStamp)
    }

    // MARK: - Layout

    private var grabber: some View {
        Capsule().fill(theme.textTertiary.opacity(0.4))
            .frame(width: 36, height: 4)
    }

    private var header: some View {
        HStack {
            Text("Edit expense")
                .font(theme.font.title)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button(role: .cancel) { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AMOUNT")
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(theme.font.heroNumeral)
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .padding(18)
        .themedCard()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DETAILS")
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            labeledField(icon: "text.bubble", placeholder: "Description", text: $description)
            labeledField(icon: "building.2", placeholder: "Merchant", text: $merchant)
        }
        .padding(18)
        .themedCard()
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CATEGORY")
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    clearChip
                    ForEach(categories) { cat in
                        let active = categoryId == cat.id
                        Button { categoryId = cat.id } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.iconSystemName)
                                Text(cat.name)
                            }
                            .font(theme.font.captionMedium)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(active ? cat.color.opacity(0.3) : theme.surface))
                            .foregroundStyle(active ? cat.color : theme.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .themedCard()
    }

    private var clearChip: some View {
        let active = categoryId == nil
        return Button { categoryId = nil } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                Text("Uncategorized")
            }
            .font(theme.font.captionMedium)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(active ? theme.accent.opacity(0.3) : theme.surface))
            .foregroundStyle(active ? theme.accent : theme.textSecondary)
        }
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DATE")
                .font(theme.font.captionMedium).tracking(1.2)
                .foregroundStyle(theme.textTertiary)
            DatePicker("",
                       selection: $expenseDate,
                       in: ...Date(),
                       displayedComponents: .date)
                .labelsHidden()
                .tint(theme.accent)
        }
        .padding(18)
        .themedCard()
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView().tint(.black).padding(.trailing, 2)
                }
                Text(isSaving ? "Saving…" : "Save changes")
                    .font(theme.font.titleCompact)
                    .foregroundStyle(Color.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                    .fill(canSave ? theme.accent : theme.accent.opacity(0.4))
            )
        }
        .disabled(!canSave)
    }

    private func labeledField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(theme.textTertiary)
                .frame(width: 20)
            TextField(placeholder, text: text)
                .font(theme.font.body)
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                .fill(theme.surface)
        )
    }

    // MARK: - Actions

    private func prefill() {
        amountText = String(format: "%.2f", original.amount)
        description = original.description ?? ""
        merchant = original.merchantName ?? ""
        categoryId = original.categoryId
        expenseDate = original.expenseDate
    }

    private func save() {
        guard let amt = parsedAmount, amt > 0 else { return }
        isSaving = true
        saveError = nil
        Task {
            let patch = diffPatch(newAmount: amt)
            let ok = await svc.updateExpense(id: original.id, patch: patch)
            isSaving = false
            if ok {
                savedStamp += 1
                try? await Task.sleep(for: .milliseconds(120))
                dismiss()
            } else {
                errorStamp += 1
                saveError = "Couldn't save. Check your connection and try again."
            }
        }
    }

    /// Only include fields that differ from the original. Keeps the PATCH
    /// body tight and makes intent clear in network logs.
    private func diffPatch(newAmount: Double) -> UpdateExpenseDTO {
        let origDescription = original.description ?? ""
        let origMerchant = original.merchantName ?? ""
        let newDescription = description.trimmingCharacters(in: .whitespaces)
        let newMerchant = merchant.trimmingCharacters(in: .whitespaces)

        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .iso8601)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let newDateStr = dateFormatter.string(from: expenseDate)
        let origDateStr = dateFormatter.string(from: original.expenseDate)

        return UpdateExpenseDTO(
            amount: newAmount == original.amount ? nil : newAmount,
            categoryId: categoryId == original.categoryId ? nil : categoryId,
            description: newDescription == origDescription ? nil : (newDescription.isEmpty ? nil : newDescription),
            merchantName: newMerchant == origMerchant ? nil : (newMerchant.isEmpty ? nil : newMerchant),
            expenseDate: newDateStr == origDateStr ? nil : newDateStr
        )
    }
}

#Preview("Edit — Liquid Glass") {
    ExpenseEditSheet(original: MockData.expenses[0])
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(ExpensesService(api: APIClient()))
        .preferredColorScheme(.dark)
}
