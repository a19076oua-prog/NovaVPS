# NovaVPS 使用说明书 / User Guide

**适用版本 / Applies to:** NovaVPS 0.1.1 · macOS Apple Silicon  
**文档日期 / Document date:** 2026-10-28

NovaVPS 是独立的 VPS 部署与后台管理软件。它在 Mac 上管理远程服务器，通过 SSH 安装专属 3x-ui 网页后台，并生成、导出节点配置。无需启动 NovaProxy。

NovaVPS is a standalone VPS deployment and management application. It runs on your Mac, uses SSH to install a managed 3x-ui web panel on a remote server, and generates and exports node configurations. NovaProxy does not need to be running.

> **分发内容 / Distribution:** 发布的源码和安装包不包含个人 VPS、SSH 密码、节点凭据或后台账户。首次使用时服务器列表为空，这是正常状态。安装或更新软件不会主动清空已有本机记录。
>
> The distributed source and installer do not contain personal VPS records, SSH passwords, node credentials, or panel accounts. An empty server list on first launch is expected. Installing or updating the app does not intentionally erase existing local records.

## 1. 准备条件 / Requirements

| 项目 / Item | 要求 / Requirement |
| --- | --- |
| Mac | Apple Silicon；应用声明最低 macOS 13。当前构建与验证环境见 VALIDATION.md。 / Apple Silicon; the app declares macOS 13 as its minimum. See VALIDATION.md for the actual build and validation environment. |
| VPS 系统 / VPS OS | Debian 或 Ubuntu，使用 systemd；x86_64 或 arm64。 / Debian or Ubuntu with systemd; x86_64 or arm64. |
| SSH 登录 / SSH access | 有效 IP、SSH 端口、用户名，以及密码或可用的私钥 / SSH Agent。 / A valid IP, SSH port, username, and password or working private key / SSH Agent. |
| 系统权限 / Privileges | root，或支持免密码 sudo 的账户。 / root, or an account with passwordless sudo. |
| 服务器网络 / Server network | 能下载 GitHub 官方发布包；生成节点时还需访问合适的 Reality 目标站。 / Access to official GitHub release downloads; node generation also requires a suitable reachable Reality target. |
| 端口 / Ports | SSH 管理端口可达。生成新节点时，所选 TCP 端口必须空闲并允许外部访问。 / The SSH management port must be reachable. A new node requires an unused TCP port that is reachable from outside. |

只有 IP 和端口不能证明服务器可登录。SSH 密码是服务器登录密码，不是代理订阅密码。已有 SSH 密码时不需要另外生成 SSH 密钥。

An IP and port alone are not enough to authenticate to a server. The SSH password is the server login password, not a proxy subscription password. Password authentication does not require generating an SSH key.

## 2. 安装与界面 / Installation and interface

1. 从项目发布附件获取 `NovaVPS-Installer.pkg`。
2. 运行安装包，将软件安装到“应用程序”。
3. 打开 **NovaVPS**。
4. 左侧添加或选择 VPS；右侧在“管理”和“配置”之间切换。

1. Download `NovaVPS-Installer.pkg` from the project's release attachments.
2. Run the installer to install the app in Applications.
3. Open **NovaVPS**.
4. Add or select a VPS in the sidebar, then use the Manage or Configuration page.

安装包只在 Mac 上安装应用，不安装 TUN 驱动、特权网络助手或系统后台守护程序。本版本使用本地临时签名，未经过 Apple 公证。

The installer places the application on your Mac. It does not install a TUN driver, privileged networking helper, or system daemon on the Mac. This version is ad-hoc signed and is not notarized by Apple.

### 界面名称对照 / Interface label reference

当前应用界面以中文显示；下表是本说明书中的英文对应名称。

The current application interface uses Chinese labels. The English names below are translations for this guide.

