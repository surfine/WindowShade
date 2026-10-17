// 欢迎窗口（1.0.18，设计稿《首次打开 1.0.17 小样》A1 / A2 / T / U1）的状态机、文案和动效数值。
// 纯逻辑，不碰界面，可单测（tests/WelcomeFlowTests.swift）；Welcome.swift 只负责把这里的结论画出来。
// 三页（页码点只数这三页，HIG 上限）：A1 看一遍再试一下（双击标题栏收成卷帘条）；A2 辅助功能（必需）+ 屏幕录制（可选）；
// T 再看四样（刘海、窗口浏览、手势与卷轴、菜单栏，一页分段）。U1“再打开一次这两项”是升级上来缺授权时单独的一页，不算页码。
// “你之前常用哪个？”的答案仍存在 Core/SwitcherOrigin.swift；T 的刘海一段由 Welcome.swift 直接读写它。

import Foundation

enum WelcomeFlow {
    // MARK: 状态机

    static let stepCount = 3
    static let practiceStep = 0
    static let permissionStep = 1
    static let tourStep = 2

    static func clamped(_ step: Int) -> Int { max(0, min(stepCount - 1, step)) }
    static func next(from step: Int) -> Int { clamped(step + 1) }
    static func back(from step: Int) -> Int { clamped(step - 1) }
    /// A1 的“跳过”直接到 T；A2 的“稍后再说”也进 T（算看过）。T 的“跳过”关窗口（见 skipCloses）。
    static func skip(from step: Int) -> Int { tourStep }
    /// T 的“跳过”：直接关窗口，算看过。
    static func skipCloses(from step: Int) -> Bool { clamped(step) == tourStep }
    static func isLast(_ step: Int) -> Bool { clamped(step) == tourStep }
    /// “继续”能不能点：A2 只等辅助功能（屏幕录制可选）；A1、T 随时能。
    static func canAdvance(from step: Int, accessibilityGranted: Bool) -> Bool {
        clamped(step) != permissionStep || accessibilityGranted
    }

    // MARK: A1：先看一遍，再轮到他

    enum PracticeState: Equatable, Sendable {
        /// 演示两轮（他一动手就停）。
        case demo
        /// 轮到他，还没试：“在这里双击”的小牌子出现。
        case idle
        /// 收起了，等他再双击展开。
        case rolled
        /// 展开了：绿色 ✓。
        case done
    }

    /// 练习窗口标题栏上的一次双击之后是什么样子。演示中途双击也算轮到他了。
    static func practice(afterDoubleClick state: PracticeState) -> PracticeState {
        state == .rolled ? .done : .rolled
    }

    /// 练习窗口这时是不是收着的。
    static func practiceIsRolled(_ state: PracticeState) -> Bool { state == .rolled }

    /// “继续”什么时候变主按钮：试完（展开了 ✓）之后。
    static func practiceNextIsPrimary(_ state: PracticeState) -> Bool { state == .done }

    /// 演示演几轮（每轮约 4.1 s），然后停在卷帘条那一帧、轮到他。
    static let demoLoops = 2

    static func practiceStatus(_ state: PracticeState) -> String {
        switch state {
        case .demo: return ""
        case .idle: return WSL10n.text("welcome.a1.yourTurn", zh: "轮到你：在右边那扇窗口的标题栏上双击。")
        case .rolled: return WSL10n.text("welcome.a1.rolled", zh: "收起了。再双击卷帘条，原样展开。")
        case .done: return WSL10n.text("welcome.a1.done", zh: "就这样。别的窗口也一样。")
        }
    }

    // MARK: 文案（过 docs/copy-guide.md）

    /// 都走目录（zh 是语义身份）。用核算属性而不是 `static let`：设置里换语言时窗口还开着，每次取值都要按当前语言重出。
    static var eyebrow: String { WSL10n.text("welcome.title", zh: "欢迎使用 WindowShade") }
    static var practiceTitle: String { WSL10n.text("welcome.a1.title", zh: "双击标题栏，把窗口收起来。") }
    static var practiceLede: String { WSL10n.text("welcome.a1.lede", zh: "窗口收成一条卷帘条，里面的东西都还在。") }
    static var practiceHint: String { WSL10n.text("welcome.a1.hint", zh: "在这里双击") }
    static var permissionTitle: String { WSL10n.text("welcome.a2.title", zh: "让每扇窗口都能收起") }
    static var permissionLede: String {
        PrivacyPaneName.adjust(WSL10n.text("welcome.a2.lede", zh: "刚才那扇是 WindowShade 自己的窗口。收起别的 App 的窗口，要打开辅助功能。"))
    }

