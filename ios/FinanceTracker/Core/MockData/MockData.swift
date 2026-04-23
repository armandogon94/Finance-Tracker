//
//  MockData.swift
//  Deterministic fake data used across all screen skeletons until the
//  real APIClient is wired up. Realistic enough to evaluate a design
//  at a glance — actual merchant names, plausible amounts, sensible
//  dates, meaningful trends.
//

import SwiftUI
import Foundation

enum MockData {
    // MARK: - User

    static let user = (name: "Claude Tester", email: "claude@example.com", currency: "USD")

    // MARK: - Categories (match the backend's seeded 9)

    static let categories: [Category] = [
        Category(id: UUID(), name: "Food & Dining",   iconSystemName: "fork.knife",          color: Color(red: 0.98, green: 0.56, blue: 0.42), monthlyBudget: 600),
        Category(id: UUID(), name: "Transportation",  iconSystemName: "car.fill",            color: Color(red: 1.00, green: 0.78, blue: 0.35), monthlyBudget: 250),
        Category(id: UUID(), name: "Shopping",        iconSystemName: "bag.fill",            color: Color(red: 0.70, green: 0.55, blue: 1.00), monthlyBudget: 300),
        Category(id: UUID(), name: "Entertainment",   iconSystemName: "film.fill",           color: Color(red: 0.95, green: 0.55, blue: 0.83), monthlyBudget: 100),
        Category(id: UUID(), name: "Bills & Utilities", iconSystemName: "bolt.fill",         color: Color(red: 0.55, green: 0.70, blue: 1.00), monthlyBudget: 400),
        Category(id: UUID(), name: "Health",          iconSystemName: "heart.fill",          color: Color(red: 0.45, green: 0.92, blue: 0.69), monthlyBudget: 150),
        Category(id: UUID(), name: "Education",       iconSystemName: "book.fill",           color: Color(red: 0.45, green: 0.78, blue: 0.95), monthlyBudget: 200),
        Category(id: UUID(), name: "Personal",        iconSystemName: "person.fill",         color: Color(red: 1.00, green: 0.65, blue: 0.40), monthlyBudget: 100),
        Category(id: UUID(), name: "Other",           iconSystemName: "square.grid.2x2.fill",color: Color(red: 0.65, green: 0.68, blue: 0.75), monthlyBudget: nil),
    ]

    static func category(named name: String) -> Category? {
        categories.first { $0.name == name }
    }

    // MARK: - Expenses

