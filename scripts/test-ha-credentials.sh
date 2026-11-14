#!/bin/bash
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then
    printf 'This credential test requires macOS and Xcode.\n' >&2
    exit 1
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$script_dir/.." && pwd)"
cd "$repo_dir"
probe_dir="$repo_dir/build/credential-probe"
xcodegen generate --spec project-home-assistant.yml
xcodebuild build -project ItsyhomeHomeAssistant.xcodeproj -scheme HAKeychainProbe \
    -configuration Release -destination "platform=macOS,variant=Mac Catalyst" \
    -derivedDataPath "$probe_dir"
probe_app="$probe_dir/Build/Products/Release-maccatalyst/HAKeychainProbe.app"
codesign --verify --deep --strict "$probe_app"
"$probe_app/Contents/MacOS/HAKeychainProbe" > "$probe_dir/probe.log" 2>&1 &
probe_pid=$!
for ((attempt = 0; attempt < 45; attempt++)); do
    if ! kill -0 "$probe_pid" 2>/dev/null; then
        if wait "$probe_pid"; then
            cat "$probe_dir/probe.log"
            exit 0
        fi
        cat "$probe_dir/probe.log" >&2
        exit 1
    fi
    sleep 1
done
kill "$probe_pid" 2>/dev/null || true
wait "$probe_pid" 2>/dev/null || true
cat "$probe_dir/probe.log" >&2
printf 'The credential probe timed out, possibly waiting for Keychain access.\n' >&2
exit 1
