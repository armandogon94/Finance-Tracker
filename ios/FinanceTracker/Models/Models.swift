//
//  Models.swift
//  Client-side model structs that mirror the backend Pydantic schemas.
//  For now they're populated from MockData; later we'll wire them to
//  APIClient + SwiftData.
//

import SwiftUI
import Foundation

struct Category: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var iconSystemName: String
    var color: Color
    var monthlyBudget: Double?
    var isHidden: Bool = false
}

struct Expense: Identifiable, Hashable, Sendable {
    let id: UUID
    var amount: Double
    var currency: String = "USD"
    var description: String?
    var merchantName: String?
    var categoryId: UUID?
    var expenseDate: Date
    var hasReceipt: Bool = false
    var ocrMethod: String? = nil
}

struct CreditCard: Identifiable, Hashable, Sendable {
    let id: UUID
    var cardName: String
    var lastFour: String?
    var currentBalance: Double
    var creditLimit: Double?
    var aprPercent: Double   // store as percent, e.g. 18.0
    var minimumPayment: Double?
    var utilization: Double { (creditLimit ?? 0) > 0 ? currentBalance / (creditLimit ?? 1) : 0 }
}

struct Loan: Identifiable, Hashable, Sendable {
    let id: UUID
    var loanName: String
    var lender: String?
    var loanType: String
    var originalPrincipal: Double
    var currentBalance: Double
    var interestRatePercent: Double
    var minimumPayment: Double?
    var progressPercent: Double {
        originalPrincipal > 0 ? (originalPrincipal - currentBalance) / originalPrincipal * 100 : 0
    }
}

struct PayoffStrategy: Identifiable, Hashable, Sendable {
    let id = UUID()
    var name: String          // "Avalanche" / "Snowball" / "Hybrid" / "Minimum only"
    var monthsToFreedom: Int
    var totalInterest: Double
    var totalPaid: Double
    var payoffOrder: [String]
}

struct ChatConversation: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var lastMessagePreview: String
    var updatedAt: Date
}

struct ChatMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    var role: Role
    var content: String
    var timestamp: Date
    enum Role: String, Sendable { case user, assistant }
}

struct DailySpend: Identifiable, Hashable, Sendable {
    let id = UUID()
    let date: Date
    let amount: Double
}

struct CategorySpend: Identifiable, Hashable, Sendable {
    let id = UUID()
    let categoryName: String
    let color: Color
    let amount: Double
}
