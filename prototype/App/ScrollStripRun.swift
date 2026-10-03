// 卷轴的执行：把 ScrollStrip 算出来的外框摆到真窗口上，手指滑动时整条跟手，松手按惯性停在列边上
// （停稳时正好停在屏幕边上、挨着停靠列的那一列让出边上露出来的那一条）；
// 每半秒对一次账：关掉的窗口让出位置、被人拖走的不再管、新开的窗口接在当前这列右边、
// 点到（或 ⌘Tab 到）停在屏幕边上的窗口时把它滑出来。
// 指针停在露出来的那一条上看一眼（ScrollStripPeek.swift）；两指张开整条缩小铺开（ScrollStripOverview.swift）。
//
// 挪窗口放在每个 App 各自的后台队列上，只挪最新的目标：慢 App 跟不上时跳过中间几帧，不拖慢手指、不拖慢别的 App。

import Cocoa

/// 后台挪窗口：每个进程一个串行队列，同一扇窗只保留最新的目标。
final class StripMover: @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [pid_t: DispatchQueue] = [:]
    private var pending: [CGWindowID: (element: AXUIElement, frame: CGRect, resize: Bool)] = [:]
    private var scheduled: Set<CGWindowID> = []

    func move(_ element: AXUIElement, pid: pid_t, id: CGWindowID, to frame: CGRect, resize: Bool) {
        lock.lock()
        let keepResize = pending[id]?.resize ?? false
        pending[id] = (element, frame, resize || keepResize)
        let needsJob = !scheduled.contains(id)
        if needsJob { scheduled.insert(id) }
        let queue = queues[pid] ?? DispatchQueue(label: "windowshade.strip.\(pid)", qos: .userInteractive)
        queues[pid] = queue
        lock.unlock()
        guard needsJob else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let job = self.pending.removeValue(forKey: id)
            self.scheduled.remove(id)
            self.lock.unlock()
            guard let job else { return }
            if job.resize {
                _ = setAXSize(job.element, job.frame.size)
                setAXPosition(job.element, job.frame.origin)
                _ = setAXSize(job.element, job.frame.size)
            }
            setAXPosition(job.element, job.frame.origin)
        }
    }
}

@MainActor
final class ScrollStripController {
    unowned let gestures: TrackpadGestureController
    private(set) var strip: ScrollStrip?
    private(set) var displayID: CGDirectDisplayID?
    private var elements: [CGWindowID: AXUIElement] = [:]
    private var pids: [CGWindowID: pid_t] = [:]
    /// 最近一次摆上去的外框：对账时拿它和窗口实际位置比，差得多就是被人拖走了。
    private var applied: [CGWindowID: CGRect] = [:]
    /// 开卷轴时这块屏上已经有的窗口：之后新出现的才算“新开的”。
    private var seen: Set<CGWindowID> = []
    private var watchTimer: Timer?
    /// 对账正在后台问：一次没回来之前不再发第二次（那个 App 卡住时要等满消息超时）。
    private var watchInFlight = false
    /// 停稳动画：和官网那段一样，按「经过了多少时间」算一条解析的阻尼弹簧，帧由显示器的刷新时钟给。
    /// 不再用 60Hz 定时器每帧固定走一小步——那样掉一帧就慢一截、还会和刷新不同步。
    private var motionLink: CADisplayLink?
    /// 拿不到显示器时钟时的退路：定时器只当节拍，位置照样按经过的时间算，不掉速。
    private var motionTimer: Timer?
    private var motionStart: CFTimeInterval = 0
    private var motionFrom: CGFloat = 0
    private var motionTo: CGFloat = 0
    private var motionSpeed: CGFloat = 0
    private var motionZeta: CGFloat = 0
    private var motionOmega: CGFloat = 0
    private var motionLimit: CFTimeInterval = 0
    private var motionFocusVisible = false
    /// CADisplayLink 会强引用它的 target；用一个小代理，免得和控制器成环。
    private lazy var motionProxy = DisplayLinkProxy(owner: self)
    /// 自己刚挪过窗口的这段时间里不对“被人拖走”的账（窗口还在路上）。
    private var busyUntil: CFTimeInterval = 0
    private let mover = StripMover()
    // 滑动中
    private var scrollStart: CGFloat = 0
    private var scrollNow: CGFloat = 0
    private var samples: [(time: TimeInterval, offset: CGFloat)] = []
    /// 探针用：每一步都记下来。
    private(set) var lastSettle: CGFloat?
    /// 上次对账时焦点在哪扇：只有焦点换了（点到、⌘Tab 到）才把它滑出来，不和手指滑动抢。
    private var lastFocused: CGWindowID?
    /// 停在边上的那一条：指针停上去看一眼。
    private(set) lazy var peek = StripPeek(strips: self)
    /// 概览开着时是它。
    private(set) var overview: StripOverview?
    /// 标题栏上两指张开攒了多少（落在哪扇、最后一次什么时候）：走满松手打开概览。
    private var spread: (id: CGWindowID, total: CGFloat, at: TimeInterval)?

