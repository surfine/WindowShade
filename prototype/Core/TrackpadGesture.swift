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
    /// 左右滑走满后再往上或往下拐：占那一侧的上角或下角。
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    /// 朝同一边连着推：½ → ⅔ → ⅓（和 Rectangle 连按的顺序一样），再推就移到那边的屏幕。
    case leftTwoThirds
    case leftThird
    case rightTwoThirds
    case rightThird
    /// 已经是左边 ⅓ 还往左推：移到左边那块屏幕，贴着交界那一半（右半屏）。右边同理。
    case toLeftDisplay
    case toRightDisplay

    /// 左右方向走满之后拐向 vertical（上或下）得到的角。
    static func corner(_ horizontal: GestureDirection, turning vertical: GestureDirection) -> GestureAction? {
        switch (horizontal, vertical) {
        case (.left, .up): return .topLeft
        case (.left, .down): return .bottomLeft
        case (.right, .up): return .topRight
        case (.right, .down): return .bottomRight
        default: return nil
        }
    }
}

/// 键盘也能拐弯：按 ⌃⌘← 或 ⌃⌘→ 之后很快再按 ⌃⌘↑ 或 ⌃⌘↓，占那一侧的上角或下角，
/// 和手势“左右走满再往上下拐”一样。隔久了就是普通的变小、变大一级。
enum KeyTurn {
    static let window: TimeInterval = 0.8

    static func corner(after horizontal: GestureDirection?, elapsed: TimeInterval,
                       press: GestureDirection) -> GestureAction? {
        guard let horizontal, elapsed >= 0, elapsed <= window, press == .up || press == .down else { return nil }
        return GestureAction.corner(horizontal, turning: press)
    }
}

/// 窗口现在贴着屏幕哪一边、占多宽（用来决定“再往那边推”推到哪一格）。
enum GestureSide: Equatable, CaseIterable {
    case leftHalf, leftTwoThirds, leftThird, rightHalf, rightTwoThirds, rightThird

    /// 这一格对应的动作（和它同名）。
    var action: GestureAction {
        switch self {
        case .leftHalf: return .leftHalf
        case .leftTwoThirds: return .leftTwoThirds
        case .leftThird: return .leftThird
        case .rightHalf: return .rightHalf
        case .rightTwoThirds: return .rightTwoThirds
        case .rightThird: return .rightThird
        }
    }
}

/// 左右也是一架梯子：朝一边连着推，½ → ⅔ → ⅓，再推移到那边的屏幕；那边没有屏幕就回到 ½。
/// 手势和键盘走同一个规则。
enum HorizontalLadder {
    static func next(from side: GestureSide?, toward direction: GestureDirection, neighbor: Bool) -> GestureAction? {
        switch direction {
        case .left:
            switch side {
            case .leftHalf?: return .leftTwoThirds
            case .leftTwoThirds?: return .leftThird
            case .leftThird?: return neighbor ? .toLeftDisplay : .leftHalf
            default: return .leftHalf
            }
        case .right:
            switch side {
            case .rightHalf?: return .rightTwoThirds
            case .rightTwoThirds?: return .rightThird
            case .rightThird?: return neighbor ? .toRightDisplay : .rightHalf
            default: return .rightHalf
            }
        default:
            return nil
        }
    }
}

/// 甩一下标题栏（iPadOS 26 的甩窗口，给鼠标用户）：拖着标题栏快速甩出去松手，按松手那一刻的
/// 速度方向走和手势同一架梯子——往上变小一级、往下铺满、左右走左右梯子、往四个角占那一角。
/// 方向不照搬 iPad 的“往上全屏”：WindowShade 里往上一直是收起，同一个标题栏不能有两套相反的规则。
/// 速度不够就是普通的拖动。
enum FlickClassifier {
    /// 松手那一刻的速度至少这么快（点/秒）：平常拖窗口都会减速再放下，远低于这个数。
    static let minimumSpeed: CGFloat = 1800

    /// 拖的是标题栏：窗口跟着指针走了至少一半路，方向也一致。甩得快时窗口会落后指针一两帧，
    /// 所以按比例看，不按固定像素差；拖文字、拖文件、拖出标签页时原窗口基本不动。
    static func windowFollowed(moved: CGVector, pointer: CGVector) -> Bool {
        let pointerLength = hypot(pointer.dx, pointer.dy)
        let movedLength = hypot(moved.dx, moved.dy)
        guard pointerLength >= 30, movedLength >= pointerLength * 0.5, movedLength <= pointerLength * 1.5 + 24 else { return false }
        return (moved.dx * pointer.dx + moved.dy * pointer.dy) / (movedLength * pointerLength) >= 0.9
    }

    /// 八个方向之一：直的给梯子，斜的给那个角。velocity：点/秒，x 向右、y 向上。
    static func direction(velocity: CGVector) -> (primary: GestureDirection, turn: GestureDirection?)? {
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed >= minimumSpeed else { return nil }
        let angle = atan2(velocity.dy, velocity.dx) * 180 / .pi // 0 = 右，90 = 上
        switch angle {
        case -22.5..<22.5: return (.right, nil)
        case 22.5..<67.5: return (.right, .up)
        case 67.5..<112.5: return (.up, nil)
        case 112.5..<157.5: return (.left, .up)
        case -67.5 ..< -22.5: return (.right, .down)
        case -112.5 ..< -67.5: return (.down, nil)
        case -157.5 ..< -112.5: return (.left, .down)
        default: return (.left, nil)
        }
    }

