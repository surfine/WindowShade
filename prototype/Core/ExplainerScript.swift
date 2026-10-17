// 设置窗口与欢迎窗口共用的讲解动画（设计稿《首次打开 1.0.17 小样》E 节与“分镜”节，1.0.18 工作单 6）。
// 这一层是纯逻辑：帧数据、按弹簧令牌算时长、页 / 行 / 选项 / 关着的状态机。不碰视图，可单测
// （tests/run-explainer-tests.sh）。画面在 App/SettingsExplainerView.swift，接行在 App/SettingsExplainerHost.swift。
//
// ── 给各页的人：只要做三件事，不用动共用文件 ──────────────────────────────────────────────
// 1. 新建 Core/ExplainerScenes+<页名>.swift，在 `extension ExplainerScenes` 里写这一页独有的场景
//    （`static var 名字: ExplainerSpec { … }`）；通用场景（双击收起、两指滑、收进刘海、窗口挪到某一格、
//    面板升起、刘海说一句、键帽、Dock 图标）已经在 ExplainerScenes+Common.swift，直接用或用 `variant` 改。
//    读屏说明句一律走 WSL10n.setting，键名 explainer.<场景>.ax，中文以“演示：”开头，三语进 Localizable.xcstrings。
// 2. 在同一个文件里给这一页一个 `ExplainerPage`：`ExplainerPage(id: "<页>", pageDefault: <场景>)`。
// 3. 在 Preferences.swift 这一页的建页函数里：`makeSettingsPageRoot(explainer: .<页>)`，再给每个行构造器
//    填 `explainer:`——`.loop(场景)`（指上去循环演）、`.still(场景)`（摆一帧不动）、`.pageDefault`
//    （和屏幕上看到的无关，回到页默认的关键帧）、`.options([场景…])`（分段控件，每段一个场景）。
//    有开关的行，开关关着时自动降灰并标“关着”；要换成另一段画面（例如“关掉动画”），给 `offScene:`。
//
// 坐标：每块 312 × 200，从左上角量（和稿里一样）；欢迎窗口按 326 / 312 等比放大，帧数据不改。
// 时长：一轮 = 0.14 s 开场（两块淡出 0.10 + 0.04）+ Σ 每帧（这一帧里最慢的令牌时长 + 停留）；
// 重摆（reset）一帧算 0.32 s（淡出 0.10 + 淡入 0.18 + 0.04）。弹簧令牌的时长与稿里的脚本同一算法：
// 从 0 走到 1 的阶跃响应，离终点 0.2% 以内且 0.05 s 后仍在以内的最早时刻（0.005 s 一格，保留 3 位）。
// ────────────────────────────────────────────────────────────────────────────────────────

import CoreGraphics
import Foundation

/// 一帧里每个元素用哪种动法。弹簧照设计系统 §4.6（`MotionSpring`）；按下 / 松开是 0.08 s 直接切换；
/// fade 是两段之间的淡入时长 0.18 s；none 不动画。
enum ExplainerEasing: String, Sendable, CaseIterable {
    case calm, settle, pop, bloom, flyOut, expand, tap, fade, none

    var spring: MotionSpring? {
        switch self {
        case .calm: return .calm
        case .settle: return .settle
        case .pop: return .pop
        case .bloom: return .bloom
        case .flyOut: return .flyOut
        case .expand: return .expand
        case .tap, .fade, .none: return nil
        }
    }

    /// 这一种动法占多长（秒）。
    var duration: Double {
        switch self {
        case .tap: return ExplainerTiming.tap
        case .fade: return ExplainerTiming.fadeIn
        case .none: return 0
        default: return spring.map { ExplainerTiming.settlingTime(of: $0) } ?? 0
        }
    }
}

enum ExplainerTiming {
    static let tap = 0.08
    /// 两段讲解之间：两块一起淡出 0.10 s，再淡入 0.18 s（§4.6 fade）。
    static let fadeOut = 0.10
    static let fadeIn = 0.18
    /// 换好内容到第一帧开始动之间的一小拍。
    static let leadIn = 0.04
    /// 一轮开场：淡出完、停一小拍，第一帧才开始。
    static var loopStart: Double { fadeOut + leadIn }
    /// 一轮里的重摆：淡出、换回初始、淡入、一小拍。
    static var resetCost: Double { fadeOut + fadeIn + leadIn }
    /// 页打开时页默认讲解演几轮。
    static let pageLoops = 2
    /// 同一行最多连演几轮。
    static let rowLoopCap = 6
    /// 低电量时一行只演几轮。
    static let lowPowerRowLoops = 1
    /// 关着时两块的不透明度。
    static let dimmedOpacity = 0.55

