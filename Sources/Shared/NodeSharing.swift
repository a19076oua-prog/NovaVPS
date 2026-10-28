import Foundation
import CoreFoundation
import CoreImage
import AppKit
import Yams

struct SharedNode: Identifiable {
    let id: String
    let name: String
    let endpoint: String
    let link: String
}

enum NodeSharing {
    static func portNumber(_ value: Any?) -> Int? {
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
           (1...65535).contains(n.doubleValue), n.doubleValue.rounded() == n.doubleValue { return n.intValue }
        if let text = value as? String, let port = Int(text), (1...65535).contains(port) { return port }
        return nil
    }
    static func candidates(_ text: String, profileName: String) throws -> [SharedNode] {
        let document = try Configuration.document(Configuration.importText(text))
        var nodes: [[String: Any]] = []
        if let native = document[NativeXrayProfile.key] as? [String: Any] {
            for outbound in native["outbounds"] as? [[String: Any]] ?? [] {
                let protocolName = (outbound["protocol"] as? String ?? "").lowercased()
                guard ["vless", "vmess", "trojan", "shadowsocks"].contains(protocolName) else { continue }
                guard outbound["proxySettings"] == nil else { throw ProxyError("链式出站请分享完整 JSON 配置。") }
                let settings = outbound["settings"] as? [String: Any] ?? [:]
                let stream = outbound["streamSettings"] as? [String: Any] ?? [:]
                let network = stream["network"] as? String ?? "tcp"
                guard ["tcp", "raw", "ws", "grpc"].contains(network) else { throw ProxyError("此传输方式请分享完整 JSON 配置。") }
                let tcp = stream["tcpSettings"] as? [String: Any] ?? stream["rawSettings"] as? [String: Any] ?? [:]
                if let header = tcp["header"] as? [String: Any], let kind = header["type"] as? String, kind != "none" { throw ProxyError("自定义 TCP 伪装请分享完整 JSON 配置。") }
                let servers = settings[protocolName == "vless" || protocolName == "vmess" ? "vnext" : "servers"] as? [[String: Any]] ?? []
                for server in servers {
                    let users = server["users"] as? [[String: Any]] ?? [server]
                    for user in users {
                        var node: [String: Any] = ["name": native["remarks"] as? String ?? profileName, "type": protocolName == "shadowsocks" ? "ss" : protocolName,
                            "server": server["address"] ?? "", "port": server["port"] ?? 0, "network": network == "raw" ? "tcp" : network]
                        if ["vless", "vmess"].contains(protocolName) {
                            guard user["encryption"] == nil || user["encryption"] as? String == "none" else { throw ProxyError("高级 VLESS 加密参数请分享完整 JSON 配置。") }
                            node["uuid"] = user["id"]; node["flow"] = user["flow"]; node["alterId"] = user["alterId"]; node["cipher"] = user["security"]
                        } else { node["password"] = server["password"]; node["cipher"] = server["method"] }
                        let security = stream["security"] as? String ?? "none"
                        guard ["none", "tls", "reality"].contains(security) else { throw ProxyError("此安全层请分享完整 JSON 配置。") }
                        node["tls"] = security != "none" || protocolName == "trojan"
                        let tls = stream["tlsSettings"] as? [String: Any] ?? [:]
                        guard tls["certificates"] == nil, tls["pinnedPeerCertificateChainSha256"] == nil else { throw ProxyError("证书与固定证书参数请分享完整 JSON 配置。") }
                        node["servername"] = tls["serverName"]; node["alpn"] = tls["alpn"]; node["skip-cert-verify"] = tls["allowInsecure"]; node["client-fingerprint"] = tls["fingerprint"]
                        if let reality = stream["realitySettings"] as? [String: Any], security == "reality" {
                            node["servername"] = reality["serverName"]; node["client-fingerprint"] = reality["fingerprint"]
                            node["reality-opts"] = ["public-key": reality["password"] ?? reality["publicKey"] ?? "", "short-id": reality["shortId"] ?? ""]
                        }
                        if network == "ws", let ws = stream["wsSettings"] as? [String: Any] { node["ws-opts"] = ["path": ws["path"] ?? "/", "headers": ws["headers"] ?? [:]] }
                        if network == "grpc", let grpc = stream["grpcSettings"] as? [String: Any] { node["grpc-opts"] = ["grpc-service-name": grpc["serviceName"] ?? ""] }
                        nodes.append(node)
                    }
                }
            }
        } else { nodes = document["proxies"] as? [[String: Any]] ?? [] }
        var result: [SharedNode] = []
        for (index, node) in nodes.enumerated() {
            // No synthesized local bridge, DIRECT, or provider address can become a remote share link.
            guard ["vless", "vmess", "trojan", "ss", "hysteria2", "tuic"].contains(node["type"] as? String ?? "") else { continue }
            let link = try makeLink(node)
            let host = node["server"] as? String ?? "", port = portNumber(node["port"]) ?? 0
            result.append(SharedNode(id: String(index), name: node["name"] as? String ?? profileName, endpoint: (node["type"] as? String ?? "").uppercased() + " · " + host + ":" + String(port), link: link))
        }
        guard !result.isEmpty else { throw ProxyError("此配置没有可分享的内嵌节点；远程 provider 和本地入口请通过配置文件分享。") }
        return result
    }

