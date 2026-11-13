import Foundation

@MainActor func runSelfTests() {
    do {
        BuiltinDisplayController.runRecoverySelfTests()
        precondition(!ScreenRecoveryPolicy.shouldRestore(parentConnected: true, externalAvailable: true, confirmed: false, expired: false))
        precondition(ScreenRecoveryPolicy.shouldRestore(parentConnected: true, externalAvailable: true, confirmed: false, expired: true))
        precondition(!ScreenRecoveryPolicy.shouldRestore(parentConnected: true, externalAvailable: true, confirmed: true, expired: true))
        precondition(ScreenRecoveryPolicy.shouldRestore(parentConnected: false, externalAvailable: true, confirmed: true, expired: false))
        precondition(ScreenRecoveryPolicy.shouldRestore(parentConnected: true, externalAvailable: false, confirmed: true, expired: false))
        let level = try ControlLevel(current: 128, maximum: 300)
        precondition(abs(level.percent - 42.6666667) < 0.001)
        precondition((try? level.rawValue(for: 0)) == 0)
        precondition((try? level.rawValue(for: 50)) == 150)
        precondition((try? level.rawValue(for: 100)) == 300)
        for percent in [-1.0, 101, .nan, .infinity] {
            precondition((try? level.rawValue(for: percent)) == nil)
        }
        for json in [#"{"current":0,"maximum":0}"#, #"{"current":301,"maximum":300}"#,
                     #"{"current":-1,"maximum":100}"#, #"{"current":1,"maximum":65536}"#] {
            precondition((try? JSONDecoder().decode(ControlLevel.self, from: Data(json.utf8))) == nil)
        }
        let valid = try JSONDecoder().decode(ControlLevel.self, from: Data(#"{"current":128,"maximum":300}"#.utf8))
        precondition(valid == level)
        let muteOn = try JSONDecoder().decode(MuteState.self, from: Data(#"{"current":1,"maximum":0}"#.utf8))
        let muteOff = try JSONDecoder().decode(MuteState.self, from: Data(#"{"current":2,"maximum":0}"#.utf8))
        precondition(muteOn.muted && !muteOff.muted)
        precondition((try? JSONDecoder().decode(MuteState.self, from: Data(#"{"current":0,"maximum":0}"#.utf8))) == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let range = try BrightnessRange(minimum: 10, maximum: 90)
        precondition(range.contains(10) && range.contains(90) && !range.contains(9) && !range.contains(.nan))
        precondition(range.clamped(100) == 90 && range.clamped(0) == 10)
        precondition((try? BrightnessRange(minimum: 80, maximum: 20)) == nil)
        precondition((try? JSONDecoder().decode(BrightnessRange.self, from: Data(#"{"minimum":100,"maximum":100}"#.utf8))) == nil)
        precondition((try? ScreenPreset(brightness: .nan, contrast: nil, volume: nil, muted: nil)) == nil)
        precondition((try? ScreenPreset(brightness: nil, contrast: nil, volume: nil, muted: nil)) == nil)
        let suite = "local.lunarcn.self-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        try preferences.saveRange(range, for: "screen-a")
        let preset = try ScreenPreset(brightness: 25, contrast: 50, volume: nil, muted: nil)
        try preferences.savePreset(preset, for: "screen-a")
        let reloaded = PreferencesStore(defaults: defaults)
        precondition(reloaded.settings(for: "screen-a").range == range)
        precondition(reloaded.settings(for: "screen-a").preset == preset)
        precondition(reloaded.settings(for: "screen-b").range == .full)
        precondition(!reloaded.settings(for: "screen-a").followBuiltin)
        try preferences.saveFollowBuiltin(true, for: "screen-a")
        let enabled = PreferencesStore(defaults: defaults)
        precondition(enabled.settings(for: "screen-a").followBuiltin)
        precondition(!enabled.settings(for: "screen-b").followBuiltin)
        precondition(enabled.settings(for: "screen-a").preset == preset)
        let oldSettings = try JSONDecoder().decode(ScreenSettings.self, from: Data(#"{"range":{"minimum":10,"maximum":90},"preset":{"brightness":25}}"#.utf8))
        precondition(!oldSettings.followBuiltin && oldSettings.range == range && oldSettings.preset?.brightness == 25)
        try preferences.saveFollowBuiltin(false, for: "screen-a")
        precondition(!PreferencesStore(defaults: defaults).settings(for: "screen-a").followBuiltin)
        try runAutomaticBrightnessTests()
        try runLiveBrightnessTests()
        let corrupt = Data("invalid-json".utf8)
        defaults.set(corrupt, forKey: PreferencesStore.key)
        let damaged = PreferencesStore(defaults: defaults)
        precondition(damaged.loadError != nil)
        do {
            try damaged.saveRange(.full, for: "screen-a")
            preconditionFailure("Unreadable settings must not be overwritten")
        } catch { precondition(defaults.data(forKey: PreferencesStore.key) == corrupt) }
        defaults.set("invalid-type", forKey: PreferencesStore.key)
        let wrongType = PreferencesStore(defaults: defaults)
        precondition(wrongType.loadError != nil)
        do {
            try wrongType.savePreset(preset, for: "screen-a")
            preconditionFailure("Invalid settings types must not be overwritten")
        } catch { precondition(defaults.string(forKey: PreferencesStore.key) == "invalid-type") }
        let fixture = directory.appendingPathComponent("helper")
        try "#!/bin/sh\n[ \"$1\" = read ] || exit 1\nprintf '{\"current\":128,\"maximum\":300}\\n'\n".write(to: fixture, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.path)
        let result = try DisplayControl.helper(["read"], executable: fixture)
        let decoded = try JSONDecoder().decode(ControlLevel.self, from: result)
        precondition(decoded == level)
        do {
            _ = try DisplayControl.helper(["invalid"], executable: fixture)
            preconditionFailure("A failed helper must not report success")
        } catch {}
        try "#!/bin/sh\nprintf 'Unconfirmed device value\\n' >&2\nexit 2\n".write(to: fixture, atomically: true, encoding: .utf8)
        do {
            _ = try DisplayControl.helper([], executable: fixture)
            preconditionFailure("An unconfirmed write must be distinguished from success")
        } catch ControlError.writeUnconfirmed { }
        try "#!/bin/sh\nexec /bin/sleep 10\n".write(to: fixture, atomically: true, encoding: .utf8)
        let start = Date()
        do {
            _ = try DisplayControl.helper([], executable: fixture, timeout: 0.05)
            preconditionFailure("A stalled helper must time out")
        } catch { precondition(Date().timeIntervalSince(start) < 3) }
        let protocolResult = try DisplayControl.helper(["--self-test"])
        precondition(String(decoding: protocolResult, as: UTF8.self).contains("passed"))
        print("LunarCN self-tests passed: live brightness coalescing, final value, cancellation, automatic brightness, persistence migration, presets, corruption protection, ranges, recovery, mute, helper errors, timeout, DDC protocol")
    } catch {
        fputs("Self-test failed: \(error)\n", stderr)
        exit(1)
    }
}

private func runLiveBrightnessTests() throws {
    let screen = ScreenIdentity(id: 2, uuid: "live-a", name: "fixture", builtin: false)
    let other = ScreenIdentity(id: 3, uuid: "live-b", name: "fixture-b", builtin: false)
    func request(_ percent: Double, _ target: ScreenIdentity? = nil) throws -> LiveBrightnessRequest {
        try LiveBrightnessRequest(screen: target ?? screen, percent: percent, range: .full)
    }
    for invalid in [-1.0, 101, .nan, .infinity] {
        precondition((try? request(invalid)) == nil)
    }
    precondition((try? LiveBrightnessRequest(screen: screen, percent: 9, range: BrightnessRange(minimum: 10, maximum: 90))) == nil)
    var buffer = LiveBrightnessBuffer()
    buffer.submit(try request(20))
    let inFlight = buffer.take()!
    for value in 0..<10000 { buffer.submit(try request(Double(value % 101))) }
    precondition(inFlight.percent == 20)
    precondition(buffer.take()?.percent == Double(9999 % 101))
    precondition(buffer.take() == nil)
    buffer.submit(try request(20))
    buffer.submit(try request(30, other))
    buffer.submit(try request(40))
    precondition(buffer.take()?.screen.uuid == other.uuid)
    precondition(buffer.take()?.percent == 40)
    precondition(buffer.take() == nil)
    buffer.submit(try request(70))
    buffer.remove(uuid: screen.uuid)
    precondition(buffer.take() == nil)

    var actual = try ControlLevel(current: 100, maximum: 200)
    var writes: [Double] = []
    let read: (ScreenIdentity) throws -> ControlLevel = { _ in actual }
    let write: (ScreenIdentity, Double, ControlLevel) throws -> ControlLevel = { target, percent, level in
        precondition(target.uuid == screen.uuid && level.maximum == 200)
        writes.append(percent)
        actual = try ControlLevel(current: level.rawValue(for: percent), maximum: level.maximum)
        return actual
    }
    let applied = try LiveBrightnessEngine.apply(request(70), run: DisplayControlRun(), read: read, write: write)
    precondition(applied.current == 140 && writes == [70])
    _ = try LiveBrightnessEngine.apply(request(70.1), run: DisplayControlRun(), read: read, write: write)
    precondition(writes == [70])
    // Reversing a drag to its initial value must still follow an in-flight change.
    buffer.submit(try request(50))
    buffer.submit(try request(70))
    buffer.submit(try request(50))
    _ = try LiveBrightnessEngine.apply(buffer.take()!, run: DisplayControlRun(), read: read, write: write)
    precondition(actual.percent == 50 && writes == [70, 50])

    let cancelled = DisplayControlRun()
    cancelled.cancel()
    var reads = 0
    do {
        _ = try LiveBrightnessEngine.apply(request(80), run: cancelled, read: { _ in reads += 1; return actual }, write: write)
        preconditionFailure("Cancelled work must not run")
    } catch is CancellationError { precondition(reads == 0) }
    let cancelAfterRead = DisplayControlRun()
    do {
        _ = try LiveBrightnessEngine.apply(request(80), run: cancelAfterRead, read: { _ in cancelAfterRead.cancel(); return actual }, write: write)
        preconditionFailure("Cancellation after reading must stop the write")
    } catch is CancellationError { precondition(writes == [70, 50]) }
    do {
        _ = try LiveBrightnessEngine.apply(request(80), run: DisplayControlRun(), read: { _ in throw ControlError.message("disconnected") }, write: write)
        preconditionFailure("Disconnected devices must not be written")
    } catch { precondition(writes == [70, 50]) }
    var attempts = 0
    do {
        _ = try LiveBrightnessEngine.apply(request(80), run: DisplayControlRun(), read: read, write: { _, _, _ in
            attempts += 1
            throw ControlError.writeUnconfirmed("fixture")
        })
        preconditionFailure("Unconfirmed writes must fail")
    } catch ControlError.writeUnconfirmed { precondition(attempts == 1) }
}

private func runAutomaticBrightnessTests() throws {
    func expect(_ value: Bool) { precondition(value) }
    let range = try BrightnessRange(minimum: 10, maximum: 90)
    let current = try ControlLevel(current: 50, maximum: 100)
    expect(try AutomaticBrightnessPolicy.target(source: 80, current: current, range: range) == 55)
    expect(try AutomaticBrightnessPolicy.target(source: 20, current: current, range: range) == 45)
    expect(try AutomaticBrightnessPolicy.target(source: 51, current: current, range: range) == nil)
    expect(try AutomaticBrightnessPolicy.target(source: 0, current: ControlLevel(current: 0, maximum: 100), range: range) == 10)
    expect(try AutomaticBrightnessPolicy.target(source: 100, current: ControlLevel(current: 100, maximum: 100), range: range) == 90)
    expect(try AutomaticBrightnessPolicy.target(source: 100, current: ControlLevel(current: 90, maximum: 100), range: range) == nil)
    expect(try AutomaticBrightnessPolicy.target(source: 100, current: ControlLevel(current: 8, maximum: 10), range: .full) == 85)
    precondition((try? AutomaticBrightnessPolicy.target(source: .nan, current: current, range: range)) == nil)
    precondition((try? AutomaticBrightnessPolicy.target(source: -1, current: current, range: range)) == nil)

    let source = ScreenIdentity(id: 1, uuid: "source", name: "source", builtin: true)
    let external = ScreenIdentity(id: 2, uuid: "target", name: "target", builtin: false)
    var target = ScreenState(screen: external)
    target.followBuiltin = true
    var device = current
    var writes: [Double] = []
    let read: (ScreenIdentity) throws -> ControlLevel = { $0.builtin ? try ControlLevel(current: 80, maximum: 100) : device }
    let write: (ScreenIdentity, Double, ControlLevel) throws -> Void = { screen, value, level in
        precondition(screen.uuid == external.uuid)
        writes.append(value)
        device = try ControlLevel(current: level.rawValue(for: value), maximum: level.maximum)
    }
    let (sampled, updates) = try AutomaticBrightnessEngine.sample(source: source, targets: [target], run: DisplayControlRun(), read: read, write: write, checkSource: { _ in })
    precondition(sampled.percent == 80 && writes == [55])
    expect(try updates[0].result.get().current == 55)

    writes = []
    let cancelled = DisplayControlRun()
    _ = try? AutomaticBrightnessEngine.sample(source: source, targets: [target], run: cancelled, read: { screen in
        if !screen.builtin { cancelled.cancel() }
        return try read(screen)
    }, write: write, checkSource: { _ in })
    precondition(writes.isEmpty)
    _ = try? AutomaticBrightnessEngine.sample(source: source, targets: [target], run: DisplayControlRun(), read: read, write: write, checkSource: { _ in throw ControlError.message("source asleep") })
    precondition(writes.isEmpty)
    var sourceChecks = 0
    _ = try? AutomaticBrightnessEngine.sample(source: source, targets: [target], run: DisplayControlRun(), read: read, write: write, checkSource: { _ in
        sourceChecks += 1
        if sourceChecks == 3 { throw ControlError.message("source disconnected before write") }
    })
    precondition(writes.isEmpty)
    target.followBuiltin = false
    _ = try AutomaticBrightnessEngine.sample(source: source, targets: [target], run: DisplayControlRun(), read: read, write: write, checkSource: { _ in })
    precondition(writes.isEmpty)
    target.followBuiltin = true
    target.readOnlyControls = [16]
    _ = try AutomaticBrightnessEngine.sample(source: source, targets: [target], run: DisplayControlRun(), read: read, write: write, checkSource: { _ in })
    precondition(writes.isEmpty)
    target.readOnlyControls = []
    let (_, failed) = try AutomaticBrightnessEngine.sample(source: source, targets: [target], run: DisplayControlRun(), read: read, write: { _, _, _ in throw ControlError.writeUnconfirmed("fixture") }, checkSource: { _ in })
    guard case .failure = failed[0].result else { preconditionFailure("Unconfirmed writes must fail") }
    var second = ScreenState(screen: ScreenIdentity(id: 3, uuid: "second", name: "second", builtin: false))
    second.followBuiltin = true
    let cancelAfterWrite = DisplayControlRun()
    var writeCount = 0
    _ = try? AutomaticBrightnessEngine.sample(source: source, targets: [target, second], run: cancelAfterWrite, read: read, write: { _, _, _ in
        writeCount += 1
        cancelAfterWrite.cancel()
    }, checkSource: { _ in })
    precondition(writeCount == 1)
}
