import XCTest
import Security
@testable import macOSBridge

final class HAAuthManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: TestHATokenStore!
    private var suite: String!
    private let url = URL(string: "http://localhost:8123")!

    override func setUp() {
        suite = "HAAuthManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = TestHATokenStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        store = nil
    }

    func testSavedCredentialsCanBeReadByAnotherManager() throws {
        let manager = HAAuthManager(defaults: defaults, tokenStore: store)
        try manager.saveCredentials(serverURL: url, accessToken: " test-token \n")
        let reopened = HAAuthManager(defaults: defaults, tokenStore: store)
        XCTAssertTrue(reopened.isConfigured)
        XCTAssertEqual(reopened.accessToken, "test-token")
        XCTAssertEqual(reopened.serverURL, url)
    }

    func testKeychainFailurePreservesPreviousCredentialsAndReportsStatus() throws {
        let manager = HAAuthManager(defaults: defaults, tokenStore: store)
        try manager.saveCredentials(serverURL: url, accessToken: "previous")
        store.writeStatus = errSecMissingEntitlement
        XCTAssertThrowsError(try manager.saveCredentials(serverURL: URL(string: "http://other:8123")!, accessToken: "replacement")) { error in
            guard case HAAuthError.credentialStorageFailed(let status) = error else {
                return XCTFail("Expected a storage error, received \(error)")
            }
            XCTAssertEqual(status, errSecMissingEntitlement)
        }
        XCTAssertEqual(manager.accessToken, "previous")
        XCTAssertEqual(manager.serverURL, url)
    }

    func testUnreadableSaveDoesNotCommitServerURL() {
        let manager = HAAuthManager(defaults: defaults, tokenStore: store)
        store.canRead = false
        XCTAssertThrowsError(try manager.saveCredentials(serverURL: url, accessToken: "test-token"))
        XCTAssertNil(manager.serverURL)
        XCTAssertFalse(manager.isConfigured)
    }

    func testEmptyTokenIsRejectedBeforeStorage() {
        let manager = HAAuthManager(defaults: defaults, tokenStore: store)
        XCTAssertThrowsError(try manager.saveCredentials(serverURL: url, accessToken: " \n"))
        XCTAssertEqual(store.writes, 0)
        XCTAssertNil(manager.serverURL)
    }

    func testDeleteFailureDoesNotPretendToDisconnect() throws {
        let manager = HAAuthManager(defaults: defaults, tokenStore: store)
        try manager.saveCredentials(serverURL: url, accessToken: "test-token")
        store.deleteStatus = errSecAuthFailed
        XCTAssertThrowsError(try manager.clearCredentials())
        XCTAssertTrue(manager.isConfigured)
        store.deleteStatus = errSecSuccess
        try manager.clearCredentials()
        XCTAssertFalse(manager.isConfigured)
    }

    func testCatalystConsumerUsesTheNativeProvider() throws {
        let native = HAAuthManager(defaults: defaults, tokenStore: store)
        try native.saveCredentials(serverURL: url, accessToken: "test-token")
        let consumer = HAAuthManager(defaults: defaults, tokenStore: TestHATokenStore())
        XCTAssertNil(consumer.accessToken)
        consumer.useTokenStore(native.tokenStore)
        XCTAssertEqual(consumer.accessToken, "test-token")
    }

    func testSubmittedCredentialsAreValidatedWithoutReadingStorage() async throws {
        let client = TestHAAuthenticationClient()
        let manager = HAAuthManager(defaults: defaults, tokenStore: store) { receivedURL, receivedToken in
            XCTAssertEqual(receivedURL, self.url)
            XCTAssertEqual(receivedToken, "submitted")
            return client
        }
        let valid = try await manager.validateCredentials(serverURL: url, accessToken: "submitted")
        XCTAssertTrue(valid)
        XCTAssertEqual(client.connections, 1)
        XCTAssertEqual(store.reads, 0)
        XCTAssertEqual(store.writes, 0)
        XCTAssertNil(manager.serverURL)
    }
}

private final class TestHATokenStore: NSObject, HATokenStore {
    var token: String?
    var canRead = true
    var writeStatus = errSecSuccess
    var deleteStatus = errSecSuccess
    var reads = 0
    var writes = 0

    init(service: String = "test", account: String = "test") { super.init() }
    func readToken() -> String? { reads += 1; return canRead ? token : nil }
    func storeToken(_ token: String) -> Int32 {
        writes += 1
        if writeStatus == errSecSuccess { self.token = token }
        return writeStatus
    }
    func removeToken() -> Int32 {
        if deleteStatus == errSecSuccess { token = nil }
        return deleteStatus
    }
}

private final class TestHAAuthenticationClient: HAAuthenticationClient {
    var connections = 0
    func connect() async throws { connections += 1 }
    func disconnect() {}
    func getDevices() async throws -> [HADevice] { [] }
    func getAreas() async throws -> [HAArea] { [] }
}
