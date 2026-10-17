// 设置 → 刘海 的讲解（设计稿《首次打开 1.0.17 小样》E 节逐页表“刘海”）。页默认是收进刘海；
// 每一行演自己的一段：有变化时提醒、实时活动、正在播放、浏览器下载、合成一排、悬停不误触、文件架、设备的电量，
// “之前常用”三段各一个场景。数字逐个照稿里的帧数据抄；通用的“刘海说一句”在 ExplainerScenes+Common.swift。

import CoreGraphics
import Foundation

extension ExplainerPage {
    /// 页默认：收进刘海（甩一下标题栏，点一下放回）。
    static var notch: ExplainerPage { ExplainerPage(id: "notch", pageDefault: ExplainerScenes.tuckIntoNotch) }
}

extension ExplainerScenes {
    /// 收着的窗口（卷帘条），“有变化时提醒”演的是收起的窗口标题变了。
    private static var rolledWindow: P { P(x: 70, y: 40, w: 172, h: 10, opacity: 1, scale: 1, rolled: true) }

    /// 有变化时提醒：收起的窗口标题变了，刘海说一句，2.6 s 后收回。
    static var notchAlert: ExplainerSpec {
        notchSays(id: "notch.alert",
                  when: WSL10n.setting("explainer.notch.alert.when", zh: "窗口标题变了"),
                  line: WSL10n.setting("explainer.notch.alert.line", zh: "构建完成"),
                  detail: WSL10n.setting("explainer.notch.alert.sub", zh: "“构建日志”那扇窗口"),
                  description: WSL10n.setting("explainer.notch.alert.ax", zh: "演示：收起的窗口标题变了，刘海展开说一句，2.6 秒后收回。"),
                  window: rolledWindow)
    }

    /// 实时活动：放一首歌，刘海两边长出封面和波形。
    static var notchLiveActivity: ExplainerSpec {
        notchSays(id: "notch.live",
                  when: WSL10n.setting("explainer.notch.live.when", zh: "放一首歌"),
                  line: WSL10n.setting("explainer.notch.live.line", zh: "♪ 晴天"),
                  detail: WSL10n.setting("explainer.notch.live.sub", zh: "两边：封面和波形"),
                  description: WSL10n.setting("explainer.notch.live.ax", zh: "演示：放一首歌，刘海两边长出封面和波形。"),
                  size: CGSize(width: 180, height: 22))
    }

    /// 正在播放：换歌，封面换成新的。
    static var notchNowPlaying: ExplainerSpec {
        notchSays(id: "notch.nowPlaying",
                  when: WSL10n.setting("explainer.notch.nowPlaying.when", zh: "换下一首"),
                  line: WSL10n.setting("explainer.notch.nowPlaying.line", zh: "♪ 七里香"),
                  detail: WSL10n.setting("explainer.notch.nowPlaying.sub", zh: "封面换成新的"),
                  description: WSL10n.setting("explainer.notch.nowPlaying.ax", zh: "演示：换歌时，刘海上的封面换成新的。"),
                  size: CGSize(width: 160, height: 28))
    }

    /// 浏览器下载：刘海一边出现进度。
    static var notchDownload: ExplainerSpec {
        notchSays(id: "notch.download",
                  when: WSL10n.setting("explainer.notch.download.when", zh: "Safari 开始下载"),
                  line: WSL10n.setting("explainer.notch.download.line", zh: "下载 48%"),
                  detail: WSL10n.setting("explainer.notch.download.sub", zh: "report.pdf"),
                  description: WSL10n.setting("explainer.notch.download.ax", zh: "演示：浏览器下载时，刘海一边显示进度。"),
                  size: CGSize(width: 150, height: 28))
    }