    static let expenses: [Expense] = {
        let now = Date()
        let cal = Calendar.current
        func days(ago: Int) -> Date { cal.date(byAdding: .day, value: -ago, to: now)! }

        return [
            Expense(id: UUID(), amount: 5.50,  description: "Starbucks latte",       merchantName: "Starbucks",     categoryId: category(named: "Food & Dining")?.id,     expenseDate: now),
            Expense(id: UUID(), amount: 43.21, description: "Weekly groceries",      merchantName: "Whole Foods",   categoryId: category(named: "Food & Dining")?.id,     expenseDate: now),
            Expense(id: UUID(), amount: 89.00, description: "Netflix annual",        merchantName: "Netflix",       categoryId: category(named: "Bills & Utilities")?.id, expenseDate: days(ago: 1)),
            Expense(id: UUID(), amount: 23.15, description: "Coffee run",            merchantName: "Dunkin'",       categoryId: category(named: "Food & Dining")?.id,     expenseDate: days(ago: 2), hasReceipt: true, ocrMethod: "claude"),
            Expense(id: UUID(), amount: 52.89, description: "Uber to airport",       merchantName: "Uber",          categoryId: category(named: "Transportation")?.id,    expenseDate: days(ago: 3)),
            Expense(id: UUID(), amount: 14.99, description: "Spotify",               merchantName: "Spotify",       categoryId: category(named: "Bills & Utilities")?.id, expenseDate: days(ago: 4)),
            Expense(id: UUID(), amount: 175.00,description: "New sneakers",          merchantName: "Nike",          categoryId: category(named: "Shopping")?.id,          expenseDate: days(ago: 5)),
            Expense(id: UUID(), amount: 28.40, description: "Pharmacy",              merchantName: "CVS",           categoryId: category(named: "Health")?.id,            expenseDate: days(ago: 6), hasReceipt: true, ocrMethod: "claude"),
            Expense(id: UUID(), amount: 120.00,description: "Electric bill",         merchantName: "ConEd",         categoryId: category(named: "Bills & Utilities")?.id, expenseDate: days(ago: 7)),
            Expense(id: UUID(), amount: 18.75, description: "Pizza dinner",          merchantName: "Joe's Pizza",   categoryId: category(named: "Food & Dining")?.id,     expenseDate: days(ago: 7)),
            Expense(id: UUID(), amount: 9.99,  description: "iCloud+",               merchantName: "Apple",         categoryId: category(named: "Bills & Utilities")?.id, expenseDate: days(ago: 9)),
            Expense(id: UUID(), amount: 62.10, description: "Gas fill-up",           merchantName: "Shell",         categoryId: category(named: "Transportation")?.id,    expenseDate: days(ago: 10)),
            Expense(id: UUID(), amount: 245.80,description: "Amazon order",          merchantName: "Amazon",        categoryId: category(named: "Shopping")?.id,          expenseDate: days(ago: 12)),
            Expense(id: UUID(), amount: 16.00, description: "Movie tickets",         merchantName: "AMC Theaters",  categoryId: category(named: "Entertainment")?.id,     expenseDate: days(ago: 13)),
            Expense(id: UUID(), amount: 34.99, description: "Book — Design Systems", merchantName: "Amazon",        categoryId: category(named: "Education")?.id,         expenseDate: days(ago: 15)),
        ]
    }()

    // MARK: - Aggregates (computed once)

    static var totalThisMonth: Double {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        return expenses.filter { $0.expenseDate >= monthStart }.reduce(0) { $0 + $1.amount }
    }

    static var totalToday: Double {
        let cal = Calendar.current
        return expenses.filter { cal.isDateInToday($0.expenseDate) }.reduce(0) { $0 + $1.amount }
    }

    static var totalThisWeek: Double {
        let cal = Calendar.current
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
        return expenses.filter { $0.expenseDate >= weekStart }.reduce(0) { $0 + $1.amount }
    }

    static var dailyLast14: [DailySpend] {
        let cal = Calendar.current
        let now = Date()
        return (0..<14).map { i -> DailySpend in
            let d = cal.date(byAdding: .day, value: -i, to: now)!
            let total = expenses
                .filter { cal.isDate($0.expenseDate, inSameDayAs: d) }
                .reduce(0.0) { $0 + $1.amount }
            return DailySpend(date: d, amount: total)
        }.reversed()
    }

    static var spendByCategory: [CategorySpend] {
        var totals: [UUID: Double] = [:]
        for e in expenses {
            guard let cid = e.categoryId else { continue }
            totals[cid, default: 0] += e.amount
        }
        return categories.compactMap { cat -> CategorySpend? in
            guard let amt = totals[cat.id], amt > 0 else { return nil }
            return CategorySpend(categoryName: cat.name, color: cat.color, amount: amt)
        }.sorted { $0.amount > $1.amount }
    }

    // MARK: - Debts

    static let creditCards: [CreditCard] = [
        CreditCard(id: UUID(), cardName: "Amex Gold",       lastFour: "0001", currentBalance: 1420, creditLimit: 5000,  aprPercent: 18.99, minimumPayment: 45),
        CreditCard(id: UUID(), cardName: "Chase Sapphire",  lastFour: "2847", currentBalance: 862,  creditLimit: 10000, aprPercent: 22.49, minimumPayment: 35),
    ]

