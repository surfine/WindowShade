// 音量亮度键遇到全屏、调度中心怎么办（《音量与亮度》稿判定表）：
// 原先旁听那一路用老门闸，只要这块屏是全屏桌面就一律不出；现在全屏交给 NotchLevelSuppression 与两耳的可见性判定——
// 全屏而且面板在这张全屏桌面上真的看得见，才出两耳，也才有可能拦；看不见或查不到，不出两耳、不拦，系统的提示照常。
// 调度中心里仍然不出（我们不能保证画在它上面）。纯逻辑，不碰 AppKit。

import Foundation

enum NotchLevelScreen {
    /// 判定表里“全屏”那一栏。isFullScreen：指针那块屏是不是原生全屏桌面（nil = 查不到）；
    /// panelVisibility：面板在这张桌面上有没有确认过可见（没露出来过、查不到都算看不见）。
    /// 不是全屏一律 .no；全屏时只有确认过可见才 .visible；全屏状态都查不到，按看不见处理（不拦）。
    static func suppressionFullScreen(isFullScreen: Bool?, panelVisibility: NotchLevelSuppression.FullScreen)
        -> NotchLevelSuppression.FullScreen {
        switch isFullScreen {
        case false?: return .no
        case true?: return panelVisibility == .visible ? .visible : .notVisible
        case nil: return .notVisible
        }
    }

    /// 旁听那一路的老门闸：只剩锁屏与调度中心。全屏不在这里挡——开不开口由 Notch.presentLevel 看面板是不是真看得见。
    static func gateContext(locked: Bool, missionControl: Bool) -> NotchLevelGate.Context {
        var context = NotchLevelGate.Context()
        context.locked = locked
        context.missionControl = missionControl
        return context
    }

    /// 拦键时判定表的“屏幕”几项。isFullScreen、missionControl 来自 NotchSpaceGate 的三态（nil = 读不到）：
    /// 调度中心读不到按没开（和让开规则一致，未知不让开）；全屏读不到按看不见。
    static func apply(to input: inout NotchLevelSuppression.Input, isFullScreen: Bool?, missionControl: Bool?,
                      panelVisibility: NotchLevelSuppression.FullScreen) {
        input.missionControl = missionControl == true
        input.fullScreen = suppressionFullScreen(isFullScreen: isFullScreen, panelVisibility: panelVisibility)
    }
}
