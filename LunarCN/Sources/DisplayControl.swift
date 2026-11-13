import AppKit
import Foundation

struct ControlLevel: Decodable, Equatable {
    let current: Int
    let maximum: Int

    var percent: Double { Double(current) / Double(maximum) * 100 }

    init(current: Int, maximum: Int) throws {
        guard (1...65535).contains(maximum), (0...maximum).contains(current) else {
            throw ControlError.message("显示器返回的数值无效。")
        }
        self.current = current
        self.maximum = maximum
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(current: values.decode(Int.self, forKey: .current),
                      maximum: values.decode(Int.self, forKey: .maximum))
    }

    private enum CodingKeys: String, CodingKey { case current, maximum }

    func rawValue(for percent: Double) throws -> Int {
        guard percent.isFinite, (0...100).contains(percent) else {
            throw ControlError.message("请选择 0% 到 100% 之间的数值。")
        }
        return Int((percent / 100 * Double(maximum)).rounded())
    }
}

enum ControlError: LocalizedError {
    case message(String)
    case writeUnconfirmed(String)
    var errorDescription: String? {
        switch self { case let .message(text), let .writeUnconfirmed(text): return text }
    }
}

struct MuteState: Decodable {
    let current: Int
    var muted: Bool { current == 1 }

    private enum CodingKeys: String, CodingKey { case current }

    init(from decoder: Decoder) throws {
        current = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .current)
        guard current == 1 || current == 2 else { throw ControlError.message("显示器返回的静音状态无效。") }
    }
}

struct ScreenIdentity: Identifiable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let builtin: Bool

    static func connected() -> [Self] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
            return Self(id: number.uint32Value, uuid: CFUUIDCreateString(nil, uuid) as String,
                        name: screen.localizedName, builtin: CGDisplayIsBuiltin(number.uint32Value) != 0)
        }
    }

    func checkConnected() throws {
        guard CGDisplayIsOnline(id) != 0,
              let actual = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              CFUUIDCreateString(nil, actual) as String == uuid else {
            throw ControlError.message("显示器连接已变化，请刷新后重试。")
        }
    }
}

struct ScreenState: Identifiable {
    var id: CGDirectDisplayID { screen.id }
    var revision = UUID()
    let screen: ScreenIdentity
    var brightness: ControlLevel?
    var contrast: ControlLevel?
    var volume: ControlLevel?
    var muted: Bool?
    var range: BrightnessRange = .full
    var savedPreset: ScreenPreset?
    var readOnlyControls: Set<Int> = []
    var followBuiltin = false
    var message = "正在读取…"
}

enum DisplayControl {
    // shortcut: DisplayServices is private, recheck it after macOS updates.
    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    static func read(_ screen: ScreenIdentity, control: Int) throws -> ControlLevel {
        try screen.checkConnected()
        if screen.builtin {
            guard control == 16, let handle = displayServices,
                  let symbol = dlsym(handle, "DisplayServicesGetBrightness") else {
                throw ControlError.message("此屏幕不支持这项控制。")
            }
            var value: Float = 0
            let status = unsafeBitCast(symbol, to: GetBrightness.self)(screen.id, &value)
            guard status == 0, value.isFinite, (0...1).contains(value) else {
                throw ControlError.message("无法读取内置屏幕亮度（\(status)）。")
            }
            return try ControlLevel(current: Int((value * 1000).rounded()), maximum: 1000)
        }
        return try JSONDecoder().decode(ControlLevel.self, from: helper(["read", String(screen.id), screen.uuid, String(control)]))
    }

    @discardableResult static func set(_ screen: ScreenIdentity, control: Int, percent: Double, level: ControlLevel) throws -> ControlLevel {
        try screen.checkConnected()
        let raw = try level.rawValue(for: percent)
        if screen.builtin {
            guard control == 16, let handle = displayServices,
                  let symbol = dlsym(handle, "DisplayServicesSetBrightness") else {
                throw ControlError.message("无法设置内置屏幕亮度。")
            }
            let status = unsafeBitCast(symbol, to: SetBrightness.self)(screen.id, Float(raw) / Float(level.maximum))
            guard status == 0 else { throw ControlError.message("系统拒绝设置内置屏幕亮度（\(status)）。") }
            let actual = try read(screen, control: control)
            guard abs(actual.current - raw) <= 5 else { throw ControlError.message("系统未确认目标亮度，请刷新后检查。") }
            return actual
        } else {
            return try JSONDecoder().decode(ControlLevel.self, from: helper(["set", String(screen.id), screen.uuid, String(control), String(raw)]))
        }
    }

