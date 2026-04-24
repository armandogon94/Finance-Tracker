//
//  CategoriesService.swift
//  Owns the category list for the logged-in user. Replaces the
//  `categories` state that used to live on ExpensesService.
//
//  Public API mirrors ExpensesService style:
//    loadAll() / create(...) / update(...) / archive(...) / reorder(...)
//  All mutating methods return a Bool (or the created row); none throw
//  to the UI so views can render inline errors without a do/catch.
//

import Foundation
import Observation
import SwiftUI

@Observable @MainActor
final class CategoriesService {
    enum LoadState: Equatable, Sendable {
        case idle, loading, loaded, empty, failed(String)
    }

    private(set) var categories: [Category] = []
    private(set) var state: LoadState = .idle

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Load

    func loadAll() async {
        state = .loading
        do {
            let dtos: [CategoryDTO] = try await api.get("/api/v1/categories/")
            categories = dtos.map(Self.mapToCategory)
            state = categories.isEmpty ? .empty : .loaded
        } catch let err as APIError {
            state = .failed(err.errorDescription ?? "Couldn't load categories.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Mutations

    /// POSTs to `/categories/` and appends the new row on success.
    /// Returns the created row so callers can clear their form.
    func create(
        name: String,
        icon: String?,
        color: String?,
        monthlyBudget: Double?
    ) async -> Category? {
        do {
            let body = CreateCategoryDTO(
                name: name,
                icon: icon,
                color: color,
                monthlyBudget: monthlyBudget
            )
            let created: CategoryDTO = try await api.post("/api/v1/categories/", body: body)
            let mapped = Self.mapToCategory(created)
            categories.append(mapped)
            if state == .empty { state = .loaded }
            return mapped
        } catch {
            return nil
        }
    }

    /// PATCHes the given category. Replaces the row in-place on success;
    /// leaves local state untouched on failure so the UI can show an
    /// inline error without ghost rows. Note: individual-resource route
    /// uses NO trailing slash (collection does).
    func update(id: UUID, patch: UpdateCategoryDTO) async -> Bool {
        do {
            let updated: CategoryDTO = try await api.patch("/api/v1/categories/\(id.uuidString)", body: patch)
            let mapped = Self.mapToCategory(updated)
            if let idx = categories.firstIndex(where: { $0.id == id }) {
                categories[idx] = mapped
            }
            return true
        } catch {
            return false
        }
    }

    /// Soft-deletes (is_active=false) on the server. Subsequent GETs
    /// omit the row, so we mirror that by removing from the local cache.
    func archive(id: UUID) async -> Bool {
        do {
            try await api.delete("/api/v1/categories/\(id.uuidString)")
            categories.removeAll { $0.id == id }
            if categories.isEmpty && state == .loaded { state = .empty }
            return true
        } catch {
            return false
        }
    }

    /// PUTs to `/categories/reorder` with an ordered list of ids; the
    /// backend derives sort_order from array index and returns the full
    /// list in the new order. We swap local state with the fresh response.
    func reorder(orderedIds: [UUID]) async -> Bool {
        // Snapshot for rollback if the request fails
        let snapshot = categories
        // Optimistically reorder locally so the UI feels instant
        categories.sort { lhs, rhs in
            let li = orderedIds.firstIndex(of: lhs.id) ?? .max
            let ri = orderedIds.firstIndex(of: rhs.id) ?? .max
            return li < ri
        }
        do {
            let body = ReorderCategoriesDTO(categoryIds: orderedIds)
            let fresh: [CategoryDTO] = try await api.put("/api/v1/categories/reorder", body: body)
            categories = fresh.map(Self.mapToCategory)
            return true
        } catch {
            categories = snapshot
            return false
        }
    }

    // MARK: - Lookup helper

    func category(for id: UUID?) -> Category? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }

    // MARK: - DTO → model mapping

    /// Keeps the raw backend icon string on the model. Views render it
    /// through `CategoryIcon(name:color:)`, which distinguishes between
    /// seeded lucide names ("utensils") and user-picked emoji ("☕").
    private static func mapToCategory(_ dto: CategoryDTO) -> Category {
        Category(
            id: dto.id,
            name: dto.name,
            iconSystemName: dto.icon ?? "",
            color: Self.color(from: dto.color) ?? Color(red: 0.65, green: 0.68, blue: 0.75),
            monthlyBudget: dto.monthlyBudget,
            isHidden: dto.isHidden
        )
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
