#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_output="$(dirname "$task_root")"
task_build="${NOVAVPS_BUILD_DIR:-$task_root/.build-native}"
task_sdk="${NOVAVPS_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
task_app="$task_output/NovaVPS.app/Contents"
mkdir -p "$task_build" "$task_app/MacOS" "$task_app/Resources"
if [[ ! -f "$task_build/libYams.a" ]]; then
  for task_source in "$task_root"/ThirdParty/Yams/Sources/CYaml/src/*.c; do
    xcrun clang -isysroot "$task_sdk" -arch arm64 -O2 -DYAML_DECLARE_STATIC -I"$task_root/ThirdParty/Yams/Sources/CYaml/include" -mmacosx-version-min=13.0 -c "$task_source" -o "$task_build/$(basename "$task_source" .c).o"
  done
  xcrun swiftc -module-cache-path "$task_build/module-cache" -sdk "$task_sdk" -DSWIFT_PACKAGE -swift-version 5 -O -parse-as-library -emit-library -static -emit-module -module-name Yams -target arm64-apple-macos13.0 \
    -I "$task_root/ThirdParty/Yams/Sources/CYaml/include" "$task_root"/ThirdParty/Yams/Sources/Yams/*.swift "$task_build"/*.o -o "$task_build/libYams.a" -emit-module-path "$task_build/Yams.swiftmodule"
fi
task_core="${NOVAVPS_XRAY_BINARY:-$task_app/Resources/xray}"
[[ -x "$task_core" ]] || { printf 'Provide the verified Xray arm64 binary with NOVAVPS_XRAY_BINARY.\n' >&2; exit 1; }
python3 - "$task_core" "$task_root/Resources/core-manifest.json" <<'PY'
import hashlib,json,sys
manifest=json.load(open(sys.argv[2])); digest=hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()
assert digest in [manifest['binarySHA256'],manifest.get('bundledBinarySHA256')], 'Xray binary checksum does not match verified provenance'
PY
if [[ "$task_core" != "$task_app/Resources/xray" ]]; then cp "$task_core" "$task_app/Resources/xray"; fi
codesign --force --sign - "$task_app/Resources/xray"
xcrun swiftc -module-cache-path "$task_build/module-cache" -sdk "$task_sdk" -swift-version 5 -O -parse-as-library -target arm64-apple-macos13.0 \
  -I "$task_build" -I "$task_root/ThirdParty/Yams/Sources/CYaml/include" -L "$task_build" -lYams \
  "$task_root"/Sources/Shared/*.swift "$task_root"/Sources/NovaVPS/*.swift \
  -framework SwiftUI -framework AppKit -framework Security -framework CoreImage -o "$task_app/MacOS/NovaVPS"
cp "$task_root/Info.plist" "$task_app/Info.plist"
cp "$task_root/Resources/panel-manager.py" "$task_root/Resources/core-manifest.json" "$task_root/LICENSE" "$task_root/THIRD_PARTY.md" "$task_app/Resources/"
python3 - "$task_app/Resources/xray" "$task_app/Resources/core-manifest.json" <<'PY'
import hashlib,json,sys
path=sys.argv[2]; manifest=json.load(open(path)); manifest['bundledBinarySHA256']=hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()
manifest['signatureNote']='Original program code, ad-hoc re-signed locally; binarySHA256 records the upstream executable before re-signing.'
open(path,'w').write(json.dumps(manifest,indent=2)+'\n')
PY
cp "$task_root/ThirdParty/Xray-LICENSE" "$task_root/ThirdParty/3x-ui-LICENSE" "$task_app/Resources/"
codesign --force --sign - "$task_output/NovaVPS.app"
codesign --verify --deep --strict "$task_output/NovaVPS.app"
printf 'Built %s\n' "$task_output/NovaVPS.app"
