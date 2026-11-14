import Foundation

/// Objective-C interop lets the Catalyst camera code use the native plugin's
/// credential store without attempting a second, differently scoped Keychain.
@objc public protocol HATokenStore: NSObjectProtocol {
    init(service: String, account: String)
    func readToken() -> String?
    func storeToken(_ token: String) -> Int32
    func removeToken() -> Int32
}
