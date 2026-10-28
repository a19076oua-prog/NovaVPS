import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: VPSModel?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard model?.busy != true else { model?.error = "操作正在进行，请等待完成后退出。"; return .terminateCancel }
            Task { @MainActor in
                model?.password = ""; await model?.tunnel.close(); sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
    }
}

@main struct NovaVPSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: VPSModel
    init() {
        let arguments = CommandLine.arguments
        if arguments.count == 2, arguments[1] == "--ssh-askpass" {
            guard let password = ProcessInfo.processInfo.environment["NOVAPROXY_SSH_PASSWORD"] else { exit(1) }
            FileHandle.standardOutput.write(Data((password + "\n").utf8)); exit(0)
        }
        if arguments.count == 4, arguments[1] == "--supervise-xray" { exit(CoreSupervisor.runXray(core: arguments[2], config: arguments[3])) }
        if arguments.count == 3, arguments[1] == "--supervise-panel" {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2])); guard data.count <= 32 * 1024 else { exit(1) }
                exit(CoreSupervisor.runSSH(arguments: try JSONDecoder().decode([String].self, from: data)))
            } catch { exit(1) }
        }
        _model = StateObject(wrappedValue: VPSModel())
    }
    var body: some Scene {
        WindowGroup {
            ManagerView(model: model).onAppear { delegate.model = model }
                .frame(minWidth: 950, minHeight: 680).tint(NovaStyle.accent)
        }.defaultSize(width: 1080, height: 790)
    }
}

