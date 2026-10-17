// 一串滚动事件是什么来的：触控板（或 Magic Mouse）的手势、普通鼠标滚轮的一格一格、还是“平滑滚轮”。
//
// 平滑滚轮：罗技 Options+ 之类的驱动把滚轮的一格摊成一小串连续的像素增量发出来——没有相位（phase 0）、
// 也没有惯性，或者只发一串惯性（只有 momentum、前面没有手指那一段）；拇指轮／横向滚轮只带第二轴。
// 以前标题栏滚轮手势、启动台和文件夹翻页只认“不连续、没相位”的一格一格，这些事件全被当成触控板的残渣丢掉了。
//
// 这里把平滑滚轮折回“格”：一下拨动（一小串、中间停顿不到 flickGap）算一格；连着拨的几下靠“减速后又加速”分开；
// 一直匀速滚的长串每走 stepPixels 再算一格；两格之间至少隔 minStepInterval。方向取这一下的主轴和正负号。
// 触控板的事件（有相位、以及紧跟其后的惯性）原样交还给调用方，判定一个字节都不碰。
// 纯逻辑，不碰事件源、不碰窗口；单测见 tests/ScrollShapeTests.swift。

import Foundation

/// 惯性阶段，按 CGEvent 的 kCGScrollWheelEventMomentumPhase（0 无、1 开始、2 继续、3 结束）。
enum ScrollMomentum: Sendable, Equatable {
    case none, began, changed, ended

    init(cgMomentumPhase raw: Int64) {
        switch raw {
        case 0: self = .none
        case 1: self = .began
        case 3: self = .ended
        default: self = .changed
        }
    }
}

/// 分类要看的几项。dx、dy 是 scrollingDeltaX/Y（连续的按点，按格的按行）。
struct ScrollShapeEvent: Sendable, Equatable {
    /// kCGScrollWheelEventIsContinuous（NSEvent.hasPreciseScrollingDeltas）。
    var precise: Bool
    /// 有没有滚动相位（began/changed/ended/cancelled/mayBegin 任一个）。
    var phased: Bool
    var momentum: ScrollMomentum
    var dx: Double
    var dy: Double
    /// 秒，单调递增（NSEvent.timestamp 或 CACurrentMediaTime）。
    var time: TimeInterval

    init(precise: Bool, phased: Bool, momentum: ScrollMomentum = .none, dx: Double = 0, dy: Double = 0,
         time: TimeInterval) {
        self.precise = precise
        self.phased = phased
        self.momentum = momentum
        self.dx = dx
        self.dy = dy
        self.time = time
    }
}

/// 平滑滚轮折算出来的格数（带正负号，和 scrollingDeltaX/Y 同向）。一个事件最多一格，只在一条轴上。
struct ScrollWheelSteps: Sendable, Equatable {
    var x: Int = 0
    var y: Int = 0

    static let none = ScrollWheelSteps()
    var isEmpty: Bool { x == 0 && y == 0 }
    var count: Int { max(abs(x), abs(y)) }
}

enum ScrollShape: Sendable, Equatable {
    /// 有相位：触控板两指或 Magic Mouse。交给原来的处理。
    case trackpad
    /// 普通鼠标滚轮的一格（不连续、没相位、没惯性）。交给原来的处理。
    case discreteWheel
    /// 平滑滚轮；steps 为空表示这个事件还没走满一格（一串还在继续）。
    case smoothWheel(ScrollWheelSteps)
    /// 触控板松手后的惯性：手势在松手那一刻已有结论。
    case ignore
}

/// 平滑滚轮的事件折成格。
struct SmoothWheelStepper: Sendable, Equatable {
    /// 停顿超过这么久，下一个事件算新的一下拨动。
    static let flickGap: TimeInterval = 0.1
    /// 一直匀速滚的长串：每再走这么多点算一格（Options+ 一格摊开大约 40–60 点，所以一下拨动只算一格）。
    static let stepPixels: Double = 100
    /// 两格之间至少隔这么久（惯性尾巴里的抖动不会多算）。
    static let minStepInterval: TimeInterval = 0.05
    /// 减速到峰值的一半以下以后又加速到上一个的两倍、并且回到峰值的一半以上：这是连着拨的下一格
    /// （尾巴里的小抖动回不到峰值的一半，不算）。
    static let restartRatio: Double = 2

