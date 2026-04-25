//
//  DebtDashboardView.swift
//  Slice 8 — real debt tracker driven by DebtService.
//   • Hero card: total debt + minimum payment + recommended-strategy hint
//   • Credit cards section with utilisation bars + APR badges
//   • Loans section with payoff progress bars
//   • Payoff strategy card: avalanche/snowball/hybrid/minimum_only chips,
//     editable monthly budget, server-computed months-to-freedom and
//     total interest. Switching strategy is local — no extra request.
//   • Add via toolbar menu, edit via tap, delete via context menu.
//

import SwiftUI

struct DebtDashboardView: View {
    @Environment(\.appTheme) private var theme
    @Environment(DebtService.self) private var debt

    @State private var showAddCard = false
    @State private var showAddLoan = false
    @State private var editingCard: CreditCardDTO?
    @State private var editingLoan: LoanDTO?
    @State private var pendingDelete: PendingDelete?

    @State private var selectedStrategy: DebtService.PayoffStrategy = .avalanche
    @State private var monthlyBudgetText: String = ""
    @State private var saveStamp = 0
    @State private var deleteStamp = 0
    @State private var errorStamp = 0

    private enum PendingDelete: Identifiable {
        case card(CreditCardDTO), loan(LoanDTO)
        var id: String {
            switch self {
            case .card(let c): "card-\(c.id)"
            case .loan(let l): "loan-\(l.id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()
                content
            }
            .navigationTitle("Debt")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAddCard = true } label: { Label("Add credit card", systemImage: "creditcard") }
                        Button { showAddLoan = true } label: { Label("Add loan", systemImage: "building.columns") }
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(theme.accent)
                    }
                }
            }
        }
        .onAppear { seedBudgetIfNeeded() }
        .onChange(of: debt.summary?.totalMinimumPayment) { _, _ in seedBudgetIfNeeded() }
        .sheet(isPresented: $showAddCard) {
            CreditCardEditSheet(mode: .create)
                .presentationDetents([.large])
                .presentationBackground(sheetBackground)
        }
        .sheet(item: $editingCard) { c in
            CreditCardEditSheet(mode: .edit(c))
                .presentationDetents([.large])
                .presentationBackground(sheetBackground)
        }
        .sheet(isPresented: $showAddLoan) {
            LoanEditSheet(mode: .create)
                .presentationDetents([.large])
                .presentationBackground(sheetBackground)
        }
        .sheet(item: $editingLoan) { l in
            LoanEditSheet(mode: .edit(l))
                .presentationDetents([.large])
                .presentationBackground(sheetBackground)
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { item in
            Button("Delete", role: .destructive) { performDelete(item) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This can't be undone. Your payoff projection will recompute without it.")
        }
        .sensoryFeedback(.success, trigger: saveStamp)
        .sensoryFeedback(.warning, trigger: deleteStamp)
        .sensoryFeedback(.error, trigger: errorStamp)
    }

    private var sheetBackground: AnyShapeStyle {
        theme.id == .liquidGlass
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(theme.background)
    }

    private var confirmationTitle: String {
        switch pendingDelete {
        case .card(let c): "Delete \(c.cardName)?"
        case .loan(let l): "Delete \(l.loanName)?"
        case .none:        ""
        }
    }

    // MARK: - Content router

    @ViewBuilder
    private var content: some View {
        switch debt.state {
        case .idle:
            ScrollView { loadingCard.padding(16) }.scrollContentBackground(.hidden)
        case .loading where debt.creditCards.isEmpty && debt.loans.isEmpty:
            ScrollView { loadingCard.padding(16) }.scrollContentBackground(.hidden)
        case .failed(let msg):
            ScrollView { errorCard(msg).padding(16) }.scrollContentBackground(.hidden)
        case .loaded, .partial, .loading:
            if isEmpty {
                emptyState
            } else {
                loadedScroll
            }
        }
    }

    private var isEmpty: Bool { debt.creditCards.isEmpty && debt.loans.isEmpty }

    private var loadedScroll: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                if !debt.creditCards.isEmpty { creditCardsCard }
                if !debt.loans.isEmpty { loansCard }
                payoffCard
                if case .partial(let msg) = debt.state {
                    partialBanner(msg)
                }
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await debt.loadAll() }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TOTAL DEBT").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
                Text(currency(debt.summary?.totalBalance ?? totalDebtFallback))
                    .font(theme.font.heroNumeral)
                    .foregroundStyle(theme.textPrimary)
            }
            Text(subtitleText)
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
            if currentStrategyEntry != nil {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(theme.accent)
                    Text("\(selectedStrategy.label) clears in \(currentStrategyEntry?.monthsToFreedom ?? 0) months • \(currencyWithDollar(currentStrategyEntry?.totalInterest ?? 0)) interest")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.accent)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .themedCard()
    }

    private var subtitleText: String {
        let cards = debt.creditCards.count
        let loans = debt.loans.count
        let parts = [
            cards > 0 ? "\(cards) card\(cards == 1 ? "" : "s")" : nil,
            loans > 0 ? "\(loans) loan\(loans == 1 ? "" : "s")" : nil
        ].compactMap { $0 }
        let joined = parts.joined(separator: " and ")
        let mins = currencyWithDollar(debt.summary?.totalMinimumPayment ?? 0)
        return joined.isEmpty
            ? "Add a card or loan to start tracking"
            : "Across \(joined) • \(mins)/mo minimum"
    }

    private var totalDebtFallback: Double {
        debt.creditCards.reduce(0) { $0 + $1.currentBalance }
            + debt.loans.reduce(0) { $0 + $1.currentBalance }
    }

    // MARK: - Credit cards

    private var creditCardsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CREDIT CARDS").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            VStack(spacing: 10) {
                ForEach(debt.creditCards) { card in
                    Button { editingCard = card } label: {
                        creditCardRow(card)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDelete = .card(card)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .padding(18)
        .themedCard()
    }

    private func creditCardRow(_ c: CreditCardDTO) -> some View {
        let utilization = (c.utilization ?? 0) / 100.0
        let utilColor: Color = {
            if utilization >= 0.8 { return theme.negative }
            if utilization >= 0.5 { return theme.accent }
            return theme.positive
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(c.cardName).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                        if let four = c.lastFour {
                            Text("•••• \(four)").font(theme.font.caption).foregroundStyle(theme.textTertiary)
                        }
                    }
                    Text("\(currencyWithDollar(c.currentBalance)) of \(currencyWithDollar(c.creditLimit ?? 0))")
                        .font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Text(String(format: "%.1f%%", c.apr * 100))
                    .font(theme.font.captionMedium)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(theme.accent.opacity(0.18)))
                    .foregroundStyle(theme.accent)
            }
            ProgressView(value: min(max(utilization, 0), 1))
                .tint(utilColor)
        }
    }

    // MARK: - Loans

    private var loansCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOANS").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            VStack(spacing: 10) {
                ForEach(debt.loans) { loan in
                    Button { editingLoan = loan } label: {
                        loanRow(loan)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDelete = .loan(loan)
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .padding(18)
        .themedCard()
    }

    private func loanRow(_ l: LoanDTO) -> some View {
        let progress = (l.progressPercent ?? 0) / 100.0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.loanName).font(theme.font.bodyMedium).foregroundStyle(theme.textPrimary)
                    Text("\(l.lender ?? l.loanType.capitalized) • \(currencyWithDollar(l.currentBalance)) of \(currencyWithDollar(l.originalPrincipal))")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer()
                Text(String(format: "%.2f%%", l.interestRate * 100))
                    .font(theme.font.captionMedium)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(theme.positive.opacity(0.18)))
                    .foregroundStyle(theme.positive)
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(theme.positive)
        }
    }

    // MARK: - Payoff card

    private var payoffCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PAYOFF STRATEGY").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)

            HStack(spacing: 8) {
                ForEach(DebtService.PayoffStrategy.allCases, id: \.self) { s in
                    let active = selectedStrategy == s
                    Button {
                        selectedStrategy = s
                    } label: {
                        Text(s.label)
                            .font(theme.font.captionMedium)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(active ? theme.accent.opacity(0.3) : theme.surface))
                            .foregroundStyle(active ? theme.accent : theme.textSecondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Text("Monthly budget").font(theme.font.caption).foregroundStyle(theme.textSecondary)
                Spacer()
                Text("$").font(theme.font.body).foregroundStyle(theme.textSecondary)
                TextField("500", text: $monthlyBudgetText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(theme.font.bodyMedium)
                    .frame(width: 90)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.surface))
                Button("Refresh") { Task { await refreshStrategiesIfPossible() } }
                    .font(theme.font.captionMedium)
                    .foregroundStyle(theme.accent)
            }

            if let entry = currentStrategyEntry {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        statTile(label: "Months", value: "\(entry.monthsToFreedom)")
                        statTile(label: "Interest", value: currencyWithDollar(entry.totalInterest))
                    }
                    if !entry.payoffOrder.isEmpty {
                        Text("Clearance order")
                            .font(theme.font.captionMedium).tracking(1.0)
                            .foregroundStyle(theme.textTertiary)
                            .padding(.top, 4)
                        ForEach(Array(entry.payoffOrder.enumerated()), id: \.offset) { idx, name in
                            HStack(spacing: 8) {
                                Text("\(idx + 1).").foregroundStyle(theme.textTertiary)
                                Text(name).foregroundStyle(theme.textPrimary)
                                Spacer()
                            }
                            .font(theme.font.body)
                        }
                    }
                }
            } else if debt.strategies == nil {
                Text("Enter a monthly budget to compute your payoff projection.")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
            }

            if let rec = debt.strategies?.recommendation, !rec.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(theme.accent)
                    Text(rec).font(theme.font.caption).foregroundStyle(theme.textSecondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .themedCard()
        .task(id: monthlyBudgetText) {
            // Auto-refresh after the user changes the budget. 350 ms debounce
            // keeps us from thrashing the API while they're still typing.
            try? await Task.sleep(for: .milliseconds(350))
            await refreshStrategiesIfPossible()
        }
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(theme.font.captionMedium).tracking(1.0).foregroundStyle(theme.textTertiary)
            Text(value).font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surface))
    }

    private var currentStrategyEntry: PayoffStrategyDTO? {
        guard let s = debt.strategies else { return nil }
        switch selectedStrategy {
        case .avalanche: return s.avalanche
        case .snowball: return s.snowball
        case .hybrid: return s.hybrid
        case .minimumOnly: return s.minimumOnly
        }
    }

    private func parsedBudget() -> Double? {
        let trimmed = monthlyBudgetText.trimmingCharacters(in: .whitespaces)
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    private func seedBudgetIfNeeded() {
        guard monthlyBudgetText.isEmpty else { return }
        let suggested = (debt.summary?.totalMinimumPayment ?? 0) * 1.5
        if suggested > 0 {
            monthlyBudgetText = String(format: "%.0f", suggested)
        }
    }

    private func refreshStrategiesIfPossible() async {
        guard let b = parsedBudget(), b > 0 else { return }
        await debt.refreshStrategies(monthlyBudget: b)
    }

    // MARK: - Empty / loading / error / partial

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 40)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(theme.positive)
            Text("No tracked debt")
                .font(theme.font.title)
                .foregroundStyle(theme.textPrimary)
            Text("Good news. Add a card or loan to project payoff plans.")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 12) {
                Button { showAddCard = true } label: {
                    Label("Add credit card", systemImage: "creditcard.fill")
                        .font(theme.font.bodyMedium)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(theme.accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(theme.accent)
                }
                Button { showAddLoan = true } label: {
                    Label("Add loan", systemImage: "building.columns")
                        .font(theme.font.bodyMedium)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(theme.surface, in: Capsule())
                        .foregroundStyle(theme.textPrimary)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingCard: some View {
        VStack(spacing: 14) {
            ProgressView().tint(theme.accent)
            Text("Loading your debt…").font(theme.font.caption).foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(24)
        .themedCard()
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 28)).foregroundStyle(theme.negative)
            Text("Couldn't load debt info").font(theme.font.titleCompact).foregroundStyle(theme.textPrimary)
            Text(msg).font(theme.font.caption).foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
            Button { Task { await debt.loadAll() } } label: {
                Text("Try again").font(theme.font.bodyMedium)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(theme.accent.opacity(0.18), in: Capsule())
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(maxWidth: .infinity).padding(24).themedCard()
    }

    private func partialBanner(_ msg: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(theme.accent)
            Text(msg).font(theme.font.caption).foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Actions

    private func performDelete(_ item: PendingDelete) {
        Task {
            switch item {
            case .card(let c):
                if await debt.deleteCreditCard(id: c.id) { deleteStamp += 1 }
                else { errorStamp += 1 }
            case .loan(let l):
                if await debt.deleteLoan(id: l.id) { deleteStamp += 1 }
                else { errorStamp += 1 }
            }
            pendingDelete = nil
            await refreshStrategiesIfPossible()
        }
    }

    // MARK: - Formatting

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale.current
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }

    private func currencyWithDollar(_ v: Double) -> String { "$" + currency(v) }
}

#Preview("Debt — Liquid Glass") {
    DebtDashboardView()
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(DebtService.previewStub())
        .preferredColorScheme(.dark)
}
