import Foundation

struct BrightnessRange: Codable, Equatable {
    let minimum: Int
    let maximum: Int
    static let full = try! BrightnessRange(minimum: 0, maximum: 100)

    init(minimum: Int, maximum: Int) throws {
        guard (0...99).contains(minimum), (1...100).contains(maximum), minimum < maximum else {
            throw ControlError.message("亮度下限必须小于上限，并处于 0% 到 100% 之间。")
        }
        self.minimum = minimum
        self.maximum = maximum
    }

    private enum CodingKeys: String, CodingKey { case minimum, maximum }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(minimum: values.decode(Int.self, forKey: .minimum), maximum: values.decode(Int.self, forKey: .maximum))
    }

    func contains(_ percent: Double) -> Bool {
        percent.isFinite && (Double(minimum)...Double(maximum)).contains(percent)
    }

    func clamped(_ percent: Double) -> Double { min(Double(maximum), max(Double(minimum), percent)) }
}

struct ScreenPreset: Codable, Equatable {
    let brightness: Double?
    let contrast: Double?
    let volume: Double?
    let muted: Bool?

    init(brightness: Double?, contrast: Double?, volume: Double?, muted: Bool?) throws {
        guard [brightness, contrast, volume].compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...100).contains($0) }),
              brightness != nil || contrast != nil || volume != nil || muted != nil else {
            throw ControlError.message("没有可保存的有效显示器设置。")
        }
        self.brightness = brightness
        self.contrast = contrast
        self.volume = volume
        self.muted = muted
    }

    private enum CodingKeys: String, CodingKey { case brightness, contrast, volume, muted }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(brightness: values.decodeIfPresent(Double.self, forKey: .brightness),
                      contrast: values.decodeIfPresent(Double.self, forKey: .contrast),
                      volume: values.decodeIfPresent(Double.self, forKey: .volume),
                      muted: values.decodeIfPresent(Bool.self, forKey: .muted))
    }
}

struct ScreenSettings: Codable {
    var range: BrightnessRange = .full
    var preset: ScreenPreset?
    var followBuiltin = false

    private enum CodingKeys: String, CodingKey { case range, preset, followBuiltin }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        range = try values.decode(BrightnessRange.self, forKey: .range)
        preset = try values.decodeIfPresent(ScreenPreset.self, forKey: .preset)
        followBuiltin = try values.decodeIfPresent(Bool.self, forKey: .followBuiltin) ?? false
    }
}

final class PreferencesStore {
    static let key = "screenSettings.v1"
    let loadError: String?
    private let defaults: UserDefaults
    private var settings: [String: ScreenSettings]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            if let stored = defaults.object(forKey: Self.key) {
                guard let data = stored as? Data else { throw ControlError.message("设置记录类型无效。") }
                settings = try JSONDecoder().decode([String: ScreenSettings].self, from: data)
            } else { settings = [:] }
            loadError = nil
        } catch {
            settings = [:]
            loadError = "已保存设置无法读取，原记录已保留；本次使用默认范围。"
        }
    }

    func settings(for uuid: String) -> ScreenSettings { settings[uuid] ?? ScreenSettings() }

    func saveRange(_ range: BrightnessRange, for uuid: String) throws {
        var value = settings(for: uuid)
        value.range = range
        try save(value, for: uuid)
    }

    func savePreset(_ preset: ScreenPreset, for uuid: String) throws {
        var value = settings(for: uuid)
        value.preset = preset
        try save(value, for: uuid)
    }

    func saveFollowBuiltin(_ enabled: Bool, for uuid: String) throws {
        var value = settings(for: uuid)
        value.followBuiltin = enabled
        try save(value, for: uuid)
    }

    private func save(_ value: ScreenSettings, for uuid: String) throws {
        guard loadError == nil else { throw ControlError.message("原设置记录无法读取，为避免覆盖数据，本次没有保存。") }
        var updated = settings
        updated[uuid] = value
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: Self.key)
        settings = updated
    }
}