| 界面文字 / UI label | English meaning |
| --- | --- |
| 管理 | Manage |
| 配置 | Configuration |
| 新增 VPS | Add VPS |
| 更多设置 | More settings |
| 检查 SSH 指纹 | Check SSH fingerprint |
| 已与 VPS 控制台核对 SSH 指纹 | I have verified the fingerprint against the VPS console |
| 安装网页后台 | Install web panel |
| 打开网页后台 | Open web panel |
| 生成新节点 | Generate new node |
| 刷新状态 | Refresh status |
| 服务操作 | Service actions |
| 导入已有配置… | Import existing configuration… |
| 导出配置文件… | Export configuration files… |
| 显示二维码 | Show QR code |
| 复制链接 | Copy link |
| 验证节点连接 | Verify node connection |

## 3. 填写服务器信息 / Enter server information

| 字段 / Field | 填写内容 / What to enter |
| --- | --- |
| 服务器 IP / Server IP | VPS 的实际 IPv4 或 IPv6；不填网页 URL。 / The actual IPv4 or IPv6 address of the VPS, not a web URL. |
| SSH 端口 / SSH port | 服务商提供的 SSH 管理端口，通常为 22，也可能是其他端口。 / The SSH management port supplied by the provider, often 22 but possibly another port. |
| SSH 用户 / SSH user | 通常为 root；其他用户需满足 sudo 条件。 / Usually root; other users must meet the sudo requirement. |
| SSH 密码 / SSH password | 当前服务器登录密码。 / The current server login password. |
| 节点端口 / Node port | 新代理节点使用的 TCP 端口，例如 443 或 8443；必须空闲，且与 SSH 端口不同。 / The TCP port for a new proxy node, such as 443 or 8443; it must be unused and different from the SSH port. |
| 备注 / Name | 可选的本机服务器名称。 / An optional local name for the server. |
| SSH 认证 / SSH authentication | 密码，或私钥 / Agent。加密私钥需预先加入 SSH Agent。 / Password, or private key / Agent. Load an encrypted key into SSH Agent beforehand. |
| Reality 目标 / Reality target | 默认自动选择；手动目标需具备有效证书、TLS 1.3 和 h2，并能从 VPS 访问。 / Selected automatically by default; a manual target must have a valid certificate, TLS 1.3 and h2, and be reachable from the VPS. |

本说明书若出现 `203.0.113.10`，仅表示文档示例，不是可连接的服务。请填写自己的 VPS 信息。

Any occurrence of `203.0.113.10` in documentation is an example address, not an available service. Enter your own VPS details.

### 核对 SSH 指纹 / Verify the SSH fingerprint

点击“检查 SSH 指纹”，将显示的 SHA-256 指纹与 VPS 控制台或服务商提供的信息核对，确认一致后再勾选确认框。公钥变化后需要重新核对。

Click Check SSH fingerprint. Compare the displayed SHA-256 fingerprint with the VPS console or provider's trusted information, then select the confirmation checkbox only if it matches. Verify again if the key changes.

## 4. 独立安装网页后台 / Install the web panel independently

适用于希望先管理服务器后台，或现有节点已占用 443 的情况。

Use this workflow when you want the web panel first, or when an existing service already uses port 443.

1. 完成登录信息和指纹确认。
2. 点击 **安装网页后台**。
3. 等待软件显示后台就绪。首次安装需要下载官方包，可能耗时数分钟。
4. 点击 **打开网页后台**。
5. 使用“复制初始用户名”和“复制初始密码”获取本次安装生成的账户，在浏览器中登录。

1. Complete the login fields and fingerprint verification.
2. Click **Install web panel**.
3. Wait for the panel-ready message. The initial installation downloads an official release and may take several minutes.
4. Click **Open web panel**.
5. Use Copy initial username and Copy initial password to obtain the account generated by this installation, then sign in through the browser.

后台自动选择独立的 VPS 本机端口。这个操作不检查或修改所填节点端口，也不会接管占用 443 的原服务；当前表单仍要求有效的节点端口，并要求它与 SSH 端口不同。

