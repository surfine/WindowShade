// 「提示音」总开关（拍板 2026-10-29 第 1 条）：编程会话等你、完成，番茄钟休息的开始与结束，
// 计时器到点，指挥页的拍子，都听这一个开关；遥控器静音键拨的也是它。
// 卷帘收起 / 展开的效果声是动作声，不是提醒，保留自己那一行（ShadeSoundEnabled），不经这里。
//
// 纯逻辑，不碰 AppKit；旧键迁移在这里集中做，测试注入自己的设置库。

import Foundation

enum AlertSoundPreference {
    static let key = "WindowShade.AlertSound"
    /// 三个旧键：番茄钟借用的效果声开关、计时器到点、指挥拍子。
    static let legacyKeys = ["ShadeSoundEnabled", "Timer.chimeEnabled", "WindowShade.Conductor.Sound"]
    /// 旧键没存过时各自当年的默认：计时器到点默认响，番茄钟借的效果声和指挥拍子默认不响。
    static let legacyDefaults = ["ShadeSoundEnabled": false, "Timer.chimeEnabled": true, "WindowShade.Conductor.Sound": false]
    /// 旧键一个都没存过时的默认，照 ReleaseDefaults 那一行（默认开：计时器到点 1.0.17 起默认会响，统一后新装不丢这一声）。
    static var defaultEnabled: Bool { ReleaseDefaults.value(key) }

    /// 迁移：新键没存过时，三个旧键都没存过照默认；否则任一旧键开着就开——没存过的旧键按它当年的默认算，
    /// 所以只关过收起音效、没碰过计时器的人，计时器照旧响（帕累托）。新键存过之后迁移不再参与，人改的值原样保留。
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: key) != nil { return defaults.bool(forKey: key) }
        guard legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return defaultEnabled }
        return legacyKeys.contains { (defaults.object(forKey: $0) as? Bool) ?? legacyDefaults[$0] ?? false }
    }

    /// 启动时把迁移结果落一次盘：之后卷帘那一行（ShadeSoundEnabled）怎么拨都不再牵动提示音。
    static func migrateIfNeeded(in defaults: UserDefaults) {
        guard defaults.object(forKey: key) == nil else { return }
        set(isEnabled(in: defaults), in: defaults)
    }

    static func set(_ on: Bool, in defaults: UserDefaults) {
        defaults.set(on, forKey: key)
    }
}