    /// 合成一排：指针停在刘海上，窗口和正在进行的事排成一排。
    static var notchMergedRow: ExplainerSpec {
        notchSays(id: "notch.merged",
                  when: WSL10n.setting("explainer.notch.merged.when", zh: "指针停在刘海上"),
                  line: WSL10n.setting("explainer.notch.merged.line", zh: "2 扇窗口 · 1 项下载"),
                  detail: WSL10n.setting("explainer.notch.merged.sub", zh: "排在同一排"),
                  description: WSL10n.setting("explainer.notch.merged.ax", zh: "演示：指针停在刘海上，窗口和正在进行的事排成一排。"),
                  size: CGSize(width: 200, height: 40),
                  pointerTo: P(x: 156, y: 6), pointer: P(x: 236, y: 120, opacity: 1))
    }

    /// 设备的电量：AirPods 连上，刘海说一声电量。
    static var notchDeviceBattery: ExplainerSpec {
        notchSays(id: "notch.battery",
                  when: WSL10n.setting("explainer.notch.battery.when", zh: "AirPods 连上"),
                  line: WSL10n.setting("explainer.notch.battery.line", zh: "AirPods 已连接"),
                  detail: WSL10n.setting("explainer.notch.battery.sub", zh: "电量 82%"),
                  description: WSL10n.setting("explainer.notch.battery.ax", zh: "演示：AirPods 连上时，刘海说一声电量。"),
                  size: CGSize(width: 160, height: 36))
    }

    /// 悬停不误触：指针路过刘海不展开，停一下才展开。
    static var notchHoverGuard: ExplainerSpec {
        ExplainerSpec(
            id: "notch.hoverGuard", device: .point,
            initial: [.windowA: window0, .pointer: P(x: 30, y: 6, opacity: 1), .notch: P(w: 40, h: 10), .notchLine: P(opacity: 0)],
            frames: [
                F("passes by: stays closed", .calm, [.pointer: P(x: 280)], hold: 0.4, story: true),
                F("comes back and rests", .calm, [.pointer: P(x: 156)], hold: 0.12, story: true),
                F("rests: it opens", .calm, [.notch: P(w: 150, h: 30, easing: .expand), .notchLine: P(opacity: 1, easing: .fade)],
                  hold: 1.2, key: true),
                F("", .calm, [.notch: P(w: 40, h: 10), .notchLine: P(opacity: 0), .pointer: P(x: 30)], hold: 0.6),
            ],
            arrows: ExplainerArrows(result: "M30 16 L280 16"),
            description: WSL10n.setting("explainer.notch.hoverGuard.ax", zh: "演示：指针路过刘海不展开，停一下才展开。"),
            notchLine: (WSL10n.setting("explainer.notch.hoverGuard.line", zh: "停一下才展开"),
                        WSL10n.setting("explainer.notch.hoverGuard.sub", zh: "路过不展开")))
    }

    /// 文件架：把文件拖到刘海，它进文件架。
    static var notchFileShelf: ExplainerSpec {
        ExplainerSpec(
            id: "notch.shelf", device: .press,
            initial: [.windowA: window0, .windowB: P(x: 240, y: 140, w: 22, h: 28, opacity: 1, scale: 1, look: .file),
                      .notch: P(w: 40, h: 10), .pointer: P(x: 251, y: 150, opacity: 1),
                      .finger1: P(x: 200, y: 130, opacity: 0, pressed: false)],
            frames: [
                F("hold the file", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.15, story: true),
                F("drag it to the notch", .calm,
                  [.finger1: P(x: 156, y: 70, easing: .calm), .pointer: P(x: 156, y: 6, easing: .calm),
                   .windowB: P(x: 145, y: 0, w: 22, h: 10, opacity: 0, scale: 0.6, easing: .settle), .notch: P(w: 64, easing: .settle)],
                  hold: 0.5, key: true),
                F("it is on the shelf", .calm, [.notch: P(w: 40, easing: .calm), .finger1: P(opacity: 0, pressed: false, easing: .fade)],
                  hold: 0.8, story: true),
                .reset,
            ],
            arrows: ExplainerArrows(device: "M200 130 L160 74", result: "M240 140 L160 14"),
            description: WSL10n.setting("explainer.notch.shelf.ax", zh: "演示：把文件拖到刘海，它进文件架。"))
    }

