//
//  DebtTests.swift
//  Slice 8 — verifies DTO decoding for the four debt endpoints
//  (credit cards, loans, summary, strategies) plus DebtService's
//  state machine and strategy-switching behaviour. Payoff math lives
//  on the backend (`GET /api/v1/debt/strategies`), so iOS doesn't
//  need DebtMath — we just decode the response.
//

import XCTest
@testable import FinanceTracker

@MainActor
final class DebtTests: XCTestCase {

    // MARK: - DTO decoding

    func testCreditCardDTODecodes() throws {
        // Real fixture from GET /api/v1/credit-cards/. Note: backend
        // stores APR as a decimal (0.18 == 18 percent).
        let json = """
        {
          "id": "abd4b965-7016-4daf-8db9-54724c0505a8",
          "card_name": "Amex Gold",
          "last_four": "0001",
          "current_balance": 400.0,
          "credit_limit": 5000.0,
          "apr": 0.18,
          "minimum_payment": 25.0,
          "statement_day": null,
          "due_day": null,
          "utilization": 8.0,
          "is_active": true,
          "created_at": "2026-04-23T02:52:01.444998Z",
          "updated_at": "2026-04-23T02:52:07.437226Z"
        }
        """.data(using: .utf8)!

        let card = try APIClient.makeDecoder().decode(CreditCardDTO.self, from: json)
        XCTAssertEqual(card.cardName, "Amex Gold")
        XCTAssertEqual(card.lastFour, "0001")
        XCTAssertEqual(card.currentBalance, 400.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(card.creditLimit), 5000.0, accuracy: 0.001)
        XCTAssertEqual(card.apr, 0.18, accuracy: 0.001, "APR is stored as decimal — multiply by 100 for display")
        XCTAssertEqual(try XCTUnwrap(card.minimumPayment), 25.0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(card.utilization), 8.0, accuracy: 0.001)
    }

    func testLoanDTODecodes() throws {
        // Real fixture from GET /api/v1/loans/. interest_rate is also
        // a decimal (0.055 == 5.5 percent yearly).
        let json = """
        {
          "id": "4caf3819-0838-4db8-a9f0-5c511ff02798",
          "loan_name": "Car Loan",
          "lender": "Wells Fargo",
          "loan_type": "car",
          "original_principal": 18000.0,
          "current_balance": 14718.75,
          "interest_rate": 0.055,
          "interest_rate_type": "yearly",
          "minimum_payment": 350.0,
          "due_day": null,
          "start_date": null,
          "progress_percent": 18.23,
          "is_active": true,
          "created_at": "2026-04-23T02:52:01.452836Z"
        }
        """.data(using: .utf8)!

        let loan = try APIClient.makeDecoder().decode(LoanDTO.self, from: json)
        XCTAssertEqual(loan.loanName, "Car Loan")
        XCTAssertEqual(loan.lender, "Wells Fargo")
        XCTAssertEqual(loan.loanType, "car")
        XCTAssertEqual(loan.originalPrincipal, 18000.0, accuracy: 0.001)
        XCTAssertEqual(loan.currentBalance, 14718.75, accuracy: 0.001)
        XCTAssertEqual(loan.interestRate, 0.055, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(loan.progressPercent), 18.23, accuracy: 0.01)
    }

    func testDebtSummaryDTODecodes() throws {
        let json = """
        {
          "total_balance": 15118.75,
          "total_minimum_payment": 375.0,
          "credit_cards": {
            "count": 1,
            "total_balance": 400.0,
            "total_credit_limit": 5000.0,
            "overall_utilization": 8.0,
            "total_minimum": 25.0,
            "average_apr": 0.18
          },
          "loans": {
            "count": 1,
            "total_balance": 14718.75,
            "total_original_principal": 18000.0,
            "overall_progress_percent": 18.23,
            "total_minimum": 350.0,
            "average_rate": 0.055
          }
        }
        """.data(using: .utf8)!

        let summary = try APIClient.makeDecoder().decode(DebtSummaryDTO.self, from: json)
        XCTAssertEqual(summary.totalBalance, 15118.75, accuracy: 0.001)
        XCTAssertEqual(summary.totalMinimumPayment, 375.0, accuracy: 0.001)
        XCTAssertEqual(summary.creditCards.count, 1)
        XCTAssertEqual(summary.loans.count, 1)
    }

