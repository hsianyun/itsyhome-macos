#!/bin/bash
set -euo pipefail

run_tests=false
case "${1:-}" in
    "") ;;
    --test) run_tests=true ;;
    --help)
        printf 'Usage: %s [--test]\nBuild and package the locally signed Home Assistant-only Mac app.\n' "$0"
        exit 0
        ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
esac
if [[ $# -gt 1 ]]; then
    printf 'Expected at most one option.\n' >&2
    exit 1
fi

if [[ "$(uname -s)" != Darwin ]]; then
    printf 'This build requires macOS and the full Xcode application.\n' >&2
    exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
    printf 'Install XcodeGen first: brew install xcodegen\n' >&2
    exit 1
fi
if ! xcodebuild -version >/dev/null 2>&1; then
    printf 'Open Xcode to finish setup and select it in Xcode Settings > Locations > Command Line Tools.\n' >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
cd "$repo_dir"

derived_data="$repo_dir/build/home-assistant"
app_path="$derived_data/Build/Products/Release-maccatalyst/Itsyhome HA.app"
archive_path="$derived_data/Itsyhome-HA.zip"
entitlements_path="$derived_data/signed-entitlements.plist"

xcodegen generate --spec project-home-assistant.yml
xcodebuild build \
    -project ItsyhomeHomeAssistant.xcodeproj \
    -scheme Itsyhome \
    -configuration Release \
    -destination "platform=macOS,variant=Mac Catalyst" \
    -derivedDataPath "$derived_data"

if [[ ! -d "$app_path" ]]; then
    printf 'Build finished without the expected application: %s\n' "$app_path" >&2
    exit 1
fi

# Xcode signs the application and its nested code using Sign to Run Locally.
# Verify the actual built bundle rather than packaging an unsigned executable.
codesign --verify --deep --strict "$app_path"
codesign --display --entitlements :- "$app_path" > "$entitlements_path" 2>/dev/null
for entitlement in \
    com.apple.developer.homekit \
    com.apple.developer.ubiquity-kvstore-identifier \
    com.apple.developer.icloud-container-identifiers \
    com.apple.developer.icloud-services; do
    if /usr/libexec/PlistBuddy -c "Print :$entitlement" "$entitlements_path" >/dev/null 2>&1; then
        printf 'Unexpected provisioning entitlement in the Home Assistant-only app: %s\n' "$entitlement" >&2
        exit 1
    fi
done
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$entitlements_path")" != true ]]; then
    printf 'The signed app is missing its network client entitlement.\n' >&2
    exit 1
fi

if "$run_tests"; then
    xcodebuild test \
        -project ItsyhomeHomeAssistant.xcodeproj \
        -scheme Itsyhome \
        -configuration Debug \
        -destination "platform=macOS" \
        -derivedDataPath "$derived_data" \
        -resultBundlePath "$derived_data/TestResults-$(date +%Y%m%d-%H%M%S).xcresult"
fi

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"
printf '\nBuilt and verified: %s\nPackaged: %s\n' "$app_path" "$archive_path"
printf 'Quit other running copies, then copy Itsyhome HA.app into Applications and open it.\n'