    // MARK: 之前常用（三段）

    private static func keyAt(_ symbol: String, _ caption: String) -> ExplainerKeyCap { ExplainerKeyCap(symbol: symbol, caption: caption) }

    /// 之前常用 · Windows：Ctrl 和 Alt 的位置原地换成 Mac 的 Control 和 Command。
    static var originWindows: ExplainerSpec {
        ExplainerSpec(
            id: "notch.origin.windows", device: .keys,
            initial: [.windowA: window0, .key1: P(opacity: 1, pressed: false, keyCap: keyAt("Ctrl", "")),
                      .key2: P(opacity: 1, pressed: false, keyCap: keyAt("Alt", ""))],
            frames: [
                F("wait", .none, [:], hold: 0.8),
                F("Ctrl becomes control", .fade, [.key1: P(keyCap: keyAt("⌃", "control"))], hold: 0.4, story: true),
                F("Alt becomes command", .fade, [.key2: P(keyCap: keyAt("⌘", "command"))], hold: 1.4, key: true),
                F("", .none, [.key1: P(keyCap: keyAt("Ctrl", "")), .key2: P(keyCap: keyAt("Alt", ""))]),
            ],
            description: WSL10n.setting("explainer.notch.origin.windows.ax", zh: "演示：选了 Windows，Alt 和 Ctrl 的位置原地换成 Mac 的 Command 和 Control。"))
    }

    /// 之前常用 · iPad：静图，刘海提示菜单要两指点按。
    static var originIpad: ExplainerSpec {
        still(id: "notch.origin.ipad",
              deviceText: WSL10n.setting("explainer.notch.origin.ipad.text", zh: "两指点按"),
              initial: [.windowA: window0, .menu: P(opacity: 1)],
              description: WSL10n.setting("explainer.notch.origin.ipad.ax", zh: "静图：选了 iPad，刘海提示菜单要两指点按。"))
    }

    /// 之前常用 · 一直用 Mac：静图，刘海多半不开口。
    static var originMac: ExplainerSpec {
        still(id: "notch.origin.mac",
              deviceText: WSL10n.setting("explainer.notch.origin.mac.text", zh: "一直用 Mac"),
              initial: [.windowA: window0],
              description: WSL10n.setting("explainer.notch.origin.mac.ax", zh: "静图：一直用 Mac，刘海多半不开口。"))
    }
}

extension ExplainerRow {
    /// 刘海页每一行演哪一段（没列出的行——番茄钟、日程、音量和亮度——回到页默认）。
    enum Notch {
        static var alerts: ExplainerRow { .loop(ExplainerScenes.notchAlert) }
        static var activities: ExplainerRow { .loop(ExplainerScenes.notchLiveActivity) }
        static var nowPlaying: ExplainerRow { .loop(ExplainerScenes.notchNowPlaying) }
        static var downloads: ExplainerRow { .loop(ExplainerScenes.notchDownload) }
        static var deviceBattery: ExplainerRow { .loop(ExplainerScenes.notchDeviceBattery) }
        static var mergedRow: ExplainerRow { .loop(ExplainerScenes.notchMergedRow) }
        static var hoverGuard: ExplainerRow { .loop(ExplainerScenes.notchHoverGuard) }
        static var fileShelf: ExplainerRow { .loop(ExplainerScenes.notchFileShelf) }
        /// 分段顺序同 SwitcherOrigin.answers：Windows / iPad / 一直用 Mac。
        static var origin: ExplainerRow {
            .options([ExplainerScenes.originWindows, ExplainerScenes.originIpad, ExplainerScenes.originMac])
        }
    }
}
