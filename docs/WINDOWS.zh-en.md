# Windows 使用说明 / Windows User Guide

适用：NovaVPS Desktop 0.2.0，Windows 10/11 x64。macOS 原生版仍提供独立 PKG 安装包。

Applies to NovaVPS Desktop 0.2.0 on Windows 10/11 x64. The native macOS application remains available as a separate PKG installer.

## 安装 / Installation

- 下载 `NovaVPS-0.2.0-Windows-x64-Setup.exe`，按向导安装。默认只安装到当前用户，不要求管理员权限。
- 或下载 `NovaVPS-0.2.0-Windows-x64.zip`，完整解压后运行其中的 `NovaVPS.exe`。不要只复制一个 EXE；旁边的 DLL 和资源必须保留。
- 不需要另外安装 Node.js、Python 或 OpenSSH。当前 Windows 包未做 Authenticode 签名。

- Download `NovaVPS-0.2.0-Windows-x64-Setup.exe` and follow the installer. The default installation is per-user and does not request administrator privileges.
- Alternatively, download `NovaVPS-0.2.0-Windows-x64.zip`, extract it completely, then run `NovaVPS.exe`. Keep the adjacent DLLs and resources; the executable is not standalone.
- Node.js, Python and OpenSSH are not required on the Windows client. The Windows package is not Authenticode-signed.

## 首次使用 / First use

1. 打开 NovaVPS；右上角可切换中文 / English。
2. 输入 VPS IP、SSH 管理端口、用户和 SSH 密码。已有密码即可使用，无需额外生成 SSH 密钥。
3. 点击“检查 SSH 指纹”，与 VPS 控制台核对，再勾选确认。
4. 只需要后台，点击“安装网页后台”；这个操作不占用节点 443。后台就绪后点击“打开网页后台”，复制初始用户名和密码登录。
5. 要生成新的代理节点，填写实际空闲、且不同于 SSH 的节点 TCP 端口，放行相应云安全组和服务器防火墙，再点“生成新节点”。
6. 在“配置”页导出 Xray JSON、Clash YAML、VLESS 链接和二维码；点击“验证节点连接”进行 HTTPS 204 验证。

1. Open NovaVPS and choose Chinese or English in the top-right language selector.
2. Enter the VPS IP, SSH management port, username and SSH password. Password authentication does not require generating an SSH key.
3. Click Check SSH fingerprint, compare it with the VPS console, then confirm it.
4. For the web panel alone, click Install web panel. This does not claim node port 443. Once ready, click Open web panel and use the generated initial username and password.
5. For a new proxy node, choose an unused TCP port different from SSH, allow it through the cloud security group and server firewall, then click Generate new node.
6. Use Configuration to export Xray JSON, Clash YAML, a VLESS link and QR code. Verify connection performs an HTTPS 204 check.

## 数据与认证 / Data and authentication

Windows 本机记录在 `%APPDATA%\NovaVPS Desktop\private\servers.json`。记录包含节点访问参数，应按私有文件保管；不保存 SSH 密码、私钥口令或后台 API Token。Windows 版使用当前用户与 SYSTEM 的目录 ACL，不依赖 Unix chmod。

Local Windows records are stored in `%APPDATA%\NovaVPS Desktop\private\servers.json`. They contain node access parameters and should remain private. SSH passwords, key passphrases and panel API tokens are not saved there. The Windows version uses a directory ACL for the current user and SYSTEM instead of relying on Unix chmod.

密码和私钥口令只保留在当前会话；切换服务器或退出会清除。SSH Agent 模式需要已有可用 Agent；Windows 默认使用 OpenSSH Agent 命名管道，或使用 SSH_AUTH_SOCK 指定的 Agent。

Passwords and key passphrases remain in the current session and are cleared when switching servers or quitting. SSH Agent mode requires a working agent; Windows uses the OpenSSH Agent named pipe by default, or SSH_AUTH_SOCK when set.

首次启动服务器列表为空。发布包不带个人 VPS、SSH 密码、节点配置或后台账户。Windows 与 macOS 使用各自的本机记录，不会自动同步账户数据。

The server list starts empty. Distributions contain no personal VPS records, SSH passwords, node configurations or panel accounts. Windows and macOS keep separate local records; account data is not synchronized automatically.

## 常见问题 / Troubleshooting

| 现象 / Symptom | 处理 / Resolution |
| --- | --- |
| 443 已占用 / Port 443 occupied | 安装后台可以继续；新节点必须选择实际空闲端口。 / Panel installation can proceed; a new node requires an unused port. |
| SSH 认证失败 / Authentication failed | 检查服务器密码、SSH 用户和管理端口；它们不是订阅密码与节点端口。 / Check the server password, SSH username and management port, rather than subscription credentials or the node port. |
| 更新后按钮禁用 / Buttons disabled after relaunch | 密码按设计不落盘，请重新输入。 / Re-enter the password; it is intentionally not saved. |
| ZIP 版启动失败 / Portable build fails to start | 完整解压 ZIP，保留所有 DLL 和 resources 文件夹。 / Extract the entire ZIP and preserve all DLLs and the resources folder. |
| 配置生成但验证失败 / Generated but unverified | 查看云安全组、服务器防火墙、VPS 出站网络和节点服务。 / Check the security group, server firewall, VPS outbound access and node service. |
| 退出后后台地址失效 / Local panel URL stops working | 重新登录 SSH 并打开后台；远程节点服务不会因退出软件而停止。 / Reconnect through SSH and open the panel; quitting the app does not stop remote node services. |

Windows 适配版复用现有 Linux VPS 安装程序。完整真实 VPS 安装验收与各平台运行证据以根目录 `VALIDATION.md` 为准；编译成功不等同于真实网络部署成功。

The Windows port reuses the Linux VPS installer. See the root VALIDATION.md for platform runtime evidence and real-VPS acceptance limits; a successful build is not proof of successful live network deployment.