struct ManagerView: View {
    @ObservedObject var model: VPSModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var advanced = false
    @State private var showImport = false
    @State private var showQR = false
    @State private var stopConfirmation = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(page == 0 ? "VPS 管理" : "节点配置").font(.system(size: 24, weight: .semibold))
                        Text(page == 0 ? "部署服务，管理后台，生成配置。" : "生成后即可分享，或导入已有节点重新导出。")
                            .font(.system(size: 12)).foregroundStyle(NovaStyle.muted)
                    }
                    Spacer()
                    Picker("页面", selection: $page) { Text("管理").tag(0); Text("配置").tag(1) }
                        .pickerStyle(.segmented).frame(width: 140).labelsHidden()
                }.padding(28)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if page == 0 { setup; management }
                        else { configuration }
                        if model.busy { HStack(spacing: 10) { ProgressView().controlSize(.small); Text(model.status).font(.system(size: 13)) } }
                        else { Text(model.status).font(.system(size: 12)).foregroundStyle(NovaStyle.muted).textSelection(.enabled) }
                        if let error = model.error { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 13)).foregroundStyle(.red).textSelection(.enabled) }
                    }.frame(maxWidth: 820).padding(.horizontal, 28).padding(.bottom, 28).frame(maxWidth: .infinity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(NovaStyle.canvas)
            .sheet(isPresented: $showImport) { ImportNodeView(model: model) }
            .sheet(isPresented: $showQR) { if let node = model.node { NodeQRView(node: node) } }
            .confirmationDialog("停止后台也会停止它管理的节点服务。", isPresented: $stopConfirmation) {
                Button("停止后台与节点", role: .destructive) { Task { await model.perform(.stop) } }
                Button("取消", role: .cancel) { }
            }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) { Image(systemName: "server.rack").foregroundStyle(NovaStyle.accent).accessibilityHidden(true); Text("NovaVPS").font(.system(size: 19, weight: .semibold)) }.padding(.vertical, 16)
            HStack { NovaSectionTitle(title: "服务器"); Spacer(); Button { Task { await model.select(nil); page = 0 } } label: { Image(systemName: "plus") }.accessibilityLabel("新增 VPS").disabled(model.busy) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.records) { record in
                        Button { Task { await model.select(record); withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { page = 0 } } } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(record.request.host).font(.system(size: 11, design: .monospaced)).foregroundStyle(NovaStyle.muted).lineLimit(1)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(model.selectedID == record.id ? NovaStyle.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(model.busy).accessibilityAddTraits(model.selectedID == record.id ? .isSelected : [])
                    }
                    if model.records.isEmpty { Text("添加 VPS 后会保存在这里。") .font(.system(size: 12)).foregroundStyle(NovaStyle.muted).frame(maxWidth: .infinity, alignment: .leading) }
                }
            }
            Spacer(minLength: 0)
            Divider()
            Button("导入已有配置…") { showImport = true }.disabled(model.busy)
            Text("独立部署工具 · v0.2.0").font(.system(size: 11)).foregroundStyle(NovaStyle.muted)
        }.padding(18).frame(width: 198).background(NovaStyle.sidebar)
    }

    private var setup: some View {
        NovaPanel {
            HStack { NovaSectionTitle(title: "服务器登录"); Spacer(); Text(model.selected?.lastState.map(VPSModel.stateLabel) ?? "新 VPS").font(.system(size: 12)).foregroundStyle(NovaStyle.muted) }
            HStack(alignment: .top, spacing: 16) {
                field("服务器 IP", placeholder: "203.0.113.10", text: $model.request.host)
                field("SSH 端口", placeholder: "22", text: $model.sshPort).frame(width: 100)
            }
            HStack(alignment: .top, spacing: 16) {
                field("SSH 用户", placeholder: "root", text: $model.request.username)
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.request.passwordAuth ? "SSH 密码" : "SSH 私钥路径").font(.system(size: 12, weight: .medium))
                    if model.request.passwordAuth { SecureField("仅保留在本次软件会话", text: $model.password).accessibilityLabel("SSH 密码") }
                    else { TextField("留空使用 SSH Agent", text: $model.request.identityFile).accessibilityLabel("SSH 私钥路径") }
                }
            }
            HStack(alignment: .center, spacing: 16) {
                field("节点端口", placeholder: "443", text: $model.nodePort).frame(width: 130)
                Text("代理节点使用此 TCP 端口。云安全组与服务器防火墙需允许访问。")
                    .font(.system(size: 12)).foregroundStyle(NovaStyle.muted).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("更多设置", isExpanded: $advanced) {
                VStack(alignment: .leading, spacing: 14) {
                    field("备注", placeholder: "可选", text: $model.name)
                    Picker("SSH 认证", selection: $model.request.passwordAuth) { Text("密码").tag(true); Text("私钥 / Agent").tag(false) }.pickerStyle(.segmented)
                    Toggle("自动选择 Reality 目标", isOn: $model.request.autoTarget)
                    if !model.request.autoTarget { field("Reality 目标", placeholder: "dl.google.com", text: $model.request.serverName) }
                    Text("支持 Debian / Ubuntu、systemd、root 或免密码 sudo。后台仅监听 VPS 本机；新安装会校验固定版本的官方安装包。")
                        .font(.system(size: 12)).foregroundStyle(NovaStyle.muted)
                }.padding(.top, 10)
            }.font(.system(size: 12))
            Divider()
            HStack(spacing: 12) {
                Button("检查 SSH 指纹") { Task { await model.checkHost() } }.disabled(model.busy)
                Button("生成新节点") { Task { await model.perform(.provision) } }.buttonStyle(NovaPrimaryButtonStyle()).disabled(!model.canOperate)
                Spacer(minLength: 0)
            }
            if model.pinMatches, let pin = model.pin {
                Text(pin.fingerprint).font(.system(size: 11, design: .monospaced)).foregroundStyle(NovaStyle.muted).textSelection(.enabled)
                Toggle("已与 VPS 控制台核对 SSH 指纹", isOn: $model.hostConfirmed).font(.system(size: 12))
            }
            if let missing = model.missing { Text(missing).font(.system(size: 12)).foregroundStyle(NovaStyle.muted) }
            Text("SSH 密码不写入磁盘；切换 VPS 或退出软件即清除。") .font(.system(size: 11)).foregroundStyle(NovaStyle.muted)
        }.textFieldStyle(.roundedBorder).controlSize(.large).disabled(model.busy)
    }

    private var management: some View {
        NovaPanel {
            HStack {
                NovaSectionTitle(title: "后台与服务")
                Spacer()
                if let version = model.selected?.panelVersion { Text("3x-ui " + version).font(.system(size: 12)).foregroundStyle(NovaStyle.muted) }
            }
            HStack(spacing: 12) {
                Button("安装网页后台") { Task { await model.perform(.install) } }.disabled(!model.canOperate)
                Button("打开网页后台") { Task { await model.openPanel() } }.buttonStyle(NovaPrimaryButtonStyle()).disabled(!model.canOperate)
                Button("刷新状态") { Task { await model.perform(.inspect) } }.disabled(!model.canOperate)
                Menu("服务操作") {
                    Button("启动后台") { Task { await model.perform(.start) } }
                    Button("重启后台") { Task { await model.perform(.restart) } }
                    Button("停止后台与节点", role: .destructive) { stopConfirmation = true }
                }.disabled(!model.canOperate)
            }
            Text("安装后台会自动使用独立的本机端口；节点 443 被占用也可安装。")
                .font(.system(size: 12)).foregroundStyle(NovaStyle.muted)
            if let details = model.panel {
                HStack(spacing: 16) {
                    Button("复制初始用户名") { copy(details.username, notice: "初始后台用户名已复制。网页端改过账户时请使用新凭据。") }
                    Button("复制初始密码") { copy(details.password, notice: "初始后台密码已复制。网页端改过账户时请使用新凭据。") }
                }.font(.system(size: 12))
            }
            TunnelStatusView(tunnel: model.tunnel)
            Text("网页后台通过 SSH 隧道访问。关闭软件只断开后台访问，VPS 节点继续运行。")
                .font(.system(size: 12)).foregroundStyle(NovaStyle.muted)
            if model.node != nil {
                Divider()
                HStack {
                    Text("已有节点配置可导出。") .font(.system(size: 12)).foregroundStyle(NovaStyle.muted)
                    Spacer()
                    Button("查看配置") { page = 1 }
                }
            }
        }
    }

    @ViewBuilder private var configuration: some View {
        if let node = model.node {
            NovaPanel {
                NovaSectionTitle(title: "VLESS · REALITY · VISION")
                Text(node.server + ":" + String(node.port)).font(.system(size: 25, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                Text("Reality 目标：" + node.serverName).font(.system(size: 13)).foregroundStyle(NovaStyle.muted)
                if let record = model.selected, let date = record.verifiedAt {
                    Text("上次验证：HTTPS 204 · \(record.milliseconds ?? 0) ms · \(date.formatted())").font(.system(size: 12)).foregroundStyle(NovaStyle.success)
                } else { Text("配置已保存；尚无本机 HTTPS 验证结果。") .font(.system(size: 12)).foregroundStyle(NovaStyle.muted) }
                Divider()
                HStack(spacing: 12) {
                    Button("导出配置文件…") { model.exportFiles() }.buttonStyle(NovaPrimaryButtonStyle())
                    Button("显示二维码") { showQR = true }
                    Button("复制链接") { do { copy(try node.shareLink(), notice: "节点链接已复制。") } catch { model.error = error.localizedDescription } }
                }.disabled(model.busy)
                Text("Xray / V2Box JSON · Clash YAML · VLESS 分享链接 · 二维码 PNG") .font(.system(size: 12)).foregroundStyle(NovaStyle.muted)
                Button("验证节点连接") { Task { await model.verifySavedNode() } }.disabled(model.busy)
                Text("导出文件包含节点凭据，按私有文件权限保存。") .font(.system(size: 12)).foregroundStyle(NovaStyle.muted)
            }
        } else {
            NovaPanel {
                NovaEmptyState(icon: "doc.badge.gearshape", title: "还没有节点配置", detail: "先一键配置 VPS，或导入已有的 TCP VLESS / Reality / Vision 节点。")
                Button("导入已有配置…") { showImport = true }.frame(maxWidth: .infinity)
            }
        }
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 12, weight: .medium)); TextField(placeholder, text: text).accessibilityLabel(title) }
    }
    private func copy(_ value: String, notice: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string); model.status = notice }
}

