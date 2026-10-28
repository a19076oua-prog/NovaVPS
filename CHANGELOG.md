# Changelog

## 0.2.0 - 2026-10-28

- Add a Windows 10/11 x64 desktop application with an installer EXE and portable ZIP.
- Retain the native macOS SwiftUI application and its PKG distribution.
- Share the Linux VPS installer between platforms; bundle JavaScript SSH, local tunnel management and Xray verification on Windows.
- Add Chinese/English UI, private Windows ACL storage, node import/export and local QR generation.
- Add Windows build and packaged-runtime CI, with explicit platform validation evidence in VALIDATION.md.

## 0.1.1 — 2026-10-28

- Separate web-panel installation from new-node generation. An occupied node port, including TCP 443, no longer blocks installing the panel.
- Keep port-conflict protection when creating a new node; existing listeners are not replaced.
- Add private record recovery for upgrades and preserve confirmed SSH host fingerprints.
- Validate with 24 Python tests and 28 native checks, including real local OpenSSH forwarding and QR decoding.

## 0.1.0 — 2026-10-28

- Initial independent macOS SwiftUI VPS manager.
- Managed 3x-ui backend, password/key SSH authentication, pinned host keys, and loopback-only web access over SSH.
- VLESS / Reality / Vision node generation and JSON, YAML, VLESS link, QR export.
- Temporary local Xray connection verification without changing system proxy or TUN.

Real Linux VPS installation acceptance remains unverified; see VALIDATION.md.