    static func readMute(_ screen: ScreenIdentity) throws -> Bool {
        try screen.checkConnected()
        return try JSONDecoder().decode(MuteState.self,
            from: helper(["read", String(screen.id), screen.uuid, "141"])).muted
    }

    static func setMute(_ screen: ScreenIdentity, muted: Bool) throws {
        try screen.checkConnected()
        _ = try JSONDecoder().decode(MuteState.self,
            from: helper(["set", String(screen.id), screen.uuid, "141", muted ? "1" : "2"]))
    }

    static func helper(_ arguments: [String], executable: URL? = nil, timeout: TimeInterval = 5) throws -> Data {
        let process = Process()
        process.executableURL = executable ?? Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("ddc-helper")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { throw ControlError.message("无法启动显示器控制程序，请重新构建应用。") }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { process.terminate() }
            if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            throw ControlError.message("显示器响应超时，请检查连接后刷新。")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 2 { throw ControlError.writeUnconfirmed(detail) }
            throw ControlError.message(detail.isEmpty ? "显示器控制失败，请刷新后重试。" : detail)
        }
        return data
    }
}

@MainActor
final class DisplayStore: ObservableObject {
    @Published var screens: [ScreenState] = []
    @Published var busy = false
    @Published private(set) var liveTargets: [String: Double] = [:]
    @Published var automaticStatus = "每 2 秒检查内建屏亮度；配合系统自动亮度使用。"
    var preferencesWarning: String? { preferences.loadError }
    private let preferences: PreferencesStore
    private var failedWrites: [String: Set<Int>] = [:]
    private let queue = DispatchQueue(label: "local.lunarcn.display-control", qos: .userInitiated)
    private var generation = 0
    private var automaticTimer: Timer?
    private var automaticRun: DisplayControlRun?
    private var automaticSuspended = true
    private var liveBuffer = LiveBrightnessBuffer()
    private var liveRun: DisplayControlRun?
    private var liveScheduled: DispatchWorkItem?
    private var lastLiveCompletion = -Double.infinity
    private var lastLiveInput = -Double.infinity

    init(preferences: PreferencesStore = PreferencesStore()) { self.preferences = preferences }

    private func decorated(_ state: ScreenState) -> ScreenState {
        var result = state
        let settings = preferences.settings(for: state.screen.uuid)
        result.range = settings.range
        result.savedPreset = settings.preset
        result.followBuiltin = !state.screen.builtin && settings.followBuiltin
        result.readOnlyControls = failedWrites[state.screen.uuid] ?? []
        return result
    }