The panel uses its own automatically selected loopback port on the VPS. This action does not probe or modify the chosen node port and does not take over the existing service on port 443. The current form still requires a valid node-port value that differs from the SSH port.

后台默认只监听 VPS 的 `127.0.0.1`，通过 SSH 隧道映射到 Mac 的本机地址。这个网页地址只能在建立隧道的 Mac 上使用；无需向公网开放后台端口。点击“断开后台访问”或退出软件会关闭隧道，VPS 服务继续运行。

By default, the panel listens only on `127.0.0.1` on the VPS. An SSH tunnel exposes it at a local address on your Mac. That browser address is usable only on the Mac with the active tunnel; the panel port does not need public exposure. Disconnecting panel access or quitting the app closes the tunnel while the VPS service continues running.

## 5. 生成新节点 / Generate a new node

1. 选择空闲节点端口。不要使用当前 SSH 端口，也不要覆盖已有服务。
2. 确认云安全组和服务器防火墙允许外部访问该 TCP 端口。
3. 点击 **生成新节点**。如果尚未安装专属后台，软件会先安装后台。
4. 等待节点保存和本机 HTTPS 验证。
5. 进入 **配置** 页面，导出文件、复制链接或显示二维码。

1. Choose an unused node port. Do not use the current SSH port or replace an existing service.
2. Ensure the cloud security group and server firewall permit external access to that TCP port.
3. Click **Generate new node**. If the managed panel is absent, the app installs it first.
4. Wait for the node to be saved and for the local HTTPS verification.
5. Open **Configuration** to export files, copy the link, or show the QR code.

软件生成 TCP VLESS / Reality / Vision 格式。配置生成与连接成功是两个结果：只有通过临时本机 Xray 入口收到 HTTPS 204，才显示验证成功。验证失败时仍保留已生成的配置，便于修复网络后重试。显示的毫秒值是 HTTPS 测试耗时，不是带宽测速结果；上次验证时间不代表当前持续在线。

The app generates TCP VLESS / Reality / Vision nodes. Configuration generation and connection success are separate outcomes: verification succeeds only after an HTTPS 204 is received through the temporary local Xray proxy. Generated configurations remain available if verification fails, so you can retry after fixing the network. The displayed milliseconds measure the HTTPS test duration, not bandwidth throughput; the last-verification time does not guarantee continuous availability.

NovaVPS 不自动修改云安全组或服务器防火墙，也不提供本机 TUN / 全设备 VPN 接管。导出配置需要在兼容的代理客户端中使用。

NovaVPS does not automatically change cloud security groups or server firewall rules and does not provide local TUN or full-device VPN interception. Use the exported configuration in a compatible proxy client.

## 6. 导出、分享与导入 / Export, share and import

“导出配置文件…”会在所选位置创建一个新的私有文件夹。

Export configuration files creates a new private folder in your selected location.

| 文件 / File | 用途 / Purpose |
| --- | --- |
| `node.xray.json` | Xray / 支持 Xray JSON 的 V2Box 等客户端。 / Xray and clients such as V2Box that support Xray JSON. |
| `node.clash.yaml` | 支持对应 VLESS / Reality 格式的 Clash 系客户端。 / Clash-family clients supporting the corresponding VLESS / Reality format. |
| `node.vless.txt` | VLESS 分享链接。 / VLESS share link. |
| `node-qr.png` | 包含相同分享链接的二维码。 / QR code containing the same share link. |

分享链接和二维码包含节点连接凭据。只分享给你希望获得节点访问权的人。二维码在本机生成，不依赖在线转换网站。

Share links and QR codes contain node access credentials. Share them only with people you intend to give node access to. QR codes are generated locally without an online conversion service.

“导入已有配置…”支持单个 TCP VLESS / Reality / Vision 的 VLESS 链接、Xray JSON 或 Clash YAML。只提取节点，不导入原分流、DNS 规则或 SSH 登录信息。导入已有节点不表示服务器已安装本软件的后台。无法完整保留的自定义链式、传输或指纹参数会被拒绝，而不是静默改写。

