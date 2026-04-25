//
//  ScanTests.swift
//  Slice 7 — verifies the OCR DTO decoding (real shapes from
//  POST /api/v1/receipts/scan), the ImageCompressor pure function, and
//  ScanService's state machine with injectable uploader + confirmer
//  closures so we don't need a fake APIClient.
//

import XCTest
import UIKit
@testable import FinanceTracker

@MainActor
final class ScanTests: XCTestCase {

    // MARK: - DTO decoding

    func testReceiptScanResponseDTODecodes() throws {
        // Real fixture from POST /api/v1/receipts/scan with target.jpg.
        let json = """
        {
          "temp_id": "572e6e9c-39a8-4cf2-9123-40bd28cdfa8d",
          "image_path": "/data/receipts/u/2026/04/572e6e9c_original.jpg",
          "thumbnail_path": "/data/receipts/u/2026/04/572e6e9c_thumb.jpg",
          "file_size": 24865,
          "ocr_data": {
            "merchant_name": "TARGET",
            "date": "2026-04-25",
            "total_amount": 18.42,
            "currency": "USD",
            "items": [],
            "payment_method": "VISA",
            "category_suggestion": "Shopping",
            "raw_text": "TARGET\\n2026-04-25\\nTOTAL $18.42\\n",
            "method": "claude",
            "confidence": "high",
            "needs_review": false
          },
          "ocr_method": "claude",
          "needs_review": false
        }
        """.data(using: .utf8)!

        let resp = try APIClient.makeDecoder().decode(ReceiptScanResponseDTO.self, from: json)
        XCTAssertEqual(resp.tempId.uuidString.lowercased(), "572e6e9c-39a8-4cf2-9123-40bd28cdfa8d")
        XCTAssertEqual(resp.fileSize, 24865)
        XCTAssertFalse(resp.needsReview)
        XCTAssertEqual(resp.ocrData.merchantName, "TARGET")
        XCTAssertEqual(try XCTUnwrap(resp.ocrData.totalAmount), 18.42, accuracy: 0.001)
        XCTAssertEqual(resp.ocrData.confidence, "high")
        XCTAssertEqual(resp.ocrData.method, "claude")
    }

    func testReceiptScanResponseDTODecodesLowConfidenceWithNullFields() throws {
        // Real fixture from when Tesseract can't read a blurry photo. Most
        // of ocr_data is null/empty — the iOS UI must not crash on this.
        let json = """
        {
          "temp_id": "11111111-1111-1111-1111-111111111111",
          "image_path": "/data/receipts/u/2026/04/blurry.jpg",
          "thumbnail_path": null,
          "file_size": 12000,
          "ocr_data": {
            "merchant_name": null,
            "date": null,
            "total_amount": null,
            "currency": null,
            "items": [],
            "payment_method": null,
            "category_suggestion": null,
            "raw_text": "garbled\\n",
            "method": "tesseract",
            "confidence": "low",
            "needs_review": true
          },
          "ocr_method": "tesseract",
          "needs_review": true
        }
        """.data(using: .utf8)!

        let resp = try APIClient.makeDecoder().decode(ReceiptScanResponseDTO.self, from: json)
        XCTAssertNil(resp.ocrData.merchantName)
        XCTAssertNil(resp.ocrData.totalAmount)
        XCTAssertTrue(resp.needsReview)
    }

    // MARK: - ImageCompressor

