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

    // MARK: - Low-level Keychain helpers

    /// Reads a single item. Uses the data-protection keychain (no password prompt on macOS).
    /// Falls back to the legacy keychain if not found, and migrates the item on success.
    private func readKeychain(account: String) -> String? {
        if let value = readKeychainRaw(account: account, dataProtection: true) {
            return value
        }
        // Migrate legacy item to data-protection keychain (one-time, prompts once per item)
        if let value = readKeychainRaw(account: account, dataProtection: false) {
            logger.info("Migrating keychain item '\(account)' to data-protection keychain")
            if let data = value.data(using: .utf8) {
                writeKeychainRaw(account: account, data: data)
                deleteLegacyKeychain(account: account)
            }
            return value
        }
        return nil
    }

    private func readKeychainRaw(account: String, dataProtection: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if dataProtection {
            query[kSecUseDataProtectionKeychain as String] = true
        }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    /// Saves to the data-protection keychain (no password prompt on macOS).
    @discardableResult
    private func writeKeychainRaw(account: String, data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecUseDataProtectionKeychain as String: true
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.warning("Keychain write failed for '\(account)' (status \(status))")
        }
        return status == errSecSuccess
    }

    private func deleteFromKeychain(account: String) {
        deleteLegacyKeychain(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func deleteLegacyKeychain(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - API Key

    func saveAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        deleteFromKeychain(account: apiKeyAccount)
        if writeKeychainRaw(account: apiKeyAccount, data: data) {
            logger.info("API key saved to Keychain")
            cachedKey = key
            deleteFallbackFile()
            return true
        }
        logger.warning("Keychain save failed, using fallback file")
        let saved = saveToFallback(key)
        if saved { cachedKey = key }
        return saved
    }

    func getAPIKey() -> String? {
        if let cachedKey { return cachedKey }
        if let key = readKeychain(account: apiKeyAccount) {
            cachedKey = key
            return key
        }
        let fallbackKey = readFromFallback()
        if fallbackKey != nil { cachedKey = fallbackKey }
        return fallbackKey
    }

    @discardableResult
    func deleteAPIKey() -> Bool {
        cachedKey = nil
        deleteFromKeychain(account: apiKeyAccount)
        deleteFallbackFile()
        return true
    }

    // MARK: - Per-project API Key

    @discardableResult
    func saveAPIKey(_ key: String, forProjectId id: UUID) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        let account = "revenuecat-api-key-\(id.uuidString)"
        deleteFromKeychain(account: account)
        if writeKeychainRaw(account: account, data: data) {
            logger.info("API key saved to Keychain for project \(id.uuidString)")
            cachedProjectKeys[id] = key
            return true
        }
        logger.warning("Keychain save failed for project, using fallback")
        let saved = saveToFallback(key, filename: ".apikey-\(id.uuidString)")
        if saved { cachedProjectKeys[id] = key }
        return saved
    }

    func getAPIKey(forProjectId id: UUID) -> String? {
        if let cached = cachedProjectKeys[id] { return cached }
        let account = "revenuecat-api-key-\(id.uuidString)"
        if let key = readKeychain(account: account) {
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
        deleteFromKeychain(account: "revenuecat-api-key-\(id.uuidString)")
        deleteFallbackFile(filename: ".apikey-\(id.uuidString)")
        return true
    }

    // MARK: - OpenAI API Key

    private let openAIKeyAccount = "openai-api-key"
    private var cachedOpenAIKey: String?

    @discardableResult
    func saveOpenAIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        deleteFromKeychain(account: openAIKeyAccount)
        if writeKeychainRaw(account: openAIKeyAccount, data: data) {
            logger.info("OpenAI key saved to Keychain")
            cachedOpenAIKey = key
            return true
        }
        logger.warning("Keychain save failed for OpenAI key, using fallback")
        let saved = saveToFallback(key, filename: ".openai-apikey")
        if saved { cachedOpenAIKey = key }
        return saved
    }

    func getOpenAIKey() -> String? {
        if let cachedOpenAIKey { return cachedOpenAIKey }
        if let key = readKeychain(account: openAIKeyAccount) {
            cachedOpenAIKey = key
            return key
        }
        let fallbackKey = readFromFallback(filename: ".openai-apikey")
        if let fallbackKey { cachedOpenAIKey = fallbackKey }
        return fallbackKey
    }

    @discardableResult
    func deleteOpenAIKey() -> Bool {
        cachedOpenAIKey = nil
        deleteFromKeychain(account: openAIKeyAccount)
        deleteFallbackFile(filename: ".openai-apikey")
        return true
    }

    // MARK: - AppsFlyer API Token (per project)

    private var cachedAppsFlyerTokens: [UUID: String] = [:]

    @discardableResult
    func saveAppsFlyerToken(_ token: String, forProjectId id: UUID) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let account = "appsflyer-api-token-\(id.uuidString)"
        deleteFromKeychain(account: account)
        if writeKeychainRaw(account: account, data: data) {
            logger.info("AppsFlyer token saved to Keychain for project \(id.uuidString)")
            cachedAppsFlyerTokens[id] = token
            return true
        }
        logger.warning("Keychain save failed for AppsFlyer token, using fallback")
        let saved = saveToFallback(token, filename: ".af-token-\(id.uuidString)")
        if saved { cachedAppsFlyerTokens[id] = token }
        return saved
    }

    func getAppsFlyerToken(forProjectId id: UUID) -> String? {
        if let cached = cachedAppsFlyerTokens[id] { return cached }
        let account = "appsflyer-api-token-\(id.uuidString)"
        if let token = readKeychain(account: account) {
            cachedAppsFlyerTokens[id] = token
            return token
        }
        let fallbackToken = readFromFallback(filename: ".af-token-\(id.uuidString)")
        if let fallbackToken { cachedAppsFlyerTokens[id] = fallbackToken }
        return fallbackToken
    }

    @discardableResult
    func deleteAppsFlyerToken(forProjectId id: UUID) -> Bool {
        cachedAppsFlyerTokens.removeValue(forKey: id)
        deleteFromKeychain(account: "appsflyer-api-token-\(id.uuidString)")
        deleteFallbackFile(filename: ".af-token-\(id.uuidString)")
        return true
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
