import AppKit
import SwiftUI

@MainActor
final class BuiltinDisplayController: ObservableObject {
    @Published var isOff = false
    @Published var available = false
    @Published var externalReady = false
    @Published var busy = false
    @Published var awaitingConfirmation = false
    @Published var remaining = 15
    @Published var message = "关闭内置屏幕后，键盘和触控板仍可使用。"
    var didChange: (() -> Void)?
    var willTurnOff: (() -> Void)?
    private var guardian: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var received = ""
    private var timer: Timer?
    private var failure: String?

    init() { updateAvailability() }

    func updateAvailability() {
        do {
            let id = try BuiltinDisplayEngine.builtinID()
            available = true
            let nowOff = CGDisplayIsActive(id) == 0
            if isOff && !nowOff {
                awaitingConfirmation = false
                timer?.invalidate()
                message = failure ?? "内置屏幕已恢复。"
            }
            isOff = nowOff
            externalReady = !BuiltinDisplayEngine.visibleExternalIDs().isEmpty
        } catch {
            available = false
            message = error.localizedDescription
        }
    }

    func turnOff() {
        guard !busy, guardian == nil else { return }
        do {
            let id = try BuiltinDisplayEngine.builtinID()
            let external = BuiltinDisplayEngine.visibleExternalIDs()
            guard CGDisplayIsActive(id) != 0, let uuid = BuiltinDisplayEngine.uuid(id), !external.isEmpty else {
                throw BuiltinDisplayError.message("请先连接并开启一台实体外接显示器，再关闭内置屏幕。")
            }
            willTurnOff?()
            if let screen = NSScreen.screens.first(where: {
                let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                return number.map { external.contains($0.uint32Value) } ?? false
            }) {
                for window in NSApp.windows where window.isVisible {
                    window.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - window.frame.width / 2,
                                                  y: screen.visibleFrame.midY - window.frame.height / 2))
                }
            }
            let process = Process()
            process.executableURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("screen-guardian")
            process.arguments = [String(id), uuid]
            let commands = Pipe()
            let responses = Pipe()
            process.standardInput = commands
            process.standardOutput = responses
            process.standardError = FileHandle.nullDevice
            input = commands.fileHandleForWriting
            output = responses.fileHandleForReading
            received = ""
            failure = nil
            guardian = process
            busy = true
            message = "正在关闭内置屏幕…"
            output?.readabilityHandler = { [weak self, weak process] handle in
                let data = handle.availableData
                Task { @MainActor [weak self, weak process] in
                    guard let self, let process, self.guardian === process else { return }
                    self.receive(data)
                }
            }
            do { try process.run() } catch {
                clearGuardian()
                throw BuiltinDisplayError.message("无法启动屏幕恢复保护程序，请重新构建应用。")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self, weak process] in
                guard let self, let process, self.guardian === process, self.busy, !self.awaitingConfirmation else { return }
                self.message = "屏幕配置响应较慢，已请求恢复。"
                self.send("restore")
            }
        } catch {
            busy = false
            message = error.localizedDescription
            updateAvailability()
            didChange?()
        }
    }

    func keepOff() {
        guard awaitingConfirmation, isOff, guardian?.isRunning == true else { return }
        if send("keep") {
            awaitingConfirmation = false
            timer?.invalidate()
            message = "内置屏幕保持关闭；断开外接屏或退出月光时会恢复。"
        }
    }

    func restore() {
        if guardian?.isRunning == true {
            busy = true
            _ = send("restore")
            return
        }
        busy = true
        Task {
            let error: String? = await Task.detached {
                do {
                    try BuiltinDisplayEngine.setEnabled(true, id: BuiltinDisplayEngine.builtinID())
                    return nil as String?
                } catch { return error.localizedDescription }
            }.value
            self.busy = false
            self.message = error ?? "内置屏幕已恢复。"
            self.updateAvailability()
            self.didChange?()
        }
    }

    func restoreOnQuit() {
        _ = send("restore")
        try? input?.close()
    }

    @discardableResult private func send(_ command: String) -> Bool {
        guard let input else { return false }
        do {
            try input.write(contentsOf: Data("\(command)\n".utf8))
            return true
        } catch {
            message = "恢复保护进程连接中断，请点击恢复内置屏幕。"
            return false
        }
    }

    private func receive(_ data: Data) {
        if data.isEmpty {
            clearGuardian()
            busy = false
            updateAvailability()
            if isOff {
                restore()
            } else {
                message = failure ?? "内置屏幕已恢复。"
                didChange?()
            }
            return
        }
        received += String(decoding: data, as: UTF8.self)
        while let newline = received.firstIndex(of: "\n") {
            let line = String(received[..<newline])
            received.removeSubrange(...newline)
            if line == "READY" {
                busy = false
                isOff = true
                awaitingConfirmation = true
                remaining = 15
                message = "请确认外接屏可见；不确认将自动恢复。"
                let deadline = Date().addingTimeInterval(15)
                timer?.invalidate()
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
                    }
                }
                didChange?()
            } else if line == "RESTORED" {
                timer?.invalidate()
                awaitingConfirmation = false
                busy = false
                isOff = false
                message = failure ?? "内置屏幕已恢复。"
                didChange?()
            } else if line.hasPrefix("ERROR:") {
                failure = String(line.dropFirst(6))
                message = failure!
            }
        }
    }

    private func clearGuardian() {
        timer?.invalidate()
        awaitingConfirmation = false
        output?.readabilityHandler = nil
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        guardian = nil
    }
}

struct BuiltinDisplayCard: View {
    @ObservedObject var control: BuiltinDisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("笔记本屏幕", systemImage: "laptopcomputer").font(.headline)
            Text(control.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if control.awaitingConfirmation {
                Text("\(control.remaining) 秒后自动恢复").font(.caption).monospacedDigit()
                HStack {
                    Button("恢复内置屏幕") { control.restore() }
                    Spacer()
                    Button("保持关闭") { control.keepOff() }.buttonStyle(.borderedProminent)
                }
            } else if control.isOff || control.busy {
                Button("恢复内置屏幕") { control.restore() }.buttonStyle(.borderedProminent)
            } else {
                Button("关闭内置屏幕") { control.turnOff() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!control.available || !control.externalReady || control.busy)
                if control.available && !control.externalReady {
                    Text("需要先连接并开启实体外接显示器。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}
