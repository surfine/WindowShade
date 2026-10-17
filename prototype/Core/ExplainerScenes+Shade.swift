// 设置 → 卷帘 的讲解（1.0.18 工作单 9；逐页表“卷帘”，稿《首次打开 1.0.17 小样》E 节）。
// 这一页独有的场景写在这里：看一眼、分屏把手、窗口之间留缝、走到一列时、放得下就居中、记住列宽、
// 收起后的样子（统一标题栏 / 缩略图两种）、浮在其他窗口上面、卷帘条半透明、iPhone 画面放到整块屏。
// 双击收起（“跟原来一样”）用通用库的 `doubleClickRoll`。照搬稿里的帧数据，坐标是 312 × 200 的块。

import CoreGraphics
import Foundation

extension ExplainerPage {
    /// 页默认：看一眼（逐页表“卷帘”的第一行）。
    static var shade: ExplainerPage { ExplainerPage(id: "shade", pageDefault: ExplainerScenes.glance) }
}

extension ExplainerRow {
    /// 卷帘页每一行演哪一段。声音三行、接收器地址、静音口令都跟页默认（不换画）。
    enum Shade {
        static var glance: ExplainerRow { .loop(ExplainerScenes.glance) }
        static var gap: ExplainerRow { .options([ExplainerScenes.gap0, ExplainerScenes.gap4, ExplainerScenes.gap10]) }
        static var splitHandle: ExplainerRow { .loop(ExplainerScenes.splitHandle) }
        /// 三个选项顺序同 `ScrollStrip.Centering.allCases`：贴边、居中、放不下才居中。
        static var centering: ExplainerRow { .options([ExplainerScenes.colEdge, ExplainerScenes.colCenter, ExplainerScenes.colOverflow]) }
        static var centerWhenFits: ExplainerRow { .still(ExplainerScenes.centerFit) }
        static var rememberWidths: ExplainerRow { .still(ExplainerScenes.rememberWidths) }
        /// 三个选项顺序同 `collapseAppearanceChoices`：跟原来一样、统一标题栏、缩略图。
        static var appearance: ExplainerRow {
            .options([ExplainerScenes.doubleClickRoll, ExplainerScenes.rollUnified, ExplainerScenes.rollThumbnail])
        }
        static var floating: ExplainerRow { .loop(ExplainerScenes.floatOnTop) }
        static var translucent: ExplainerRow { .still(ExplainerScenes.translucentBar) }
        static var sound: ExplainerRow { .pageDefault }
        static var iPhoneFullScreen: ExplainerRow { .loop(ExplainerScenes.iPhoneFullScreen) }
        static var plain: ExplainerRow { .pageDefault }
    }
}

extension ExplainerScenes {
    /// 收成卷帘条（稿里的 A0 收起后）。
    private static var strip: P { P(x: 70, y: 40, w: 172, h: 10, opacity: 1, scale: 1, rolled: true) }

    // MARK: 触发

    /// 看一眼：指针停在卷帘条上，窗口内容垂下来；移开收回。
    static var glance: ExplainerSpec {
        ExplainerSpec(
            id: "glance", device: .point,
            initial: [.windowA: strip, .windowB: P(x: 70, y: 52, w: 172, h: 0, opacity: 0, scale: 1),
                      .pointer: P(x: 236, y: 160, opacity: 1), .finger1: P(x: 190, y: 120, opacity: 0, pressed: false)],
            frames: [
                F("finger down", .fade, [.finger1: P(opacity: 1)]),
                F("pointer rests on the bar", .calm, [.pointer: P(x: 150, y: 44), .finger1: P(x: 150, y: 84)], hold: 0.12, story: true),
                F("it hangs down for a look", .calm, [.windowB: P(h: 104, opacity: 1)], hold: 1.4, key: true),
                F("move away: it goes back", .calm, [.pointer: P(x: 236, y: 160), .finger1: P(x: 190, y: 120),
                                                      .windowB: P(h: 0, opacity: 0)], hold: 0.4, story: true),
                F("", .fade, [.finger1: P(opacity: 0)], hold: 0.6),
            ],
            arrows: ExplainerArrows(device: "M190 120 L154 88", result: "M156 60 L156 140 M150 132 l6 8 l6 -8"),
            description: WSL10n.setting("explainer.glance.ax", zh: "演示：指针停在卷帘条上，窗口内容垂下来给你看一眼；移开就收回。"))
    }

    // MARK: 排布

    /// 窗口之间留缝（静图）：两扇并排，缝 g。
    private static func gapScene(_ g: Double, id: String, text: SettingsText, description: SettingsText) -> ExplainerSpec {
        let w = (312 - 3 * g) / 2
        let h = 190 - 2 * g - 10
        return still(id: id, deviceText: text,
                     initial: [.windowA: P(x: g, y: 10 + g, w: w, h: h, opacity: 1, scale: 1),
                               .windowB: P(x: 2 * g + w, y: 10 + g, w: w, h: h, opacity: 1, scale: 1)],
                     description: description)
    }

