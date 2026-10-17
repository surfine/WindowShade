// 设置 → 高级（含 高级 → 实验）的讲解（1.0.18 工作单 9；逐页表“高级”和“实验”，稿《首次打开 1.0.17 小样》E 节）。
// 高级页：界面语言（静图）、减少动态效果（静图，停在关键帧）、导出诊断信息（静图）；其余行跟页默认。
// 实验：离开就锁、普通窗口实时预览、跟着声音跳、回来时说一下离开期间的事、拷贝进度、猜你从哪来，各演各的；
// 开关默认关着，由状态机降灰并标“关着”。设备的电量在 1.0.18 搬回刘海页，场景在刘海页那份。
// 照搬稿里的帧数据，坐标是 312 × 200 的块。场景名带 adv 前缀，免得和别的页重名。

import CoreGraphics
import Foundation

extension ExplainerPage {
    /// 页默认：界面语言（逐页表“高级”的第一行）。
    static var advanced: ExplainerPage { ExplainerPage(id: "advanced", pageDefault: ExplainerScenes.advLanguage) }
}

extension ExplainerRow {
    /// 高级页每一行演哪一段。恢复默认值、诊断日志、导出设置、导入设置、欢迎使用、报告问题都跟页默认（不换画）。
    enum Advanced {
        static var language: ExplainerRow { .still(ExplainerScenes.advLanguage) }
        static var reduceMotion: ExplainerRow { .still(ExplainerScenes.advReduceMotion) }
        static var exportDiagnostics: ExplainerRow { .still(ExplainerScenes.advDiagnostics) }
        // 实验。
        static var awayLock: ExplainerRow { .loop(ExplainerScenes.advAwayLock) }
        static var livePreview: ExplainerRow { .loop(ExplainerScenes.advLivePreview) }
        static var followSound: ExplainerRow { .loop(ExplainerScenes.advBeat) }
        static var awaySummary: ExplainerRow { .loop(ExplainerScenes.advAwaySummary) }
        static var copyProgress: ExplainerRow { .loop(ExplainerScenes.advCopyProgress) }
        static var originGuess: ExplainerRow { .loop(ExplainerScenes.advOriginGuess) }
        /// 旁人靠近（稿里标了“照行文案画”，还没定稿）：先跟页默认，不画没定的东西。
        static var bystander: ExplainerRow { .pageDefault }
    }
}

extension ExplainerScenes {
    // MARK: 高级

    /// 界面语言（静图）：菜单栏图标和它的菜单，左块写三种文字。
    static var advLanguage: ExplainerSpec {
        still(id: "adv.language",
              deviceText: WSL10n.setting("explainer.adv.language.text", zh: "简体中文 · English · 繁體中文"),
              initial: [.windowA: window0, .menuBarIcon: P(opacity: 1), .menu: P(opacity: 1)],
              description: WSL10n.setting("explainer.adv.language.ax", zh: "演示：界面语言切换后立即生效。"))
    }

    /// 减少动态效果（静图）：讲解停在关键帧；系统开着减少动态效果时由状态机叠上箭头。画面借双击收起的关键帧。
    static var advReduceMotion: ExplainerSpec {
        doubleClickRoll.variant(id: "adv.reduce",
                                description: WSL10n.setting("explainer.adv.reduce.ax", zh: "演示：打开减少动态效果后，讲解停在关键帧，用箭头标出怎么动。")) { spec in
            spec.forceStill = true
        }
    }

    /// 导出诊断信息（静图）：存成这台 Mac 上的一个文件夹，不会自动发出。
    static var advDiagnostics: ExplainerSpec {
        still(id: "adv.diagnostics",
              deviceText: WSL10n.setting("explainer.adv.diagnostics.text", zh: "导出诊断信息…"),
              initial: [.cover: P(opacity: 1, text: WSL10n.setting("explainer.adv.diagnostics.cover", zh: "文件夹在这台 Mac 上 · 不会自动发出").shown)],
              description: WSL10n.setting("explainer.adv.diagnostics.ax", zh: "演示：诊断信息存成这台 Mac 上的一个文件夹，不会自动发出。"))
    }

    // MARK: 实验

    /// 离开就锁：随身设备走远了，倒数 10 秒后锁屏。左块的字跟着变。
    static var advAwayLock: ExplainerSpec {
        let near = WSL10n.setting("explainer.adv.awayLock.near", zh: "iPhone 在身边")
        let far = WSL10n.setting("explainer.adv.awayLock.far", zh: "iPhone 走远了")
        let back = WSL10n.setting("explainer.adv.awayLock.back", zh: "回来了")
        let countdown = WSL10n.setting("explainer.adv.awayLock.countdown", zh: "10 秒后锁屏")
        let locked = WSL10n.setting("explainer.adv.awayLock.locked", zh: "已锁定")
        return ExplainerSpec(
            id: "adv.awayLock", device: .text,
            initial: [.windowA: window0, .dock: P(opacity: 1), .cover: P(opacity: 0, text: ""), .deviceText: P(opacity: 1)],
            frames: [
                F("it is nearby", .none, [:], hold: 0.8),
                F("it walks away", .fade, [.deviceText: P(text: far.shown)], hold: 0.6, story: true),
                F("countdown", .fade, [.cover: P(opacity: 1, text: countdown.shown)], hold: 1.2, story: true),
                F("locked", .fade, [.cover: P(text: locked.shown)], hold: 1.4, key: true),
                F("it is back", .fade, [.cover: P(opacity: 0), .deviceText: P(text: back.shown)], hold: 0.8),
                .reset,
            ],
            description: WSL10n.setting("explainer.adv.awayLock.ax", zh: "演示：随身设备走远了，倒数 10 秒后锁屏。"),
            deviceText: near)
    }

