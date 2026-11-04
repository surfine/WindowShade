import CoreGraphics
import Foundation

// 照系统的岛（第 28 至 33 条）：尺寸只在 IslandMetrics 一处；耳朵／本体分块；长按去哪；键盘；悬停不展开。
@main
struct NotchIslandMetricsTests {
    static func main() {
        var t = TestSuite("NotchIslandMetrics")
        typealias M = IslandMetrics
        typealias I = IslandInteraction

        t.section("IM-01", "暂定尺寸（iOS）：紧凑耳 52.33 × 36.67，小圆 36.67，展开 408，提醒 84，那一排 160，格 104")
        t.expect(M.compactEarWidth == 52.33 && M.compactHeight == 36.67, "紧凑每耳 52.33 × 36.67")
        t.expect(M.compactEarWidth >= 52.33 && M.compactEarWidth <= M.compactEarMaxWidth && M.compactEarMaxWidth == 62.33, "耳宽在 52.33…62.33 内")
        t.expect(abs(36.67 / 2 /* deprecated compactCornerRadius */ - 18.335) < 0.0001, "紧凑底角 = 高的一半")
        t.expect(M.minimalDiameter == 36.67 && M.minimalDiameter == M.compactHeight, "小圆直径 36.67，和紧凑同高")
        t.expect(M.expandedWidth == 371 && M.expandedMinimumWidth == 371, "展开宽 371（iOS 原尺寸）")
        t.expect(M.alertHeight == 84 && M.teachingHeight == 112 && M.expandedMaximumHeight == 160, "提醒 84、教手势 112、上限 160")
        t.expect(M.rowHeight == 160 && M.rowCellHeight == 104, "那一排 160，格 104")
        t.expect(NotchRow.cellWidth == 124 && NotchRow.islandWidth == Double(M.expandedWidth), "格 124 宽；岛宽取自 IslandMetrics")
        t.expect(Double(M.rowCellHeight) + 2 * NotchRow.edgeMargin + 28 == Double(M.rowHeight), "格 104 + 上下边距 14 + 刘海 28 = 160")

        t.section("IM-02", "别处的数字跟着 IslandMetrics 走（真机量过只改一个文件）")
        t.expect(NotchRoomPolicy.fullSide == M.compactEarWidth && NotchRoomPolicy.legacyActivitySide == M.compactEarWidth, "耳宽规则")
        t.expect(NotchRoomPolicy.minimalWidth == M.minimalDiameter && NotchRoomPolicy.minimalGap == M.minimalGap, "最小形宽与间距")
        let size = NotchMinimalPresentation.size(for: .notched)
        t.expect(size.width == M.minimalDiameter && size.height == M.minimalDiameter, "第二个活动分出的是正圆")
        t.expect(NotchMinimalPresentation.islandExtent(for: .notched) == M.compactEarWidth, "岛伸出的宽 = 一只耳")
        let frames = NotchMinimalPresentation.frames(island: CGRect(x: 0, y: 0, width: 260.67, height: M.compactHeight), count: 1, placement: .notched)
        t.expect(frames.count == 1 && abs(frames[0].width - frames[0].height) < 0.0001 && abs(frames[0].midY - M.compactHeight / 2) < 0.0001,
                 "小圆是正圆，竖直居中在紧凑的岛上")
        t.expect(frames[0].minX == 260.67 + M.minimalGap, "离右耳 6")
        let reach = NotchMinimalPresentation.measuredReach(for: .notched)
        t.expect(abs(reach - (M.compactEarWidth + M.minimalGap + 2 * M.minimalDiameter + M.minimalGap)) < 0.0001, "量空位 = 耳宽 + 间距 + 两颗小圆")

        t.section("IM-03", "点：耳朵打开那件活动的 App，本体回到主屏幕")
        let width: CGFloat = 260.67, notch: CGFloat = 156
        t.expect(I.region(x: 10, islandWidth: width, notchWidth: notch) == .leadingEar, "左耳")
        t.expect(I.region(x: width - 10, islandWidth: width, notchWidth: notch) == .trailingEar, "右耳")
        t.expect(I.region(x: width / 2, islandWidth: width, notchWidth: notch) == .body, "本体")
        let edge = (width - notch) / 2
        t.expect(I.region(x: edge, islandWidth: width, notchWidth: notch) == .body && I.region(x: edge + notch, islandWidth: width, notchWidth: notch) == .body,
                 "刘海的左右边缘算本体")
        t.expect(I.region(x: edge - 0.01, islandWidth: width, notchWidth: notch) == .leadingEar, "差一点出刘海就是耳朵")
        t.expect(I.tap(in: .leadingEar, earsAreActivity: true) == .openActivity && I.tap(in: .trailingEar, earsAreActivity: true) == .openActivity,
                 "两只耳朵都打开 App")
        t.expect(I.tap(in: .body, earsAreActivity: true) == .goHome, "本体回主屏幕")
        t.expect(I.tap(in: .leadingEar, earsAreActivity: false) == .goHome, "不是活动的两耳（窗口个数）：和本体一样回主屏幕")

        t.section("IM-04", "长按：有任何东西就展开那一排，什么都没有才去启动台“今天”")
        t.expect(I.longPress(rowIsEmpty: false) == .expandRow, "只收着窗口也展开")
        t.expect(I.longPress(rowIsEmpty: true) == .openToday, "完全空才打开今天")

        t.section("IM-05", "键盘：空格 = 长按，Return = 点；带 ⌘ ⌃ ⌥ 不算")
        t.expect(I.key(forKeyCode: 49, hasCommandModifiers: false) == .longPress, "空格")
        t.expect(I.key(forKeyCode: 36, hasCommandModifiers: false) == .press && I.key(forKeyCode: 76, hasCommandModifiers: false) == .press, "Return、Enter")
        t.expect(I.key(forKeyCode: 49, hasCommandModifiers: true) == nil && I.key(forKeyCode: 0, hasCommandModifiers: false) == nil, "别的键不接")

        t.section("IM-06", "悬停：指针停上来只通知（教一下，不展开），展开着才立刻通知")
        t.expect(I.hoverNotifiesImmediately(isExpanded: true) && !I.hoverNotifiesImmediately(isExpanded: false), "展开着立刻通知，其余等停够")

        t.finish()
    }
}