    /// 弹簧从 0 到 1 的阶跃响应落定时刻（见文件头）。和稿里的脚本逐格同算，所以文档里的“一轮 n 秒”对得上。
    static func settlingTime(of token: MotionSpring) -> Double {
        let spring = FlickSpring(dampingRatio: token.dampingRatio, response: token.response)
        func off(_ t: Double) -> Double { abs(spring.state(displacement: -1, velocity: 0, at: t).x) }
        var index = 0
        while Double(index) * 0.005 < 4 {
            let t = Double(index) * 0.005
            if off(t) < 0.002, off(t + 0.05) < 0.002 { return (t * 1000).rounded() / 1000 }
            index += 1
        }
        return token.response * 2.5
    }
}

/// 两块里的元素。前一组在右块（迷你桌面），后一组在左块（设备）。
enum ExplainerElement: String, Sendable, CaseIterable {
    case windowA, windowB, windowC, panel, dock, pointer, notch, notchLine, menuBarIcon, menu, cover
    case finger1, finger2, key1, key2, deviceText

    var onDeviceTile: Bool {
        switch self {
        case .finger1, .finger2, .key1, .key2, .deviceText: return true
        default: return false
        }
    }
}

/// 窗口、面板换样子（稿里的 class）。
enum ExplainerLook: String, Sendable, CaseIterable {
    case plain, unified, thumbnail, privatePreview, livePreview, highlight1, highlight2, highlight3, file
}

/// 键帽：大字和下面的小字（例如 ⌘ / command）。
struct ExplainerKeyCap: Equatable, Sendable {
    var symbol: String
    var caption: String
}

/// 一个元素的一次改动：只写要变的那几项，其余沿用上一帧。
struct ExplainerPatch: Equatable, Sendable {
    var x: Double? = nil
    var y: Double? = nil
    var w: Double? = nil
    var h: Double? = nil
    var opacity: Double? = nil
    var scale: Double? = nil
    /// 指尖按下（缩到 0.8）。
    var pressed: Bool? = nil
    /// 窗口收成卷帘条（内容行淡掉）。
    var rolled: Bool? = nil
    /// 窗口亮边、菜单栏图标亮框。
    var highlighted: Bool? = nil
    var keyCap: ExplainerKeyCap? = nil
    /// 这个元素上写的字（文字块、遮罩）。已经是当前语言的句子。
    var text: String? = nil
    var look: ExplainerLook? = nil
    /// 只给这个元素换动法（稿里的 `_e`）；nil 用这一帧的。
    var easing: ExplainerEasing? = nil

    /// 叠到旧状态上：新写的项盖掉旧的，没写的留着。动法不留到下一帧。
    func applied(onto base: ExplainerPatch) -> ExplainerPatch {
        var out = base
        if let x { out.x = x }
        if let y { out.y = y }
        if let w { out.w = w }
        if let h { out.h = h }
        if let opacity { out.opacity = opacity }
        if let scale { out.scale = scale }
        if let pressed { out.pressed = pressed }
        if let rolled { out.rolled = rolled }
        if let highlighted { out.highlighted = highlighted }
        if let keyCap { out.keyCap = keyCap }
        if let text { out.text = text }
        if let look { out.look = look }
        out.easing = nil
        return out
    }
}

typealias ExplainerState = [ExplainerElement: ExplainerPatch]

/// 一帧：一组改动、动法、停留。`isKey` 是关键帧（停住、截图、减少动态效果都摆这一帧），
/// `inStoryboard` 是分镜里摆出来的那几格（稿里的 k）。`reset` 帧把两块淡出、换回初始再淡入。
struct ExplainerFrame: Equatable, Sendable {
    /// 只给日志与分镜看的英文名，不对用户显示。
    var label: String
    var easing: ExplainerEasing
    var set: ExplainerState
    var hold: Double
    var isKey: Bool
    var inStoryboard: Bool
    var isReset: Bool