    /// 普通窗口实时预览：窗口浏览里选中的那张卡播放实时画面（借 Dock 悬停，卡换成实时样子）。
    static var advLivePreview: ExplainerSpec {
        dockHover.variant(id: "adv.livePreview",
                          description: WSL10n.setting("explainer.adv.livePreview.ax", zh: "演示：窗口浏览里选中的那张卡播放实时画面。")) { spec in
            spec.initial[.panel]?.look = .livePreview
        }
    }

    /// 跟着声音跳：刘海两边跟着音乐的节拍一下一下跳。
    static var advBeat: ExplainerSpec {
        ExplainerSpec(
            id: "adv.beat", device: .text,
            initial: [.windowA: window0, .notch: P(w: 40, h: 10), .deviceText: P(opacity: 1)],
            frames: [
                F("a beat", .pop, [.notch: P(w: 70, h: 12)], hold: 0.1, story: true),
                F("", .calm, [.notch: P(w: 56, h: 11)], hold: 0.1),
                F("another beat", .pop, [.notch: P(w: 74, h: 12)], hold: 0.1, key: true),
                F("", .calm, [.notch: P(w: 56, h: 11)], hold: 0.1),
                F("", .pop, [.notch: P(w: 68, h: 12)], hold: 0.1),
                F("", .calm, [.notch: P(w: 40, h: 10)], hold: 0.8),
            ],
            description: WSL10n.setting("explainer.adv.beat.ax", zh: "演示：刘海两边跟着音乐的节拍跳。"),
            deviceText: WSL10n.setting("explainer.adv.beat.text", zh: "音乐的节拍"))
    }

    /// 回来时说一下离开期间的事：锁屏 → 解锁，刘海说离开期间有什么变化。
    static var advAwaySummary: ExplainerSpec {
        let lockText = WSL10n.setting("explainer.adv.awaySummary.cover", zh: "锁屏")
        return ExplainerSpec(
            id: "adv.awaySummary", device: .text,
            initial: [.windowA: window0, .cover: P(opacity: 1, text: lockText.shown), .notch: P(w: 40, h: 10),
                      .notchLine: P(opacity: 0), .deviceText: P(opacity: 1)],
            frames: [
                F("locked", .none, [:], hold: 0.8),
                F("unlock", .fade, [.cover: P(opacity: 0)], hold: 0.3, story: true),
                F("the notch says what changed", .calm, [.notch: P(w: 160, h: 36, easing: .bloom), .notchLine: P(opacity: 1, easing: .fade)],
                  hold: 2.6, key: true),
                F("closes", .calm, [.notch: P(w: 40, h: 10, easing: .calm), .notchLine: P(opacity: 0, easing: .fade)], hold: 0.6, story: true),
                .reset,
            ],
            description: WSL10n.setting("explainer.adv.awaySummary.ax", zh: "演示：解锁回来，刘海说离开期间有什么变化。"),
            deviceText: WSL10n.setting("explainer.adv.awaySummary.text", zh: "锁屏 → 解锁"),
            notchLine: (WSL10n.setting("explainer.adv.awaySummary.line", zh: "离开期间"),
                        WSL10n.setting("explainer.adv.awaySummary.sub", zh: "2 扇窗口有变化")))
    }

    /// 拷贝进度：在 Finder 里拷文件时，刘海里显示拷到哪了。
    static var advCopyProgress: ExplainerSpec {
        notchSays(id: "adv.copyProgress",
                  when: WSL10n.setting("explainer.adv.copyProgress.text", zh: "在访达里拷文件"),
                  line: WSL10n.setting("explainer.adv.copyProgress.line", zh: "拷贝 3 / 10"),
                  detail: WSL10n.setting("explainer.adv.copyProgress.sub", zh: "照片 → 移动硬盘"),
                  description: WSL10n.setting("explainer.adv.copyProgress.ax", zh: "演示：在访达里拷文件时，刘海里显示拷到哪了。"),
                  size: CGSize(width: 160, height: 30))
    }

    /// 猜你从哪来：借“刘海教你”，刘海换成问一次你之前常用什么。
    static var advOriginGuess: ExplainerSpec {
        notchTeaches.variant(id: "adv.originGuess",
                             description: WSL10n.setting("explainer.adv.originGuess.ax", zh: "演示：按出 Windows 的习惯时，刘海问一次你之前常用什么。")) { spec in
            spec.notchLine = (WSL10n.setting("explainer.adv.originGuess.line", zh: "你之前常用 Windows？"),
                              WSL10n.setting("explainer.adv.originGuess.sub", zh: "点一下刘海回答"))
        }
    }
}
