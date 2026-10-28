import Foundation
import Combine
import AppKit
import Darwin

struct SavedPin: Codable {
    let host: String, port: Int, knownHost: String, algorithm: String, fingerprint: String
    init(_ value: ServerPin) { host = value.host; port = value.port; knownHost = value.knownHost; algorithm = value.algorithm; fingerprint = value.fingerprint }
    var value: ServerPin { ServerPin(host: host, port: port, knownHost: knownHost, algorithm: algorithm, fingerprint: fingerprint) }
}

struct VPSRecord: Codable, Identifiable {
    var id: UUID
    var name: String
    var request: ServerRequest
    var pin: SavedPin?
    var node: DeployedNode?
    var panelVersion: String?
    var lastState: String?
    var verifiedAt: Date?
    var milliseconds: Int?
}

@MainActor final class VPSModel: ObservableObject {
    @Published var records: [VPSRecord] = []
    @Published var selectedID: UUID?
    @Published var name = ""
    @Published var request = ServerRequest()
    @Published var sshPort = "22"
    @Published var nodePort = "443"
    @Published var password = ""
    @Published var pin: ServerPin?
    @Published var hostConfirmed = false
    @Published var busy = false
    @Published var status = "填写 VPS 登录信息，检查 SSH 指纹后开始配置。"
    @Published var error: String?
    @Published var panel: PanelInfo?
    let tunnel = PanelTunnel()
    let directory: URL
    private var lockFD: Int32 = -1
    var selected: VPSRecord? { records.first { $0.id == selectedID } }
    var node: DeployedNode? {
        guard let value = selected?.node, value.server == request.host.trimmingCharacters(in: .whitespacesAndNewlines), value.port == Int(nodePort) else { return nil }
        return value
    }
    var pinMatches: Bool { pin?.host == request.host.trimmingCharacters(in: .whitespacesAndNewlines) && pin?.port == Int(sshPort) }
    var canOperate: Bool { !busy && lockFD >= 0 && hostConfirmed && pinMatches && (try? snapshot()) != nil && (!request.passwordAuth || !password.isEmpty) }
    var missing: String? {
        if (try? snapshot()) == nil { return "请填写有效的 IP、SSH 端口与节点端口。" }
        if !pinMatches { return "先检查 SSH 指纹。" }
        if !hostConfirmed { return "与 VPS 控制台核对指纹，再勾选确认。" }
        if request.passwordAuth && password.isEmpty { return "请填写 SSH 登录密码。" }
        return nil
    }

    init() {
        if let path = ProcessInfo.processInfo.environment["NOVAVPS_DATA_DIR"] { directory = URL(fileURLWithPath: path) }
        else { directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NovaVPS") }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            lockFD = Darwin.open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
            guard lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { if lockFD >= 0 { Darwin.close(lockFD) }; lockFD = -1; throw ProxyError("NovaVPS 已在运行，请使用现有窗口。") }
            let file = directory.appendingPathComponent("servers.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Data(contentsOf: file)
                guard data.count <= 2 * 1024 * 1024 else { throw ProxyError("服务器记录过大。") }
                records = try JSONDecoder().decode([VPSRecord].self, from: data)
            }
            try restoreRecoveredRecords()
            if let first = records.first { load(first) }
        } catch { self.error = error.localizedDescription }
    }

    deinit { if lockFD >= 0 { Darwin.close(lockFD) } }

    func snapshot() throws -> ServerRequest {
        guard let ssh = Int(sshPort), let port = Int(nodePort) else { throw ProxyError("端口须为 1–65535 的整数。") }
        var value = request; value.host = value.host.trimmingCharacters(in: .whitespacesAndNewlines); value.sshPort = ssh; value.nodePort = port
        try value.validate(); return value
    }

    func select(_ record: VPSRecord?) async {
        guard !busy else { return }
        await tunnel.close(); panel = nil; password = ""; error = nil
        if let record { load(record) }
        else { selectedID = nil; name = ""; request = ServerRequest(); sshPort = "22"; nodePort = "443"; pin = nil; hostConfirmed = false; status = "填写 VPS 登录信息，检查 SSH 指纹后开始配置。" }
    }

