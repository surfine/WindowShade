// 代理先动、真窗后到：标题栏两指左右滑的左右半屏与甩一下标题栏的排布全过程（整合计划第 13 步；Aaron 2026-10-31
// 定 A、B）。其余排布（四角、三分、铺满、键盘、菜单、刘海小岛）照旧。
// 手势中代理跟手（ProxyFollow）、目标处画半透明落点外框，真窗不动；松手代理带速度落定，那一刻后台给真窗写一次外框，
// 等 WindowServer 真到位再撤背景淡出代理（无空档无重影）。落定前可被两指接住改道（位置速度连续，ProxyMotion.retargeted），
// 真窗这期间仍停原处直到唯一那一次写。减少动态效果：不跟手不滑，原处淡出目标淡入（ProxyPresentation.dissolve）。
// 线程：本类只在主线程用；写外框与等到位在全局队列，只带值过去、结果跳回主线程。不放锁不放 Mutex——
// @MainActor 类里的 Mutex 被后台碰过一次就崩过（见 feedback-mutex-mainactor-trap）。

import Cocoa
import ApplicationServices

@MainActor
final class WindowProxyArranger {
    enum Phase: Equatable {
        /// 跟着手指：还没松手。
        case tracking
        /// 松手了，代理在落向目标（可接住、可改道）。
        case settling
        /// 代理到了，真窗口那一次写已经发出，等它到位。
        case writing
        /// 没执行（换了方向、取消）：代理退回真窗口原处后消失，不写。这时真窗口照常可以接新手势。
        case returning
    }

    final class Item {
        let id: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        /// 真窗口此刻的外框（AX 坐标）：写之前它一直在这里。
        let original: CGRect
        let stage: WindowProxyStage
        var phase: Phase = .tracking
        /// 跟手从哪里长出来：一般就是 original；接住时是代理被接住的地方。
        var base: CGRect
        var target: CGRect?
        /// 被接住之前要去的地方：接住后什么都没认出就松手，接着去那里。
        var pendingTarget: CGRect?
        /// 目标所在屏幕的可用区域（AX 坐标）：App 不肯变成目标大小时，按实际大小放进目标正中、不出这块区域。
        var area: CGRect = .zero
        var goalKey: String?
        var trail = ProxyTrail()
        var captureRequested = false
        var onLanded: ((CGRect) -> Void)?
        init(id: CGWindowID, pid: pid_t, element: AXUIElement, original: CGRect, stage: WindowProxyStage) {
            self.id = id
            self.pid = pid
            self.element = element
            self.original = original
            self.base = original
            self.stage = stage
        }
    }

    private var items: [CGWindowID: Item] = [:]
    private(set) var ledger = ProxyCommitLedger()
    var clock: () -> Double = { CACurrentMediaTime() }
    /// 探针可强制有无截图（模拟没有屏幕录制），不改系统权限。nil 时看系统。
    var snapshotsAllowedOverride: Bool?
    /// 跟手比例：和标题栏收起跟手同一个数（TrackpadGestureController.followRatio）。
    var followRatio: Double = TrackpadGestureController.followRatio

    private var snapshotsAllowed: Bool { snapshotsAllowedOverride ?? hasScreenRecordingPermission() }
    private var presentation: ProxyPresentation { .choose(reduceMotion: Motion.reduced) }

    // MARK: - 查询

    var isActive: Bool { !items.isEmpty }
    func owns(_ id: CGWindowID) -> Bool { items[id] != nil }
    func isTracking(_ id: CGWindowID) -> Bool { items[id]?.phase == .tracking }
    /// 松手后还没收场（在飞或在等真窗口到位）：别的手势先别碰这扇真窗口。
    func isBusy(_ id: CGWindowID) -> Bool {
        guard let phase = items[id]?.phase else { return false }
        return phase == .settling || phase == .writing
    }
    func phase(_ id: CGWindowID) -> Phase? { items[id]?.phase }
    /// 真窗口此刻（写之前）的外框。
    func original(_ id: CGWindowID) -> CGRect? { items[id]?.original }
    func presentedFrame(_ id: CGWindowID) -> CGRect? { items[id]?.stage.presentedFrame }
    func look(_ id: CGWindowID) -> ProxyLook? { items[id]?.stage.look }
    /// 这扇窗最近一次提交写了几次外框（应当是 1；落点就是原处时是 0）。
    func lastWriteCount(_ id: CGWindowID) -> Int? { ledger.lastAttempts(window: id) }

