// 别的桌面上的窗口（docs/direction.md「回到窗口」第 1 步）：刘海里那一排把它们也列出来，
// 停在一格上就从那张桌面实时抓画面、在原处给你看一眼；点一下才过去。为一张桌面一个 App、靠切桌面的人（Marvin）做。
//
// 纯逻辑：输入是窗口列表（前后次序，最前的在前）、每扇窗所在的桌面、每块屏的桌面次序和当前桌面；
// 输出是要放进刘海的那几扇，和每扇写什么（“桌面 3”或“全屏”）。不碰私有接口、不碰界面。

import CoreGraphics
import Foundation

/// 一块屏（或“显示器具有单独的空间”关掉时的所有屏）上的桌面，按调度中心里从左到右的次序。
struct DesktopRow: Equatable, Sendable {
    struct Space: Equatable, Sendable {
        let id: UInt64
        /// 全屏 App 自己的那张桌面（调度中心里显示 App 名字，不编号）。
        let isFullScreen: Bool
    }
    let spaces: [Space]
    /// 这块屏此刻正显示的桌面。
    let current: UInt64
}

/// 窗口列表里的一扇（只取判断要用的几样）。
struct ElsewhereCandidate: Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    let layer: Int
    let bounds: CGRect
    let alpha: Double
    let isOnScreen: Bool
    /// 它所在的桌面（私有接口读到的）；最小化的窗口没有桌面。
    let spaces: [UInt64]
}

struct ElsewhereWindow: Equatable, Sendable {
    enum Place: Equatable, Sendable {
        /// 这块屏上的第几张普通桌面（从 1 数，和调度中心一致）。
        case desktop(Int)
        case fullScreen
    }
    let id: CGWindowID
    let pid: pid_t
    let place: Place
    /// 窗口的位置和大小（窗口列表的坐标：左上角为原点）。
    let bounds: CGRect
}

enum ElsewhereWindows {
    /// 太小的不算窗口（工具条、浮动面板）。
    static let minimumSize = CGSize(width: 120, height: 80)
    /// 刘海那一排最多 8 格，别的桌面上的最多占 6 格；同一个 App 最多 3 扇，免得一个浏览器占满。
    static let limit = 6
    static let perApp = 3

    /// windows：窗口列表，最前的在前（就是最近用过的在前）。exclude：已经在那一排里的（收起的、侧拉的……）。
    static func plan(windows: [ElsewhereCandidate], desktops: [DesktopRow], exclude: Set<CGWindowID>,
                     ownPID: pid_t, limit: Int = limit, perApp: Int = perApp) -> [ElsewhereWindow] {
        let current = Set(desktops.map(\.current))
        // 每张桌面的叫法：普通桌面按它在这块屏上的次序编号，全屏桌面不编号。
        // 各屏有独立桌面时，调度中心（和“切换到桌面 N”那组快捷键、yabai 的 mission-control 序号）是跨屏连续编号的：
        // 内建屏两张，外接屏第一张就是“桌面 3”。所以计数不在每块屏重新开始。
        var places: [UInt64: ElsewhereWindow.Place] = [:]
        var number = 0
        for row in desktops {
            for space in row.spaces {
                if space.isFullScreen {
                    places[space.id] = .fullScreen
                } else {
                    number += 1
                    places[space.id] = .desktop(number)
                }
            }
        }
        var result: [ElsewhereWindow] = []
        var perAppCount: [pid_t: Int] = [:]
        var seen = Set<CGWindowID>()
        for window in windows {
            guard result.count < limit else { break }
            guard window.layer == 0, window.pid != ownPID, !exclude.contains(window.id), !seen.contains(window.id),
                  window.alpha > 0, !window.isOnScreen,
                  window.bounds.width >= minimumSize.width, window.bounds.height >= minimumSize.height,
                  !window.spaces.isEmpty,
                  // 在任何一块屏的当前桌面上（包括“在所有桌面上”的窗口）：看得见，不算别处。
                  window.spaces.allSatisfy({ !current.contains($0) }),
                  // 不认识的桌面（读到一半桌面变了）：宁可不放，也不写错“桌面几”。
                  let place = window.spaces.lazy.compactMap({ places[$0] }).first,
                  perAppCount[window.pid, default: 0] < perApp else { continue }
            seen.insert(window.id)
            perAppCount[window.pid, default: 0] += 1
            result.append(ElsewhereWindow(id: window.id, pid: window.pid, place: place, bounds: window.bounds))
        }
        return result
    }

