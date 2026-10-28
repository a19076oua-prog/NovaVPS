import Foundation

struct PanelInfo: Decodable {
    let port: Int
    let basePath: String
    let username: String
    let password: String
    let version: String
    func validate() throws {
        guard (1024...65535).contains(port), basePath.range(of: "^/[a-f0-9]{32}/$", options: .regularExpression) != nil,
              (1...80).contains(username.count), (16...256).contains(password.count),
              !username.contains(where: { $0.isNewline || $0.isWhitespace }), !password.contains(where: { $0.isNewline }),
              version == "v3.11.0" else { throw ProxyError("后台返回的访问参数不正确。") }
    }
}

struct PanelResult: Decodable {
    let installed: Bool
    let state: String
    let node: DeployedNode?
    let panel: PanelInfo?
    let inboundCount: Int?
}

enum PanelAction: String { case inspect, install, provision, start, stop, restart }

enum PanelService {
    struct Envelope: Decodable { let success: Bool; let result: PanelResult?; let error: String? }
    static func parse(_ text: String, status: Int32, request: ServerRequest) throws -> PanelResult {
        try request.validate()
        guard text.utf8.count <= 512 * 1024 else { throw ProxyError("后台响应超出大小限制。") }
        let lines = text.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("NOVAVPS_RESULT: ") }
        guard lines.count == 1, let encoded = lines.first, let data = Data(base64Encoded: String(encoded.dropFirst("NOVAVPS_RESULT: ".count))) else {
            try SSHDeployment.checkStatus(status, output: text)
            throw ProxyError("服务器没有返回完整后台结果。可刷新状态后重试。")
        }
        let result = try JSONDecoder().decode(Envelope.self, from: data)
        guard result.success, status == 0, let value = result.result else {
            let message = result.error ?? "后台操作未完成。"
            // Only application-defined, short error messages are displayed; never the SSH transcript.
            guard message.utf8.count < 1200, !message.contains("apiToken"), !message.contains("privateKey") else { throw ProxyError("后台操作未完成，请刷新状态。") }
            throw ProxyError(message)
        }
        guard ["not-installed", "active", "inactive", "failed", "activating", "deactivating", "unknown"].contains(value.state),
              value.inboundCount.map({ (0...100000).contains($0) }) ?? true else { throw ProxyError("后台状态格式无效。") }
        if value.installed {
            guard let panel = value.panel else { throw ProxyError("已安装后台缺少访问参数。") }
            try panel.validate()
        } else if value.panel != nil || value.node != nil || value.state != "not-installed" { throw ProxyError("后台安装状态与返回内容不符。") }
        if let node = value.node { try node.validate(expected: request, requireServerName: false) }
        return value
    }

    static func payload(_ request: ServerRequest) throws -> String {
        try request.validate()
        return try JSONSerialization.data(withJSONObject: ["host": request.host, "nodePort": request.nodePort, "serverName": request.serverName, "autoTarget": request.autoTarget], options: [.sortedKeys]).base64EncodedString()
    }

    static func perform(_ action: PanelAction, request: ServerRequest, pin: ServerPin, password: String) throws -> PanelResult {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("panel-manager.py") else { throw ProxyError("后台管理脚本缺失。") }
        let source = try String(contentsOf: url, encoding: .utf8)
        let script = """
        set -eu
        umask 077
        if ! command -v python3 >/dev/null 2>&1; then
          command -v apt-get >/dev/null 2>&1 || exit 73
          DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=60 update >/dev/null 2>&1
          DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=60 install -y --no-install-recommends python3 ca-certificates >/dev/null 2>&1
        fi
        exec python3 - \(SSHDeployment.quote(action.rawValue)) \(SSHDeployment.quote(try payload(request))) <<'NOVAVPS_PYTHON'
        \(source)
        NOVAVPS_PYTHON
        """
        let (status, output) = try SSHDeployment.execute(request, pin: pin, password: password, script: script,
            command: "if [ \"$(id -u)\" = 0 ]; then exec bash -s; else exec sudo -n bash -s; fi", timeout: [.install, .provision].contains(action) ? 600 : 90)
        return try parse(output, status: status, request: request)
    }
}