    // MARK: - 跟手（标题栏两指左右滑）

    /// 手势还在：代理按进度从 base 长向 target。第一次调用时建代理（current：真窗口此刻的外框）。
    /// goalKey：目标是哪一格（动作名）。同一格只算一次目标（要问一次辅助功能“能不能改大小”），之后每帧只插值。
    func track(id: CGWindowID, pid: pid_t, element: AXUIElement, goalKey: String, current: () -> CGRect?,
               target: (CGRect) -> (frame: CGRect, area: CGRect)?, progress: CGFloat) {
        let item: Item
        if let existing = items[id], existing.phase == .returning {
            // 上一下没执行、代理还在退回去：这一下重新开始。
            drop(id)
        }
        if let existing = items[id] {
            guard existing.phase == .tracking else { return }
            item = existing
        } else {
            guard let frame = current() else { return }
            item = makeItem(id: id, pid: pid, element: element, frame: frame, snapshot: nil)
            requestSnapshot(item)
        }
        if item.goalKey != goalKey || item.target == nil {
            guard let goal = target(item.base) else { return }
            item.goalKey = goalKey
            item.target = goal.frame
            item.area = goal.area
        }
        guard let goalFrame = item.target else { return }
        let goal = (frame: goalFrame, area: item.area)
        if presentation == .dissolve {
            // 减少动态效果：代理不跟着滑，只在目标处淡淡画出落点。
            item.stage.setLanding(goal.frame, opacity: ProxyFollow.landingOpacity(progress: progress))
            return
        }
        let f = ProxyFollow.fraction(progress: progress, followRatio: followRatio)
        let frame = ProxyFollow.frame(from: item.base, to: goal.frame, fraction: f)
        item.stage.follow(frame)
        item.trail.add(frame, at: clock())
        item.stage.setLanding(goal.frame, opacity: ProxyFollow.landingOpacity(progress: progress))
    }

    /// 方向变了、手势取消、松手但不执行：代理回到原处（被接住的回到它原来要去的地方），真窗口不写。
    func abandon(_ id: CGWindowID) {
        guard let item = items[id], item.phase == .tracking else { return }
        item.stage.setLanding(nil, opacity: 0)
        if let pending = item.pendingTarget {
            // 接住了又放开、没认出新方向：从这里接着去原来的终点。
            settle(item, to: pending, velocity: .zero)
            return
        }
        item.phase = .returning
        let back = item.original
        let finish: @MainActor () -> Void = { [weak self, weak item] in
            guard let self, let item, self.items[id] === item else { return }
            self.items.removeValue(forKey: id)
            item.stage.finish()
        }
        if presentation == .dissolve || item.stage.presentedFrame == back {
            finish()
            return
        }
        item.stage.play(ProxyMotion(from: item.stage.presentedFrame, to: back, velocity: item.trail.velocity(at: clock()),
                                    at: clock(), position: Self.settleSpring, size: Self.settleSpring, limitOvershoot: 0),
                        done: finish)
    }

    /// 松手执行：代理带着手指的速度落到目标，落定时真窗口写一次。没有在跟手的代理返回 false（调用方走老路）。
    func commit(_ id: CGWindowID, landed: @escaping (CGRect) -> Void) -> Bool {
        guard let item = items[id], item.phase == .tracking, let target = item.target else { return false }
        item.onLanded = landed
        item.stage.setLanding(target, opacity: 1)
        settle(item, to: target, velocity: item.trail.velocity(at: clock()))
        return true
    }

    /// 中途改道（例如被接住后的捏合撤销）：位置和速度从此刻接着走。
    func redirect(_ id: CGWindowID, to target: CGRect, landed: ((CGRect) -> Void)? = nil) -> Bool {
        guard let item = items[id] else { return false }
        if let landed { item.onLanded = landed }
        item.pendingTarget = nil
        item.stage.setLanding(target, opacity: 1)
        switch item.phase {
        case .tracking:
            settle(item, to: target, velocity: item.trail.velocity(at: clock()))
        case .settling:
            item.target = target
            if presentation == .dissolve {
                settle(item, to: target, velocity: .zero)
            } else if let motion = item.stage.motion {
                item.stage.play(motion.retargeted(to: target, at: clock())) { [weak self, weak item] in
                    guard let self, let item else { return }
                    self.write(item)
                }
            } else {
                settle(item, to: target, velocity: .zero)
            }
        case .writing, .returning:
            return false
        }
        return true
    }

