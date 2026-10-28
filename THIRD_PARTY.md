# Third-party components

- NovaVPS is GPL-3.0. Shared SSH transport, configuration exporters, local probe supervision, QR generation and visual tokens derive from the NovaProxy sources in this workspace. Exact sources are recorded in SHARED_SOURCES.json. The desktop client does not require NovaProxy to run.
- Yams 6.2.2 is MIT licensed. Its unmodified source and license are included under ThirdParty/Yams.
- Xray-core v26.10.21 is MPL-2.0 licensed. The unmodified arm64 macOS core is bundled. LICENSE is included; matching source is available from https://github.com/XTLS/Xray-core/tree/v26.10.21 . Archive and binary provenance are in Resources/core-manifest.json.
- 3x-ui v3.11.0 is GPL-3.0 licensed: https://github.com/MHSanaei/3x-ui/tree/v3.11.0 . Its binary is not bundled with the desktop application. When explicitly configured by the user, the VPS installer downloads the official Linux release and checks the pinned SHA-256. The full original license is included as ThirdParty/3x-ui-LICENSE. The management API follows the matching source and OpenAPI specification.
- Apple SwiftUI, AppKit, CoreImage and SF Symbols provide native controls and local QR rendering. SSH is provided by macOS OpenSSH. No online configuration converter is used.
- UI design guidance follows the already-installed UI UX Pro Max skill. No MotionSites templates, fonts, video or image assets are embedded.

## Cross-platform desktop client

Desktop/ uses Electron 45.1.0 (MIT), ssh2 1.17.0 (MIT), yaml 2.9.1 (ISC), and qrcode 1.5.4 (MIT). Versions and package integrity are locked in Desktop/package-lock.json. The Windows installer includes the Electron/Chromium notices, runtime package licenses, and Desktop/resources/THIRD-PARTY-LICENSES.txt. No native SSH module is required. The app icon is an original code-drawn SVG with matching generated PNG/ICO/ICNS assets, licensed with this project. Electron builder 26.18.0 and test tools are development dependencies.

The Windows Xray core is the pinned official v26.10.21 Windows x64 executable; the archive SHA-256 is recorded in Desktop/scripts/prepare-core.cjs and the extracted executable hash is stored with each build. Program code is not modified. Matching source and MPL-2.0 license are provided through the existing Xray provenance and license files.
