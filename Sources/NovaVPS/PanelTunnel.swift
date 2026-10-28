import Foundation
import Combine
import Darwin

@MainActor final class PanelTunnel: ObservableObject {
    @Published private(set) var url: URL?
    private var process: Process?
    private var directory: URL?
    private var pipe: Pipe?
    private var monitor: Task<Void, Never>?
    var active: Bool { process?.isRunning == true && url != nil }

    func open(request: ServerRequest, pin: ServerPin, password: String, panel: PanelInfo) async throws -> URL {
        try panel.validate(); try request.validate()
        guard request.host == pin.host, request.sshPort == pin.port else { throw ProxyError("SSH 指纹与当前服务器不符。") }
        if request.passwordAuth { guard !password.isEmpty, !password.contains("\n"), !password.contains("\0") else { throw ProxyError("请填写 SSH 密码。") } }
        await close()
        let folder = URL(fileURLWithPath: "/private/tmp/nvps-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = folder
        do {
            let hosts = folder.appendingPathComponent("known_hosts")
            try privateWrite(Data(pin.knownHost.utf8), hosts)
            let control = folder.appendingPathComponent("master.sock").path
            let (fd, port) = try LocalPort.reserve()
            var reserved = true; defer { if reserved { Darwin.close(fd) } }
            var arguments = ["-F", "/dev/null", "-N", "-T", "-p", String(request.sshPort), "-l", request.username,
                "-L", "127.0.0.1:\(port):127.0.0.1:\(panel.port)", "-o", "ExitOnForwardFailure=yes", "-o", "StrictHostKeyChecking=yes",
                "-o", "UserKnownHostsFile=" + hosts.path, "-o", "GlobalKnownHostsFile=/dev/null", "-o", "HostKeyAlgorithms=" + pin.algorithm,
                "-o", "UpdateHostKeys=no", "-o", "ConnectTimeout=15", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3",
                "-o", "ControlMaster=yes", "-o", "ControlPath=" + control, "-o", "ControlPersist=no", "-o", "IPQoS=none",
                "-o", "NumberOfPasswordPrompts=1", "-o", "BatchMode=" + (request.passwordAuth ? "no" : "yes")]
            var environment = ProcessInfo.processInfo.environment
            environment.removeValue(forKey: "SSH_ASKPASS"); environment.removeValue(forKey: "NOVAPROXY_SSH_PASSWORD")
            if request.passwordAuth {
                let helper = folder.appendingPathComponent("askpass")
                try privateWrite(Data("#!/bin/sh\nexec \"$NOVAPROXY_ASKPASS_EXECUTABLE\" --ssh-askpass\n".utf8), helper)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
                environment["SSH_ASKPASS"] = helper.path; environment["SSH_ASKPASS_REQUIRE"] = "force"; environment["DISPLAY"] = "novavps:0"
                environment["NOVAPROXY_ASKPASS_EXECUTABLE"] = Bundle.main.executableURL!.path; environment["NOVAPROXY_SSH_PASSWORD"] = password
                arguments += ["-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "PubkeyAuthentication=no"]
            } else if !request.identityFile.isEmpty { arguments += ["-i", request.identityFile, "-o", "IdentitiesOnly=yes"] }
            arguments.append(request.host)
            let args = folder.appendingPathComponent("arguments.json"); try privateWrite(JSONEncoder().encode(arguments), args)
            let child = Process(); child.executableURL = Bundle.main.executableURL; child.arguments = ["--supervise-panel", args.path]; child.environment = environment
            let output = Pipe(); child.standardOutput = output; child.standardError = output; pipe = output
            output.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
            Darwin.close(fd); reserved = false
            process = child; try child.run()
            for _ in 0..<100 {
                guard child.isRunning else { throw ProxyError("SSH 隧道未建立，请检查密码、指纹及服务端端口转发设置。") }
                if FileManager.default.fileExists(atPath: control) {
                    let status = try await Task.detached {
                        try SSHDeployment.run(executable: "/usr/bin/ssh", arguments: ["-F", "/dev/null", "-S", control, "-O", "check", request.host], timeout: 3).0
                    }.value
                    if status == 0, child.isRunning, LocalPort.ready(port) {
                        guard let result = URL(string: "http://127.0.0.1:\(port)" + panel.basePath) else { throw ProxyError("后台本地地址无效。") }
                        url = result
                        monitor = Task { [weak self] in
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                guard !Task.isCancelled else { return }
                                if child.isRunning == false { await self?.close(); return }
                            }
                        }
                        return result
                    }
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            throw ProxyError("SSH 隧道连接超时，未打开后台。")
        } catch { await close(); throw error }
    }

    func close() async {
        monitor?.cancel(); monitor = nil
        let child = process; process = nil; url = nil
        if let child, child.isRunning {
            child.terminate()
            for _ in 0..<45 { if !child.isRunning { break }; try? await Task.sleep(nanoseconds: 100_000_000) }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        }
        pipe?.fileHandleForReading.readabilityHandler = nil; pipe = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }; directory = nil
    }

    private func privateWrite(_ data: Data, _ url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