    func testImageCompressorProducesJpegUnderTwoMegabytes() {
        // Build a 4032×3024 image (rough iPhone main camera resolution).
        // White-fill, no draws — keeps it predictable across CI hardware.
        let size = CGSize(width: 4032, height: 3024)
        let renderer = UIGraphicsImageRenderer(size: size)
        let big = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            // A few rectangles so the compressed JPEG isn't trivially 0 bytes.
            for i in 0..<20 {
                ctx.fill(CGRect(x: CGFloat(i) * 100, y: 200, width: 50, height: 30))
            }
        }
        let data = ImageCompressor.compress(big, maxDimension: 2048, quality: 0.7)
        XCTAssertNotNil(data)
        XCTAssertLessThan(data!.count, 2_000_000, "compressed receipt should fit under 2 MB")
        // First two bytes of a JPEG are 0xFF 0xD8 (SOI marker).
        XCTAssertEqual(data!.first, 0xFF)
        XCTAssertEqual(data![1], 0xD8)
    }

    // MARK: - ScanService state machine

    func testScanServiceTransitionsIdleToUploadingToReviewing() async {
        let fixture = Self.scanFixture()
        let service = ScanService(
            uploader: { _ in
                // Simulate a tiny network delay so we can observe `.uploading`.
                try? await Task.sleep(for: .milliseconds(20))
                return fixture
            },
            confirmer: { _ in fatalError("not called in this test") },
            onCreated: { _ in }
        )

        XCTAssertEqual(service.state, .idle)

        let task = Task { await service.scan(imageData: Data([0xFF, 0xD8, 0xFF, 0xD9])) }
        // While the uploader is sleeping the service should be .uploading.
        try? await Task.sleep(for: .milliseconds(5))
        XCTAssertEqual(service.state, .uploading)

        await task.value
        if case .reviewing(let resp) = service.state {
            XCTAssertEqual(resp.tempId, fixture.tempId)
            XCTAssertEqual(resp.ocrData.merchantName, fixture.ocrData.merchantName)
        } else {
            XCTFail("expected .reviewing, got \(service.state)")
        }
    }

    func testScanServiceFailureRevertsToFailedAndAllowsRetry() async {
        let service = ScanService(
            uploader: { _ in throw APIError.unknown("kaboom") },
            confirmer: { _ in fatalError() },
            onCreated: { _ in }
        )

        await service.scan(imageData: Data([0xFF, 0xD8]))
        if case .failed(let msg) = service.state {
            XCTAssertFalse(msg.isEmpty)
        } else {
            XCTFail("expected .failed, got \(service.state)")
        }

        // Retrying with a now-working uploader transitions to reviewing.
        let fixture = Self.scanFixture()
        service._test_replaceUploader { _ in fixture }
        await service.scan(imageData: Data([0xFF, 0xD8]))
        if case .reviewing = service.state {} else {
            XCTFail("retry should land in reviewing, got \(service.state)")
        }
    }

    func testScanServiceConfirmCallsConfirmerWithEditedFieldsAndResets() async {
        let fixture = Self.scanFixture()
        var capturedRequest: ReceiptConfirmRequestDTO?
        var capturedExpense: ReceiptConfirmResponseDTO?

        let service = ScanService(
            uploader: { _ in fixture },
            confirmer: { req in
                capturedRequest = req
                return ReceiptConfirmResponseDTO(
                    expenseId: UUID(),
                    archiveId: UUID(),
                    amount: req.amount,
                    merchantName: req.merchantName,
                    expenseDate: req.expenseDate ?? "",
                    imagePath: req.imagePath
                )
            },
            onCreated: { resp in capturedExpense = resp }
        )

        // Get into .reviewing first.
        await service.scan(imageData: Data([0xFF, 0xD8]))

        // User edits the OCR'd amount from 18.42 → 19.99 and adds a note.
        let edited = ReceiptConfirmRequestDTO(
            tempId: fixture.tempId,
            imagePath: fixture.imagePath,
            thumbnailPath: fixture.thumbnailPath,
            fileSize: fixture.fileSize,
            categoryId: nil,
            amount: 19.99,
            taxAmount: 0,
            currency: "USD",
            description: "User-added note",
            merchantName: fixture.ocrData.merchantName,
            expenseDate: fixture.ocrData.date,
            notes: nil,
            isTaxDeductible: false,
            ocrData: nil,
            ocrMethod: fixture.ocrMethod,
            ocrConfidence: nil
        )
        await service.confirm(edited)

        XCTAssertEqual(try XCTUnwrap(capturedRequest?.amount), 19.99, accuracy: 0.001, "confirmer must receive the user's edited amount, not the raw OCR amount")
        XCTAssertEqual(capturedRequest?.description, "User-added note")
        XCTAssertNotNil(capturedExpense, "onCreated callback should fire so ExpensesService can insert optimistically")
        XCTAssertEqual(service.state, .idle, "service should reset to idle after a successful save")
    }

    // MARK: - Fixtures

    private static func scanFixture() -> ReceiptScanResponseDTO {
        let json = """
        {
          "temp_id": "572e6e9c-39a8-4cf2-9123-40bd28cdfa8d",
          "image_path": "/data/receipts/u/2026/04/test_original.jpg",
          "thumbnail_path": "/data/receipts/u/2026/04/test_thumb.jpg",
          "file_size": 24865,
          "ocr_data": {
            "merchant_name": "TARGET",
            "date": "2026-04-25",
            "total_amount": 18.42,
            "currency": "USD",
            "items": [],
            "payment_method": "VISA",
            "category_suggestion": "Shopping",
            "raw_text": "TARGET\\n",
            "method": "claude",
            "confidence": "high",
            "needs_review": false
          },
          "ocr_method": "claude",
          "needs_review": false
        }
        """.data(using: .utf8)!
        return try! APIClient.makeDecoder().decode(ReceiptScanResponseDTO.self, from: json)
    }
}
