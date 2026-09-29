// 窗口之间每条缝的认对、拖动、松手落点（纯计算，不碰窗口）。
// 排好的两排窗之间有一条缝：竖缝左右两边、横缝上下两边各有一扇或几扇窗贴着它。认出来之后，
// 拖这条缝两边一起变，松手吸附到整块屏的 ⅙ / ¼ / ⅓ / ½ / ⅔ / ¾ / ⅚，两边各只有一扇又是整块屏的
// （一对）甩一下就有一扇离开。坐标是 AX 坐标：左上角为原点、y 向下。area 是屏幕可用区域；
// gap 是 ArrangeGap 的窗口间距规则：贴着屏幕边的那条边让出一整道缝，两扇窗面对面那两条边各让半道。

import CoreGraphics

/// 两排窗口之间的一条缝：竖缝左右两边、横缝上下两边各有一扇或几扇窗贴着它。
struct Seam: Equatable {
    enum Axis: Equatable { case vertical, horizontal }   // vertical: x = position；horizontal: y = position
    let axis: Axis
    /// 那道缝（空档）的正中间。
    let position: CGFloat
    /// 缝两边一起盖住的那一段：竖缝是 y 范围，横缝是 x 范围。
    let span: ClosedRange<CGFloat>
    /// 左 / 上那几扇，沿缝排好。
    let before: [SplitWindow]
    /// 右 / 下那几扇，沿缝排好。
    let after: [SplitWindow]
    /// 这些窗所在的屏幕可用区域。
    let area: CGRect
    /// 两边各只有一扇、而且两扇合起来占满整块屏：这种缝拖到头可以让一扇窗离开。
    let isPair: Bool
}

enum SeamLayout {
    static let tolerance: CGFloat = 6
    /// 最窄一边（点）：拖到比这还窄就有阻力。
    static let minimumSide: CGFloat = 240
    /// 松手时推算的落点离屏幕边不到这么多（占整块的比例），可以离开的那种缝就让一扇走。
    static let dismissFraction: CGFloat = 0.15

    /// windows 按前后排列（0 是最前面），里面可能还有别的屏上的窗、压在上面的浮窗。
    /// 先认出这块屏上排好的那几扇（T），再从每扇窗的远侧边往外找对面贴着的一排：凑成一条缝就算。
    /// 竖缝按位置排在前，横缝排在后，各自从小到大。
    static func seams(frontToBack windows: [SplitWindow], area: CGRect, gap: CGFloat) -> [Seam] {
        let tiling = collect(windows, area: area)
        var vertical: [Seam] = []
        var horizontal: [Seam] = []
        for w in tiling {
            if let seam = candidate(w, in: tiling, area: area, gap: gap, axis: .vertical),
               !taken(seam.position, in: vertical) {
                vertical.append(seam)
            }
            if let seam = candidate(w, in: tiling, area: area, gap: gap, axis: .horizontal),
               !taken(seam.position, in: horizontal) {
                horizontal.append(seam)
            }
        }
        return vertical.sorted { $0.position < $1.position } + horizontal.sorted { $0.position < $1.position }
    }

    /// 缝停在 position 时两边各扇窗的框（按编号给）：外侧那条边和另一方向照旧，面对面那两条边各让半个缝。
    static func frames(_ seam: Seam, position: CGFloat, gap: CGFloat) -> [UInt32: CGRect] {
        var out: [UInt32: CGRect] = [:]
        for w in seam.before {
            let f = w.frame
            switch seam.axis {
            case .vertical:
                out[w.id] = CGRect(x: f.minX, y: f.minY, width: (position - gap / 2) - f.minX, height: f.height)
            case .horizontal:
                out[w.id] = CGRect(x: f.minX, y: f.minY, width: f.width, height: (position - gap / 2) - f.minY)
            }
        }
        for w in seam.after {
            let f = w.frame
            switch seam.axis {
            case .vertical:
                let x = position + gap / 2
                out[w.id] = CGRect(x: x, y: f.minY, width: f.maxX - x, height: f.height)
            case .horizontal:
                let y = position + gap / 2
                out[w.id] = CGRect(x: f.minX, y: y, width: f.width, height: f.maxY - y)
            }
        }
        return out
    }

