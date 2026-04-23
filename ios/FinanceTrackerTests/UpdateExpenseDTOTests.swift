//
//  UpdateExpenseDTOTests.swift
//  PATCH semantics for expense updates: nil fields must be OMITTED
//  from the JSON payload, not sent as null. FastAPI uses exclude-unset
//  on the Pydantic model to distinguish "don't change" from "set to null",
//  but we can only express that on the client side by encoding with
//  encodeIfPresent rather than encodeNil.
//

import XCTest
@testable import FinanceTracker

final class UpdateExpenseDTOTests: XCTestCase {

    private func json(of dto: UpdateExpenseDTO) throws -> [String: Any] {
        let data = try JSONEncoder().encode(dto)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testOmitsAllFieldsWhenEveryPropertyIsNil() throws {
        let dto = UpdateExpenseDTO(
            amount: nil,
            categoryId: nil,
            description: nil,
            merchantName: nil,
            expenseDate: nil
        )
        let body = try json(of: dto)
        XCTAssertEqual(body.count, 0, "Expected empty object so PATCH leaves every server-side field untouched, got \(body)")
    }

    func testEncodesOnlyTheAmountWhenAllOtherFieldsAreNil() throws {
        let dto = UpdateExpenseDTO(
            amount: 12.34,
            categoryId: nil,
            description: nil,
            merchantName: nil,
            expenseDate: nil
        )
        let body = try json(of: dto)
        XCTAssertEqual(body.keys.sorted(), ["amount"])
        XCTAssertEqual(body["amount"] as? Double, 12.34)
    }

    func testSnakeCaseKeysMatchBackendContract() throws {
        let catId = UUID()
        let dto = UpdateExpenseDTO(
            amount: 5,
            categoryId: catId,
            description: "Coffee",
            merchantName: "Blue Bottle",
            expenseDate: "2026-04-22"
        )
        let body = try json(of: dto)
        XCTAssertEqual(body.keys.sorted(),
                       ["amount", "category_id", "description", "expense_date", "merchant_name"])
        XCTAssertEqual(body["amount"] as? Double, 5)
        XCTAssertEqual(body["category_id"] as? String, catId.uuidString)
        XCTAssertEqual(body["description"] as? String, "Coffee")
        XCTAssertEqual(body["merchant_name"] as? String, "Blue Bottle")
        XCTAssertEqual(body["expense_date"] as? String, "2026-04-22")
    }
}