    init(_ label: String = "", _ easing: ExplainerEasing = .calm, _ set: ExplainerState,
         hold: Double = 0, key: Bool = false, story: Bool = false) {
        self.label = label
        self.easing = easing
        self.set = set
        self.hold = hold
        self.isKey = key
        self.inStoryboard = story || key
        self.isReset = false
    }

    static var reset: ExplainerFrame {
        var frame = ExplainerFrame("reset", .none, [:])
        frame.isReset = true
        return frame
    }

    /// 这一帧占多长：最慢那个元素的令牌时长 + 停留。没有改动的帧只算停留；重摆帧固定 0.32 s。
    var duration: Double {
        if isReset { return ExplainerTiming.resetCost }
        let slowest = set.values.map { ($0.easing ?? easing).duration }.max() ?? 0
        return slowest + hold
    }
}

/// 左块画什么：点按、两指、按住再移动、键盘、指针、一句话、静止的触控板。
enum ExplainerDevice: String, Sendable {
    case click, twoFinger, press, keys, point, text, pad
}

/// 减少动态效果和停住时叠的箭头与原位虚线框。路径用稿里的 SVG 写法（M / L / l，312 × 200 坐标）。
struct ExplainerArrows: Equatable, Sendable {
    var device: String = ""
    var result: String = ""
    var ghost: CGRect? = nil
}

/// 一段讲解。`id` 唯一；`description` 是读屏说明句（也挂到行的 accessibilityHelp）。
struct ExplainerSpec: Equatable {
    var id: String
    var device: ExplainerDevice
    /// 只有触控板能做（只连鼠标时左块仍画触控板，底下写“要用触控板”）。
    var trackpadOnly = false
    var initial: ExplainerState
    var frames: [ExplainerFrame]
    var arrows = ExplainerArrows()
    var description: SettingsText
    /// 左块的一句话（device == .text）。
    var deviceText: SettingsText? = nil
    /// 刘海说的两行。
    var notchLine: (title: SettingsText, detail: SettingsText)? = nil
    /// 没有帧也不是静图时强制摆一帧（稿里的 forceStill）。
    var forceStill = false

    static func == (lhs: ExplainerSpec, rhs: ExplainerSpec) -> Bool { lhs.id == rhs.id }

    /// 静图：没有帧，摆初始那一帧。
    var isStill: Bool { frames.isEmpty || forceStill }

    /// 关键帧下标：最后一个标了 `key` 的帧；没有就是 nil（摆初始）。
    var keyFrameIndex: Int? { frames.lastIndex { $0.isKey } }

    /// 稿里 `variant`：复制一份改几处，换 id 和说明句。
    func variant(id: String, description: SettingsText, _ change: (inout ExplainerSpec) -> Void) -> ExplainerSpec {
        var copy = self
        copy.id = id
        copy.description = description
        change(&copy)
        return copy
    }

    /// 演到第 index 帧结束时的整组状态（reset 帧换回初始）。index 为 nil 是初始。
    func state(throughFrame index: Int?) -> ExplainerState {
        var state = initial.mapValues { $0.applied(onto: ExplainerPatch()) }
        guard let index else { return state }
        for frame in frames.prefix(index + 1) {
            if frame.isReset { state = initial.mapValues { $0.applied(onto: ExplainerPatch()) }; continue }
            for (element, patch) in frame.set {
                state[element] = patch.applied(onto: state[element] ?? ExplainerPatch())
            }
        }
        return state
    }

    /// 关键帧那一刻的样子（停住、减少动态效果、截图）。
    var keyState: ExplainerState { state(throughFrame: keyFrameIndex) }

    var timeline: ExplainerTimeline { ExplainerTimeline(self) }
}

/// 一轮的时间表：每帧从第几秒开始、一轮多长。
struct ExplainerTimeline: Equatable, Sendable {
    let starts: [Double]
    let loopDuration: Double

    init(_ spec: ExplainerSpec) {
        var t = ExplainerTiming.loopStart
        var starts: [Double] = []
        for frame in spec.frames {
            starts.append(t)
            t += frame.duration
        }
        self.starts = starts
        loopDuration = spec.frames.isEmpty ? 0 : t
    }
}

/// 一页：页默认讲解。
struct ExplainerPage: Equatable {
    var id: String
    var pageDefault: ExplainerSpec
}