    static func title(forStep step: Int, tour segment: TourSegment = .notch) -> String {
        switch clamped(step) {
        case practiceStep: return practiceTitle
        case permissionStep: return permissionTitle
        default: return segment.title
        }
    }

    /// 页码点给读屏的名字：“第 n 页，共 3 页”。n 从 1 数；超出范围按最近的一页读。
    static func pageLabel(_ n: Int) -> String {
        WSL10n.text("welcome.flow.pageOf", zh: "第 %@ 页，共 %@ 页", String(max(1, min(stepCount, n))), String(stepCount))
    }

    // MARK: A2 / U1：授权行

    /// 回到授权页多久还有一项没好，出现“−”那句。U1 一打开就在（升级时最常见的就是“开关开着却没用”）。
    static let stuckHintDelay: Double = 10

    static func showsStuckHint(again: Bool, accessibility: Bool, screenRecording: Bool, secondsOnPage: Double) -> Bool {
        if again { return !accessibility }
        return !(accessibility && screenRecording) && secondsOnPage >= stuckHintDelay
    }

    /// A2 的状态行：辅助功能好了以后请他去别的窗口上试一下。
    static func permissionStatus(accessibility: Bool) -> String {
        accessibility ? WSL10n.text("welcome.a2.try", zh: "现在去任何一扇窗口的标题栏上双击试试。") : ""
    }

    /// U1 的进度字。
    static func againProgress(accessibility: Bool, screenRecording: Bool) -> String {
        if accessibility && screenRecording { return WSL10n.text("welcome.progress.ready", zh: "权限已就绪") }
        if accessibility { return WSL10n.text("welcome.u1.leftScreen", zh: "还差屏幕录制。不开也能用。") }
        return WSL10n.text("welcome.u1.leftBoth", zh: "还差 2 项")
    }

    // MARK: T：再看四样

    enum TourSegment: Int, CaseIterable, Sendable {
        case notch, browse, gestures, menuBar

        /// 这一段有几块演示（按顺序演）：刘海是收进刘海 + 刘海教你，手势与卷轴是两指滑 + 魔法平铺。
        var heroCount: Int {
            switch self {
            case .notch, .gestures: return 2
            case .browse, .menuBar: return 1
            }
        }

        /// 每块演几轮：一段只有一块时演两轮，两块时各演一轮（稿里四段一共约 45–55 s）。
        var loopsPerHero: Int { heroCount > 1 ? 1 : 2 }

        /// 分段上的名字。
        var segmentTitle: String {
            switch self {
            case .notch: return WSL10n.text("settings.section.notch", zh: "刘海")
            case .browse: return WSL10n.text("settings.section.browser", zh: "窗口浏览")
            case .gestures: return WSL10n.text("welcome.tour.seg.gestures", zh: "手势与卷轴")
            case .menuBar: return WSL10n.text("welcome.tour.seg.menuBar", zh: "菜单栏")
            }
        }

        var title: String {
            switch self {
            case .notch: return WSL10n.text("welcome.tour.notch.title", zh: "窗口可以收进刘海")
            case .browse: return WSL10n.text("welcome.tour.browse.title", zh: "停在 Dock 图标上，看它的所有窗口")
            case .gestures: return WSL10n.text("welcome.tour.gestures.title", zh: "两指一滑，窗口就排好")
            case .menuBar: return WSL10n.text("welcome.tour.menuBar.title", zh: "它在菜单栏里")
            }
        }

