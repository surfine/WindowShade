// 触控板手势：两指在标题栏或卷帘条上滑动、张合时，判断要做哪件事、已经做到几成。
//
// 纯逻辑，不碰事件与窗口。控制器把每一帧的手指位移喂进来，拿回提示浮窗该显示的
// 动作与进度，松手时拿回要执行的动作（或 nil = 取消）。
// - 方向跟着内容走（自然滚动下就是手指的方向），随时可以改主意：往回拉到起点附近就是取消，
//   转向另一个方向就换成那个方向的动作；
// - 但一开始认出的方向如果不归我们（比如在 Safari 标签上左右滑是切换标签），这一整下都
//   不接管，免得斜着切标签时被认成上滑收起；
// - 走满 armDistance 算“松手即执行”，此刻给一次触感；
// - 松手时按速度投射落点（Apple 的指数衰减形式），快速一甩也算数，往回甩则取消。

import CoreGraphics
import Foundation

enum GestureZone: Equatable {
    case titleBar
    case strip
}

enum GestureAction: String, Equatable, CaseIterable {
    /// 上滑：收起窗口。
    case shade
    /// 卷帘条上下滑：展开窗口。
    case expand
    case leftHalf
    case rightHalf
    /// 两指张开：铺满屏幕。
    case fill
    /// 两指捏合：撤销上次排布。
    case undoPlacement
}

enum GestureDirection: Equatable, CaseIterable {
    case up, down, left, right

    /// 手指坐标系：x 向右为正，y 向上为正。
    var unit: CGVector {
        switch self {
        case .up: return CGVector(dx: 0, dy: 1)
        case .down: return CGVector(dx: 0, dy: -1)
        case .left: return CGVector(dx: -1, dy: 0)
        case .right: return CGVector(dx: 1, dy: 0)
        }
    }
}

/// 每个区域里，哪个方向对应哪件事。nil = 这个方向不做事，浮窗也不出现。
struct GestureMap: Equatable {
    var up: GestureAction?
    var down: GestureAction?
    var left: GestureAction?
    var right: GestureAction?
    var spread: GestureAction?
    var pinch: GestureAction?
    /// 这些动作此刻做不了：浮窗照样出现、说明为什么，但不会走满，松手也不执行。
    /// 比悄无声息更好——用户知道手势被认出来了。
    var unavailable: Set<GestureAction> = []

    func action(for direction: GestureDirection) -> GestureAction? {
        switch direction {
        case .up: return up
        case .down: return down
        case .left: return left
        case .right: return right
        }
    }

    /// 标题栏。上下是一架尺寸梯子，和卷帘同向：往下拉一格变大，往上推一格变小——
    /// 卷帘条 ⇄ 原来大小 ⇄ 铺满屏幕。所以普通窗口下拉铺满、上推收起；铺满的窗口上推
    /// 先撤销那次铺满，再上推才收起。左右占半屏，张开铺满，捏合撤销上次排布。
    /// - isFilled：窗口现在就占满了屏幕可用区域（下拉、张开都没有意义）。
    /// - appOwnsHorizontal：指针下的控件自己用左右滑（标签页、地址栏），左右让给 App。
    /// - 没有可撤销的排布时，捏合只说明这一点。
    static func titleBar(canUndoPlacement: Bool, isFilled: Bool = false,
                         appOwnsHorizontal: Bool = false) -> GestureMap {
        GestureMap(up: isFilled && canUndoPlacement ? .undoPlacement : .shade,
                   down: isFilled ? nil : .fill,
                   left: appOwnsHorizontal ? nil : .leftHalf,
                   right: appOwnsHorizontal ? nil : .rightHalf,
                   spread: isFilled ? nil : .fill,
                   pinch: .undoPlacement,
                   unavailable: canUndoPlacement ? [] : [.undoPlacement])
    }

    /// 卷帘条：往下拉展开。
    static let strip = GestureMap(down: .expand)

