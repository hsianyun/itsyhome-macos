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

/// Match the production app's hidden Catalyst scene instead of letting UIKit
/// create an unrelated full-size window behind the native Settings window.
final class ProbeSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        scene.sizeRestrictions?.minimumSize = CGSize(width: 1, height: 1)
        scene.sizeRestrictions?.maximumSize = CGSize(width: 1, height: 1)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