    func refresh() {
        cancelLiveBrightness()
        cancelAutomaticBrightness()
        generation += 1
        let token = generation
        let identities = ScreenIdentity.connected()
        busy = true
        screens = identities.map { decorated(ScreenState(screen: $0)) }
        queue.async {
            let result = identities.map(Self.load)
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.screens = result.map(self.decorated)
                self.busy = false
                self.pollAutomaticBrightness()
            }
        }
    }

    func apply(_ state: ScreenState, brightness: Double?, contrast: Double?, volume: Double?, muted: Bool?) {
        guard !busy, liveTargets.isEmpty else { return }
        if let brightness, !preferences.settings(for: state.screen.uuid).range.contains(brightness) {
            show("目标亮度超出已保存范围，请先调整范围或预设。", on: state.id)
            return
        }
        let requested = [(16, brightness != nil), (18, contrast != nil), (98, volume != nil), (141, muted != nil)]
        guard !requested.contains(where: { $0.1 && (failedWrites[state.screen.uuid] ?? []).contains($0.0) }) else {
            show("此项目的写入已暂停，请先检查连接并点击“允许重试写入”。", on: state.id)
            return
        }
        cancelAutomaticBrightness()
        if brightness != nil, state.followBuiltin {
            do {
                try preferences.saveFollowBuiltin(false, for: state.screen.uuid)
                if let index = screens.firstIndex(where: { $0.screen.uuid == state.screen.uuid }) { screens[index].followBuiltin = false }
            } catch { show(error.localizedDescription, on: state.id); return }
        }
        busy = true
        let token = generation
        queue.async {
            var failure: String?
            var activeControl: Int?
            var rejectedControl: Int?
            do {
                if let brightness, let level = state.brightness {
                    activeControl = 16
                    try DisplayControl.set(state.screen, control: 16, percent: brightness, level: level)
                }
                if let contrast, let level = state.contrast {
                    activeControl = 18
                    try DisplayControl.set(state.screen, control: 18, percent: contrast, level: level)
                }
                if let volume, let level = state.volume {
                    activeControl = 98
                    try DisplayControl.set(state.screen, control: 98, percent: volume, level: level)
                }
                if let muted {
                    activeControl = 141
                    try DisplayControl.setMute(state.screen, muted: muted)
                }
            } catch {
                failure = error.localizedDescription
                if case ControlError.writeUnconfirmed = error { rejectedControl = activeControl }
            }
            var result = Self.load(state.screen)
            if let failure {
                result.message = failure
            } else if result.message == "已读取当前设置" {
                result.message = "已应用并读取确认"
            }
            let updated = result
            let rejected = rejectedControl
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                if let rejected { self.failedWrites[state.screen.uuid, default: []].insert(rejected) }
                if let index = self.screens.firstIndex(where: { $0.screen.uuid == state.screen.uuid }) {
                    self.screens[index] = self.decorated(updated)
                }
                self.busy = false
            }
        }
    }

    private func show(_ message: String, on id: UInt32) {
        if let index = screens.firstIndex(where: { $0.id == id }) { screens[index].message = message }
    }

    func allowRetry(_ state: ScreenState) {
        guard !busy else { return }
        failedWrites[state.screen.uuid] = nil
        if let index = screens.firstIndex(where: { $0.id == state.id }) {
            screens[index].readOnlyControls = []
            screens[index].revision = UUID()
            screens[index].message = state.followBuiltin ? "已允许重试自动亮度，正在读取并跟随。" : "已允许再次尝试写入，请调整目标值后点击应用。"
        }
        pollAutomaticBrightness()
    }

    func saveRange(_ state: ScreenState, minimum: Int, maximum: Int) {
        guard !busy else { return }
        cancelLiveBrightness()
        cancelAutomaticBrightness()
        do {
            let range = try BrightnessRange(minimum: minimum, maximum: maximum)
            try preferences.saveRange(range, for: state.screen.uuid)
            if let index = screens.firstIndex(where: { $0.id == state.id }) {
                screens[index].range = range
                screens[index].revision = UUID()
                screens[index].message = "亮度范围已保存；当前设备值保持不变。"
            }
        } catch { show(error.localizedDescription, on: state.id) }
    }

    private func cancelAutomaticBrightness() {
        automaticRun?.cancel()
        automaticRun = nil
    }

    func setLiveBrightness(_ state: ScreenState, percent: Double) {
        guard !busy, let current = screens.first(where: { $0.screen.uuid == state.screen.uuid && $0.id == state.id }),
              !current.followBuiltin, !current.readOnlyControls.contains(16), current.brightness != nil else { return }
        do {
            let request = try LiveBrightnessRequest(screen: state.screen, percent: percent,
                                                    range: preferences.settings(for: state.screen.uuid).range)
            cancelAutomaticBrightness()
            lastLiveInput = ProcessInfo.processInfo.systemUptime
            liveBuffer.submit(request)
            liveTargets[state.screen.uuid] = percent
            scheduleLiveBrightness()
        } catch { show(error.localizedDescription, on: state.id) }
    }

    private func cancelLiveBrightness() {
        liveScheduled?.cancel()
        liveScheduled = nil
        liveRun?.cancel()
        liveRun = nil
        liveBuffer = LiveBrightnessBuffer()
        liveTargets = [:]
    }

    private func scheduleLiveBrightness() {
        guard liveRun == nil, liveScheduled == nil, let request = liveBuffer.first else { return }
        let interval = request.screen.builtin ? 0.05 : 0.15
        let delay = max(0, lastLiveCompletion + interval - ProcessInfo.processInfo.systemUptime)
        let work = DispatchWorkItem { [weak self] in
            self?.liveScheduled = nil
            self?.writeNextLiveBrightness()
        }
        liveScheduled = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func writeNextLiveBrightness() {
        guard !busy, liveRun == nil, let request = liveBuffer.take() else { return }
        let run = DisplayControlRun()
        liveRun = run
        queue.async {
            let result = Result { try LiveBrightnessEngine.apply(request, run: run) }
            var fallback: ControlLevel?
            if case .failure = result, (try? run.check()) != nil {
                fallback = try? DisplayControl.read(request.screen, control: 16)
            }
            let actualOnFailure = fallback
            DispatchQueue.main.async {
                guard self.liveRun === run else { return }
                self.liveRun = nil
                self.lastLiveCompletion = ProcessInfo.processInfo.systemUptime
                guard let index = self.screens.firstIndex(where: { $0.screen.uuid == request.screen.uuid && $0.id == request.screen.id }) else {
                    self.liveBuffer.remove(uuid: request.screen.uuid)
                    self.liveTargets[request.screen.uuid] = nil
                    self.scheduleLiveBrightness()
                    return
                }
                switch result {
                case let .success(level):
                    self.screens[index].brightness = level
                    self.screens[index].message = "亮度已实时调整并读取确认"
                case let .failure(error):
                    self.liveBuffer.remove(uuid: request.screen.uuid)
                    self.failedWrites[request.screen.uuid, default: []].insert(16)
                    self.screens[index].readOnlyControls.insert(16)
                    if let actualOnFailure { self.screens[index].brightness = actualOnFailure }
                    self.screens[index].message = "实时亮度已暂停：\(error.localizedDescription)"
                }
                if !self.liveBuffer.contains(uuid: request.screen.uuid) { self.liveTargets[request.screen.uuid] = nil }
                self.scheduleLiveBrightness()
            }
        }
    }

    func startAutomaticBrightness() {
        guard automaticTimer == nil else { return }
        automaticSuspended = false
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollAutomaticBrightness() }
        }
        RunLoop.main.add(timer, forMode: .common)
        automaticTimer = timer
        pollAutomaticBrightness()
    }

    func stopAutomaticBrightness() {
        cancelLiveBrightness()
        automaticSuspended = true
        automaticTimer?.invalidate()
        automaticTimer = nil
        cancelAutomaticBrightness()
        automaticStatus = "自动亮度已暂停，外接屏保持当前亮度。"
    }

    func setFollowBuiltin(_ state: ScreenState, enabled: Bool) {
        guard !busy, !state.screen.builtin else { return }
        do {
            try preferences.saveFollowBuiltin(enabled, for: state.screen.uuid)
            cancelLiveBrightness()
            cancelAutomaticBrightness()
            if let index = screens.firstIndex(where: { $0.screen.uuid == state.screen.uuid }) { screens[index].followBuiltin = enabled }
            if enabled {
                automaticStatus = "正在读取内建屏亮度…"
                pollAutomaticBrightness()
            }
            else { refresh() }
        } catch { show(error.localizedDescription, on: state.id) }
    }

    private func pollAutomaticBrightness() {
        guard !automaticSuspended, !busy, automaticRun == nil, liveTargets.isEmpty,
              ProcessInfo.processInfo.systemUptime - lastLiveInput >= 0.5 else { return }
        guard screens.contains(where: { $0.followBuiltin }) else { return }
        let targets = screens.filter { $0.followBuiltin && $0.brightness != nil && !$0.readOnlyControls.contains(16) }
        guard !targets.isEmpty else {
            automaticStatus = "自动亮度已暂停，等待可用的外接屏亮度读数；请检查连接并刷新。"
            return
        }
        guard let source = screens.first(where: { $0.screen.builtin })?.screen else {
            automaticStatus = "未找到活动的内建屏，自动亮度已暂停；外接屏保持当前亮度。"
            return
        }
        let run = DisplayControlRun()
        automaticRun = run
        let token = generation
        queue.async {
            let result = Result { try AutomaticBrightnessEngine.sample(source: source, targets: targets, run: run) }
            DispatchQueue.main.async {
                guard token == self.generation, self.automaticRun === run, !self.automaticSuspended else { return }
                self.automaticRun = nil
                switch result {
                case let .success((sourceLevel, updates)):
                    self.automaticStatus = "正在跟随内建屏：\(Int(sourceLevel.percent.rounded()))% · 分步调整亮度。"
                    if let index = self.screens.firstIndex(where: { $0.screen.uuid == source.uuid }) { self.screens[index].brightness = sourceLevel }
                    for update in updates {
                        guard let index = self.screens.firstIndex(where: { $0.screen.uuid == update.screen.uuid && $0.id == update.screen.id }), self.screens[index].followBuiltin else { continue }
                        switch update.result {
                        case let .success(level):
                            self.screens[index].brightness = level
                            if self.screens[index].message.hasPrefix("自动亮度已暂停") || self.screens[index].message.hasPrefix("已允许重试自动亮度") {
                                self.screens[index].message = "自动亮度已同步并读取确认"
                            }
                        case let .failure(error):
                            self.failedWrites[update.screen.uuid, default: []].insert(16)
                            self.screens[index].readOnlyControls.insert(16)
                            self.screens[index].message = "自动亮度已暂停：\(error.localizedDescription)"
                        }
                    }
                case let .failure(error):
                    self.automaticStatus = "无法读取内建屏，已暂停跟随：\(error.localizedDescription)"
                }
            }
        }
    }

    func savePreset(_ state: ScreenState) {
        guard !busy, liveTargets.isEmpty else { return }
        do {
            let preset = try ScreenPreset(brightness: state.brightness?.percent, contrast: state.contrast?.percent,
                                          volume: state.volume?.percent, muted: state.muted)
            try preferences.savePreset(preset, for: state.screen.uuid)
            if let index = screens.firstIndex(where: { $0.id == state.id }) { screens[index].savedPreset = preset }
            show("当前设备值已保存为此显示器的预设。", on: state.id)
        } catch { show(error.localizedDescription, on: state.id) }
    }

    func restorePreset(_ state: ScreenState) {
        guard !busy, liveTargets.isEmpty, let preset = state.savedPreset else { return }
        func changed(_ saved: Double?, _ current: ControlLevel?, _ control: Int) -> Double? {
            guard let saved, let current, !state.readOnlyControls.contains(control), abs(saved - current.percent) > 0.1 else { return nil }
            return saved
        }
        let brightness = changed(preset.brightness, state.brightness, 16)
        let contrast = changed(preset.contrast, state.contrast, 18)
        let volume = changed(preset.volume, state.volume, 98)
        let muted = preset.muted != state.muted && state.muted != nil && !state.readOnlyControls.contains(141) ? preset.muted : nil
        guard brightness != nil || contrast != nil || volume != nil || muted != nil else {
            show("预设的可用项目与当前设置一致；不可用或暂停的项目已跳过。", on: state.id)
            return
        }
        apply(state, brightness: brightness, contrast: contrast, volume: volume, muted: muted)
    }

    nonisolated private static func load(_ screen: ScreenIdentity) -> ScreenState {
        var state = ScreenState(screen: screen)
        var failures: [String] = []
        do { state.brightness = try DisplayControl.read(screen, control: 16) }
        catch { failures.append("亮度：\(error.localizedDescription)") }
        if !screen.builtin {
            do { state.contrast = try DisplayControl.read(screen, control: 18) }
            catch { failures.append("对比度：\(error.localizedDescription)") }
            state.volume = try? DisplayControl.read(screen, control: 98)
            state.muted = try? DisplayControl.readMute(screen)
        }
        state.message = failures.isEmpty ? "已读取当前设置" : failures.joined(separator: "\n")
        return state
    }
}
