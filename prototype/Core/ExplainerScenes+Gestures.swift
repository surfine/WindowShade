// 设置 → 手势 的讲解（1.0.18 工作单 9 的参照实现，别的页照这个文件的样子写自己的 ExplainerScenes+<页名>.swift）。
// 这一页用到的场景全在通用库里；这里只定这一页的页默认，和每一行演哪一段（稿 E 节逐页表“手势”）。

import Foundation

extension ExplainerPage {
    /// 页默认：标题栏手势往上滑收起（第一段“收起与展开”的第一行）。
    static var gestures: ExplainerPage { gestures(segment: 0) }

    /// 手势页分成四段（就是四个分组：收起与展开、刘海、排布、窗口浏览）；每段的页默认是这一段第一行。
    static func gestures(segment: Int) -> ExplainerPage {
        switch segment {
        case 1: return ExplainerPage(id: "gestures.notch", pageDefault: ExplainerScenes.tuckIntoNotch)
        case 2: return ExplainerPage(id: "gestures.arrange", pageDefault: ExplainerScenes.dropSplit)
        case 3: return ExplainerPage(id: "gestures.browser", pageDefault: ExplainerScenes.dockSwipe)
        default: return ExplainerPage(id: "gestures", pageDefault: ExplainerScenes.swipeUpRoll)
        }
    }
}

extension ExplainerRow {
    /// 手势页每一行（与对照表每一行）演哪一段。
    enum Gestures {
        static var titleBar: ExplainerRow { .loop(ExplainerScenes.swipeUpRoll) }
        static var doubleClick: ExplainerRow { .loop(ExplainerScenes.doubleClickRoll) }
        /// 中键收起：WindowShade 2 预览行，没有自己的画，回到页默认。
        static var middleFold: ExplainerRow { .pageDefault }
        static var tuck: ExplainerRow { .loop(ExplainerScenes.tuckIntoNotch) }
        static var overviewTuck: ExplainerRow { .loop(ExplainerScenes.overviewTuck) }
        static var dropSplit: ExplainerRow { .loop(ExplainerScenes.dropSplit) }
        static var stripDrag: ExplainerRow { .loop(ExplainerScenes.stripDrag) }
        static var dockSwipe: ExplainerRow { .loop(ExplainerScenes.dockSwipe) }

        // 标题栏手势下的对照表：每个方向各演各的；捏合（撤销上次排布）没有自己的画，跟着这一行。
        static var tableUp: ExplainerRow { .loop(ExplainerScenes.swipeUpRoll) }
        static var tableDown: ExplainerRow { .loop(ExplainerScenes.swipeDownFill) }
        static var tableSide: ExplainerRow { .loop(ExplainerScenes.swipeSideHalf) }
        static var tableSpread: ExplainerRow { .loop(ExplainerScenes.magicTile) }
        static var tableStripPull: ExplainerRow { .loop(ExplainerScenes.swipeUpRoll) }
    }
}
