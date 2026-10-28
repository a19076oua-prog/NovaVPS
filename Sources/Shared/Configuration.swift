import Foundation
import CryptoKit
import Yams

struct ProxyError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct Profile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var source: String?
    var updated = Date()
}

struct Configuration {
    static let maxBytes = 2 * 1024 * 1024
    static let initial = """
    proxies: []
    proxy-groups:
      - name: PROXY
        type: select
        proxies: [DIRECT]
    rules:
      - DOMAIN-SUFFIX,local,DIRECT
      - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
      - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
      - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
      - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
      - MATCH,PROXY
    """

    static func document(_ text: String) throws -> [String: Any] {
        guard text.utf8.count <= maxBytes else { throw ProxyError("配置超过 2 MB，请精简后重试。") }
        guard let document = try Yams.load(yaml: text) as? [String: Any],
              document["proxies"] != nil || document["proxy-providers"] != nil else {
            throw ProxyError("需要 Clash / mihomo YAML 配置，或支持的节点分享链接。")
        }
        return document
    }

    static func normalize(_ text: String, token: String, proxyPort: Int, apiPort: Int, mode: String, tunEnabled: Bool = false) throws -> String {
        let original = try document(text)
        var result: [String: Any] = [:]
        for key in ["proxies", "proxy-groups", "rules", "sub-rules", "hosts", "dns", "sniffer", "geodata-mode", "geodata-loader", "geox-url", "global-client-fingerprint"] {
            if let value = original[key] { result[key] = value }
        }
        for kind in ["proxy-providers", "rule-providers"] {
            if let providers = original[kind] as? [String: [String: Any]] {
                var cleaned: [String: [String: Any]] = [:]
                for (name, var provider) in providers {
                    let type = provider["type"] as? String ?? "http"
                    guard type == "http" || type == "inline" else {
                        throw ProxyError("第一版仅支持 HTTP 或 inline provider；请将本地 provider 内容合并到配置。")
                    }
                    if type == "http" {
                        guard let address = provider["url"] as? String,
                              let url = URL(string: address), url.scheme == "https", url.host != nil else {
                            throw ProxyError("远程 provider 必须使用 HTTPS。")
                        }
                        let hash = SHA256.hash(data: Data((kind + name).utf8)).map { String(format: "%02x", $0) }.joined()
                        provider["path"] = "providers/\(hash).yaml"
                    } else { provider.removeValue(forKey: "path") }
                    cleaned[name] = provider
                }
                result[kind] = cleaned
            }
        }
        if result["rules"] == nil { result["rules"] = ["MATCH,DIRECT"] }
        if var dns = result["dns"] as? [String: Any] {
            dns.removeValue(forKey: "listen")
            result["dns"] = dns
        }
        result["mixed-port"] = proxyPort
        result["bind-address"] = "127.0.0.1"
        result["allow-lan"] = false
        result["external-controller"] = "127.0.0.1:\(apiPort)"
        result["secret"] = token
        result["mode"] = mode
        result["log-level"] = "info"
        result["ipv6"] = true
        result["tcp-concurrent"] = true
        result["unified-delay"] = true
        if tunEnabled {
            result["tun"] = ["enable": true, "stack": "mixed", "auto-route": true, "auto-detect-interface": true,
                "dns-hijack": ["any:53", "tcp://any:53"], "strict-route": true, "mtu": 1500,
                "inet6-address": ["fdfe:dcba:9876::1/126"], "udp-timeout": 300]
            var dns = result["dns"] as? [String: Any] ?? [:]
            dns["enable"] = true
            // This range also determines mihomo's IPv4 TUN address and virtual DNS gateway.
            dns["fake-ip-range"] = "198.18.0.1/16"
            if dns["enhanced-mode"] == nil { dns["enhanced-mode"] = "fake-ip" }
            if (dns["nameserver"] as? [String])?.isEmpty != false { dns["nameserver"] = ["https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"] }
            // Never resolve the TUN DNS upstream using the system DNS that we are redirecting.
            dns["default-nameserver"] = ["1.1.1.1", "8.8.8.8"]
            dns["use-system-hosts"] = false
            if usesSystemDNS(dns) { throw ProxyError("TUN 模式不支持使用 system / dhcp 上游 DNS，请改为明确的 DNS 地址。") }
            result["dns"] = dns
        } else { result["tun"] = ["enable": false] }
        result["profile"] = ["store-selected": true, "store-fake-ip": true]
        return try Yams.dump(object: result, sortKeys: true)
    }

