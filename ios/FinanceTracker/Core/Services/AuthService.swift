//
//  AuthService.swift
//  Owns authentication state. Holds the APIClient + KeychainTokenStore.
//  RootView observes isAuthenticated to decide between LoginView and
//  the main tab bar.
//

import Foundation
import Observation

@Observable @MainActor
final class AuthService {
    enum Status: Sendable {
        case signedOut
        case checkingSession
        case signedIn(UserDTO)
    }

    private(set) var status: Status = .signedOut
    private(set) var lastError: APIError?

    /// Optional callback invoked on signOut so the surrounding app can wipe
    /// in-memory caches (ExpensesService, CategoriesService, etc.) without
    /// AuthService needing to know about those services directly.
    @ObservationIgnored
    var onSignOut: (() -> Void)?

    let api: APIClient
    private let tokenStore: any TokenStore & TokenProvider

    init(tokenStore: any TokenStore & TokenProvider = KeychainTokenStore()) {
        self.tokenStore = tokenStore
        self.api = APIClient(tokenProvider: tokenStore)
    }

    /// Test-only hook: seed `status` with a UserDTO so signOut tests don't
    /// need the network. Underscore prefix flags it as not-for-production.
    func _test_seedSignedIn(user: UserDTO) {
        status = .signedIn(user)
    }

    /// Currently-signed-in user, if any. Lets SettingsView read the same
    /// state without unwrapping the enum at every call site.
    var currentUser: UserDTO? {
        if case .signedIn(let u) = status { return u }
        return nil
    }

    // MARK: - Bootstrapping

    /// Called once at app launch. Order of precedence:
    ///   1. `-autoLogin[=email:password]` launch arg — always signs in,
    ///      wiping any existing token first. Dev convenience only.
    ///   2. Existing Keychain token + /auth/me check.
    ///   3. Otherwise stay signed out.
    func restoreSession() async {
        if let creds = Self.autoLoginCredentials() {
            tokenStore.wipe()
            lastError = nil
            _ = await signIn(email: creds.email, password: creds.password)
            return
        }

        guard tokenStore.loadAccessToken() != nil else {
            status = .signedOut
            return
        }
        status = .checkingSession
        do {
            let me: UserDTO = try await api.get("/api/v1/auth/me")
            status = .signedIn(me)
        } catch APIError.unauthorized {
            // Token expired / invalid — wipe and present login.
            tokenStore.wipe()
            status = .signedOut
        } catch {
            // Network/backend unreachable — keep tokens but mark signed out
            // so the user sees the login screen with an error message.
            lastError = error as? APIError ?? .unknown(error.localizedDescription)
            status = .signedOut
        }
    }

    /// Parse `-autoLogin` / `-autoLogin=email:password` launch args.
    /// Returns default dev creds when the bare `-autoLogin` flag is set
    /// so you can re-launch in one tap from a dev scheme.
    private static func autoLoginCredentials() -> (email: String, password: String)? {
        let args = ProcessInfo.processInfo.arguments
        if let raw = args.first(where: { $0.hasPrefix("-autoLogin=") }) {
            let body = String(raw.dropFirst("-autoLogin=".count))
            let parts = body.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (email: parts[0], password: parts[1])
        }
        if args.contains("-autoLogin") {
            return (email: "claude@example.com", password: "ClaudeTest2026!")
        }
        return nil
    }

    // MARK: - Login / register / logout

    func signIn(email: String, password: String) async -> Bool {
        lastError = nil
        do {
            let resp: TokenResponseDTO = try await api.post(
                "/api/v1/auth/login",
                body: LoginRequestDTO(email: email, password: password)
            )
            try tokenStore.save(access: resp.accessToken, refresh: resp.refreshToken)

            let me: UserDTO = try await api.get("/api/v1/auth/me")
            status = .signedIn(me)
            return true
        } catch let err as APIError {
            lastError = err
            return false
        } catch {
            lastError = .unknown(error.localizedDescription)
            return false
        }
    }

    func register(email: String, password: String, displayName: String?) async -> Bool {
        lastError = nil
        do {
            let resp: TokenResponseDTO = try await api.post(
                "/api/v1/auth/register",
                body: RegisterRequestDTO(
                    email: email,
                    password: password,
                    displayName: displayName,
                    currency: "USD",
                    timezone: TimeZone.current.identifier
                )
            )
            try tokenStore.save(access: resp.accessToken, refresh: resp.refreshToken)

            let me: UserDTO = try await api.get("/api/v1/auth/me")
            status = .signedIn(me)
            return true
        } catch let err as APIError {
            lastError = err
            return false
        } catch {
            lastError = .unknown(error.localizedDescription)
            return false
        }
    }

    /// Sign out: clears the keychain, resets status, and lets the surrounding
    /// app wipe its in-memory caches via the `onSignOut` callback. Idempotent
    /// — calling twice is safe and a no-op the second time.
    func signOut() {
        tokenStore.wipe()
        status = .signedOut
        lastError = nil
        onSignOut?()
    }

    // MARK: - Convenience

    var isAuthenticated: Bool {
        if case .signedIn = status { return true }
        return false
    }
}
