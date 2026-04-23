//
//  ExpensesService.swift
//  Fetches + caches the expense list for the logged-in user. Maps
//  server DTOs onto the UI-facing Expense model, joining in category
//  metadata from CategoriesService.
//

import Foundation
import Observation
import SwiftUI

@Observable @MainActor
final class ExpensesService {
    enum LoadState: Equatable, Sendable {
        case idle, loading, loaded, empty, failed(String)
    }

    private(set) var expenses: [Expense] = []
    private(set) var categories: [Category] = []
    private(set) var state: LoadState = .idle

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Loading

    func loadAll() async {
        state = .loading
        // Trailing slashes matter: FastAPI 307-redirects the non-slash form,
        // and URLSession drops the Authorization header on redirect, which
        // then 401s the follow-up.
        async let expensesTask: ExpenseListResponseDTO = api.get("/api/v1/expenses/")
        async let categoriesTask: [CategoryDTO] = api.get("/api/v1/categories/")

        do {
            let (expensesResp, catDTOs) = try await (expensesTask, categoriesTask)
            self.categories = catDTOs.map { dto in
                let icon = Self.iconSystemName(fromBackendIcon: dto.icon, name: dto.name)
                let color = Self.color(from: dto.color) ?? .gray
                return Category(
                    id: dto.id,
                    name: dto.name,
                    iconSystemName: icon,
                    color: color,
                    monthlyBudget: dto.monthlyBudget,
                    isHidden: dto.isHidden
                )
            }

            self.expenses = expensesResp.items.map { dto in
                Expense(
                    id: dto.id,
                    amount: dto.amount,
                    currency: dto.currency,
                    description: dto.description,
                    merchantName: dto.merchantName,
                    categoryId: dto.categoryId,
                    expenseDate: dto.expenseDate,
                    hasReceipt: dto.receiptImagePath != nil,
                    ocrMethod: dto.ocrMethod
                )
            }
            state = expenses.isEmpty ? .empty : .loaded
        } catch let err as APIError {
            state = .failed(err.errorDescription ?? "Couldn't load expenses.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Mutation

    /// Optimistically add locally, then POST. Rolls back on failure.
    func addExpense(
        amount: Double,
        description: String?,
        merchantName: String?,
        categoryId: UUID?,
        date: Date = Date()
    ) async -> Bool {
        let iso = DateFormatter()
        iso.calendar = Calendar(identifier: .iso8601)
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = TimeZone.current
        iso.dateFormat = "yyyy-MM-dd"

        let body = CreateExpenseDTO(
            amount: amount,
            categoryId: categoryId,
            description: description,
            merchantName: merchantName,
            expenseDate: iso.string(from: date)
        )

        do {
            // Trailing slash matters — FastAPI returns 307 without it on POST,
            // and URLSession drops the body when following redirects.
            let created: ExpenseDTO = try await api.post("/api/v1/expenses/", body: body)
            let expense = Expense(
                id: created.id,
                amount: created.amount,
                currency: created.currency,
                description: created.description,
                merchantName: created.merchantName,
                categoryId: created.categoryId,
                expenseDate: created.expenseDate,
                hasReceipt: false
            )
            expenses.insert(expense, at: 0)
            state = .loaded
            return true
        } catch {
            return false
        }
    }

    // MARK: - Derived values used by the UI

    var totalToday: Double {
        let cal = Calendar.current
        return expenses.filter { cal.isDateInToday($0.expenseDate) }
            .reduce(0) { $0 + $1.amount }
    }

    var totalThisWeek: Double {
        let cal = Calendar.current
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))
        else { return 0 }
        return expenses.filter { $0.expenseDate >= weekStart }
            .reduce(0) { $0 + $1.amount }
    }

    var totalThisMonth: Double {
        let cal = Calendar.current
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date()))
        else { return 0 }
        return expenses.filter { $0.expenseDate >= monthStart }
            .reduce(0) { $0 + $1.amount }
    }

    func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    // MARK: - Mapping helpers

    /// The backend seeds category icons as lucide-react names (utensils,
    /// car, film, …). Map to SF Symbols here.
    private static func iconSystemName(fromBackendIcon icon: String?, name: String) -> String {
        guard let icon else {
            // Fallback based on category name
            return "square.grid.2x2.fill"
        }
        switch icon.lowercased() {
        case "utensils": return "fork.knife"
        case "car": return "car.fill"
        case "shopping-bag", "shoppingbag": return "bag.fill"
        case "film": return "film.fill"
        case "zap": return "bolt.fill"
        case "heart": return "heart.fill"
        case "book": return "book.fill"
        case "user": return "person.fill"
        case "receipt": return "square.grid.2x2.fill"
        case "home": return "house.fill"
        case "coffee": return "cup.and.saucer.fill"
        case "plane": return "airplane"
        case "shirt": return "tshirt.fill"
        case "lightbulb": return "lightbulb.fill"
        case "gift": return "gift.fill"
        case "smartphone": return "iphone"
        case "pill": return "pills.fill"
        case "shopping-cart": return "cart.fill"
        default:
            // If user stored an emoji or SF symbol name, pass-through;
            // SF symbols tolerate unknown names by showing a placeholder.
            return icon
        }
    }

    private static func color(from hex: String?) -> Color? {
        guard let hex, hex.hasPrefix("#"), hex.count == 7 else { return nil }
        let scanner = Scanner(string: String(hex.dropFirst()))
        var rgb: UInt64 = 0
        guard scanner.scanHexInt64(&rgb) else { return nil }
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