        var lede: String {
            switch self {
            case .notch: return WSL10n.text("welcome.tour.notch.lede", zh: "朝刘海甩一下标题栏，窗口就收进去；点一下刘海，放回。按了 Mac 上不管用的快捷键，刘海会说一句该按哪个。")
            case .browse: return WSL10n.text("welcome.tour.browse.lede", zh: "指针停一下，这个 App 的窗口就排出来，点哪扇去哪扇。菜单里的“选择窗口…”也行。")
            case .gestures: return WSL10n.text("welcome.tour.gestures.lede", zh: "两指在标题栏上往左、往右滑，占左半屏、右半屏。两指张开，窗口一列挨一列排好；放不下的接成卷轴，两指滑过去。")
            case .menuBar: return WSL10n.text("welcome.tour.menuBar.lede", zh: "WindowShade 没有 Dock 图标。点菜单栏上的这个图标，收起的窗口和设置都在这里。")
            }
        }

        /// “你之前常用哪个？”只放在刘海一段下面（这个答案决定刘海教什么）。
        var asksOrigin: Bool { self == .notch }
        /// 跳过了授权时，菜单栏一段多一行橙色小字。
        var showsMissingAccessibility: Bool { self == .menuBar }

        static var last: TourSegment { .menuBar }
    }

    static var missingAccessibilityNote: String {
        PrivacyPaneName.adjust(WSL10n.text("welcome.tour.noAccessibility", zh: "还没打开辅助功能，现在只能收起 WindowShade 自己的窗口。"))
    }
    static var originQuestion: String { WSL10n.text("welcome.flow.originTitle", zh: "你之前常用哪个？") }
    static var originOptional: String { WSL10n.text("welcome.tour.originOptional", zh: "不选也行") }

    /// T 现在演到哪：哪一段、这一段的第几块；auto 是还在自己往下走（他点了分段、指针停在两块上、按了“继续”就停）。
    struct TourPlayback: Equatable, Sendable {
        var segment: TourSegment
        var hero: Int = 0
        var auto: Bool = true
    }

    /// 两块演示之间停一下（秒）。
    static let tourHeroGap: Double = 0.4

    /// 一块演完之后演什么：这一段还有下一块就演下一块；这一段演完了、还在自己往下走、不是最后一段就跳到下一段；
    /// 否则停在这里（nil）。减少动态效果时不自己往下走。
    static func tour(after playback: TourPlayback, reduceMotion: Bool) -> TourPlayback? {
        if reduceMotion { return nil }
        if playback.hero + 1 < playback.segment.heroCount {
            var next = playback
            next.hero += 1
            return next
        }
        guard playback.auto, let following = TourSegment(rawValue: playback.segment.rawValue + 1) else { return nil }
        return TourPlayback(segment: following, hero: 0, auto: true)
    }

    /// “继续”在 T 里一段一段走；最后一段的“继续”是“开始使用”（关窗口）。返回 nil 就是该关窗口了。
    static func tour(continueFrom segment: TourSegment) -> TourSegment? {
        TourSegment(rawValue: segment.rawValue + 1)
    }

    // MARK: 窗口高度

    /// 窗口内容高度（点）：照稿里画板的尺寸。A2 没有演示块，和 A1 一样高；T 多一排分段、一行可选的单选，高一截。
    enum Layout {
        static let width: CGFloat = 720
        static let padding: CGFloat = 26
        static let top: CGFloat = 40
        static let bottomBar: CGFloat = 64
        static let practiceHeight: CGFloat = 470
        static let permissionHeight: CGFloat = 470
        static let tourHeight: CGFloat = 520
        static let againHeight: CGFloat = 470
        /// 两块 326 × 209，间距 16：整条 668 宽。
        static let heroHeight: CGFloat = 209
        static let heroGap: CGFloat = 20
    }

    static func windowHeight(forStep step: Int) -> CGFloat {
        switch clamped(step) {
        case practiceStep: return Layout.practiceHeight
        case permissionStep: return Layout.permissionHeight
        default: return Layout.tourHeight
        }
    }

    /// A1 和 T 顶上有两块演示；A2、U1 没有。
    static func hasHero(step: Int) -> Bool { clamped(step) != permissionStep }

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
        /// 窗口变高变矮用弹簧；减少动态效果时在淡化的同时直接换高度。
        var animatesWindow: Bool
    }

    static func transition(reduceMotion: Bool) -> StepTransition {
        StepTransition(fadeOut: 0.10, fadeIn: 0.18, rise: reduceMotion ? 0 : 6, animatesWindow: !reduceMotion)
    }
}
