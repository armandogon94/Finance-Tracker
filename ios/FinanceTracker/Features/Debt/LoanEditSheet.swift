//
//  LoanEditSheet.swift
//  Slice 8 — create/edit a loan. Same shape as CreditCardEditSheet but
//  with loan-specific fields (lender, type, original principal, rate).
//

import SwiftUI

struct LoanEditSheet: View {
    enum Mode {
        case create
        case edit(LoanDTO)

        var isEdit: Bool { if case .edit = self { return true } else { return false } }
        var title: String { isEdit ? "Edit loan" : "New loan" }
    }

    static let loanTypes = [
        ("car", "Car loan"),
        ("student", "Student loan"),
        ("mortgage", "Mortgage"),
        ("personal", "Personal loan"),
        ("medical", "Medical"),
        ("other", "Other")
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(DebtService.self) private var debt

    let mode: Mode

    @State private var loanName = ""
    @State private var lender = ""
    @State private var loanType = "car"
    @State private var originalText = ""
    @State private var balanceText = ""
    @State private var rateText = ""
    @State private var minPaymentText = ""
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var savedStamp = 0
    @State private var errorStamp = 0

    private var parsedOriginal: Double? { Double(originalText.replacingOccurrences(of: ",", with: ".")) }
    private var parsedBalance: Double? { Double(balanceText.replacingOccurrences(of: ",", with: ".")) }
    private var parsedRate: Double? { Double(rateText.replacingOccurrences(of: ",", with: ".")) }
    private var parsedMin: Double? { Double(minPaymentText.replacingOccurrences(of: ",", with: ".")) }

    private var canSave: Bool {
        !isSaving
            && !loanName.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedRate != nil
            && (mode.isEdit || (parsedOriginal != nil && parsedBalance != nil))
    }

    var body: some View {
        ZStack {
            ThemedBackdrop()
            ScrollView {
                VStack(spacing: 16) {
                    grabber
                    header
                    nameCard
                    typeCard
                    balancesCard
                    rateCard
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
            Text("LOAN").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            TextField("Loan name (e.g. Car Loan)", text: $loanName)
                .font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                .textInputAutocapitalization(.words)
            TextField("Lender (optional, e.g. Wells Fargo)", text: $lender)
                .font(theme.font.body)
                .foregroundStyle(theme.textPrimary)
                .textInputAutocapitalization(.words)
        }
        .padding(18)
        .themedCard()
    }

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TYPE").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.loanTypes, id: \.0) { item in
                        let active = loanType == item.0
                        Button { loanType = item.0 } label: {
                            Text(item.1)
                                .font(theme.font.captionMedium)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(active ? theme.accent.opacity(0.3) : theme.surface))
                                .foregroundStyle(active ? theme.accent : theme.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .themedCard()
    }

    private var balancesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BALANCES").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            labeledMoneyField(label: "Original principal", text: $originalText)
            labeledMoneyField(label: "Current balance", text: $balanceText)
            labeledMoneyField(label: "Min payment", text: $minPaymentText)
        }
        .padding(18)
        .themedCard()
    }

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INTEREST RATE").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("5.5", text: $rateText)
                    .keyboardType(.decimalPad)
                    .font(theme.font.heroNumeral)
                    .foregroundStyle(theme.textPrimary)
                Text("% / yr").font(theme.font.title).foregroundStyle(theme.textSecondary)
            }
            Text("Enter as a percent (e.g. 5.5 for 5.5% yearly).")
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
                .frame(width: 110)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous).fill(theme.surface))
    }

    private var saveButton: some View {
        Button(action: save) {
            HStack(spacing: 6) {
                if isSaving { ProgressView().tint(.black).padding(.trailing, 2) }
                Text(isSaving ? "Saving…" : (mode.isEdit ? "Save changes" : "Add loan"))
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
        if case let .edit(l) = mode {
            loanName = l.loanName
            lender = l.lender ?? ""
            loanType = l.loanType
            originalText = String(format: "%.2f", l.originalPrincipal)
            balanceText = String(format: "%.2f", l.currentBalance)
            rateText = String(format: "%.2f", l.interestRate * 100)
            minPaymentText = l.minimumPayment.map { String(format: "%.2f", $0) } ?? ""
        }
    }

    private func save() {
        guard let ratePercent = parsedRate else { return }
        let rateDecimal = ratePercent / 100.0
        let trimmedName = loanName.trimmingCharacters(in: .whitespaces)
        let trimmedLender = lender.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        isSaving = true
        saveError = nil
        Task {
            let ok: Bool
            switch mode {
            case .create:
                guard let original = parsedOriginal, let balance = parsedBalance else {
                    isSaving = false
                    saveError = "Original principal and current balance are required."
                    return
                }
                let body = CreateLoanDTO(
                    loanName: trimmedName,
                    lender: trimmedLender.isEmpty ? nil : trimmedLender,
                    loanType: loanType,
                    originalPrincipal: original,
                    currentBalance: balance,
                    interestRate: rateDecimal,
                    interestRateType: "yearly",
                    minimumPayment: parsedMin,
                    dueDay: nil,
                    startDate: nil
                )
                ok = (await debt.addLoan(body)) != nil
            case .edit(let original):
                let patch = diff(original: original, name: trimmedName, lender: trimmedLender, rateDecimal: rateDecimal)
                ok = await debt.updateLoan(id: original.id, patch: patch)
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

    private func diff(original: LoanDTO, name: String, lender: String, rateDecimal: Double) -> UpdateLoanDTO {
        let nameChanged = name != original.loanName
        let lenderChanged = lender != (original.lender ?? "")
        let balChanged = parsedBalance != nil && parsedBalance != original.currentBalance
        let rateChanged = abs(rateDecimal - original.interestRate) > 0.0001
        let minChanged = parsedMin != original.minimumPayment
        return UpdateLoanDTO(
            loanName: nameChanged ? name : nil,
            lender: lenderChanged ? (lender.isEmpty ? nil : lender) : nil,
            currentBalance: balChanged ? parsedBalance : nil,
            interestRate: rateChanged ? rateDecimal : nil,
            minimumPayment: minChanged ? parsedMin : nil,
            dueDay: nil
        )
    }
}
