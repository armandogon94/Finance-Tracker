//
//  ScanView.swift
//  Slice 7 — real receipt scan flow on top of ScanService.
//
//  States:
//    .idle      → "Scan a receipt" + Library / Camera buttons
//    .uploading → ProgressView with "Reading your receipt…"
//    .reviewing → editable form prefilled from OCR (amount/merchant/date/category)
//    .saving    → button shows "Saving…" with spinner
//    .failed    → error card with retry button
//
//  After a successful save: ExpensesService inserts the new row at the
//  top of its cache and AppNavigation flips to the Expenses tab so the
//  user sees their expense immediately.
//

import SwiftUI
import UIKit

struct ScanView: View {
    @Environment(\.appTheme) private var theme
    @Environment(ScanService.self) private var scan
    @Environment(CategoriesService.self) private var cats
    @Environment(AppNavigation.self) private var nav

    // Local form state — populated from the OCR response when we enter
    // .reviewing, then edited freely until the user taps Save.
    @State private var amountText = ""
    @State private var merchant = ""
    @State private var description = ""
    @State private var expenseDate = Date()
    @State private var categoryId: UUID?
    @State private var showLibraryPicker = false
    @State private var showCameraPicker = false
    @State private var pickedImage: UIImage?

    @State private var pickedFeedback = 0
    @State private var savedFeedback = 0
    @State private var errorFeedback = 0

