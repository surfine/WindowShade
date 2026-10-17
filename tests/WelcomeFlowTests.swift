// 欢迎窗口（1.0.18：A1 / A2 / T / U1）的状态机、练习状态、T 的分段与自动往下走、授权行、页码读屏、窗口高度：纯逻辑。
import Foundation

@main
struct WelcomeFlowTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        stateMachine()
        practice()
        tour()
        permissions()
        pageLabels()
        layout()
        reducedMotion()
        heightMotion()
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("welcome flow: all passed")
    }

    // 三页：A1 -> A2 -> T；A1 的跳过直接到 T；T 的跳过关窗口；A2 只等辅助功能。
    static func stateMachine() {
        expect(WelcomeFlow.stepCount == 3, "three pages")
        expect(WelcomeFlow.next(from: 0) == 1 && WelcomeFlow.next(from: 1) == 2, "forward walks A1 -> A2 -> T")
        expect(WelcomeFlow.next(from: 2) == 2, "forward stops at T")
        expect(WelcomeFlow.back(from: 2) == 1 && WelcomeFlow.back(from: 0) == 0, "back walks and stops at A1")
        expect(WelcomeFlow.skip(from: WelcomeFlow.practiceStep) == WelcomeFlow.tourStep, "A1 skip goes to T")
        expect(!WelcomeFlow.skipCloses(from: 0) && !WelcomeFlow.skipCloses(from: 1) && WelcomeFlow.skipCloses(from: 2), "only T's skip closes the window")
        expect(WelcomeFlow.clamped(-4) == 0 && WelcomeFlow.clamped(9) == 2, "out-of-range pages are clamped")
        expect(WelcomeFlow.isLast(2) && !WelcomeFlow.isLast(1), "only T is last")
        expect(!WelcomeFlow.canAdvance(from: 1, accessibilityGranted: false), "A2 waits for Accessibility")
        expect(WelcomeFlow.canAdvance(from: 1, accessibilityGranted: true), "A2 continues once Accessibility is on (Screen Recording optional)")
        expect(WelcomeFlow.canAdvance(from: 0, accessibilityGranted: false) && WelcomeFlow.canAdvance(from: 2, accessibilityGranted: false), "A1 and T never wait")
        expect(WelcomeFlow.title(forStep: 0) == "双击标题栏，把窗口收起来。" && WelcomeFlow.title(forStep: 1) == "让每扇窗口都能收起", "A1 / A2 titles")
        expect(WelcomeFlow.title(forStep: 2, tour: .browse) == WelcomeFlow.TourSegment.browse.title, "T title follows the segment")
    }

    // A1：演示 -> 轮到你 -> 收起 -> 展开 ✓；演示中途双击也算轮到他。
    static func practice() {
        typealias P = WelcomeFlow.PracticeState
        expect(WelcomeFlow.practice(afterDoubleClick: .demo) == .rolled, "double-click during the demo rolls up")
        expect(WelcomeFlow.practice(afterDoubleClick: .idle) == .rolled, "double-click on your turn rolls up")
        expect(WelcomeFlow.practice(afterDoubleClick: .rolled) == .done, "double-click on the strip unrolls: done")
        expect(WelcomeFlow.practice(afterDoubleClick: .done) == .rolled, "after done it keeps toggling")
        expect(WelcomeFlow.practiceIsRolled(.rolled) && !WelcomeFlow.practiceIsRolled(.done), "rolled only while rolled")
        expect(([P.demo, .idle, .rolled] as [P]).allSatisfy { !WelcomeFlow.practiceNextIsPrimary($0) } && WelcomeFlow.practiceNextIsPrimary(.done),
               "Continue turns primary only after done")
        expect(WelcomeFlow.practiceStatus(.demo).isEmpty, "no status line during the demo")
        let lines = ([P.idle, .rolled, .done] as [P]).map(WelcomeFlow.practiceStatus)
        expect(lines.allSatisfy { !$0.isEmpty } && Set(lines).count == 3, "each practice state has its own line")
        expect(WelcomeFlow.demoLoops == 2, "demo plays two rounds")
    }

    // T：四段；刘海、手势与卷轴各两块；自动往下走；继续一段一段走，最后关窗口。
    static func tour() {
        typealias S = WelcomeFlow.TourSegment
        expect(S.allCases == [.notch, .browse, .gestures, .menuBar], "four segments in order")
        expect(S.allCases.map(\.heroCount) == [2, 1, 2, 1], "hero counts per segment")
        expect(S.allCases.map(\.loopsPerHero) == [1, 2, 1, 2], "single heroes loop twice, pairs once each")
        expect(S.allCases.filter(\.asksOrigin) == [.notch], "the origin row sits under the notch segment only")
        expect(S.allCases.filter(\.showsMissingAccessibility) == [.menuBar], "missing-Accessibility line on the menu bar segment only")
        expect(Set(S.allCases.map(\.title)).count == 4 && Set(S.allCases.map(\.lede)).count == 4, "four distinct titles and ledes")
        expect(WelcomeFlow.tourHeroGap == 0.4, "0.4 s gap between heroes")

        let start = WelcomeFlow.TourPlayback(segment: .notch)
        let second = WelcomeFlow.tour(after: start, reduceMotion: false)
        expect(second == WelcomeFlow.TourPlayback(segment: .notch, hero: 1, auto: true), "notch plays its second hero")
        let browse = second.flatMap { WelcomeFlow.tour(after: $0, reduceMotion: false) }
        expect(browse == WelcomeFlow.TourPlayback(segment: .browse, hero: 0, auto: true), "then moves on to browse")
        var walked: [S] = [.notch]
        var p: WelcomeFlow.TourPlayback? = start
        while let cur = p, let nxt = WelcomeFlow.tour(after: cur, reduceMotion: false) { if nxt.segment != walked.last { walked.append(nxt.segment) }; p = nxt }
        expect(walked == S.allCases, "auto-advance walks all four segments and stops at the last")
        let manual = WelcomeFlow.TourPlayback(segment: .browse, hero: 0, auto: false)
        expect(WelcomeFlow.tour(after: manual, reduceMotion: false) == nil, "a picked segment stays put")
        let manualPair = WelcomeFlow.TourPlayback(segment: .gestures, hero: 0, auto: false)
        expect(WelcomeFlow.tour(after: manualPair, reduceMotion: false)?.hero == 1, "a picked segment still plays its second hero")
        expect(WelcomeFlow.tour(after: start, reduceMotion: true) == nil, "reduced motion never auto-advances")

        expect(WelcomeFlow.tour(continueFrom: .notch) == .browse && WelcomeFlow.tour(continueFrom: .gestures) == .menuBar, "Continue walks the segments")
        expect(WelcomeFlow.tour(continueFrom: .menuBar) == nil, "Continue on the last segment closes the window")
    }

    // A2 / U1：10 秒卡住提示；U1 一打开就在；进度字。
    static func permissions() {
        expect(WelcomeFlow.stuckHintDelay == 10, "stuck hint after 10 s")
        expect(!WelcomeFlow.showsStuckHint(again: false, accessibility: false, screenRecording: false, secondsOnPage: 9.9), "no hint before 10 s")
        expect(WelcomeFlow.showsStuckHint(again: false, accessibility: false, screenRecording: false, secondsOnPage: 10), "hint at 10 s")
        expect(WelcomeFlow.showsStuckHint(again: false, accessibility: true, screenRecording: false, secondsOnPage: 30), "still one row missing: hint")
        expect(!WelcomeFlow.showsStuckHint(again: false, accessibility: true, screenRecording: true, secondsOnPage: 30), "both granted: no hint")
        expect(WelcomeFlow.showsStuckHint(again: true, accessibility: false, screenRecording: false, secondsOnPage: 0), "U1 shows the hint right away")
        expect(!WelcomeFlow.showsStuckHint(again: true, accessibility: true, screenRecording: false, secondsOnPage: 0), "U1 drops the hint once Accessibility is on")
        expect(WelcomeFlow.permissionStatus(accessibility: false).isEmpty && !WelcomeFlow.permissionStatus(accessibility: true).isEmpty, "A2 asks to try once granted")
        let progress = [(false, false), (true, false), (true, true)].map { WelcomeFlow.againProgress(accessibility: $0.0, screenRecording: $0.1) }
        expect(Set(progress).count == 3, "three distinct U1 progress lines")
        expect(progress[2] == "权限已就绪", "both granted reads ready")
    }

    // 页码点读屏“第 n 页，共 3 页”。
    static func pageLabels() {
        expect((1...3).map(WelcomeFlow.pageLabel) == ["第 1 页，共 3 页", "第 2 页，共 3 页", "第 3 页，共 3 页"], "page dots read 第 n 页，共 3 页")
        expect(WelcomeFlow.pageLabel(0) == "第 1 页，共 3 页" && WelcomeFlow.pageLabel(7) == "第 3 页，共 3 页", "page label stays inside 1...3")
    }

    // 窗口高度照稿：A1 / A2 / U1 470，T 520；A2 没有演示块。
    static func layout() {
        expect(WelcomeFlow.windowHeight(forStep: 0) == 470 && WelcomeFlow.windowHeight(forStep: 1) == 470 && WelcomeFlow.windowHeight(forStep: 2) == 520, "470 / 470 / 520")
        expect(WelcomeFlow.Layout.againHeight == 470, "U1 470")
        expect(WelcomeFlow.hasHero(step: 0) && !WelcomeFlow.hasHero(step: 1) && WelcomeFlow.hasHero(step: 2), "A1 and T carry heroes, A2 does not")
    }

    // 减少动态效果：翻页只淡化不位移；窗口不走弹簧。
    static func reducedMotion() {
        let normal = WelcomeFlow.transition(reduceMotion: false)
        let reduced = WelcomeFlow.transition(reduceMotion: true)
        expect(normal.fadeOut == 0.10 && normal.fadeIn == 0.18 && normal.rise == 6, "normal: out 0.10, in 0.18, rise 6 pt")
        expect(reduced.fadeOut == 0.10 && reduced.fadeIn == 0.18 && reduced.rise == 0, "reduced: same fades, no displacement")
        expect(normal.animatesWindow && !reduced.animatesWindow, "reduced: the window height switches under the fade")
    }

    // 窗口高度弹簧：不回弹、换目标沿用速度、停得下来。
    static func heightMotion() {
        let tall = Double(WelcomeFlow.Layout.tourHeight), short = Double(WelcomeFlow.Layout.permissionHeight)
        var m = WelcomeFlow.HeightMotion(at: tall)
        expect(m.height(at: 5) == tall && m.isSettled(at: 5), "a fresh motion rests on its height")
        m.retarget(to: short, at: 10)
        expect(abs(m.height(at: 10) - tall) < 0.0001, "starts from the current height")
        var monotone = true, last = tall, t = 10.0
        while t < 11 { t += 1.0 / 120; let h = m.height(at: t); if h > last + 0.0001 || h < short - 0.0001 { monotone = false }; last = h }
        expect(monotone, "critically damped: no bounce past the target")
        expect(m.isSettled(at: 11.2), "settles")
        var n = WelcomeFlow.HeightMotion(at: tall)
        n.retarget(to: short, at: 0)
        let hMid = n.height(at: 0.1), vMid = n.velocity(at: 0.1)
        n.retarget(to: tall, at: 0.1)
        expect(abs(n.height(at: 0.1) - hMid) < 0.0001, "retarget keeps the current height")
        expect(vMid < 0 && abs(n.velocity(at: 0.1) - vMid) < 0.0001, "retarget keeps the current velocity")
        n.jump(to: short)
        expect(n.height(at: 0) == short && n.isSettled(at: 0), "reduced motion jumps with no leftover speed")
    }
}