    // MARK: - 甩一下

    /// 甩一下标题栏：真窗口停在松手处（from），代理带着甩出去的速度飞到 to，落定时写一次。
    /// pictures：拖动中后台截好的窗口和背景（没有屏幕录制时为空，代理就是描边）。velocity：AX 坐标，点/秒。
    func fly(id: CGWindowID, pid: pid_t, element: AXUIElement, from: CGRect, to: CGRect, velocity: CGVector,
             pictures: DragPictures?, landed: @escaping (CGRect) -> Void) {
        drop(id)
        let snapshot = snapshotsAllowed ? pictures?.window : nil
        let item = makeItem(id: id, pid: pid, element: element, frame: from, snapshot: snapshot)
        if let snapshot, let background = pictures?.background(covering: from) {
            item.stage.adopt(snapshot: snapshot, background: background, over: from)
        }
        item.onLanded = landed
        item.stage.setLanding(to, opacity: 1)
        settle(item, to: to, velocity: ProxyVelocity(dx: Double(velocity.dx), dy: Double(velocity.dy)))
    }

    // MARK: - 接住

    /// 两指手势落在一个还在飞的代理的标题栏一带：接住它，此后由这次手势带着走。
    /// 返回被接住的那扇窗（真窗口仍在原处，没写过）。减少动态效果时代理不飞，没有可接的。
    func catchProxy(at point: CGPoint, band: CGFloat = 80) -> (id: CGWindowID, pid: pid_t, element: AXUIElement)? {
        guard presentation == .slide else { return nil }
        for item in items.values where item.phase == .settling {
            let frame = item.stage.presentedFrame
            guard point.x >= frame.minX, point.x <= frame.maxX, point.y >= frame.minY, point.y <= frame.minY + band else { continue }
            let state = item.stage.stop()
            item.phase = .tracking
            item.pendingTarget = item.target
            item.base = state.frame
            item.trail.reset()
            item.trail.add(state.frame, at: clock())
            wlog(String(format: "gesture: proxy id=%d caught mid-flight at (%.0f,%.0f) v=(%.0f,%.0f)", item.id,
                        state.frame.minX, state.frame.minY, state.velocity.dx, state.velocity.dy))
            return (item.id, item.pid, item.element)
        }
        return nil
    }

    /// 真窗口被别的途径接手（又被按住拖、被别的排布改了）：代理马上撤，那一次写不再发生。
    func drop(_ id: CGWindowID) {
        guard let item = items.removeValue(forKey: id) else { return }
        item.stage.finish(fade: false)
        wlog("gesture: proxy id=\(id) dropped (\(item.phase))")
    }

    // MARK: - 内部

    /// 落定的弹簧：位置带着手的速度，用 `glide`（甩的动作本身带动量，回弹一点点）；尺寸用 `settle`（不回弹）。
    private static let settleSpring = FlickSpring(dampingRatio: MotionSpring.settle.dampingRatio,
                                                  response: MotionSpring.settle.response)

    private func makeItem(id: CGWindowID, pid: pid_t, element: AXUIElement, frame: CGRect, snapshot: CGImage?) -> Item {
        let stage = WindowProxyStage(frame: frame, look: .choose(hasSnapshot: snapshot != nil), snapshot: snapshot,
                                     cornerRadius: SystemCornerRadius.window)
        stage.clock = clock
        let item = Item(id: id, pid: pid, element: element, original: frame, stage: stage)
        items[id] = item
        return item
    }