    static func makeLink(_ node: [String: Any]) throws -> String {
        guard let type = node["type"] as? String, let originalHost = node["server"] as? String, !originalHost.isEmpty,
              let port = portNumber(node["port"]), node["dialer-proxy"] == nil, node["plugin"] == nil else { throw ProxyError("节点或链式 / 插件参数不能生成独立链接，请分享完整配置。") }
        let host = originalHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let name = node["name"] as? String ?? host, network = node["network"] as? String ?? "tcp"
        guard ["tcp", "ws", "grpc"].contains(network) else { throw ProxyError("此传输方式请分享完整配置。") }
        guard !["fingerprint", "ca", "ca-str", "client-cert", "client-key"].contains(where: { node[$0] != nil }) else { throw ProxyError("证书相关参数请分享完整配置。") }
        if type == "ss", network != "tcp" || node["tls"] as? Bool == true { throw ProxyError("SS 的自定义传输请分享完整配置。") }
        let uuid = node["uuid"] as? String ?? "", password = node["password"] as? String ?? ""
        if ["vless", "vmess", "tuic"].contains(type), UUID(uuidString: uuid) == nil { throw ProxyError("节点 UUID 无效。") }
        if ["trojan", "ss", "hysteria2", "tuic"].contains(type), password.isEmpty { throw ProxyError("节点认证信息为空。") }
        let ws = node["ws-opts"] as? [String: Any] ?? [:], headers = ws["headers"] as? [String: Any] ?? [:]
        guard ws.keys.allSatisfy({ ["path", "headers"].contains($0) }), headers.keys.allSatisfy({ $0.lowercased() == "host" }) else { throw ProxyError("自定义 WebSocket 参数请分享完整配置。") }
        let sni = node["servername"] as? String ?? node["sni"] as? String ?? host
        if type == "vmess" {
            guard network != "grpc", node["skip-cert-verify"] as? Bool != true, node["client-fingerprint"] == nil else { throw ProxyError("此 VMess 参数请分享完整配置。") }
            let object: [String: Any] = ["v": "2", "ps": name, "add": host, "port": String(port), "id": uuid,
                "aid": String(node["alterId"] as? Int ?? 0), "scy": node["cipher"] as? String ?? "auto", "net": network,
                "type": "none", "host": headers["Host"] as? String ?? host, "path": ws["path"] as? String ?? "/",
                "tls": node["tls"] as? Bool == true ? "tls" : "", "sni": sni]
            return "vmess://" + (try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])).base64EncodedString()
        }
        var url = URLComponents(); url.scheme = type == "hysteria2" ? "hysteria2" : type
        url.host = host.contains(":") ? "[" + host + "]" : host; url.port = port; url.fragment = name
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        func credential(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        var query: [URLQueryItem] = []
        func add(_ key: String, _ value: String?) { if let value, !value.isEmpty { query.append(URLQueryItem(name: key, value: value)) } }
        if type == "ss" {
            guard let cipher = node["cipher"] as? String, !cipher.isEmpty else { throw ProxyError("SS 加密方式缺失。") }
            let auth = Data((cipher + ":" + password).utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            url.percentEncodedUser = auth
        } else if type == "tuic" {
            url.percentEncodedUser = credential(uuid); url.percentEncodedPassword = credential(password)
            add("sni", sni); add("congestion_control", node["congestion-controller"] as? String ?? "cubic")
        } else if type == "hysteria2" {
            url.percentEncodedUser = credential(password); add("sni", sni)
            add("obfs", node["obfs"] as? String); add("obfs-password", node["obfs-password"] as? String)
        } else {
            url.percentEncodedUser = credential(type == "vless" ? uuid : password)
            add("encryption", type == "vless" ? "none" : nil); add("type", network); add("sni", sni)
            add("flow", node["flow"] as? String); add("fp", node["client-fingerprint"] as? String)
            if let reality = node["reality-opts"] as? [String: Any] {
                guard let key = reality["public-key"] as? String, Configuration.decode64(key)?.count == 32 else { throw ProxyError("Reality 公钥无效。") }
                add("security", "reality"); add("pbk", key); add("sid", reality["short-id"] as? String)
            } else { add("security", type == "trojan" || node["tls"] as? Bool == true ? "tls" : "none") }
            if network == "ws" { add("path", ws["path"] as? String ?? "/"); add("host", headers["Host"] as? String) }
            if network == "grpc" { add("serviceName", (node["grpc-opts"] as? [String: Any])?["grpc-service-name"] as? String) }
        }
        if node["skip-cert-verify"] as? Bool == true { add("allowInsecure", "1") }
        add("alpn", (node["alpn"] as? [String])?.joined(separator: ","))
        if !query.isEmpty { url.queryItems = query }
        guard let result = url.string else { throw ProxyError("节点链接生成失败。") }
        return result
    }

    static func qrPNG(_ link: String) throws -> Data {
        guard !link.isEmpty, link.utf8.count <= 2000, let filter = CIFilter(name: "CIQRCodeGenerator") else { throw ProxyError("链接过长或二维码生成不可用，请复制链接。") }
        filter.setValue(Data(link.utf8), forKey: "inputMessage"); filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { throw ProxyError("二维码生成失败。") }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), rect = scaled.extent.insetBy(dx: -32, dy: -32)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: rect)
        let final = scaled.composited(over: white)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let cg = context.createCGImage(final, from: rect, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()) else { throw ProxyError("二维码渲染失败。") }
        guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw ProxyError("二维码图片保存格式生成失败。") }
        return data
    }
}
