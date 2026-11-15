#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
probe_dir="$PWD/build/settings-catalyst"
xcodegen generate --spec project-settings-probe.yml
xcodebuild build -project ItsyhomeSettingsProbe.xcodeproj -scheme SettingsProbe \
    -configuration Debug -destination "platform=macOS,variant=Mac Catalyst" \
    -derivedDataPath "$probe_dir"
probe_app="$probe_dir/Build/Products/Debug-maccatalyst/SettingsProbe.app"
codesign --verify --deep --strict "$probe_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$probe_app"
xcodebuild test -project ItsyhomeSettingsProbe.xcodeproj -scheme SettingsProbeUITests \
    -configuration Debug -destination "platform=macOS" \
    -derivedDataPath "$probe_dir" -resultBundlePath "$probe_dir/SettingsUI.xcresult"
