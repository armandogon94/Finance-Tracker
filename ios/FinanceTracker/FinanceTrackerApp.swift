//
//  FinanceTrackerApp.swift
//  Finance Tracker — native SwiftUI app targeting iOS 26+.
//
//  The app boots into RootView, which hosts a tab bar. The overall visual
//  language is swappable via the AppTheme environment, configurable at
//  runtime from Settings → Design Playground.
//

import SwiftUI

@main
struct FinanceTrackerApp: App {
    @State private var themeStore = ThemeStore()
    @State private var auth = AuthService()
    @State private var expenses: ExpensesService
    @State private var categories: CategoriesService
    @State private var analytics: AnalyticsService
    @State private var scan: ScanService
    @State private var navigation = AppNavigation()

    init() {
        // Preview harness launch args (see docs/ios-design-previews/capture.sh):
        //   -theme=<liquidGlass|healthCards>    override persisted theme
        //   -skipAuth                           bypass login (uses mock data)
        let args = ProcessInfo.processInfo.arguments
        for a in args where a.hasPrefix("-theme=") {
            let raw = String(a.dropFirst("-theme=".count))
            if let id = ThemeID(rawValue: raw) {
                UserDefaults.standard.set(id.rawValue, forKey: "FinanceTracker.selectedTheme")
            }
        }
        if args.contains("-skipAuth") {
            UserDefaults.standard.set(true, forKey: "FinanceTracker.skipAuth")
        }

        // Construct AuthService first so the other services can reuse its
        // APIClient (same actor = same token provider = one keychain read).
        let authService = AuthService()
        let expensesService = ExpensesService(api: authService.api)
        let categoriesService = CategoriesService(api: authService.api)
        let analyticsService = AnalyticsService(api: authService.api)

        // ScanService routes its uploader/confirmer through APIClient, and
        // its onCreated callback inserts the freshly-saved expense at the
        // top of ExpensesService — so the user sees their new row immediately
        // when ScanView flips them to the Expenses tab.
        let api = authService.api
        let scanService = ScanService(
            uploader: { [weak expensesService] data in
                _ = expensesService // silence unused warning; keep capture pattern uniform
                let resp: ReceiptScanResponseDTO = try await api.uploadMultipart(
                    "/api/v1/receipts/scan",
                    fileName: "receipt.jpg",
                    mimeType: "image/jpeg",
                    fileData: data
                )
                return resp
            },
            confirmer: { request in
                let resp: ReceiptConfirmResponseDTO = try await api.post(
                    "/api/v1/receipts/confirm",
                    body: request
                )
                return resp
            },
            onCreated: { [weak expensesService] resp in
                guard let expensesService else { return }
                let f = DateFormatter()
                f.calendar = Calendar(identifier: .iso8601)
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone.current
                f.dateFormat = "yyyy-MM-dd"
                let expense = Expense(
                    id: resp.expenseId,
                    amount: resp.amount,
                    currency: "USD",
                    description: nil,
                    merchantName: resp.merchantName,
                    categoryId: nil,
                    expenseDate: f.date(from: resp.expenseDate) ?? Date(),
                    hasReceipt: true,
                    ocrMethod: nil
                )
                expensesService.prepend(expense)
            }
        )

        // On signOut, wipe in-memory caches so the next user starts clean.
        authService.onSignOut = { [
            weak expensesService,
            weak categoriesService,
            weak analyticsService,
            weak scanService
        ] in
            expensesService?.reset()
            categoriesService?.reset()
            analyticsService?.reset()
            scanService?.reset()
        }

        self._auth = State(initialValue: authService)
        self._expenses = State(initialValue: expensesService)
        self._categories = State(initialValue: categoriesService)
        self._analytics = State(initialValue: analyticsService)
        self._scan = State(initialValue: scanService)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.appTheme, themeStore.current)
                .environment(themeStore)
                .environment(auth)
                .environment(expenses)
                .environment(categories)
                .environment(analytics)
                .environment(scan)
                .environment(navigation)
                .preferredColorScheme(themeStore.current.preferredColorScheme)
                .task {
                    await auth.restoreSession()
                }
        }
    }
}