/// 一行怎么接讲解（行构造器的 `explainer:` 参数）。
struct ExplainerRow: Equatable {
    enum Kind: Equatable {
        /// 指上去循环演这一段。
        case loop(ExplainerSpec)
        /// 摆一帧不动。
        case still(ExplainerSpec)
        /// 和屏幕上的变化无关：回到页默认的关键帧。
        case pageDefault
        /// 分段控件：每段一段讲解，下标对上分段。
        case options([ExplainerSpec])
    }
    var kind: Kind
    /// 开关关着时改演这一段（不降灰），例如“关掉动画”。
    var offScene: ExplainerSpec? = nil

    static func loop(_ spec: ExplainerSpec, offScene: ExplainerSpec? = nil) -> ExplainerRow { ExplainerRow(kind: .loop(spec), offScene: offScene) }
    static func still(_ spec: ExplainerSpec) -> ExplainerRow { ExplainerRow(kind: .still(spec)) }
    static var pageDefault: ExplainerRow { ExplainerRow(kind: .pageDefault) }
    static func options(_ specs: [ExplainerSpec]) -> ExplainerRow { ExplainerRow(kind: .options(specs)) }

    /// 这一行的读屏说明句（挂到 accessibilityHelp）：选中那一段的；页默认没有。
    func description(option: Int?) -> SettingsText? {
        switch kind {
        case .loop(let spec), .still(let spec): return spec.description
        case .pageDefault: return nil
        case .options(let specs):
            guard !specs.isEmpty else { return nil }
            return specs[min(max(option ?? 0, 0), specs.count - 1)].description
        }
    }
}

// MARK: - 状态机

/// 讲解带此刻该摆什么。视图只照这个做；换内容时按 `transition` 换。
struct ExplainerPresentation: Equatable {
    enum Mode: Equatable {
        /// 演 loops 轮，演完停在关键帧（不加箭头）。
        case play(loops: Int)
        /// 停在关键帧。arrows：叠箭头与虚线框（减少动态效果）。
        case hold(arrows: Bool)
    }
    enum Transition: Equatable {
        /// 两块淡出 0.10、淡入 0.18。
        case crossfade
        /// 直接替换（减少动态效果、第一次摆、截图）。
        case instant
        /// 同一段，只改降灰（用 calm 回到全彩）或停住，不换内容。
        case inPlace
    }
    var spec: ExplainerSpec
    var mode: Mode
    var dimmed: Bool
    var transition: Transition
    /// 换了讲解：发一次 polite 播报。
    var announces: Bool
}

/// 页 / 行 / 选项 / 关着的状态机（稿 E 节“规则”表）。视图把事件喂进来，照返回的 `ExplainerPresentation` 摆；
/// 返回 nil 是不用变。纯值类型，测试直接喂事件。
struct ExplainerDirector {
    /// 一行此刻的样子：host 每次喂事件时现读。
    struct RowState: Equatable {
        var id: Int
        var row: ExplainerRow
        /// nil = 这一行没有开关。
        var isOn: Bool?
        /// 分段控件现在选的是第几段。
        var selectedOption: Int?
    }
    struct Environment: Equatable {
        var reduceMotion = false
        var lowPower = false
        /// 窗口在最前、没被挡住、没最小化、在这块桌面上。
        var visible = true
    }
    enum Event: Equatable {
        case openPage
        case enter(RowState)
        case exit(rowID: Int)
        /// 点了行（不是控件）：选住，再点放开。
        case click(RowState)
        /// 指针停在分段控件的另一段上（不改设置）。
        case hoverOption(RowState, option: Int)
        case leaveOption(RowState)
        /// 开关拨了、分段选了：现读的新状态。
        case rowChanged(RowState)
        /// 视图演完了上一次 `.play` 要的轮数（带上那一段的 id，过时的不算）。
        case loopsFinished(String)
        case environment(Environment)
    }

    let page: ExplainerPage
    private(set) var environment: Environment
    private(set) var current: ExplainerPresentation?
    /// 指针（或键盘焦点）在哪一行。
    private(set) var hovered: RowState?
    /// 点选住的行。
    private(set) var selected: RowState?
    private var hoveredOption: Int?
    /// 页默认已经演过：回到页时只摆关键帧，不重演。
    private(set) var pagePlayed = false
    /// 正在演的这一段还没演完就看不见了：回来从头演。
    private var interrupted = false

