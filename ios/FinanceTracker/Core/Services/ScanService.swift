//
//  ScanService.swift
//  Drives the receipt-OCR flow. Two-step backend contract:
//
//    1. POST /api/v1/receipts/scan (multipart/form-data, field `file`)
//         → ReceiptScanResponseDTO { temp_id, image_path, ocr_data, … }
//    2. POST /api/v1/receipts/confirm (application/json)
//         → ReceiptConfirmResponseDTO { expense_id, archive_id, amount, … }
//
//  Step 1 stores the image and runs OCR; step 2 takes the user's edited
//  fields and creates the actual Expense. iOS keeps the user-edit step
//  explicit between them so we never auto-save a Tesseract hallucination.
//
//  Dependencies (uploader / confirmer / onCreated) are injected as
//  closures so unit tests can drive the state machine with in-memory
//  fakes — no fake APIClient, no mock-everything hairball.
//

import Foundation
import Observation

@Observable @MainActor
final class ScanService {
    enum State: Equatable, Sendable {
        case idle
        case uploading
        case reviewing(ReceiptScanResponseDTO)
        case saving
        case failed(String)

        // ReceiptScanResponseDTO isn't Equatable — compare temp_id only.
        // (Plenty for tests; UI never compares two DTOs.)
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.uploading, .uploading), (.saving, .saving): return true
            case (.reviewing(let l), .reviewing(let r)): return l.tempId == r.tempId
            case (.failed(let l), .failed(let r)): return l == r
            default: return false
            }
        }
    }

    private(set) var state: State = .idle

    // Injected dependencies — production wiring threads APIClient through
    // these closures. Tests pass in-memory fakes.
    private var uploader: (Data) async throws -> ReceiptScanResponseDTO
    private let confirmer: (ReceiptConfirmRequestDTO) async throws -> ReceiptConfirmResponseDTO
    private let onCreated: (ReceiptConfirmResponseDTO) -> Void

    init(
        uploader: @escaping (Data) async throws -> ReceiptScanResponseDTO,
        confirmer: @escaping (ReceiptConfirmRequestDTO) async throws -> ReceiptConfirmResponseDTO,
        onCreated: @escaping (ReceiptConfirmResponseDTO) -> Void
    ) {
        self.uploader = uploader
        self.confirmer = confirmer
        self.onCreated = onCreated
    }

    // MARK: - Flow

    func scan(imageData: Data) async {
        state = .uploading
        do {
            let resp = try await uploader(imageData)
            state = .reviewing(resp)
        } catch let err as APIError {
            state = .failed(err.errorDescription ?? "Couldn't read receipt.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func confirm(_ request: ReceiptConfirmRequestDTO) async {
        state = .saving
        do {
            let resp = try await confirmer(request)
            onCreated(resp)
            state = .idle
        } catch let err as APIError {
            state = .failed(err.errorDescription ?? "Couldn't save expense.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Drop the current scan and go back to the capture screen. Called
    /// from the Discard button or after a save propagates.
    func reset() {
        state = .idle
    }

    // MARK: - Test hook

    /// Test-only: swap the uploader between calls so we can simulate
    /// "first attempt failed, retry succeeded" without rebuilding the
    /// service.
    func _test_replaceUploader(_ next: @escaping (Data) async throws -> ReceiptScanResponseDTO) {
        self.uploader = next
    }
}