    /// 拖着走：范围内照给的位置；越过范围就带阻力，越拉越拉不动，永远不会硬停。
    static func dragged(_ proposed: CGFloat, seam: Seam, gap: CGFloat) -> CGFloat {
        let limits = limits(seam, gap: gap)
        if proposed < limits.lo {
            return limits.lo - CGFloat(FluidMotion.rubberBand(Double(limits.lo - proposed), limit: 60))
        }
        if proposed > limits.hi {
            return limits.hi + CGFloat(FluidMotion.rubberBand(Double(proposed - limits.hi), limit: 60))
        }
        return proposed
    }

    enum Landing: Equatable { case position(CGFloat), beforeLeaves, afterLeaves }

    /// 松手：按惯性推一推会落到哪。一对的那种缝快到屏幕边就有一扇离开；别的缝只在拖动范围内挑最近的刻度，
    /// 甩得再猛也不会让谁离开。position 是手推到的位置（没经过橡皮筋）：带着阻力的把手最多只比最窄一边
    /// 多走不到 60 点，窄屏、上下拼满时离“屏幕边”还远，看手推到哪，慢慢推到屏幕边也能让一扇离开。
    static func landing(position: CGFloat, velocity: CGFloat, seam: Seam, gap: CGFloat) -> Landing {
        let start = seam.axis == .vertical ? seam.area.minX : seam.area.minY
        let end = seam.axis == .vertical ? seam.area.maxX : seam.area.maxY
        let length = end - start
        let projected = position + CGFloat(FluidMotion.projection(velocity: Double(velocity)))
        if seam.isPair {
            if projected < start + length * dismissFraction { return .beforeLeaves }
            if projected > end - length * dismissFraction { return .afterLeaves }
        }
        let limits = limits(seam, gap: gap)
        let shares: [CGFloat] = [1.0 / 6, 1.0 / 4, 1.0 / 3, 1.0 / 2, 2.0 / 3, 3.0 / 4, 5.0 / 6]
        let candidates = shares.map { start + length * $0 }.filter { $0 >= limits.lo && $0 <= limits.hi }
        if let nearest = candidates.min(by: { abs($0 - projected) < abs($1 - projected) }) {
            return .position(nearest)
        }
        return .position(min(max(projected, limits.lo), limits.hi))
    }

    /// 滑到 position 之后回读到的实际外框（observed，按编号）：有的 App 有自己的最小（最大）尺寸，
    /// 缩不到或放不到要的宽 / 高。按每扇实际肯接受的大小，把缝挪到离 position 最近、每扇都放得下的地方，
    /// 另一边照这条实际的边重排，两边不压在一起；都接受了原样返回 position。两边谁都不肯让、或者挪过去
    /// 另一边窄过最窄一边，返回 nil（回到拖之前）。差不到 tolerance 的算接受（终端一类按字符格取整）。
    static func fitted(_ seam: Seam, position: CGFloat, observed: [UInt32: CGRect], gap: CGFloat) -> CGFloat? {
        let target = frames(seam, position: position, gap: gap)
        let vertical = seam.axis == .vertical
        var lo = -CGFloat.infinity, hi = CGFloat.infinity
        for w in seam.before {
            guard let want = target[w.id], let got = observed[w.id] else { continue }
            let (wanted, actual) = vertical ? (want.width, got.width) : (want.height, got.height)
            // 左 / 上那扇外侧的边不动，它实际多宽，缝就在它右 / 下边再让半道。
            let edge = (vertical ? w.frame.minX : w.frame.minY) + actual + gap / 2
            if actual > wanted + tolerance { lo = max(lo, edge) }   // 缩不到：缝至少在这
            if actual < wanted - tolerance { hi = min(hi, edge) }   // 放不到：缝最多到这
        }
        for w in seam.after {
            guard let want = target[w.id], let got = observed[w.id] else { continue }
            let (wanted, actual) = vertical ? (want.width, got.width) : (want.height, got.height)
            let edge = (vertical ? w.frame.maxX : w.frame.maxY) - actual - gap / 2
            if actual > wanted + tolerance { hi = min(hi, edge) }
            if actual < wanted - tolerance { lo = max(lo, edge) }
        }
        guard lo <= hi else { return nil }
        let fitted = min(max(position, lo), hi)
        guard fitted != position else { return position }
        let limits = limits(seam, gap: gap)
        guard fitted >= limits.lo, fitted <= limits.hi else { return nil }
        return fitted
    }

