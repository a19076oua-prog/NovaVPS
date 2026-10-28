# NovaVPS 0.2.0 validation

Date: 2026-10-28. macOS build: Apple Silicon; Swift 6.3.3, MacOSX26.5.sdk. Native macOS version 0.2.0, build 4. Windows desktop version 0.2.0: Electron 45.1.0, electron-builder 26.18.0, Node.js 24.

## Completed

- Native SwiftUI application built with the pinned SDK; ad-hoc code signatures verified recursively.
- The production app was opened and its management screen inspected. IP, SSH port, password, node port, fingerprint gate, web-panel entry and management/configuration navigation are present in the native window.
- 24 Python tests pass: local bearer API HTTP contract; redirects and oversized responses rejected; invalid requests/states/archive members rejected; private state permissions; occupied port and existing service protection; idempotent provisioning; recovery after response loss; disabled inbound rejection; fresh SQLite initialization and subscription disabling; service unit generation; rollback limited to newly created owned paths.
- Separate panel installation is tested with a genuinely occupied node socket; node creation still rejects that occupied port.
- Native checks cover JSON/YAML/VLESS round trips and IPv6; incompatible transport/fingerprint rejection; all four export files and 600 permissions; Vision QR decoding equals the exact generated VLESS link; the bundled Xray accepts generated JSON; result-envelope and HTTP204 failure handling; password clearing and persistence; deployment authentication gates.
- Actual macOS `/usr/bin/ssh` is tested against an isolated local ssh2 server: password login, wrong-password rejection, changed-host-key rejection, management stdin/result transport, loopback TCP forwarding to a local HTTP fixture, and listener removal after tunnel closure.
- These tests use synthetic credentials and documentation IPs. No user password, existing configuration or real server was read into test fixtures or release files. Tests do not change system proxy or TUN.

## Windows desktop adaptation

- The macOS SwiftUI application and PKG are retained. Windows adds a separate self-contained x64 EXE installer and portable ZIP. No Node.js, Python or OpenSSH installation is needed on the Windows client. The same remote Linux panel-manager.py is bundled in both products.
- 22 desktop tests pass on macOS and on the Windows CI runner: request/result validation, JSON/YAML/VLESS round trips, unsupported configuration rejection, private record storage, no saved SSH password, real QR decoding, password SSH authentication, wrong-password and changed-host-key rejection, and actual loopback HTTP forwarding through SSH with listener cleanup. These use isolated local fixtures.
- Windows cross-build on macOS succeeded. The unpacked executable is a Windows x64 PE; its ASAR contains current source and no native .node addons; the packaged Linux manager is byte-identical to the shared source. The official Windows Xray archive is checked against its pinned SHA-256 and its binary is checked again at runtime.
- The cross-platform preview also passed its packaged runtime checks on Apple Silicon macOS: bundled native Xray accepts exported JSON, records exclude SSH passwords, the remote manager is present, the sandboxed renderer loads management controls, and preload/validated IPC initialize an empty profile. Chinese/English switching, synthetic node import and QR display were inspected in the actual preview window. This preview is not the native macOS release application.
- Windows packaged EXE runtime passed all six checks on the real Windows x64 runner in [CI run 40641185607](https://github.com/a19076oua-prog/NovaVPS/actions/runs/40641185607), commit 916e03505b9e8eef26740d7ac2a2216c467f6c23: native Windows Xray validates JSON; private persistence excludes SSH passwords; shared manager is bundled; sandboxed renderer and preload load; validated IPC initializes empty data; completed import returns busy=false. The report and screenshot archive SHA-256 matched GitHub. The Windows release EXE and ZIP come from this successful CI run. Its distribution archive SHA-256 is 77386d0690f52acf70b240d48c39e87ab70dfecd85fc21c67ac6494e6e0e5cd8. No interactive NSIS wizard or Windows 10 device was manually tested.
- Windows records and exports use a restricted current-user/SYSTEM directory ACL. Passwords and key passphrases are session-only. No existing user VPN, installed app record or real SSH credential was used in Windows tests.

Reproduce on Windows from Desktop/: npm ci --ignore-scripts --no-audit --no-fund; npm test; node scripts/prepare-core.cjs win32-x64; npm run prepare:licenses; npm run build:win; node scripts/run-smoke.cjs dist/win-unpacked/NovaVPS.exe. The workflow saves the native JSON report, screenshot and Windows distributions as artifacts.

## Not yet verified on a real VPS

The 3x-ui Linux executable, apt installation, systemd launch, public node connectivity, cloud firewall and Reality TLS handshake have **not** been exercised together on a real Debian/Ubuntu VPS. Installer logic tests replace the downloaded Linux executable, bcrypt hashing and systemctl with controlled fixtures; they do not prove a real deployment succeeded.

The application requires the user to supply valid SSH credentials and compare the public-key fingerprint. A saved or exported node is not reported as connected until the app receives a successful HTTPS 204 through its temporary Xray proxy. The last-success time is historical evidence, not a live guarantee.

## Reproduction

1. Run `python3 Tests/test_manager.py`.
2. Run `scripts/build.sh` with NOVAVPS_XRAY_BINARY and an optional NOVAVPS_BUILD_DIR.
3. Install the development-only `Tests/package.json` dependency (`ssh2` 1.17.0). Run `Tests/run-native.sh` with the same build directory. This uses disposable loopback listeners and deletes its temporary files on exit.

Upstream sources: https://github.com/MHSanaei/3x-ui/tree/v3.11.0 and https://github.com/XTLS/Xray-core/tree/v26.10.21 . Versioned release hashes are recorded in the source installer and core manifest. 3x-ui Linux amd64 archive was downloaded and its SHA-256 and archive layout verified; the arm64 digest was checked against official release metadata, without downloading or executing that Linux binary.

## Packaging

The macOS installer payload contains only NovaVPS.app and installs into /Applications. No privileged helper, LaunchDaemon, network settings or postinstall script is installed on the Mac. Source ZIP includes the native app, source, tests, licenses and these instructions; excludes personal server data, test runtime folders, dependency caches and Python bytecode. Installer and ZIP checksums are beside the packages.

The Windows installer is per-user and does not request elevation. Windows packages are not Authenticode signed; the native macOS app is ad-hoc signed and not Apple notarized. Portable Windows ZIPs must be fully extracted. Source packages exclude Desktop/dist, Desktop/resources/core, smoke-results and dependency caches.

Distribution verification completed 2026-10-29: the downloaded Windows portable ZIP passed integrity, x64 PE, current ASAR source (with Windows CRLF normalization), bundled Xray hash and shared-manager parity checks. No personal server records or exports were present.
