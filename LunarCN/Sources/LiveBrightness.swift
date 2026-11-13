import Foundation

struct LiveBrightnessRequest {
    let screen: ScreenIdentity
    let percent: Double

    init(screen: ScreenIdentity, percent: Double, range: BrightnessRange) throws {
        guard range.contains(percent) else { throw ControlError.message("目标亮度超出已保存范围。") }
        self.screen = screen
        self.percent = percent
    }
}

struct LiveBrightnessBuffer {
    private var pending: [LiveBrightnessRequest] = []
    var first: LiveBrightnessRequest? { pending.first }

    mutating func submit(_ request: LiveBrightnessRequest) {
        remove(uuid: request.screen.uuid)
        pending.append(request)
    }

    mutating func take() -> LiveBrightnessRequest? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    func contains(uuid: String) -> Bool { pending.contains { $0.screen.uuid == uuid } }
    mutating func remove(uuid: String) { pending.removeAll { $0.screen.uuid == uuid } }
}

enum LiveBrightnessEngine {
    static func apply(_ request: LiveBrightnessRequest, run: DisplayControlRun,
                      read: (ScreenIdentity) throws -> ControlLevel = { try DisplayControl.read($0, control: 16) },
                      write: (ScreenIdentity, Double, ControlLevel) throws -> ControlLevel = { try DisplayControl.set($0, control: 16, percent: $1, level: $2) }) throws -> ControlLevel {
        try run.check()
        let actual = try read(request.screen)
        try run.check()
        if try actual.rawValue(for: request.percent) == actual.current { return actual }
        return try write(request.screen, request.percent, actual)
    }
}