    /// 看一眼的画面放在哪（Cocoa 坐标，左下角为原点）。window：窗口自己的位置和大小；visible：指着的那块屏去掉菜单栏
    /// 和程序坞的地方；screen：那块屏；tile：指着的那一格。
    /// - 窗口就在这块屏上：在它原来的位置、按原来的大小（放不下就等比缩小，中心不动、整张留在可用区域里）。
    /// - 在别的屏上：等比缩小，挂在那一格下面，最宽占可用区域的七成。
    static func cardFrame(window: CGRect, visible: CGRect, screen: CGRect, tile: CGRect) -> CGRect {
        guard window.width > 0, window.height > 0, visible.width > 0, visible.height > 0 else { return .zero }
        if screen.contains(CGPoint(x: window.midX, y: window.midY)) {
            let scale = min(1, visible.width / window.width, visible.height / window.height)
            let size = CGSize(width: floor(window.width * scale), height: floor(window.height * scale))
            let x = min(max(window.midX - size.width / 2, visible.minX), visible.maxX - size.width)
            let y = min(max(window.midY - size.height / 2, visible.minY), visible.maxY - size.height)
            return CGRect(origin: CGPoint(x: x, y: y), size: size)
        }
        let gap: CGFloat = 8
        let room = CGSize(width: visible.width * 0.72, height: min(tile.minY, visible.maxY) - gap - (visible.minY + 10))
        guard room.width > 0, room.height > 0 else { return .zero }
        let scale = min(1, room.width / window.width, room.height / window.height)
        let size = CGSize(width: floor(window.width * scale), height: floor(window.height * scale))
        let x = min(max(tile.midX - size.width / 2, visible.minX + 8), visible.maxX - 8 - size.width)
        return CGRect(x: x, y: min(tile.minY, visible.maxY) - gap - size.height, width: size.width, height: size.height)
    }

    /// 系统设置里“调度中心”的一组快捷键（往左 / 往右移动一个空间）：按键码和修饰键（CGEventFlags 的原始值）。
    struct SpaceKey: Equatable, Sendable {
        let keyCode: UInt16
        let flags: UInt64
    }

    enum GoPlan: Equatable, Sendable {
        /// 激活这个 App，系统自己切到它最前那扇窗所在的桌面（实测约 0.8 秒）。
        case activate
        /// 它在这张桌面上也有窗口，激活不会切：按系统自己的“移动一个空间”快捷键走过去，走 count 步。
        case keys(SpaceKey, count: Int)
    }

    /// 怎么去那扇窗时要知道的几件事。
    struct GoFacts: Equatable, Sendable {
        /// 这个 App 在眼前（任何一块屏的当前桌面）有窗口：激活只会叫出那一扇，不切。
        var appHasWindowHere: Bool
        /// 要去的这扇正是这个 App 最前的那扇：激活切去的就是它的桌面；不是的话激活会带错桌面。
        var targetIsAppFront: Bool
        /// 系统设置里“切换到某个应用程序时，会切换到包含该应用程序已打开窗口的空间”开着。
        var activationSwitches: Bool
        /// 这个 App 已经在最前：再激活什么也不会发生。
        var appIsFrontmost: Bool
        /// 目标那一排就是指针所在那块屏的：“移动一个空间”只作用在指针所在的屏上。
        var targetOnPointerDisplay: Bool
    }

    /// 怎么去那扇窗。row：目标那块屏的桌面次序（全屏桌面也算一步，和 ⌃← ⌃→ 一样）；target：窗口所在的桌面。
    /// 激活能准确切过去时就激活；否则在目标就在指针那块屏上时按快捷键走过去；都不行就退回激活（至少把 App 叫到前面）。
    static func goPlan(_ facts: GoFacts, row: DesktopRow?, target: UInt64?,
                       moveLeft: SpaceKey?, moveRight: SpaceKey?) -> GoPlan {
        let activationLandsThere = !facts.appHasWindowHere && facts.targetIsAppFront && facts.activationSwitches
            && !facts.appIsFrontmost
        guard !activationLandsThere, facts.targetOnPointerDisplay, let row, let target,
              let from = row.spaces.firstIndex(where: { $0.id == row.current }),
              let to = row.spaces.firstIndex(where: { $0.id == target }), from != to else { return .activate }
        let steps = to - from
        guard let key = steps > 0 ? moveRight : moveLeft else { return .activate }
        return .keys(key, count: abs(steps))
    }

    /// 读“往左 / 往右移动一个空间”（AppleSymbolicHotKeys 的 79 / 81）。关掉了返回 nil；没改过用系统默认的 ⌃← / ⌃→。
    /// entry：那一项的字典（enabled、value.parameters = [字符, 键码, 修饰键]）。
    static func spaceKey(_ entry: [String: Any]?, defaultKeyCode: UInt16) -> SpaceKey? {
        let controlFn: UInt64 = 0x40000 | 0x800000
        guard let entry else { return SpaceKey(keyCode: defaultKeyCode, flags: controlFn) }
        guard (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? NSNumber)?.boolValue ?? true) else { return nil }
        guard let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Any], parameters.count >= 3,
              let code = (parameters[1] as? NSNumber)?.uint16Value,
              let flags = (parameters[2] as? NSNumber)?.uint64Value else {
            return SpaceKey(keyCode: defaultKeyCode, flags: controlFn)
        }
        return SpaceKey(keyCode: code, flags: flags)
    }

    /// 格子上写的那一句。
    static func label(_ place: ElsewhereWindow.Place) -> String {
        switch place {
        case .desktop(let number): return "桌面 \(number)"
        case .fullScreen: return "全屏"
        }
    }
}
