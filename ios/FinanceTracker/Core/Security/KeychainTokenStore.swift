//
//  KeychainTokenStore.swift
//  Persists the access + refresh tokens in the iOS Keychain. Uses
//  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` so tokens
//  survive reboots, aren't synced to other devices, and aren't
//  readable while the device is locked. Conforms to TokenProvider
//  so APIClient can read the current access token on every request.
//

import Foundation
import Security

protocol TokenStore: AnyObject, Sendable {
    func loadAccessToken() -> String?
    func loadRefreshToken() -> String?
    func save(access: String?, refresh: String?) throws
    func wipe()
}

final class KeychainTokenStore: TokenStore, TokenProvider, @unchecked Sendable {
    private let service: String
    private let accessKey = "access_token"
    private let refreshKey = "refresh_token"
    private let queue = DispatchQueue(label: "KeychainTokenStore", attributes: .concurrent)

    init(service: String = "com.armandointeligencia.FinanceTracker") {
        self.service = service
    }

    // MARK: - TokenProvider

    func currentAccessToken() -> String? {
        queue.sync { readItem(key: accessKey) }
    }

    func updateAccessToken(_ token: String?) async {
        queue.sync(flags: .barrier) {
            if let token { try? writeItem(key: accessKey, value: token) }
            else { deleteItem(key: accessKey) }
        }
    }

    // MARK: - TokenStore

    func loadAccessToken() -> String? {
        queue.sync { readItem(key: accessKey) }
    }
    func loadRefreshToken() -> String? {
        queue.sync { readItem(key: refreshKey) }
    }
    func save(access: String?, refresh: String?) throws {
        try queue.sync(flags: .barrier) {
            if let access { try writeItem(key: accessKey, value: access) } else { deleteItem(key: accessKey) }
            if let refresh { try writeItem(key: refreshKey, value: refresh) } else { deleteItem(key: refreshKey) }
        }
    }
    func wipe() {
        queue.sync(flags: .barrier) {
            deleteItem(key: accessKey)
            deleteItem(key: refreshKey)
        }
    }

    // MARK: - Keychain primitives

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private func readItem(key: String) -> String? {
        var q = baseQuery(key: key)
        q[kSecReturnData as String] = kCFBooleanTrue
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    private func writeItem(key: String, value: String) throws {
        let data = Data(value.utf8)
        let q = baseQuery(key: key)

        // Update first, fall back to add.
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(q as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw NSError(domain: "KeychainTokenStore", code: Int(updateStatus))
        }

        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw NSError(domain: "KeychainTokenStore", code: Int(addStatus))
        }
    }

    private func deleteItem(key: String) {
        SecItemDelete(baseQuery(key: key) as CFDictionary)
    }
}