Import existing configuration accepts a single TCP VLESS / Reality / Vision node as a VLESS link, Xray JSON, or Clash YAML. It extracts the node only, without importing original routing rules, DNS rules, or SSH login details. Importing a node does not mean that the managed panel is installed on its server. Unsupported custom chaining, transport, or fingerprint settings are rejected rather than silently rewritten.

## 7. 日常后台管理 / Routine panel management

| 操作 / Action | 效果 / Effect |
| --- | --- |
| 刷新状态 / Refresh status | 通过 SSH 查询专属后台状态。 / Query the managed panel through SSH. |
| 启动后台 / Start panel | 启动本软件管理的服务。 / Start the app-managed service. |
| 重启后台 / Restart panel | 重启该后台，其管理的节点连接可能暂时中断。 / Restart the panel; connections through its nodes may briefly disconnect. |
| 停止后台与节点 / Stop panel and nodes | 停止该后台及其管理的节点，需要确认。 / Stop the panel and its managed nodes; confirmation is required. |
| 退出 NovaVPS / Quit NovaVPS | 断开本机后台隧道、清除会话密码，远程服务继续运行。 / Close the local panel tunnel and clear the session password while remote services continue running. |

软件仅管理自己创建的 `novavps-panel.service`，不会覆盖或自动接管已有的标准 3x-ui 安装。网页后台可以管理更多协议；这些协议的配置请从网页后台导出。

The app manages only the `novavps-panel.service` instance it creates. It does not overwrite or automatically adopt an existing standard 3x-ui installation. The web panel can manage additional protocols; export those configurations from the panel itself.

如果在网页端修改了初始用户名或密码，之后使用新凭据登录；原生软件中的“复制初始密码”不会显示新密码。不要修改专属后台的监听地址、端口或根路径，否则原生入口可能失效。

If you change the initial username or password in the web panel, use the new credentials thereafter. Copy initial password in the desktop app does not retrieve the changed password. Changing the managed panel's listen address, port, or base path can break the native management entry.

## 8. 常见问题 / Troubleshooting

| 现象 / Symptom | 处理方式 / What to do |
| --- | --- |
| 按钮点不了 / Button disabled | 检查 IP、端口、用户格式、认证信息和指纹确认框；操作进行中也会禁用按钮。 / Check the IP, ports, username format, authentication, and fingerprint confirmation. Buttons are also disabled during an active operation. |
| 节点端口 443 已占用 / Node port 443 occupied | 只需要后台时点“安装网页后台”；生成新节点时选择实际空闲的端口。 / Use Install web panel if you only need the panel; choose a genuinely unused port for a new node. |
| SSH 认证失败 / SSH authentication failed | 核对服务器登录用户、密码、SSH 端口；加密私钥需加入 Agent。 / Verify the server username, password, and SSH port; load encrypted keys into Agent. |
| SSH 超时或拒绝连接 / SSH timeout or refusal | 检查服务器在线状态、SSH 服务、管理端口、安全组以及当前网络。 / Check server availability, SSH service, management port, security group, and your network. |
| SSH 指纹变化 / SSH fingerprint changed | 先从 VPS 控制台确认服务器身份，再重新检查和确认；不要直接忽略变化。 / Confirm the server's identity through its console before rechecking and confirming the new fingerprint. |
| 配置已生成但验证失败 / Generated configuration fails verification | 检查所选节点 TCP 端口的安全组与防火墙、VPS 出站网络和服务状态，再点“验证节点连接”。 / Check the node TCP port's security group and firewall, VPS outbound network, and service state; then retry Verify node connection. |
| 网页后台未运行 / Panel not running | 先安装后台，或在“服务操作”中启动它，然后刷新状态。 / Install the panel or start it through Service actions, then refresh status. |
| 关闭软件后本机网页打不开 / Local panel URL stops working after quitting | SSH 隧道已关闭；重新输入 SSH 登录信息并点击“打开网页后台”。 / The SSH tunnel has closed; re-enter SSH credentials and click Open web panel. |
| 已有标准 3x-ui，安装被拒绝 / Existing standard 3x-ui blocks installation | 使用原后台，或选择另一台 VPS；当前版本不会接管它。 / Use the existing panel or another VPS; this version does not adopt it. |
| 系统或 sudo 不符合要求 / Unsupported OS or sudo setup | 使用受支持的 Debian / Ubuntu 和 root / 免密码 sudo 账户。 / Use a supported Debian / Ubuntu system and root or passwordless sudo. |

