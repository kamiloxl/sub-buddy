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

    /// Fallback file when Keychain is unavailable (unsigned builds)
    private var fallbackURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("SubBuddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(".apikey")
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

    // MARK: - Keychain helpers

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: apiKeyAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - File fallback

    private func saveToFallback(_ key: String) -> Bool {
        do {
            try key.write(to: fallbackURL, atomically: true, encoding: .utf8)

            // Restrict file permissions to owner only (600)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fallbackURL.path
            )
            logger.info("API key saved to fallback file")
            return true
        } catch {
            logger.error("Fallback save failed: \(error.localizedDescription)")
            return false
        }
    }

    private func readFromFallback() -> String? {
        guard FileManager.default.fileExists(atPath: fallbackURL.path) else { return nil }
        do {
            let key = try String(contentsOf: fallbackURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? nil : key
        } catch {
            logger.error("Fallback read failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func deleteFallbackFile() {
        try? FileManager.default.removeItem(at: fallbackURL)
    }
}
