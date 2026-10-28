import Foundation
import CryptoKit
import Darwin
import Yams

struct ServerRequest: Codable, Equatable {
    var host = ""
    var sshPort = 22
    var username = "root"
    var nodePort = 443
    var serverName = "dl.google.com"
    var identityFile = ""
    var passwordAuth = true
    var autoTarget = true

    func validate() throws {
        var v4 = in_addr(); var v6 = in6_addr()
        guard inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1 else { throw ProxyError("请输入有效的服务器 IPv4 或 IPv6 地址。") }
        guard (1...65535).contains(sshPort), (1...65535).contains(nodePort), sshPort != nodePort else { throw ProxyError("SSH 和节点端口须在 1–65535 之间，且不能相同。") }
        guard username.range(of: "^[a-z_][a-z0-9_-]{0,31}$", options: .regularExpression) != nil else { throw ProxyError("SSH 用户名格式无效。") }
        guard serverName.utf8.count <= 253, serverName.range(of: "^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$", options: .regularExpression) != nil, serverName.contains("."), !serverName.contains("..") else { throw ProxyError("Reality 目标需要有效的域名，并支持 TLS 1.3。") }
        if !passwordAuth, !identityFile.isEmpty {
            guard identityFile.hasPrefix("/"), FileManager.default.isReadableFile(atPath: identityFile) else { throw ProxyError("请选择可读的 SSH 私钥文件；加密密钥请先加入 SSH Agent。") }
        }
    }
}

struct ServerPin {
    let host: String
    let port: Int
    let knownHost: String
    let algorithm: String
    let fingerprint: String

    static func parse(scan: String, request: ServerRequest) throws -> ServerPin {
        let expected = request.sshPort == 22 ? request.host : "[\(request.host)]:\(request.sshPort)"
        for kind in ["ssh-ed25519", "ecdsa-sha2-nistp256", "ssh-rsa"] {
            for line in scan.split(whereSeparator: \.isNewline) {
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count == 3, String(parts[0]) == expected, String(parts[1]) == kind, let key = Data(base64Encoded: String(parts[2])), !key.isEmpty else { continue }
                let digest = Data(SHA256.hash(data: key)).base64EncodedString().replacingOccurrences(of: "=", with: "")
                return ServerPin(host: request.host, port: request.sshPort, knownHost: String(line) + "\n", algorithm: kind == "ssh-rsa" ? "rsa-sha2-512,rsa-sha2-256" : kind, fingerprint: "SHA256:" + digest)
            }
        }
        throw ProxyError("未获取到服务器 SSH 公钥。请检查 IP、SSH 端口及防火墙。")
    }
}

struct DeployedNode: Codable, Equatable {
    let server: String
    let port: Int
    let uuid: String
    let publicKey: String
    let shortId: String
    let serverName: String

