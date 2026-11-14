//
//  HAAuthManager.swift
//  Itsyhome
//
//  Home Assistant authentication and credential management
//

import Foundation
import Security
import os.log

private let logger = Logger(subsystem: "com.nickustinov.itsyhome", category: "HAAuthManager")

protocol HAAuthenticationClient: AnyObject {
    func connect() async throws
    func disconnect()
    func getDevices() async throws -> [HADevice]
    func getAreas() async throws -> [HAArea]
}

extension HomeAssistantClient: HAAuthenticationClient {}

final class HAAuthManager {

    // MARK: - Singleton

    static let shared = HAAuthManager()

    // MARK: - Constants

    private let serverURLKey = "HomeAssistantServerURL"
    private let defaults: UserDefaults
    private(set) var tokenStore: HATokenStore
    private let makeClient: (URL, String) throws -> HAAuthenticationClient

    // MARK: - Properties

    /// The Home Assistant server URL
    var serverURL: URL? {
        get {
            guard let urlString = defaults.string(forKey: serverURLKey) else {
                return nil
            }
            return URL(string: urlString)
        }
        set {
            if let url = newValue {
                defaults.set(url.absoluteString, forKey: serverURLKey)
            } else {
                defaults.removeObject(forKey: serverURLKey)
            }
        }
    }

    /// The access token is read from Keychain; save failures are never hidden.
    var accessToken: String? { tokenStore.readToken() }

    /// Transient overrides set by network auto-switch. Not persisted.
    var effectiveServerURLOverride: URL?
    var effectiveAccessTokenOverride: String?

    /// The URL to connect to: override if set, otherwise saved serverURL.
    var effectiveServerURL: URL? {
        effectiveServerURLOverride ?? serverURL
    }

    /// The token to use: override if set, otherwise saved accessToken.
    var effectiveAccessToken: String? {
        effectiveAccessTokenOverride ?? accessToken
    }

    /// Whether credentials are configured
    var isConfigured: Bool {
        serverURL != nil && accessToken != nil
    }

    // MARK: - Initialization

    private convenience init() {
        let service = BuildFeatures.isHomeAssistantOnly
            ? "com.hsianyun.itsyhome.ha.homeassistant" : "com.nickustinov.itsyhome.homeassistant"
        let store: HATokenStore
        #if os(macOS) && HOME_ASSISTANT_ONLY
        store = HALoginKeychainTokenStore(service: service, account: "access_token")
        #else
        store = HASecItemTokenStore(service: service, account: "access_token")
        #endif
        self.init(defaults: .standard, tokenStore: store)
    }

    init(defaults: UserDefaults, tokenStore: HATokenStore,
         makeClient: @escaping (URL, String) throws -> HAAuthenticationClient = {
             try HomeAssistantClient(serverURL: $0, accessToken: $1)
         }) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        self.makeClient = makeClient
    }

    /// The Catalyst module shares the native plugin's store, including cameras.
    func useTokenStore(_ store: HATokenStore) {
        tokenStore = store
    }

    // MARK: - Public methods

    /// Commit the URL only once the token can actually be saved and read back.
    func saveCredentials(serverURL: URL, accessToken: String) throws {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw HAAuthError.invalidToken }
        let status = tokenStore.storeToken(token)
        guard status == errSecSuccess else {
            logger.error("Failed to save Home Assistant credentials: \(status)")
            throw HAAuthError.credentialStorageFailed(status)
        }
        guard tokenStore.readToken() == token else {
            throw HAAuthError.credentialStorageFailed(errSecDecode)
        }
        self.serverURL = serverURL
        logger.info("Credentials saved for \(serverURL.host ?? "unknown", privacy: .public)")
    }

    func clearCredentials() throws {
        let status = tokenStore.removeToken()
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw HAAuthError.credentialStorageFailed(status)
        }
        serverURL = nil
        effectiveServerURLOverride = nil
        effectiveAccessTokenOverride = nil
        logger.info("Credentials cleared")
    }

    /// Validate credentials by testing connection
    func validateCredentials() async throws -> Bool {
        guard let url = serverURL, let token = accessToken else {
            throw HAAuthError.notConfigured
        }

        return try await validateCredentials(serverURL: url, accessToken: token)
    }

    /// Test submitted values before changing persistent credentials.
    func validateCredentials(serverURL: URL, accessToken: String) async throws -> Bool {
        let client = try makeClient(serverURL, accessToken)

        do {
            try await client.connect()
            client.disconnect()
            return true
        } catch {
            client.disconnect()
            let nsError = error as NSError
            logger.error("Credential validation failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public) – \(nsError.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Validate credentials and fetch device/area counts for onboarding
    func validateAndFetchCounts() async throws -> (deviceCount: Int, areaCount: Int) {
        guard let url = serverURL, let token = accessToken else {
            throw HAAuthError.notConfigured
        }

        return try await validateAndFetchCounts(serverURL: url, accessToken: token)
    }

    func validateAndFetchCounts(serverURL: URL, accessToken: String) async throws -> (deviceCount: Int, areaCount: Int) {
        let client = try makeClient(serverURL, accessToken)

        do {
            try await client.connect()
            let devices = try await client.getDevices()
            let areas = try await client.getAreas()
            client.disconnect()
            return (devices.count, areas.count)
        } catch {
            client.disconnect()
            let nsError = error as NSError
            logger.error("Credential validation failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public) – \(nsError.localizedDescription, privacy: .public)")
            throw error
        }
    }

}

// MARK: - Errors

enum HAAuthError: LocalizedError {
    case notConfigured
    case invalidURL
    case invalidToken
    case credentialStorageFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Home Assistant is not configured"
        case .invalidURL:
            return "Invalid server URL"
        case .invalidToken:
            return "Invalid access token"
        case .credentialStorageFailed(let status):
            let message = String(localized: "error.home_assistant.keychain", defaultValue: "Unable to access Home Assistant credentials in Keychain.", bundle: .macOSBridge)
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error"
            return "\(message) \(detail) (\(status))"
        }
    }
}
