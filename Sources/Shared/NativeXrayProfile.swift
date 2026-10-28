import Foundation
import Darwin
import Yams

enum NativeXrayProfile {
    static let key = "novaproxy-xray-native"
    static let protocols: Set<String> = ["vless", "vmess", "trojan", "shadowsocks", "socks", "http", "freedom", "blackhole", "dns"]
    static func loopback(_ host: String) -> Bool {
        if host.lowercased() == "localhost" { return true }
        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 { return UInt32(bigEndian: v4.s_addr) >> 24 == 127 }
        var v6 = in6_addr(), reference = in6_addr(); _ = inet_pton(AF_INET6, "::1", &reference)
        return inet_pton(AF_INET6, host, &v6) == 1 && withUnsafeBytes(of: v6) { Data($0) } == withUnsafeBytes(of: reference) { Data($0) }
    }

    static func wrap(_ original: [String: Any]) throws -> [String: Any] {
        _ = try runtime(original, port: 23456, password: "validation-only", interface: nil)
        let name = String((original["remarks"] as? String ?? "Xray 出口").prefix(120))
        return [key: original, "proxies": [["name": name, "type": "socks5", "server": "127.0.0.1", "port": 23456, "udp": true]],
                "proxy-groups": [["name": "PROXY", "type": "select", "proxies": [name]]], "rules": ["MATCH,PROXY"]]
    }

    static func physicalInterface() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var names = Set<String>(), pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let p = pointer {
            let a = p.pointee; let name = String(cString: a.ifa_name)
            if name.range(of: "^en[0-9]+$", options: .regularExpression) != nil,
               a.ifa_flags & UInt32(IFF_UP) != 0, a.ifa_flags & UInt32(IFF_RUNNING) != 0,
               let address = a.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) { names.insert(name) }
            pointer = a.ifa_next
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.first
    }

    static func runtime(_ original: [String: Any], port: Int, password: String, interface: String?) throws -> Data {
        guard let items = original["outbounds"] as? [[String: Any]], !items.isEmpty, items.count <= 64 else { throw ProxyError("Xray JSON 需要 1–64 个有效出站。") }
        guard (1024...65535).contains(port), !password.isEmpty else { throw ProxyError("Xray 本地入口无效。") }
        if let interface, interface.range(of: "^[A-Za-z][A-Za-z0-9]{0,15}$", options: .regularExpression) == nil { throw ProxyError("Xray 出站网卡格式无效。") }
        var outbounds: [[String: Any]] = []
        for source in items {
            guard let value = source["protocol"] as? String, protocols.contains(value.lowercased()) else { throw ProxyError("Xray 原生文件包含本客户端未支持的出站类型。") }
            var outbound: [String: Any] = ["protocol": value.lowercased()]
            for name in ["settings", "streamSettings", "mux", "tag", "proxySettings"] { outbound[name] = source[name] }
            var stream = outbound["streamSettings"] as? [String: Any] ?? [:]
            if var reality = stream["realitySettings"] as? [String: Any] {
                if reality["password"] == nil { reality["password"] = reality["publicKey"] }
                reality.removeValue(forKey: "privateKey"); reality["show"] = false
                stream["realitySettings"] = reality
            }
            // The app controls the egress interface; imported socket options cannot request privileged behavior.
            stream.removeValue(forKey: "sockopt")
            let settings = outbound["settings"] as? [String: Any] ?? [:]
            let destinations = (settings["vnext"] as? [[String: Any]] ?? settings["servers"] as? [[String: Any]] ?? []).compactMap { $0["address"] as? String }
            if let interface, !destinations.contains(where: loopback) { stream["sockopt"] = ["interface": interface] }
            if !stream.isEmpty { outbound["streamSettings"] = stream }
            outbounds.append(outbound)
        }
        let sourceInbounds = original["inbounds"] as? [[String: Any]] ?? []
        let tag = sourceInbounds.first(where: { ($0["protocol"] as? String)?.lowercased() == "socks" })?["tag"] as? String ?? "socks"
        var result: [String: Any] = ["log": ["loglevel": "none"], "outbounds": outbounds,
            "inbounds": [["tag": tag, "listen": "127.0.0.1", "port": port, "protocol": "socks",
                          "settings": ["auth": "password", "accounts": [["user": "novaproxy", "pass": password]], "udp": true],
                          "sniffing": ["enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true]]]]
        for name in ["dns", "routing", "policy"] { result[name] = original[name] }
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    static func plan(_ document: [String: Any], port: Int, password: String, interface: String?) throws -> RealityBridgePlan {
        guard let original = document[key] as? [String: Any], var adapter = document["proxies"] as? [[String: Any]], adapter.count == 1,
              let name = adapter[0]["name"] as? String else { throw ProxyError("Xray 原生配置结构无效，请重新导入 JSON。") }
        var config = document
        config.removeValue(forKey: key)
        adapter[0] = ["name": name, "type": "socks5", "server": "127.0.0.1", "port": port, "username": "novaproxy", "password": password, "udp": true]
        config["proxies"] = adapter
        return RealityBridgePlan(yaml: try Yams.dump(object: config, sortKeys: true), json: try runtime(original, port: port, password: password, interface: interface), ports: [port])
    }
}
