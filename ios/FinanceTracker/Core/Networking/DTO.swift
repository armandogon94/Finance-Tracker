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

    enum CodingKeys: String, CodingKey {
        case id, email, currency, timezone
        case displayName = "display_name"
        case isActive = "is_active"
        case isSuperuser = "is_superuser"
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
