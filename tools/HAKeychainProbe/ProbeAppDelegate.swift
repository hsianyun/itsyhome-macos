import UIKit
import Security

/// Exercises storage in an actual ad-hoc-signed, sandboxed Catalyst process.
/// The ordinary macOS XCTest process does not reproduce its Keychain rules.
@main
final class ProbeAppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let service = "com.hsianyun.itsyhome.credential-probe.\(UUID().uuidString)"
        let account = "probe"
        let oldStore = HASecItemTokenStore(service: service, account: account)
        let oldStatus = oldStore.storeToken("synthetic-probe")
        _ = oldStore.removeToken()

        let roots = [Bundle.main.builtInPlugInsURL, Bundle.main.resourceURL].compactMap { $0 }
        guard let path = roots.map({ $0.appendingPathComponent("HAKeychainProbeBridge.bundle") })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let bundle = Bundle(url: path),
              let storeType = bundle.principalClass as? HATokenStore.Type else {
            finish(stage: "load-native-store", status: -1, oldStatus: oldStatus)
        }
        let store = storeType.init(service: service, account: account)
        let first = "synthetic-first-\(UUID().uuidString)"
        let status = store.storeToken(first)
        guard status == errSecSuccess else {
            finish(stage: "save", status: status, oldStatus: oldStatus)
        }
        let reopened = storeType.init(service: service, account: account)
        guard reopened.readToken() == first else {
            _ = store.removeToken()
            finish(stage: "reopen-read", status: errSecDecode, oldStatus: oldStatus)
        }
        let second = "synthetic-second-\(UUID().uuidString)"
        let updated = reopened.storeToken(second)
        guard updated == errSecSuccess, store.readToken() == second else {
            _ = store.removeToken()
            finish(stage: "replace", status: updated, oldStatus: oldStatus)
        }
        let removed = store.removeToken()
        guard removed == errSecSuccess, reopened.readToken() == nil else {
            finish(stage: "delete", status: removed, oldStatus: oldStatus)
        }
        finish(stage: "complete", status: errSecSuccess, oldStatus: oldStatus)
    }

    private func finish(stage: String, status: Int32, oldStatus: Int32) -> Never {
        let ok = stage == "complete" && status == errSecSuccess
        let result: [String: Any] = ["ok": ok, "stage": stage, "status": status, "secItemStatus": oldStatus]
        let data = try! JSONSerialization.data(withJSONObject: result, options: .sortedKeys)
        print("HA_KEYCHAIN_PROBE \(String(decoding: data, as: UTF8.self))")
        fflush(stdout)
        exit(ok ? 0 : 1)
    }
}
