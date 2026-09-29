// 画中画（PiP）：把一扇真窗做成屏幕角上的一小块实时画面（纯计算，不碰任何窗口）。
//
// 规则：三种大小按来源的宽高比缩到一块；拖完按惯性推算面板中心会飘到哪，飘过左右屏幕边就整块推出去
// 藏起来、只留一个小标签，否则看落在哪个象限就贴哪个角；同一个角上已经有的几块竖直摞成一列。
// 面板用 Cocoa 屏幕坐标（原点左下、y 向上）：area 是屏幕可见范围，screen 是整块屏。
// 只有 parked、restored 两条算的是真窗该躲到哪、回到哪，用 AX 坐标（原点左上、y 向下）。

import CoreGraphics

/// 屏幕四个角：名字里的上下按 Cocoa 坐标（y 向上）说。
enum PiPCorner: CaseIterable, Equatable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// 三档大小，rawValue 就是 widths 的下标。
enum PiPSizeLevel: Int, CaseIterable {
    case small, medium, large
}

/// 左右两条屏幕边（藏起来的时候用）。
enum PiPSide: Equatable {
    case left, right
}

/// 松手之后面板去哪：贴某个角，或者藏到某条边上。
enum PiPLanding: Equatable {
    case corner(PiPCorner)
    case stash(PiPSide)
}

enum PiPLayout {
    /// 离可见范围的边留多少。
    static let inset: CGFloat = 16
    /// 同一个角上两块之间留多少。
    static let spacing: CGFloat = 12
    /// 三档的宽度，按 PiPSizeLevel.rawValue 取。
    static let widths: [CGFloat] = [240, 360, 520]
    /// 藏起来时留在屏幕边上的小标签。
    static let tabSize = CGSize(width: 16, height: 76)

    /// 按来源（整个窗口，或者窗口里选中的一块）的宽高比算出面板尺寸。
    /// 先按档取宽、按比例算高；高得离谱就压到可见高度的六成再反推宽；宽高都不许小过 120×60。
    static func size(source: CGSize, level: PiPSizeLevel, area: CGRect) -> CGSize {
        guard source.width > 0, source.height > 0, area.width > 0, area.height > 0 else { return .zero }
        let widthCap = min(widths[level.rawValue], area.width * 0.45)    // 再宽也不超过可见宽度的四成半
        let heightCap = area.height * 0.6                               // 再高也不超过可见高度的六成
        var width = widthCap
        var height = width * source.height / source.width
        if height > heightCap {
            height = heightCap
            width = height * source.width / source.height
        }
        // 最小尺寸：能保持比例就把另一边撑开，撑不下（超过上限）就只把这一边顶到最小。
        if height < 60 {
            let grown = 60 * source.width / source.height
            if grown <= widthCap { width = grown }
            height = 60
        }
        if width < 120 {
            let grown = 120 * source.height / source.width
            if grown <= heightCap { height = grown }
            width = 120
        }
        return CGSize(width: width.rounded(), height: height.rounded())
    }