不要因看到端口占用就停止未知进程、关闭防火墙或反复重装。先确认服务用途，并区分 SSH 端口、代理节点端口和后台本机端口。

Do not respond to a port conflict by stopping unknown processes, disabling the firewall, or repeatedly reinstalling. Identify the service first and distinguish the SSH port, proxy node port, and panel loopback port.

## 9. 数据与隐私 / Data and privacy

| 位置 / Location | 内容 / Contents |
| --- | --- |
| Mac：`~/Library/Application Support/NovaVPS/servers.json` | 本机 VPS 记录、SSH 公钥指纹、节点客户端参数。目录权限 700、文件权限 600。 / Local VPS records, SSH public-key fingerprints, and client node parameters. Directory mode 700; file mode 600. |
| Mac 会话内存 / Mac session memory | SSH 密码；切换 VPS 或退出时清除，不由应用写入记录文件。 / SSH password; cleared when switching VPS or quitting, and not written to record files by the app. |
| VPS：`/opt/novavps-panel` | 专属后台程序。 / Managed panel program. |
| VPS：`/var/lib/novavps-panel` | 后台数据库和私有管理记录，包含初始后台账户与 API 凭据。 / Panel database and private management state, including initial panel credentials and API credentials. |
| VPS：`/var/log/novavps-panel` | 专属后台日志目录。 / Managed panel log directory. |
| 你选择的导出文件夹 / Selected export folder | 包含访问凭据的客户端配置、链接和二维码，按私有文件权限保存。 / Client configurations, link, and QR containing access credentials, saved with private file permissions. |

本机记录不是无敏感信息的普通文档：其中的节点参数可以赋予节点访问权。GitHub 发布仅包含程序、源码、测试和文档，不包含上述本机运行数据、私人导出文件或远程后台数据库。

Local records are not ordinary non-sensitive documents: their node parameters can grant node access. GitHub distributions contain the application, source, tests, and documentation, excluding these local runtime records, private exports, and remote panel databases.

## 10. 验证状态与许可 / Validation and licensing

当前版本通过 24 项 Python 测试和 28 项原生检查，包含配置往返、二维码解码、真实 macOS OpenSSH 连接本地隔离测试服务器，以及 SSH 转发与关闭清理。**这些测试不等于真实 Linux VPS 安装成功；当前尚未完成真实 Debian / Ubuntu VPS 的完整安装验收。**

This version passed 24 Python tests and 28 native checks, including configuration round trips, QR decoding, actual macOS OpenSSH connections to an isolated local test server, and SSH forwarding and cleanup. **These tests do not establish successful deployment to a real Linux VPS; end-to-end acceptance on a real Debian / Ubuntu VPS remains unverified.**

程序采用 GPL-3.0，包含 Yams 和 Xray-core 等第三方组件；3x-ui 由服务器安装流程下载固定官方版本并校验哈希。组件版本、来源、许可和验证细节见仓库根目录的 `THIRD_PARTY.md`、`LICENSE`、`SHARED_SOURCES.json`、`Resources/core-manifest.json` 和 `VALIDATION.md`。

The application is GPL-3.0 licensed and includes third-party components such as Yams and Xray-core. The server installer downloads a pinned official 3x-ui release and verifies its hash. See `THIRD_PARTY.md`, `LICENSE`, `SHARED_SOURCES.json`, `Resources/core-manifest.json`, and `VALIDATION.md` at the repository root for component versions, provenance, licensing, and validation details.
