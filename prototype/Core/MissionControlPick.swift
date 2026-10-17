// 调度中心打开时的判断与目标挑选（纯查询，不碰窗口）。
//
// 调度中心打开时，WindowManager 会铺一层全屏的 ExposeShieldWindow；关掉就没了。
// 这时系统并没有把 ⌘W 交给谁，所以要在这一层上认出"指针指着的那扇窗"，
// 才能把 ⌘W 送到对的地方（见 App/MissionControlKeys.swift）。
//
// 坐标和 CGWindowList 一致：左上角为原点、y 向下。

import CoreGraphics
import Foundation

/// 指针底下那一扇：谁、哪一扇、在哪儿。
struct MissionControlTarget: Equatable {
    let pid: pid_t
    let windowID: CGWindowID
    let frame: CGRect
}

enum MissionControlPick {
    /// 调度中心打开时 WindowManager 铺的那层窗口的名字。
    static let shieldName = "ExposeShieldWindow"

    /// 系统自己的层：Dock、调度中心、通知中心、菜单栏。
    static let ignoredOwners: Set<String> = [
        "Dock", "WindowManager", "Window Server", "通知中心", "Notification Center",
    ]

    /// 认出调度中心靠的是哪一条线索。名字对得上最可靠；其余是系统换了窗口名之后的备援。
    enum Detection: String, Equatable {
        /// 窗口名正好是 ExposeShieldWindow（macOS 15/26 实测）。
        case shieldName
        /// Dock 或 WindowManager 名下、名字里带 expose／missioncontrol 的窗口（改名但沿用前缀）。
        case nameVariant
        /// WindowManager 名下、盖满一块屏、层级不低于遮罩层的无名窗口。
        case fullScreenSystemLayer
    }

    /// 备援里"遮罩层"的最低层级：测量到的 ExposeShieldWindow 在 19，留一点余量，普通窗口与 Dock 条（20 以上也不会盖满屏）都不在内。
    static let shieldMinLayer = 18

    static func isActive(in windows: [[String: Any]], screens: [CGRect]? = nil) -> Bool {
        detection(in: windows, screens: screens) != nil
    }

    /// nil＝没开。只有 `.shieldName` 是确证；备援命中时调用方要更保守（见 MissionControlKeys）。
    static func detection(in windows: [[String: Any]], screens: [CGRect]? = nil) -> Detection? {
        if windows.contains(where: { ($0[kCGWindowName as String] as? String) == shieldName }) {
            return .shieldName
        }
        var displayRects = screens
        for info in windows {
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "WindowManager" || owner == "Dock" else { continue }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer >= shieldMinLayer else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { continue }
            let name = (info[kCGWindowName as String] as? String ?? "").lowercased()
            if name.contains("expose") || name.contains("missioncontrol") { return .nameVariant }
            // 无名的整屏窗口只信 WindowManager：Dock 名下的整屏层还可能是别的东西（启动台之类）。
            guard owner == "WindowManager", name.isEmpty, let bounds = windowBounds(info) else { continue }
            if displayRects == nil { displayRects = activeDisplayBounds() }
            if displayRects?.contains(where: { bounds.width >= $0.width - 1 && bounds.height >= $0.height - 1 }) == true {
                return .fullScreenSystemLayer
            }
        }
        return nil
    }

    /// 各块屏在 CGWindowList 坐标（左上角为原点）里的外框。
    static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    /// 一行诊断：认为调度中心开着却挑不到目标时写进日志，看得出是哪条线索、窗口表里有什么。
    static func diagnostic(at point: CGPoint, in windows: [[String: Any]], detection: Detection) -> String {
        let normal = windows.filter { ((($0[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0) == 0) }
        let system = windows.compactMap { info -> String? in
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "WindowManager" || owner == "Dock" else { return nil }
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let name = info[kCGWindowName as String] as? String ?? ""
            return "\(owner)/\(name.isEmpty ? "-" : name)/L\(layer)"
        }
        return "mc-keys: no target; rule=\(detection.rawValue) pointer=(\(Int(point.x)),\(Int(point.y))) "
            + "windows=\(windows.count) layer0=\(normal.count) system=[\(system.prefix(6).joined(separator: ","))]"
    }

    /// 窗口表是前后顺序（0 在最前）。只要普通层、看得见、不属于系统、指针落在里面的第一扇。
    /// 自己的窗口不算，别人的一份都不动。
    static func target(at point: CGPoint, in windows: [[String: Any]],
                       ownPID: pid_t = getpid()) -> MissionControlTarget? {
        for info in windows {
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer == 0 else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.01 else { continue }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            guard !ignoredOwners.contains(owner) else { continue }
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pid_t(pidNumber.int32Value)
            guard pid != ownPID, pid > 0 else { continue }
            guard let idNumber = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = windowBounds(info), bounds.contains(point) else { continue }
            return MissionControlTarget(pid: pid, windowID: CGWindowID(idNumber.uint32Value),
                                        frame: bounds)
        }
        return nil
    }

    /// 和 Window/AXWindow.swift 的 cgWindowBounds 同一件事；这里不引用 AppKit，方便单测。
    static func windowBounds(_ info: [String: Any]) -> CGRect? {
        guard let raw = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        var rect = CGRect.zero
        return CGRectMakeWithDictionaryRepresentation(raw, &rect) ? rect : nil
    }
}
