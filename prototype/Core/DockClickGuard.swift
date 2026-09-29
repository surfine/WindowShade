// “让开这个 App”（再点一下 Dock 图标）的守卫和默认值（docs/direction.md 最后一张表）。纯逻辑，可单测。
//
// 守卫：这个 App 有看不见的窗口时不让开，改成把窗口叫出来。他点 Dock 图标多半是在找窗口
// （Word 开着两份，一份缩进了程序坞），这时藏起整个 App，连眼前这份也不见了。
// 看不见的窗口：最小化的、在别的桌面上的（全屏 App 的那张桌面也算）、整扇在所有屏幕外面的。
// 整扇在屏幕外面的，还要 App 自己（辅助功能）说它是一扇标准窗口才算：不少 App 把画面用的辅助窗口停在屏幕外面，
// 那不是他丢了的窗口，算上它只会让这个 App 的 Dock 图标永远点了没反应。
// WindowShade 自己收着的窗口（卷帘条、收进刘海、侧拉、画中画）不算：它们有自己的地方找回来，让开这个 App 也不碍事。
// 这里只分类；窗口表、哪些最小化、在哪张桌面由 App/DockClickHide.swift 查好传进来。

import CoreGraphics

enum DockClickGuard {
    /// 窗口表里这个 App 的一扇窗（CGWindowListCopyWindowInfo 那一行）。
    struct Window: Equatable {
        let id: CGWindowID
        /// CG 全局坐标（主屏左上为原点、y 向下），和 NSScreen 换算后的 screens 同一套。
        let bounds: CGRect
        /// kCGWindowIsOnscreen：在这张桌面上、没最小化、没藏起来。
        let onScreen: Bool
        let layer: Int
        let alpha: Double
    }

    /// 这个 App 的窗口都在哪。
    struct Survey: Equatable {
        /// 这张桌面上有露着的窗口（和以前一样的判断：普通层级、比 80×60 大、在屏上）。没有就不接，照系统原样。
        var visible = false
        /// 最小化的（按辅助功能列出来的顺序）。
        var minimized: [CGWindowID] = []
        /// 在别的桌面上的。
        var elsewhere: [CGWindowID] = []
        /// 在屏上，但整扇在所有屏幕外面的标准窗口。
        var offscreen: [CGWindowID] = []

        var hasUnseen: Bool { !minimized.isEmpty || !elsewhere.isEmpty || !offscreen.isEmpty }
    }

    enum Action: Equatable {
        /// 这一下本来就不归我们（没有露着的窗口）：什么都不做。
        case leave
        /// 让开这个 App（和 ⌘H 一样）。
        case hide
        /// 有看不见的窗口：不让开。有最小化的，把第一扇还原到前面；没有（在别的桌面、在屏幕外）就只是不让开。
        case bringBack(CGWindowID?)
    }

    /// 普通的窗口：普通层级、比 80×60 大（和以前判断“露着”用的是同一条）。
    static func isRegular(_ window: Window) -> Bool {
        window.layer == 0 && window.bounds.width > 80 && window.bounds.height > 60
    }

    /// 在屏上、看得见（不透明）、却整扇在所有屏幕外面的普通窗口。有这种窗口时才去问辅助功能它是不是标准窗口。
    static func outsideScreens(windows: [Window], screens: [CGRect], managed: Set<CGWindowID>) -> [CGWindowID] {
        windows.filter { window in
            window.onScreen && isRegular(window) && !managed.contains(window.id) && window.alpha > 0
                && !screens.contains(where: { $0.intersects(window.bounds) })
        }.map(\.id)
    }

    /// 窗口分类。
    /// - screens：每块屏的外框，CG 全局坐标。
    /// - managed：WindowShade 自己收着的窗口。
    /// - minimized：辅助功能报告为最小化的窗口（按它列出来的顺序）。
    /// - standard：辅助功能报告为标准窗口的（只在有屏幕外的窗口时才问，其余时候给空）。屏幕外的只有它里面的才算。
    /// - spaceOf：窗口在哪张桌面（查不到给 nil）；currentSpaces：每块屏现在显示的那张桌面。查不到桌面时不判“在别的桌面”。
    static func survey(windows: [Window], screens: [CGRect], managed: Set<CGWindowID>, minimized: [CGWindowID],
                       standard: Set<CGWindowID>, spaceOf: (CGWindowID) -> UInt64?, currentSpaces: Set<UInt64>) -> Survey {
        var result = Survey()
        result.visible = windows.contains { $0.onScreen && isRegular($0) }
        result.minimized = minimized.filter { !managed.contains($0) }
        result.offscreen = outsideScreens(windows: windows, screens: screens, managed: managed).filter(standard.contains)
        let minimizedSet = Set(minimized)
        for window in windows where !window.onScreen && isRegular(window) && !managed.contains(window.id) {
            if !minimizedSet.contains(window.id), !currentSpaces.isEmpty,
               let space = spaceOf(window.id), !currentSpaces.contains(space) {
                result.elsewhere.append(window.id)
            }
        }
        return result
    }

    static func action(for survey: Survey) -> Action {
        guard survey.visible else { return .leave }
        guard survey.hasUnseen else { return .hide }
        return .bringBack(survey.minimized.first)
    }
}

/// “让开这个 App”没设置过时开不开。
/// 换机的人（欢迎窗口里答了 Windows 或 iPad）默认关：这正是 Windows 任务栏的行为，他在 Dock 上找窗口时会把眼前的也藏掉。
/// 用过 1.0.16 测试版的，这个开关当时默认开着：照旧开着。其余（一直用 Mac、没答的，包括从 1.0.15 升上来还没答的）默认开。
enum DockClickHideDefault {
    static func isOn(previewInstall: Bool, origin: SwitcherOrigin) -> Bool {
        if previewInstall { return true }
        switch origin {
        case .windows, .ipad: return false
        case .mac, .unanswered: return true
        }
    }
}