    init(page: ExplainerPage, environment: Environment = Environment(), pagePlayed: Bool = false) {
        self.page = page
        self.environment = environment
        self.pagePlayed = pagePlayed
    }

    mutating func handle(_ event: Event) -> ExplainerPresentation? {
        switch event {
        case .openPage:
            return show(target(), fresh: true)
        case .enter(let row):
            hovered = row
            hoveredOption = nil
            return show(target(), fresh: true)
        case .exit(let id):
            guard hovered?.id == id else { return nil }
            hovered = nil
            hoveredOption = nil
            return show(target(), fresh: true)
        case .click(let row):
            selected = selected?.id == row.id ? nil : row
            hovered = row
            return show(target(), fresh: true)
        case .hoverOption(let row, let option):
            hovered = row
            hoveredOption = option
            return show(target(), fresh: true)
        case .leaveOption(let row):
            guard hovered?.id == row.id, hoveredOption != nil else { return nil }
            hoveredOption = nil
            return show(target(), fresh: true)
        case .rowChanged(let row):
            if hovered?.id == row.id { hovered = row }
            if selected?.id == row.id { selected = row }
            return show(target(), fresh: false)
        case .loopsFinished(let id):
            guard let current, current.spec.id == id, case .play = current.mode else { return nil }
            if active == nil { pagePlayed = true }
            interrupted = false
            return settle(arrows: false)
        case .environment(let next):
            let previous = environment
            environment = next
            if !next.visible {
                // 看不见：停在这一段的关键帧；还在演的记下，回来从头演。
                guard previous.visible, let current else { return nil }
                if case .play = current.mode { interrupted = true }
                return settle(arrows: next.reduceMotion)
            }
            let motionChanged = presentedReduced != next.reduceMotion
            if !previous.visible || motionChanged {
                let replay = interrupted || motionChanged
                interrupted = false
                return replay ? show(target(), fresh: true, replay: true) : nil
            }
            return nil
        }
    }

    /// 演哪一行：指着的优先（指到别的行就演那一行），指针离开后演选住的。
    private var active: RowState? { hovered ?? selected }

    private enum Target { case page, row(RowState) }
    private func target() -> Target { active.map { .row($0) } ?? .page }

    /// 上一次摆出去时是不是按减少动态效果摆的。
    private var presentedReduced = false

    /// 停在当前这一段的关键帧，不换内容。
    private mutating func settle(arrows: Bool) -> ExplainerPresentation? {
        guard var held = current else { return nil }
        held.mode = .hold(arrows: arrows)
        held.transition = .inPlace
        held.announces = false
        current = held
        return held
    }

    private func spec(for row: RowState) -> ExplainerSpec {
        if row.isOn == false, let off = row.row.offScene { return off }
        switch row.row.kind {
        case .loop(let spec), .still(let spec): return spec
        case .pageDefault: return page.pageDefault
        case .options(let specs):
            guard !specs.isEmpty else { return page.pageDefault }
            let wanted = (row.id == hovered?.id ? hoveredOption : nil) ?? row.selectedOption ?? 0
            return specs[min(max(wanted, 0), specs.count - 1)]
        }
    }

