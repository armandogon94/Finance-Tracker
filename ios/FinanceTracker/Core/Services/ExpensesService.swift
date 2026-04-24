//
//  ExpensesService.swift
//  Fetches + caches the expense list for the logged-in user.
//  Categories live on `CategoriesService` (see Slice 4 extraction);
//  views that need both inject both services via @Environment.
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
    private(set) var state: LoadState = .idle

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Loading

    func loadAll() async {
        state = .loading
        do {
            // Trailing slash: FastAPI 307-redirects the non-slash form and
            // URLSession drops Authorization on redirect. Use canonical.
            let expensesResp: ExpenseListResponseDTO = try await api.get("/api/v1/expenses/")
            self.expenses = expensesResp.items.map(Self.mapToExpense)
            state = expenses.isEmpty ? .empty : .loaded
        } catch let err as APIError {
            state = .failed(err.errorDescription ?? "Couldn't load expenses.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Mutations

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
            let expense = Self.mapToExpense(created)
            expenses.insert(expense, at: 0)
            state = .loaded
            return true
        } catch {
            return false
        }
    }

    /// PATCH an existing expense. Replaces the row in-place on success;
    /// leaves local state untouched on failure so callers can show an
    /// inline error without ghost rows.
    ///
    /// Note on URL shape: the collection route `/expenses/` wants a
    /// trailing slash; the individual-resource routes
    /// `/expenses/{id}` want NO trailing slash (because FastAPI declares
    /// them as `@router.patch("/{id}")`). Using the wrong form forces a
    /// 307 round-trip; our RedirectAuthDelegate handles it, but skip the
    /// dance when we can.
    func updateExpense(id: UUID, patch: UpdateExpenseDTO) async -> Bool {
        do {
            let updated: ExpenseDTO = try await api.patch("/api/v1/expenses/\(id.uuidString)", body: patch)
            let mapped = Self.mapToExpense(updated)
            if let idx = expenses.firstIndex(where: { $0.id == id }) {
                expenses[idx] = mapped
            } else {
                expenses.insert(mapped, at: 0)
            }
            if state == .empty { state = .loaded }
            return true
        } catch {
            return false
        }
    }

    /// DELETE the expense server-side, then remove from the local cache.
    /// Only mutates on success — if the backend rejects, the row stays put.
    func deleteExpense(id: UUID) async -> Bool {
        do {
            try await api.delete("/api/v1/expenses/\(id.uuidString)")
            expenses.removeAll { $0.id == id }
            if expenses.isEmpty && state == .loaded { state = .empty }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Mapping helper

    private static func mapToExpense(_ dto: ExpenseDTO) -> Expense {
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

    // MARK: - Derived totals used by the UI

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
}