    /// 在这张地图上甩向 velocity 该做什么。
    static func action(velocity: CGVector, map: GestureMap) -> GestureAction? {
        guard let (primary, turn) = direction(velocity: velocity) else { return nil }
        if let turn { return map.corners ? GestureAction.corner(primary, turning: turn) : nil }
        return map.action(for: primary)
    }
}

/// 左右两边有没有别的屏幕：纯几何，按屏幕外框（同一坐标系）判断。
enum DisplayNeighbor {
    /// 在 `index` 那块屏幕的 `direction` 一侧、上下有重叠、离得最近的那块；没有返回 nil。
    static func index(in frames: [CGRect], of index: Int, toward direction: GestureDirection) -> Int? {
        guard frames.indices.contains(index) else { return nil }
        let me = frames[index]
        var best: (Int, CGFloat)?
        for (i, other) in frames.enumerated() where i != index {
            let overlap = min(me.maxY, other.maxY) - max(me.minY, other.minY)
            guard overlap > 0 else { continue }
            let gap: CGFloat
            switch direction {
            case .left: guard other.maxX <= me.minX + 1 else { continue }; gap = me.minX - other.maxX
            case .right: guard other.minX >= me.maxX - 1 else { continue }; gap = other.minX - me.maxX
            default: return nil
            }
            if best == nil || gap < best!.1 { best = (i, gap) }
        }
        return best?.0
    }
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
    /// 左右走满之后可以拐弯占角（标题栏上开；卷帘条上没有左右）。
    var corners = false
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
    /// - side：窗口已经贴在哪一边、占多宽。再往同一边推，沿左右梯子走一格（见 HorizontalLadder）。
    /// - neighbors：左右哪边有别的屏幕。
    static func titleBar(canUndoPlacement: Bool, isFilled: Bool = false,
                         appOwnsHorizontal: Bool = false, side: GestureSide? = nil,
                         neighbors: Set<GestureDirection> = []) -> GestureMap {
        let unavailable: Set<GestureAction> = canUndoPlacement ? [] : [.undoPlacement]
        let left = HorizontalLadder.next(from: side, toward: .left, neighbor: neighbors.contains(.left))
        let right = HorizontalLadder.next(from: side, toward: .right, neighbor: neighbors.contains(.right))
        return GestureMap(up: isFilled && canUndoPlacement ? .undoPlacement : .shade,
                          down: isFilled ? nil : .fill,
                          left: appOwnsHorizontal ? nil : left,
                          right: appOwnsHorizontal ? nil : right,
                          spread: isFilled ? nil : .fill,
                          pinch: .undoPlacement,
                          corners: !appOwnsHorizontal,
                          unavailable: unavailable)
    }

    /// 卷帘条：往下拉展开。
    static let strip = GestureMap(down: .expand)

    /// 键盘上按一下方向键：和手势走同一架梯子，只是一下到位。做不了的（比如没有可撤销的
    /// 排布）照样交给浮窗说明、不做事；这个方向上没有动作（卷帘条上往上、铺满后往下）返回 nil。
    func keyFrame(_ direction: GestureDirection) -> GestureFrame? {
        guard let action = action(for: direction) else { return nil }
        let available = !unavailable.contains(action)
        return GestureFrame(action: action, progress: available ? 1 : 0, available: available)
    }

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
    /// 左右走满之后，还要朝上或朝下再走这么远才算拐弯占角：比走满略短，但必须是有意的一段。
    var turnDistance: CGFloat = 44
    /// 拐弯那一段里，上下至少是左右的这么多倍。
    var turnDominance: CGFloat = 1.2
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
    /// 左右已经走满过一次：方向锁在左右，之后朝上下走是在“拐弯”，不再改判成收起、铺满。
    private var turnLocked = false
    /// 走满那一刻手指在哪：拐弯从这里重新计量。
    private var armedAt = CGVector.zero
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
            turnLocked = false
            return .idle
        }
        if turnLocked, let horizontal = direction {
            return turnFrame(horizontal)
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
        if map.corners, direction == .left || direction == .right, along >= tuning.armDistance {
            turnLocked = true
            armedAt = translation
            return turnFrame(direction)
        }
        return frame(for: action, progress: along / tuning.armDistance)
    }

    /// 左右走满之后：朝上或朝下走够 turnDistance 就换成那个角；拐回来又是半屏（或换屏）。
    /// 进度仍按左右走了多远算：往回拉照样能取消。
    private func turnFrame(_ horizontal: GestureDirection) -> GestureFrame {
        guard map.corners, let action = map.action(for: horizontal) else {
            turnLocked = false
            return .idle
        }
        let along = max(0, component(translation, horizontal))
        // 只算走满之后的那一段：要以上下为主，一路斜着划下去不算拐弯（手指划长了常带弧线）。
        let after = CGVector(dx: translation.dx - armedAt.dx, dy: translation.dy - armedAt.dy)
        let vertical: GestureDirection = after.dy >= 0 ? .up : .down
        if abs(after.dy) >= tuning.turnDistance, abs(after.dy) >= abs(after.dx) * tuning.turnDominance,
           let corner = GestureAction.corner(horizontal, turning: vertical) {
            return frame(for: corner, progress: along / tuning.armDistance)
        }
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
        turnLocked = false
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