    /// 缝两边各自最窄一边要留下的量：左边几扇的远侧边加 240 再加半道缝，右边几扇同理。
    private static func limits(_ seam: Seam, gap: CGFloat) -> (lo: CGFloat, hi: CGFloat) {
        switch seam.axis {
        case .vertical:
            let lo = (seam.before.map { $0.frame.minX + minimumSide }.max() ?? seam.area.minX) + gap / 2
            let hi = (seam.after.map { $0.frame.maxX - minimumSide }.min() ?? seam.area.maxX) - gap / 2
            return (lo, hi)
        case .horizontal:
            let lo = (seam.before.map { $0.frame.minY + minimumSide }.max() ?? seam.area.minY) + gap / 2
            let hi = (seam.after.map { $0.frame.maxY - minimumSide }.min() ?? seam.area.maxY) - gap / 2
            return (lo, hi)
        }
    }

    /// 从前往后收：盖住自己一半以上的才算这块屏上的窗；碰到第一扇和已经收下的窗压得太多（超过小的那扇的
    /// 十分之一）就停 —— 那是压在排布上面的浮窗或更后面的大窗，后面的都不算数。最多收 12 扇。
    private static func collect(_ windows: [SplitWindow], area: CGRect) -> [SplitWindow] {
        var kept: [SplitWindow] = []
        for w in windows {
            guard mostlyOnScreen(w, area: area) else { continue }
            if kept.contains(where: { tooMuchOverlap($0, w) }) { break }
            kept.append(w)
            if kept.count >= 12 { break }
        }
        return kept
    }

    /// 一扇窗（它的远侧边，竖缝是 maxX、横缝是 maxY）对面有没有一排贴着的窗：两边都非空、
    /// 各自沿缝是一整段连贯的范围、两段的起止对得上，才算一条缝。
    private static func candidate(_ w: SplitWindow, in tiling: [SplitWindow], area: CGRect,
                                  gap: CGFloat, axis: Seam.Axis) -> Seam? {
        let edge = axis == .vertical ? w.frame.maxX : w.frame.maxY
        let far = axis == .vertical ? area.maxX : area.maxY
        guard edge < far - gap - tolerance else { return nil }
        let position = edge + gap / 2
        let before = tiling.filter { near(facingEdge($0, axis: axis, leading: false), edge) }
            .sorted { alongStart($0, axis: axis) < alongStart($1, axis: axis) }
        let after = tiling.filter { near(facingEdge($0, axis: axis, leading: true), edge + gap) }
            .sorted { alongStart($0, axis: axis) < alongStart($1, axis: axis) }
        guard !before.isEmpty, !after.isEmpty,
              let above = run(before, axis: axis, gap: gap), let below = run(after, axis: axis, gap: gap),
              near(above.lowerBound, below.lowerBound), near(above.upperBound, below.upperBound) else { return nil }
        let span = max(above.lowerBound, below.lowerBound)...min(above.upperBound, below.upperBound)
        guard span.lowerBound <= span.upperBound else { return nil }
        return Seam(axis: axis, position: position, span: span, before: before, after: after,
                    area: area, isPair: isPair(before, after, area: area, gap: gap, axis: axis))
    }

