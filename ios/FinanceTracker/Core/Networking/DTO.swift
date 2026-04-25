//
//  DTO.swift
//  Wire-format types that directly mirror the FastAPI Pydantic schemas.
//  Kept separate from the UI-facing model structs in Models/Models.swift —
//  services translate DTO → model so the UI never has to know JSON key
//  shapes. All property names use Swift camelCase via CodingKeys.
//

import Foundation

// MARK: - Auth

struct TokenResponseDTO: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

struct LoginRequestDTO: Encodable, Sendable {
    let email: String
    let password: String
}

struct RegisterRequestDTO: Encodable, Sendable {
    let email: String
    let password: String
    let displayName: String?
    let currency: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case email, password, currency, timezone
        case displayName = "display_name"
    }
}

struct UserDTO: Decodable, Sendable {
    let id: UUID
    let email: String
    let displayName: String?
    let currency: String
    let timezone: String
    let isActive: Bool
    let isSuperuser: Bool
    /// Account creation date — optional so we don't blow up if the backend
    /// version we're talking to doesn't expose it. Used by SettingsView for
    /// the "Member since {month year}" subtitle.
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, currency, timezone
        case displayName = "display_name"
        case isActive = "is_active"
        case isSuperuser = "is_superuser"
        case createdAt = "created_at"
    }
}

// MARK: - Categories

struct CategoryDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let icon: String?
    let color: String?
    let monthlyBudget: Double?
    let isHidden: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color
        case monthlyBudget = "monthly_budget"
        case isHidden = "is_hidden"
        case sortOrder = "sort_order"
    }
}

/// POST body for `/api/v1/categories/`. Only `name` is required; the
/// backend fills icon/color with sensible defaults ("receipt" / "#3B82F6").
struct CreateCategoryDTO: Encodable, Sendable {
    let name: String
    let icon: String?
    let color: String?
    let monthlyBudget: Double?

    enum CodingKeys: String, CodingKey {
        case name, icon, color
        case monthlyBudget = "monthly_budget"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(monthlyBudget, forKey: .monthlyBudget)
    }
}

/// PATCH body for `/api/v1/categories/{id}`. Every property is optional;
/// nil values are OMITTED from the JSON (not sent as null) so the
/// backend's exclude-unset Pydantic model leaves those fields alone.
struct UpdateCategoryDTO: Encodable, Sendable {
    let name: String?
    let icon: String?
    let color: String?
    let monthlyBudget: Double?
    let isHidden: Bool?

    enum CodingKeys: String, CodingKey {
        case name, icon, color
        case monthlyBudget = "monthly_budget"
        case isHidden = "is_hidden"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(monthlyBudget, forKey: .monthlyBudget)
        try c.encodeIfPresent(isHidden, forKey: .isHidden)
    }
}

/// PUT body for `/api/v1/categories/reorder`. The backend accepts an
/// ordered list of IDs and derives `sort_order` from the array index —
/// simpler than sending per-row sort_order.
struct ReorderCategoriesDTO: Encodable, Sendable {
    let categoryIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case categoryIds = "category_ids"
    }
}

// MARK: - Expenses

struct ExpenseDTO: Decodable, Sendable {
    let id: UUID
    let categoryId: UUID?
    let amount: Double
    let currency: String
    let description: String?
    let merchantName: String?
    let expenseDate: Date
    let receiptImagePath: String?
    let ocrMethod: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, currency, description
        case categoryId = "category_id"
        case merchantName = "merchant_name"
        case expenseDate = "expense_date"
        case receiptImagePath = "receipt_image_path"
        case ocrMethod = "ocr_method"
    }
}

struct ExpenseListResponseDTO: Decodable, Sendable {
    let items: [ExpenseDTO]
    let total: Int
}

struct CreateExpenseDTO: Encodable, Sendable {
    let amount: Double
    let categoryId: UUID?
    let description: String?
    let merchantName: String?
    let expenseDate: String  // "YYYY-MM-DD"

    enum CodingKeys: String, CodingKey {
        case amount, description
        case categoryId = "category_id"
        case merchantName = "merchant_name"
        case expenseDate = "expense_date"
    }
}

/// PATCH body for /api/v1/expenses/{id}/. Every property is optional;
/// nil values are OMITTED from the JSON (not sent as null) so the
/// backend's exclude-unset Pydantic model leaves those fields alone.
struct UpdateExpenseDTO: Encodable, Sendable {
    let amount: Double?
    let categoryId: UUID?
    let description: String?
    let merchantName: String?
    let expenseDate: String?  // "YYYY-MM-DD"

    enum CodingKeys: String, CodingKey {
        case amount, description
        case categoryId = "category_id"
        case merchantName = "merchant_name"
        case expenseDate = "expense_date"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(categoryId, forKey: .categoryId)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(merchantName, forKey: .merchantName)
        try c.encodeIfPresent(expenseDate, forKey: .expenseDate)
    }
}

// MARK: - Analytics

/// `GET /api/v1/analytics/monthly?year=YYYY` response.
/// Always returns 12 entries; months without spend show `total: 0`.
struct MonthlyAnalyticsResponseDTO: Decodable, Sendable {
    let year: Int
    let data: [MonthlyAnalyticsRowDTO]
}

struct MonthlyAnalyticsRowDTO: Decodable, Sendable, Equatable {
    let month: Int       // 1-12
    let total: Double
    let count: Int
}

/// `GET /api/v1/analytics/by-category?start_date=&end_date=` response.
/// `category_id` is null for the synthetic "Uncategorized" bucket.
struct CategoryBreakdownResponseDTO: Decodable, Sendable {
    let data: [CategoryBreakdownRowDTO]
    let grandTotal: Double
    let startDate: String?
    let endDate: String?

    enum CodingKeys: String, CodingKey {
        case data
        case grandTotal = "grand_total"
        case startDate  = "start_date"
        case endDate    = "end_date"
    }
}

struct CategoryBreakdownRowDTO: Decodable, Sendable, Identifiable {
    let categoryId: UUID?       // nil for "Uncategorized"
    let categoryName: String
    let color: String
    let icon: String
    let total: Double
    let count: Int
    let percentage: Double

    var id: String { categoryId?.uuidString ?? "uncategorized" }

    enum CodingKeys: String, CodingKey {
        case categoryId   = "category_id"
        case categoryName = "category_name"
        case color, icon, total, count, percentage
    }
}