    static func parse(output: String, expected: ServerRequest) throws -> DeployedNode {
        let markers = output.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("NOVAPROXY_RESULT: ") }
        guard markers.count == 1, let marker = markers.first, let data = Data(base64Encoded: String(marker.dropFirst("NOVAPROXY_RESULT: ".count))) else { throw ProxyError("服务器没有返回完整节点。可重新部署以恢复已生成配置。") }
        let node = try JSONDecoder().decode(Self.self, from: data)
        try node.validate(expected: expected)
        return node
    }

    func validate(expected: ServerRequest, requireServerName: Bool = true) throws {
        let node = self
        var returned = expected; returned.serverName = node.serverName
        try returned.validate()
        var v4 = in_addr(); var v6 = in6_addr(); var expected4 = in_addr(); var expected6 = in6_addr()
        let matchesIPv4 = inet_pton(AF_INET, node.server, &v4) == 1 && inet_pton(AF_INET, expected.host, &expected4) == 1 && v4.s_addr == expected4.s_addr
        let matchesIPv6 = inet_pton(AF_INET6, node.server, &v6) == 1 && inet_pton(AF_INET6, expected.host, &expected6) == 1 && withUnsafeBytes(of: v6) { Data($0) } == withUnsafeBytes(of: expected6) { Data($0) }
        guard matchesIPv4 || matchesIPv6,
              node.port == expected.nodePort, (!requireServerName || node.serverName == expected.serverName || (expected.autoTarget && ["dl.google.com", "www.bing.com"].contains(node.serverName))),
              UUID(uuidString: node.uuid) != nil,
              node.publicKey.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              Configuration.decode64(node.publicKey)?.count == 32,
              node.shortId.range(of: "^[a-f0-9]{16}$", options: .regularExpression) != nil else { throw ProxyError("服务器返回的节点参数与请求不符。") }
    }

    func yaml() throws -> String {
        let name = "服务器 " + server
        let proxy: [String: Any] = ["name": name, "type": "vless", "server": server, "port": port, "uuid": uuid,
            "flow": "xtls-rprx-vision", "network": "tcp", "udp": true, "tls": true, "servername": serverName,
            "client-fingerprint": "chrome", "skip-cert-verify": false,
            "reality-opts": ["public-key": publicKey, "short-id": shortId]]
        // A single fixed outbound avoids lazy health checks or unintended DIRECT selections.
        return try Yams.dump(object: ["proxies": [proxy], "proxy-groups": [["name": "PROXY", "type": "select", "proxies": [name]]],
            "rules": ["IP-CIDR,127.0.0.0/8,DIRECT,no-resolve", "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve", "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve", "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve", "MATCH,PROXY"]], sortKeys: true)
    }

    func nativeJSON() throws -> Data {
        let outbound: [String: Any] = ["tag": "proxy", "protocol": "vless",
            "settings": ["vnext": [["address": server, "port": port, "users": [["id": uuid, "encryption": "none", "flow": "xtls-rprx-vision"]]]]],
            "streamSettings": ["network": "tcp", "security": "reality", "realitySettings": ["serverName": serverName, "fingerprint": "chrome", "publicKey": publicKey, "password": publicKey, "shortId": shortId, "show": false]]]
        return try JSONSerialization.data(withJSONObject: ["remarks": "NovaVPS · " + server,
            "log": ["loglevel": "warning"],
            "inbounds": [["tag": "socks", "listen": "127.0.0.1", "port": 10808, "protocol": "socks", "settings": ["udp": true]],
                         ["tag": "http", "listen": "127.0.0.1", "port": 10809, "protocol": "http"]],
            "outbounds": [outbound, ["tag": "direct", "protocol": "freedom"], ["tag": "block", "protocol": "blackhole"]],
            "routing": ["domainStrategy": "AsIs", "rules": [["type": "field", "ip": ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "::1/128", "fc00::/7", "fe80::/10"], "outboundTag": "direct"]]]], options: [.prettyPrinted, .sortedKeys])
    }

    func nativeProfile() throws -> String { try Configuration.importText(String(data: nativeJSON(), encoding: .utf8)!) }

    func shareLink() throws -> String {
        var parts = URLComponents(); parts.scheme = "vless"; parts.user = uuid; parts.host = server.contains(":") ? "[" + server + "]" : server; parts.port = port
        parts.queryItems = [URLQueryItem(name: "encryption", value: "none"), URLQueryItem(name: "security", value: "reality"),
                           URLQueryItem(name: "type", value: "tcp"), URLQueryItem(name: "flow", value: "xtls-rprx-vision"),
                           URLQueryItem(name: "sni", value: serverName), URLQueryItem(name: "fp", value: "chrome"),
                           URLQueryItem(name: "pbk", value: publicKey), URLQueryItem(name: "sid", value: shortId)]
        parts.fragment = "NovaVPS · " + server
        guard let result = parts.string else { throw ProxyError("节点链接生成失败。") }
        return result
    }
}

struct ExistingDeployment: Error {}

struct RepairedDeployment: Decodable {
    let success: Bool
    let changed: Bool?
    let client: DeployedNode?
    let error: String?

    static func parse(_ output: String, expected: ServerRequest) throws -> Self {
        let lines = output.split(whereSeparator: \.isNewline).filter { $0.hasPrefix("{\"success\":") || $0.hasPrefix("{\"success\" :") }
        guard lines.count == 1, let line = lines.first, let value = try? JSONDecoder().decode(Self.self, from: Data(line.utf8)) else { throw ProxyError("服务器未返回完整修复结果。SSH 中断时请重新检测已有节点；不要重复创建新服务。") }
        guard value.success else { throw ProxyError(repairReason(value.error)) }
        guard let node = value.client, value.changed != nil else { throw ProxyError("修复结果缺少节点。") }
        try node.validate(expected: expected, requireServerName: false)
        return value
    }

