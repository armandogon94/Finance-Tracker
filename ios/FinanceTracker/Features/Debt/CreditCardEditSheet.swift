//
//  CreditCardEditSheet.swift
//  Slice 8 — create/edit a credit card. Modeled after CategoryEditSheet:
//  Mode enum drives create vs edit, diff-based PATCH on save so PATCH
//  bodies only carry fields the user changed.
//

import SwiftUI

struct CreditCardEditSheet: View {
    enum Mode {
        case create
        case edit(CreditCardDTO)

        var isEdit: Bool { if case .edit = self { return true } else { return false } }
        var title: String { isEdit ? "Edit credit card" : "New credit card" }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(DebtService.self) private var debt

    let mode: Mode

    @State private var cardName = ""
    @State private var lastFour = ""
    @State private var balanceText = ""
    @State private var limitText = ""
    @State private var aprText = ""
    @State private var minPaymentText = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedStamp = 0
    @State private var errorStamp = 0

    private var parsedBalance: Double? { Double(balanceText.replacingOccurrences(of: ",", with: ".")) }
    private var parsedLimit: Double? { Double(limitText.replacingOccurrences(of: ",", with: ".")) }
    private var parsedApr: Double? { Double(aprText.replacingOccurrences(of: ",", with: ".")) }
    private var parsedMin: Double? { Double(minPaymentText.replacingOccurrences(of: ",", with: ".")) }

    private var canSave: Bool {
        !isSaving
            && !cardName.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedApr != nil
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 16) {
                    grabber
                    header
                    nameCard
                    balanceCard
                    aprCard
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

    private var grabber: some View {
        Capsule().fill(theme.textTertiary.opacity(0.4)).frame(width: 36, height: 4)
    }

    private var header: some View {
        HStack {
            Text(mode.title).font(theme.font.title).foregroundStyle(theme.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.top, 4)
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CARD").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            TextField("Card name (e.g. Amex Gold)", text: $cardName)
                .font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                .textInputAutocapitalization(.words)
            HStack(spacing: 6) {
                Text("•••• ").foregroundStyle(theme.textSecondary)
                TextField("Last 4", text: $lastFour)
                    .keyboardType(.numberPad)
                    .font(theme.font.body)
                    .foregroundStyle(theme.textPrimary)
                    .frame(width: 80)
            }
        }
        .padding(18)
        .themedCard()
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BALANCE").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            labeledMoneyField(label: "Current balance", text: $balanceText)
            labeledMoneyField(label: "Credit limit", text: $limitText)
            labeledMoneyField(label: "Min payment", text: $minPaymentText)
        }
        .padding(18)
        .themedCard()
    }

    private var aprCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("APR").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("18.0", text: $aprText)
                    .keyboardType(.decimalPad)
                    .font(theme.font.heroNumeral)
                    .foregroundStyle(theme.textPrimary)
                Text("%").font(theme.font.title).foregroundStyle(theme.textSecondary)
            }
            Text("Enter as a percent (e.g. 18 for 18% APR).")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .padding(18)
        .themedCard()
    }

    private func labeledMoneyField(label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(theme.textSecondary).font(theme.font.body)
            Spacer()
            Text("$").foregroundStyle(theme.textSecondary)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(theme.font.bodyMedium)
                .foregroundStyle(theme.textPrimary)
                .frame(width: 100)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous).fill(theme.surface))
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: 6) {
                if isSaving { ProgressView().tint(.black).padding(.trailing, 2) }
                Text(isSaving ? "Saving…" : (mode.isEdit ? "Save changes" : "Add credit card"))
                    .font(theme.font.titleCompact)
                    .foregroundStyle(Color.black)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                .fill(canSave ? theme.accent : theme.accent.opacity(0.4)))
        }
        .disabled(!canSave)
    }

    // MARK: - Actions

    private func prefill() {
        if case let .edit(c) = mode {
            cardName = c.cardName
            lastFour = c.lastFour ?? ""
            balanceText = String(format: "%.2f", c.currentBalance)
            limitText = c.creditLimit.map { String(format: "%.2f", $0) } ?? ""
            // Backend stores APR as decimal; show as percent.
            aprText = String(format: "%.2f", c.apr * 100)
            minPaymentText = c.minimumPayment.map { String(format: "%.2f", $0) } ?? ""
        }
    }

    private func save() {
        guard let aprPercent = parsedApr else { return }
        let aprDecimal = aprPercent / 100.0
        let trimmedName = cardName.trimmingCharacters(in: .whitespaces)
        let trimmedFour = lastFour.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        saveError = nil
        Task {
            let ok: Bool
            switch mode {
            case .create:
                let body = CreateCreditCardDTO(
                    cardName: trimmedName,
                    lastFour: trimmedFour.isEmpty ? nil : trimmedFour,
                    currentBalance: parsedBalance ?? 0,
                    creditLimit: parsedLimit,
                    apr: aprDecimal,
                    minimumPayment: parsedMin,
                    statementDay: nil,
                    dueDay: nil
                )
                ok = (await debt.addCreditCard(body)) != nil
            case .edit(let original):
                let patch = diff(original: original, name: trimmedName, lastFour: trimmedFour, aprDecimal: aprDecimal)
                ok = await debt.updateCreditCard(id: original.id, patch: patch)
            }
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

    private func diff(original: CreditCardDTO, name: String, lastFour: String, aprDecimal: Double) -> UpdateCreditCardDTO {
        let nameChanged = name != original.cardName
        let balChanged = parsedBalance != nil && parsedBalance != original.currentBalance
        let limChanged = parsedLimit != original.creditLimit
        let aprChanged = abs(aprDecimal - original.apr) > 0.0001
        let minChanged = parsedMin != original.minimumPayment
        return UpdateCreditCardDTO(
            cardName: nameChanged ? name : nil,
            currentBalance: balChanged ? parsedBalance : nil,
            creditLimit: limChanged ? parsedLimit : nil,
            apr: aprChanged ? aprDecimal : nil,
            minimumPayment: minChanged ? parsedMin : nil,
            statementDay: nil,
            dueDay: nil
        )
    }
}

