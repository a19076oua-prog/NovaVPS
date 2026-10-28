import Foundation
import Darwin
import Yams

struct RealityBridgePlan {
    let yaml: String
    let json: Data
    let ports: [Int]
    static func supported(_ node: [String: Any]) -> Bool {
        node["type"] as? String == "vless" && node["reality-opts"] != nil && (node["network"] as? String ?? "tcp") == "tcp" && node["dialer-proxy"] == nil
    }
    static func count(_ document: [String: Any]) -> Int {
        if document[NativeXrayProfile.key] != nil { return 1 }
        let nodes = document["proxies"] as? [[String: Any]] ?? []
        return nodes.filter { supported($0) || (document["novaproxy-reality-core"] as? String == "xray" && $0["type"] as? String == "vless" && $0["reality-opts"] != nil) }.count
    }
    static func make(_ text: String, ports: [Int], password: String) throws -> Self {
        var config = try Configuration.document(text)
        if config["novaproxy-xray-interface"] == nil { config["novaproxy-xray-interface"] = NativeXrayProfile.physicalInterface() }
        if config[NativeXrayProfile.key] != nil {
            guard ports.count == 1 else { throw ProxyError("Xray 原生配置入口数量无效。") }
            return try NativeXrayProfile.plan(config, port: ports[0], password: password, interface: config["novaproxy-xray-interface"] as? String)
        }
        guard var nodes = config["proxies"] as? [[String: Any]] else { throw ProxyError("Xray 兼容模式需要内嵌节点。") }
        var inbounds: [[String: Any]] = [], outbounds: [[String: Any]] = [], rules: [[String: Any]] = []
        let interface = config["novaproxy-xray-interface"] as? String
        if let interface, interface.range(of: "^[A-Za-z][A-Za-z0-9]{0,15}$", options: .regularExpression) == nil { throw ProxyError("无效的 Xray 出站接口。") }
        for i in nodes.indices {
            let n = nodes[i]
            guard (supported(n) || config["novaproxy-reality-core"] as? String == "xray"), n["type"] as? String == "vless", let reality = n["reality-opts"] as? [String: Any] else { continue }
            guard inbounds.count < ports.count, let name = n["name"] as? String, let server = n["server"] as? String, !server.isEmpty,
                  let port = n["port"] as? Int, (1...65535).contains(port), let uuid = n["uuid"] as? String, UUID(uuidString: uuid) != nil,
                  let publicKey = reality["public-key"] as? String, Configuration.decode64(publicKey)?.count == 32,
                  (n["network"] as? String ?? "tcp") == "tcp", n["dialer-proxy"] == nil else { throw ProxyError("Xray 兼容模式目前支持有效的 TCP VLESS / Reality 节点；高级传输请使用普通模式。") }
            let sid = reality["short-id"] as? String ?? ""
            guard sid.count <= 16, sid.count % 2 == 0, sid.range(of: "^[0-9a-fA-F]*$", options: .regularExpression) != nil else { throw ProxyError("Reality short ID 格式无效。") }
            let index = inbounds.count; let incoming = "in-\(index)", outgoing = "out-\(index)"
            var user: [String: Any] = ["id": uuid, "encryption": "none"]
            if let flow = n["flow"] as? String, !flow.isEmpty {
                guard flow == "xtls-rprx-vision" else { throw ProxyError("不支持此 Reality flow。") }; user["flow"] = flow
            }
            var stream: [String: Any] = ["network": "raw", "security": "reality", "realitySettings": ["fingerprint": n["client-fingerprint"] as? String ?? "chrome", "serverName": n["servername"] as? String ?? server, "password": publicKey, "shortId": sid]]
            if let interface, !NativeXrayProfile.loopback(server) { stream["sockopt"] = ["interface": interface] }
            inbounds.append(["tag": incoming, "listen": "127.0.0.1", "port": ports[index], "protocol": "socks", "settings": ["auth": "password", "accounts": [["user": "novaproxy", "pass": password]], "udp": true]])
            outbounds.append(["tag": outgoing, "protocol": "vless", "settings": ["vnext": [["address": server, "port": port, "users": [user]]]], "streamSettings": stream])
            rules.append(["type": "field", "inboundTag": [incoming], "outboundTag": outgoing])
            nodes[i] = ["name": name, "type": "socks5", "server": "127.0.0.1", "port": ports[index], "username": "novaproxy", "password": password, "udp": true]
        }
        guard !inbounds.isEmpty, inbounds.count == ports.count else { throw ProxyError("没有可用的内嵌 TCP Reality 节点。") }
        config["proxies"] = nodes
        let json = try JSONSerialization.data(withJSONObject: ["log": ["loglevel": "warning"], "inbounds": inbounds, "outbounds": outbounds, "routing": ["rules": rules]])
        return Self(yaml: try Yams.dump(object: config, sortKeys: true), json: json, ports: ports)
    }
}

@MainActor final class RealityBridge {
    private var process: Process?
    private var output: Pipe?
    private var configURL: URL?
    private(set) var expected = false
    var isRunning: Bool { process?.isRunning == true }
    func prepare(_ text: String, directory: URL) async throws -> String {
        let document = try Configuration.document(text)
        let count = RealityBridgePlan.count(document)
        guard count > 0 else { return text }
        guard !expected else { throw ProxyError("Xray 兼容内核已在运行。") }
        guard (1...32).contains(count) else { throw ProxyError("Xray 兼容模式需要 1–32 个内嵌 Reality 节点。") }
        var descriptors: [Int32] = [], ports: [Int] = []
        defer { descriptors.forEach { Darwin.close($0) } }
        for _ in 0..<count {
            let fd = socket(AF_INET, SOCK_STREAM, 0); guard fd >= 0 else { throw ProxyError("无法分配 Xray 本地端口。") }; descriptors.append(fd)
            var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let fetched = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
            guard bound == 0, fetched == 0 else { throw ProxyError("无法预留 Xray 本地端口。") }; ports.append(Int(UInt16(bigEndian: address.sin_port)))
        }
        let plan = try RealityBridgePlan.make(Yams.dump(object: document, sortKeys: true), ports: ports, password: UUID().uuidString + UUID().uuidString)
        let url = directory.appendingPathComponent("xray-runtime.json"); configURL = url
        try plan.json.write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let child = Process(); child.executableURL = Bundle.main.executableURL
        child.arguments = ["--supervise-xray", Bundle.main.resourceURL!.appendingPathComponent("xray").path, url.path]
        let pipe = Pipe(); child.standardOutput = pipe; child.standardError = pipe; output = pipe
        // Drain bounded chunks; upstream credentials never enter the UI log.
        pipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        descriptors.forEach { Darwin.close($0) }; descriptors.removeAll()
        process = child; expected = true
        do {
            try child.run()
            for _ in 0..<80 {
                guard child.isRunning else { throw ProxyError("Xray 兼容内核启动失败。") }
                let ready = ports.allSatisfy { port in
                    let fd = socket(AF_INET, SOCK_STREAM, 0); guard fd >= 0 else { return false }; defer { Darwin.close(fd) }
                    var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1"); a.sin_port = UInt16(port).bigEndian
                    return withUnsafePointer(to: &a) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 } }
                }
                if ready { return plan.yaml }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            throw ProxyError("Xray 兼容内核启动超时。")
        } catch { stop(); throw error }
    }
    func stop() {
        expected = false; output?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning { process.terminate(); process.waitUntilExit() }
        process = nil; output = nil
        if let configURL { try? FileManager.default.removeItem(at: configURL) }; configURL = nil
    }
}
