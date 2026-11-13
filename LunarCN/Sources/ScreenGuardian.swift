import Foundation
import CoreGraphics

private final class Commands {
    private let lock = NSLock()
    private var confirmed = false
    private var connected = true
    private var restoring = false

    func accept(_ command: String?) {
        lock.lock()
        defer { lock.unlock() }
        if command == "keep" { confirmed = true }
        if command == "restore" { restoring = true }
        if command == nil { connected = false }
    }

    func shouldRestore(externalAvailable: Bool, expired: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return restoring || ScreenRecoveryPolicy.shouldRestore(parentConnected: connected,
            externalAvailable: externalAvailable, confirmed: confirmed, expired: expired)
    }
}

@main
enum ScreenGuardian {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        setbuf(stdout, nil)
        let arguments = CommandLine.arguments
        guard arguments.count == 3, let id = UInt32(arguments[1]),
              BuiltinDisplayEngine.uuid(id) == arguments[2], CGDisplayIsBuiltin(id) != 0,
              CGDisplayIsActive(id) != 0 else {
            print("ERROR:内置屏幕身份核对失败。")
            exit(1)
        }
        let commands = Commands()
        DispatchQueue.global().async {
            while let line = readLine() { commands.accept(line) }
            commands.accept(nil)
        }
        do {
            try BuiltinDisplayEngine.setEnabled(false, id: id)
            print("READY")
            let deadline = DispatchTime.now() + 15
            while CGDisplayIsOnline(id) == 0 {
                if commands.shouldRestore(externalAvailable: !BuiltinDisplayEngine.onlineExternalIDs().isEmpty,
                                          expired: DispatchTime.now() >= deadline) { break }
                Thread.sleep(forTimeInterval: 0.25)
            }
        } catch {
            print("ERROR:\(error.localizedDescription)")
        }
        // The guardian outlives the UI process so an app crash still triggers recovery.
        for _ in 0..<3 {
            do {
                try BuiltinDisplayEngine.setEnabled(true, id: id)
                print("RESTORED")
                return
            } catch {
                print("ERROR:\(error.localizedDescription)")
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        exit(1)
    }
}
