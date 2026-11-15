import Foundation
import Security

/// The existing data-protection Keychain path for provisioned builds.
final class HASecItemTokenStore: NSObject, HATokenStore {
    private let service: String
    private let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
        super.init()
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func readToken() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func storeToken(_ token: String) -> Int32 {
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var request = query
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(request as CFDictionary, nil)
    }

    func removeToken() -> Int32 {
        SecItemDelete(query as CFDictionary)
    }
}

#if os(macOS)
/// Native macOS Keychain APIs explicitly address the encrypted login Keychain.
/// SecItem inside a Catalyst host always selects the data-protection Keychain,
/// which needs provisioned access-group entitlements that local builds lack.
final class HALoginKeychainTokenStore: NSObject, HATokenStore {
    private let service: String
    private let account: String
    private let lock = NSLock()

    init(service: String, account: String) {
        self.service = service
        self.account = account
        super.init()
    }

    private func find(length: UnsafeMutablePointer<UInt32>?,
                      data: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
                      item: UnsafeMutablePointer<SecKeychainItem?>?) -> OSStatus {
        service.withCString { serviceBytes in
            account.withCString { accountBytes in
                SecKeychainFindGenericPassword(nil, UInt32(service.utf8.count), serviceBytes,
                                               UInt32(account.utf8.count), accountBytes,
                                               length, data, item)
            }
        }
    }

    func readToken() -> String? {
        lock.lock()
        defer { lock.unlock() }
        var length: UInt32 = 0
        var bytes: UnsafeMutableRawPointer?
        guard find(length: &length, data: &bytes, item: nil) == errSecSuccess else { return nil }
        defer { SecKeychainItemFreeContent(nil, bytes) }
        guard let bytes else { return nil }
        return String(data: Data(bytes: bytes, count: Int(length)), encoding: .utf8)
    }

    func storeToken(_ token: String) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        var item: SecKeychainItem?
        let status = find(length: nil, data: nil, item: &item)
        let data = Data(token.utf8)
        if status == errSecSuccess, let item {
            return data.withUnsafeBytes { bytes in
                guard let address = bytes.baseAddress else { return errSecParam }
                return SecKeychainItemModifyAttributesAndData(item, nil, UInt32(bytes.count), address)
            }
        }
        guard status == errSecItemNotFound else { return status }
        return service.withCString { serviceBytes in
            account.withCString { accountBytes in
                data.withUnsafeBytes { bytes in
                    guard let address = bytes.baseAddress else { return errSecParam }
                    return SecKeychainAddGenericPassword(nil, UInt32(service.utf8.count), serviceBytes,
                                                 UInt32(account.utf8.count), accountBytes,
                                                 UInt32(bytes.count), address, nil)
                }
            }
        }
    }

    func removeToken() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        var item: SecKeychainItem?
        let status = find(length: nil, data: nil, item: &item)
        guard status == errSecSuccess, let item else { return status }
        return SecKeychainItemDelete(item)
    }
}
#endif