struct TunnelStatusView: View {
    @ObservedObject var tunnel: PanelTunnel
    var body: some View {
        if let url = tunnel.url {
            HStack {
                Link("再次打开后台", destination: url)
                Text(url.absoluteString).font(.system(size: 11, design: .monospaced)).foregroundStyle(NovaStyle.muted).textSelection(.enabled)
                Spacer()
                Button("断开后台访问") { Task { await tunnel.close() } }
            }.font(.system(size: 12))
        }
    }
}

struct ImportNodeView: View {
    @ObservedObject var model: VPSModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("导入已有节点").font(.system(size: 22, weight: .semibold)); Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text("粘贴单个 VLESS 链接、Xray JSON 或 Clash YAML。本机提取节点参数，不上传；不导入原分流与 DNS 规则。")
                .font(.system(size: 12)).foregroundStyle(NovaStyle.muted)
            TextEditor(text: $text).font(.system(size: 12, design: .monospaced)).frame(height: 220).border(NovaStyle.line)
            HStack {
                Button("选择文件…") {
                    let dialog = NSOpenPanel(); dialog.canChooseDirectories = false; dialog.allowsMultipleSelection = false
                    if dialog.runModal() == .OK, let url = dialog.url {
                        do { let data = try Data(contentsOf: url); guard data.count <= Configuration.maxBytes, let content = String(data: data, encoding: .utf8) else { throw ProxyError("配置文件过大或不是 UTF-8。") }; text = content }
                        catch { self.error = error.localizedDescription }
                    }
                }
                Spacer()
                Button("导入节点") { do { try model.importNode(text); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(NovaPrimaryButtonStyle()).disabled(text.isEmpty)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
        }.padding(28).frame(width: 610).background(NovaStyle.canvas)
    }
}

struct NodeQRView: View {
    let node: DeployedNode
    @Environment(\.dismiss) private var dismiss
    @State private var data: Data?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 18) {
            HStack { Text("节点二维码").font(.system(size: 22, weight: .semibold)); Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 280, height: 280)
                    .padding(14).background(.white, in: RoundedRectangle(cornerRadius: 16)).accessibilityLabel("节点二维码，包含连接凭据")
            }
            Text("使用客户端扫码导入。二维码包含节点凭据。") .font(.system(size: 12)).foregroundStyle(NovaStyle.muted)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
        }.padding(28).frame(width: 450).background(NovaStyle.canvas)
            .onAppear { do { data = try NodeSharing.qrPNG(node.shareLink()) } catch { self.error = error.localizedDescription } }
    }
}