    private func load(_ record: VPSRecord) {
        selectedID = record.id; name = record.name; request = record.request; sshPort = String(request.sshPort); nodePort = String(request.nodePort)
        pin = record.pin?.value; hostConfirmed = pin != nil
        status = record.node == nil ? "连接 VPS 后可配置后台与节点。" : "已保存节点配置；可导出或连接 VPS 刷新状态。"
    }

    func checkHost() async {
        guard !busy, lockFD >= 0 else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let value = try snapshot(); status = "正在读取 SSH 公钥…"
            let checked = try await Task.detached { try SSHDeployment.scan(value) }.value
            let unchanged = pin?.knownHost == checked.knownHost && pin?.host == checked.host && pin?.port == checked.port
            let previouslyKnown = pin != nil
            pin = checked; hostConfirmed = unchanged && hostConfirmed
            status = unchanged ? "SSH 指纹与已确认记录一致。" : previouslyKnown ? "SSH 指纹已变化。请在 VPS 控制台核实后重新确认。" : "已获取 SSH 指纹。请与 VPS 控制台核对后确认。"
        } catch { self.error = error.localizedDescription; status = "SSH 指纹检查未完成。" }
    }

    private func persist(_ record: VPSRecord) throws {
        guard lockFD >= 0 else { throw ProxyError("服务器记录正由另一个窗口使用。") }
        var updated = records
        if let index = updated.firstIndex(where: { $0.id == record.id }) { updated[index] = record } else { updated.append(record) }
        let data = try JSONEncoder().encode(updated)
        guard data.count <= 2 * 1024 * 1024 else { throw ProxyError("服务器记录超出大小限制。") }
        let url = directory.appendingPathComponent("servers.json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        records = updated; selectedID = record.id
    }

    // An updater can stage records from a previous installation without writing
    // a live process's records file. Merge only after acquiring the instance lock.
    private func restoreRecoveredRecords() throws {
        let file = directory.appendingPathComponent("recovered-servers.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let data = try Data(contentsOf: file)
        guard data.count <= 2 * 1024 * 1024 else { throw ProxyError("恢复记录过大。") }
        let recovered = try JSONDecoder().decode([VPSRecord].self, from: data)
        for record in recovered {
            try record.request.validate()
            if let node = record.node { try node.validate(expected: record.request, requireServerName: false) }
            if let saved = record.pin {
                let checked = try ServerPin.parse(scan: saved.knownHost, request: record.request)
                guard checked.fingerprint == saved.fingerprint else { throw ProxyError("恢复记录的 SSH 指纹无效。") }
            }
        }
        for var record in recovered {
            if let existing = records.first(where: { $0.request.host == record.request.host && $0.request.nodePort == record.request.nodePort }) { record.id = existing.id }
            try persist(record)
        }
        let backup = directory.appendingPathComponent("recovered-applied-" + UUID().uuidString + ".json")
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
    }

    private func capture(_ value: ServerRequest, pin: ServerPin, result: PanelResult? = nil) throws {
        var record = selected ?? VPSRecord(id: UUID(), name: "", request: value)
        record.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? value.host : String(name.prefix(80))
        record.request = value; record.pin = SavedPin(pin)
        if let result {
            record.lastState = result.state; record.panelVersion = result.panel?.version
            if let node = result.node {
                if record.node != node { record.verifiedAt = nil; record.milliseconds = nil }
                record.node = node
            }
        }
        try persist(record)
    }

    func perform(_ action: PanelAction) async {
        guard canOperate, let pin else { error = missing; return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let value = try snapshot(); let credential = password
            try capture(value, pin: pin)
            if action == .stop || action == .restart { await tunnel.close() }
            status = action == .install ? "正在独立安装网页后台，不修改现有节点，首次下载可能需要几分钟…" : action == .provision ? "正在安装 / 配置 3x-ui 并生成节点，首次下载可能需要几分钟…" : "正在通过 SSH 管理后台…"
            let result = try await Task.detached { try PanelService.perform(action, request: value, pin: pin, password: credential) }.value
            panel = result.panel; try capture(value, pin: pin, result: result)
            if action == .install {
                status = "网页后台已就绪，可点击“打开网页后台”。原有节点继续使用原服务；生成新节点时需选择空闲端口。"
                return
            }
            guard action == .provision, let node = result.node else {
                status = !result.installed ? "此 VPS 尚未安装 NovaVPS 后台。" : result.state == "active" ? "后台运行中。配置与状态已刷新。" : "后台状态：" + Self.stateLabel(result.state)
                return
            }
            status = "配置已生成并保存，正在从本机验证真实 HTTPS 请求…"
            do {
                let milliseconds = try await Task.detached { try NodeVerifier.verify(node) }.value
                if var record = selected { record.verifiedAt = Date(); record.milliseconds = milliseconds; try persist(record) }
                status = "节点已验证 · HTTPS 204 · \(milliseconds) ms。可导出配置或打开网页后台。"
            } catch {
                status = "配置已生成，可导出；本机连接尚未验证。"
                self.error = error.localizedDescription + " 请检查节点 TCP 端口、安全组和服务器防火墙。"
            }
        } catch { self.error = error.localizedDescription; status = "操作未完成，可刷新状态后重试。" }
    }

    func openPanel() async {
        guard canOperate, let pin else { error = missing; return }
        busy = true; error = nil; defer { busy = false }
        do {
            let value = try snapshot(); let credential = password
            status = "正在读取后台参数并建立 SSH 隧道…"
            let result = try await Task.detached { try PanelService.perform(.inspect, request: value, pin: pin, password: credential) }.value
            guard result.installed, result.state == "active", let details = result.panel else { throw ProxyError("后台未运行，请先点击“安装网页后台”或启动已有后台。") }
            panel = details; try capture(value, pin: pin, result: result)
            let url = try await tunnel.open(request: value, pin: pin, password: credential, panel: details)
            guard NSWorkspace.shared.open(url) else { throw ProxyError("浏览器未能打开。可复制下方本机后台地址。") }
            status = "网页后台已打开。复制后台用户名和密码登录即可。"
        } catch { self.error = error.localizedDescription; status = "网页后台未打开。" }
    }

    func verifySavedNode() async {
        guard !busy, let node else { return }
        busy = true; error = nil; status = "正在通过节点验证 HTTPS…"; defer { busy = false }
        do {
            let milliseconds = try await Task.detached { try NodeVerifier.verify(node) }.value
            if var record = selected { record.verifiedAt = Date(); record.milliseconds = milliseconds; try persist(record) }
            status = "节点已验证 · HTTPS 204 · \(milliseconds) ms。"
        } catch { self.error = error.localizedDescription; status = "已有配置保留，连接验证未通过。" }
    }

    func importNode(_ text: String) throws {
        guard !busy else { return }
        let node = try NodeImport.parse(text)
        var value = ServerRequest(); value.host = node.server; value.nodePort = node.port; value.serverName = node.serverName; value.autoTarget = false
        if value.sshPort == value.nodePort { value.sshPort = value.nodePort == 22 ? 2222 : 22 }
        try node.validate(expected: value)
        let record = VPSRecord(id: UUID(), name: "导入 · " + node.server, request: value, node: node)
        try persist(record); load(record); panel = nil; password = ""
        status = "已有节点已导入，可重新导出。SSH 信息请另行填写；导入不代表后台已经安装。"
    }

    func exportFiles() {
        guard let node, !busy else { return }
        let dialog = NSOpenPanel(); dialog.canChooseDirectories = true; dialog.canChooseFiles = false; dialog.canCreateDirectories = true; dialog.prompt = "导出配置"
        guard dialog.runModal() == .OK, let location = dialog.url else { return }
        do {
            let target = location.appendingPathComponent("NovaVPS-" + UUID().uuidString.prefix(8))
            try Self.export(node, to: target)
            status = "已导出 Xray JSON、Clash YAML、分享链接和二维码。"; NSWorkspace.shared.activateFileViewerSelecting([target])
        } catch { self.error = error.localizedDescription }
    }

    static func export(_ node: DeployedNode, to directory: URL) throws {
        let files: [(String, Data)] = [("node.xray.json", try node.nativeJSON()), ("node.clash.yaml", Data(try node.yaml().utf8)), ("node.vless.txt", Data((try node.shareLink() + "\n").utf8)), ("node-qr.png", try NodeSharing.qrPNG(node.shareLink()))]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            for (name, data) in files {
                let file = directory.appendingPathComponent(name); try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
        } catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    static func stateLabel(_ state: String) -> String {
        ["active": "运行中", "inactive": "已停止", "failed": "启动失败", "not-installed": "尚未安装", "activating": "启动中", "deactivating": "停止中"][state] ?? "未知"
    }
}
