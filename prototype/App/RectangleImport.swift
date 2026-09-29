// 从 Rectangle 搬过来：一下把对应的动作设成 Rectangle 的快捷键，手上的习惯不用改。
// 装过 Rectangle 的，照它现在的设置（偏好设置里改过的、清掉的都算）；只有它导出的 RectangleConfig.json 的，照那份；
// 都没有的，用它首次打开时推荐的那一套（⌃⌥ 加方向键和字母）。算法见 Core/RectangleKeymap.swift。
// Raycast 的窗口命令没有默认快捷键、设置也读不到：名字一一对应（RectangleCommand.raycastName），照着录就行。

import Cocoa

enum RectangleImport {
    enum Source { case preferences, config, recommended }

    /// Rectangle 的动作 → 我们的快捷键。
    static let mapping: [RectangleCommand: GlobalShortcut] = [
        .leftHalf: .leftHalf, .rightHalf: .rightHalf, .topHalf: .topHalf, .bottomHalf: .bottomHalf,
        .topLeft: .topLeft, .topRight: .topRight, .bottomLeft: .bottomLeft, .bottomRight: .bottomRight,
        .firstThird: .leftThird, .centerThird: .centerThird, .lastThird: .rightThird,
        .firstTwoThirds: .leftTwoThirds, .lastTwoThirds: .rightTwoThirds,
        .maximize: .fill, .maximizeHeight: .fullHeight, .larger: .larger, .smaller: .smaller,
        .center: .center, .restore: .undoPlacement,
        .nextDisplay: .nextDisplay, .previousDisplay: .previousDisplay,
    ]

    /// Rectangle 现在用的快捷键，以及是从哪看来的。
    static func current() -> (combos: [RectangleCommand: KeyCombo], source: Source) {
        let domain = RectangleKeymap.domain as CFString
        if let keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String],
           !keys.isEmpty,
           let prefs = CFPreferencesCopyMultiple(keys as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String: Any] {
            return (RectangleKeymap.resolve(preferences: prefs), .preferences)
        }
        let config = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Rectangle/RectangleConfig.json")
        if let data = try? Data(contentsOf: config), let combos = RectangleKeymap.resolve(configJSON: data) {
            return (combos, .config)
        }
        return (RectangleKeymap.recommendedSet, .recommended)
    }

    /// 设好对应的快捷键。我们自己别的动作用着同一个组合的，让给 Rectangle 的这一个（关掉），返回它们的名字。
    @discardableResult
    static func apply(_ combos: [RectangleCommand: KeyCombo]) -> (count: Int, yielded: [String]) {
        var assigned: [GlobalShortcut: GlobalShortcutSettings.HotKey] = [:]
        for (command, combo) in combos {
            guard let shortcut = mapping[command] else { continue }
            assigned[shortcut] = GlobalShortcutSettings.HotKey(keyCode: combo.keyCode, modifiers: combo.carbonModifiers)
        }
        var yielded: [String] = []
        for shortcut in GlobalShortcut.allCases where assigned[shortcut] == nil {
            guard let mine = GlobalShortcutSettings.hotKey(for: shortcut), assigned.values.contains(mine) else { continue }
            GlobalShortcutSettings.setHotKey(nil, for: shortcut)
            yielded.append(shortcut.title)
        }
        for (shortcut, hotKey) in assigned { GlobalShortcutSettings.setHotKey(hotKey, for: shortcut) }
        return (assigned.count, yielded)
    }

    static var isRectangleRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: RectangleKeymap.domain).isEmpty
    }
}

extension GlobalShortcut {
    /// 直接排到哪一格、做哪一样（走 TrackpadGestureController.keyPlace）；别的动作返回 nil。
    var placement: GestureAction? {
        switch self {
        case .topHalf: return .topHalf
        case .bottomHalf: return .bottomHalf
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        case .leftThird: return .leftThird
        case .centerThird: return .centerThird
        case .rightThird: return .rightThird
        case .leftTwoThirds: return .leftTwoThirds
        case .rightTwoThirds: return .rightTwoThirds
        case .fill: return .fill
        case .fullHeight: return .fullHeight
        case .larger: return .larger
        case .smaller: return .smaller
        case .center: return .center
        case .undoPlacement: return .undoPlacement
        default: return nil
        }
    }
}

extension AppDelegate {
    /// 设置里“用 Rectangle 的快捷键”（只在这里，刘海不主动推荐）。Rectangle 还开着时它占着这些组合：说一声，等它退出再注册一遍。
    @MainActor @objc func prefUseRectangleShortcuts() {
        let (combos, source) = RectangleImport.current()
        let result = RectangleImport.apply(combos)
        registerGlobalShortcuts()
        rebuildMenu()
        refreshPreferencesWindowIfOpen()
        wlog("rectangle-import: \(result.count) shortcuts from \(source), yielded=\(result.yielded)")
        if RectangleImport.isRectangleRunning {
            notch.announce("退出 Rectangle 后就能用", detail: "它还开着，这些快捷键暂时归它", tone: .info)
            var token: NSObjectProtocol?
            token = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == RectangleKeymap.domain else { return }
                if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
                MainActor.assumeIsolated {
                    self?.registerGlobalShortcuts()
                    self?.rebuildMenu()
                    self?.notch.announce("Rectangle 的快捷键现在归 WindowShade 了", tone: .done)
                }
            }
            return
        }
        var detail = source == .recommended ? "用的是 Rectangle 推荐的那一套" : "照你在 Rectangle 里的设置"
        if !result.yielded.isEmpty { detail += "；\(result.yielded.joined(separator: "、"))的快捷键让给了它" }
        notch.announce("换成了 Rectangle 的快捷键", detail: detail, tone: .done)
    }
}
