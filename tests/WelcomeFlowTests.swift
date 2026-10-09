// 欢迎窗口三步（M4 样片）的状态机、说明行、减少动态效果、页码读屏、键帽错开：纯逻辑。
import Foundation

@main
struct WelcomeFlowTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        stateMachine()
        optionNotes()
        reducedMotion()
        pageLabels()
        stageAndWindow()
        keycaps()
        heightMotion()
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("welcome flow: all passed")
    }

    // 三步状态机：前进、后退、到头不绕回、跳过、第二步选了才能继续。
    static func stateMachine() {
        expect(WelcomeFlow.stepCount == 3, "three steps")
        expect(WelcomeFlow.next(from: 0) == 1 && WelcomeFlow.next(from: 1) == 2, "forward walks 1 -> 2 -> 3")
        expect(WelcomeFlow.next(from: 2) == 2, "forward stops at the last step")
        expect(WelcomeFlow.back(from: 2) == 1 && WelcomeFlow.back(from: 1) == 0, "back walks 3 -> 2 -> 1")
        expect(WelcomeFlow.back(from: 0) == 0, "back stops at the first step")
        expect((0..<3).allSatisfy { WelcomeFlow.skip(from: $0) == WelcomeFlow.permissionStep }, "skip goes straight to the permission step")
        expect(WelcomeFlow.clamped(-4) == 0 && WelcomeFlow.clamped(9) == 2, "out-of-range steps are clamped")
        expect(WelcomeFlow.isLast(2) && !WelcomeFlow.isLast(1), "only step 3 is last")
        expect(!WelcomeFlow.canAdvance(from: 1, origin: .unanswered), "step 2 cannot continue until an option is picked")
        expect([SwitcherOrigin.windows, .ipad, .mac].allSatisfy { WelcomeFlow.canAdvance(from: 1, origin: $0) }, "step 2 continues after any answer")
        expect(WelcomeFlow.canAdvance(from: 0, origin: .unanswered) && WelcomeFlow.canAdvance(from: 2, origin: .unanswered), "steps 1 and 3 never wait for an answer")
        // 选项切换：每次选都换说明行，退回没答也换。
        var seen: [String] = []
        for origin in [SwitcherOrigin.unanswered, .windows, .ipad, .mac, .unanswered] { seen.append(WelcomeFlow.originNote(for: origin)) }
        expect(zip(seen, seen.dropFirst()).allSatisfy { $0 != $1 }, "switching the option switches the note line")
        expect(WelcomeFlow.title(forStep: 0) == "刚换 Mac？从刘海开始。" && WelcomeFlow.title(forStep: 1) == "你之前常用哪个？"
               && WelcomeFlow.title(forStep: 2) == "最后一步：授权", "step titles")
        expect(WelcomeFlow.eyebrow(forStep: 0) == "欢迎使用 WindowShade" && WelcomeFlow.eyebrow(forStep: 1).isEmpty, "only step 1 carries the welcome eyebrow")
        expect(WelcomeFlow.introLede == "按了 Windows 的快捷键没反应时，刘海说一句 Mac 上按哪一下。顺利的时候，它不出声。", "step 1 lede")
    }

    // 四种说明行，逐字对样片。
    static func optionNotes() {
        expect(WelcomeFlow.originNote(for: .windows) == "拷贝、粘贴用拇指按 ⌘，就在你原来按 Alt 的地方。其余的，卡住时刘海会说。", "note for Windows")
        expect(WelcomeFlow.originNote(for: .ipad) == "在 Mac 上，菜单要两指点按，和 iPad 接触控板时一样。卡住时刘海会说。", "note for iPad")
        expect(WelcomeFlow.originNote(for: .mac) == "那刘海多半不会开口。设置里随时能改。", "note for always-Mac")
        expect(WelcomeFlow.originNote(for: .unanswered) == "选一个，刘海按你的习惯来教。", "note when nothing is picked")
    }

    // 减少动态效果：翻页只淡化不位移；键帽不弹；窗口不走弹簧。
    static func reducedMotion() {
        let normal = WelcomeFlow.transition(reduceMotion: false)
        let reduced = WelcomeFlow.transition(reduceMotion: true)
        expect(normal.fadeOut == 0.10 && normal.fadeIn == 0.18 && normal.rise == 6, "normal: out 0.10, in 0.18, rise 6 pt")
        expect(reduced.fadeOut == 0.10 && reduced.fadeIn == 0.18, "reduced: same fades")
        expect(reduced.rise == 0, "reduced: no displacement")
        expect(normal.animatesWindow && !reduced.animatesWindow, "reduced: the window height switches under the fade")
        expect(WelcomeFlow.keySwapPlan(reduceMotion: true).steps.allSatisfy { $0.popFrom == 1 }, "reduced: keycaps do not pop")
        expect(WelcomeFlow.keySwapPlan(reduceMotion: false).steps.allSatisfy { $0.popFrom == 0.9 }, "normal: new keycap text pops from 0.9")
    }

    // 页码点读屏“第 n 页”。
    static func pageLabels() {
        expect((1...3).map(WelcomeFlow.pageLabel) == ["第 1 页", "第 2 页", "第 3 页"], "page dots read 第 n 页")
        expect(WelcomeFlow.pageLabel(0) == "第 1 页" && WelcomeFlow.pageLabel(7) == "第 3 页", "page label stays inside 1...3")
    }

    // 舞台高度和窗口：第 3 步不放舞台，窗口矮一截，舞台比例从窗口高度反推。
    static func stageAndWindow() {
        typealias L = WelcomeFlow.Layout
        expect(WelcomeFlow.hasStage(step: 0) && WelcomeFlow.hasStage(step: 1) && !WelcomeFlow.hasStage(step: 2), "steps 1 and 2 have the stage, step 3 does not")
        expect(WelcomeFlow.windowHeight(forStep: 0) == WelcomeFlow.windowHeight(forStep: 1), "steps 1 and 2 share one window height")
        expect(WelcomeFlow.windowHeight(forStep: 2) < WelcomeFlow.windowHeight(forStep: 1), "step 3 window is shorter")
        expect(WelcomeFlow.stageFraction(forWindowHeight: WelcomeFlow.windowHeight(forStep: 0)) == 1, "full window shows the whole stage")
        expect(WelcomeFlow.stageFraction(forWindowHeight: WelcomeFlow.windowHeight(forStep: 2)) == 0, "short window shows no stage")
        let mid = (WelcomeFlow.windowHeight(forStep: 0) + WelcomeFlow.windowHeight(forStep: 2)) / 2
        expect(abs(WelcomeFlow.stageFraction(forWindowHeight: mid) - 0.5) < 0.0001, "halfway window shows half the stage")
        expect(WelcomeFlow.stageFraction(forWindowHeight: 9999) == 1 && WelcomeFlow.stageFraction(forWindowHeight: 0) == 0, "stage fraction is clamped")
        expect(L.stageHeight > 0 && L.heightWithStage > L.heightWithoutStage, "layout constants are consistent")
        expect(WelcomeFlow.introLoopRounds == 3 && WelcomeFlow.introRestMoment == 0.5, "step 1 plays 3 rounds then rests on the open frame")
    }

    // 键帽：Windows 的四颗原地换成 Mac 的，错开 60 ms，最后 ⌘ 亮起。
    static func keycaps() {
        expect(WelcomeFlow.windowsKeyNames == ["Ctrl", "Fn", "⊞", "Alt"], "Windows keycaps")
        expect(WelcomeFlow.macKeyNames == ["fn", "control", "option", "command"], "Mac keycaps in the same positions")
        expect(WelcomeFlow.macKeyNames[WelcomeFlow.litKeyIndex] == "command", "the lit key is command, where Alt was")
        expect(WelcomeFlow.keycapsShown(for: .windows), "Windows shows the swap")
        expect([SwitcherOrigin.ipad, .mac, .unanswered].allSatisfy { !WelcomeFlow.keycapsShown(for: $0) }, "other answers show no swap")
        let plan = WelcomeFlow.keySwapPlan(reduceMotion: false)
        expect(plan.steps.map(\.index) == [0, 1, 2, 3], "four keycaps swap in order")
        let starts = plan.steps.map(\.oldFadeStart)
        expect(zip(starts, starts.dropFirst()).allSatisfy { abs(($1 - $0) - 0.06) < 0.0001 }, "staggered by 60 ms")
        expect(plan.steps.allSatisfy { $0.oldFadeDuration == 0.10 && $0.newFadeDuration == 0.18 && abs($0.newFadeStart - $0.oldFadeStart - 0.05) < 0.0001 },
               "old text fades out 0.10, new fades in 0.18 right behind")
        expect(plan.glowFrom == 0.14 && plan.glowTo == 0.28, "command fill 0.14 -> 0.28")
        expect(plan.glowStart > plan.steps[0].oldFadeStart, "command lights up after the swap starts")
        expect(WelcomeFlow.keySwapPlan(reduceMotion: true).steps.map(\.oldFadeStart) == starts, "reduced motion keeps the same order and stagger")
    }

    // 窗口高度弹簧：不回弹、换目标沿用速度、停得下来。
    static func heightMotion() {
        let tall = Double(WelcomeFlow.Layout.heightWithStage), short = Double(WelcomeFlow.Layout.heightWithoutStage)
        var m = WelcomeFlow.HeightMotion(at: tall)
        expect(m.height(at: 5) == tall && m.isSettled(at: 5), "a fresh motion rests on its height")
        m.retarget(to: short, at: 10)
        expect(abs(m.height(at: 10) - tall) < 0.0001, "starts from the current height")
        var monotone = true, last = tall, t = 10.0
        while t < 11 { t += 1.0 / 120; let h = m.height(at: t); if h > last + 0.0001 || h < short - 0.0001 { monotone = false }; last = h }
        expect(monotone, "critically damped: no bounce past the target")
        expect(m.isSettled(at: 10.8) && abs(m.height(at: 11) - short) < 0.5, "settles within a calm 0.8 s")
        // 中途换目标：位置连续、速度连续（不从零速度重起）。
        var n = WelcomeFlow.HeightMotion(at: tall)
        n.retarget(to: short, at: 0)
        let hMid = n.height(at: 0.1), vMid = n.velocity(at: 0.1)
        n.retarget(to: tall, at: 0.1)
        expect(abs(n.height(at: 0.1) - hMid) < 0.0001, "retarget keeps the current height")
        expect(vMid < 0 && abs(n.velocity(at: 0.1) - vMid) < 0.0001, "retarget keeps the current velocity")
        expect(n.height(at: 0.12) < hMid, "momentum carries on before turning back")
        expect(n.isSettled(at: 1.2) && abs(n.height(at: 1.2) - tall) < 0.5, "turns around and settles on the new target")
        n.jump(to: short)
        expect(n.height(at: 0) == short && n.isSettled(at: 0), "reduced motion jumps with no leftover speed")
    }
}
