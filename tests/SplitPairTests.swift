// 分屏的认对、拖中间那条、松手落点：纯逻辑，不碰任何窗口。
import CoreGraphics
import Foundation

@main
struct SplitPairTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func window(_ id: UInt32, _ frame: CGRect) -> SplitWindow {
        SplitWindow(id: id, frame: frame)
    }

    static func main() {
        let area = CGRect(x: 0, y: 25, width: 1728, height: 1080)
        let portrait = CGRect(x: 0, y: 25, width: 1080, height: 1895)

        // 两半正好占满：认成并排的一对；左边那扇排在列表后面也还是前。
        do {
            let left = window(1, CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height))
            let right = window(2, CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height))
            let pair = SplitLayout.pair(frontToBack: [right, left], area: area, gap: 0)
            expect(pair?.axis == .sideBySide, "two halves left and right form a side-by-side pair")
            expect(pair?.seam == 864, "the bar sits in the middle of the screen (got \(pair?.seam ?? -1))")
            expect(pair?.leading.id == 1 && pair?.trailing.id == 2, "the left window is the leading one even when it is later in the list")
            expect(pair?.area == area, "the pair remembers the screen it is on")
        }

        // 6:4 分（浏览器占左边六成）：按 ArrangeGap 的规则算出两扇窗，再认对。
        do {
            let share: CGFloat = 0.6
            let rawLeft = CGRect(x: area.minX, y: area.minY, width: area.width * share, height: area.height)
            let rawRight = CGRect(x: rawLeft.maxX, y: area.minY, width: area.width * (1 - share), height: area.height)
            let left = ArrangeGap.apply(rawLeft, in: area, gap: 8)
            let right = ArrangeGap.apply(rawRight, in: area, gap: 8)
            expect(left == CGRect(x: 8, y: 33, width: 1024.8, height: 1064) && right.minX - left.maxX == 8,
                   "a 6:4 split with a gap leaves a full gap at the screen edges and one between them (\(left))")
            let pair = SplitLayout.pair(frontToBack: [window(1, left), window(2, right)], area: area, gap: 8)
            expect(pair != nil, "a 6:4 split with a gap is recognized")
            expect(abs((pair?.seam ?? 0) - (area.minX + share * 1728)) < 0.5,
                   "the bar sits where the two meet (got \(pair?.seam ?? -1))")
        }

        // 竖着放的屏：上下两半认成上下的一对。
        do {
            let top = window(1, CGRect(x: portrait.minX, y: portrait.minY, width: portrait.width, height: portrait.height / 2))
            let bottom = window(2, CGRect(x: portrait.minX, y: portrait.midY, width: portrait.width, height: portrait.height / 2))
            let pair = SplitLayout.pair(frontToBack: [bottom, top], area: portrait, gap: 0)
            expect(pair?.axis == .stacked, "a portrait screen stacks the two windows")
            expect(pair?.leading.id == 1 && abs((pair?.seam ?? 0) - portrait.midY) < 0.5, "the top window leads and the bar lies across the middle")
        }

        let halfLeft = window(1, CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height))
        let halfRight = window(2, CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height))

        // 最前面是个小对话框：头两扇就凑不成一对。
        do {
            let dialog = window(9, CGRect(x: 600, y: 400, width: 400, height: 300))
            expect(SplitLayout.pair(frontToBack: [dialog, halfLeft, halfRight], area: area, gap: 0) == nil,
                   "a small dialog in front means no pair")
        }

        // 另一块屏上的窗不算数，剩下的这一扇自己也凑不成对。
        do {
            let elsewhere = window(9, CGRect(x: 2400, y: 25, width: 800, height: 700))
            let lone = window(1, CGRect(x: area.minX, y: area.minY, width: area.width * 0.6, height: area.height))
            expect(SplitLayout.pair(frontToBack: [elsewhere, lone], area: area, gap: 0) == nil,
                   "a window on another screen is ignored; one window alone cannot pair")
        }

        // 高度没占满：不算一对。
        do {
            let shortLeft = window(1, CGRect(x: area.minX, y: 190, width: area.width / 2, height: 700))
            let shortRight = window(2, CGRect(x: area.midX, y: 190, width: area.width / 2, height: 700))
            expect(SplitLayout.pair(frontToBack: [shortLeft, shortRight], area: area, gap: 0) == nil,
                   "windows that do not fill the height are not a pair")
        }

        // 两扇之间空的档和设置里的缝对不上：不算一对。
        do {
            expect(SplitLayout.pair(frontToBack: [halfLeft, halfRight], area: area, gap: 8) == nil,
                   "two touching halves are not a pair when the gap setting says 8")
        }

        // 同样的两半，按 8 点的缝摆好：认出来之后才谈拖和落点。
        let gapLeft = window(1, ArrangeGap.apply(halfLeft.frame, in: area, gap: 8))
        let gapRight = window(2, ArrangeGap.apply(halfRight.frame, in: area, gap: 8))

        // 分隔条挪到 1000：外面两条边不动，面对面那两条各让半个缝。
        do {
            guard let pair = SplitLayout.pair(frontToBack: [gapLeft, gapRight], area: area, gap: 8) else {
                expect(false, "the halves pair for the frames check")
                return
            }
            let frames = SplitLayout.frames(pair, seam: 1000, gap: 8)
            expect(frames.leading.maxX == 996 && frames.trailing.minX == 1004, "the facing edges leave half a gap each (\(frames.leading), \(frames.trailing))")
            expect(frames.leading.minX == pair.leading.frame.minX && frames.trailing.maxX == pair.trailing.frame.maxX,
                   "the outer edges stay where they were")
            expect(frames.leading.minY == pair.leading.frame.minY && frames.leading.height == pair.leading.frame.height
                   && frames.trailing.height == pair.trailing.frame.height, "the cross-axis extent is kept")
        }

        // 拖：范围内照给；越过太窄的那一边带阻力，走得比手少，也不会撞到硬墙。
        do {
            guard let pair = SplitLayout.pair(frontToBack: [gapLeft, gapRight], area: area, gap: 8) else {
                expect(false, "the halves pair for the drag check")
                return
            }
            let bound = SplitLayout.minimumSide + 8 + 4   // 最窄一边、贴边的缝、半道缝
            let highBound = area.maxX - bound
            expect(SplitLayout.dragged(800, pair: pair, gap: 8) == 800, "inside the range the bar follows the pointer exactly")
            expect(SplitLayout.dragged(highBound, pair: pair, gap: 8) == highBound, "the bound itself is still exact")
            let pushed = SplitLayout.dragged(highBound + 100, pair: pair, gap: 8)
            expect(pushed > highBound && pushed < highBound + 100, "past the bound it moves less than the overshoot (got \(pushed - highBound))")
            expect(pushed < highBound + 60, "and it never reaches the 60-point limit")
            let pulled = SplitLayout.dragged(-100, pair: pair, gap: 8)
            expect(pulled < bound && pulled > bound - 60, "the same at the other end (got \(pulled - bound))")
        }

        // 松手：慢慢放下的看落在哪个刻度上；甩一下就看惯性推出去多远，快到边就让一扇离开。
        do {
            guard let pair = SplitLayout.pair(frontToBack: [halfLeft, halfRight], area: area, gap: 0) else {
                expect(false, "the halves pair for the landing check")
                return
            }
            expect(SplitLayout.landing(seam: 0.48 * 1728, velocity: 0, pair: pair) == .seam(864),
                   "released near 0.48 it snaps to one half")
            expect(SplitLayout.landing(seam: 0.30 * 1728, velocity: 0, pair: pair) == .seam(576),
                   "released near 0.30 it snaps to one third (got \(SplitLayout.landing(seam: 0.30 * 1728, velocity: 0, pair: pair)))")
            expect(SplitLayout.landing(seam: 864, velocity: 3000, pair: pair) == .trailingLeaves,
                   "a fast fling from the middle carries the right window off screen")
            expect(SplitLayout.landing(seam: 864, velocity: -3000, pair: pair) == .leadingLeaves,
                   "a fast fling the other way carries the left window off screen")
            expect(SplitLayout.landing(seam: 0.1 * 1728, velocity: 0, pair: pair) == .leadingLeaves,
                   "released at 0.1 the left window leaves")
        }

        // 竖着分的屏：落点按 y 算。
        do {
            let top = window(1, CGRect(x: portrait.minX, y: portrait.minY, width: portrait.width, height: portrait.height / 2))
            let bottom = window(2, CGRect(x: portrait.minX, y: portrait.midY, width: portrait.width, height: portrait.height / 2))
            guard let pair = SplitLayout.pair(frontToBack: [top, bottom], area: portrait, gap: 0) else {
                expect(false, "the portrait halves pair for the landing check")
                return
            }
            expect(SplitLayout.landing(seam: portrait.minY + 0.3 * 1895, velocity: 0, pair: pair) == .seam(portrait.minY + 1895 / 3),
                   "on a portrait screen the landing is measured down the screen")
            expect(SplitLayout.landing(seam: pair.seam, velocity: 3000, pair: pair) == .trailingLeaves,
                   "a downward fling sends the bottom window away")
            expect(SplitLayout.landing(seam: portrait.minY + 0.1 * 1895, velocity: 0, pair: pair) == .leadingLeaves,
                   "released near the top the top window leaves")
        }

        if failures == 0 { print("PASS: split pair — recognition (halves, 6:4 with gaps, portrait stacking, dialogs, other screens, short frames, gap mismatch), seams and frames, dragging with rubber band, release landing (snapping, flinging away)") }
        else { print("FAILED \(failures)"); exit(1) }
    }
}
