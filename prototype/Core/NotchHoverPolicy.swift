import CoreGraphics
import Foundation

/// 悬停不误触（《实时活动晋级》稿“二 · 悬停和点击不误触”，工作包 LA-4）。
///
/// 纯规则，不碰系统：面板（App/Notch.swift 的 NotchPanel）把已有的进出、移动、滚轮事件交进来，
/// 这里决定提示亮不亮、什么时候再看一眼、要不要展开那一排。不轮询：只在事件到来和面板自己的
/// 一次性计时器到点时算；计时器只在指针还在热区里、还没展开时存在。
///
/// - 热区就是面板此刻占的地方（刘海加上此刻长出的耳朵、最小形、下巴），由面板的跟踪区域保证；这里只管时间和位移。
/// - 停在热区里，连续 `dwell`（0.12 秒）移动不到 `stillRadius`（8 点），才展开那一排。慢慢滑过去也不算停。
/// - 进来那一下速度超过 `sweepSpeed`（600 点/秒）算横扫：这一趟不给提示；停下来以后照常算停留。
/// - 提示只往下长 `hintDrop`（3 点），不往两边长（`hintRect`）。
/// - 鼠标滚轮、惯性滚动：不算停留，也不重新计时；指针再动起来才重新算。
/// - 系统的 » 在：只认点击（悬停不展开、不提示）。全屏时菜单栏滑下来：也不展开。
///
/// 默认关（`defaultsKey`）：关着时面板走原来的“进来 0.12 秒就展开、提示两边各长 5 点”。
struct NotchHoverPolicy: Equatable {
    // MARK: 数字（照稿）

    /// 停多久才展开（和 `Motion.Hold.notchDwell` 同值）。
    static let dwell: TimeInterval = 0.12
    /// 这一段时间里移动不到这么多点，才算停。
    static let stillRadius: CGFloat = 8
    /// 进来那一下快过这个速度（点/秒）算横扫。
    static let sweepSpeed: CGFloat = 600
    /// 提示只往下长这么多点。
    static let hintDrop: CGFloat = 3
    /// 两个采样相隔不到这么久，速度算不准：等下一个采样再判断是不是横扫。
    static let minimumSpeedInterval: TimeInterval = 0.004
    /// 再看一眼的计时器容差：晚一点没关系，验收是 0.12–0.20 秒内展开。
    static let timerTolerance: TimeInterval = 0.02

    /// 设置里的键：默认关，关着是旧行为。
    static let defaultsKey = "Notch.hoverGuard"
    static let defaultEnabled = false

    // MARK: 输入与输出

    /// 这一刻的环境。
    struct Context: Equatable {
        /// 系统的 » 在（图标太多被藏起来了）：你多半正要去点刚露出来的图标，只认点击。
        var clickOnly = false
        /// 这块屏在全屏桌面上（指针顶到上沿让菜单栏滑下来时，面板可能正露着）：不展开。
        var fullScreen = false

        init(clickOnly: Bool = false, fullScreen: Bool = false) {
            self.clickOnly = clickOnly
            self.fullScreen = fullScreen
        }

        /// 悬停在这一刻能不能展开、能不能提示。
        var hoverAllowed: Bool { !clickOnly && !fullScreen }
    }

    /// 每个事件之后面板该做的事。
    struct Step: Equatable {
        /// 提示该不该亮着（亮 = 岛往下长 3 点）。
        var hint: Bool
        /// 该在这个时刻（和事件同一个时钟）之前或那一刻再问一次 `fire`；nil = 不需要计时器，有就停掉。
        /// 已经有更早的计时器在等就不必重排：它到点时会拿到新的时刻。
        var deadline: TimeInterval?
        /// 现在展开那一排。
        var expand: Bool

        static let idle = Step(hint: false, deadline: nil, expand: false)
    }

    // MARK: 状态

    private struct Sample: Equatable {
        var point: CGPoint
        var time: TimeInterval
    }

    private enum Entry: Equatable {
        /// 还不知道进来有多快：等下一个移动采样。
        case pending
        /// 慢慢进来的：可以提示。
        case calm
        /// 横扫进来的：这一趟不提示。
        case sweep
    }

    private(set) var inside = false
    /// 展开过了：这一趟不再算（和旧行为一样，进来一次只展开一次）。
    private(set) var expanded = false
    private var entry: Entry = .pending
    private var enterSample: Sample?
    /// 这一段“停”从哪里、什么时候开始；nil = 被滚轮打断了，等指针再动。
    private var anchor: Sample?

    init() {}

    /// 现在的提示状态（探针、测试用）。
    var hinting: Bool { inside && !expanded && entry == .calm }

    // MARK: 事件

    /// 指针进了热区。`speed` 是调用方已经知道的进来速度（点/秒）；不知道就给 nil，等第一个移动采样再判断。
    mutating func enter(at point: CGPoint, time: TimeInterval, speed: CGFloat? = nil, context: Context) -> Step {
        inside = true
        expanded = false
        let sample = Sample(point: point, time: time)
        enterSample = sample
        anchor = sample
        if let speed { entry = speed > Self.sweepSpeed ? .sweep : .calm } else { entry = .pending }
        return step(context: context)
    }

    /// 指针在热区里动了。
    mutating func move(to point: CGPoint, time: TimeInterval, context: Context) -> Step {
        guard inside else { return .idle }
        if entry == .pending, let start = enterSample {
            let interval = time - start.time
            if interval >= Self.minimumSpeedInterval {
                let speed = Self.distance(point, start.point) / CGFloat(interval)
                entry = speed > Self.sweepSpeed ? .sweep : .calm
            }
        }
        guard !expanded else { return step(context: context) }
        if let current = anchor, Self.distance(point, current.point) < Self.stillRadius {
            // 还在这一段“停”里：手抖不算动，不重新计时。
        } else {
            anchor = Sample(point: point, time: time)
        }
        return step(context: context)
    }

    /// 鼠标滚轮、惯性滚动：不算停留，也不重新计时；等指针再动。
    mutating func scroll(time: TimeInterval, context: Context) -> Step {
        guard inside else { return .idle }
        if !expanded { anchor = nil }
        return step(context: context)
    }

    /// 面板的计时器到点了：停够了就展开；没停够就说下一次什么时候再问。
    mutating func fire(time: TimeInterval, context: Context) -> Step {
        guard inside, !expanded, context.hoverAllowed, let current = anchor else { return step(context: context) }
        // 计时器容差和浮点：差不到 1 毫秒算到点。
        guard time + 0.001 >= current.time + Self.dwell else { return step(context: context) }
        expanded = true
        var result = step(context: context)
        result.expand = true
        return result
    }

    /// 指针离开热区：一切归零，提示收掉、计时器停掉（收起那一排是面板原来的规矩）。
    mutating func exit() -> Step {
        self = NotchHoverPolicy()
        return .idle
    }

    // MARK: 画法

    /// 提示的样子：只往下长 3 点，宽度不变（两边是量过的，不能借着提示越界）。Cocoa 坐标：y 朝上，顶边不动。
    static func hintRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: rect.minY - hintDrop, width: rect.width, height: rect.height + hintDrop)
    }

    // MARK: 内部

    private func step(context: Context) -> Step {
        guard inside, !expanded, context.hoverAllowed else { return .idle }
        let deadline = anchor.map { $0.time + Self.dwell }
        return Step(hint: entry == .calm, deadline: deadline, expand: false)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
