// 窗口之间每条缝的认对、拖动、松手落点：纯逻辑，不碰任何窗口。
import CoreGraphics
import Foundation

@main
struct SeamLayoutTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.001) -> Bool { abs(a - b) <= tol }

    static func position(of landing: SeamLayout.Landing) -> CGFloat? {
        if case .position(let p) = landing { return p }
        return nil
    }

    static let area = CGRect(x: 0, y: 25, width: 1728, height: 1080)

    /// 把毛坯框按 ArrangeGap 摆好，编号从 1 开始。
    static func windows(_ raw: [CGRect], in screen: CGRect = SeamLayoutTests.area, gap: CGFloat) -> [SplitWindow] {
        raw.enumerated().map { SplitWindow(id: UInt32($0.offset + 1),
                                           frame: ArrangeGap.apply($0.element, in: screen, gap: gap)) }
    }

    /// 左右两半。
    static func halves(in screen: CGRect = SeamLayoutTests.area) -> [CGRect] {
        [CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height),
         CGRect(x: screen.midX, y: screen.minY, width: screen.width / 2, height: screen.height)]
    }

    /// 上下两半。
    static func stackedHalves(in screen: CGRect) -> [CGRect] {
        [CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height / 2),
         CGRect(x: screen.minX, y: screen.midY, width: screen.width, height: screen.height / 2)]
    }

    /// 左边六成，右边上下两扇。
    static func shareStacked() -> [CGRect] {
        let leftWidth = area.width * 0.6
        let right = CGRect(x: area.minX + leftWidth, y: area.minY,
                           width: area.width - leftWidth, height: area.height)
        return [CGRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height),
                CGRect(x: right.minX, y: right.minY, width: right.width, height: right.height / 2),
                CGRect(x: right.minX, y: right.midY, width: right.width, height: right.height / 2)]
    }

    /// 四角。
    static func corners() -> [CGRect] {
        [CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height / 2),
         CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height / 2),
         CGRect(x: area.minX, y: area.midY, width: area.width / 2, height: area.height / 2),
         CGRect(x: area.midX, y: area.midY, width: area.width / 2, height: area.height / 2)]
    }

    /// 竖着三等分。
    static func thirds() -> [CGRect] {
        (0..<3).map { i in
            CGRect(x: area.minX + area.width / 3 * CGFloat(i), y: area.minY,
                   width: area.width / 3, height: area.height)
        }
    }

    /// 两半：正好一条竖缝在屏幕中间，是一对。
    static func checkHalves(_ gap: CGFloat) {
        let ws = windows(halves(), gap: gap)
        let seams = SeamLayout.seams(frontToBack: [ws[1], ws[0]], area: area, gap: gap)
        expect(seams.count == 1, "gap \(gap): two halves make exactly one seam (got \(seams.count))")
        guard seams.count == 1 else { return }
        let seam = seams[0]
        expect(seam.axis == .vertical, "gap \(gap): the seam between two halves is vertical")
        expect(near(seam.position, area.minX + area.width / 2),
               "gap \(gap): the seam sits in the middle of the screen (got \(seam.position))")
        expect(seam.before.map(\.id) == [1] && seam.after.map(\.id) == [2],
               "gap \(gap): the left window is before even when it is later in the list")
        expect(seam.isPair, "gap \(gap): two full halves are a pair")
        expect(near(seam.span.lowerBound, ws[0].frame.minY) && near(seam.span.upperBound, ws[0].frame.maxY),
               "gap \(gap): the seam spans the full height (got \(seam.span))")
        expect(seam.area == area, "gap \(gap): the seam remembers the screen it is on")
    }

    /// 左边六成 + 右边上下两扇：一条竖缝（一扇对两扇），还有右边两扇之间的一条横缝。
    static func checkShareStacked(_ gap: CGFloat) {
        let ws = windows(shareStacked(), gap: gap)
        let seams = SeamLayout.seams(frontToBack: ws, area: area, gap: gap)
        expect(seams.count == 2, "gap \(gap): the six-four split with a stacked column has two seams (got \(seams.count))")
        guard seams.count == 2, seams[0].axis == .vertical, seams[1].axis == .horizontal else {
            expect(false, "gap \(gap): there is one vertical seam and then one horizontal one")
            return
        }
        let v = seams[0], h = seams[1]
        expect(v.before.map(\.id) == [1] && v.after.map(\.id) == [2, 3],
               "gap \(gap): the vertical seam has the wide window on the left and the two stacked ones on the right (got \(v.before.map(\.id)) / \(v.after.map(\.id)))")
        expect(!v.isPair, "gap \(gap): one window against two is not a pair")
        expect(near(v.position, ws[0].frame.maxX + gap / 2),
               "gap \(gap): the vertical seam lies in the gap right of the wide window (got \(v.position))")
        expect(near(v.span.lowerBound, ws[0].frame.minY) && near(v.span.upperBound, ws[0].frame.maxY),
               "gap \(gap): the vertical seam spans both stacked windows (got \(v.span))")
        expect(h.before.map(\.id) == [2] && h.after.map(\.id) == [3],
               "gap \(gap): the horizontal seam has the upper window above and the lower one below")
        expect(near(h.position, ws[1].frame.maxY + gap / 2),
               "gap \(gap): the horizontal seam lies in the gap between the stacked two (got \(h.position))")
        expect(near(h.span.lowerBound, ws[1].frame.minX) && near(h.span.upperBound, ws[1].frame.maxX),
               "gap \(gap): the horizontal seam spans the right column (got \(h.span))")
    }

    /// 四角：竖缝两扇对两扇，横缝也是，横缝横跨整块屏。
    static func checkCorners(_ gap: CGFloat) {
        let ws = windows(corners(), gap: gap)
        let seams = SeamLayout.seams(frontToBack: ws, area: area, gap: gap)
        expect(seams.count == 2, "gap \(gap): four corners make a vertical and a horizontal seam (got \(seams.count))")
        guard seams.count == 2, seams[0].axis == .vertical, seams[1].axis == .horizontal else {
            expect(false, "gap \(gap): the four corners give one vertical seam and then one horizontal one")
            return
        }
        let v = seams[0], h = seams[1]
        expect(v.before.map(\.id) == [1, 3] && v.after.map(\.id) == [2, 4],
               "gap \(gap): two left corners against two right ones (got \(v.before.map(\.id)) / \(v.after.map(\.id)))")
        expect(h.before.map(\.id) == [1, 2] && h.after.map(\.id) == [3, 4],
               "gap \(gap): two top corners against two bottom ones (got \(h.before.map(\.id)) / \(h.after.map(\.id)))")
        expect(near(v.position, area.minX + area.width / 2) && near(h.position, area.minY + area.height / 2),
               "gap \(gap): the two seams cross in the middle (got \(v.position), \(h.position))")
        expect(near(v.span.lowerBound, ws[0].frame.minY) && near(v.span.upperBound, ws[2].frame.maxY),
               "gap \(gap): the vertical seam spans the screen height (got \(v.span))")
        expect(near(h.span.lowerBound, ws[0].frame.minX) && near(h.span.upperBound, ws[1].frame.maxX),
               "gap \(gap): the horizontal seam spans the full width (got \(h.span))")
        expect(!v.isPair && !h.isPair, "gap \(gap): a two-by-two grid is not a pair")
    }

    /// 竖着三等分：两条竖缝。
    static func checkThirds(_ gap: CGFloat) {
        let ws = windows(thirds(), gap: gap)
        let seams = SeamLayout.seams(frontToBack: ws, area: area, gap: gap)
        expect(seams.count == 2, "gap \(gap): three thirds make two seams (got \(seams.count))")
        guard seams.count == 2 else { return }
        expect(seams.allSatisfy { $0.axis == .vertical }, "gap \(gap): both seams of a column split are vertical")
        expect(seams[0].position < seams[1].position, "gap \(gap): the seams come left to right")
        expect(near(seams[0].position, ws[0].frame.maxX + gap / 2) && near(seams[1].position, ws[1].frame.maxX + gap / 2),
               "gap \(gap): one seam after the first column and one after the second (got \(seams.map(\.position)))")
        expect(seams[0].before.map(\.id) == [1] && seams[0].after.map(\.id) == [2]
               && seams[1].before.map(\.id) == [2] && seams[1].after.map(\.id) == [3],
               "gap \(gap): each seam has one window on each side")
        expect(!seams[0].isPair && !seams[1].isPair, "gap \(gap): a third against a third is not a pair")
        expect(near(seams[0].span.lowerBound, ws[0].frame.minY) && near(seams[0].span.upperBound, ws[0].frame.maxY),
               "gap \(gap): the seam spans the whole column")
    }

    static func main() {
        // 两半（不留缝、留 8 点的缝）。
        checkHalves(0)
        checkHalves(8)
        checkShareStacked(0)
        checkShareStacked(8)
        checkCorners(0)
        checkCorners(8)
        checkThirds(0)
        checkThirds(8)

        // 三等分（不留缝）落在 ⅓ 和 ⅔ 上。
        do {
            let ws = windows(thirds(), gap: 0)
            let seams = SeamLayout.seams(frontToBack: ws, area: area, gap: 0)
            expect(seams.count == 2 && near(seams[0].position, area.minX + area.width / 3)
                   && near(seams[1].position, area.minX + area.width * 2 / 3),
                   "gap 0: the seams of three thirds sit on a third and two thirds (got \(seams.map(\.position)))")
        }

        // 最前面是个小浮窗：压着后面的排布，收不到能成缝的窗。
        do {
            let dialog = SplitWindow(id: 9, frame: CGRect(x: 600, y: 400, width: 400, height: 300))
            let ws = windows(halves(), gap: 0)
            let seams = SeamLayout.seams(frontToBack: [dialog, ws[0], ws[1]], area: area, gap: 0)
            expect(seams.isEmpty, "a small floating window in front means no seams (got \(seams.count))")
        }

        // 更后面压着一扇大窗（排在列表后面、盖着排布）：前面排布之间的缝照常有。
        do {
            let ws = windows(halves(), gap: 0)
            let big = SplitWindow(id: 9, frame: CGRect(x: 400, y: area.minY, width: 1000, height: area.height))
            let seams = SeamLayout.seams(frontToBack: [ws[0], ws[1], big], area: area, gap: 0)
            expect(seams.count == 1 && near(seams[0].position, area.minX + area.width / 2)
                   && seams[0].before.map(\.id) == [1] && seams[0].after.map(\.id) == [2],
                   "a big overlapping window behind the tiling does not break the seams in front (got \(seams.count))")
        }

        // 缝挪到 1000：四扇窗面对面那四条边跟着动，外侧那几条边和另一方向照旧。
        do {
            let ws = windows(corners(), gap: 0)
            guard let seam = SeamLayout.seams(frontToBack: ws, area: area, gap: 0).first(where: { $0.axis == .vertical }) else {
                expect(false, "the two-by-two grid has a vertical seam for the frames check")
                return
            }
            let frames = SeamLayout.frames(seam, position: 1000, gap: 0)
            expect(frames.count == 4, "frames() covers all four windows (got \(frames.count))")
            expect(frames[1] == CGRect(x: 0, y: 25, width: 1000, height: 540)
                   && frames[3] == CGRect(x: 0, y: 565, width: 1000, height: 540),
                   "the left windows keep their left edge and stop at the seam (got \(frames[1] ?? .zero), \(frames[3] ?? .zero))")
            expect(frames[2] == CGRect(x: 1000, y: 25, width: 728, height: 540)
                   && frames[4] == CGRect(x: 1000, y: 565, width: 728, height: 540),
                   "the right windows keep their right edge and start at the seam (got \(frames[2] ?? .zero), \(frames[4] ?? .zero))")
            expect(frames.values.allSatisfy { $0.height == 540 }, "the cross-axis extent is kept")
        }

        // 拖：范围内照给；顶到最窄的 240 就带阻力，走得比手少，也不会撞到硬墙。
        do {
            let ws = windows(shareStacked(), gap: 0)
            guard let seam = SeamLayout.seams(frontToBack: ws, area: area, gap: 0).first(where: { $0.axis == .vertical }) else {
                expect(false, "the stacked column has a vertical seam for the drag check")
                return
            }
            let lo = ws[0].frame.minX + SeamLayout.minimumSide
            let hi = ws[1].frame.maxX - SeamLayout.minimumSide
            expect(SeamLayout.dragged(600, seam: seam, gap: 0) == 600, "inside the range the seam follows the pointer exactly")
            expect(SeamLayout.dragged(lo, seam: seam, gap: 0) == lo && SeamLayout.dragged(hi, seam: seam, gap: 0) == hi,
                   "the bounds themselves are still exact")
            let pushed = SeamLayout.dragged(hi + 100, seam: seam, gap: 0)
            expect(pushed > hi && pushed < hi + 100,
                   "past the bound it moves less than the overshoot (got \(pushed - hi))")
            expect(pushed < hi + 60, "and it never reaches the 60-point limit")
            let pulled = SeamLayout.dragged(lo - 100, seam: seam, gap: 0)
            expect(pulled < lo && pulled > lo - 60, "the same at the other end (got \(pulled - lo))")
            expect(near(hi, ws[1].frame.maxX - SeamLayout.minimumSide),
                   "the stacked column keeps its 240-point minimum (got \(hi))")
        }

        // 松手：一对的那种缝甩一下就有一扇离开；别的缝甩得再猛也只是挑个位置。
        do {
            let ws = windows(halves(), gap: 0)
            guard let seam = SeamLayout.seams(frontToBack: ws, area: area, gap: 0).first else {
                expect(false, "the halves have a seam for the landing check")
                return
            }
            expect(seam.isPair, "the halves seam is a pair")
            expect(SeamLayout.landing(position: seam.position, velocity: 3000, seam: seam, gap: 0) == .afterLeaves,
                   "a fast fling to the right carries the right window off screen")
            expect(SeamLayout.landing(position: seam.position, velocity: -3000, seam: seam, gap: 0) == .beforeLeaves,
                   "a fast fling the other way carries the left window off screen")
            expect(near(position(of: SeamLayout.landing(position: 0.34 * area.width, velocity: 0, seam: seam, gap: 0)) ?? -1,
                        area.minX + area.width / 3),
                   "a slow release near 0.34 already snaps to a third (got \(SeamLayout.landing(position: 0.34 * area.width, velocity: 0, seam: seam, gap: 0)))")
            expect(SeamLayout.landing(position: 0.48 * area.width, velocity: 0, seam: seam, gap: 0) == .position(area.minX + area.width / 2),
                   "a slow release in the middle snaps to a half")
        }

        // 两扇对两扇：甩出去也只落到范围内的刻度上，谁都不离开。
        do {
            let ws = windows(corners(), gap: 0)
            guard let seam = SeamLayout.seams(frontToBack: ws, area: area, gap: 0).first(where: { $0.axis == .vertical }) else {
                expect(false, "the two-by-two grid has a vertical seam for the landing check")
                return
            }
            let limits = (lo: ws[0].frame.minX + SeamLayout.minimumSide, hi: ws[1].frame.maxX - SeamLayout.minimumSide)
            let fling = SeamLayout.landing(position: seam.position, velocity: 3000, seam: seam, gap: 0)
            expect(position(of: fling).map { $0 >= limits.lo && $0 <= limits.hi } == true,
                   "a fling on a two-by-two seam lands inside the drag range (got \(fling))")
            let back = SeamLayout.landing(position: seam.position, velocity: -3000, seam: seam, gap: 0)
            expect(position(of: back).map { $0 >= limits.lo && $0 <= limits.hi } == true,
                   "flinging the other way does not send anyone away either (got \(back))")
            expect(near(position(of: SeamLayout.landing(position: 0.34 * area.width, velocity: 0, seam: seam, gap: 0)) ?? -1,
                        area.minX + area.width / 3),
                   "a slow release near 0.34 snaps to a third here too")
        }

        // 1280 点宽的屏幕、左右拼满：顶着阻力慢慢推到屏幕边（手停在边上、速度约为 0），被推的那扇也离开。
        // 把手被橡皮筋拽住，停在离开的那条线里面，所以看的是手推到哪。
        do {
            let narrow = CGRect(x: 0, y: 25, width: 1280, height: 775)
            let ws = windows(halves(in: narrow), in: narrow, gap: 0)
            guard let seam = SeamLayout.seams(frontToBack: ws, area: narrow, gap: 0).first, seam.isPair else {
                expect(false, "two halves of a 1280-point screen are a pair")
                return
            }
            let held = SeamLayout.dragged(narrow.minX, seam: seam, gap: 0)
            expect(held > narrow.minX + narrow.width * SeamLayout.dismissFraction,
                   "on a 1280-point screen the rubber band holds the bar short of the edge zone (bar at \(held))")
            expect(SeamLayout.landing(position: narrow.minX, velocity: 0, seam: seam, gap: 0) == .beforeLeaves,
                   "pushing slowly all the way to the left edge of a 1280-point screen sends the left window away")
            expect(SeamLayout.landing(position: narrow.maxX, velocity: 0, seam: seam, gap: 0) == .afterLeaves,
                   "pushing slowly all the way to the right edge sends the right window away")
            let leaning = narrow.minX + SeamLayout.minimumSide - 10
            expect(SeamLayout.landing(position: leaning, velocity: 0, seam: seam, gap: 0) == .position(narrow.minX + narrow.width / 4),
                   "just leaning into the resistance snaps back to a quarter (got \(SeamLayout.landing(position: leaning, velocity: 0, seam: seam, gap: 0)))")
        }

        // 横放的屏幕上下拼满：可视高度 875，推到菜单栏、推到最底下也能让一扇离开。
        do {
            let wide = CGRect(x: 0, y: 25, width: 1440, height: 875)
            let ws = windows(stackedHalves(in: wide), in: wide, gap: 0)
            guard let seam = SeamLayout.seams(frontToBack: ws, area: wide, gap: 0).first, seam.axis == .horizontal, seam.isPair else {
                expect(false, "two stacked halves are a horizontal pair")
                return
            }
            let held = SeamLayout.dragged(0, seam: seam, gap: 0)
            expect(held > wide.minY + wide.height * SeamLayout.dismissFraction,
                   "stacked, the rubber band alone never reaches the edge zone (bar at \(held))")
            expect(SeamLayout.landing(position: 0, velocity: 0, seam: seam, gap: 0) == .beforeLeaves,
                   "pushing the bar up into the menu bar sends the upper window away")
            expect(SeamLayout.landing(position: wide.maxY, velocity: 0, seam: seam, gap: 0) == .afterLeaves,
                   "pushing it down to the bottom edge sends the lower window away")
            expect(position(of: SeamLayout.landing(position: wide.minY + wide.height * 0.3, velocity: 0, seam: seam, gap: 0))
                   .map { near($0, wide.minY + wide.height / 3) } == true,
                   "a slow release at 0.3 of the height snaps to a third")
        }

        // 回读：App 不肯缩到要的宽度，缝挪到它实际的边；另一边跟着让，两扇不压在一起。
        do {
            let ws = windows(halves(), gap: 0)
            guard let seam = SeamLayout.seams(frontToBack: ws, area: area, gap: 0).first else {
                expect(false, "the halves have a seam for the read-back check")
                return
            }
            let sixth = area.minX + area.width / 6
            var observed = SeamLayout.frames(seam, position: sixth, gap: 0)
            expect(SeamLayout.fitted(seam, position: sixth, observed: observed, gap: 0) == sixth,
                   "when both windows took their sizes the seam stays where it landed")
            observed[1] = CGRect(x: 0, y: 25, width: sixth - 3, height: 1080)
            expect(SeamLayout.fitted(seam, position: sixth, observed: observed, gap: 0) == sixth,
                   "a few points of rounding (a terminal's character grid) count as taken")
            observed[1] = CGRect(x: 0, y: 25, width: 500, height: 1080)
            expect(SeamLayout.fitted(seam, position: sixth, observed: observed, gap: 0) == 500,
                   "a left window that stays 500 wide moves the seam to its real edge (got \(String(describing: SeamLayout.fitted(seam, position: sixth, observed: observed, gap: 0))))")

            let fiveSixths = area.minX + area.width * 5 / 6
            var right = SeamLayout.frames(seam, position: fiveSixths, gap: 0)
            right[2] = CGRect(x: fiveSixths, y: 25, width: 500, height: 1080)
            expect(SeamLayout.fitted(seam, position: fiveSixths, observed: right, gap: 0) == area.maxX - 500,
                   "a right window that stays 500 wide keeps its right edge and the seam moves left to meet it (got \(String(describing: SeamLayout.fitted(seam, position: fiveSixths, observed: right, gap: 0))))")

            let half = area.midX
            var both = SeamLayout.frames(seam, position: half, gap: 0)
            both[1] = CGRect(x: 0, y: 25, width: 1000, height: 1080)
            both[2] = CGRect(x: half, y: 25, width: 900, height: 1080)
            expect(SeamLayout.fitted(seam, position: half, observed: both, gap: 0) == nil,
                   "when neither side gives way there is no place for the seam (back to where it was)")
            var huge = SeamLayout.frames(seam, position: half, gap: 0)
            huge[1] = CGRect(x: 0, y: 25, width: 1600, height: 1080)
            expect(SeamLayout.fitted(seam, position: half, observed: huge, gap: 0) == nil,
                   "a window that would squeeze the other side under the minimum sends both back")
        }

        // 回读，留 8 点的缝、上下拼满：面对面那两条边照样各让半道。
        do {
            let gapped = windows(halves(), gap: 8)
            if let seam = SeamLayout.seams(frontToBack: gapped, area: area, gap: 8).first {
                let sixth = area.minX + area.width / 6
                var observed = SeamLayout.frames(seam, position: sixth, gap: 8)
                observed[1] = CGRect(x: 8, y: 33, width: 500, height: 1064)
                let fitted = SeamLayout.fitted(seam, position: sixth, observed: observed, gap: 8)
                expect(fitted == 8 + 500 + 4 && SeamLayout.frames(seam, position: fitted ?? 0, gap: 8)[2]?.minX == 8 + 500 + 8,
                       "gap 8: the right window starts one gap after the left window's real edge (got \(String(describing: fitted)))")
            } else {
                expect(false, "gap 8: the halves have a seam for the read-back check")
            }
            let stacked = windows(stackedHalves(in: area), gap: 0)
            if let seam = SeamLayout.seams(frontToBack: stacked, area: area, gap: 0).first(where: { $0.axis == .horizontal }) {
                let quarter = area.minY + area.height / 4
                var observed = SeamLayout.frames(seam, position: quarter, gap: 0)
                observed[1] = CGRect(x: 0, y: area.minY, width: area.width, height: 400)
                expect(SeamLayout.fitted(seam, position: quarter, observed: observed, gap: 0) == area.minY + 400,
                       "stacked: an upper window that stays 400 tall moves the seam down to its bottom edge")
            } else {
                expect(false, "the stacked halves have a horizontal seam for the read-back check")
            }
        }

        if failures == 0 {
            print("PASS: seam layout — seams between tiled windows (halves, six-four with a stacked column, two-by-two, thirds; with and without a gap), floating and overlapping windows, frames, dragging with the 240-point minimum and rubber band, release landing (snapping, flinging away only on a pair, pushing slowly to the edge on a narrow or stacked screen), reading back sizes an app refused")
        } else {
            print("FAILED \(failures)")
            exit(1)
        }
    }
}
