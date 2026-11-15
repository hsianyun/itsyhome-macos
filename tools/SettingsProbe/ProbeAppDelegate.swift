import UIKit

@main
final class ProbeAppDelegate: UIResponder, UIApplicationDelegate {
    private var driver: SettingsProbe?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let roots = [Bundle.main.builtInPlugInsURL, Bundle.main.resourceURL].compactMap { $0 }
        guard let path = roots.map({ $0.appendingPathComponent("macOSBridge.bundle") })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let bundle = Bundle(url: path),
              let type = bundle.principalClass as? SettingsProbe.Type else {
            fatalError("Cannot load the production settings plugin into the Catalyst probe")
        }
        driver = type.init()
        DispatchQueue.main.async { self.driver?.start() }
        return true
    }
}