    /// 轻点两下（系统叫“智能缩放”：触控板两指、Magic Mouse 单指）：一下到位，没有进度。
    /// 标题栏上在铺满与还原之间切换——和照片、网页里智能缩放“放大到合适、再点回去”同义；
    /// 已经铺满又没有可撤销的排布时，说明这一点，不做事。卷帘条上是展开。
    static func doubleTap(zone: GestureZone, isFilled: Bool, canUndoPlacement: Bool) -> GestureFrame {
        switch zone {
        case .strip:
            return GestureFrame(action: .expand, progress: 1)
        case .titleBar:
            guard isFilled else { return GestureFrame(action: .fill, progress: 1) }
            return GestureFrame(action: .undoPlacement, progress: canUndoPlacement ? 1 : 0,
                                available: canUndoPlacement)
        }
    }
}

struct GestureTuning: Equatable {
    /// 手指走这么远才开始认方向（点，已含系统加速）。
    var hysteresis: CGFloat = 10
    /// 沿方向走满这段就是“松手即执行”。
    var armDistance: CGFloat = 56
    /// 快速一甩至少要走这么远，防止轻触误发。
    var minimumCommitDistance: CGFloat = 18
    /// 改方向要比原方向多走这么多倍，避免在 45° 附近来回跳。
    var switchRatio: CGFloat = 1.25
    /// 张合：累计缩放走满这么多是“松手即执行”。
    var armMagnification: CGFloat = 0.22
    var magnificationHysteresis: CGFloat = 0.03
    var minimumCommitMagnification: CGFloat = 0.08
    /// 投射落点用的减速率（0.99 偏利落）。
    var decelerationRate: CGFloat = 0.99
    /// 只用松手前这段时间里的采样估速度：更早的停顿不算甩，松手前一刻往回拉要算作往回。
    var velocityWindow: TimeInterval = 0.05
}

/// 浮窗每一帧要显示的东西。
struct GestureFrame: Equatable {
    var action: GestureAction?
    /// 0 起步，1 = 松手即执行；超过 1 表示已经拉过头。
    var progress: CGFloat
    /// false：认出了手势，但这件事此刻做不了（浮窗说明原因）。
    var available = true
    var armed: Bool { action != nil && available && progress >= 1 }

    static let idle = GestureFrame(action: nil, progress: 0)
}

enum GestureFeedback: Equatable {
    /// 刚走满：此刻松手就会执行。
    case armed
    /// 又退回去了。
    case disarmed
}

final class GestureRecognizer {
    private enum Mode { case undecided, swipe, pinch }

    private(set) var map: GestureMap
    let tuning: GestureTuning
    private(set) var frame = GestureFrame.idle
    private var mode = Mode.undecided
    /// 已经认过一次方向；第一次认出的方向不归我们时，整下手势作废（foreign）。
    private var decided = false
    /// 保留首次越过方向门槛的意图，迟到的控件确认不能把切标签改判成收起。
    private var initialDirection: GestureDirection?
    private var foreign = false
    private var translation = CGVector.zero
    private var magnification: CGFloat = 0
    /// 当前认定的滑动方向（张合时为 nil）。
    private(set) var direction: GestureDirection?
    /// (时间, 手指位移或累计缩放)：只保留最近一小段，用来估松手速度。
    private var swipeSamples: [(TimeInterval, CGVector)] = []
    private var pinchSamples: [(TimeInterval, CGFloat)] = []

    init(map: GestureMap, tuning: GestureTuning = GestureTuning()) {
        self.map = map
        self.tuning = tuning
    }

    /// 两指滑动了一帧。delta 是手指位移（x 向右、y 向上为正）。
    @discardableResult
    func scroll(_ delta: CGVector, at time: TimeInterval) -> [GestureFeedback] {
        guard mode != .pinch else { return [] }
        mode = .swipe
        translation.dx += delta.dx
        translation.dy += delta.dy
        record(&swipeSamples, (time, translation), now: time)
        return update(to: swipeFrame())
    }

