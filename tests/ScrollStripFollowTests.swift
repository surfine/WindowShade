// 卷轴第二批（稿：docs/design-drafts/卷轴.html 工作包 SS-05、SS-06、SS-07）：
// 张开跟手的概览（进度、橡皮筋、松手推算过一半才开）、滑完的焦点挑法、按 App 记住宽度（重启仍在、一键忘掉）、
// 卷轴开着时拖标题栏的蓝条缝判定、拖远才离开、卷轴关着时什么都不管、自动卷时不改窗口大小。纯逻辑，不碰任何窗口。
import CoreGraphics
import Foundation

@main
struct ScrollStripFollowTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool { abs(a - b) <= tolerance }

    static func main() {
        let screen = CGRect(x: 0, y: 25, width: 1500, height: 900)

        // MARK: 滑完的焦点

        do {
            let five = ScrollStrip(columns: (1...5).map { .init(ids: [CGWindowID($0)], width: 500) }, area: screen)
            expect(five.focusAfterScroll(focused: 0, from: 0, to: 500) == 3,
                   "focused column slid fully off the left: focus goes to the farthest fully visible column the strip moved toward")
            expect(five.focusAfterScroll(focused: 1, from: 0, to: 500) == nil,
                   "focused column still fully on screen: focus stays")
            expect(five.focusAfterScroll(focused: 0, from: 0, to: 250) == nil,
                   "focused column only half off screen: focus stays (today it would switch apps)")
            expect(five.focusAfterScroll(focused: 4, from: 1000, to: 0) == 0,
                   "scrolling back left: focus goes to the leftmost fully visible column")
            expect(five.focusAfterScroll(focused: nil, from: 0, to: 1000) == 4,
                   "nothing focused in the strip: the farthest fully visible column toward the move")
            expect(five.focusAfterScroll(focused: 0, from: 500, to: 500) == 1,
                   "no movement but focus is off screen: the nearest fully visible column")
            expect(five.isOffscreen(0, at: 490) && !five.isOffscreen(0, at: 489),
                   "a column counts as off screen once only its 10-point sliver could show")

            let wide = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2], width: 1000), .init(ids: [3], width: 1000)],
                                   area: screen)
            expect(wide.focusAfterScroll(focused: 2, from: 0, to: 250) == nil,
                   "no column fully visible: focus does not move (no needless app switch)")
            expect(wide.isFullyVisible(0, at: 0) && wide.isFullyVisible(1, at: 500) && !wide.isFullyVisible(1, at: 250),
                   "fully visible is the whole column inside the screen")
        }

        // MARK: 按 App 记住宽度

        do {
            expect(StripWidthMemory.preset(for: 0.5) == 0.5 && StripWidthMemory.preset(for: 0.34) == 1.0 / 3
                   && StripWidthMemory.preset(for: 0.98) == 1 && StripWidthMemory.preset(for: 0.42) == nil
                   && StripWidthMemory.preset(for: .nan) == nil,
                   "a width is remembered only as one of the presets (⅓ ½ ⅔ full)")

            var memory = StripWidthMemory()
            expect(memory.remember(bundleID: "com.example.editor", width: 980, screenWidth: 1470),
                   "changing a column to ⅔ remembers it for that app")
            expect(!memory.remember(bundleID: nil, width: 735, screenWidth: 1470)
                   && !memory.remember(bundleID: "", width: 735, screenWidth: 1470)
                   && !memory.remember(bundleID: "com.example.odd", width: 600, screenWidth: 1470),
                   "no app identity, or a width that is not a preset: nothing remembered")
            expect(memory.width(for: "com.example.editor", in: CGRect(x: 0, y: 0, width: 1470, height: 900)) == 980
                   && memory.width(for: "com.example.editor", in: CGRect(x: 0, y: 0, width: 1800, height: 1000)) == 1200,
                   "the remembered preset scales to the screen it opens on")
            expect(memory.width(for: "com.example.other", in: screen) == nil && memory.width(for: nil, in: screen) == nil,
                   "an app never changed opens at the width its role asks for")
            memory.remember(bundleID: "com.example.editor", width: 490, screenWidth: 1470)
            expect(memory.fraction(for: "com.example.editor") == 1.0 / 3 && memory.entries.count == 1,
                   "changing it again replaces the old preset")

            let suite = "windowshade.tests.stripwidth.\(getpid())"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            expect(!StripWidthMemory.isEnabled(defaults), "remembering widths is off by default")
            defaults.set(false, forKey: StripWidthMemory.enabledKey)
            expect(!StripWidthMemory.isEnabled(defaults), "an explicit off from the earlier default-on build stays off")
            defaults.removeObject(forKey: StripWidthMemory.enabledKey)
            memory.remember(bundleID: "com.example.browser", width: 735, screenWidth: 1470)
            memory.save(defaults)
            let relaunched = StripWidthMemory.load(UserDefaults(suiteName: suite)!)
            expect(relaunched == memory && relaunched.fraction(for: "com.example.browser") == 0.5,
                   "remembered widths are still there after a relaunch")
            defaults.set([["com.example.ok", 0.5], ["broken"], [42, 0.5], ["com.example.bad", "x"]], forKey: StripWidthMemory.storageKey)
            expect(StripWidthMemory.load(defaults).entries.map(\.bundleID) == ["com.example.ok"],
                   "damaged stored entries are skipped, good ones kept")
            StripWidthMemory.forgetAll(defaults)
            expect(StripWidthMemory.load(defaults).entries.isEmpty && defaults.object(forKey: StripWidthMemory.storageKey) == nil,
                   "forget clears everything in one step")
            StripWidthMemory.setEnabled(true, defaults)
            expect(StripWidthMemory.isEnabled(defaults), "the switch turns it on")
            StripWidthMemory.setEnabled(false, defaults)
            expect(!StripWidthMemory.isEnabled(defaults) && defaults.object(forKey: StripWidthMemory.enabledKey) == nil,
                   "turning it back off leaves the preference clean")
            memory.save(defaults)
            expect(!StripWidthMemory.isEnabled(defaults) && StripWidthMemory.load(defaults) == memory,
                   "remembered widths from before stay stored while the switch is off")
            StripWidthMemory().save(defaults)
            expect(defaults.object(forKey: StripWidthMemory.storageKey) == nil, "an empty memory stores nothing")
            defaults.removePersistentDomain(forName: suite)

            var many = StripWidthMemory()
            for index in 0..<(StripWidthMemory.capacity + 6) {
                many.remember(bundleID: "app.\(index)", width: 500, screenWidth: 1500)
            }
            expect(many.entries.count == StripWidthMemory.capacity && many.fraction(for: "app.0") == nil
                   && many.fraction(for: "app.\(StripWidthMemory.capacity + 5)") != nil,
                   "the memory stays bounded and drops the oldest first")
        }

        // MARK: 张开跟手的概览

        do {
            let arm: CGFloat = 0.25
            expect(StripOverviewSpread.rawProgress(total: arm, arm: arm) == 0.5,
                   "today's open threshold sits exactly at half way")
            for total in stride(from: CGFloat(0), through: 0.6, by: 0.01) {
                let old = total >= arm
                let new = StripOverviewSpread.opens(progress: StripOverviewSpread.rawProgress(total: total, arm: arm), velocity: 0)
                if old != new { expect(false, "held still before release, open/close must match the old rule at total \(total)") }
            }
            expect(true, "held still before release, opening matches the old threshold everywhere")
            expect(!StripOverviewSpread.opens(progress: 0.3, velocity: 0),
                   "spread to 30% and stop: the overview goes back")
            expect(StripOverviewSpread.opens(progress: 0.3, velocity: 1),
                   "a quick spread released early still opens (projected past half)")
            expect(!StripOverviewSpread.opens(progress: 0.6, velocity: -1),
                   "closing the fingers past half while moving back: it goes back")
            let over = StripOverviewSpread.shown(1.5), under = StripOverviewSpread.shown(-1)
            expect(over > 1 && over < 1 + StripOverviewSpread.limit && under < 0 && under > -StripOverviewSpread.limit,
                   "beyond 0…1 the progress is held by a rubber band (at most 5%)")
            expect(StripOverviewSpread.shown(0.42) == 0.42 && StripOverviewSpread.shown(2) > StripOverviewSpread.shown(1.5),
                   "inside 0…1 progress follows 1:1, the band keeps growing slowly")
            expect(near(StripOverviewSpread.band(0.1), (1 - 1 / (0.1 * 0.5 / 0.05 + 1)) * 0.05),
                   "rubber band uses stiffness 0.5, limit 5%")
            let real = CGRect(x: 0, y: 0, width: 1000, height: 900), small = CGRect(x: 100, y: 200, width: 400, height: 360)
            expect(StripOverviewSpread.frame(from: real, to: small, progress: 0) == real
                   && StripOverviewSpread.frame(from: real, to: small, progress: 1) == small
                   && StripOverviewSpread.frame(from: real, to: small, progress: 0.5) == CGRect(x: 50, y: 100, width: 700, height: 630),
                   "each window grows from where it really is into its overview place")
            expect(StripOverviewSpread.opacity(-0.02) == 0 && StripOverviewSpread.opacity(0.3) == 0.3 && StripOverviewSpread.opacity(1.03) == 1,
                   "the overview fades with the progress, clamped")
            let strip = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2, 3], width: 750)], area: screen)
            let frames = strip.screenFrames()
            expect(frames[1] == CGRect(x: 0, y: 0, width: 1000, height: 900) && frames[2]?.minY == 0 && frames[3]?.maxY == 900,
                   "real frames are measured from the top-left of the usable screen, like the overview panel")
        }

        // MARK: 卷轴开着时拖标题栏

        do {
            let three = ScrollStrip(columns: [.init(ids: [1], width: 500), .init(ids: [2], width: 500), .init(ids: [3], width: 500)],
                                    area: screen)
            expect(StripTitleDrag.begin(id: 1, down: .zero, strip: nil, enabled: true) == nil,
                   "strip closed: dragging a window is untouched")
            expect(StripTitleDrag.begin(id: 1, down: .zero, strip: three, enabled: false) == nil,
                   "switch off (the default): dragging a window is untouched")
            expect(StripTitleDrag.begin(id: 9, down: .zero, strip: three, enabled: true) == nil,
                   "a window not in the strip is untouched")
            let single = ScrollStrip(columns: [.init(ids: [1], width: 500)], area: screen)
            expect(StripTitleDrag.begin(id: 1, down: .zero, strip: single, enabled: true) == nil,
                   "a strip of one column is untouched")

            expect(three.screenSeam(nearest: 300, dragging: 1) == nil && three.screenSeam(nearest: 600, dragging: 1) == nil,
                   "pointer still over its own column: no blue bar")
            let swap = three.screenSeam(nearest: 800, dragging: 1)
            expect(swap?.drop == .newColumn(at: 2) && swap?.bar == CGRect(x: 998, y: 25, width: 4, height: 900),
                   "nearest vertical seam between the next two columns, full height (\(String(describing: swap)))")
            let end = three.screenSeam(nearest: 1490, dragging: 1)
            expect(end?.drop == .newColumn(at: 3) && end?.bar.maxX == 1500,
                   "the seam at the strip's end is drawn just inside the screen edge")
            let leftEnd = three.screenSeam(nearest: 10, dragging: 3)
            expect(leftEnd?.drop == .newColumn(at: 0) && leftEnd?.bar.minX == 0, "and the same at the left end")

            let long = ScrollStrip(columns: (1...5).map { .init(ids: [CGWindowID($0)], width: 500) }, area: screen)
            expect(long.screenSeam(nearest: 1499, dragging: 1)?.drop == .newColumn(at: 3),
                   "seams parked off screen are not offered")
            expect(long.screenSeam(nearest: 1499, dragging: 1, at: 500)?.drop == .newColumn(at: 4),
                   "after scrolling at the edge the seams follow the strip")

            var drag = StripTitleDrag.begin(id: 1, down: CGPoint(x: 250, y: 40), strip: three, enabled: true)!
            drag.update(pointer: CGPoint(x: 800, y: 60), strip: three)
            expect(drag.seam?.drop == .newColumn(at: 2) && drag.end(pointer: CGPoint(x: 800, y: 60), intoNotch: false) == .stay(.newColumn(at: 2)),
                   "release on the blue bar: the window moves there and stays in the strip")
            expect(drag.end(pointer: CGPoint(x: 800, y: 60), intoNotch: true) == .leave,
                   "released into the notch: it leaves the strip")
            var back = StripTitleDrag.begin(id: 1, down: CGPoint(x: 250, y: 40), strip: three, enabled: true)!
            back.update(pointer: CGPoint(x: 300, y: 50), strip: three)
            expect(back.end(pointer: CGPoint(x: 300, y: 50), intoNotch: false) == .stay(nil),
                   "a short drag over its own column: it goes back to its place")
            var far = StripTitleDrag.begin(id: 1, down: CGPoint(x: 250, y: 40), strip: three, enabled: true)!
            far.update(pointer: CGPoint(x: 250, y: 40 + StripTitleDrag.leaveDistance), strip: three)
            expect(far.leaving && far.seam == nil, "pulled 256 points away from the strip: it is leaving, no blue bar")
            var sideways = StripTitleDrag.begin(id: 1, down: CGPoint(x: 250, y: 40), strip: three, enabled: true)!
            sideways.update(pointer: CGPoint(x: 1300, y: 80), strip: three)
            expect(!sideways.leaving && sideways.seam?.drop == .newColumn(at: 3),
                   "dragging sideways along the strip, even far, keeps choosing seams")
            far.update(pointer: CGPoint(x: 800, y: 60), strip: three)
            expect(far.seam == nil && far.end(pointer: CGPoint(x: 800, y: 60), intoNotch: false) == .leave,
                   "dragged back afterwards it still leaves (once torn out, stays out)")
            expect(three.columns == ScrollStrip(columns: [.init(ids: [1], width: 500), .init(ids: [2], width: 500),
                                                         .init(ids: [3], width: 500)], area: screen).columns,
                   "tracking a drag never changes the strip itself")

            // 靠边自动卷：别的窗口只挪位置，大小保持此刻摆着的大小。
            let parkedStrip = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2], width: 500), .init(ids: [3], width: 500)],
                                          area: screen)
            let applied = parkedStrip.frames()
            let slid = parkedStrip.slidFrames(at: 400, sizes: applied, excluding: 2)
            expect(slid[2] == nil && slid.keys.sorted() == [1, 3], "the dragged window is left to the system")
            expect(slid.allSatisfy { $0.value.size == applied[$0.key]?.size }, "no window changes size before release")
            expect(slid[1]?.minX == -400, "the others slide with the strip")
            expect(parkedStrip.slidFrames(at: 400, sizes: [1: applied[1]!], excluding: 2).keys.sorted() == [1],
                   "a window never placed is not moved")
            expect(EdgeScroll.zone == 30 && EdgeScroll.dwellRequired == 0.1 && EdgeScroll.maxSpeed == 1500,
                   "edge auto-scroll numbers: 30 points, 100 ms, 1500 points a second")
        }

        if failures == 0 {
            print("PASS: scroll strip follow-up — spread-to-open progress and release, focus after scrolling, per-app remembered widths, title-bar drag seams, leaving the strip, nothing changes while the strip is off")
        } else {
            print("FAILED: \(failures)")
            exit(1)
        }
    }
}
