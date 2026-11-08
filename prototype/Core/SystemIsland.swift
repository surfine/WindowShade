// 系统灵動岛（PROLED XDR 触控 MacBook Pro，macOS 27）：这台机器的顶部归系统的岛。
//
// 系统自己也只有一处判断，而且就只有一句（macOS 27.0.1 dyld cache 里的 HealthKit）：
//
//   -[_HKBehavior currentDeviceSupportsDynamicIsland]:
//       adrp x0, "DeviceSupportsDynamicIsland"
//       bl   _MGCopyAnswer
//
// 所以这里问同一个来源：能问 MobileGestalt 就问，问不到就答“不知道”，不猜机型、不按屏幕形状推。
// 拍板第 18 / 38 条：只有系统真有岛的机器让位；旧刘海机照常画我们的岛。
//
// 纯逻辑 + 一次只读的 dlsym；不写设置、不碰窗口，可单测（tests/run-system-island-tests.sh）。

import CoreFoundation
import Foundation

/// 屏幕顶部正中那一段归谁：真刘海、系统的灵動岛、还是我们自己的隐形刘海。
enum SlotKind: Equatable {
    case notch
    case systemIsland
    case virtual
}

enum SystemIsland {
    enum Answer: String, Sendable {
        /// 系统有灵動岛：顶部那段不归我们，面板不画、不接窗口。
        case present
        /// 没有（旧刘海机、外接屏、桌面 Mac）。
        case absent
        /// 问不到：按“没有”走，但记下来，探针里能看见。
        case unknown
    }

    /// 系统给的原始读数：1 有、0 没有、其它问不到。开进程时问一次，之后不再问。
    static let raw: Int = readGestalt()

    /// 真机复核用的开关（`defaults write` 或探针里设）：`on` / `off`，其余一律听系统的。
    /// 11-06 之后真机上对一次，把结果写进机型表就能把它去掉。
    enum Override {
        static let key = "Notch.systemIsland"
    }

    static var answer: Answer {
        resolve(raw: raw, override: UserDefaults.standard.string(forKey: Override.key))
    }

    static var present: Bool { answer == .present }

    /// 纯函数：原始读数 ＋ 复核开关 → 结论。开关只认明确的 on/off，写错的照样听系统的。
    static func resolve(raw: Int, override: String?) -> Answer {
        switch override?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "on", "yes", "true", "1": return .present
        case "off", "no", "false", "0": return .absent
        default: break
        }
        switch raw {
        case 1: return .present
        case 0: return .absent
        default: return .unknown
        }
    }

    /// 纯函数：顶部这段归谁。只有“机器有岛 + 这块屏是内建屏”才让给系统；外接屏照旧。
    static func slotKind(systemIsland: Bool, builtIn: Bool, hasNotch: Bool) -> SlotKind {
        if systemIsland && builtIn { return .systemIsland }
        return hasNotch ? .notch : .virtual
    }

    /// 问 MobileGestalt。读不到就看不出错误：返回 -1，让上层当“没有”。
    private static func readGestalt() -> Int {
        guard let handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY),
              let symbol = dlsym(handle, "MGCopyAnswer") else { return -1 }
        typealias CopyAnswer = @convention(c) (UnsafeRawPointer) -> UnsafeRawPointer?
        let copy = unsafeBitCast(symbol, to: CopyAnswer.self)
        let key = "DeviceSupportsDynamicIsland" as CFString
        guard let raw = copy(Unmanaged.passUnretained(key).toOpaque()) else { return -1 }
        // MGCopyAnswer 返回 +1，交给 ARC 收。
        let value = Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue()
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue(unsafeDowncast(value, to: CFBoolean.self)) ? 1 : 0
        }
        if CFGetTypeID(value) == CFNumberGetTypeID() {
            var number: Int32 = 0
            if CFNumberGetValue(unsafeDowncast(value, to: CFNumber.self), .intType, &number) {
                return number != 0 ? 1 : 0
            }
        }
        return -1
    }
}