    /// fresh：换了目标（可能要从头演）；否则只改降灰。replay：就算是同一段也从头摆。
    private mutating func show(_ target: Target, fresh: Bool, replay: Bool = false) -> ExplainerPresentation? {
        let reduced = environment.reduceMotion
        var next: ExplainerPresentation
        switch target {
        case .page:
            let spec = page.pageDefault
            let mode: ExplainerPresentation.Mode
            if reduced || spec.isStill { mode = .hold(arrows: reduced) }
            else if pagePlayed || environment.lowPower { mode = .hold(arrows: false) }
            else { mode = .play(loops: ExplainerTiming.pageLoops) }
            next = ExplainerPresentation(spec: spec, mode: mode, dimmed: false, transition: .crossfade, announces: true)
        case .row(let row):
            // 指过行之后，页默认算演过了：移开只回到它的关键帧，不重演。
            pagePlayed = true
            let spec = spec(for: row)
            let isPageDefault = row.row.kind == .pageDefault
            let mode: ExplainerPresentation.Mode
            if reduced || spec.isStill { mode = .hold(arrows: reduced) }
            else if isPageDefault { mode = .hold(arrows: false) }
            else { mode = .play(loops: environment.lowPower ? ExplainerTiming.lowPowerRowLoops : ExplainerTiming.rowLoopCap) }
            // 开关关着：照样演，降灰；换成了关着的那一段就不降灰。页默认的行不降灰。
            let dimmed = !isPageDefault && row.isOn == false && row.row.offScene == nil
            next = ExplainerPresentation(spec: spec, mode: mode, dimmed: dimmed, transition: .crossfade, announces: true)
        }
        if reduced { next.transition = .instant }
        // 看不见时不演：先停在关键帧，记下来，看得见了再从头演。
        if !environment.visible, case .play = next.mode {
            next.mode = .hold(arrows: reduced)
            interrupted = true
        }
        guard let current else {
            next.transition = .instant
            return commit(next)
        }
        if current.spec.id == next.spec.id, !replay {
            if !fresh || current.mode == next.mode {
                // 同一段：开关拨了、或又指回正在演的那段——不重演，只改降灰。
                guard current.dimmed != next.dimmed else { return nil }
                var updated = current
                updated.dimmed = next.dimmed
                updated.transition = .inPlace
                updated.announces = false
                return commit(updated)
            }
            next.announces = false
        }
        return commit(next)
    }

    private mutating func commit(_ next: ExplainerPresentation) -> ExplainerPresentation {
        current = next
        presentedReduced = environment.reduceMotion
        return next
    }
}

// MARK: - 截图用的定帧

/// `--settings-shots` 截图时把讲解带定在某一帧，画面每次都一样。
/// `--explainer-frame key`（默认）摆关键帧；`--explainer-frame <n>` 摆第 n 帧演完的样子；`initial` 摆初始。
enum ExplainerFreeze: Equatable, Sendable {
    case keyFrame
    case initial
    case frame(Int)

    static func parse(_ arguments: [String]) -> ExplainerFreeze? {
        if let index = arguments.firstIndex(of: "--explainer-frame") {
            let value = arguments.count > index + 1 ? arguments[index + 1] : "key"
            if value == "initial" { return .initial }
            if let n = Int(value), n >= 0 { return .frame(n) }
            return .keyFrame
        }
        return arguments.contains("--settings-shots") ? .keyFrame : nil
    }

    /// 定在哪一帧（nil = 初始）。超出帧数时取最后一帧。
    func frameIndex(in spec: ExplainerSpec) -> Int? {
        switch self {
        case .keyFrame: return spec.keyFrameIndex
        case .initial: return nil
        case .frame(let n): return spec.frames.isEmpty ? nil : min(n, spec.frames.count - 1)
        }
    }
}

// MARK: - 箭头路径

/// 稿里箭头的 SVG 写法：只有 M（绝对移到）、L（绝对连线）、l（相对连线）。
enum ExplainerPath {
    enum Segment: Equatable { case move(CGPoint), line(CGPoint) }

    static func parse(_ text: String) -> [Segment] {
        var segments: [Segment] = []
        var command: Character = "M"
        var numbers: [Double] = []
        var cursor = CGPoint.zero
        func flush() {
            var i = 0
            while i + 1 < numbers.count {
                let a = numbers[i], b = numbers[i + 1]
                switch command {
                case "M": cursor = CGPoint(x: a, y: b); segments.append(.move(cursor)); command = "L"
                case "L": cursor = CGPoint(x: a, y: b); segments.append(.line(cursor))
                case "m": cursor = CGPoint(x: cursor.x + a, y: cursor.y + b); segments.append(.move(cursor)); command = "l"
                case "l": cursor = CGPoint(x: cursor.x + a, y: cursor.y + b); segments.append(.line(cursor))
                default: break
                }
                i += 2
            }
            numbers.removeAll()
        }
        var token = ""
        func endToken() {
            if let value = Double(token) { numbers.append(value) }
            token = ""
        }
        for ch in text {
            if "MLml".contains(ch) {
                endToken(); flush(); command = ch
            } else if ch == " " || ch == "," {
                endToken()
            } else if ch == "-", !token.isEmpty {
                endToken(); token = "-"
            } else {
                token.append(ch)
            }
        }
        endToken(); flush()
        return segments
    }
}
