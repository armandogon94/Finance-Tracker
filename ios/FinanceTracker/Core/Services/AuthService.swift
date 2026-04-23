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

    let api: APIClient
    private let tokenStore: KeychainTokenStore

    init(tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.tokenStore = tokenStore
        self.api = APIClient(tokenProvider: tokenStore)
    }

    // MARK: - Bootstrapping

    /// Called once at app launch. If a token is present in Keychain,
    /// try to fetch the current user; otherwise stay signed out.
    func restoreSession() async {
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

    func signOut() {
        tokenStore.wipe()
        status = .signedOut
    }

    // MARK: - Convenience

    var isAuthenticated: Bool {
        if case .signedIn = status { return true }
        return false
    }
}
