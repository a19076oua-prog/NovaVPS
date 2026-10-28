# NovaVPS 0.2.0

[macOS 中英双语使用说明书 / macOS Chinese–English User Guide](docs/USER_GUIDE.zh-en.md)


**Windows + macOS**：Windows 10/11 x64 提供安装 EXE 与便携 ZIP；macOS Apple Silicon 继续提供原生 SwiftUI PKG。两个平台都支持后台安装、SSH 隧道和配置分享，发布包均为空白个人数据。

**Windows + macOS**: installer EXE and portable ZIP for Windows 10/11 x64; native SwiftUI PKG retained for Apple Silicon macOS. Both manage the panel, SSH tunnel and configuration sharing, without bundled personal data.

[Windows 中英说明 / Windows guide](docs/WINDOWS.zh-en.md) · [Desktop 构建 / Build](Desktop/README.md)

独立的 VPS 部署与管理软件。无需启动 NovaProxy。

## 能做什么

- 输入 VPS 的 IP、SSH 端口、用户名与密码，核对 SSH 指纹后，一键安装专属 3x-ui 后台并生成 VLESS / Reality / Vision 节点。
- 在软件中查看状态、启动、停止或重启后台；通过 SSH 隧道一键打开网页管理界面。
- 导出 Xray / V2Box JSON、Clash YAML、VLESS 分享链接、二维码 PNG。
- 导入单个相同格式的已有节点，重新生成四种分享文件。导入只提取节点，不搬运原分流和 DNS 规则。
- 部署后通过临时、需要认证的本机 Xray 入口发起 HTTPS 204 请求，显示连接是否验证成功。不会修改系统代理或 TUN。

## 使用

1. Windows：运行发布附件中的 `NovaVPS-0.2.0-Windows-x64-Setup.exe`；或完整解压便携 ZIP 后运行 `NovaVPS.exe`。macOS：安装 `NovaVPS-Installer.pkg`，从“应用程序”打开 **NovaVPS**。
2. 填写 VPS IP、SSH 端口（通常 22）、SSH 用户、密码和空闲节点端口。
3. 点击“检查 SSH 指纹”，与服务商控制台核对后勾选确认。
4. 只需要后台时，点击“安装网页后台”；不检查或修改节点端口，原有 443 服务可以继续运行。需要新节点时，点击“生成新节点”，所填端口必须空闲。首次下载可能需要数分钟。SSH 密码不保存到磁盘；切换 VPS 或退出即清除。
5. 点击“打开网页后台”，复制初始用户名、密码登录；或进入“配置”导出文件和二维码。

目标 VPS 需要 Debian / Ubuntu、systemd、x86_64 或 arm64，以及 root 或免密码 sudo。还需要能访问 GitHub 和 Reality 目标站。SSH 密码是 VPS 的登录密码，不是代理订阅密码；只给一个任意 IP 和端口不能部署。

云安全组和服务器防火墙需要允许**所选节点的 TCP 端口**。软件不会代管云账号或自动放行云安全组。端口已占用时请选择其他空闲端口，例如 8443；软件会拒绝覆盖现有服务。

## 网页后台

采用固定版本 3x-ui v3.11.0，下载官方包并校验固定 SHA-256。默认后台只监听 VPS 的 127.0.0.1；新安装关闭订阅监听，通过软件建立的 SSH 隧道进入网页。关闭隧道或退出软件不会停止 VPS 节点。

专属服务为 `novavps-panel.service`，程序在 `/opt/novavps-panel`，私有数据在 `/var/lib/novavps-panel`。不会覆盖已有标准 3x-ui；已安装标准 3x-ui 的 VPS 需继续使用原后台或选择另一台 VPS。软件仅管理自己创建的这套后台。

网页端可以管理更多协议。原生配置导出目前只支持 TCP VLESS / Reality / Vision，其他协议请从网页后台导出。网页端修改初始账户后使用新凭据登录；“复制初始密码”不会显示网页端的新密码。不要修改专属后台的监听 IP、端口或根路径，否则原生管理入口会失效。

## 文件与隐私

macOS 原生版记录在 `~/Library/Application Support/NovaVPS/servers.json`，目录权限 700、文件权限 600。Windows 版记录在 `%APPDATA%\NovaVPS Desktop\private\servers.json`，使用当前用户和 SYSTEM 的私有 ACL。保存 SSH 公钥指纹与节点客户端参数，不保存 SSH 密码或后台 API Token。导出文件包含节点凭据，也使用私有文件权限。二维码在本机生成。

## 验证边界

见 [VALIDATION.md](VALIDATION.md)。已完成本地原生构建、远程管理逻辑测试、真实 macOS OpenSSH 连接本地隔离测试服务器、SSH 转发、配置校验和二维码解码验证。**尚未使用真实 Linux VPS 完成安装验收**；没有把模拟后台测试当成真实部署成功。

## 构建

Apple Silicon Mac，macOS 13+。当前验证使用 Swift 6.3.3、MacOSX26.5 SDK。`scripts/build.sh` 直接编译原生 SwiftUI 程序与附带 Yams 源码。把经过 `Resources/core-manifest.json` 所列官方归档哈希校验的 Xray arm64 二进制传给 `NOVAVPS_XRAY_BINARY`。

```sh
NOVAVPS_XRAY_BINARY=/absolute/path/to/xray bash scripts/build.sh
python3 Tests/test_manager.py
```

Windows 构建使用 `Desktop/` 中固定版本的 Electron、内置 SSH 客户端和官方 Xray 内核，详见 [构建说明](Desktop/README.md)。Windows 安装包未做 Authenticode 签名；macOS 程序使用本地临时签名，未做 Apple 公证。源码和第三方许可随包提供；详见 LICENSE、THIRD_PARTY.md 和 SHARED_SOURCES.json。

仓库只保存源码、测试和文档；应用、安装包与源码分发 ZIP 作为发布附件提供。本地服务器记录、SSH 密码和导出节点文件不进入 Git。

## English quick start

NovaVPS is a standalone Windows and macOS VPS manager. Install its managed 3x-ui panel, open it through an SSH tunnel, and generate TCP VLESS / Reality / Vision node configurations.

1. Windows: run `NovaVPS-0.2.0-Windows-x64-Setup.exe`, or fully extract the portable ZIP and run `NovaVPS.exe`. macOS: install `NovaVPS-Installer.pkg` and open NovaVPS.
2. Enter your VPS IP, SSH port, username and password, then check and confirm the SSH fingerprint against the VPS console.
3. Use **安装网页后台 / Install web panel** for the panel alone. An occupied node port does not block this workflow. Use **生成新节点 / Generate new node** only with an unused node port.
4. Open the web panel and copy its initial login credentials, or open **配置 / Configuration** to export Xray JSON, Clash YAML, a VLESS link and a QR PNG.

Client requirements: Windows 10/11 x64 or Apple Silicon macOS 13+. VPS requirements: Debian/Ubuntu with systemd, x86_64 or arm64, and root or passwordless sudo. Cloud and server firewalls must permit the selected node TCP port; the app does not open these rules automatically.

Distributions start with empty personal data. Your VPS records, SSH passwords and exported node credentials are not included. Local tests have passed; end-to-end installation on a real Linux VPS is not yet verified. See the [full bilingual guide](docs/USER_GUIDE.zh-en.md) and [validation record](VALIDATION.md).
