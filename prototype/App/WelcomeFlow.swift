// 欢迎窗口三步（M4 样片，docs/design-drafts/安静的刘海 动效样片.html）的状态机、文案和动效数值。
// 纯逻辑，不碰界面，可单测（tests/WelcomeFlowTests.swift）；Welcome.swift 只负责把这里的结论画出来。
// 三步：1 刚换 Mac？从刘海开始（舞台上一段短动画）；2 你之前常用哪个（舞台左下四颗键帽）；3 授权（不放舞台，窗口变矮）。
// 来处的存取在 Core/SwitcherOrigin.swift，这里只读它的四种答案。

import Foundation

enum WelcomeFlow {
    // MARK: 状态机

    static let stepCount = 3
    static let introStep = 0
    static let originStep = 1
    static let permissionStep = 2

    static func clamped(_ step: Int) -> Int { max(0, min(stepCount - 1, step)) }
    static func next(from step: Int) -> Int { clamped(step + 1) }
    static func back(from step: Int) -> Int { clamped(step - 1) }
    /// “跳过”：任何一步都直接到授权页；来处没答就算没答。
    static func skip(from step: Int) -> Int { permissionStep }
    static func isLast(_ step: Int) -> Bool { clamped(step) == permissionStep }
    /// “继续”能不能点：第二步选了才能继续，其余的步随时能。
    static func canAdvance(from step: Int, origin: SwitcherOrigin) -> Bool {
        step != originStep || origin.isAnswered
    }

    // MARK: 文案（过 docs/copy-guide.md）

    static let introEyebrow = "欢迎使用 WindowShade"
    static let introTitle = "刚换 Mac？从刘海开始。"
    static let introLede = "按了 Windows 的快捷键没反应时，刘海说一句 Mac 上按哪一下。顺利的时候，它不出声。"
    static let originTitle = "你之前常用哪个？"
    static let permissionTitle = "最后一步：授权"
    static let permissionLede = "辅助功能让 WindowShade 能移动窗口，屏幕录制让它能显示实时画面。两项都打开就能用了。"

    /// 第二步选项下面那一行，按选项换。
    static func originNote(for origin: SwitcherOrigin) -> String {
        switch origin {
        case .windows: return "拷贝、粘贴用拇指按 ⌘，就在你原来按 Alt 的地方。其余的，卡住时刘海会说。"
        case .ipad: return "在 Mac 上，菜单要两指点按，和 iPad 接触控板时一样。卡住时刘海会说。"
        case .mac: return "那刘海多半不会开口。设置里随时能改。"
        case .unanswered: return "选一个，刘海按你的习惯来教。"
        }
    }

    static func title(forStep step: Int) -> String {
        switch clamped(step) {
        case introStep: return introTitle
        case originStep: return originTitle
        default: return permissionTitle
        }
    }

    /// 小标题：只有第一步有（“欢迎使用 WindowShade”），页数交给页码点。
    static func eyebrow(forStep step: Int) -> String { step == introStep ? introEyebrow : "" }

    /// 页码点给读屏的名字。n 从 1 数；超出范围按最近的一页读。
    static func pageLabel(_ n: Int) -> String { "第 \(max(1, min(stepCount, n))) 页" }

    // MARK: 舞台和窗口高度

    /// 舞台只给前两步；第三步是授权行，不放舞台。
    static func hasStage(step: Int) -> Bool { clamped(step) != permissionStep }

    /// 窗口内容高度（点）：有舞台的两步一样高，授权页没有舞台所以矮一截。窗口高度是唯一的形变，
    /// 舞台的可见比例从窗口高度反推（见 stageFraction），所以窗口怎么动，舞台和文字就怎么跟。
    enum Layout {
        static let width: CGFloat = 720
        static let padding: CGFloat = 26
        static let top: CGFloat = 40
        static let stageHeight: CGFloat = 300
        static let stageGap: CGFloat = 20
        /// 标题、选项、说明行这一块（有舞台的两步里最高的那一步）。
        static let contentHeight: CGFloat = 170
        /// 授权页：小标题、标题、导语之后是授权行（进度字加两行卡片）。
        /// 授权行有三行（辅助功能、屏幕录制、日程），每行约 49 点。
        static let permissionContentHeight: CGFloat = 345
        static let bottomBar: CGFloat = 64
        static let heightWithStage: CGFloat = top + stageHeight + stageGap + contentHeight + bottomBar
        static let heightWithoutStage: CGFloat = top + permissionContentHeight + bottomBar
    }

    static func windowHeight(forStep step: Int) -> CGFloat {
        hasStage(step: step) ? Layout.heightWithStage : Layout.heightWithoutStage
    }

    /// 舞台露出多少（0 是收没了，1 是整块）：从窗口现在的高度反推，窗口在 calm 里变矮时舞台跟着收。
    static func stageFraction(forWindowHeight height: CGFloat) -> CGFloat {
        let span = Layout.heightWithStage - Layout.heightWithoutStage
        return max(0, min(1, (height - Layout.heightWithoutStage) / span))
    }

