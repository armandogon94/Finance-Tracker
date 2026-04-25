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

// MARK: - Receipts (OCR scan + confirm)

/// `POST /api/v1/receipts/scan` (multipart/form-data) response.
/// Backend writes the uploaded image into long-term storage but the
/// expense isn't created yet — it lives in a "pending" bucket keyed
/// by `tempId` until the iOS user calls /receipts/confirm.
struct ReceiptScanResponseDTO: Decodable, Sendable {
    let tempId: UUID
    let imagePath: String
    let thumbnailPath: String?
    let fileSize: Int?
    let ocrData: ReceiptOcrDataDTO
    let ocrMethod: String?
    let needsReview: Bool

    enum CodingKeys: String, CodingKey {
        case tempId         = "temp_id"
        case imagePath      = "image_path"
        case thumbnailPath  = "thumbnail_path"
        case fileSize       = "file_size"
        case ocrData        = "ocr_data"
        case ocrMethod      = "ocr_method"
        case needsReview    = "needs_review"
    }
}

/// Nested `ocr_data` block. Almost every field is optional because Tesseract
/// (the offline fallback) routinely misses everything except `raw_text`.
/// Codable so we can both decode it from /scan and echo it back into the
/// /confirm body verbatim (the backend uses it for telemetry/auditing).
struct ReceiptOcrDataDTO: Codable, Sendable {
    let merchantName: String?
    let date: String?            // backend returns `YYYY-MM-DD`
    let totalAmount: Double?
    let currency: String?
    let paymentMethod: String?
    let categorySuggestion: String?
    let rawText: String?
    let method: String?          // "claude" | "tesseract"
    let confidence: String?      // "low" | "medium" | "high"
    let needsReview: Bool?

    enum CodingKeys: String, CodingKey {
        case merchantName       = "merchant_name"
        case date
        case totalAmount        = "total_amount"
        case currency
        case paymentMethod      = "payment_method"
        case categorySuggestion = "category_suggestion"
        case rawText            = "raw_text"
        case method
        case confidence
        case needsReview        = "needs_review"
    }
}

/// `POST /api/v1/receipts/confirm` body. Carries the temp_id from /scan
/// plus the user's edited fields. Backend creates the actual Expense.
struct ReceiptConfirmRequestDTO: Encodable, Sendable {
    let tempId: UUID
    let imagePath: String
    let thumbnailPath: String?
    let fileSize: Int?
    let categoryId: UUID?
    let amount: Double
    let taxAmount: Double
    let currency: String
    let description: String?
    let merchantName: String?
    let expenseDate: String?      // "YYYY-MM-DD"
    let notes: String?
    let isTaxDeductible: Bool
    let ocrData: ReceiptOcrDataDTO?
    let ocrMethod: String?
    let ocrConfidence: Double?

    enum CodingKeys: String, CodingKey {
        case tempId            = "temp_id"
        case imagePath         = "image_path"
        case thumbnailPath     = "thumbnail_path"
        case fileSize          = "file_size"
        case categoryId        = "category_id"
        case amount
        case taxAmount         = "tax_amount"
        case currency
        case description
        case merchantName      = "merchant_name"
        case expenseDate       = "expense_date"
        case notes
        case isTaxDeductible   = "is_tax_deductible"
        case ocrData           = "ocr_data"
        case ocrMethod         = "ocr_method"
        case ocrConfidence     = "ocr_confidence"
    }
}

/// `POST /api/v1/receipts/confirm` response. Smaller summary than ExpenseDTO —
/// just enough for iOS to insert a row optimistically.
struct ReceiptConfirmResponseDTO: Decodable, Sendable {
    let expenseId: UUID
    let archiveId: UUID
    let amount: Double
    let merchantName: String?
    let expenseDate: String       // "YYYY-MM-DD"
    let imagePath: String

    enum CodingKeys: String, CodingKey {
        case expenseId    = "expense_id"
        case archiveId    = "archive_id"
        case amount
        case merchantName = "merchant_name"
        case expenseDate  = "expense_date"
        case imagePath    = "image_path"
    }
}