    static let loans: [Loan] = [
        Loan(id: UUID(), loanName: "Car Loan",     lender: "Wells Fargo",     loanType: "car",      originalPrincipal: 18000, currentBalance: 12680, interestRatePercent: 5.5, minimumPayment: 350),
        Loan(id: UUID(), loanName: "Student Loan", lender: "Federal Direct",  loanType: "student",  originalPrincipal: 25000, currentBalance: 18400, interestRatePercent: 4.5, minimumPayment: 220),
    ]

    static var totalDebt: Double {
        creditCards.reduce(0) { $0 + $1.currentBalance } +
        loans.reduce(0) { $0 + $1.currentBalance }
    }

    static var totalMinPayment: Double {
        creditCards.reduce(0) { $0 + ($1.minimumPayment ?? 0) } +
        loans.reduce(0) { $0 + ($1.minimumPayment ?? 0) }
    }

    // MARK: - Strategies

    static let strategies: [PayoffStrategy] = [
        PayoffStrategy(name: "Avalanche",    monthsToFreedom: 74, totalInterest: 6420, totalPaid: 39782,
                       payoffOrder: ["Chase Sapphire", "Amex Gold", "Car Loan", "Student Loan"]),
        PayoffStrategy(name: "Snowball",     monthsToFreedom: 76, totalInterest: 6812, totalPaid: 40174,
                       payoffOrder: ["Chase Sapphire", "Amex Gold", "Car Loan", "Student Loan"]),
        PayoffStrategy(name: "Hybrid",       monthsToFreedom: 75, totalInterest: 6550, totalPaid: 39912,
                       payoffOrder: ["Chase Sapphire", "Amex Gold", "Car Loan", "Student Loan"]),
        PayoffStrategy(name: "Minimum only", monthsToFreedom: 118, totalInterest: 11250, totalPaid: 44612,
                       payoffOrder: ["—"])
    ]

    // MARK: - Chat

    static let conversations: [ChatConversation] = [
        ChatConversation(id: UUID(), title: "Month overview",     lastMessagePreview: "Your biggest category this month is Food…", updatedAt: Date()),
        ChatConversation(id: UUID(), title: "Debt payoff plan",   lastMessagePreview: "If you push $600/mo to the avalanche…",     updatedAt: Date().addingTimeInterval(-3_600 * 3)),
        ChatConversation(id: UUID(), title: "Weekend spending",   lastMessagePreview: "You spent $214 on dining this weekend.",     updatedAt: Date().addingTimeInterval(-86_400)),
    ]

    static let messages: [ChatMessage] = [
        ChatMessage(id: UUID(), role: .user,      content: "What did I spend the most on this month?", timestamp: Date().addingTimeInterval(-120)),
        ChatMessage(id: UUID(), role: .assistant, content: "Food & Dining is your largest category at $285.64 across 12 transactions — roughly 32% of your $895 total spend this month. Whole Foods ($43) and Joe's Pizza ($19) lead the list. You're at 47% of your $600 Food budget with 9 days left in the month, so you're on track.", timestamp: Date().addingTimeInterval(-80)),
        ChatMessage(id: UUID(), role: .user,      content: "How fast can I pay off the Amex?", timestamp: Date().addingTimeInterval(-45)),
        ChatMessage(id: UUID(), role: .assistant, content: "With a $45 minimum it'd take 45 months and cost $410 in interest. Bump to $120/mo and it's 14 months with $168 interest — saving you $242. Want me to simulate $200/mo?", timestamp: Date().addingTimeInterval(-10)),
    ]

    // MARK: - Recent OCR demo

    static let lastOcr = (
        merchant: "Dunkin'",
        total: 23.15,
        date: "Apr 21, 2026",
        items: ["2 Lg Cold Brew", "4 Caramel Swirl", "4 Oatmilk", "Strawberry Donut"],
        category: "Food & Dining"
    )
}