    /// 张合了一帧。delta 是这一帧的缩放增量（张开为正）。
    @discardableResult
    func magnify(_ delta: CGFloat, at time: TimeInterval) -> [GestureFeedback] {
        // 系统在一次手势里只会认一种：一旦开始张合，前面那点滑动作废。
        if mode != .pinch {
            mode = .pinch
            translation = .zero
            direction = nil
            swipeSamples.removeAll()
        }
        magnification += delta
        record(&pinchSamples, (time, magnification), now: time)
        return update(to: pinchFrame())
    }

    /// 手指离开。返回要执行的动作；nil 表示取消。
    func end(at time: TimeInterval) -> GestureAction? {
        defer { reset() }
        guard let action = frame.action, frame.available else { return nil }
        switch mode {
        case .undecided:
            return nil
        case .swipe:
            guard let direction else { return nil }
            let along = component(translation, direction)
            guard along >= tuning.minimumCommitDistance else { return nil }
            let velocity = swipeVelocity(at: time)
            let projected = along + project(component(velocity, direction))
            return projected >= tuning.armDistance ? action : nil
        case .pinch:
            let sign: CGFloat = magnification >= 0 ? 1 : -1
            let amount = abs(magnification)
            guard amount >= tuning.minimumCommitMagnification else { return nil }
            let projected = amount + project(pinchVelocity(at: time) * sign)
            return projected >= tuning.armMagnification ? action : nil
        }
    }

    func cancel() { reset() }

    /// 手势开始后才确认了指针下是什么（辅助功能查询是异步的）：换成确认后的地图，
    /// 保留最初的方向意图，更新当前动作；不能因确认较晚而接管原本属于 App 的手势。
    @discardableResult
    func updateMap(_ newMap: GestureMap) -> [GestureFeedback] {
        map = newMap
        switch mode {
        case .undecided:
            return []
        case .swipe:
            decided = initialDirection != nil
            foreign = initialDirection.map { newMap.action(for: $0) == nil } ?? false
            if foreign {
                direction = nil
                return update(to: .idle)
            }
            return update(to: swipeFrame())
        case .pinch:
            return update(to: pinchFrame())
        }
    }

    // MARK: - 内部

    private func swipeFrame() -> GestureFrame {
        guard !foreign else { return .idle }
        let length = hypot(translation.dx, translation.dy)
        guard length >= tuning.hysteresis else {
            direction = nil
            return .idle
        }
        let candidate = dominantDirection(translation)
        if let current = direction, candidate != current {
            let currentAlong = component(translation, current)
            if currentAlong > 0,
               component(translation, candidate) < currentAlong * tuning.switchRatio {
                // 还不够明确：保持原方向。
            } else {
                direction = candidate
            }
        } else {
            direction = candidate
        }
        if !decided, let direction {
            decided = true
            initialDirection = direction
            if map.action(for: direction) == nil {
                foreign = true
                return .idle
            }
        }
        guard let direction, let action = map.action(for: direction) else { return .idle }
        let along = max(0, component(translation, direction))
        return frame(for: action, progress: along / tuning.armDistance)
    }

    private func pinchFrame() -> GestureFrame {
        guard abs(magnification) >= tuning.magnificationHysteresis else { return .idle }
        let action = magnification > 0 ? map.spread : map.pinch
        guard let action else { return .idle }
        return frame(for: action, progress: abs(magnification) / tuning.armMagnification)
    }

    private func frame(for action: GestureAction, progress: CGFloat) -> GestureFrame {
        let available = !map.unavailable.contains(action)
        return GestureFrame(action: action, progress: available ? progress : 0, available: available)
    }

    private func update(to next: GestureFrame) -> [GestureFeedback] {
        let wasArmed = frame.armed
        let previousAction = frame.action
        frame = next
        var feedback: [GestureFeedback] = []
        if next.armed, !wasArmed || previousAction != next.action {
            feedback.append(.armed)
        } else if wasArmed, !next.armed {
            feedback.append(.disarmed)
        }
        return feedback
    }

    private func dominantDirection(_ v: CGVector) -> GestureDirection {
        if abs(v.dx) > abs(v.dy) { return v.dx > 0 ? .right : .left }
        return v.dy > 0 ? .up : .down
    }

