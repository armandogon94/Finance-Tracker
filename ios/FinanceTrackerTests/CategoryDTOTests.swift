//
//  CategoryDTOTests.swift
//  Wire-format tests for the three category-write DTOs. PATCH semantics
//  mirror UpdateExpenseDTO: nil fields must be OMITTED from the JSON
//  (not sent as null) so FastAPI's exclude-unset model leaves those
//  fields alone. Reorder payload matches the Pydantic CategoryReorder
//  shape (`{category_ids: [uuid…]}`).
//

import XCTest
@testable import FinanceTracker

final class CategoryDTOTests: XCTestCase {

    private func json<T: Encodable>(of value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - CreateCategoryDTO

    func testCreateCategoryDTOUsesSnakeCaseForMonthlyBudget() throws {
        let dto = CreateCategoryDTO(
            name: "Coffee",
            icon: "☕",
            color: "#F59E0B",
            monthlyBudget: 75
        )
        let body = try json(of: dto)
        XCTAssertEqual(body["name"] as? String, "Coffee")
        XCTAssertEqual(body["icon"] as? String, "☕")
        XCTAssertEqual(body["color"] as? String, "#F59E0B")
        XCTAssertEqual(body["monthly_budget"] as? Double, 75)
        XCTAssertNil(body["monthlyBudget"], "monthlyBudget must be serialised as monthly_budget for FastAPI")
    }

    func testCreateCategoryDTOOmitsOptionalFieldsWhenNil() throws {
        let dto = CreateCategoryDTO(name: "Gym", icon: nil, color: nil, monthlyBudget: nil)
        let body = try json(of: dto)
        XCTAssertEqual(body.keys.sorted(), ["name"])
        XCTAssertEqual(body["name"] as? String, "Gym")
    }

    // MARK: - UpdateCategoryDTO (PATCH)

    func testUpdateCategoryDTOProducesEmptyObjectWhenAllFieldsNil() throws {
        let dto = UpdateCategoryDTO(
            name: nil, icon: nil, color: nil, monthlyBudget: nil, isHidden: nil
        )
        let body = try json(of: dto)
        XCTAssertEqual(body.count, 0, "Expected empty object so PATCH leaves every server-side field untouched, got \(body)")
    }

    func testUpdateCategoryDTOEncodesOnlyIsHiddenWhenOthersNil() throws {
        let dto = UpdateCategoryDTO(
            name: nil, icon: nil, color: nil, monthlyBudget: nil, isHidden: true
        )
        let body = try json(of: dto)
        XCTAssertEqual(body.keys.sorted(), ["is_hidden"])
        XCTAssertEqual(body["is_hidden"] as? Bool, true)
    }

    func testUpdateCategoryDTOSerialisesAllFieldsInSnakeCase() throws {
        let dto = UpdateCategoryDTO(
            name: "Coffee",
            icon: "☕",
            color: "#F59E0B",
            monthlyBudget: 100,
            isHidden: false
        )
        let body = try json(of: dto)
        XCTAssertEqual(body.keys.sorted(),
                       ["color", "icon", "is_hidden", "monthly_budget", "name"])
        XCTAssertEqual(body["name"] as? String, "Coffee")
        XCTAssertEqual(body["icon"] as? String, "☕")
        XCTAssertEqual(body["color"] as? String, "#F59E0B")
        XCTAssertEqual(body["monthly_budget"] as? Double, 100)
        XCTAssertEqual(body["is_hidden"] as? Bool, false)
    }

    // MARK: - ReorderCategoriesDTO

    func testReorderCategoriesDTOEncodesCategoryIdsArray() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let dto = ReorderCategoriesDTO(categoryIds: [a, b, c])
        let body = try json(of: dto)
        XCTAssertEqual(body.keys.sorted(), ["category_ids"])
        let ids = try XCTUnwrap(body["category_ids"] as? [String])
        XCTAssertEqual(ids, [a.uuidString, b.uuidString, c.uuidString])
    }
}
