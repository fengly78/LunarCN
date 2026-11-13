import CoreGraphics
import ColorSync
import Foundation
import IOKit

enum BuiltinDisplayError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case let .message(text): return text } }
}

enum BuiltinDisplayEngine {
    // shortcut: SkyLight is a private API, recheck these signatures after macOS updates.
    private static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
    private typealias List = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32
    private typealias Configure = @convention(c) (CGDisplayConfigRef?, UInt32, Bool) -> Int32
    private typealias DisplayInfo = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?

    private static func symbol(_ name: String, fallback: String) throws -> UnsafeMutableRawPointer {
        guard let skyLight, let pointer = dlsym(skyLight, name) ?? dlsym(skyLight, fallback) else {
            throw BuiltinDisplayError.message("当前 macOS 未提供所需的屏幕关闭接口。")
        }
        return pointer
    }

    static func builtinID() throws -> UInt32 {
        let list = unsafeBitCast(try symbol("SLSGetDisplayList", fallback: "CGSGetDisplayList"), to: List.self)
        var count: UInt32 = 0
        guard list(0, nil, &count) == 0, count > 0, count <= 128 else {
            throw BuiltinDisplayError.message("无法读取完整显示器列表。")
        }
        var ids = [UInt32](repeating: 0, count: Int(count))
        let capacity = count
        guard list(capacity, &ids, &count) == 0, count <= capacity,
              let builtin = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
            throw BuiltinDisplayError.message("没有检测到笔记本内置屏幕。")
        }
        return builtin
    }

    static func uuid(_ id: UInt32) -> String? {
        guard let value = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, value) as String
    }

    static func visibleExternalIDs() -> [UInt32] {
        guard let coreDisplay, let symbol = dlsym(coreDisplay, "CoreDisplay_DisplayCreateInfoDictionary") else { return [] }
        let info = unsafeBitCast(symbol, to: DisplayInfo.self)
        var ids = [UInt32](repeating: 0, count: 128)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(128, &ids, &count) == .success, count <= 128 else { return [] }
        return ids.prefix(Int(count)).filter { id in
            guard CGDisplayIsBuiltin(id) == 0, CGDisplayIsAsleep(id) == 0,
                  let dictionary = info(id)?.takeRetainedValue() as? [String: Any],
                  dictionary["kCGDisplayIsVirtualDevice"] as? Bool != true,
                  dictionary["kCGDisplayIsAirPlay"] as? Bool != true,
                  let location = dictionary["IODisplayLocation"] as? String else { return false }
            let service = IORegistryEntryCopyFromPath(kIOMainPortDefault, location as CFString)
            guard service != MACH_PORT_NULL else { return false }
            IOObjectRelease(service)
            return true
        }
    }

    static func setEnabled(_ enabled: Bool, id: UInt32) throws {
        guard CGDisplayIsBuiltin(id) != 0 else { throw BuiltinDisplayError.message("目标不是笔记本内置屏幕。") }
        if !enabled && visibleExternalIDs().isEmpty {
            throw BuiltinDisplayError.message("请先连接并开启一台实体外接显示器。")
        }
        if (CGDisplayIsActive(id) != 0) == enabled { return }
        let configure = unsafeBitCast(try symbol("SLSConfigureDisplayEnabled", fallback: "CGSConfigureDisplayEnabled"), to: Configure.self)
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            throw BuiltinDisplayError.message("无法开始屏幕配置。")
        }
        let result = configure(config, id, enabled)
        guard result == 0 else {
            CGCancelDisplayConfiguration(config)
            throw BuiltinDisplayError.message("系统拒绝更改内置屏幕状态（\(result)）。")
        }
        let committed = CGCompleteDisplayConfiguration(config, .forSession)
        guard committed == .success else {
            throw BuiltinDisplayError.message("屏幕配置未生效（\(committed.rawValue)）。")
        }
        for _ in 0..<30 {
            if (CGDisplayIsActive(id) != 0) == enabled { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw BuiltinDisplayError.message("系统未确认内置屏幕状态，请点击恢复或重新打开屏幕。")
    }
}

enum ScreenRecoveryPolicy {
    static func shouldRestore(parentConnected: Bool, externalAvailable: Bool, confirmed: Bool, expired: Bool) -> Bool {
        !parentConnected || !externalAvailable || (!confirmed && expired)
    }
}
