// 设置里“音量和亮度”这一行（《音量与亮度》稿“设置这一行，和辅助功能”）：开关、三种副标题、“允许…”那一路。
// 纯逻辑，不碰 AppKit；画这一行在 Preferences.swift。

import Foundation

enum NotchLevelSetting {
    /// 开关，默认开（Aaron 2026-10-09）。关了：不出两耳，也不拦键，系统的提示照常。
    static let key = "Notch.levelKeys.enabled"
    /// 开关或辅助功能状态变了，设置这一行与监听都按它重算。
    static let didChange = Notification.Name("WindowShade.NotchLevelSetting.didChange")

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    static func setEnabled(_ on: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(on, forKey: key)
    }
}

/// 这一行现在怎么写。
struct NotchLevelSettingRow: Equatable, Sendable {
    static let title = "音量和亮度"
    static let symbol = "speaker.wave.2"

    var subtitle: String
    /// ⓘ 里那一句（一定有）。
    var info: String
    /// 没允许辅助功能时的按钮字；nil 就不放按钮。
    var allowButton: String?

    static let normalSubtitle = "按音量、亮度键时显示"
    static let missingSubtitle = "系统的提示也会出现"
    static let allowTitle = "允许…"
    static let normalInfo = "按音量、亮度、键盘灯键时，刘海两边显示一条，系统自己的提示藏起来。锁屏和调度中心里仍是系统的提示。"
    static let missingInfo = "在“辅助功能”里打开 WindowShade，系统自己的提示就会藏起来。"
    static let unverifiedInfo = "这个 macOS 版本还没核对过，系统的提示会一起出现。"

    /// 三种写法：平时；没允许辅助功能；允许了但版本没核对过。
    /// 没允许时副标题固定是“系统的提示也会出现”并带按钮；版本没核对过时，ⓘ 改说版本（允许了也藏不了，不能说“就会藏起来”）。
    static func make(accessibilityTrusted: Bool, versionVerified: Bool) -> NotchLevelSettingRow {
        if !accessibilityTrusted {
            return NotchLevelSettingRow(subtitle: missingSubtitle,
                                        info: versionVerified ? missingInfo : unverifiedInfo,
                                        allowButton: allowTitle)
        }
        return NotchLevelSettingRow(subtitle: normalSubtitle,
                                    info: versionVerified ? normalInfo : unverifiedInfo,
                                    allowButton: nil)
    }
}

/// 点“允许…”之后等用户去系统设置里打开：设置窗口在前台时每 1 秒查一次，最多 2 分钟；不在后台轮询。
struct NotchLevelAllowWatch: Equatable, Sendable {
    static let interval: TimeInterval = 1
    static let limit: TimeInterval = 120

    enum Step: Equatable, Sendable {
        /// 已经允许了：马上装监听，不用重开。
        case allowed
        /// 满 2 分钟：不再查。
        case expired
        /// 设置窗口不在前台：先停，回到前台再查一次、接着数。
        case paused
        case waiting
    }

    var startedAt: TimeInterval

    func step(now: TimeInterval, trusted: Bool, windowInFront: Bool) -> Step {
        if trusted { return .allowed }
        if now - startedAt >= Self.limit { return .expired }
        return windowInFront ? .waiting : .paused
    }
}