    // MARK: 窗口高度的弹簧

    /// 窗口高度逐帧由 FlickSpring.calm 驱动：不用贝塞尔。中途换目标（连点“继续”）时，
    /// 从当前位置和当前速度接着走，不重新从零速度起步。停稳（离目标不到半点、速度很小）就该停帧。
    struct HeightMotion: Equatable {
        private(set) var target: Double
        private var displacement: Double
        private var velocity: Double
        private var start: Double
        let spring: FlickSpring

        init(at height: Double, spring: FlickSpring = .calm) {
            self.target = height; self.displacement = 0; self.velocity = 0; self.start = 0; self.spring = spring
        }

        func height(at time: Double) -> Double {
            target + spring.state(displacement: displacement, velocity: velocity, at: max(0, time - start)).x
        }

        func velocity(at time: Double) -> Double {
            spring.state(displacement: displacement, velocity: velocity, at: max(0, time - start)).v
        }

        func isSettled(at time: Double) -> Bool {
            abs(height(at: time) - target) < 0.5 && abs(velocity(at: time)) < 5
        }

        /// 换目标：位置、速度都沿用此刻的。
        mutating func retarget(to newTarget: Double, at time: Double) {
            let now = height(at: time), v = velocity(at: time)
            target = newTarget
            displacement = now - newTarget
            velocity = v
            start = time
        }

        /// 不动画（减少动态效果）：直接落在目标上，速度清零。
        mutating func jump(to newTarget: Double) {
            target = newTarget; displacement = 0; velocity = 0; start = 0
        }
    }

    // MARK: 翻页（同一个窗口里换内容）

    struct StepTransition: Equatable {
        /// 旧内容淡出（秒）。
        var fadeOut: Double
        /// 新内容淡入（秒）。
        var fadeIn: Double
        /// 新内容从下面上浮多少点；减少动态效果时是 0（只淡化，不位移）。
        var rise: Double
        /// 窗口变矮用弹簧；减少动态效果时在淡化的同时直接换高度。
        var animatesWindow: Bool
    }

    static func transition(reduceMotion: Bool) -> StepTransition {
        StepTransition(fadeOut: 0.10, fadeIn: 0.18, rise: reduceMotion ? 0 : 6, animatesWindow: !reduceMotion)
    }

    // MARK: 第一步的动画

    /// 整轮播几遍后停下。
    static let introLoopRounds = 3
    /// 停在一轮里的哪一刻（开口帧：刘海说出 Mac 上那一下、键帽已换成 ⌘）。
    static let introRestMoment = 0.5

    // MARK: 第二步的键帽

    /// 左下四颗键帽的字，按位置对应：Windows 键盘上的 Ctrl / Fn / ⊞ / Alt，原地换成 Mac 的 fn / control / option / command。
    static let windowsKeyNames = ["Ctrl", "Fn", "⊞", "Alt"]
    static let macKeyNames = ["fn", "control", "option", "command"]
    /// 最后亮起的是 ⌘（第四颗）：你原来按 Alt 的地方。
    static let litKeyIndex = 3

    /// 只有答 Windows 时才换键帽；其余答案（含没答）键帽不出现。
    static func keycapsShown(for origin: SwitcherOrigin) -> Bool { origin == .windows }

    struct KeySwapStep: Equatable {
        let index: Int
        /// 以下都是从“选了 Windows”那一刻起算的秒数。
        let oldFadeStart: Double
        let oldFadeDuration: Double
        let newFadeStart: Double
        let newFadeDuration: Double
        /// 新字弹出时从这个比例长到 1；1 就是不弹（减少动态效果）。
        let popFrom: Double
    }

    struct KeySwapPlan: Equatable {
        let steps: [KeySwapStep]
        /// ⌘ 填充（白）从 glowFrom 升到 glowTo，从 glowStart 起、用 glowDuration（calm 的时长）。
        let glowStart: Double
        let glowDuration: Double
        let glowFrom: Double
        let glowTo: Double
    }

    static let keySwapLeadIn = 0.45
    static let keySwapStagger = 0.06

    static func keySwapPlan(reduceMotion: Bool) -> KeySwapPlan {
        let steps = (0..<4).map { i -> KeySwapStep in
            let start = keySwapLeadIn + keySwapStagger * Double(i)
            return KeySwapStep(index: i, oldFadeStart: start, oldFadeDuration: 0.10,
                               newFadeStart: start + 0.05, newFadeDuration: 0.18, popFrom: reduceMotion ? 1 : 0.9)
        }
        // 样片的时刻：换字开始 0.45 s 后，加一次淡入的 0.18 s 和 0.25 s 的停顿，⌘ 亮起（最后一颗换完的这一刻之后）。
        return KeySwapPlan(steps: steps, glowStart: keySwapLeadIn + 0.18 + 0.25,
                           glowDuration: 0.34, glowFrom: 0.14, glowTo: 0.28)
    }
}