    static var gap0: ExplainerSpec {
        gapScene(0, id: "gap0", text: WSL10n.setting("explainer.gap0.text", zh: "窗口之间留缝 · 不留"),
                 description: WSL10n.setting("explainer.gap0.ax", zh: "演示：两扇并排的窗口之间不留缝。"))
    }
    static var gap4: ExplainerSpec {
        gapScene(4, id: "gap4", text: WSL10n.setting("explainer.gap4.text", zh: "窗口之间留缝 · 窄"),
                 description: WSL10n.setting("explainer.gap4.ax", zh: "演示：两扇并排的窗口之间留窄缝。"))
    }
    static var gap10: ExplainerSpec {
        gapScene(10, id: "gap10", text: WSL10n.setting("explainer.gap10.text", zh: "窗口之间留缝 · 宽"),
                 description: WSL10n.setting("explainer.gap10.ax", zh: "演示：两扇并排的窗口之间留宽缝。"))
    }

    /// 分屏把手：拖中间那根竖条，两扇一起变宽变窄。
    static var splitHandle: ExplainerSpec {
        ExplainerSpec(
            id: "split", device: .press,
            initial: [.windowA: P(x: 2, y: 12, w: 153, h: 168, opacity: 1, scale: 1),
                      .windowB: P(x: 157, y: 12, w: 153, h: 168, opacity: 1, scale: 1),
                      .pointer: P(x: 156, y: 100, opacity: 1), .finger1: P(x: 156, y: 120, opacity: 0, pressed: false)],
            frames: [
                F("hold the divider", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.15, story: true),
                F("drag left", .calm, [.finger1: P(x: 116, easing: .calm), .pointer: P(x: 106, easing: .calm),
                                       .windowA: P(w: 103, easing: .settle), .windowB: P(x: 107, w: 203, easing: .settle)],
                  hold: 0.8, key: true),
                F("drag back", .calm, [.finger1: P(x: 156, easing: .calm), .pointer: P(x: 156, easing: .calm),
                                       .windowA: P(w: 153, easing: .settle), .windowB: P(x: 157, w: 153, easing: .settle)], story: true),
                F("let go", .tap, [.finger1: P(opacity: 0, pressed: false)], hold: 0.8),
            ],
            arrows: ExplainerArrows(device: "M156 120 L116 120 M124 114 l-8 6 l8 6", result: "M156 100 L106 100 M114 94 l-8 6 l8 6"),
            description: WSL10n.setting("explainer.split.ax", zh: "演示：拖中间那根竖条，两扇窗口一起变宽变窄。"))
    }

    /// 走到一列时 · 贴边（静图）：走到的那一列贴着屏幕边停。
    static var colEdge: ExplainerSpec {
        still(id: "colEdge", deviceText: WSL10n.setting("settings.shade.centering.edge", zh: "贴边"),
              initial: [.windowA: P(x: -70, y: 16, w: 120, h: 166, opacity: 1, scale: 1),
                        .windowB: P(x: 54, y: 16, w: 120, h: 166, opacity: 1, scale: 1),
                        .windowC: P(x: 178, y: 16, w: 132, h: 166, opacity: 1, scale: 1)],
              description: WSL10n.setting("explainer.colEdge.ax", zh: "演示：走到的那一列贴着屏幕边停。"))
    }

    private static var centeredColumns: ExplainerState {
        [.windowA: P(x: -28, y: 16, w: 120, h: 166, opacity: 1, scale: 1),
         .windowB: P(x: 96, y: 16, w: 120, h: 166, opacity: 1, scale: 1),
         .windowC: P(x: 220, y: 16, w: 120, h: 166, opacity: 1, scale: 1)]
    }

    /// 走到一列时 · 居中（静图）：走到的那一列停在屏幕正中。
    static var colCenter: ExplainerSpec {
        still(id: "colCenter", deviceText: WSL10n.setting("settings.shade.centering.center", zh: "居中"),
              initial: centeredColumns,
              description: WSL10n.setting("explainer.colCenter.ax", zh: "演示：走到的那一列停在屏幕正中。"))
    }

    /// 走到一列时 · 放不下才居中（静图）：三列放不下一屏时居中，放得下就贴边。稿里只画了前两种，这里补第三种。
    static var colOverflow: ExplainerSpec {
        still(id: "colOverflow", deviceText: WSL10n.setting("settings.shade.centering.fits", zh: "放不下才居中"),
              initial: centeredColumns,
              description: WSL10n.setting("explainer.colOverflow.ax", zh: "演示：几列放不下一屏时，走到的那一列停在屏幕正中；放得下就贴边。"))
    }

    /// 放得下就居中（静图）：两列加起来不到一屏，整组在正中。
    static var centerFit: ExplainerSpec {
        still(id: "centerFit", deviceText: nil,
              initial: [.windowA: P(x: 46, y: 16, w: 108, h: 166, opacity: 1, scale: 1),
                        .windowB: P(x: 158, y: 16, w: 108, h: 166, opacity: 1, scale: 1)],
              description: WSL10n.setting("explainer.centerFit.ax", zh: "演示：两列加起来不到一屏，整组放在正中。"))
    }