    static func repairReason(_ reason: String?) -> String {
        switch reason {
        case "root login is required": return "修复需要 root 或免密码 sudo。"
        case "this is not a NovaProxy-managed deployment", "service identity does not match NovaProxy": return "该服务器不是完整的 NovaProxy 部署，已停止以避免修改其他服务。"
        case "existing deployment uses another node port; server was not changed": return "填写的节点端口与已有部署不同，服务器未修改。请填写原节点端口。"
        case "server/client parameters differ; refusing to change them", "server/client public key mismatch": return "服务器保存的认证参数不一致，已停止，未重新生成或覆盖凭据。"
        case "service is not active": return "服务器代理服务未运行。请先检查服务状态。"
        case "alternative Reality targets failed; server was not changed": return "服务器上的完整 Reality 请求测试失败，替代目标也未通过；服务器未修改。请检查服务器出站网络。"
        case "candidate configuration was rejected; server was not changed": return "替代配置未通过 Xray 校验，服务器未修改。"
        case "repair verification failed; original configuration restored": return "修改后的实际请求测试失败，已恢复原配置。"
        case "repair failed; original files restored but service restart failed": return "原配置文件已恢复，但服务器服务没有成功重启，请检查服务状态。"
        case "rollback could not restore all files; manual service recovery is required": return "回滚未能完整恢复文件。服务器保留了备份，需要通过 SSH 检查该服务。"
        case "TimeoutExpired": return "服务器检测请求超时；未得到连通证明。请检查服务器出站网络后重试。"
        case "BlockingIOError": return "服务器上已有部署或修复正在运行，请等待其完成。"
        case "repair interrupted": return "修复被中断。重新检测已有节点可确认服务器当前状态。"
        default: return "服务器检测或修复失败，未得到完整连通证明。请检查该服务及服务器出站网络。"
        }
    }
}

