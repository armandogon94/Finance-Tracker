//
//  DebtService.swift
//  Loads and mutates credit cards + loans + summary, and fetches
//  payoff strategies from the backend (no client-side math). All
//  endpoints discovered via openapi probe on 2026-04-25:
//
//    GET /api/v1/credit-cards/                             → [CreditCardResponse]
//    POST /api/v1/credit-cards/                            CreditCardCreate → CreditCardResponse
//    PATCH /api/v1/credit-cards/{id}                       CreditCardUpdate → CreditCardResponse
//    DELETE /api/v1/credit-cards/{id}
//    GET /api/v1/loans/                                    → [LoanResponse]
//    POST /api/v1/loans/                                   LoanCreate → LoanResponse
//    PATCH /api/v1/loans/{id}                              LoanUpdate → LoanResponse
//    DELETE /api/v1/loans/{id}
//    GET /api/v1/debt/summary                              → DebtSummary
//    GET /api/v1/debt/strategies?monthly_budget=X          → StrategyComparison
//
//  Field gotchas (from probe):
//    - apr (CC) and interest_rate (Loan) are stored as DECIMALS, not percent.
//      0.18 means 18% APR; 0.055 means 5.5% interest. The UI multiplies by
//      100 for display and divides by 100 when sending edits back.
//    - utilization comes back already as a 0–100 percentage.
//    - progress_percent on loans is also already 0–100.
//
//  Partial-failure semantics mirror AnalyticsService: cards/loans/summary
//  load concurrently; if at least one slice succeeds the service lands in
//  .partial(message), only when all three fail does it land in .failed.
//

import Foundation
import Observation

@Observable @MainActor
final class DebtService {
    enum LoadState: Equatable, Sendable {
        case idle, loading, loaded
        case partial(String)
        case failed(String)
    }

    enum PayoffStrategy: String, CaseIterable, Sendable, Hashable {
        case avalanche, snowball, hybrid, minimumOnly = "minimum_only"
        var label: String {
            switch self {
            case .avalanche:   "Avalanche"
            case .snowball:    "Snowball"
            case .hybrid:      "Hybrid"
            case .minimumOnly: "Minimum only"
            }
        }
    }

    private(set) var state: LoadState = .idle
    private(set) var creditCards: [CreditCardDTO] = []
    private(set) var loans: [LoanDTO] = []
    private(set) var summary: DebtSummaryDTO?
    private(set) var strategies: StrategyComparisonDTO?
    private(set) var lastBudgetUsed: Double?

    // Closures so tests can inject in-memory fakes — same trick used by
    // ScanService. Production wiring threads APIClient through these.
    // @Sendable so they can survive the @MainActor boundary when async-let
    // hops them off the main thread for the parallel load.
    private let loadCards: @Sendable () async throws -> [CreditCardDTO]
    private let loadLoans: @Sendable () async throws -> [LoanDTO]
    private let loadSummary: @Sendable () async throws -> DebtSummaryDTO?
    private let loadStrategies: @Sendable (Double) async throws -> StrategyComparisonDTO

    private let createCardCall: @Sendable (CreateCreditCardDTO) async throws -> CreditCardDTO
    private let updateCardCall: @Sendable (UUID, UpdateCreditCardDTO) async throws -> CreditCardDTO
    private let deleteCardCall: @Sendable (UUID) async throws -> Void

    private let createLoanCall: @Sendable (CreateLoanDTO) async throws -> LoanDTO
    private let updateLoanCall: @Sendable (UUID, UpdateLoanDTO) async throws -> LoanDTO
    private let deleteLoanCall: @Sendable (UUID) async throws -> Void

    init(
        loadCards: @escaping @Sendable () async throws -> [CreditCardDTO],
        loadLoans: @escaping @Sendable () async throws -> [LoanDTO],
        loadSummary: @escaping @Sendable () async throws -> DebtSummaryDTO?,
        loadStrategies: @escaping @Sendable (Double) async throws -> StrategyComparisonDTO,
        createCardCall: @escaping @Sendable (CreateCreditCardDTO) async throws -> CreditCardDTO,
        updateCardCall: @escaping @Sendable (UUID, UpdateCreditCardDTO) async throws -> CreditCardDTO,
        deleteCardCall: @escaping @Sendable (UUID) async throws -> Void,
        createLoanCall: @escaping @Sendable (CreateLoanDTO) async throws -> LoanDTO,
        updateLoanCall: @escaping @Sendable (UUID, UpdateLoanDTO) async throws -> LoanDTO,
        deleteLoanCall: @escaping @Sendable (UUID) async throws -> Void
    ) {
        self.loadCards = loadCards
        self.loadLoans = loadLoans
        self.loadSummary = loadSummary
        self.loadStrategies = loadStrategies
        self.createCardCall = createCardCall
        self.updateCardCall = updateCardCall
        self.deleteCardCall = deleteCardCall
        self.createLoanCall = createLoanCall
        self.updateLoanCall = updateLoanCall
        self.deleteLoanCall = deleteLoanCall
    }

