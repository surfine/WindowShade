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

    static func isActive(in windows: [[String: Any]]) -> Bool {
        windows.contains { ($0[kCGWindowName as String] as? String) == shieldName }
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
