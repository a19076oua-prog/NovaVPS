#!/bin/bash
set -euo pipefail
# Run build.sh first. Install Tests/package.json's development-only ssh2 dependency.
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="${NOVAVPS_BUILD_DIR:-$task_root/.build-native}"
task_sdk="${NOVAVPS_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
task_fixture="$(mktemp -d /private/tmp/novavps-checks.XXXXXXXX)"
task_pid=""
cleanup() { if [[ -n "$task_pid" ]]; then kill "$task_pid" 2>/dev/null || true; wait "$task_pid" 2>/dev/null || true; fi; rm -rf "$task_fixture"; }
trap cleanup EXIT
ssh-keygen -q -t ed25519 -N '' -f "$task_fixture/host-key"
node "$task_root/Tests/ssh-fixture.cjs" "$task_fixture" & task_pid=$!
for ((task_i=0;task_i<100;task_i++)); do [[ -f "$task_fixture/ready.json" ]] && break; sleep 0.05; done
[[ -f "$task_fixture/ready.json" ]]
task_app="$task_fixture/NativeChecks.app/Contents"
mkdir -p "$task_app/MacOS" "$task_app/Resources"
cp "$(dirname "$task_root")/NovaVPS.app/Contents/Resources/xray" "$task_app/Resources/xray"
cp "$task_root/Resources/panel-manager.py" "$task_app/Resources/"
cat > "$task_app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>NativeChecks</string><key>CFBundleIdentifier</key><string>local.novavps.checks</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -module-cache-path "$task_build/module-cache" -sdk "$task_sdk" -swift-version 5 -O -parse-as-library -target arm64-apple-macos13.0 \
 -I "$task_build" -I "$task_root/ThirdParty/Yams/Sources/CYaml/include" -L "$task_build" -lYams \
 "$task_root"/Sources/Shared/*.swift "$task_root/Sources/NovaVPS/PanelService.swift" "$task_root/Sources/NovaVPS/PanelTunnel.swift" "$task_root/Sources/NovaVPS/NodeVerifier.swift" "$task_root/Sources/NovaVPS/NodeImport.swift" "$task_root/Sources/NovaVPS/VPSModel.swift" "$task_root/Tests/NativeChecks.swift" \
 -framework SwiftUI -framework AppKit -framework Security -framework CoreImage -framework Vision -o "$task_app/MacOS/NativeChecks"
"$task_app/MacOS/NativeChecks" "$task_fixture"