    /// 记住每个 App 的列宽（静图）：同一个 App 下次进卷轴还是那么宽。
    static var rememberWidths: ExplainerSpec {
        still(id: "rememberW", deviceText: nil,
              initial: [.windowA: P(x: 6, y: 16, w: 80, h: 166, opacity: 1, scale: 1),
                        .windowB: P(x: 90, y: 16, w: 140, h: 166, opacity: 1, scale: 1),
                        .windowC: P(x: 234, y: 16, w: 80, h: 166, opacity: 1, scale: 1)],
              description: WSL10n.setting("explainer.rememberW.ax", zh: "演示：同一个 App 下次进卷轴还是那么宽。"))
    }

    // MARK: 外观

    /// 收起后统一成一样的标题栏：收起那一帧换样子，展开回原样。
    static var rollUnified: ExplainerSpec {
        doubleClickRoll.variant(id: "appUni", description: WSL10n.setting("explainer.appUni.ax", zh: "演示：收起后统一成一样的标题栏。")) { spec in
            for index in spec.frames.indices {
                guard let h = spec.frames[index].set[.windowA]?.h else { continue }
                spec.frames[index].set[.windowA]?.look = h < 20 ? .unified : .plain
            }
        }
    }

    /// 收起后在原处缩成一张缩略图：收起那一帧缩到右下，展开回原样。
    static var rollThumbnail: ExplainerSpec {
        doubleClickRoll.variant(id: "appThumb", description: WSL10n.setting("explainer.appThumb.ax", zh: "演示：收起后在原处缩成一张缩略图。")) { spec in
            for index in spec.frames.indices {
                guard let h = spec.frames[index].set[.windowA]?.h else { continue }
                spec.frames[index].set[.windowA] = h < 20
                    ? P(x: 214, y: 124, w: 88, h: 62, rolled: false, look: .thumbnail)
                    : P(x: 70, y: 40, w: 172, h: 118, rolled: false, look: .plain)
            }
            spec.arrows.result = "M156 100 L250 150 M240 150 l10 0 l0 -10"
        }
    }

    /// 浮在其他窗口上面：点后面那扇窗口，它到前面来，卷帘条仍在最上面。
    static var floatOnTop: ExplainerSpec {
        ExplainerSpec(
            id: "floatTop", device: .click,
            initial: [.windowB: P(x: 30, y: 30, w: 200, h: 140, opacity: 1, scale: 1, highlighted: false),
                      .windowA: P(x: 120, y: 20, w: 172, h: 10, opacity: 1, scale: 1, rolled: true),
                      .pointer: P(x: 260, y: 160, opacity: 1), .finger1: P(x: 156, y: 96, opacity: 0, pressed: false)],
            frames: [
                F("pointer to the window behind", .calm, [.pointer: P(x: 80, y: 100)], story: true),
                F("click", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.06),
                F("", .tap, [.finger1: P(opacity: 0, pressed: false)]),
                F("it comes forward, the bar stays on top", .calm, [.windowB: P(highlighted: true)], hold: 1.2, key: true),
                F("", .calm, [.windowB: P(highlighted: false), .pointer: P(x: 260, y: 160)], hold: 0.6),
            ],
            description: WSL10n.setting("explainer.floatTop.ax", zh: "演示：点一下后面那扇窗口，它到前面来，卷帘条仍在最上面。"))
    }

    /// 卷帘条半透明（静图）：后面的内容透出来。
    static var translucentBar: ExplainerSpec {
        still(id: "trans", deviceText: nil,
              initial: [.windowB: P(x: 40, y: 30, w: 200, h: 130, opacity: 1, scale: 1),
                        .windowA: P(x: 90, y: 60, w: 172, h: 10, opacity: 0.55, scale: 1, rolled: true)],
              description: WSL10n.setting("explainer.trans.ax", zh: "演示：卷帘条半透明，后面的内容透出来。"))
    }

    // MARK: 实验

    /// 把 iPhone 的画面放到整块屏：长按刘海，整块屏变成 iPhone 的画面；按 Esc 回来。
    static var iPhoneFullScreen: ExplainerSpec {
        ExplainerSpec(
            id: "iphoneFull", device: .press,
            initial: [.windowA: window0, .cover: P(opacity: 0, text: WSL10n.setting("explainer.iphoneFull.cover", zh: "iPhone 的画面").shown),
                      .pointer: P(x: 156, y: 5, opacity: 1), .finger1: P(x: 156, y: 96, opacity: 0, pressed: false)],
            frames: [
                F("long-press the notch", .tap, [.finger1: P(opacity: 1, pressed: true)], hold: 0.6, story: true),
                F("full screen", .fade, [.cover: P(opacity: 1)], hold: 1.4, key: true),
                F("Esc: back to the desktop", .fade, [.cover: P(opacity: 0), .finger1: P(opacity: 0, pressed: false)], hold: 0.8, story: true),
            ],
            description: WSL10n.setting("explainer.iphoneFull.ax", zh: "演示：长按刘海，整块屏变成 iPhone 的画面；按 Esc 回来。"))
    }
}