    // MARK: - Loading

    func loadAll() async {
        state = .loading

        async let cardsTask = loadCards()
        async let loansTask = loadLoans()
        async let summaryTask = loadSummary()

        let cardsResult: Result<[CreditCardDTO], Error>
        do { cardsResult = .success(try await cardsTask) }
        catch { cardsResult = .failure(error) }

        let loansResult: Result<[LoanDTO], Error>
        do { loansResult = .success(try await loansTask) }
        catch { loansResult = .failure(error) }

        let summaryResult: Result<DebtSummaryDTO?, Error>
        do { summaryResult = .success(try await summaryTask) }
        catch { summaryResult = .failure(error) }

        var failedSlices: [String] = []
        switch cardsResult {
        case .success(let v): self.creditCards = v
        case .failure: failedSlices.append("credit cards")
        }
        switch loansResult {
        case .success(let v): self.loans = v
        case .failure: failedSlices.append("loans")
        }
        switch summaryResult {
        case .success(let v): self.summary = v
        case .failure: failedSlices.append("summary")
        }

        if failedSlices.count == 3 {
            state = .failed("Couldn't load debt info.")
        } else if failedSlices.isEmpty {
            state = .loaded
        } else {
            state = .partial("Couldn't load: \(failedSlices.joined(separator: ", ")).")
        }
    }

    /// Refresh just the strategy comparison. Cheap to re-run because the
    /// backend computes it from the user's existing cards + loans.
    /// Skipped (silently leaves `strategies = nil`) when the user has zero
    /// debt — the endpoint isn't meaningful in that case.
    func refreshStrategies(monthlyBudget: Double) async {
        guard !creditCards.isEmpty || !loans.isEmpty, monthlyBudget > 0 else {
            strategies = nil
            return
        }
        do {
            strategies = try await loadStrategies(monthlyBudget)
            lastBudgetUsed = monthlyBudget
        } catch {
            // Keep whatever we had cached; the caller can show a stale
            // value rather than blanking the strategy card.
        }
    }

    /// Drop every cached field. Called from AuthService.onSignOut.
    func reset() {
        state = .idle
        creditCards = []
        loans = []
        summary = nil
        strategies = nil
        lastBudgetUsed = nil
    }

    // MARK: - Credit-card mutations

    /// Adds a new credit card. The card lands in the local cache at row 0
    /// only on a successful POST — no optimistic insert because the
    /// server-assigned id and timestamps shape the row.
    func addCreditCard(_ body: CreateCreditCardDTO) async -> CreditCardDTO? {
        do {
            let card = try await createCardCall(body)
            creditCards.insert(card, at: 0)
            return card
        } catch {
            return nil
        }
    }

    func updateCreditCard(id: UUID, patch: UpdateCreditCardDTO) async -> Bool {
        do {
            let updated = try await updateCardCall(id, patch)
            if let i = creditCards.firstIndex(where: { $0.id == id }) {
                creditCards[i] = updated
            }
            return true
        } catch {
            return false
        }
    }

    func deleteCreditCard(id: UUID) async -> Bool {
        let snapshot = creditCards
        creditCards.removeAll { $0.id == id }
        do {
            try await deleteCardCall(id)
            return true
        } catch {
            creditCards = snapshot
            return false
        }
    }

    // MARK: - Loan mutations

    func addLoan(_ body: CreateLoanDTO) async -> LoanDTO? {
        do {
            let loan = try await createLoanCall(body)
            loans.insert(loan, at: 0)
            return loan
        } catch {
            return nil
        }
    }

    func updateLoan(id: UUID, patch: UpdateLoanDTO) async -> Bool {
        do {
            let updated = try await updateLoanCall(id, patch)
            if let i = loans.firstIndex(where: { $0.id == id }) {
                loans[i] = updated
            }
            return true
        } catch {
            return false
        }
    }

    func deleteLoan(id: UUID) async -> Bool {
        let snapshot = loans
        loans.removeAll { $0.id == id }
        do {
            try await deleteLoanCall(id)
            return true
        } catch {
            loans = snapshot
            return false
        }
    }

    /// Preview-only constructor that crashes on every call. SwiftUI
    /// previews need the type but never actually drive these methods.
    static func previewStub() -> DebtService {
        DebtService(
            loadCards:       { [] },
            loadLoans:       { [] },
            loadSummary:     { nil },
            loadStrategies:  { _ in fatalError("preview") },
            createCardCall:  { _ in fatalError("preview") },
            updateCardCall:  { _, _ in fatalError("preview") },
            deleteCardCall:  { _ in fatalError("preview") },
            createLoanCall:  { _ in fatalError("preview") },
            updateLoanCall:  { _, _ in fatalError("preview") },
            deleteLoanCall:  { _ in fatalError("preview") }
        )
    }
}