    static func importText(_ text: String) throws -> String {
        guard text.utf8.count <= maxBytes else { throw ProxyError("配置超过 2 MB，请精简后重试。") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["outbounds"] != nil {
            return try Yams.dump(object: NativeXrayProfile.wrap(json), sortKeys: true)
        }
        if (try? document(trimmed)) != nil { return trimmed }
        var lines = trimmed
        if !trimmed.contains("://"), let data = decode64(trimmed), let decoded = String(data: data, encoding: .utf8) { lines = decoded }
        var nodes: [[String: Any]] = []
        var names = Set<String>()
        for line in lines.split(whereSeparator: \.isNewline) {
            var node = try parseLink(String(line).trimmingCharacters(in: .whitespaces))
            let base = node["name"] as? String ?? "节点"
            var name = base; var index = 2
            while names.contains(name) { name = "\(base) \(index)"; index += 1 }
            names.insert(name); node["name"] = name; nodes.append(node)
        }
        guard !nodes.isEmpty else { throw ProxyError("没有发现可导入的节点。") }
        let nodeNames = nodes.compactMap { $0["name"] as? String }
        let groups: [[String: Any]] = [
            ["name": "PROXY", "type": "select", "proxies": ["自动选择", "故障切换"] + nodeNames + ["DIRECT"]],
            ["name": "自动选择", "type": "url-test", "proxies": nodeNames, "url": "https://www.gstatic.com/generate_204", "interval": 300, "tolerance": 50, "lazy": true],
            ["name": "故障切换", "type": "fallback", "proxies": nodeNames, "url": "https://www.gstatic.com/generate_204", "interval": 300, "lazy": true]
        ]
        return try Yams.dump(object: ["proxies": nodes, "proxy-groups": groups, "rules": ["IP-CIDR,127.0.0.0/8,DIRECT,no-resolve", "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve", "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve", "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve", "DOMAIN-SUFFIX,local,DIRECT", "MATCH,PROXY"]], sortKeys: true)
    }

    static func decode64(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/").filter { !$0.isWhitespace }
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        return Data(base64Encoded: normalized)
    }

    static func usesSystemDNS(_ value: Any) -> Bool {
        if let text = value as? String { return text == "system" || text.hasPrefix("system://") || text.hasPrefix("dhcp://") }
        if let array = value as? [Any] { return array.contains(where: usesSystemDNS) }
        if let dictionary = value as? [String: Any] { return dictionary.values.contains(where: usesSystemDNS) }
        return false
    }

    static func parseLink(_ link: String) throws -> [String: Any] {
        if link.hasPrefix("vmess://") {
            let payload = String(link.dropFirst(8))
            guard let data = decode64(payload), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let server = object["add"] as? String, let uuid = object["id"] as? String,
                  let port = Int(String(describing: object["port"] ?? "")), (1...65535).contains(port) else { throw ProxyError("VMess 链接格式无效。") }
            var node: [String: Any] = ["name": object["ps"] as? String ?? server, "type": "vmess", "server": server, "port": port, "uuid": uuid, "alterId": Int(String(describing: object["aid"] ?? "0")) ?? 0, "cipher": object["scy"] as? String ?? "auto", "udp": true]
            if object["tls"] as? String == "tls" { node["tls"] = true; node["servername"] = object["sni"] as? String ?? server }
            let network = object["net"] as? String ?? "tcp"
            if network == "ws" { node["network"] = "ws"; node["ws-opts"] = ["path": object["path"] as? String ?? "/", "headers": ["Host": object["host"] as? String ?? server]] }
            else if network != "tcp" { throw ProxyError("此 VMess 传输方式请通过完整 YAML 导入。") }
            return node
        }
        guard let u = URLComponents(string: link), let scheme = u.scheme?.lowercased(),
              let rawServer = u.host, !rawServer.isEmpty, let port = u.port, (1...65535).contains(port) else { throw ProxyError("节点链接缺少有效的服务器或端口。") }
        let server = rawServer.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !server.isEmpty else { throw ProxyError("节点链接缺少有效的服务器。") }
        var q: [String: String] = [:]
        for item in u.queryItems ?? [] { q[item.name] = item.value ?? "" }
        var n: [String: Any] = ["name": u.fragment ?? server, "server": server, "port": port, "udp": true]
        switch scheme {
        case "ss":
            var credential = u.user ?? ""
            if let password = u.password { credential += ":" + password }
            else if let data = decode64(credential), let value = String(data: data, encoding: .utf8) { credential = value }
            let pair = credential.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, q["plugin"] == nil else { throw ProxyError("SS 插件或此链接格式请通过完整 YAML 导入。") }
            n["type"] = "ss"; n["cipher"] = String(pair[0]); n["password"] = String(pair[1])
        case "vless", "trojan":
            guard let credential = u.user, !credential.isEmpty else { throw ProxyError("链接缺少认证信息。") }
            n["type"] = scheme
            n[scheme == "vless" ? "uuid" : "password"] = credential
            if let flow = q["flow"], !flow.isEmpty { n["flow"] = flow }
            n["tls"] = scheme == "trojan" || ["tls", "reality"].contains(q["security"] ?? "")
            n["servername"] = q["sni"] ?? q["peer"] ?? server
            if let fingerprint = q["fp"] { n["client-fingerprint"] = fingerprint }
            if q["security"] == "reality" {
                guard let publicKey = q["pbk"], !publicKey.isEmpty else { throw ProxyError("Reality 链接缺少 public key。") }
                n["reality-opts"] = ["public-key": publicKey, "short-id": q["sid"] ?? ""]
            }
            let network = q["type"] ?? "tcp"
            if network == "ws" { n["network"] = "ws"; n["ws-opts"] = ["path": q["path"] ?? "/", "headers": ["Host": q["host"] ?? server]] }
            else if network == "grpc" { n["network"] = "grpc"; n["grpc-opts"] = ["grpc-service-name": q["serviceName"] ?? ""] }
            else if network != "tcp" { throw ProxyError("此传输方式请通过完整 YAML 导入。") }
        case "hysteria2", "hy2":
            n["type"] = "hysteria2"; n["password"] = (u.user ?? "") + (u.password.map { ":" + $0 } ?? "")
            n["sni"] = q["sni"] ?? server
            if let obfs = q["obfs"] { n["obfs"] = obfs; n["obfs-password"] = q["obfs-password"] ?? "" }
        case "tuic":
            guard let uuid = u.user, let password = u.password else { throw ProxyError("TUIC 链接需要 UUID 和密码。") }
            n["type"] = "tuic"; n["uuid"] = uuid; n["password"] = password; n["sni"] = q["sni"] ?? server
            n["congestion-controller"] = q["congestion_control"] ?? "cubic"
        default: throw ProxyError("此链接协议请通过完整 YAML 导入；支持 ss / vmess / vless / trojan / hy2 / tuic。")
        }
        if q["allowInsecure"] == "1" || q["insecure"] == "1" { n["skip-cert-verify"] = true }
        if let alpn = q["alpn"] { n["alpn"] = alpn.split(separator: ",").map(String.init) }
        return n
    }
}
