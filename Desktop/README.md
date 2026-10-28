# NovaVPS Desktop 0.2.0

Windows 桌面适配版；现有 macOS SwiftUI 版本继续保留。

The Windows desktop port, alongside the retained native SwiftUI macOS application.

- Windows 10/11 x64 installer and portable ZIP; Node.js, Python and OpenSSH do not need to be installed on the Windows client.
- Bundled JavaScript SSH client, explicit host-fingerprint confirmation, password / private-key / SSH Agent authentication.
- Shared `../Resources/panel-manager.py` for the Linux VPS; independent panel installation and new-node creation.
- Loopback-only SSH web-panel tunnel; JSON/YAML/VLESS/QR export, local Xray configuration and HTTPS-204 verification.
- Chinese and English interface, keyboard navigation and reduced-motion support.
- Passwords remain in the app session. Windows server records and exports use a restricted user/SYSTEM ACL; Unix test builds use mode 700/600.

## Build

```sh
npm ci --ignore-scripts --no-audit --no-fund
node scripts/prepare-core.cjs win32-x64
npm run prepare:licenses
npm test
npm run build:win
```

Outputs are under `dist/`. The installer is `NovaVPS-0.2.0-Windows-x64-Setup.exe`; the portable distribution is `NovaVPS-0.2.0-Windows-x64.zip`. Extract the entire portable ZIP before running NovaVPS.exe; its adjacent DLLs and resources are required.

The Windows runtime is self-contained. The target VPS still needs supported Debian/Ubuntu, systemd, and root or passwordless sudo. Cloud/server firewall rules are not automatically changed.

## Packaged runtime checks

```sh
node scripts/run-smoke.cjs dist/win-unpacked/NovaVPS.exe
```

This launches the actual packaged executable with a disposable profile, checks private persistence, validates JSON with the bundled native Windows Xray, verifies the sandboxed UI/preload/IPC, and captures a screenshot and JSON report under `smoke-results/`. It does not deploy to a real VPS or change system proxy/TUN settings.

`.github/workflows/windows-build.yml` runs these tests on Windows. A successful cross-build on macOS is reported separately from native Windows runtime evidence.

For UI verification on an Apple Silicon development Mac, prepare `darwin-arm64` core and run `npm run build:mac:test`. This preview does not replace the existing native macOS distribution.

Dependency versions are locked in package-lock.json. Runtime third-party notices are collected into resources/THIRD-PARTY-LICENSES.txt; Electron/Chromium notices ship with the packaged runtime. Xray archives and executables are checked against pinned SHA-256 values.