    private func component(_ v: CGVector, _ direction: GestureDirection) -> CGFloat {
        v.dx * direction.unit.dx + v.dy * direction.unit.dy
    }

    /// Apple《Designing Fluid Interfaces》的落点投射：速度（每秒）→ 还会滑多远。
    private func project(_ velocityPerSecond: CGFloat) -> CGFloat {
        let rate = tuning.decelerationRate
        return velocityPerSecond / 1000 * rate / (1 - rate)
    }

    private func record<T>(_ samples: inout [(TimeInterval, T)], _ sample: (TimeInterval, T),
                           now: TimeInterval) {
        samples.append(sample)
        let horizon = now - tuning.velocityWindow * 2
        if let firstKept = samples.firstIndex(where: { $0.0 >= horizon }), firstKept > 0 {
            samples.removeFirst(firstKept)
        }
    }

    private func swipeVelocity(at time: TimeInterval) -> CGVector {
        let recent = swipeSamples.filter { $0.0 >= time - tuning.velocityWindow }
        guard let first = recent.first, let last = recent.last, last.0 - first.0 > 0.004 else {
            return .zero
        }
        let dt = CGFloat(last.0 - first.0)
        return CGVector(dx: (last.1.dx - first.1.dx) / dt, dy: (last.1.dy - first.1.dy) / dt)
    }

    private func pinchVelocity(at time: TimeInterval) -> CGFloat {
        let recent = pinchSamples.filter { $0.0 >= time - tuning.velocityWindow }
        guard let first = recent.first, let last = recent.last, last.0 - first.0 > 0.004 else {
            return 0
        }
        return (last.1 - first.1) / CGFloat(last.0 - first.0)
    }

    private func reset() {
        frame = .idle
        mode = .undecided
        translation = .zero
        magnification = 0
        direction = nil
        decided = false
        initialDirection = nil
        foreign = false
        swipeSamples.removeAll()
        pinchSamples.removeAll()
    }
}

/// 滚动事件里的增量 → 手势方向（x 向右、y 向上为正）。
/// 方向跟“内容”走：在标题栏上滚动，就像在滚动窗口本身——内容往上走，窗口卷起来；
/// 往下走，窗口放下来。触控板开着自然滚动（系统默认）时，内容方向就是手指方向；
/// 关了自然滚动的鼠标，滚轮往上推是内容往下走，也就是铺满——和 HyperDock 的“往上滚铺满”一致。
/// scrollingDeltaX > 0 = 内容向右，scrollingDeltaY > 0 = 内容向下。
enum GestureFingerDelta {
    static func fromScroll(deltaX: CGFloat, deltaY: CGFloat) -> CGVector {
        CGVector(dx: deltaX, dy: -deltaY)
    }
}

/// 指针下的控件自己用哪些方向。输入是从命中的元素一路往上到窗口的（角色, 子角色）。
/// 规则：控件自己用的方向归它，我们只接它不用的。
enum GestureOwnership {
    typealias Element = (role: String, subrole: String?)

    /// 本来就能滚动的内容：整下手势都归 App。
    static let scrollableRoles: Set<String> = [
        "AXScrollArea", "AXWebArea", "AXTextArea", "AXTable", "AXOutline", "AXList", "AXBrowser",
    ]
    /// 自己用左右滑的控件：标签页（Safari 实测是 AXRadioButton/AXTabButton，左右滑切换标签）、
    /// 标签组、文本框（Safari 的地址栏嵌在当前标签里）、滑块。
    static let horizontalRoles: Set<String> = [
        "AXTabGroup", "AXTextField", "AXComboBox", "AXSlider", "AXScrollBar",
    ]
    static let horizontalSubroles: Set<String> = ["AXTabButton", "AXSearchField"]

    static func appOwnsAll(_ chain: [Element]) -> Bool {
        chain.contains { scrollableRoles.contains($0.role) }
    }

    static func appOwnsHorizontal(_ chain: [Element]) -> Bool {
        chain.contains { horizontalRoles.contains($0.role) || $0.subrole.map(horizontalSubroles.contains) == true }
    }
}
