import Foundation
import AppKit
import Vision
import Darwin

@main struct NativeChecks {
    static var checks = 0
    static func check(_ value: @autoclosure () throws -> Bool, _ name: String) throws {
        guard try value() else { throw ProxyError("FAIL " + name) }; checks += 1; print("PASS " + name)
    }
    static func rejects(_ name: String, _ body: () throws -> Void) throws {
        var failed = false; do { try body() } catch { failed = true }; try check(failed, name)
    }
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 2, args[1] == "--ssh-askpass" { FileHandle.standardOutput.write(Data(((ProcessInfo.processInfo.environment["NOVAPROXY_SSH_PASSWORD"] ?? "") + "\n").utf8)); return }
        if args.count == 3, args[1] == "--supervise-panel" { exit(CoreSupervisor.runSSH(arguments: try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: args[2]))))) }
        if args.count == 4, args[1] == "--supervise-xray" { exit(CoreSupervisor.runXray(core: args[2], config: args[3])) }
        let fixture = URL(fileURLWithPath: args[1])
        let key = Data(repeating: 7, count: 32).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let node = DeployedNode(server: "203.0.113.10", port: 18443, uuid: "aa6e9817-af14-4d58-b93a-f9e720c81173", publicKey: key, shortId: "aabbccdd00112233", serverName: "example.com")
        try check(try NodeImport.parse(node.shareLink()) == node, "VLESS link round trip")
        try check(try NodeImport.parse(String(decoding: node.nativeJSON(), as: UTF8.self)) == node, "Xray JSON round trip")
        try check(try NodeImport.parse(node.yaml()) == node, "Clash YAML round trip")
        let ipv6 = DeployedNode(server: "2001:db8::1", port: node.port, uuid: node.uuid, publicKey: key, shortId: node.shortId, serverName: node.serverName)
        try check(try NodeImport.parse(ipv6.shareLink()) == ipv6, "IPv6 link round trip")
        try rejects("unsupported transport rejected") { _ = try NodeImport.parse(node.yaml().replacingOccurrences(of: "network: tcp", with: "network: ws")) }
        try rejects("fingerprint loss rejected") { _ = try NodeImport.parse(node.yaml().replacingOccurrences(of: "client-fingerprint: chrome", with: "client-fingerprint: firefox")) }
        let exported = fixture.appendingPathComponent("export")
        try VPSModel.export(node, to: exported)
        try check(try FileManager.default.contentsOfDirectory(atPath: exported.path).count == 4, "all four export formats")
        for file in try FileManager.default.contentsOfDirectory(at: exported, includingPropertiesForKeys: nil) {
            let mode = (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber).intValue
            try check(mode == 0o600, "private export permission " + file.lastPathComponent)
        }
        let image = try Data(contentsOf: exported.appendingPathComponent("node-qr.png"))
        let qr = VNDetectBarcodesRequest(); qr.symbologies = [.qr]
        try VNImageRequestHandler(data: image).perform([qr])
        try check(qr.results?.first?.payloadStringValue == node.shareLink(), "QR decodes to exact VLESS link")
        let xray = Bundle.main.resourceURL!.appendingPathComponent("xray").path
        let validated = try SSHDeployment.run(executable: xray, arguments: ["run", "-test", "-config", exported.appendingPathComponent("node.xray.json").path], timeout: 15)
        try check(validated.0 == 0, "bundled Xray validates exported JSON")
        var request = ServerRequest(); request.host = node.server; request.nodePort = node.port; request.serverName = node.serverName
        func envelope(_ object: [String: Any]) throws -> String { "NOVAVPS_RESULT: " + (try JSONSerialization.data(withJSONObject: object)).base64EncodedString() + "\n" }
        let missing = try envelope(["success":true,"result":["installed":false,"state":"not-installed"]])
        try check(try !PanelService.parse(missing, status: 0, request: request).installed, "remote result parser")
        try rejects("SSH nonzero cannot report success") { _ = try PanelService.parse(missing, status: 255, request: request) }
        try rejects("duplicate result marker rejected") { _ = try PanelService.parse(missing + missing, status: 0, request: request) }
        try rejects("unverified HTTP rejected") { _ = try ConnectivityProbe.parse(status: 0, output: "200\n0.1") }
        try rejects("failed curl rejected") { _ = try ConnectivityProbe.parse(status: 7, output: "204\n0.1") }
        setenv("NOVAVPS_DATA_DIR", fixture.appendingPathComponent("records").path, 1)
        let model = VPSModel(); model.password = "fixture-memory-only-password"
        try model.importNode(node.shareLink())
        try check(model.password.isEmpty, "import clears SSH password from memory")
        let recordData = try Data(contentsOf: model.directory.appendingPathComponent("servers.json"))
        try check(!String(decoding: recordData, as: UTF8.self).contains("fixture-memory-only-password"), "SSH password absent from saved records")
        try check(!model.canOperate, "import cannot authorize remote deployment without confirmed SSH pin")
        let recoveryDirectory = fixture.appendingPathComponent("recovery")
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try recordData.write(to: recoveryDirectory.appendingPathComponent("servers.json"))
        var recovered = try JSONDecoder().decode([VPSRecord].self, from: recordData)
        recovered[0].id = UUID(); recovered[0].request.sshPort = 2222
        try JSONEncoder().encode(recovered).write(to: recoveryDirectory.appendingPathComponent("recovered-servers.json"))
        setenv("NOVAVPS_DATA_DIR", recoveryDirectory.path, 1)
        let restored = VPSModel()
        try check(restored.records.count == 1 && restored.records.first?.request.sshPort == 2222 && restored.error == nil, "update recovery merges records without duplicate VPS")
        try check(!FileManager.default.fileExists(atPath: recoveryDirectory.appendingPathComponent("recovered-servers.json").path), "update recovery keeps applied backup")
        let ready = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("ready.json"))) as! [String: Any]
        request.host = "127.0.0.1"; request.sshPort = ready["sshPort"] as! Int
        let pin = try SSHDeployment.scan(request)
        let result = try PanelService.perform(.inspect, request: request, pin: pin, password: "fixture-ssh-password-only")
        try check(result.installed && result.state == "active", "real OpenSSH password transport + API envelope")
        let passwordResult = try SSHDeployment.execute(request, pin: pin, password: "fixture-wrong-password", script: "fixture", command: "fixture", timeout: 10)
        try check(passwordResult.0 != 0, "wrong SSH password rejected")
        let badPin = ServerPin(host: pin.host, port: pin.port, knownHost: pin.knownHost.replacingOccurrences(of: "AAAAC3", with: "AAAAD3"), algorithm: pin.algorithm, fingerprint: pin.fingerprint)
        let pinResult = try SSHDeployment.execute(request, pin: badPin, password: "fixture-ssh-password-only", script: "fixture", command: "fixture", timeout: 10)
        try check(pinResult.0 != 0, "changed SSH host key rejected")
        let tunnel = PanelTunnel()
        let url = try await tunnel.open(request: request, pin: pin, password: "fixture-ssh-password-only", panel: result.panel!)
        let response = try SSHDeployment.run(executable: "/usr/bin/curl", arguments: ["-q", "--noproxy", "*", "--fail", "--max-time", "5", "--silent", url.absoluteString], timeout: 8)
        try check(response.0 == 0 && response.1 == "NOVAVPS_TUNNEL_FIXTURE", "real SSH loopback forwarding")
        let localPort = url.port!; await tunnel.close()
        try check(!tunnel.active && !LocalPort.ready(localPort), "closing tunnel releases listener")
        print("Native checks passed: \(checks)")
    }
}
