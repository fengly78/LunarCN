import Foundation
import CoreGraphics

enum AutomaticBrightnessPolicy {
    static func target(source: Double, current: ControlLevel, range: BrightnessRange) throws -> Double? {
        guard source.isFinite, (0...100).contains(source) else { throw ControlError.message("内建屏亮度读数无效，已暂停跟随。") }
        let desired = range.clamped(source)
        if range.contains(current.percent), abs(desired - current.percent) < 1.5 { return nil }
        let step = max(-5, min(5, desired - current.percent))
        let next = range.clamped(current.percent + step)
        guard try current.rawValue(for: next) != current.current else { return nil }
        return next
    }
}

// A setting change cancels queued work; a write already sent to the device may finish.
final class DisplayControlRun: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock()
        let value = cancelled
        lock.unlock()
        if value { throw CancellationError() }
    }
}

struct AutomaticBrightnessUpdate {
    let screen: ScreenIdentity
    let result: Result<ControlLevel, Error>
}

enum AutomaticBrightnessEngine {
    static func checkSource(_ screen: ScreenIdentity) throws {
        try screen.checkConnected()
        guard screen.builtin, CGDisplayIsActive(screen.id) != 0, CGDisplayIsAsleep(screen.id) == 0 else {
            throw ControlError.message("内建屏已关闭或休眠，自动亮度已暂停；外接屏保持当前亮度。")
        }
    }

    static func sample(source: ScreenIdentity, targets: [ScreenState], run: DisplayControlRun,
                       read: (ScreenIdentity) throws -> ControlLevel = { try DisplayControl.read($0, control: 16) },
                       write: (ScreenIdentity, Double, ControlLevel) throws -> Void = { _ = try DisplayControl.set($0, control: 16, percent: $1, level: $2) },
                       checkSource: (ScreenIdentity) throws -> Void = Self.checkSource) throws -> (ControlLevel, [AutomaticBrightnessUpdate]) {
        try run.check()
        try checkSource(source)
        let sourceLevel = try read(source)
        var updates: [AutomaticBrightnessUpdate] = []
        for target in targets where !target.screen.builtin && target.followBuiltin && !target.readOnlyControls.contains(16) {
            try run.check()
            try checkSource(source)
            let actual: ControlLevel
            let value: Double?
            do {
                actual = try read(target.screen)
                value = try AutomaticBrightnessPolicy.target(source: sourceLevel.percent, current: actual, range: target.range)
            } catch {
                updates.append(AutomaticBrightnessUpdate(screen: target.screen, result: .failure(error)))
                continue
            }
            try run.check()
            try checkSource(source)
            do {
                if let value {
                    try write(target.screen, value, actual)
                    updates.append(AutomaticBrightnessUpdate(screen: target.screen, result: .success(try read(target.screen))))
                } else {
                    updates.append(AutomaticBrightnessUpdate(screen: target.screen, result: .success(actual)))
                }
            } catch is CancellationError { throw CancellationError() }
            catch { updates.append(AutomaticBrightnessUpdate(screen: target.screen, result: .failure(error))) }
        }
        return (sourceLevel, updates)
    }
}