    /// 某一角上的面板位置：离可见边 inset，同一个角已经有几块就顺着竖直方向往后摞。
    /// stackedBefore 是这些块的尺寸，贴着角的那个排最前；上面的角往下摞，下面的角往上摞。
    static func frame(corner: PiPCorner, size: CGSize, area: CGRect, stackedBefore: [CGSize] = []) -> CGRect {
        let offset = stackedBefore.reduce(0) { $0 + $1.height + spacing }
        let x: CGFloat
        switch corner {
        case .topLeft, .bottomLeft: x = area.minX + inset
        case .topRight, .bottomRight: x = area.maxX - inset - size.width
        }
        let y: CGFloat
        switch corner {
        case .topLeft, .topRight: y = area.maxY - inset - size.height - offset
        case .bottomLeft, .bottomRight: y = area.minY + inset + offset
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// 点在哪个角：拿可见范围的中心分四个象限，正好压在中线上算右边、上边。
    static func corner(nearest point: CGPoint, area: CGRect) -> PiPCorner {
        if point.y >= area.midY {
            return point.x < area.midX ? .topLeft : .topRight
        }
        return point.x < area.midX ? .bottomLeft : .bottomRight
    }

    /// 松手：面板中心带着甩出去的速度按惯性再推算一段，飘过左右屏幕边就藏起来，否则看落在哪个角。
    static func landing(frame: CGRect, velocity: CGVector, area: CGRect, screen: CGRect) -> PiPLanding {
        let projected = CGPoint(x: frame.midX + CGFloat(FluidMotion.projection(velocity: Double(velocity.dx))),
                                y: frame.midY + CGFloat(FluidMotion.projection(velocity: Double(velocity.dy))))
        let margin = frame.width * 0.25
        if projected.x < screen.minX + margin { return .stash(.left) }
        if projected.x > screen.maxX - margin { return .stash(.right) }
        return .corner(corner(nearest: projected, area: area))
    }

    /// 藏起来的整块面板：完全推出屏幕那一边（一点都看不见），y 和尺寸不动。
    static func stashedFrame(_ frame: CGRect, side: PiPSide, screen: CGRect) -> CGRect {
        let x = side == .left ? screen.minX - frame.width : screen.maxX
        return CGRect(x: x, y: frame.minY, width: frame.width, height: frame.height)
    }

    /// 藏起来时留在屏幕边上的小标签：贴着那一边，竖直中心对着 midY，但不许跑出可见范围。
    static func tabFrame(side: PiPSide, midY: CGFloat, area: CGRect, screen: CGRect) -> CGRect {
        let x = side == .left ? screen.minX : screen.maxX - tabSize.width
        let y = min(max(midY - tabSize.height / 2, area.minY), area.maxY - tabSize.height)
        return CGRect(x: x, y: y, width: tabSize.width, height: tabSize.height)
    }

    /// 选中一块：把面板里的选择框换算到窗口自己的坐标（y 翻过来），裁进正在显示的范围，
    /// 再保证不小过 60×40 点。选择框小得像个点击（不到 8×8 面板点）就返回 nil。
    static func crop(selection: CGRect, viewSize: CGSize, showing: CGRect) -> CGRect? {
        guard selection.width >= 8, selection.height >= 8, viewSize.width > 0, viewSize.height > 0 else { return nil }
        let scaleX = showing.width / viewSize.width
        let scaleY = showing.height / viewSize.height
        var rect = CGRect(x: showing.minX + selection.minX * scaleX,
                          y: showing.minY + (viewSize.height - selection.maxY) * scaleY,
                          width: selection.width * scaleX,
                          height: selection.height * scaleY)
        rect = rect.intersection(showing)
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return nil }
        // 最小 60×40：先围着选择框中心长，长完再整体挪回 showing 里面。
        if rect.width < 60 {
            rect.origin.x -= (60 - rect.width) / 2
            rect.size.width = 60
        }
        if rect.height < 40 {
            rect.origin.y -= (40 - rect.height) / 2
            rect.size.height = 40
        }
        if rect.minX < showing.minX { rect.origin.x = showing.minX }
        if rect.maxX > showing.maxX { rect.origin.x = showing.maxX - rect.width }
        if rect.minY < showing.minY { rect.origin.y = showing.minY }
        if rect.maxY > showing.maxY { rect.origin.y = showing.maxY - rect.height }
        return rect
    }

    /// 真窗进画中画之后停在哪（AX 坐标，y 向下）：推到离得近的那一边屏幕外，只留 peek 点露在里面。
    /// 那一边外面有别的屏幕（others，整块屏）、推过去会露在那块屏上，就换另一边；两边都会露出来返回 nil。
    /// y 夹在这块屏的上下之间，露着的那 peek 点始终落在这块屏上。
    static func parked(_ window: CGRect, screenAX: CGRect, others: [CGRect] = [], peek: CGFloat = 2) -> CGRect? {
        let y = min(max(window.minY, screenAX.minY), max(screenAX.minY, screenAX.maxY - window.height))
        let left = CGRect(x: screenAX.minX - window.width + peek, y: y, width: window.width, height: window.height)
        let right = CGRect(x: screenAX.maxX - peek, y: y, width: window.width, height: window.height)
        let sides = window.midX < screenAX.midX ? [left, right] : [right, left]
        return sides.first { spot in
            !others.contains { other in
                let hit = other.intersection(spot)
                return !hit.isNull && hit.width > 2 && hit.height > 2
            }
        }
    }

    /// 回到原处时放回的离边距离（原处已经不在任何一块屏幕上时才用）。
    static let restoreMargin: CGFloat = 10

    /// 回到原处落在哪（AX 坐标，y 向下）：标题栏那一截还在某块屏幕的可见范围里就原样放回；
    /// 落不到任何一块上了（那块显示器拔掉了、换了排列），就挪进和它重叠最多的那块（都不重叠就挑最近的），
    /// 大小不变，离边留 10 点。
    static func restored(_ window: CGRect, areas: [CGRect]) -> CGRect {
        let titleBar = CGRect(x: window.minX, y: window.minY, width: window.width, height: min(window.height, 28))
        let onScreen = areas.contains { area in
            let hit = area.intersection(titleBar)
            return !hit.isNull && hit.width >= 40 && hit.height >= 1
        }
        guard !onScreen else { return window }
        func overlap(_ area: CGRect) -> CGFloat {
            let hit = area.intersection(window)
            return hit.isNull ? 0 : hit.width * hit.height
        }
        func distance(_ area: CGRect) -> CGFloat { hypot(area.midX - window.midX, area.midY - window.midY) }
        let target = areas.max { overlap($0) < overlap($1) }.flatMap { overlap($0) > 0 ? $0 : nil }
            ?? areas.min { distance($0) < distance($1) }
        guard let area = target else { return window }
        let m = restoreMargin
        return CGRect(x: min(max(window.minX, area.minX + m), max(area.minX + m, area.maxX - window.width - m)),
                      y: min(max(window.minY, area.minY + m), max(area.minY + m, area.maxY - window.height - m)),
                      width: window.width, height: window.height)
    }
}
