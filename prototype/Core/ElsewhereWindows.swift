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
        var places: [UInt64: ElsewhereWindow.Place] = [:]
        for row in desktops {
            var number = 0
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

    /// 格子上写的那一句。
    static func label(_ place: ElsewhereWindow.Place) -> String {
        switch place {
        case .desktop(let number): return "桌面 \(number)"
        case .fullScreen: return "全屏"
        }
    }
}
