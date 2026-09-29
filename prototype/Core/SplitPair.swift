// 两扇窗正好占满一块屏的两半时，中间有一条可以拖的分隔条（纯计算，不碰窗口）。
// 拖中间这条：两边一起变宽变窄；松手吸附到 ⅓ / ½ / ⅔；甩到边上就让一扇离开。
// 坐标是 AX 坐标：左上角为原点、y 向下。area 是屏幕可用区域；gap 是 ArrangeGap 的窗口间距规则：
// 贴着屏幕边的那一条边让出一整道缝，两扇窗面对面那两条边各让半道（合起来正好一道）。

import CoreGraphics

/// 一扇窗：编号 + 现在的位置。
struct SplitWindow: Equatable {
    let id: UInt32
    let frame: CGRect
}

/// 认好的一对：前（左 / 上）那扇、后（右 / 下）那扇、朝哪个方向分、哪块屏、缝在中间哪里。
struct SplitPair: Equatable {
    enum Axis: Equatable { case sideBySide, stacked }   // sideBySide：竖条（x = seam）；stacked：横条（y = seam）
    let leading: SplitWindow   // 左（并排）或上（上下）
    let trailing: SplitWindow  // 右或下
    let axis: Axis
    let area: CGRect
    /// 两扇窗之间空档的中点（sideBySide 是 x，stacked 是 y）。
    let seam: CGFloat
}

enum SplitLayout {
    static let tolerance: CGFloat = 6
    /// 最窄一边（点）：拖中间那条时再往里就有阻力。
    static let minimumSide: CGFloat = 320
    /// 松手时推算的落点离屏幕边不到这么多（占整块的比例），那一扇就离开。
    static let dismissFraction: CGFloat = 0.15

    /// windows 按前后排列（0 是最前面），里面可能还有别的屏上的窗。
    /// 取头两扇盖住自己一半以上、落在这块屏里的窗：正好占满两半才算一对，先试左右再试上下。
    static func pair(frontToBack windows: [SplitWindow], area: CGRect, gap: CGFloat) -> SplitPair? {
        let onScreen = windows.filter { mostlyOnScreen($0, area: area) }
        guard onScreen.count >= 2 else { return nil }
        let (a, b) = (onScreen[0], onScreen[1])
        return sideBySide(a, b, area: area, gap: gap) ?? stacked(a, b, area: area, gap: gap)
    }

    /// 分隔条停在 seam 时两扇窗的框：外侧的边和另一方向的尺寸照旧，面对面那两条边各让半个缝。
    static func frames(_ pair: SplitPair, seam: CGFloat, gap: CGFloat) -> (leading: CGRect, trailing: CGRect) {
        switch pair.axis {
        case .sideBySide:
            let l = pair.leading.frame, r = pair.trailing.frame
            return (CGRect(x: l.minX, y: l.minY, width: seam - gap / 2 - l.minX, height: l.height),
                    CGRect(x: seam + gap / 2, y: r.minY, width: r.maxX - (seam + gap / 2), height: r.height))
        case .stacked:
            let t = pair.leading.frame, b = pair.trailing.frame
            return (CGRect(x: t.minX, y: t.minY, width: t.width, height: seam - gap / 2 - t.minY),
                    CGRect(x: b.minX, y: seam + gap / 2, width: b.width, height: b.maxY - (seam + gap / 2)))
        }
    }

    /// 拖着走：范围内照给的位置；越过范围就带阻力，越拉越拉不动，永远不会硬停。
    static func dragged(_ proposed: CGFloat, pair: SplitPair, gap: CGFloat) -> CGFloat {
        let limits = limits(pair, gap: gap)
        if proposed < limits.start {
            return limits.start - CGFloat(FluidMotion.rubberBand(Double(limits.start - proposed), limit: 60))
        }
        if proposed > limits.end {
            return limits.end + CGFloat(FluidMotion.rubberBand(Double(proposed - limits.end), limit: 60))
        }
        return proposed
    }

    enum Landing: Equatable { case seam(CGFloat), leadingLeaves, trailingLeaves }

