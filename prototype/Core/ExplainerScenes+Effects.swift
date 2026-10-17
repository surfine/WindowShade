// 设置 → 效果 的讲解（1.0.18 工作单 9；设计稿《首次打开 1.0.17 小样》逐页表“效果”）。
// 这一页独有的场景：关掉动画时的收起（直接变成卷帘条）、桌面开合、锁屏开合、暂停效果（静图）。
// “收起窗口时的动画”开着时演通用库里的 doubleClickRoll；预览那几行没有自己的画，回到页默认。

import Foundation

extension ExplainerPage {
    /// 页默认：双击标题栏收起（稿里 fx 页的 def 是 dbl）。
    static var effects: ExplainerPage { ExplainerPage(id: "effects", pageDefault: ExplainerScenes.doubleClickRoll) }
}

extension ExplainerScenes {
    /// 关掉动画时：同一段双击，窗口高度那一帧不再走弹簧，直接变成卷帘条 / 直接展开。
    static var rollInstant: ExplainerSpec {
        doubleClickRoll.variant(
            id: "rollInstant",
            description: WSL10n.setting("explainer.rollInstant.ax", zh: "演示：关掉动画时，双击后窗口直接变成卷帘条。")
        ) { spec in
            spec.frames = spec.frames.map { frame in
                var copy = frame
                if frame.set[.windowA]?.h != nil { copy.easing = .none }
                return copy
            }
        }
    }

    /// 桌面开合：合上一半，桌面往下压一点，打开再回来。
    static var lidDesktop: ExplainerSpec {
        ExplainerSpec(
            id: "lid", device: .text,
            initial: [.windowA: window0, .dock: P(opacity: 1), .deviceText: P(opacity: 1)],
            frames: [
                F("wait", .none, [:], hold: 0.4),
                F("lid half closed: the desktop presses down", .settle, [.windowA: P(y: 52, scale: 0.9)], hold: 0.5, key: true),
                F("lid open: it comes back", .settle, [.windowA: P(y: 40, scale: 1)], hold: 0.9),
            ],
            arrows: ExplainerArrows(result: "M156 30 L156 50 M150 42 l6 8 l6 -8", ghost: windowRect),
            description: WSL10n.setting("explainer.lid.ax", zh: "演示：合上一半再打开，桌面跟着往下压一点、再回来。"),
            deviceText: WSL10n.setting("explainer.lid.device", zh: "合上盖子，再打开"))
    }

    /// 锁屏开合：锁屏画面跟着盖子缩一点再回来。
    static var lidLockScreen: ExplainerSpec {
        ExplainerSpec(
            id: "lockLid", device: .text,
            initial: [.cover: P(opacity: 1, scale: 1, text: WSL10n.text("explainer.lockLid.cover", zh: "锁屏")),
                      .deviceText: P(opacity: 1)],
            frames: [
                F("wait", .none, [:], hold: 0.4),
                F("lid half closed: the lock screen shrinks", .settle, [.cover: P(scale: 0.9)], hold: 0.5, key: true),
                F("lid open: it comes back", .settle, [.cover: P(scale: 1)], hold: 0.9),
            ],
            description: WSL10n.setting("explainer.lockLid.ax", zh: "演示：锁屏时开合盖子，锁屏画面跟着动。"),
            deviceText: WSL10n.setting("explainer.lockLid.device", zh: "锁屏时合上盖子"))
    }

    /// 暂停效果：静图，效果先停一停，讲解带也停住。
    static var pauseEffects: ExplainerSpec {
        still(id: "pauseFx", deviceText: WSL10n.setting("explainer.pauseFx.device", zh: "暂停"),
              initial: [.windowA: window0],
              description: WSL10n.setting("explainer.pauseFx.ax", zh: "静图：效果都先停一停，讲解带也停住。"))
    }
}

extension ExplainerRow {
    /// 效果页每一行演哪一段。
    enum Effects {
        static var windows: ExplainerRow { .loop(ExplainerScenes.doubleClickRoll, offScene: ExplainerScenes.rollInstant) }
        static var desktop: ExplainerRow { .loop(ExplainerScenes.lidDesktop) }
        static var lockScreen: ExplainerRow { .loop(ExplainerScenes.lidLockScreen) }
        static var pause: ExplainerRow { .still(ExplainerScenes.pauseEffects) }
        /// 预览对象 / 样式 / 进度：没有自己的画，回到页默认。
        static var preview: ExplainerRow { .pageDefault }
    }
}
