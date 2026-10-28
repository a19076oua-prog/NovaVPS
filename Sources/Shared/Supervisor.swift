import Foundation
import Darwin

struct CoreSupervisor {
    static func run(core: String, directory: String, config: String) -> Int32 {
        supervise(core: core, arguments: ["-d", directory, "-f", config])
    }
    static func runXray(core: String, config: String) -> Int32 {
        supervise(core: core, arguments: ["run", "-config", config])
    }
    static func runSSH(arguments: [String]) -> Int32 { supervise(core: "/usr/bin/ssh", arguments: arguments) }
    private static func supervise(core: String, arguments: [String]) -> Int32 {
        let parent = getppid()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: core)
        child.arguments = arguments
        child.standardOutput = FileHandle.standardOutput
        child.standardError = FileHandle.standardError
        do { try child.run() }
        catch { fputs("Core launch failed: \(error.localizedDescription)\n", stderr); return 1 }
        // A separate process observes parent death, including forced app termination.
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        let queue = DispatchQueue(label: "local.novaproxy.supervisor")
        let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        var shuttingDown = false
        var ticks = 0
        let beginShutdown = {
            if !shuttingDown {
                shuttingDown = true
                if child.isRunning { child.terminate() }
            }
        }
        terminate.setEventHandler(handler: beginShutdown)
        interrupt.setEventHandler(handler: beginShutdown)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.3, repeating: 0.3)
        timer.setEventHandler {
            if getppid() != parent { beginShutdown() }
            if shuttingDown {
                ticks += 1
                if ticks > 8, child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        terminate.resume(); interrupt.resume(); timer.resume()
        child.waitUntilExit()
        timer.cancel(); terminate.cancel(); interrupt.cancel()
        return child.terminationStatus
    }
}
