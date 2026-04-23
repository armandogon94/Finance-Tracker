//
//  QuickAddSheet.swift
//  Sub-10-second expense entry: amount keypad + optional note + category
//  chip picker. On save, POSTs to /api/v1/expenses via ExpensesService;
//  the service optimistically inserts the new row at position 0 so
//  HomeView and ExpensesListView update without an extra round trip.
//

import SwiftUI

struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(ExpensesService.self) private var svc

    @State private var amount: String = "0"
    @State private var note: String = ""
    @State private var selectedCategory: Category?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedSignal = 0      // drives sensory feedback

    private var categories: [Category] {
        svc.categories.isEmpty ? MockData.categories : svc.categories
    }

    private var parsedAmount: Double? { Double(amount) }

    private var canSave: Bool {
        !isSaving && (parsedAmount ?? 0) > 0 && selectedCategory != nil
    }

    var body: some View {
        ZStack {
            if theme.id == .liquidGlass {
                Color.clear
            } else {
                theme.background.ignoresSafeArea()
            }
            VStack(spacing: 14) {
                grabber
                header

                amountDisplay
                noteField
                categoryPicker

                if let saveError {
                    Text(saveError)
                        .font(theme.font.caption)
                        .foregroundStyle(theme.negative)
                        .multilineTextAlignment(.center)
                }

                keypad
                saveButton
            }
            .padding(20)
        }
        .onAppear {
            if selectedCategory == nil {
                selectedCategory = categories.first
            }
        }
        .sensoryFeedback(.success, trigger: savedSignal)
    }

    // MARK: - UI pieces

    private var grabber: some View {
        Capsule().fill(theme.textTertiary.opacity(0.4))
            .frame(width: 36, height: 4)
            .padding(.top, 6)
    }

    private var header: some View {
        HStack {
            Text("Quick Add")
                .font(theme.font.title)
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button(role: .cancel) { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
            Text(amount).font(theme.font.heroNumeral).foregroundStyle(theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var noteField: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(theme.textTertiary)
            TextField("Note (optional)", text: $note)
                .font(theme.font.body)
                .foregroundStyle(theme.textPrimary)
                .autocorrectionDisabled(false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                .fill(theme.surface)
        )
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { cat in
                    let active = selectedCategory?.id == cat.id
                    Button { selectedCategory = cat } label: {
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

    private var keypad: some View {
        let rows = [["1","2","3"], ["4","5","6"], ["7","8","9"], [".","0","⌫"]]
        return VStack(spacing: 10) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 10) {
                    ForEach(row, id: \.self) { key in
                        Button { tap(key) } label: {
                            Text(key)
                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                                        .fill(theme.surface)
                                )
                                .foregroundStyle(theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: 6) {
                if isSaving {
                    ProgressView().tint(.black).padding(.trailing, 2)
                }
                Text(isSaving ? "Saving…" : "Save expense")
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

    // MARK: - Actions

    private func tap(_ key: String) {
        saveError = nil
        if key == "⌫" {
            amount = String(amount.dropLast())
            if amount.isEmpty { amount = "0" }
        } else if key == "." {
            if !amount.contains(".") { amount += "." }
        } else {
            if amount == "0" { amount = key } else { amount += key }
        }
    }

    private func save() {
        guard let amt = parsedAmount, amt > 0 else { return }
        isSaving = true
        saveError = nil
        Task {
            let ok = await svc.addExpense(
                amount: amt,
                description: note.isEmpty ? nil : note,
                merchantName: nil,
                categoryId: selectedCategory?.id,
                date: Date()
            )
            isSaving = false
            if ok {
                savedSignal += 1
                // Tiny delay so the success haptic fires before the sheet slides away
                try? await Task.sleep(for: .milliseconds(120))
                dismiss()
            } else {
                saveError = "Couldn't save. Check your connection and try again."
            }
        }
    }
}

#Preview("QuickAdd — Liquid Glass") {
    QuickAddSheet()
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(ExpensesService(api: APIClient()))
        .preferredColorScheme(.dark)
}