    /// 有屏幕录制时在后台截窗口和背景（几十毫秒），截好再把描边换成截图；手势不等它。
    private func requestSnapshot(_ item: Item) {
        guard !item.captureRequested, snapshotsAllowed else { return }
        item.captureRequested = true
        let id = item.id, original = item.original
        let center = cocoaFrame(fromAXPosition: original.origin, size: original.size)
        guard let screen = screenAtPoint(NSPoint(x: center.midX, y: center.midY))
                ?? NSScreen.main else { return }
        let screenAX = CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size)
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let pictures = DragPictures.capture(id: id, screenAX: screenAX)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let item = self.items[id], item.stage.look == .outline,
                          let window = pictures.window else { return }
                    // 已经松手、真窗口那一次写也发出了：不再铺背景（它会盖住刚到位的真窗口原处的东西）。
                    guard item.phase != .writing else { return }
                    item.stage.adopt(snapshot: window, background: pictures.background(covering: item.original),
                                     over: item.original)
                }
            }
        }
    }

    private func settle(_ item: Item, to target: CGRect, velocity: ProxyVelocity) {
        item.phase = .settling
        item.target = target
        item.pendingTarget = nil
        let land: @MainActor () -> Void = { [weak self, weak item] in
            guard let self, let item else { return }
            self.write(item)
        }
        switch presentation {
        case .dissolve:
            item.stage.dissolve(to: target, done: land)
        case .slide:
            let from = item.stage.presentedFrame
            let motion = ProxyMotion(from: from, to: target, velocity: velocity, at: clock())
            item.stage.play(motion, done: land)
        }
    }

    /// 代理到了：真窗口写一次外框（后台），等它在 WindowServer 里到位，再收场。
    private func write(_ item: Item) {
        guard items[item.id] === item, item.phase == .settling, let target = item.target else { return }
        item.phase = .writing
        let token = ledger.open(window: item.id)
        let id = item.id, element = item.element, original = item.original, area = item.area
        let began = clock()
        guard !ArrangementRules.sameFrame(target, original) else {
            // 目标就是原处（接住后撤销回来）：不用写。
            landed(item, observed: original, began: began)
            return
        }
        guard ledger.admitWrite(token) else {
            wlog("gesture: proxy id=\(id) refused a second frame write")
            return
        }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let observed = Self.writeOnce(element: element, id: id, original: original, target: target, area: area)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let item = self.items[id], item.phase == .writing else { return }
                    self.landed(item, observed: observed, began: began)
                }
            }
        }
    }

    private func landed(_ item: Item, observed: CGRect, began: Double) {
        items.removeValue(forKey: item.id)
        item.stage.finish()
        wlog(String(format: "gesture: proxy id=%d landed (%.0f,%.0f %.0fx%.0f) writes=%d waited=%.0fms look=%@", item.id,
                    observed.minX, observed.minY, observed.width, observed.height,
                    ledger.lastAttempts(window: item.id) ?? 0, (clock() - began) * 1000,
                    item.stage.look == .snapshot ? "snapshot" : "outline"))
        item.onLanded?(observed)
    }

    /// 唯一那一次写：和 TrackpadGestureController.setFrame 同一组调用——尺寸、位置各设两遍
    /// （谁先谁后都有 App 吃亏，见那里的注释）。这一组算一次写：同一个外框，一次发出，之后只读不再写。
    /// 之后只读 WindowServer 等它到位，最多 2.5 秒（三指拖移刚抬手时 App 还在拖动里，这一次写会排队到它松手）。
    /// App 不肯变成目标大小（有最小、最大尺寸）时，按它实际的大小放进目标正中——这是唯一允许的第二次挪动，日志里写明。
    nonisolated private static func writeOnce(element: AXUIElement, id: CGWindowID, original: CGRect,
                                              target: CGRect, area: CGRect) -> CGRect {
        _ = setAXSize(element, target.size)
        setAXPosition(element, target.origin)
        _ = setAXSize(element, target.size)
        setAXPosition(element, target.origin)
        let deadline = CACurrentMediaTime() + 2.5
        var observed = target
        var previous: CGRect?
        var steadySince = CACurrentMediaTime()
        while CACurrentMediaTime() < deadline {
            if let info = cgWindowInfo(id), let bounds = cgWindowBounds(info) {
                observed = bounds
                if ProxyLanding.arrived(bounds, at: target) { return bounds }
                if bounds != previous { previous = bounds; steadySince = CACurrentMediaTime() }
                // 已经离开原处、又稳住 150 毫秒还不是目标的样子：App 自己定了大小（或位置被系统夹住）。
                if !ProxyLanding.arrived(bounds, at: original), CACurrentMediaTime() - steadySince > 0.15 { break }
            }
            usleep(8_000)
        }
        if abs(observed.width - target.width) > 4 || abs(observed.height - target.height) > 4 {
            let centered = ProxyLanding.centered(observed.size, in: target, area: area)
            setAXPosition(element, centered.origin)
            wlog("gesture: proxy id=\(id) app kept its own size \(Int(observed.width))x\(Int(observed.height)); centred in the target once")
            return CGRect(origin: axPosition(element) ?? centered.origin, size: observed.size)
        }
        return observed
    }
}