    var body: some View {
        NavigationStack {
            ZStack {
                ThemedBackdrop()
                content
            }
            .navigationTitle("Scan receipt")
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .libraryPicker(isPresented: $showLibraryPicker) { img in
            pickedImage = img
            pickedFeedback += 1
            Task { await runScan(on: img) }
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraPicker(
                onPick: { img in
                    showCameraPicker = false
                    pickedImage = img
                    pickedFeedback += 1
                    Task { await runScan(on: img) }
                },
                onCancel: { showCameraPicker = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: scan.state) { _, new in
            if case .reviewing(let resp) = new {
                prefill(from: resp)
            }
        }
        .sensoryFeedback(.selection, trigger: pickedFeedback)
        .sensoryFeedback(.success, trigger: savedFeedback)
        .sensoryFeedback(.error, trigger: errorFeedback)
    }

    // MARK: - State router

    @ViewBuilder
    private var content: some View {
        switch scan.state {
        case .idle:
            captureScreen
        case .uploading:
            uploadingScreen
        case .reviewing:
            reviewingScreen
        case .saving:
            reviewingScreen.disabled(true)  // form locked while saving
        case .failed(let msg):
            failedScreen(msg)
        }
    }

    // MARK: - Idle

    private var captureScreen: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(theme.accent)
            VStack(spacing: 6) {
                Text("Scan a receipt")
                    .font(theme.font.title)
                    .foregroundStyle(theme.textPrimary)
                Text("Take a photo or pick one from your library — we'll read the amount, merchant, and date for you.")
                    .font(theme.font.caption)
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            VStack(spacing: 12) {
                primaryButton(label: "Take photo", systemImage: "camera.fill") {
                    showCameraPicker = true
                }
                secondaryButton(label: "Choose from library", systemImage: "photo.on.rectangle") {
                    showLibraryPicker = true
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func primaryButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(label).font(theme.font.titleCompact)
            }
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                    .fill(theme.accent)
            )
        }
    }

    private func secondaryButton(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(label).font(theme.font.bodyMedium)
            }
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous)
                    .fill(theme.surface)
            )
        }
    }

    // MARK: - Uploading

    private var uploadingScreen: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().strokeBorder(theme.accent.opacity(0.25), lineWidth: 8)
                    .frame(width: 120, height: 120)
                Circle().trim(from: 0, to: 0.75)
                    .stroke(theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .rotationEffect(.degrees(360))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: UUID())
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.accent)
            }
            Text("Reading your receipt…")
                .font(theme.font.titleCompact)
                .foregroundStyle(theme.textPrimary)
            Text("Claude Vision is extracting amount, merchant, and date.\nUsually 2–3 seconds.")
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Reviewing

    private var reviewingScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                if case .reviewing(let resp) = scan.state {
                    confidenceBadge(for: resp.ocrData)
                }
                amountCard
                detailsCard
                categoryCard
                dateCard

                if case .saving = scan.state {
                    Text("Saving…")
                        .font(theme.font.caption)
                        .foregroundStyle(theme.textSecondary)
                }

                actionRow
                Spacer(minLength: 30)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func confidenceBadge(for data: ReceiptOcrDataDTO) -> some View {
        let confidence = data.confidence ?? "low"
        let color: Color = {
            switch confidence {
            case "high": return theme.positive
            case "medium": return theme.accent
            default: return theme.negative
            }
        }()
        let label: String = {
            switch confidence {
            case "high": return "High confidence — looks good, double-check the amount"
            case "medium": return "Medium confidence — review the fields below"
            default: return "Low confidence — please verify everything"
            }
        }()
        HStack(spacing: 8) {
            Image(systemName: "sparkles").foregroundStyle(color)
            Text(label).font(theme.font.caption).foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AMOUNT").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$").font(theme.font.title).foregroundStyle(theme.textSecondary)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(theme.font.heroNumeral)
                    .foregroundStyle(theme.textPrimary)
            }
        }
        .padding(18)
        .themedCard()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DETAILS").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            labeledField(icon: "building.2", placeholder: "Merchant", text: $merchant)
            labeledField(icon: "text.bubble", placeholder: "Note (optional)", text: $description)
        }
        .padding(18)
        .themedCard()
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CATEGORY").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    clearChip
                    ForEach(cats.categories) { cat in
                        let active = categoryId == cat.id
                        Button { categoryId = cat.id } label: {
                            HStack(spacing: 6) {
                                CategoryIcon(name: cat.iconSystemName, color: active ? cat.color : theme.textSecondary, pointSize: 12)
                                Text(cat.name)
                            }
                            .font(theme.font.captionMedium)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(active ? cat.color.opacity(0.3) : theme.surface))
                            .foregroundStyle(active ? cat.color : theme.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(18)
        .themedCard()
    }

    private var clearChip: some View {
        let active = categoryId == nil
        return Button { categoryId = nil } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                Text("Uncategorized")
            }
            .font(theme.font.captionMedium)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(active ? theme.accent.opacity(0.3) : theme.surface))
            .foregroundStyle(active ? theme.accent : theme.textSecondary)
        }
    }

    private var dateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DATE").font(theme.font.captionMedium).tracking(1.2).foregroundStyle(theme.textTertiary)
            DatePicker("", selection: $expenseDate, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .tint(theme.accent)
        }
        .padding(18)
        .themedCard()
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                scan.reset()
            } label: {
                Text("Discard")
                    .font(theme.font.bodyMedium)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: theme.radii.button).fill(theme.surface))
                    .foregroundStyle(theme.textPrimary)
            }
            Button(action: saveTapped) {
                HStack(spacing: 6) {
                    if case .saving = scan.state {
                        ProgressView().tint(.black).padding(.trailing, 2)
                    }
                    Text(saveLabel)
                        .font(theme.font.titleCompact)
                        .foregroundStyle(Color.black)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: theme.radii.button).fill(canSave ? theme.accent : theme.accent.opacity(0.4)))
            }
            .disabled(!canSave)
        }
        .padding(.top, 4)
    }

    // MARK: - Failed

    private func failedScreen(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(theme.negative)
            Text("Couldn't scan that receipt")
                .font(theme.font.title)
                .foregroundStyle(theme.textPrimary)
            Text(msg)
                .font(theme.font.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack(spacing: 12) {
                secondaryButton(label: "Cancel", systemImage: "xmark") {
                    scan.reset()
                }
                primaryButton(label: "Try again", systemImage: "arrow.clockwise") {
                    if let img = pickedImage {
                        Task { await runScan(on: img) }
                    } else {
                        scan.reset()
                    }
                }
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Actions

    private func runScan(on image: UIImage) async {
        guard let data = ImageCompressor.compress(image) else {
            errorFeedback += 1
            return
        }
        await scan.scan(imageData: data)
        if case .failed = scan.state { errorFeedback += 1 }
    }

    private func prefill(from resp: ReceiptScanResponseDTO) {
        let ocr = resp.ocrData
        if let amt = ocr.totalAmount, amt > 0 {
            amountText = String(format: "%.2f", amt)
        } else {
            amountText = ""
        }
        merchant = ocr.merchantName?.trimmingCharacters(in: .whitespaces) ?? ""
        description = ""
        if let dateStr = ocr.date, let parsed = Self.parseDate(dateStr) {
            expenseDate = parsed
        } else {
            expenseDate = Date()
        }
        // Try to map the OCR's category_suggestion ("Coffee", "Food & Dining"…)
        // to a real Category by name (case-insensitive). Stays nil if no match.
        if let suggestion = ocr.categorySuggestion?.lowercased() {
            categoryId = cats.categories.first { $0.name.lowercased() == suggestion }?.id
        }
    }

    private func saveTapped() {
        guard let resp = currentResponse, let amt = parsedAmount else { return }
        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
        let dateStr = Self.dateFormatter.string(from: expenseDate)
        let request = ReceiptConfirmRequestDTO(
            tempId: resp.tempId,
            imagePath: resp.imagePath,
            thumbnailPath: resp.thumbnailPath,
            fileSize: resp.fileSize,
            categoryId: categoryId,
            amount: amt,
            taxAmount: 0,
            currency: resp.ocrData.currency ?? "USD",
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            merchantName: trimmedMerchant.isEmpty ? nil : trimmedMerchant,
            expenseDate: dateStr,
            notes: nil,
            isTaxDeductible: false,
            ocrData: resp.ocrData,
            ocrMethod: resp.ocrMethod,
            ocrConfidence: nil
        )
        Task {
            await scan.confirm(request)
            if case .idle = scan.state {
                savedFeedback += 1
                // Tiny delay so the success haptic registers before the tab swap
                try? await Task.sleep(for: .milliseconds(150))
                nav.selectedTab = .expenses
            } else if case .failed = scan.state {
                errorFeedback += 1
            }
        }
    }

    // MARK: - Derived

    private var currentResponse: ReceiptScanResponseDTO? {
        if case .reviewing(let r) = scan.state { return r }
        if case .saving = scan.state {
            // We're saving — the ScanService still holds the response inside
            // its previous .reviewing state, but we can't easily retrieve it.
            // saveTapped() runs from .reviewing, so this branch shouldn't fire.
            return nil
        }
        return nil
    }

    private var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let v = Double(trimmed), v > 0 else { return nil }
        return v
    }

    private var canSave: Bool {
        if case .saving = scan.state { return false }
        return parsedAmount != nil
    }

    private var saveLabel: String {
        if case .saving = scan.state { return "Saving…" }
        return "Save expense"
    }

    private func labeledField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(theme.textTertiary).frame(width: 20)
            TextField(placeholder, text: text)
                .font(theme.font.body)
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: theme.radii.button, style: .continuous).fill(theme.surface))
    }

    // MARK: - Date helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func parseDate(_ s: String) -> Date? {
        dateFormatter.date(from: s)
    }
}

#Preview("Scan — Liquid Glass") {
    let api = APIClient()
    return ScanView()
        .environment(\.appTheme, LiquidGlassTheme())
        .environment(CategoriesService(api: api))
        .environment(ScanService(
            uploader: { _ in fatalError("preview") },
            confirmer: { _ in fatalError("preview") },
            onCreated: { _ in }
        ))
        .environment(AppNavigation())
        .preferredColorScheme(.dark)
}
