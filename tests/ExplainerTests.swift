// 讲解动画（SettingsExplainer）的纯逻辑：令牌时长、一轮时长、关键帧、读屏句、页 / 行 / 选项 / 关着的状态机、
// 6 轮上限、看不见时停、截图定帧、箭头路径。期望值是手算的：弹簧落定时刻用稿里脚本的算法另写一遍算
// （0.005 s 一格、离终点 0.2% 以内且 0.05 s 后仍在以内），一轮时长按稿里 frameTimes 的规则逐帧加。
import CoreGraphics
import Foundation

@main
struct ExplainerTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }
    static func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.0005) -> Bool { abs(a - b) <= tolerance }

    static func main() {
        tokenDurations()
        loopTimings()
        sceneLibrary()
        pageAndRowLoops()
        offAndOptions()
        environment()
        freezeAndPaths()
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("explainer: all passed")
    }

    // 令牌时长：和稿里脚本算出来的一样（Python 另算：calm 0.460、settle 0.515、pop 0.370、bloom 0.545、flyOut 0.355、expand 0.405）。
    static func tokenDurations() {
        let expected: [(ExplainerEasing, Double)] = [(.calm, 0.46), (.settle, 0.515), (.pop, 0.37), (.bloom, 0.545),
                                                     (.flyOut, 0.355), (.expand, 0.405), (.tap, 0.08), (.fade, 0.18), (.none, 0)]
        for (easing, value) in expected {
            expect(near(easing.duration, value), "\(easing.rawValue) lasts \(value) s (got \(easing.duration))")
        }
        expect(near(ExplainerTiming.loopStart, 0.14) && near(ExplainerTiming.resetCost, 0.32), "loop lead-in 0.14 s, reset 0.32 s")
    }

    // 一轮时长（手算，逐帧：最慢令牌 + 停留）：
    // dbl：0.14 + 0.46 + 3×0.14 + 0.08 + (0.515+1.0) + 3×0.14 + 0.08 + (0.515+0.5) + (0.46+0.8) = 5.39（稿：一轮 5.4 s）
    // swipeUp：0.14 + 0.18 + 0.515 + 1.08 + 0 + 0.18 + 0.515 + 0.98 = 3.59
    // tuck：0.14 + 0.23 + 0.515 + 0.915 + 1.06 + 0 + 0.14 + 0.08 + (0.46+0.8) = 4.34
    // swipeD：0.14 + 0.18 + 0.515 + 1.18 + 0.32 = 2.335
    static func loopTimings() {
        let dbl = ExplainerScenes.doubleClickRoll.timeline
        expect(near(dbl.loopDuration, 5.39), "double-click loop is 5.39 s (got \(dbl.loopDuration))")
        expect(ExplainerScenes.doubleClickRoll.keyFrameIndex == 5, "double-click key frame is the roll-up (frame 6)")
        expect(near(dbl.starts[5], 1.10), "roll-up starts at 1.10 s (got \(dbl.starts[5]))")
        expect(near(ExplainerScenes.swipeUpRoll.timeline.loopDuration, 3.59), "swipe-up loop is 3.59 s")
        expect(near(ExplainerScenes.tuckIntoNotch.timeline.loopDuration, 4.34), "tuck loop is 4.34 s")
        expect(near(ExplainerScenes.swipeDownFill.timeline.loopDuration, 2.335), "swipe-down loop with a reset is 2.335 s")
        // 一行最多 6 轮：双击那段约 32 s，最快的一段（往下滑）约 14 s。都在“不一直演下去”的量级。
        let cap = Double(ExplainerTiming.rowLoopCap)
        expect(near(cap * dbl.loopDuration, 32.34, 0.01), "six double-click loops stop after 32.3 s")
        let still = ExplainerScenes.still(id: "s", deviceText: nil, initial: [:], description: WSL10n.setting("explainer.dbl.ax", zh: "演示：在标题栏上双击，窗口收成卷帘条；再双击，展开。"))
        expect(still.timeline.loopDuration == 0 && still.isStill, "a still has no loop")
    }

    static func sceneLibrary() {
        let scenes = ExplainerScenes.storyboard
        expect(scenes.count == 13, "storyboard has the 13 groups of the draft")
        expect(Set(scenes.map(\.id)).count == scenes.count, "scene ids are unique")
        for spec in scenes {
            expect(spec.keyFrameIndex != nil, "\(spec.id) has a key frame")
            expect(spec.description.zh.hasPrefix("演示：") && spec.description.zh.count > 6, "\(spec.id) has a VoiceOver sentence")
            expect(spec.frames.allSatisfy { $0.duration >= 0 } && spec.timeline.loopDuration > 1, "\(spec.id) loop is longer than a second")
            expect(!ExplainerPath.parse(spec.arrows.result).isEmpty, "\(spec.id) has a result arrow for Reduce Motion")
            // 元素落在两块里该在的那一块：设备块只放指尖、键帽和那一句话。
            let used = Set(spec.initial.keys).union(spec.frames.flatMap { $0.set.keys })
            expect(used.allSatisfy { e in spec.initial[e] != nil || spec.frames.contains { $0.set[e] != nil } }, "\(spec.id) elements resolve")
        }
        // 窗口浏览页：循环的场景有关键帧、读屏句、时长大于一秒；静图没有帧；按窗口切换三段对上分段。
        let browserLoops = [ExplainerScenes.dockClickHide, ExplainerScenes.dockStay, ExplainerScenes.missionControlClose,
                            ExplainerScenes.switcher(option: true), ExplainerScenes.switcher(option: false)]
        for spec in browserLoops {
            expect(spec.keyFrameIndex != nil && spec.description.zh.hasPrefix("演示：") && spec.timeline.loopDuration > 1, "\(spec.id) is a looping scene with a key frame")
        }
        let browserStills = [ExplainerScenes.menuItemStill, ExplainerScenes.switcherOff, ExplainerScenes.panelStill]
        expect(browserStills.allSatisfy { $0.isStill && $0.description.zh.hasPrefix("静图：") }, "browser stills have no frames")
        if case .options(let specs) = ExplainerRow.Browser.switcher.kind {
            expect(specs.map(\.id) == ["switcherOff", "switcherOption", "switcherCommand"], "switcher options line up with Off / ⌥Tab / ⌘Tab")
        } else { expect(false, "switcher is an options row") }
        expect(ExplainerScenes.switcher(option: true).keyState[.panel]?.look == .highlight2, "switcher key frame is the second Tab")
        expect(ExplainerPage.browser.pageDefault.id == "dockHover", "browser page default is Dock hover")
        // 关键帧那一刻的样子：双击那段停在卷帘条（高 10、内容收起），窗口没挪。
        let key = ExplainerScenes.doubleClickRoll.keyState
        expect(key[.windowA]?.h == 10 && key[.windowA]?.rolled == true && key[.windowA]?.x == 70, "double-click key state is the strip in place")
        expect(key[.pointer]?.x == 150 && key[.finger1]?.opacity == 0, "pointer stays on the title bar, finger lifted")
        // 重摆帧之后回到初始。
        let fill = ExplainerScenes.swipeDownFill
        let afterReset = fill.state(throughFrame: fill.frames.count - 1)
        expect(afterReset[.windowA]?.w == 172 && afterReset[.windowA]?.h == 118, "a reset frame puts the window back")
        expect(fill.keyState[.windowA]?.w == 308, "swipe-down key state fills the screen")
        // 动法只管这一帧：叠完之后不留到下一帧。
        expect(ExplainerScenes.swipeUpRoll.keyState.values.allSatisfy { $0.easing == nil }, "per-element easing does not stick to state")
        // 通用带参数的场景。
        let cell = ExplainerScenes.windowToCell(id: "leftHalf", keys: (ExplainerKeyCap(symbol: "⌃⌘", caption: "control command"), ExplainerKeyCap(symbol: "←", caption: "")),
                                                target: ExplainerScenes.leftHalf, description: ExplainerScenes.swipeSideHalf.description)
        expect(cell.keyState[.windowA]?.w == 153 && cell.keyState[.key1]?.keyCap?.symbol == "⌃⌘", "window-to-cell ends on the target frame")
        // 0.14 + 0.4 + 0.2 + 0.08 + (0.515 + 1.1) + 0.32 = 2.755
        expect(near(cell.timeline.loopDuration, 2.755), "key press loop is 2.755 s (got \(cell.timeline.loopDuration))")
        let say = ExplainerScenes.notchSays(id: "say", when: ExplainerScenes.doubleClickRoll.description, line: ExplainerScenes.doubleClickRoll.description,
                                            detail: ExplainerScenes.doubleClickRoll.description, description: ExplainerScenes.doubleClickRoll.description)
        // 0.14 + 0.6 + (0.545 + 2.6) + (0.46 + 0.8) = 5.145
        expect(near(say.timeline.loopDuration, 5.145) && say.notchLine != nil && say.device == .text, "notch-says loop is 5.145 s with two lines")
        expect(ExplainerScenes.dockSwipe.trackpadOnly && !ExplainerScenes.dockHover.trackpadOnly, "only the Dock swipe needs a trackpad")
    }

    static func row(_ id: Int, _ row: ExplainerRow, on: Bool? = true, option: Int? = nil) -> ExplainerDirector.RowState {
        ExplainerDirector.RowState(id: id, row: row, isOn: on, selectedOption: option)
    }

    static func pageAndRowLoops() {
        var d = ExplainerDirector(page: .gestures)
        let open = d.handle(.openPage)
        expect(open?.spec.id == "swipeUp" && open?.mode == .play(loops: 2) && open?.transition == .instant, "page opens: page default plays twice, first show is instant")
        let held = d.handle(.loopsFinished("swipeUp"))
        expect(held?.mode == .hold(arrows: false) && held?.transition == .inPlace && d.pagePlayed, "after two loops it holds the key frame without arrows")
        expect(d.handle(.loopsFinished("swipeUp")) == nil, "a second finish changes nothing")

        let dbl = row(1, ExplainerRow.Gestures.doubleClick)
        let enter = d.handle(.enter(dbl))
        expect(enter?.spec.id == "dbl" && enter?.mode == .play(loops: 6) && enter?.transition == .crossfade && enter?.announces == true,
               "pointer enters a row: cross-fade to it, loop at most 6 times, announce")
        expect(d.handle(.loopsFinished("swipeUp")) == nil, "a stale finish for another scene is ignored")
        expect(d.handle(.loopsFinished("dbl"))?.mode == .hold(arrows: false), "after 6 loops the row holds its key frame")
        expect(d.handle(.enter(dbl))?.mode == .play(loops: 6), "pointer coming back replays the row")
        let leave = d.handle(.exit(rowID: 1))
        expect(leave?.spec.id == "swipeUp" && leave?.mode == .hold(arrows: false), "leaving without a selection returns to the page key frame, no replay")
        expect(d.handle(.exit(rowID: 1)) == nil, "leaving twice changes nothing")

        // 扫过几行：每进一行就改目标，不排队。
        var sweep = ExplainerDirector(page: .gestures)
        _ = sweep.handle(.openPage)
        _ = sweep.handle(.enter(row(1, ExplainerRow.Gestures.doubleClick)))
        _ = sweep.handle(.exit(rowID: 1))
        let third = sweep.handle(.enter(row(3, ExplainerRow.Gestures.tuck)))
        expect(third?.spec.id == "tuck" && third?.mode == .play(loops: 6), "sweeping over rows retargets to the latest one")
        expect(sweep.handle(.exit(rowID: 3))?.mode == .hold(arrows: false), "once a row was shown the page loop is not replayed")

        // 点选住：指针移开也接着演；指到别的行演那一行，移开回到选住的。
        var pick = ExplainerDirector(page: .gestures)
        _ = pick.handle(.openPage)
        let tuck = row(3, ExplainerRow.Gestures.tuck)
        _ = pick.handle(.enter(tuck))
        expect(pick.handle(.click(tuck)) == nil, "clicking the row that is already playing keeps it playing")
        expect(pick.handle(.exit(rowID: 3)) == nil, "a selected row keeps playing after the pointer leaves")
        expect(pick.handle(.enter(dbl))?.spec.id == "dbl", "hovering another row plays that one")
        expect(pick.handle(.exit(rowID: 1))?.spec.id == "tuck", "leaving it goes back to the selected row")
        _ = pick.handle(.enter(tuck))
        _ = pick.handle(.click(tuck))
        expect(pick.handle(.exit(rowID: 3))?.spec.id == "swipeUp", "clicking again releases the selection")

        // 页默认的行：回到页默认的关键帧，不为它换画、不降灰。
        var middle = ExplainerDirector(page: .gestures)
        _ = middle.handle(.openPage)
        let m = middle.handle(.enter(row(9, ExplainerRow.Gestures.middleFold, on: false)))
        expect(m?.spec.id == "swipeUp" && m?.mode == .hold(arrows: false) && m?.dimmed == false, "a page-default row holds the page key frame, never dimmed")

        // 手势页四段：每段的页默认是这一段第一行，页 id 各不相同（整页重建时按 id 接着用状态机）。
        let segments = (0..<4).map { ExplainerPage.gestures(segment: $0) }
        expect(segments.map(\.pageDefault.id) == ["swipeUp", "tuck", "dropSplit", "dockSwipe"], "each segment opens on its first row")
        expect(Set(segments.map(\.id)).count == 4 && ExplainerPage.gestures == segments[0], "segment pages have distinct ids; the page default is the first segment")
        var notch = ExplainerDirector(page: segments[1])
        let opened = notch.handle(.openPage)
        expect(opened?.spec.id == "tuck" && opened?.mode == .play(loops: 2), "the notch segment plays its first row twice")
    }

    static func offAndOptions() {
        var d = ExplainerDirector(page: .gestures)
        _ = d.handle(.openPage)
        let off = row(4, ExplainerRow.Gestures.overviewTuck, on: false)
        let dim = d.handle(.enter(off))
        expect(dim?.dimmed == true && dim?.mode == .play(loops: 6), "an off switch still plays, dimmed")
        let lit = d.handle(.rowChanged(row(4, ExplainerRow.Gestures.overviewTuck, on: true)))
        expect(lit?.dimmed == false && lit?.transition == .inPlace && lit?.mode == .play(loops: 6) && lit?.announces == false,
               "turning it on while watching undims in place without restarting")
        expect(d.handle(.rowChanged(row(4, ExplainerRow.Gestures.overviewTuck, on: true))) == nil, "nothing changes when nothing changed")

        // 关着时换成另一段（不降灰）。
        let instant = ExplainerScenes.doubleClickRoll.variant(id: "rollInstant", description: ExplainerScenes.doubleClickRoll.description) { _ in }
        var e = ExplainerDirector(page: .gestures)
        _ = e.handle(.openPage)
        let swapped = e.handle(.enter(row(5, .loop(ExplainerScenes.doubleClickRoll, offScene: instant), on: false)))
        expect(swapped?.spec.id == "rollInstant" && swapped?.dimmed == false, "an off scene replaces dimming")
        let back = e.handle(.rowChanged(row(5, .loop(ExplainerScenes.doubleClickRoll, offScene: instant), on: true)))
        expect(back?.spec.id == "dbl" && back?.transition == .crossfade, "turning it on cross-fades to the on scene")

        // 选项：演选中那一段；指到另一段先演那一段，移开回到选中的；选了就换。
        let opts = ExplainerRow.options([ExplainerScenes.doubleClickRoll, ExplainerScenes.swipeUpRoll, ExplainerScenes.tuckIntoNotch])
        var o = ExplainerDirector(page: .gestures)
        _ = o.handle(.openPage)
        expect(o.handle(.enter(row(6, opts, on: nil, option: 1)))?.spec.id == "swipeUp", "option row shows the selected option")
        expect(o.handle(.hoverOption(row(6, opts, on: nil, option: 1), option: 2))?.spec.id == "tuck", "hovering another segment previews it")
        expect(o.handle(.leaveOption(row(6, opts, on: nil, option: 1)))?.spec.id == "swipeUp", "leaving the segment goes back to the selected one")
        let chosen = o.handle(.rowChanged(row(6, opts, on: nil, option: 0)))
        expect(chosen?.spec.id == "dbl" && chosen?.transition == .crossfade, "choosing a segment cross-fades to it")
        expect(opts.description(option: 2)?.key == "explainer.tuck.ax" && ExplainerRow.pageDefault.description(option: nil) == nil,
               "row help is the shown option's sentence; page-default rows have none")
    }

    static func environment() {
        // 减少动态效果：不循环，摆关键帧 + 箭头；换行直接替换。
        var r = ExplainerDirector(page: .gestures, environment: .init(reduceMotion: true))
        let open = r.handle(.openPage)
        expect(open?.mode == .hold(arrows: true) && open?.transition == .instant, "Reduce Motion: page shows the key frame with arrows")
        let enter = r.handle(.enter(row(1, ExplainerRow.Gestures.doubleClick)))
        expect(enter?.mode == .hold(arrows: true) && enter?.transition == .instant, "Reduce Motion: rows swap directly, still with arrows")
        let on = r.handle(.environment(.init(reduceMotion: false)))
        expect(on?.mode == .play(loops: 6), "turning Reduce Motion off starts the row loop")

        // 低电量：页循环不自动播，行只演一轮。
        var low = ExplainerDirector(page: .gestures, environment: .init(lowPower: true))
        expect(low.handle(.openPage)?.mode == .hold(arrows: false), "Low Power: page loop does not autoplay")
        expect(low.handle(.enter(row(1, ExplainerRow.Gestures.doubleClick)))?.mode == .play(loops: 1), "Low Power: a row plays once")

        // 看不见：停在关键帧；回来从这一段开头演。
        var v = ExplainerDirector(page: .gestures)
        _ = v.handle(.openPage)
        let hidden = v.handle(.environment(.init(visible: false)))
        expect(hidden?.mode == .hold(arrows: false) && hidden?.transition == .inPlace, "occluded: holds the current key frame")
        expect(v.handle(.environment(.init(visible: false))) == nil, "still occluded: nothing more")
        let shown = v.handle(.environment(.init(visible: true)))
        expect(shown?.spec.id == "swipeUp" && shown?.mode == .play(loops: 2), "visible again: replays the interrupted segment from the start")
        _ = v.handle(.loopsFinished("swipeUp"))
        _ = v.handle(.environment(.init(visible: false)))
        expect(v.handle(.environment(.init(visible: true))) == nil, "a finished page loop is not replayed on return")
        // 窗口还没到最前就打开了页：先停在关键帧，看得见了才演两轮。
        var early = ExplainerDirector(page: .gestures, environment: .init(visible: false))
        expect(early.handle(.openPage)?.mode == .hold(arrows: false), "a page opened in a hidden window waits on the key frame")
        expect(early.handle(.environment(.init(visible: true)))?.mode == .play(loops: 2), "it plays twice once the window is visible")
        // 已经演过的页再打开（整页重建）：只摆关键帧。
        var rebuilt = ExplainerDirector(page: .gestures, pagePlayed: true)
        expect(rebuilt.handle(.openPage)?.mode == .hold(arrows: false), "a rebuilt page that already played holds the key frame")
    }

    static func freezeAndPaths() {
        expect(ExplainerFreeze.parse(["WindowShade"]) == nil, "no freeze in normal runs")
        expect(ExplainerFreeze.parse(["WindowShade", "--settings-shots", "/tmp/x"]) == .keyFrame, "settings shots freeze on the key frame")
        expect(ExplainerFreeze.parse(["WindowShade", "--settings-shots", "--explainer-frame", "3"]) == .frame(3), "an explicit frame wins")
        expect(ExplainerFreeze.parse(["x", "--explainer-frame", "initial"]) == .initial, "initial can be frozen")
        expect(ExplainerFreeze.frame(99).frameIndex(in: ExplainerScenes.doubleClickRoll) == 11, "frame index is clamped to the last frame")
        expect(ExplainerFreeze.keyFrame.frameIndex(in: ExplainerScenes.doubleClickRoll) == 5, "key frame freeze picks the key frame")
        let path = ExplainerPath.parse("M146 70 l10 -8 l10 8 M156 150 L156 60")
        expect(path == [.move(CGPoint(x: 146, y: 70)), .line(CGPoint(x: 156, y: 62)), .line(CGPoint(x: 166, y: 70)),
                        .move(CGPoint(x: 156, y: 150)), .line(CGPoint(x: 156, y: 60))], "arrow paths parse M, l and L")
        expect(ExplainerPath.parse("M126 92 l-8 6 l8 6") == [.move(CGPoint(x: 126, y: 92)), .line(CGPoint(x: 118, y: 98)), .line(CGPoint(x: 126, y: 104))],
               "negative relative steps parse")
        expect(ExplainerPath.parse("").isEmpty, "empty path draws nothing")
    }
}
