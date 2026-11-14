# Install this fork on your Mac

This fork adds a combined temperature and humidity reading beside the main Itsyhome menu bar icon. Install a build from this repository to use it; the upstream App Store app does not include this fork's changes.

## Requirements

- macOS 14 or later.
- The full Xcode application, opened once to finish installing its components. The repository's CI uses Xcode 16.4.
- [Homebrew](https://brew.sh/) and XcodeGen, or another installation of XcodeGen.
- A Home Assistant server that your Mac can reach, and a long-lived access token.
- For the normal signed development build below, your own Apple development signing team. The default project includes HomeKit and iCloud capabilities, so the team and provisioning profile must support those capabilities even if you choose Home Assistant at runtime.

## 1. Download the source

In Terminal:

```sh
brew install xcodegen
git clone https://github.com/hsianyun/itsyhome-macos.git
cd itsyhome-macos
```

If you already have a clean checkout of this fork, update it instead:

```sh
git switch main
git pull --ff-only origin main
```

## 2. Configure signing and build

1. Open **Xcode → Settings → Accounts** (called **Apple Accounts** in newer Xcode versions) and sign in to your Apple development account.
2. In `project.yml`, replace the existing `DEVELOPMENT_TEAM` value with your team's ID. Replace the `PRODUCT_BUNDLE_IDENTIFIER` values for `Itsyhome`, `macOSBridge` and `macOSBridgeTests` with unique identifiers you control, for example `com.yourname.itsyhome`, `com.yourname.itsyhome.macOSBridge` and `com.yourname.itsyhome.macOSBridgeTests`. Use the same prefix for `bundleIdPrefix` at the top of the file.
3. Generate the Xcode project and open it:

   ```sh
   xcodegen generate
   open Itsyhome.xcodeproj
   ```

4. Select the **Itsyhome** scheme and **My Mac (Mac Catalyst)** as the run destination. Resolve Swift package dependencies if Xcode prompts you.
5. Check **Signing & Capabilities** for the app and plugin targets. Use your own team with automatic signing and let Xcode create the required profiles.
6. Choose **Product → Run**. The app runs in the menu bar; its main window is intentionally hidden.

The source of truth is `project.yml`. Regenerating the Xcode project overwrites settings made only in the generated project. Keep any persistent signing changes in `project.yml`.

If Xcode reports that your team cannot provision HomeKit or iCloud, the default project cannot be signed by that team as configured. Use a team/profile with those capabilities or make a separate Home Assistant-only development configuration that omits them. An unsigned compile passing does not establish that an app can launch on your Mac. Apple's [running an app guide](https://developer.apple.com/documentation/xcode/building-and-running-an-app) explains local signing and provisioning.

## 3. Install the built application

1. Quit any other running copy of Itsyhome from its menu bar menu.
2. In Xcode's Project navigator, expand **Products**, right-click **Itsyhome.app**, and choose **Show in Finder**. If Products is hidden, choose **Product → Show Build Folder in Finder**, then open the `Products/Debug-maccatalyst` folder.
3. Copy **Itsyhome.app** into your Mac's **Applications** folder, replacing an older copy only if you intend to replace it. Keep the entire application bundle together; it contains the native menu bar plugin and frameworks.
4. Stop the Xcode run, then open the installed copy from Applications.

This is a development-signed application, not a notarized release installer. Keep using the same signing identity and bundle identifiers for later local builds if you want them to use the same app identity. [Apple's code signing documentation](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac) covers preparing a build for distribution to other Macs.

## 4. Connect Home Assistant

1. In Home Assistant, open your **Profile → Security → Long-lived access tokens**, then create a token.
2. On Itsyhome's first launch, choose **Home Assistant**. If it is already configured for HomeKit, switch platform in **Settings → General**.
3. Enter your Home Assistant server URL, such as `http://homeassistant.local:8123`, and the token in the connection screen or **Settings → Home Assistant**.
4. Connect and allow local network access if macOS prompts for it.

Keep the token private. Use the existing URL and token configuration if you have already connected this fork to your server.

## 5. Enable the combined readings

1. Open **Settings → Advanced**.
2. Enable **Temperature and humidity in menu bar**.
3. Choose a **Temperature sensor** and a **Humidity sensor**. The selectors include room names and Home Assistant entity IDs to help identify your devices.
4. Set **Temperature units** to **Celsius**, **Fahrenheit** or **System default**.

The main menu bar item now shows a combined reading, for example **21.5°C · 45%**, beside the existing icon. Clicking it still opens the usual Home menu. You can leave **Summarise temperature and humidity** enabled; separate sensor pins are optional.

The readings update while the menu is closed. Sensor choices are saved per home. Unknown, missing or unavailable readings show `--°C` / `--°F` and `--%` until data returns. Turn the display switch off to restore the icon-only item.

If a sensor is missing from the selectors, check that its Home Assistant entity is enabled and has `device_class: temperature` or `device_class: humidity`. Also check Itsyhome's entity category filter in **Settings → Home Assistant** if Home Assistant marks the entity as diagnostic or configuration. Reconnect or use the menu's refresh action after changing entity metadata.

## Update or remove your local build

To update, quit Itsyhome, pull this fork's latest `main`, restore your local signing settings if needed, regenerate the project, rebuild, then copy the new app into Applications again. If you changed `project.yml` for signing, preserve those edits before pulling; keep your identifiers and team settings out of commits intended for this repository.

To stop running this version, quit it and remove its application bundle from Applications. You can then launch another installed version.

## Developer verification

The repository's GitHub Actions workflow runs the macOS tests on pushes to `main` and pull requests. To run the same signing-disabled test command on a Mac after generating the project:

```sh
xcodebuild test \
  -scheme Itsyhome \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

This test command is for verification; use the signed development build steps above to install and launch the app.
