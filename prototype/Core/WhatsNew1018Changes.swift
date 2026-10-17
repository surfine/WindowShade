// 1.0.18“这一版新开了这几样”（N1）该列哪几行，以及启动时走哪条引导路（新装 A1、升级缺授权 U1 → N1、升级只看 N1）。
//
// Aaron 拍板 2026-10-17：这 13 个键 1.0.18 起默认开，新老都开（见 ReleaseDefaults、docs/releases/v1.0.18-defaults.md）。
// 升级上来的人用 N1 告诉他一次，只列真变了的：显式存过值的不算（照他自己的），没存过的、1.0.17 发出去是关、
// 现在是开的才算。他自己关过刘海，刘海那一行（和放在刘海里的文件架）就不出。
//
// 纯逻辑，只读传进来的值，可单测（tests/run-whats-new-1018-tests.sh）。

import Foundation

enum WhatsNew1018Changes {
    /// N1 的三行。
    enum Group: String, CaseIterable, Sendable {
        /// 刘海主功能和它的子项。
        case notch
        /// Dock 悬停查看窗口。
        case dockHover
        /// 文件架和再点一下 Dock 图标让开。
        case shelfAndDock
    }

    static let notchMasterKey = "Notch.enabled"
    static let notchKeys = [
        notchMasterKey, "Notch.changeAlerts", "Notch.teach", "Notch.activitiesEnabled",
        "Notch.activities.musicEnabled", "Notch.activities.nowPlayingStream", "Notch.mergedRow",
        "Notch.minimalPresentation", "Notch.deviceBattery.enabled", "Notch.levelKeys.enabled",
    ]
    static let dockHoverKey = "WindowBrowserDockEnabled"
    static let fileShelfKey = "FileShelf.enabled"
    static let dockClickKey = "Dock.clickToHide"
    /// 这一版拍板改了默认值的 13 个键。
    static var keys: [String] { notchKeys + [dockHoverKey, fileShelfKey, dockClickKey] }

    /// 这一版只弹一次 N1 / U1 的记号。
    static let whatsNewShownKey = "WhatsNewShown.1.0.18"
    static let permissionsAgainShownKey = "PermissionsAgainShown.1.0.18"

    /// 哪些键对这个人真变了：没显式存过值（`stored` 给 nil）、1.0.17 没设过时是关、现在没设过时是开。
    /// - stored：键里存的 Bool；没存过或存的不是 Bool 给 nil（和各处读设置时“按没设过算”一致）。
    /// - releaseValue：这一版没设过时的值（默认 ReleaseDefaults.value）。
    /// - dockClickNow：“再点 Dock 让开”现在没设过时的值（DockClickHideDefault 还看来处：从 Windows、iPad 来的仍关）。
    /// - previewInstall：用过 1.0.16 测试版的，“再点 Dock 让开”那时没设过就是开，对他不算变。
    static func changedKeys(stored: (String) -> Bool?,
                            releaseValue: (String) -> Bool = ReleaseDefaults.value,
                            dockClickNow: Bool,
                            previewInstall: Bool) -> [String] {
        keys.filter { key in
            guard stored(key) == nil else { return false }
            if key == dockClickKey { return !previewInstall && dockClickNow }
            // 1.0.17 发出去时这 13 个键没设过都是关（总账里没验过、没拍板）。
            return releaseValue(key)
        }
    }

    /// N1 要列的组，按 N1 里的顺序。没有就不弹 N1。
    /// 刘海现在关着（他自己显式关过）：刘海那一行不出，放在刘海里的文件架也不算；“再点 Dock 让开”不靠刘海，照算。
    static func groups(changed: [String], notchOn: Bool) -> [Group] {
        let changed = Set(changed)
        var result: [Group] = []
        if notchOn, !changed.isDisjoint(with: notchKeys) { result.append(.notch) }
        if changed.contains(dockHoverKey) { result.append(.dockHover) }
        if (notchOn && changed.contains(fileShelfKey)) || changed.contains(dockClickKey) { result.append(.shelfAndDock) }
        return result
    }

    /// 方便调用：直接读一份设置。
    static func groups(in defaults: UserDefaults, dockClickNow: Bool, previewInstall: Bool,
                       releaseValue: (String) -> Bool = ReleaseDefaults.value) -> [Group] {
        let stored: (String) -> Bool? = { defaults.object(forKey: $0) as? Bool }
        let changed = changedKeys(stored: stored, releaseValue: releaseValue,
                                  dockClickNow: dockClickNow, previewInstall: previewInstall)
        let notchOn = stored(notchMasterKey) ?? releaseValue(notchMasterKey)
        return groups(changed: changed, notchOn: notchOn)
    }
}

/// 启动时走哪条引导路（设计稿“首次打开 1.0.17 小样”工作单第 4 条）。
enum LaunchOnboardingRoute: Equatable, Sendable {
    /// 什么都不弹。
    case none
    /// 欢迎窗口，从第一页（A1）看起。
    case welcome
    /// 升级上来缺辅助功能：“再打开一次这两项”（U1）；thenWhatsNew 时关掉 U1 后接 N1。
    case permissionsAgain(thenWhatsNew: Bool)
    /// 升级上来、有真变了的新默认：“这一版新开了这几样”（N1）。
    case whatsNew

    /// - upgrade：这台 Mac 以前跑过 WindowShade（这一次启动之前就有安装记录，或认出是 1.0.15 及以前的老安装）。
    ///   不依赖更新日志，所以手动下载装上来的也认得出。
    /// - onboardingShown：欢迎窗口看过了（ShadeOnboardingShown）。
    /// - accessibilityTrusted：现在有没有辅助功能（启动时只读，不弹系统框）。
    /// - permissionsAgainShown / whatsNewShown：这一版的 U1 / N1 看过了没有。
    /// - hasWhatsNew：WhatsNew1018Changes.groups 不空。
    static func decide(upgrade: Bool, onboardingShown: Bool, accessibilityTrusted: Bool,
                       permissionsAgainShown: Bool, whatsNewShown: Bool, hasWhatsNew: Bool) -> LaunchOnboardingRoute {
        // 新装：A1；T 已经演过新开的这些，不看 N1。
        guard upgrade else { return onboardingShown ? .none : .welcome }
        let whatsNew = hasWhatsNew && !whatsNewShown
        // 先找回授权：不先找回，新开的这些也用不了。
        if !accessibilityTrusted && !permissionsAgainShown { return .permissionsAgain(thenWhatsNew: whatsNew) }
        if whatsNew { return .whatsNew }
        // 老安装还没看完欢迎窗口（以前每次启动都会再弹，照旧）。
        return onboardingShown ? .none : .welcome
    }
}