    /// 一边的几扇沿缝排好后拼成一段连贯的范围；中间的空档得是 -tol 到 gap + tol 之间（正好一道缝）。
    private static func run(_ windows: [SplitWindow], axis: Seam.Axis, gap: CGFloat) -> ClosedRange<CGFloat>? {
        let ranges = windows.map { along($0, axis: axis) }.sorted { $0.lowerBound < $1.lowerBound }
        guard let first = ranges.first, let last = ranges.last else { return nil }
        for i in ranges.indices.dropFirst() {
            let step = ranges[i].lowerBound - ranges[i - 1].upperBound
            guard step >= -tolerance, step <= gap + tolerance else { return nil }
        }
        return first.lowerBound...last.upperBound
    }

    /// 两边各只有一扇、两边各自的四条边都按 ArrangeGap 贴着屏幕边：这种缝拖到头可以让一扇窗离开。
    private static func isPair(_ before: [SplitWindow], _ after: [SplitWindow], area: CGRect,
                               gap: CGFloat, axis: Seam.Axis) -> Bool {
        guard before.count == 1, after.count == 1,
              let b = before.first?.frame, let a = after.first?.frame else { return false }
        switch axis {
        case .vertical:
            return near(b.minX, area.minX + gap) && near(a.maxX, area.maxX - gap)
                && near(b.minY, area.minY + gap) && near(b.maxY, area.maxY - gap)
                && near(a.minY, area.minY + gap) && near(a.maxY, area.maxY - gap)
        case .horizontal:
            return near(b.minY, area.minY + gap) && near(a.maxY, area.maxY - gap)
                && near(b.minX, area.minX + gap) && near(b.maxX, area.maxX - gap)
                && near(a.minX, area.minX + gap) && near(a.maxX, area.maxX - gap)
        }
    }

    /// 一扇窗在轴上的近侧边：leading 是朝缝的那条（竖缝 minX、横缝 minY），否则是远侧边。
    private static func facingEdge(_ w: SplitWindow, axis: Seam.Axis, leading: Bool) -> CGFloat {
        switch (axis, leading) {
        case (.vertical, true): return w.frame.minX
        case (.vertical, false): return w.frame.maxX
        case (.horizontal, true): return w.frame.minY
        case (.horizontal, false): return w.frame.maxY
        }
    }

    /// 一扇窗沿缝盖住的那一段：竖缝是 y 范围，横缝是 x 范围。
    private static func along(_ w: SplitWindow, axis: Seam.Axis) -> ClosedRange<CGFloat> {
        axis == .vertical ? w.frame.minY...w.frame.maxY : w.frame.minX...w.frame.maxX
    }

    private static func alongStart(_ w: SplitWindow, axis: Seam.Axis) -> CGFloat {
        axis == .vertical ? w.frame.minY : w.frame.minX
    }

    /// 同一个位置上只认一条缝（同一方向的重复候选跳过）。
    private static func taken(_ position: CGFloat, in seams: [Seam]) -> Bool {
        seams.contains { near($0.position, position) }
    }

    private static func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }

    /// 盖住自己一半以上，才算“落在这块屏上”。
    private static func mostlyOnScreen(_ w: SplitWindow, area: CGRect) -> Bool {
        let own = w.frame.width * w.frame.height
        guard own > 0 else { return false }
        let shared = w.frame.intersection(area)
        guard !shared.isNull, shared.width > 0, shared.height > 0 else { return false }
        return shared.width * shared.height >= own / 2
    }

    /// 两扇窗压在一起、而且压掉的部分超过小的那扇的十分之一。
    private static func tooMuchOverlap(_ a: SplitWindow, _ b: SplitWindow) -> Bool {
        let shared = a.frame.intersection(b.frame)
        guard !shared.isNull, shared.width > 0, shared.height > 0 else { return false }
        let own = min(a.frame.width * a.frame.height, b.frame.width * b.frame.height)
        guard own > 0 else { return false }
        return shared.width * shared.height > own * 0.1
    }
}
