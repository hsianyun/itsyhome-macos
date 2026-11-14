# Install the Home Assistant-only version on your Mac

The recommended local build is **Itsyhome HA**. It connects directly to Home Assistant and includes the combined temperature and humidity display. It uses Xcode's **Sign to Run Locally** signing identity, with no Apple Developer Program membership, development team or provisioning profile to configure.

HomeKit mode and iCloud sync are disabled in this build. It has its own app identifier, settings and Home Assistant credential entry, so it can coexist with the original Itsyhome app. The original full-featured project remains available in `project.yml`.

## Requirements

- macOS 14 or later.
- The full Xcode application. Open it once and finish installing its components. The included CI workflow uses Xcode 16.4.
- [Homebrew](https://brew.sh/) and XcodeGen, or another installation of XcodeGen.
- Your Home Assistant server URL and a long-lived access token.

## 1. Download this fork

```sh
brew install xcodegen
git clone https://github.com/hsianyun/itsyhome-macos.git
cd itsyhome-macos
```

If the Home Assistant-only pull request has not been merged into `main` yet, check out its branch before building:

```sh
git fetch origin codex/home-assistant-only
git switch --track origin/codex/home-assistant-only
```

For an existing checkout already on that branch, use `git pull --ff-only`. After merging the pull request, you can use `main` instead.

## 2. Build the local application

```sh
./scripts/build-home-assistant.sh
```

The script generates **ItsyhomeHomeAssistant.xcodeproj** from `project-home-assistant.yml`, builds a Release app, checks its code signature and verifies that its signed entitlements contain no HomeKit or iCloud provisioning requirements. Xcode signs nested frameworks and the native menu bar plugin as part of the build.

The results are:

- `build/home-assistant/Build/Products/Release-maccatalyst/Itsyhome HA.app`
- `build/home-assistant/Itsyhome-HA.zip`

You do not need to edit team IDs or bundle identifiers. The local build overrides the original project's signing settings and replaces its entire entitlement map, keeping sandbox and network permissions.

To build and run the unit tests as well:

```sh
./scripts/build-home-assistant.sh --test
```

If you prefer Xcode's interface:

```sh
xcodegen generate --spec project-home-assistant.yml
open ItsyhomeHomeAssistant.xcodeproj
```

Choose the **Itsyhome** scheme and **My Mac (Mac Catalyst)**, then **Product → Run**. Leave the generated local signing settings in place. The app appears in the menu bar; its main window is intentionally hidden.

If Terminal reports that `xcodebuild` requires Xcode, choose your installed Xcode in **Xcode → Settings → Locations → Command Line Tools** and try again.

## 3. Install and open it

Quit any running copy of **Itsyhome HA** before replacing it. In Finder, copy the built **Itsyhome HA.app** into Applications, then open it. Keep the entire app bundle together, including its plugin and frameworks.

Alternatively, install into your personal Applications folder from the repository directory:

```sh
mkdir -p "$HOME/Applications"
ditto "build/home-assistant/Build/Products/Release-maccatalyst/Itsyhome HA.app" "$HOME/Applications/Itsyhome HA.app"
open "$HOME/Applications/Itsyhome HA.app"
```

This is a locally signed application for your own Mac. It is not a notarized distribution build. Apple describes this signing identity as [Sign to Run Locally](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements). Local signing changes between builds can cause macOS to ask for network or Keychain access again.

## 4. Connect Home Assistant

The app starts in Home Assistant mode and opens the connection settings when credentials are missing.

1. In Home Assistant, open **Profile → Security → Long-lived access tokens**, then create a token.
2. In **Itsyhome HA → Settings → Home Assistant**, enter your server URL, such as `http://homeassistant.local:8123`, and the token.
3. Connect and allow local network access if macOS prompts for it.

Enter credentials again even if the original Itsyhome app is already configured: this version deliberately uses a separate credential entry. Tokens stay in Keychain. Keep iCloud-dependent features and Apple Home control in the original full build.

## 5. Enable the combined readings

1. Open **Settings → Advanced**.
2. Enable **Temperature and humidity in menu bar**.
3. Choose a **Temperature sensor** and a **Humidity sensor**.
4. Set **Temperature units** to **Celsius**, **Fahrenheit** or **System default**.

The main icon now includes a combined reading such as **21.5°C · 45%**. Clicking it opens the normal Home menu. You can leave **Summarise temperature and humidity** enabled; separate pinned items are optional.

Readings update while the menu is closed, and selections are saved per home. Missing or unavailable values show `--°C` / `--°F` and `--%` until data returns.

If a sensor is absent, check that its Home Assistant entity is enabled and has `device_class: temperature` or `device_class: humidity`. Check **Settings → Home Assistant → Entity categories** if the entity is classified as diagnostic or configuration. Refresh or reconnect after changing entity metadata.

## Build using GitHub Actions

The **Home Assistant local build** workflow builds this variant on a Mac runner, runs tests and uploads the **Itsyhome-HA** artifact containing `Itsyhome-HA.zip` after a successful run. It also supports **Run workflow** from the repository's **Actions** tab.

Forks may have Actions disabled initially. If the workflow does not run, enable workflows in the repository's Actions tab first. A workflow artifact exists only after the Mac build and tests succeed. A downloaded artifact is still locally signed rather than notarized; building on your own Mac is the recommended local installation method.

## Updating

Quit **Itsyhome HA**, update your checkout, run the build script again, and replace the installed app bundle. This build keeps its settings separately from the original app. No personal team or signing changes need to be maintained in the repository.

## Building the original full version

The existing `project.yml` still builds the full HomeKit/Home Assistant app with iCloud support. Generate it with `xcodegen generate` and follow [CONTRIBUTING.md](CONTRIBUTING.md). That configuration retains the original HomeKit/iCloud signing requirements and needs a compatible Apple development team and provisioning profile.
