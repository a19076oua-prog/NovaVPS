import Foundation

enum ConnectivityProbe {
    struct Result { let milliseconds: Int }
    enum Failure: LocalizedError {
        case portUnavailable(Int)
        case request(Int32)
        case response(String)
        var errorDescription: String? {
            switch self {
            case .portUnavailable(let port): return "从本机无法连接节点 TCP \(port)。请核对 IP、监听端口、云安全组和服务器防火墙。"
            case .request(28): return "节点端口可连接，但经代理的 HTTPS 请求超时。Reality 握手或服务器出站网络仍未通过验证。"
            case .request(35), .request(56): return "节点端口可连接，但代理 HTTPS 握手失败或连接被重置。请检测 Reality 目标及认证参数。"
            case .request(60): return "代理 HTTPS 证书验证失败，请检查系统时间及证书；程序没有跳过验证。"
            case .request(let code): return "节点端口可连接，但经代理的 HTTPS 请求失败（curl 状态 \(code)）。"
            case .response(let code): return "代理测试返回 HTTP \(code)，预期为 204；尚未确认节点连通。"
            }
        }
    }

    static func parse(status: Int32, output: String) throws -> Result {
        guard status == 0 else { throw Failure.request(status) }
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n")
        guard parts.count == 2, parts[0] == "204", let seconds = Double(parts[1]), seconds.isFinite, seconds >= 0, seconds <= 25 else {
            let code = parts.first.map(String.init) ?? "000"
            throw Failure.response(code.range(of: "^[0-9]{3}$", options: .regularExpression) != nil ? code : "000")
        }
        return Result(milliseconds: Int(seconds * 1000))
    }

    static func verify(_ request: ServerRequest, proxyPort: Int) throws -> Result {
        try request.validate()
        let (tcp, _) = try SSHDeployment.run(executable: "/usr/bin/nc", arguments: ["-z", "-G", "5", "-w", "5", request.host, String(request.nodePort)], timeout: 7)
        guard tcp == 0 else { throw Failure.portUnavailable(request.nodePort) }
        // The generated profile has one fixed proxy, rule mode and no DIRECT fallback.
        // -q ignores ~/.curlrc; --noproxy overrides ambient exclusions; TLS stays verified.
        let (status, output) = try SSHDeployment.run(executable: "/usr/bin/curl", arguments: ["-q", "--noproxy", "", "--proxy", "socks5h://127.0.0.1:\(proxyPort)", "--silent", "--connect-timeout", "8", "--max-time", "20", "--output", "/dev/null", "--write-out", "%{http_code}\n%{time_total}", "https://www.gstatic.com/generate_204"], timeout: 24)
        return try parse(status: status, output: output)
    }
}