    init(gestures: TrackpadGestureController) {
        self.gestures = gestures
    }

    var isActive: Bool { strip != nil }
    func contains(_ id: CGWindowID) -> Bool { strip?.column(of: id) != nil }

    func canWiden(_ id: CGWindowID) -> Bool {
        guard let strip, let index = strip.column(of: id) else { return false }
        return strip.steppedWidth(index, wider: true) != nil
    }

    func canNarrow(_ id: CGWindowID) -> Bool {
        guard let strip, let index = strip.column(of: id) else { return false }
        return strip.steppedWidth(index, wider: false) != nil
    }

    // MARK: 开、关

    func start(_ strip: ScrollStrip, screen: NSScreen, elements: [CGWindowID: AXUIElement], pids: [CGWindowID: pid_t]) {
        stop(reason: "replaced")
        self.strip = strip
        displayID = Self.displayID(screen)
        self.elements = elements
        self.pids = pids
        seen = Set((CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .compactMap { ($0[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) } })
        apply()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watch() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
        wlog("strip: start columns=\(strip.columns.map { $0.ids.count }) widths=\(strip.columns.map { Int($0.width) }) offset=\(Int(strip.offset))")
    }

    func stop(reason: String) {
        guard strip != nil || watchTimer != nil else { return }
        watchTimer?.invalidate(); watchTimer = nil
        endMotion()
        peek.stop()
        overview?.close(picking: nil)
        overview = nil
        spread = nil
        strip = nil
        displayID = nil
        elements.removeAll(); pids.removeAll(); applied.removeAll(); seen.removeAll()
        wlog("strip: stop reason=\(reason)")
    }

    // MARK: 摆放

    /// offset 不为空：正跟着手指或弹簧在走，只挪位置、不按此刻的位置改大小（见 ScrollStrip.placedFrame）：
    /// 往回滑、滑一下又弹回原处都不改；朝停靠列那边滑出去，它一滑进屏幕，挨着它的那列放回原宽（改一次）。
    /// 停稳（offset 为空）再按新位置让出边上那一条，只改让法变了的那几扇。
    private func apply(offset: CGFloat? = nil) {
        guard let strip else { return }
        for (id, raw) in strip.frames(at: offset, moving: offset != nil) {
            let frame = ArrangeGap.apply(raw, in: strip.area)
            guard applied[id] != frame else { continue }
            guard let element = elements[id], let pid = pids[id] else { continue }
            let resize = applied[id].map { abs($0.width - frame.width) > 0.5 || abs($0.height - frame.height) > 0.5 } ?? true
            applied[id] = frame
            gestures.owner.cancelRestorePin(for: id)
            mover.move(element, pid: pid, id: id, to: frame, resize: resize)
        }
        busyUntil = CACurrentMediaTime() + 0.9
        // 停稳了才能看一眼边上那一条；还在动就先收掉。
        if offset == nil, !motionActive {
            peek.update(strip.slivers(gap: ArrangeGap.points), area: strip.area)
        } else {
            peek.dismiss(reason: "moving")
        }
    }

    // MARK: 手指滑动：整条跟手

    func beginScroll() {
        gestures.owner.notch.coachUsed(.stripScroll)
        endMotion()
        peek.dismiss(reason: "scroll")
        scrollStart = strip?.offset ?? 0
        scrollNow = scrollStart
        samples = []
    }

    /// fingerDX：从开始到现在手指一共往右走了多少（点）。内容跟着手指：手指往右，卷轴往右，offset 变小。
    func scroll(fingerDX: CGFloat, at time: TimeInterval) {
        guard let strip else { return }
        var value = scrollStart - fingerDX
        // 两头越往外越拉不动（橡皮筋），松手弹回。
        let limit = Double(strip.area.width * 0.25)
        if value < 0 { value = -CGFloat(FluidMotion.rubberBand(Double(-value), limit: limit)) }
        else if value > strip.maxOffset {
            value = strip.maxOffset + CGFloat(FluidMotion.rubberBand(Double(value - strip.maxOffset), limit: limit))
        }
        scrollNow = value
        samples.append((time, value))
        if samples.count > 8 { samples.removeFirst(samples.count - 8) }
        apply(offset: value)
    }

    /// 松手：按最后一小段的速度推算会停在哪，吸到最近的列边上，接着速度弹簧过去。
    func endScroll() {
        guard let strip else { return }
        var velocity: CGFloat = 0
        if let first = samples.first, let last = samples.last, last.time - first.time > 0.008 {
            velocity = (last.offset - first.offset) / CGFloat(last.time - first.time)
        }
        // 减速率和官网一致（0.998，像普通滚动，滑得远、停得柔）；原来 0.995 停得太急。
        let projected = scrollNow + CGFloat(FluidMotion.projection(velocity: Double(velocity), decelerationRate: 0.998))
        let target = strip.snapped(projected)
        animate(from: scrollNow, to: target, velocity: velocity, focusVisible: true)
        wlog("strip: release offset=\(Int(scrollNow)) velocity=\(Int(velocity)) → \(Int(target))")
    }

    /// 停下来那一段：和官网一样的阻尼弹簧（ζ=0.88、ω=2π/0.42），接上手指离开时的速度。
    /// 位置按「经过了多少时间」解出来，不是每帧加一小步——所以 60Hz 和 120Hz 是同一条曲线，
    /// 掉一帧也不会走样、不会变慢。帧由显示器的刷新时钟（CADisplayLink）给，和屏幕同步。
    /// focusVisible：手指滑完停下后，焦点所在的那扇已经滑出屏幕时，把焦点给停下后露在屏幕上的第一列（niri 也是这样）。
    private func animate(from start: CGFloat, to target: CGFloat, velocity: CGFloat, focusVisible: Bool = false) {
        endMotion()
        peek.dismiss(reason: "moving")
        guard abs(target - start) >= 0.5 else {
            settle(at: target, focusVisible: focusVisible)
            return
        }
        // 减少动态效果：还是走原来那条又快又稳的（临界阻尼、0.2 秒），不跟官网那样瞬间到位。
        let reduced = Motion.reduced
        motionZeta = reduced ? 1 : 0.88
        motionOmega = 2 * .pi / (reduced ? 0.2 : 0.42)
        motionLimit = reduced ? 0.6 : 1.2
        motionFrom = start
        motionTo = target
        motionSpeed = velocity
        motionStart = CACurrentMediaTime()
        motionFocusVisible = focusVisible
        if let screen = motionScreen() {
            let link = screen.displayLink(target: motionProxy, selector: #selector(DisplayLinkProxy.step(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            motionLink = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.advanceMotion() }
            }
            RunLoop.main.add(timer, forMode: .common)
            motionTimer = timer
        }
    }

    private var motionActive: Bool { motionLink != nil || motionTimer != nil }

    private func endMotion() {
        motionLink?.invalidate(); motionLink = nil
        motionTimer?.invalidate(); motionTimer = nil
    }

    /// 这一帧走到哪：解析解，只跟经过的时间有关。
    func advanceMotion() {
        guard strip != nil else { endMotion(); return }
        let t = CACurrentMediaTime() - motionStart
        let state = FluidMotion.springState(t, from: Double(motionFrom), to: Double(motionTo),
                                            velocity: Double(motionSpeed), zeta: Double(motionZeta),
                                            omega: Double(motionOmega))
        let position = CGFloat(state.position)
        if t >= motionLimit || (abs(position - motionTo) < 0.5 && abs(CGFloat(state.velocity)) < 20) {
            settle(at: motionTo, focusVisible: motionFocusVisible)
            return
        }
        // 注意：这里只把窗口挪到 position，不动 strip.offset。offset 是「停稳时在哪」，
        // 滑动中要让 ScrollStrip 拿它和当前位置比，才知道挨着停靠列的那一列什么时候该让回原宽。
        apply(offset: position)
    }

    /// 停到位：钉在目标上，做停稳那一套（对账、让出边上那一条、必要时把焦点那列滑出来）。
    private func settle(at target: CGFloat, focusVisible: Bool) {
        endMotion()
        guard var strip else { return }
        strip.offset = target
        self.strip = strip
        lastSettle = target
        apply()
        if focusVisible { focusVisibleColumn() }
    }

    // MARK: 键盘、列宽

    /// ⌃⌘←→：走到左边、右边那一列，把它滑出来，焦点给它。已经到头返回 false。
    func step(_ id: CGWindowID, toward direction: GestureDirection) -> Bool {
        guard let strip, let index = strip.column(of: id) else { return false }
        let next = direction == .left ? index - 1 : index + 1
        guard strip.columns.indices.contains(next), let target = strip.columns[next].ids.first else { return false }
        lastFocused = target
        focus(target)
        animate(from: strip.offset, to: strip.revealing(next), velocity: 0)
        return true
    }

    /// 这一列宽一档或窄一档，并让它整列露出来。
    func resize(_ id: CGWindowID, wider: Bool) -> Bool {
        guard var strip, let index = strip.column(of: id), let width = strip.steppedWidth(index, wider: wider) else { return false }
        strip.setWidth(width, of: index)
        self.strip = strip
        apply()
        wlog("strip: column \(index) → \(Int(width)) wide")
        return true
    }

    /// 把这扇窗那一列整列滑出来，焦点给它（概览里点它）。
    func reveal(_ id: CGWindowID) {
        guard let strip, let index = strip.column(of: id) else { return }
        lastFocused = id
        if let pid = pids[id] { NSRunningApplication(processIdentifier: pid)?.activate() }
        focus(id)
        animate(from: strip.offset, to: strip.revealing(index), velocity: 0)
        wlog("strip: reveal id=\(id) column=\(index)")
    }

    // MARK: 看一眼、概览

    /// 此刻能不能看一眼边上那一条：卷轴停稳了、概览没开。
    var canPeek: Bool { strip != nil && !motionActive && overview == nil }

    /// 停在两边屏幕外的所有窗口：刘海列“别的桌面上的窗口”时不算它们（它们在这张桌面上，只是挪出了屏幕）。
    var allParkedIDs: Set<CGWindowID> { parkedIDs(on: .left).union(parkedIDs(on: .right)) }

    /// 停在这一边的所有窗口（叠在屏幕边上的几列都算）。
    func parkedIDs(on side: ScrollStrip.Side) -> Set<CGWindowID> {
        guard let strip else { return [] }
        let parked = strip.parked()
        return Set((side == .left ? parked.left : parked.right).flatMap { strip.columns[$0].ids })
    }

    /// 停在边上的这扇（哪一列都算）此刻露出来的那一条；不在边上返回 nil。
    func parkedSliver(of id: CGWindowID) -> ScrollStrip.Sliver? { strip?.sliver(of: id, gap: ArrangeGap.points) }

    func pid(of id: CGWindowID) -> pid_t? { pids[id] }

    /// 概览：整条卷轴缩小铺开，点哪扇就把它那列滑出来。没开卷轴、已经开着返回 false。
    /// 入口是标题栏上两指张开（见 noteSpread）；菜单、快捷键要接的话也调它。
    @discardableResult
    func showOverview(reason: String) -> Bool {
        guard let strip, overview == nil,
              NSScreen.screens.contains(where: { Self.displayID($0) == displayID }) else { return false }
        peek.dismiss(reason: "overview")
        let owner = gestures.owner
        let view = StripOverview(strip: strip, selected: lastFocused, pids: pids,
                                 snapshot: { id in await owner.fastWindowCapture(id) })
        view.onPick = { [weak self] id in
            self?.overview = nil
            self?.reveal(id)
        }
        view.onClose = { [weak self] in self?.overview = nil }
        overview = view
        view.show()
        wlog("strip: overview opens (\(reason)) columns=\(strip.columns.count) offset=\(Int(strip.offset))")
        return true
    }

    /// 标题栏上两指张合了一帧（TrackpadGestures.magnify 转过来）。只记账、不吞事件：卷轴里的窗口张开原本不做事。
    func noteSpread(on id: CGWindowID, delta: CGFloat) {
        guard contains(id) else { return }
        let now = CACurrentMediaTime()
        if let last = spread, last.id == id, now - last.at < 0.3 {
            spread = (id, last.total + delta, now)
        } else {
            spread = (id, delta, now)
        }
    }

    /// 张合松手。confirmed：指针下确认是这扇窗的标题栏。张开走满（和魔法平铺同一个门槛）就打开概览。
    func endSpread(on id: CGWindowID, confirmed: Bool) {
        defer { spread = nil }
        guard confirmed, contains(id), let last = spread, last.id == id,
              last.total >= gestures.tuning.armMagnification else { return }
        showOverview(reason: "spread")
    }

    private func focusVisibleColumn() {
        guard let strip else { return }
        let focusedID = focusedWindow().flatMap { windowID(of: $0) }
        if let focusedID, let index = strip.column(of: focusedID), strip.revealing(index) == strip.offset { return }
        let visible = strip.columns.indices.first { strip.revealing($0) == strip.offset }
        guard let visible, let target = strip.columns[visible].ids.first else { return }
        lastFocused = target
        focus(target)
    }

    private func focus(_ id: CGWindowID) {
        guard let element = elements[id], let pid = pids[id] else { return }
        raiseAXWindow(element)
        focusAXWindow(element, pid: pid)
    }

    // MARK: 对账

    private func watch() {
        guard isActive else { stop(reason: "screen gone"); return }
        guard let screen = NSScreen.screens.first(where: { Self.displayID($0) == displayID }) else {
            stop(reason: "screen gone")
            return
        }
        // 概览开着：焦点在概览上，窗口也没人动，等它收起再对账。
        guard overview == nil, !watchInFlight else { return }
        watchInFlight = true
        // 问窗口服务器和别的 App 都很贵：CGWindowList 一次约 3 毫秒，appWindows 一次实测约 20 毫秒，
        // 碰上一个不响应的 App 还能等到 2 秒的消息超时。这些全放后台线程问，主线程只拿结果对账——
        // 对账每半秒一次，压在主线程上就是动画掉帧。AX 可以在任意线程调用（见 AppWindows.swift）。
        let ownPID = getpid()
        let seenIDs = seen
        let arrangeOnly = gestures.arrangeOnlyPID
        let screenAX = CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let facts = Self.gatherWatchFacts(ownPID: ownPID, seenIDs: seenIDs,
                                              arrangeOnly: arrangeOnly, screenAX: screenAX)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.watchInFlight = false
                    self.applyWatch(facts)
                }
            }
        }
    }

    /// 后台线程问出来的对账素材。
    private struct WatchFacts {
        struct Onscreen { var id: CGWindowID; var pid: pid_t; var bounds: CGRect }
        var bounds: [CGWindowID: CGRect] = [:]
        var onscreen: [Onscreen] = []
        var focusedID: CGWindowID?
        /// 新出现的窗口里通过检查的（标准窗口、够大、在这块屏上）：id → 元素。
        var candidates: [CGWindowID: AXUIElement] = [:]
    }

    private nonisolated static func gatherWatchFacts(ownPID: pid_t, seenIDs: Set<CGWindowID>,
                                                     arrangeOnly: pid_t?, screenAX: CGRect) -> WatchFacts {
        let all = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var facts = WatchFacts()
        facts.bounds.reserveCapacity(all.count)
        for info in all {
            guard let number = info[kCGWindowNumber as String] as? NSNumber, let frame = cgWindowBounds(info) else { continue }
            let id = CGWindowID(number.uint32Value)
            facts.bounds[id] = frame
            if (info[kCGWindowIsOnscreen as String] as? Bool) == true, (info[kCGWindowLayer as String] as? Int) == 0,
               let pid = info[kCGWindowOwnerPID as String] as? pid_t {
                facts.onscreen.append(WatchFacts.Onscreen(id: id, pid: pid, bounds: frame))
            }
        }
        // 新窗口：这块屏上、标准窗口、够大。辅助功能那两次读最贵，也在这里做完。
        for window in facts.onscreen where !seenIDs.contains(window.id) {
            guard window.pid != ownPID, window.bounds.width >= 240, window.bounds.height >= 160,
                  screenAX.contains(CGPoint(x: window.bounds.midX, y: window.bounds.midY)),
                  arrangeOnly.map({ $0 == window.pid }) ?? true,
                  let element = appWindows(pid: window.pid).first(where: { windowID(of: $0) == window.id }),
                  axSubrole(element) == kAXStandardWindowSubrole as String,
                  !axBoolAttribute(element, "AXFullScreen") else { continue }
            facts.candidates[window.id] = element
        }
        facts.focusedID = focusedWindow().flatMap { windowID(of: $0) }
        return facts
    }

    /// 主线程对账：只用后台问好的素材改卷轴，自己不再问窗口服务器或别的 App。
    private func applyWatch(_ facts: WatchFacts) {
        guard var strip else { return }
        let owner = gestures.owner
        let bounds = facts.bounds
        let onscreen = facts.onscreen
        // 卷轴里的窗口全都不在屏幕上：切到了别的桌面、锁了屏、调度中心开着，这时不对账。
        let visibleIDs = Set(onscreen.map(\.id))
        guard strip.ids.contains(where: visibleIDs.contains) else { return }
        var changed = false
        let quiet = CACurrentMediaTime() > busyUntil && !motionActive
        let parkedColumns = strip.parked()
        let parked = Set((parkedColumns.left + parkedColumns.right).flatMap { strip.columns[$0].ids })
        for id in strip.ids {
            // 关掉了、被收起、侧拉、收进刘海：让出位置。
            // 别的窗口都还在、它却不在屏幕上了：关掉、最小化、隐藏了。
            var leave = bounds[id] == nil || !visibleIDs.contains(id)
                || owner.shaded[id] != nil || owner.slideOver.isSlideOver(id) || owner.notch.isTucked(id)
            // 被人拖走、改了大小：不再管它（露在屏幕上的列才比；停在边上的会被系统挪一点）。
            if !leave, quiet, !parked.contains(id), let actual = bounds[id], let expected = applied[id],
               abs(actual.minX - expected.minX) > 24 || abs(actual.minY - expected.minY) > 24
                || abs(actual.width - expected.width) > 24 || abs(actual.height - expected.height) > 24 {
                leave = true
                gestures.forgetPlacement(for: id)
            }
            if leave {
                gestures.noteLeft(id)
                strip.remove(id)
                elements.removeValue(forKey: id); pids.removeValue(forKey: id); applied.removeValue(forKey: id)
                changed = true
                wlog("strip: window \(id) left the strip")
            }
        }
        // 新开的窗口：接在当前这列右边（别的列不变窄）。
        for window in onscreen where !seen.contains(window.id) {
            seen.insert(window.id)
            guard let element = facts.candidates[window.id],
                  owner.shaded[window.id] == nil, !owner.slideOver.isSlideOver(window.id) else { continue }
            let app = NSRunningApplication(processIdentifier: window.pid)
            let category = app?.bundleURL.flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String }
            let role = MagicTiling.role(bundleID: app?.bundleIdentifier, category: category)
            let after = facts.focusedID.flatMap { strip.column(of: $0) } ?? (strip.columns.count - 1)
            strip.insert(window.id, width: ScrollStrip.width(for: role, in: strip.area), after: after)
            elements[window.id] = element
            pids[window.id] = window.pid
            gestures.noteJoined(window.id, element: element, before: window.bounds, area: strip.area)
            changed = true
            wlog("strip: new window \(window.id) joins after column \(after)")
        }
        // 点到（或 ⌘Tab 到）停在边上、只露出一部分的窗口：把它整列滑出来。只在焦点换了的时候。
        let focusChanged = facts.focusedID != lastFocused
        lastFocused = facts.focusedID
        if !changed, focusChanged, !motionActive, let focusedID = facts.focusedID, let index = strip.column(of: focusedID) {
            let target = strip.revealing(index)
            if abs(target - strip.offset) > 1 {
                self.strip = strip
                animate(from: strip.offset, to: target, velocity: 0)
                wlog("strip: reveal focused window \(focusedID)")
                return
            }
        }
        guard changed else { return }
        if strip.columns.count <= 1 {
            self.strip = strip
            apply()
            stop(reason: "one column left")
            return
        }
        self.strip = strip
        apply()
    }

    private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// 卷轴在哪块屏上，就用那块屏的刷新时钟。
    private func motionScreen() -> NSScreen? {
        if let displayID, let screen = NSScreen.screens.first(where: { Self.displayID($0) == displayID }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: 探针

    var offsetForProbe: CGFloat? { strip?.offset }
    var isSettledForProbe: Bool { !motionActive }
    func scrollForProbe(by fingerDX: CGFloat, steps: Int) async {
        beginScroll()
        let t0 = CACurrentMediaTime()
        for step in 1...max(1, steps) {
            scroll(fingerDX: fingerDX * CGFloat(step) / CGFloat(max(1, steps)), at: t0 + Double(step) * 0.016)
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        endScroll()
    }
}

/// CADisplayLink 强引用它的 target：这个代理只弱引用控制器，避免和控制器成环。
/// 回调在主线程的 run loop 上（见 animate），所以直接当主线程用。
private final class DisplayLinkProxy: NSObject {
    weak var owner: ScrollStripController?
    init(owner: ScrollStripController) { self.owner = owner }
    @objc func step(_ link: CADisplayLink) {
        let owner = owner
        MainActor.assumeIsolated { owner?.advanceMotion() }
    }
}