    /// 松手：按惯性推一推会落到哪：快到边了就有一扇离开，否则吸附到最近的 ⅓ / ½ / ⅔。
    static func landing(seam: CGFloat, velocity: CGFloat, pair: SplitPair) -> Landing {
        let start = start(pair), end = end(pair)
        let length = end - start
        let projected = seam + CGFloat(FluidMotion.projection(velocity: Double(velocity)))
        if projected < start + length * dismissFraction { return .leadingLeaves }
        if projected > end - length * dismissFraction { return .trailingLeaves }
        let snaps = [1.0 / 3, 0.5, 2.0 / 3].map { start + length * CGFloat($0) }
        let nearest = snaps.min { abs($0 - projected) < abs($1 - projected) } ?? start + length / 2
        return .seam(nearest)
    }

    /// 分隔条沿轴能走的范围：两端各自留下贴边的整道缝、最窄的一边、再加它的半道缝。
    private static func limits(_ pair: SplitPair, gap: CGFloat) -> (start: CGFloat, end: CGFloat) {
        let margin = gap + minimumSide + gap / 2
        return (start(pair) + margin, end(pair) - margin)
    }

    private static func start(_ pair: SplitPair) -> CGFloat {
        pair.axis == .sideBySide ? pair.area.minX : pair.area.minY
    }

    private static func end(_ pair: SplitPair) -> CGFloat {
        pair.axis == .sideBySide ? pair.area.maxX : pair.area.maxY
    }

    /// 盖住自己一半以上，才算“落在这块屏上”。
    private static func mostlyOnScreen(_ w: SplitWindow, area: CGRect) -> Bool {
        let own = w.frame.width * w.frame.height
        guard own > 0 else { return false }
        let shared = w.frame.intersection(area)
        guard !shared.isNull, shared.width > 0, shared.height > 0 else { return false }
        return shared.width * shared.height >= own / 2
    }

    /// 左右并排：按 minX 分前后。两条外边贴缝、中间正好一道缝、上下都占满、各自够宽。
    private static func sideBySide(_ one: SplitWindow, _ other: SplitWindow, area: CGRect, gap: CGFloat) -> SplitPair? {
        let (l, r) = one.frame.minX <= other.frame.minX ? (one, other) : (other, one)
        guard abs(l.frame.minX - (area.minX + gap)) <= tolerance,
              abs(r.frame.maxX - (area.maxX - gap)) <= tolerance,
              abs((r.frame.minX - l.frame.maxX) - gap) <= tolerance,
              abs(l.frame.minY - (area.minY + gap)) <= tolerance,
              abs(r.frame.minY - (area.minY + gap)) <= tolerance,
              abs(l.frame.maxY - (area.maxY - gap)) <= tolerance,
              abs(r.frame.maxY - (area.maxY - gap)) <= tolerance,
              l.frame.width >= 200, r.frame.width >= 200 else { return nil }
        return SplitPair(leading: l, trailing: r, axis: .sideBySide, area: area,
                         seam: (l.frame.maxX + r.frame.minX) / 2)
    }

    /// 上下分开：同一套规则，把 x 和 y 换过来。
    private static func stacked(_ one: SplitWindow, _ other: SplitWindow, area: CGRect, gap: CGFloat) -> SplitPair? {
        let (t, b) = one.frame.minY <= other.frame.minY ? (one, other) : (other, one)
        guard abs(t.frame.minY - (area.minY + gap)) <= tolerance,
              abs(b.frame.maxY - (area.maxY - gap)) <= tolerance,
              abs((b.frame.minY - t.frame.maxY) - gap) <= tolerance,
              abs(t.frame.minX - (area.minX + gap)) <= tolerance,
              abs(b.frame.minX - (area.minX + gap)) <= tolerance,
              abs(t.frame.maxX - (area.maxX - gap)) <= tolerance,
              abs(b.frame.maxX - (area.maxX - gap)) <= tolerance,
              t.frame.height >= 200, b.frame.height >= 200 else { return nil }
        return SplitPair(leading: t, trailing: b, axis: .stacked, area: area,
                         seam: (t.frame.maxY + b.frame.minY) / 2)
    }
}