    private var lastAt: TimeInterval?
    private var lastStepAt: TimeInterval = -.infinity
    /// 这一下的主轴（true 为横向）和方向。
    private var horizontal: Bool?
    private var sign: Int = 0
    private var peak: Double = 0
    private var previous: Double = 0
    /// 上一格之后在主轴上又走了多少点。
    private var travel: Double = 0

    init() {}

    mutating func reset() { self = SmoothWheelStepper() }

    mutating func feed(dx: Double, dy: Double, at time: TimeInterval) -> ScrollWheelSteps {
        defer { lastAt = time }
        let isHorizontal = abs(dx) > abs(dy)
        let value = isHorizontal ? dx : dy
        let magnitude = abs(value)
        guard magnitude > 0 else { return .none }
        let direction = value > 0 ? 1 : -1
        let gap = lastAt.map { time - $0 } ?? .infinity
        let newFlick = horizontal == nil || gap > Self.flickGap || isHorizontal != horizontal || direction != sign
            || (magnitude >= Self.restartRatio * previous && previous <= peak / 2 && magnitude >= peak / 2)
        if newFlick {
            horizontal = isHorizontal
            sign = direction
            peak = magnitude
            previous = magnitude
            travel = 0
            return step(at: time)
        }
        peak = max(peak, magnitude)
        previous = magnitude
        travel += magnitude
        guard travel >= Self.stepPixels else { return .none }
        let stepped = step(at: time)
        if !stepped.isEmpty { travel -= Self.stepPixels }
        return stepped
    }

    private mutating func step(at time: TimeInterval) -> ScrollWheelSteps {
        guard time - lastStepAt >= Self.minStepInterval, let horizontal else { return .none }
        lastStepAt = time
        return horizontal ? ScrollWheelSteps(x: sign) : ScrollWheelSteps(y: sign)
    }
}

/// 一路滚动事件的分类器。每个要分清来源的地方各持一份，事件按到达顺序全喂进来。
struct ScrollShapeClassifier: Sendable, Equatable {
    /// 触控板相位（或它的惯性）之后这么久以内来的惯性仍算触控板的；再晚来的只有惯性的一串算平滑滚轮。
    static let momentumGap: TimeInterval = 0.3

    private var trackpadAt: TimeInterval?
    private(set) var stepper = SmoothWheelStepper()

    init() {}

    mutating func classify(_ e: ScrollShapeEvent) -> ScrollShape {
        if e.phased {
            trackpadAt = e.time
            stepper.reset()
            return .trackpad
        }
        if e.momentum != .none {
            if let at = trackpadAt, e.time - at <= Self.momentumGap {
                trackpadAt = e.momentum == .ended ? nil : e.time
                return .ignore
            }
            trackpadAt = nil
            return .smoothWheel(stepper.feed(dx: e.dx, dy: e.dy, at: e.time))
        }
        trackpadAt = nil
        guard e.precise else {
            stepper.reset()
            return .discreteWheel
        }
        return .smoothWheel(stepper.feed(dx: e.dx, dy: e.dy, at: e.time))
    }
}

#if canImport(AppKit)
import AppKit

extension ScrollShapeEvent {
    /// 从 NSEvent 取（主线程上各处 scrollWheel 用）。time 不给就用事件自己的时间戳。
    init(_ event: NSEvent, time: TimeInterval? = nil) {
        let momentum: ScrollMomentum
        if event.momentumPhase.contains(.began) { momentum = .began }
        else if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { momentum = .ended }
        else if event.momentumPhase != [] { momentum = .changed }
        else { momentum = .none }
        self.init(precise: event.hasPreciseScrollingDeltas, phased: event.phase != [], momentum: momentum,
                  dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY), time: time ?? event.timestamp)
    }
}
#endif
