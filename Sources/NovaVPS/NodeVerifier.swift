import Foundation
import Darwin

enum LocalPort {
    static func reserve() throws -> (Int32, Int) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ProxyError("无法分配本地端口。") }
        var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let fetched = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        guard result == 0, fetched == 0 else { Darwin.close(fd); throw ProxyError("无法预留本地端口。") }
        return (fd, Int(UInt16(bigEndian: address.sin_port)))
    }
    static func ready(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0); guard fd >= 0 else { return false }; defer { Darwin.close(fd) }
        var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = UInt16(port).bigEndian
        return withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 } }
    }
}

enum NodeVerifier {
    static func verify(_ node: DeployedNode) throws -> Int {
        guard let binary = Bundle.main.resourceURL?.appendingPathComponent("xray").path else { throw ProxyError("节点验证内核缺失。") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("novavps-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let (fd, port) = try LocalPort.reserve()
        var reserved = true; defer { if reserved { Darwin.close(fd) } }
        let password = UUID().uuidString + UUID().uuidString
        let object = try JSONSerialization.jsonObject(with: node.nativeJSON()) as! [String: Any]
        let data = try NativeXrayProfile.runtime(object, port: port, password: password, interface: NativeXrayProfile.physicalInterface())
        let configuration = directory.appendingPathComponent("probe.json")
        try data.write(to: configuration, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configuration.path)
        let (valid, _) = try SSHDeployment.run(executable: binary, arguments: ["run", "-test", "-config", configuration.path], timeout: 12)
        guard valid == 0 else { throw ProxyError("生成的配置未通过 Xray 参数校验。") }
        let process = Process(); process.executableURL = Bundle.main.executableURL
        process.arguments = ["--supervise-xray", binary, configuration.path]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        Darwin.close(fd); reserved = false
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            for _ in 0..<40 { if !process.isRunning { break }; Thread.sleep(forTimeInterval: 0.05) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit(); pipe.fileHandleForReading.readabilityHandler = nil
        }
        for _ in 0..<80 {
            guard process.isRunning else { throw ProxyError("节点验证内核未能启动。") }
            if LocalPort.ready(port) { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard LocalPort.ready(port) else { throw ProxyError("节点验证入口启动超时。") }
        let configurationText = "proxy = \"socks5h://127.0.0.1:\(port)\"\nproxy-user = \"novaproxy:\(password)\"\nurl = \"https://www.gstatic.com/generate_204\"\n"
        let (status, output) = try SSHDeployment.run(executable: "/usr/bin/curl", arguments: ["-q", "--noproxy", "", "--silent", "--connect-timeout", "8", "--max-time", "20", "--output", "/dev/null", "--write-out", "%{http_code}\n%{time_total}", "--config", "-"], input: configurationText, timeout: 24)
        return try ConnectivityProbe.parse(status: status, output: output).milliseconds
    }
}
