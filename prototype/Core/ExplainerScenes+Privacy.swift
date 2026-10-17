// 设置 → 隐私 的讲解（1.0.18 工作单 9；逐页表“隐私”，稿《首次打开 1.0.17 小样》E 节）。
// 这一页全是静图：私人窗口、两项系统授权（已授权 / 未授权各一张，按此刻的授权状态摆）、登录时自动启动（开关关着时降灰）。
// “读到的都列在这里”那块是页默认。坐标是 312 × 200 的块，数字照稿抄。

import CoreGraphics
import Foundation

extension ExplainerPage {
    /// 页默认：私人窗口（逐页表“隐私”的第一行）。
    static var privacy: ExplainerPage { ExplainerPage(id: "privacy", pageDefault: ExplainerScenes.privateWindow) }
}

extension ExplainerRow {
    /// 隐私页每一行演哪一段。授权行按此刻的授权状态取已授权或未授权那张；更新行、读到的清单跟页默认。
    enum Privacy {
        static var privateApps: ExplainerRow { .still(ExplainerScenes.privateWindow) }
        static func accessibility(granted: Bool) -> ExplainerRow {
            .still(granted ? ExplainerScenes.accessibilityOn : ExplainerScenes.accessibilityOff)
        }
        static func screenRecording(granted: Bool) -> ExplainerRow {
            .still(granted ? ExplainerScenes.screenRecordingOn : ExplainerScenes.screenRecordingOff)
        }
        /// 开关关着照样摆这一张，自动降灰。
        static var launchAtLogin: ExplainerRow { .still(ExplainerScenes.launchAtLogin) }
        static var plain: ExplainerRow { .pageDefault }
    }
}

extension ExplainerScenes {
    /// 窗口收成卷帘条 + 菜单栏下的窗口浏览面板，是授权与私人窗口三张图的共同底。
    private static var panelBase: ExplainerState {
        [.windowA: P(x: 60, y: 28, w: 190, h: 70, opacity: 1, scale: 1), .dock: P(opacity: 1)]
    }

    /// 私人窗口：选进私人窗口的 App，在窗口浏览和看一眼里只露图标。
    static var privateWindow: ExplainerSpec {
        var initial = panelBase
        initial[.panel] = P(y: 112, opacity: 1, look: .privatePreview)
        return still(id: "privateWindow", deviceText: WSL10n.setting("explainer.privateWindow.text", zh: "私人窗口：1Password"),
                     initial: initial,
                     description: WSL10n.setting("explainer.privateWindow.ax", zh: "演示：选进私人窗口的 App，在窗口浏览和看一眼里只露图标，不露内容。"))
    }

    /// 辅助功能 · 已授权：窗口能被收起。
    static var accessibilityOn: ExplainerSpec {
        still(id: "accessibilityOn",
              deviceText: WSL10n.setting("explainer.accessibilityOn.text", zh: "辅助功能 · 已授权").namingPrivacyPane(),
              initial: [.windowA: P(x: 70, y: 40, w: 172, h: 10, opacity: 1, scale: 1, rolled: true)],
              description: WSL10n.setting("explainer.accessibilityOn.ax", zh: "演示：打开辅助功能，窗口才能被收起、挪动。").namingPrivacyPane())
    }

    /// 辅助功能 · 未授权：窗口原样不动。
    static var accessibilityOff: ExplainerSpec {
        still(id: "accessibilityOff",
              deviceText: WSL10n.setting("explainer.accessibilityOff.text", zh: "辅助功能 · 未授权").namingPrivacyPane(),
              initial: [.windowA: window0],
              description: WSL10n.setting("explainer.accessibilityOff.ax", zh: "演示：没打开辅助功能时，窗口收不起来，也挪不动。").namingPrivacyPane())
    }

    /// 屏幕录制 · 已授权：卡片里是窗口的实时画面。
    static var screenRecordingOn: ExplainerSpec {
        var initial = panelBase
        initial[.panel] = P(y: 112, opacity: 1, look: .livePreview)
        return still(id: "screenRecordingOn", deviceText: WSL10n.setting("explainer.screenRecordingOn.text", zh: "屏幕录制 · 已授权"),
                     initial: initial,
                     description: WSL10n.setting("explainer.screenRecordingOn.ax", zh: "演示：打开屏幕录制，卡片里是窗口的实时画面。"))
    }

    /// 屏幕录制 · 未授权：卡片里只有图标，没有画面。
    static var screenRecordingOff: ExplainerSpec {
        var initial = panelBase
        initial[.panel] = P(y: 112, opacity: 1, look: .plain)
        return still(id: "screenRecordingOff", deviceText: WSL10n.setting("explainer.screenRecordingOff.text", zh: "屏幕录制 · 未授权"),
                     initial: initial,
                     description: WSL10n.setting("explainer.screenRecordingOff.ax", zh: "演示：没打开屏幕录制时，卡片里没有窗口的画面。"))
    }

    /// 登录时自动启动 · 开：登录后菜单栏里的图标自己出现。
    static var launchAtLogin: ExplainerSpec {
        still(id: "launchAtLogin", deviceText: WSL10n.setting("explainer.launchAtLogin.text", zh: "登录这台 Mac"),
              initial: [.windowA: window0, .menuBarIcon: P(opacity: 1, highlighted: true)],
              description: WSL10n.setting("explainer.launchAtLogin.ax", zh: "演示：登录后，菜单栏里的图标自己出现。"))
    }
}