enum SSHDeployment {
    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func run(executable: String, arguments: [String], input: String? = nil, environment: [String: String]? = nil, timeout: Double) throws -> (Int32, String) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        if let environment { process.environment = environment }
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        let stdin = Pipe(); process.standardInput = stdin
        try process.run()
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() } }
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        }
        timer.resume(); defer { timer.cancel() }
        if let input { try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
        try stdin.fileHandleForWriting.close()
        var bytes = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            if bytes.count + chunk.count > 512 * 1024 {
                kill(process.processIdentifier, SIGKILL); process.waitUntilExit()
                throw ProxyError("SSH 返回内容过大，部署已中断。")
            }
            bytes.append(chunk)
        }
        process.waitUntilExit()
        return (process.terminationStatus, String(data: bytes, encoding: .utf8) ?? "")
    }

    static func scan(_ request: ServerRequest) throws -> ServerPin {
        try request.validate()
        let (_, output) = try run(executable: "/usr/bin/ssh-keyscan", arguments: ["-T", "8", "-p", String(request.sshPort), "-t", "ed25519,ecdsa,rsa", request.host], timeout: 25)
        return try ServerPin.parse(scan: output, request: request)
    }

    static func execute(_ request: ServerRequest, pin: ServerPin, password: String, script: String, command: String, timeout: Double) throws -> (Int32, String) {
        try request.validate()
        guard request.host == pin.host, request.sshPort == pin.port else { throw ProxyError("连接地址已改变，请重新检查服务器指纹。") }
        if request.passwordAuth { guard !password.isEmpty, !password.contains("\n"), !password.contains("\0") else { throw ProxyError("请输入 SSH 登录密码。") } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("novaproxy-ssh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let hosts = directory.appendingPathComponent("known_hosts")
        try pin.knownHost.write(to: hosts, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hosts.path)
        var arguments = ["-F", "/dev/null", "-T", "-p", String(request.sshPort), "-l", request.username,
            "-o", "StrictHostKeyChecking=yes", "-o", "UserKnownHostsFile=" + hosts.path, "-o", "GlobalKnownHostsFile=/dev/null",
            "-o", "HostKeyAlgorithms=" + pin.algorithm, "-o", "UpdateHostKeys=no", "-o", "ConnectTimeout=15",
            "-o", "IPQoS=none", "-o", "TCPKeepAlive=yes", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=12", "-o", "ClearAllForwardings=yes",
            "-o", "NumberOfPasswordPrompts=1", "-o", "BatchMode=" + (request.passwordAuth ? "no" : "yes")]
        var env = ProcessInfo.processInfo.environment
        // Prevent parent proxy/askpass settings from altering the connection.
        env.removeValue(forKey: "SSH_ASKPASS"); env.removeValue(forKey: "NOVAPROXY_SSH_PASSWORD")
        if request.passwordAuth {
            let helper = directory.appendingPathComponent("askpass")
            try "#!/bin/sh\nexec \"$NOVAPROXY_ASKPASS_EXECUTABLE\" --ssh-askpass\n".write(to: helper, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
            env["SSH_ASKPASS"] = helper.path; env["SSH_ASKPASS_REQUIRE"] = "force"; env["DISPLAY"] = "novaproxy:0"
            env["NOVAPROXY_ASKPASS_EXECUTABLE"] = Bundle.main.executableURL!.path
            env["NOVAPROXY_SSH_PASSWORD"] = password
            arguments += ["-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "PubkeyAuthentication=no"]
        } else if !request.identityFile.isEmpty { arguments += ["-i", request.identityFile, "-o", "IdentitiesOnly=yes"] }
        arguments += [request.host, command]
        return try run(executable: "/usr/bin/ssh", arguments: arguments, input: script, environment: env, timeout: timeout)
    }

    static func deploy(_ request: ServerRequest, pin: ServerPin, password: String, script: String) throws -> DeployedNode {
        let prefix = "NP_HOST=" + quote(request.host) + "\nNP_PORT=" + quote(String(request.nodePort)) + "\nNP_SNI=" + quote(request.serverName) + "\nNP_AUTO_TARGET=" + quote(request.autoTarget ? "1" : "0") + "\n"
        let (status, output) = try execute(request, pin: pin, password: password, script: prefix + script,
            command: "if [ \"$(id -u)\" = 0 ]; then exec bash -s; else exec sudo -n bash -s; fi", timeout: 480)
        if status != 0, output.contains("different settings") || output.contains("another port") { throw ExistingDeployment() }
        try checkStatus(status, output: output)
        return try DeployedNode.parse(output: output, expected: request)
    }

    static func repair(_ request: ServerRequest, pin: ServerPin, password: String, script: String) throws -> RepairedDeployment {
        let args = "python3 - " + quote(request.host) + " " + quote(String(request.nodePort))
        let (status, output) = try execute(request, pin: pin, password: password, script: script,
            command: "if [ \"$(id -u)\" = 0 ]; then exec " + args + "; else exec sudo -n " + args + "; fi", timeout: 240)
        if status == 0 || output.split(whereSeparator: \.isNewline).contains(where: { $0.hasPrefix("{\"success\":") }) {
            let result = try RepairedDeployment.parse(output, expected: request)
            try checkStatus(status, output: output)
            return result
        }
        try checkStatus(status, output: output)
        throw ProxyError("服务器未返回修复结果。")
    }

    static func checkStatus(_ status: Int32, output: String) throws {
        guard status == 0 else {
            // Never surface raw SSH output: it could contain generated client credentials.
            let reason: String
            if output.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") || output.contains("Host key verification failed") { reason = "服务器指纹与确认值不一致；请核实服务器身份后重新检查。" }
            else if output.contains("Permission denied") { reason = "SSH 认证失败，请检查用户、密码或密钥。" }
            else if output.contains("sudo") && output.contains("password") { reason = "该账户需要免密码 sudo；也可以使用 root 登录。" }
            else if output.contains("not responding") || output.contains("Connection timed out") || output.contains("Operation timed out") || output.contains("Connection reset") || status == 15 || status == 9 { reason = "SSH 连接超时或中断；没有收到完整结果。请检查 SSH 管理端口和当前网络；重新检测已有节点可确认状态。" }
            else if output.contains("Connection refused") { reason = "服务器拒绝 SSH 连接。请检查 SSH 服务及管理端口；SSH 端口与代理节点端口不同。" }
            else if output.contains("already in use") { reason = "节点端口已占用，请选择其他端口。" }
            else if output.contains("different settings") || output.contains("another port") { reason = "已有部署使用其他端口或 Reality 域名，请使用原参数。" }
            else if output.contains("refusing to overwrite") { reason = "服务器已有不完整或非本应用管理的文件，已停止以避免覆盖。" }
            else if output.contains("supports Debian") || output.contains("Linux with systemd") || output.contains("Only x86_64") { reason = "服务器需为 Debian/Ubuntu、systemd、x86_64 或 arm64。" }
            else if output.contains("checksum mismatch") { reason = "Xray 下载文件校验失败，未安装。" }
            else if output.contains("Reality target is unreachable") { reason = "服务器无法连接 Reality 目标，或目标不支持经证书验证的 TLS 1.3；请更换目标域名。" }
            else { reason = "SSH 或远程安装失败（状态 \(status)）。请检查服务器到 GitHub 的连接及权限。中断后可用相同参数重试。" }
            throw ProxyError(reason)
        }
    }
}
