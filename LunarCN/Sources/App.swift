import AppKit
import SwiftUI

struct MonitorCard: View {
    let state: ScreenState
    @ObservedObject var store: DisplayStore
    @State private var contrast: Double
    @State private var volume: Double
    @State private var muted: Bool
    @State private var minimum: Int
    @State private var maximum: Int

    init(state: ScreenState, store: DisplayStore) {
        self.state = state
        self.store = store
        _contrast = State(initialValue: state.contrast?.percent ?? 0)
        _volume = State(initialValue: state.volume?.percent ?? 0)
        _muted = State(initialValue: state.muted ?? false)
        _minimum = State(initialValue: state.range.minimum)
        _maximum = State(initialValue: state.range.maximum)
    }

    private var brightness: Double { state.range.clamped(store.liveTargets[state.screen.uuid] ?? state.brightness?.percent ?? 0) }

    private var contrastChanged: Bool { !state.readOnlyControls.contains(18) && (state.contrast.map { abs(contrast - $0.percent) > 0.1 } ?? false) }
    private var volumeChanged: Bool { !state.readOnlyControls.contains(98) && (state.volume.map { abs(volume - $0.percent) > 0.1 } ?? false) }
    private var muteChanged: Bool { !state.readOnlyControls.contains(141) && (state.muted.map { muted != $0 } ?? false) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: state.screen.builtin ? "laptopcomputer" : "display")
                    .font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.screen.name).font(.headline).textSelection(.enabled)
                    Text(state.screen.builtin ? "内置屏幕 · 系统亮度" : "外接显示器 · 硬件调光")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if state.brightness != nil {
                levelSlider("亮度", icon: "sun.max", value: Binding(get: { brightness }, set: { store.setLiveBrightness(state, percent: $0) }),
                            range: Double(state.range.minimum)...Double(state.range.maximum))
                    .disabled(state.readOnlyControls.contains(16) || state.followBuiltin)
                if let actual = state.brightness, !state.range.contains(actual.percent) {
                    Text("设备当前亮度为 \(Int(actual.percent.rounded()))%，超出保存范围；移动亮度滑块即调整。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if state.contrast != nil {
                levelSlider("对比度", icon: "circle.lefthalf.filled", value: $contrast)
                    .disabled(state.readOnlyControls.contains(18))
            }
            if !state.screen.builtin, state.brightness != nil || state.followBuiltin {
                Toggle("自动亮度 · 跟随内建屏", isOn: Binding(get: { state.followBuiltin }, set: { store.setFollowBuiltin(state, enabled: $0) }))
                    .toggleStyle(.switch)
                if state.followBuiltin {
                    Text(state.readOnlyControls.contains(16) ? "自动亮度写入已暂停；检查连接后点击“允许重试写入”。" : store.automaticStatus)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text("关闭自动亮度后可手动调节。内建屏关闭时暂停跟随，恢复后继续。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if state.volume != nil {
                levelSlider("显示器音量", icon: "speaker.wave.2", value: $volume)
                    .disabled(state.readOnlyControls.contains(98))
            }
            if state.muted != nil {
                Toggle("显示器静音", isOn: $muted).toggleStyle(.switch).disabled(state.readOnlyControls.contains(141))
            }
            if !state.screen.builtin, state.volume == nil, state.muted == nil {
                Text("此设备未返回可用的显示器音量或静音控制。").font(.caption).foregroundStyle(.secondary)
            }
            Text(state.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !state.readOnlyControls.isEmpty {
                Text("读取或写入异常的调节已暂停，读数仍可刷新。检查连接或显示器设置后，可允许重试。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("允许重试写入") { store.allowRetry(state) }.controlSize(.small)
            }
            if state.contrast != nil || state.volume != nil || state.muted != nil {
                HStack {
                    Spacer()
                    Button("应用其他更改") {
                        store.apply(state, brightness: nil,
                                    contrast: contrastChanged ? contrast : nil,
                                    volume: volumeChanged ? volume : nil, muted: muteChanged ? muted : nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.busy || !store.liveTargets.isEmpty || (!contrastChanged && !volumeChanged && !muteChanged))
                }
            }
            DisclosureGroup("设置与预设") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("范围和预设按此显示器保存，重新打开应用后保留。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if state.brightness != nil {
                        Stepper("亮度下限：\(minimum)%", value: $minimum, in: 0...99)
                        Stepper("亮度上限：\(maximum)%", value: $maximum, in: 1...100)
                        Button("保存亮度范围") { store.saveRange(state, minimum: minimum, maximum: maximum) }
                            .disabled(minimum >= maximum || !store.liveTargets.isEmpty)
                        if minimum >= maximum { Text("下限必须小于上限。").font(.caption).foregroundStyle(.red) }
                    }
                    HStack {
                        Button("保存当前设备值") { store.savePreset(state) }
                        Button("恢复预设（可用项）") { store.restorePreset(state) }.disabled(state.savedPreset == nil)
                    }.controlSize(.small).disabled(!store.liveTargets.isEmpty)
                    Text("亮度拖动即生效；其他项目先应用再保存。恢复时跳过不可用或暂停的项目；应用亮度预设会关闭自动跟随。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 8)
            }.font(.subheadline)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
        .disabled(store.busy)
    }

    private func levelSlider(_ title: String, icon: String, value: Binding<Double>, range: ClosedRange<Double> = 0...100) -> some View {
        VStack(spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))%").monospacedDigit().foregroundStyle(.secondary)
            }.font(.subheadline)
            Slider(value: value, in: range, step: 1) { Text(title) }
                .labelsHidden()
                .accessibilityValue("\(Int(value.wrappedValue.rounded())) 百分比")
        }
    }
}

struct ControlPanel: View {
    @ObservedObject var store: DisplayStore
    @ObservedObject var builtin: BuiltinDisplayController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill").font(.largeTitle).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("月光").font(.title2.bold())
                    Text("中文显示器控制 · \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.busy || !store.liveTargets.isEmpty { ProgressView().controlSize(.small).accessibilityLabel("正在读取或调整显示器") }
                Button { store.refresh(); builtin.updateAvailability() } label: { Image(systemName: "arrow.clockwise") }
                    .help("重新读取显示器设置").accessibilityLabel("刷新显示器")
                    .disabled(store.busy)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    if let warning = store.preferencesWarning {
                        Text(warning).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    BuiltinDisplayCard(control: builtin)
                    if store.screens.isEmpty && !store.busy {
                        VStack(spacing: 12) {
                            Image(systemName: "display.trianglebadge.exclamationmark").font(.largeTitle)
                            Text("没有检测到可用屏幕").font(.headline)
                            Text("连接显示器后点击刷新。").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 48)
                    }
                    ForEach(store.screens) { state in
                        MonitorCard(state: state, store: store).id("\(state.screen.uuid)-\(state.revision)")
                    }
                    Text("亮度拖动即生效；对比度、音量和静音点击“应用其他更改”后写入。外接屏需开启 DDC/CI。")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(16)
            }.background(Color(nsColor: .windowBackgroundColor))
            Divider()
            HStack {
                Text("独立开发版本").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("许可与来源") { NSWorkspace.shared.open(Bundle.main.resourceURL!.appendingPathComponent("NOTICE.txt")) }
                    .buttonStyle(.link)
                Button("退出") { NSApp.terminate(nil) }.buttonStyle(.link)
            }.padding(14)
        }
        .frame(minWidth: 430, minHeight: 560)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DisplayStore()
    private let builtin = BuiltinDisplayController()
    private var item: NSStatusItem!
    private var window: NSWindow!
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "moon.stars", accessibilityDescription: "月光显示器控制")
        item.button?.target = self
        item.button?.action = #selector(showWindow)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 430, height: 590)
        window.title = "月光 · 中文显示器控制"
        window.contentView = NSHostingView(rootView: ControlPanel(store: store, builtin: builtin))
        window.isReleasedWhenClosed = false
        window.center()
        showWindow()
        store.refresh()
        store.startAutomaticBrightness()
        builtin.updateAvailability()
        builtin.willTurnOff = { [weak self] in self?.store.stopAutomaticBrightness() }
        builtin.didChange = { [weak self] in self?.store.refresh(); self?.store.startAutomaticBrightness() }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.lunarcn.show"),
                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.showWindow() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.store.refresh(); self?.builtin.updateAvailability() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.store.refresh(); self?.store.startAutomaticBrightness(); self?.builtin.updateAvailability() }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.store.stopAutomaticBrightness() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                         object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.store.refresh(); self?.store.startAutomaticBrightness() }
        })
    }

    func applicationWillTerminate(_ notification: Notification) { store.stopAutomaticBrightness(); builtin.restoreOnQuit() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    @objc private func showWindow() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
enum LunarCNApp {
    @MainActor static func main() {
        signal(SIGPIPE, SIG_IGN)
        if CommandLine.arguments.contains("--self-test") {
            runSelfTests()
            return
        }
        if CommandLine.arguments.contains("--restore-display") {
            do {
                try BuiltinDisplayEngine.setEnabled(true, id: BuiltinDisplayEngine.builtinID())
                print("内置屏幕已恢复。")
            } catch {
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        let lockPath = FileManager.default.temporaryDirectory.appendingPathComponent("local.lunarcn.displaycontrol.lock").path
        let lock = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { fputs("无法创建应用运行锁。\n", stderr); exit(1) }
        defer { close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.lunarcn.show"), object: nil)
            NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.lunarcn.displaycontrol")
                .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })?
                .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}
