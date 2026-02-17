import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.subbuddy.app", category: "Keychain")

final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.subbuddy.app"
    private let apiKeyAccount = "revenuecat-api-key"

    /// In-memory cache to avoid repeated Keychain reads (and system password prompts)
    private var cachedKey: String?
    private var cachedProjectKeys: [UUID: String] = [:]

    /// Fallback URL for legacy single API key
    private var fallbackURL: URL {
        fallbackDir.appendingPathComponent(".apikey")
    }

    private init() {}

    // MARK: - API Key

    func saveAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        deleteFromKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            logger.info("API key saved to Keychain")
            cachedKey = key
            deleteFallbackFile()
            return true
        }

        logger.warning("Keychain save failed (status \(status)), using fallback file")
        let saved = saveToFallback(key)
        if saved { cachedKey = key }
        return saved
    }

    func getAPIKey() -> String? {
        if let cachedKey { return cachedKey }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            cachedKey = key
            return key
        }

        if status != errSecItemNotFound {
            logger.debug("Keychain read status: \(status), trying fallback")
        }

        let fallbackKey = readFromFallback()
        if fallbackKey != nil { cachedKey = fallbackKey }
        return fallbackKey
    }

    @discardableResult
    func deleteAPIKey() -> Bool {
        cachedKey = nil
        deleteFromKeychain()
        deleteFallbackFile()
        return true
    }

    // MARK: - Per-project API Key

    @discardableResult
    func saveAPIKey(_ key: String, forProjectId id: UUID) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        let account = "revenuecat-api-key-\(id.uuidString)"
        deleteFromKeychain(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            logger.info("API key saved to Keychain for project \(id.uuidString)")
            cachedProjectKeys[id] = key
            return true
        }

        logger.warning("Keychain save failed for project (status \(status)), using fallback")
        let saved = saveToFallback(key, filename: ".apikey-\(id.uuidString)")
        if saved { cachedProjectKeys[id] = key }
        return saved
    }

    func getAPIKey(forProjectId id: UUID) -> String? {
        if let cached = cachedProjectKeys[id] { return cached }

        let account = "revenuecat-api-key-\(id.uuidString)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            cachedProjectKeys[id] = key
            return key
        }

        let fallbackKey = readFromFallback(filename: ".apikey-\(id.uuidString)")
        if let fallbackKey { cachedProjectKeys[id] = fallbackKey }
        return fallbackKey
    }

    @discardableResult
    func deleteAPIKey(forProjectId id: UUID) -> Bool {
        cachedProjectKeys.removeValue(forKey: id)
        let account = "revenuecat-api-key-\(id.uuidString)"
        deleteFromKeychain(account: account)
        deleteFallbackFile(filename: ".apikey-\(id.uuidString)")
        return true
    }

    // MARK: - Keychain helpers

    private func deleteFromKeychain() {
        deleteFromKeychain(account: apiKeyAccount)
    }

    private func deleteFromKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - File fallback

    private var fallbackDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SubBuddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func saveToFallback(_ key: String) -> Bool {
        saveToFallback(key, filename: ".apikey")
    }

    private func saveToFallback(_ key: String, filename: String) -> Bool {
        let url = fallbackDir.appendingPathComponent(filename)
        do {
            try key.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            logger.info("API key saved to fallback file: \(filename)")
            return true
        } catch {
            logger.error("Fallback save failed: \(error.localizedDescription)")
            return false
        }
    }

    private func readFromFallback() -> String? {
        readFromFallback(filename: ".apikey")
    }

    private func readFromFallback(filename: String) -> String? {
        let url = fallbackDir.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let key = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : key
        } catch {
            logger.error("Fallback read failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func deleteFallbackFile() {
        deleteFallbackFile(filename: ".apikey")
    }

    private func deleteFallbackFile(filename: String) {
        let url = fallbackDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }
}