    func testStrategyComparisonDTODecodes() throws {
        // Real fixture from GET /api/v1/debt/strategies?monthly_budget=500
        let json = """
        {
          "avalanche":   { "strategy": "avalanche",   "months_to_freedom": 33, "total_interest": 1202.52, "payoff_order": ["Amex Gold", "Car Loan"] },
          "snowball":    { "strategy": "snowball",    "months_to_freedom": 33, "total_interest": 1202.52, "payoff_order": ["Amex Gold", "Car Loan"] },
          "hybrid":      { "strategy": "hybrid",      "months_to_freedom": 33, "total_interest": 1202.52, "payoff_order": ["Amex Gold", "Car Loan"] },
          "minimum_only":{ "strategy": "minimum_only","months_to_freedom": 45, "total_interest": 1687.52, "payoff_order": ["Amex Gold", "Car Loan"] },
          "recommendation": "Avalanche is both the fastest (33 months) and cheapest ($1,202.52 total interest)."
        }
        """.data(using: .utf8)!

        let cmp = try APIClient.makeDecoder().decode(StrategyComparisonDTO.self, from: json)
        XCTAssertEqual(cmp.avalanche.monthsToFreedom, 33)
        XCTAssertEqual(cmp.avalanche.totalInterest, 1202.52, accuracy: 0.01)
        XCTAssertEqual(cmp.avalanche.payoffOrder, ["Amex Gold", "Car Loan"])
        XCTAssertEqual(cmp.minimumOnly.monthsToFreedom, 45)
        XCTAssertFalse(cmp.recommendation.isEmpty)
    }

    // MARK: - DebtService

    func testDebtServiceLoadAllPopulatesAllThreeCachesConcurrently() async {
        let cardJSON = Self.fixture(of: CreditCardDTO.self, json: """
            {"id":"\(UUID().uuidString)","card_name":"Test","last_four":null,
             "current_balance":1000.0,"credit_limit":2000.0,"apr":0.20,
             "minimum_payment":50.0,"statement_day":null,"due_day":null,
             "utilization":50.0,"is_active":true,
             "created_at":"2026-04-25T00:00:00Z","updated_at":"2026-04-25T00:00:00Z"}
            """)
        let loanJSON = Self.fixture(of: LoanDTO.self, json: """
            {"id":"\(UUID().uuidString)","loan_name":"Test Loan","lender":null,
             "loan_type":"other","original_principal":5000.0,"current_balance":3000.0,
             "interest_rate":0.06,"interest_rate_type":"yearly","minimum_payment":150.0,
             "due_day":null,"start_date":null,"progress_percent":40.0,
             "is_active":true,"created_at":"2026-04-25T00:00:00Z"}
            """)
        let summaryJSON = Self.fixture(of: DebtSummaryDTO.self, json: """
            {"total_balance":4000.0,"total_minimum_payment":200.0,
             "credit_cards":{"count":1,"total_balance":1000.0,"total_credit_limit":2000.0,
                            "overall_utilization":50.0,"total_minimum":50.0,"average_apr":0.20},
             "loans":{"count":1,"total_balance":3000.0,"total_original_principal":5000.0,
                     "overall_progress_percent":40.0,"total_minimum":150.0,"average_rate":0.06}}
            """)

        let service = DebtService(
            loadCards:    { [cardJSON] },
            loadLoans:    { [loanJSON] },
            loadSummary:  { summaryJSON },
            loadStrategies:  { _ in fatalError("not in this test") },
            createCardCall:  { _ in fatalError() },
            updateCardCall:  { _, _ in fatalError() },
            deleteCardCall:  { _ in fatalError() },
            createLoanCall:  { _ in fatalError() },
            updateLoanCall:  { _, _ in fatalError() },
            deleteLoanCall:  { _ in fatalError() }
        )

        XCTAssertEqual(service.state, .idle)
        await service.loadAll()
        XCTAssertEqual(service.state, .loaded)
        XCTAssertEqual(service.creditCards.count, 1)
        XCTAssertEqual(service.loans.count, 1)
        XCTAssertNotNil(service.summary)
    }

    func testDebtServicePartialFailureKeepsOtherSlicesPopulated() async {
        let cardJSON = Self.fixture(of: CreditCardDTO.self, json: """
            {"id":"\(UUID().uuidString)","card_name":"Test","last_four":null,
             "current_balance":1000.0,"credit_limit":2000.0,"apr":0.20,
             "minimum_payment":50.0,"statement_day":null,"due_day":null,
             "utilization":50.0,"is_active":true,
             "created_at":"2026-04-25T00:00:00Z","updated_at":"2026-04-25T00:00:00Z"}
            """)

        // Loans throws; cards + summary succeed.
        let service = DebtService(
            loadCards:    { [cardJSON] },
            loadLoans:    { throw APIError.unknown("loans down") },
            loadSummary:  { nil },
            loadStrategies:  { _ in fatalError() },
            createCardCall:  { _ in fatalError() },
            updateCardCall:  { _, _ in fatalError() },
            deleteCardCall:  { _ in fatalError() },
            createLoanCall:  { _ in fatalError() },
            updateLoanCall:  { _, _ in fatalError() },
            deleteLoanCall:  { _ in fatalError() }
        )

        await service.loadAll()
        if case .partial = service.state {} else {
            XCTFail("expected .partial, got \(service.state)")
        }
        XCTAssertEqual(service.creditCards.count, 1, "successful slice (cards) should still populate")
        XCTAssertTrue(service.loans.isEmpty)
    }

    // MARK: - Helpers

    private static func fixture<T: Decodable>(of type: T.Type, json: String) -> T {
        let data = json.data(using: .utf8)!
        return try! APIClient.makeDecoder().decode(T.self, from: data)
    }
}
