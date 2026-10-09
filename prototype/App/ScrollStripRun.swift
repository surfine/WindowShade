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
    /// 手指开始滑时卷轴停在哪：滑完换焦点时按卷轴走的方向挑（见 focusVisibleColumn）。
    private var motionScrollFrom: CGFloat = 0
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
    /// 标题栏上两指张开攒了多少（落在哪扇、最后一次什么时候）：张开时概览跟着长，松手按推算过一半才打开。
    private var spread: (id: CGWindowID, total: CGFloat, at: TimeInterval)?
    /// 张开的进度（原始进度，不夹）按时间记下：松手时取最后 0.15 秒算速度。
    private var spreadSamples: [(time: TimeInterval, offset: CGFloat)] = []
    /// 概览正跟着张开在长（还没松手）：这时 overview 是它，但还不接键盘和鼠标。
    private var overviewTracking = false
    /// 按 App 记住的列宽（本机设置）：开卷轴时读一次，你改了宽度时写回去。
    private var widthMemory = StripWidthMemory()
    /// 正在拖的标题栏（卷轴开着、开关开着时才有）。
    private var titleDrag: StripTitleDrag?
    /// 拖标题栏靠屏幕边自动卷：此刻卷到哪（松手前不写回 strip.offset）、刷新时钟、进触发区多久了。
    private var titleDragOffset: CGFloat?
    private var titleEdgeTracker = EdgeScrollTracker()
    private var titleEdgeLink: CADisplayLink?
    private var titleEdgeLastTick: CFTimeInterval = 0
    private var titleEdgePointer: CGPoint = .zero
    private lazy var titleEdgeProxy = TitleEdgeLinkProxy(owner: self)
    /// 蓝条：画在屏幕上最近的那道竖缝上。
    private lazy var seamBar = StripSeamBar()

    init(gestures: TrackpadGestureController) {
        self.gestures = gestures
        // 菜单“窗口”里的“卷轴概览”：卷轴开着才能点。
        StripOverviewMenuTarget.shared.open = { [weak self] in self?.showOverview(reason: "menu") ?? false }
        StripOverviewMenuTarget.shared.canOpen = { [weak self] in self?.canShowOverview ?? false }
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

    func start(_ initial: ScrollStrip, screen: NSScreen, elements: [CGWindowID: AXUIElement], pids: [CGWindowID: pid_t]) {
        stop(reason: "replaced")
        // 设置 › 卷帘 › 排布：走到一列时贴边 / 居中 / 放不下才居中，放得下就居中。放得下时整组先摆到正中。
        var strip = initial
        strip.applyStoredCentering()
        self.strip = strip
        widthMemory = StripWidthMemory.load()
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
        cancelTitleDrag()
        overview?.close(picking: nil)
        overview = nil
        overviewTracking = false
        spread = nil
        spreadSamples = []
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
        strip?.forgetLastInsert()
        scrollStart = strip?.offset ?? 0
        scrollNow = scrollStart
        samples = []
    }

    /// fingerDX：从开始到现在手指一共往右走了多少（点）。内容跟着手指：手指往右，卷轴往右，offset 变小。
    func scroll(fingerDX: CGFloat, at time: TimeInterval) {
        guard let strip else { return }
        var value = scrollStart - fingerDX
        // 两头越往外越拉不动（橡皮筋），松手弹回。两头是 scrollBounds：贴边时是 [0, maxOffset]，
        // 居中方式下第一列、最后一列居中的位置，整组居中时只有那一个点（offset 可以是负数）。
        let limit = Double(strip.area.width * 0.25)
        let bounds = strip.scrollBounds
        if value < bounds.lowerBound {
            value = bounds.lowerBound - CGFloat(FluidMotion.rubberBand(Double(bounds.lowerBound - value), limit: limit))
        } else if value > bounds.upperBound {
            value = bounds.upperBound + CGFloat(FluidMotion.rubberBand(Double(value - bounds.upperBound), limit: limit))
        }
        scrollNow = value
        samples.append((time, value))
        // 只留最近 0.3 秒，松手时再取最后 0.15 秒算速度。
        samples.removeAll { time - $0.time > 0.3 }
        apply(offset: value)
    }

    /// 松手：按最后一小段的速度推算会停在哪，吸到最近的列边上，接着速度弹簧过去。
    /// time 和 scroll(fingerDX:at:) 用同一个时钟：手指停住一会儿再抬起，不会带着旧的速度甩出去。
    func endScroll(at time: TimeInterval) {
        guard let strip else { return }
        let velocity = ScrollStrip.releaseVelocity(samples: samples, releaseTime: time)
        // 减速率和官网一致（0.998，像普通滚动，滑得远、停得柔）；原来 0.995 停得太急。
        let projected = scrollNow + CGFloat(FluidMotion.projection(velocity: Double(velocity), decelerationRate: 0.998))
        let target = strip.snapped(projected)
        animate(from: scrollNow, to: target, velocity: velocity, focusVisible: true)
        wlog("strip: release offset=\(Int(scrollNow)) velocity=\(Int(velocity)) → \(Int(target))")
    }

    /// 停下来那一段：和官网一样的阻尼弹簧（ζ=0.88、ω=2π/0.42），接上手指离开时的速度。
    /// 位置按「经过了多少时间」解出来，不是每帧加一小步——所以 60Hz 和 120Hz 是同一条曲线，
    /// 掉一帧也不会走样、不会变慢。帧由显示器的刷新时钟（CADisplayLink）给，和屏幕同步。
    /// focusVisible：手指滑完停下后，焦点所在的那一列整列滑出了屏幕时，把焦点给朝卷轴走的方向最远、整列露着的那一列
    /// （niri 的挑法，见 ScrollStrip.focusAfterScroll）。
    private func animate(from start: CGFloat, to target: CGFloat, velocity: CGFloat, focusVisible: Bool = false) {
        endMotion()
        self.strip?.forgetLastInsert()
        peek.dismiss(reason: "moving")
        guard abs(target - start) >= 0.5 else {
            motionScrollFrom = focusVisible ? scrollStart : start
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
        motionScrollFrom = focusVisible ? scrollStart : start
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
        animate(from: strip.offset, to: strip.offsetFor(next, previous: index), velocity: 0)
        return true
    }

    /// 设置里改了“走到一列时”或“放得下就居中”：卷轴开着就按新的方式立刻停到该停的位置。
    func refreshCentering() {
        guard var strip, overview == nil else { return }
        let stored = ScrollStrip.storedCentering()
        guard strip.centering != stored.mode || strip.centersWhenFits != stored.whenFits else { return }
        strip.centering = stored.mode
        strip.centersWhenFits = stored.whenFits
        self.strip = strip
        let focusColumn = lastFocused.flatMap { strip.column(of: $0) } ?? strip.columns.indices.first { strip.revealing($0) == strip.offset }
        let target = focusColumn.map { strip.offsetFor($0) } ?? strip.clamped(strip.offset)
        animate(from: strip.offset, to: target, velocity: 0)
    }

    /// ⌃⌘[ ⌃⌘]：焦点那扇窗并进左边或右边那一列，已经在一列里就拆成自己一列。默认不占键（GlobalShortcut）。
    /// 焦点不在卷轴里、旁边没有那一列返回 false。
    @discardableResult
    func joinFocused(toward side: ScrollStrip.Side) -> Bool {
        guard let id = focusedWindow().flatMap({ windowID(of: $0) }), contains(id) else { return false }
        return join(id, toward: side)
    }

    /// 并进左边或右边那一列（叠到那一列底下、高度平分）；已经在一列里就拆成自己一列，宽度同原来那一列。
    /// 每扇至少 280 点高：放不下就不并进，那一列晃一下。返回 true 表示这个动作有了回应（含晃一下）。
    @discardableResult
    func join(_ id: CGWindowID, toward side: ScrollStrip.Side) -> Bool {
        guard var strip, overview == nil, strip.column(of: id) != nil else { return false }
        switch strip.join(id, toward: side) {
        case .none:
            return false
        case .full(let column):
            wlog("strip: join refused, column \(column) already holds \(strip.columns[column].ids.count)")
            refuseJoin(column: column)
            return true
        case .merged(let column), .split(let column):
            endMotion()
            peek.dismiss(reason: "join")
            lastFocused = id
            self.strip = strip
            apply()
            wlog("strip: window \(id) joined/split toward \(side) → column \(column) of \(strip.columns.count)")
            // 只剩一列：卷轴结束，窗口留在原处（和关窗口剩一列时一样）。
            if strip.columns.count <= 1 { stop(reason: "one column left") }
            return true
        }
    }

    /// 那一列放不下：整列的窗口左右晃一下（pop）；减少动态效果、或那一列停在屏幕外时不晃，在刘海上说一句。
    private func refuseJoin(column: Int) {
        guard let strip, strip.columns.indices.contains(column) else { return }
        let parked = strip.parked()
        let ids = strip.columns[column].ids
        if Motion.reduced || parked.left.contains(column) || parked.right.contains(column) {
            _ = gestures.owner.notch.announce("这一列放不下了", tone: .problem)
            return
        }
        for (step, dx) in [8, -8, 5, -3, 0].enumerated() {
            let delta = CGFloat(dx)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(step)) { [weak self] in
                MainActor.assumeIsolated { self?.nudge(ids, dx: delta) }
            }
        }
    }

    /// 晃一下的一步：只在最近摆上去的外框上横着挪一点，不改大小、不改卷轴（挪得不到 24 点，对账不会当成被人拖走）。
    private func nudge(_ ids: [CGWindowID], dx: CGFloat) {
        guard strip != nil else { return }
        for id in ids {
            guard let element = elements[id], let pid = pids[id], var frame = applied[id] else { continue }
            frame.origin.x += dx
            mover.move(element, pid: pid, id: id, to: frame, resize: false)
        }
        busyUntil = max(busyUntil, CACurrentMediaTime() + 0.6)
    }

    /// 这一列宽一档或窄一档，并让它整列露出来。
    func resize(_ id: CGWindowID, wider: Bool) -> Bool {
        guard var strip, let index = strip.column(of: id), let width = strip.steppedWidth(index, wider: wider) else { return false }
        strip.setWidth(width, of: index)
        self.strip = strip
        apply()
        wlog("strip: column \(index) → \(Int(width)) wide")
        rememberWidth(width, of: id, screenWidth: strip.area.width)
        return true
    }

    /// 你给这个 App 改了一次宽度：记下那一档（只存 App 的标识和比例，本机设置，设置里能关、能一键忘掉）。
    private func rememberWidth(_ width: CGFloat, of id: CGWindowID, screenWidth: CGFloat) {
        guard StripWidthMemory.isEnabled(), let pid = pids[id],
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
              widthMemory.remember(bundleID: bundleID, width: width, screenWidth: screenWidth) else { return }
        widthMemory.save()
    }

    /// 把这扇窗那一列整列滑出来，焦点给它（概览里点它）。
    func reveal(_ id: CGWindowID) {
        guard let strip, let index = strip.column(of: id) else { return }
        let previous = lastFocused.flatMap { strip.column(of: $0) }
        lastFocused = id
        if let pid = pids[id] { NSRunningApplication(processIdentifier: pid)?.activate() }
        focus(id)
        animate(from: strip.offset, to: strip.offsetFor(index, previous: previous), velocity: 0)
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
    /// 入口是标题栏上两指张开（见 noteSpread，跟手）和菜单“窗口”里的“卷轴概览”（StandardMenu）。
    @discardableResult
    func showOverview(reason: String) -> Bool {
        guard let view = makeOverview() else { return false }
        view.show()
        wlog("strip: overview opens (\(reason)) columns=\(strip?.columns.count ?? 0) offset=\(Int(strip?.offset ?? 0))")
        return true
    }

    /// 菜单里那一项能不能点：卷轴开着、概览没开。
    var canShowOverview: Bool { strip != nil && overview == nil }

    private func makeOverview() -> StripOverview? {
        guard let strip, overview == nil,
              NSScreen.screens.contains(where: { Self.displayID($0) == displayID }) else { return nil }
        peek.dismiss(reason: "overview")
        let owner = gestures.owner
        let view = StripOverview(strip: strip, selected: lastFocused, pids: pids,
                                 snapshot: { id in await owner.fastWindowCapture(id) })
        view.onPick = { [weak self] id in
            self?.overview = nil
            self?.overviewTracking = false
            self?.reveal(id)
        }
        view.onClose = { [weak self] in
            self?.overview = nil
            self?.overviewTracking = false
        }
        let opened = strip
        view.onMove = { [weak self] id, drop in
            self?.overview = nil
            self?.overviewTracking = false
            self?.moveFromOverview(id, drop, opened: opened)
        }
        overview = view
        return view
    }

    /// 概览里拖着换了位置（或 VoiceOver 动作）：真窗口只摆一轮。概览开着的时候卷轴变过（开了关了窗口）就作废。
    private func moveFromOverview(_ id: CGWindowID, _ drop: ScrollStrip.Drop, opened: ScrollStrip) {
        guard var strip, strip.columns == opened.columns, strip.move(id, to: drop) else { return }
        endMotion()
        peek.dismiss(reason: "overview move")
        lastFocused = id
        self.strip = strip
        apply()
        focus(id)
        wlog("strip: overview moved window \(id) \(drop) → \(strip.columns.count) columns")
        // 只剩一列：卷轴结束，窗口留在原处。
        if strip.columns.count <= 1 { stop(reason: "one column left") }
    }

    /// 标题栏上两指张合了一帧（TrackpadGestures.magnify 转过来）。不吞事件：卷轴里的窗口张开原本不做事。
    /// visible：这一下已经确认落在这扇窗的标题栏上，可以把概览画出来了。张开时概览跟着长（减少动态效果时不跟）。
    func noteSpread(on id: CGWindowID, delta: CGFloat, visible: Bool = false) {
        guard contains(id) else { return }
        let now = CACurrentMediaTime()
        if let last = spread, last.id == id, now - last.at < 0.3 {
            spread = (id, last.total + delta, now)
        } else {
            if overviewTracking { cancelSpread() }
            spread = (id, delta, now)
            spreadSamples = []
        }
        guard let total = spread?.total else { return }
        let raw = StripOverviewSpread.rawProgress(total: total, arm: gestures.tuning.armMagnification)
        spreadSamples.append((now, raw))
        spreadSamples.removeAll { now - $0.time > 0.3 }
        guard visible, !Motion.reduced else { return }
        if overviewTracking {
            overview?.track(StripOverviewSpread.shown(raw))
        } else if overview == nil, raw > 0, let view = makeOverview() {
            overviewTracking = true
            view.beginTracking()
            view.track(StripOverviewSpread.shown(raw))
            wlog("strip: overview follows the spread")
        }
    }

    /// 张合松手。confirmed：指针下确认是这扇窗的标题栏。按推算的进度过一半就打开（手停住时和从前走满的门槛一样），
    /// 否则收回。没跟手（减少动态效果、确认晚到）时，开就只淡入。
    func endSpread(on id: CGWindowID, confirmed: Bool) {
        defer { spread = nil; spreadSamples = [] }
        let now = CACurrentMediaTime()
        let raw = spread.flatMap { $0.id == id ? StripOverviewSpread.rawProgress(total: $0.total, arm: gestures.tuning.armMagnification) : nil }
        let velocity = ScrollStrip.releaseVelocity(samples: spreadSamples, releaseTime: now)
        let opens = confirmed && contains(id) && raw.map { StripOverviewSpread.opens(progress: $0, velocity: velocity) } == true
        if overviewTracking, let view = overview {
            // 不论开不开都不再跟手：开了就是一个普通的概览（铺好后接键盘、鼠标），收回时它收起会把 overview 清掉。
            overviewTracking = false
            view.finishTracking(open: opens, velocity: velocity)
            wlog("strip: spread released at \(String(format: "%.2f", raw ?? 0)) v=\(String(format: "%.2f", velocity)) → \(opens ? "open" : "back")")
            return
        }
        guard opens else { return }
        showOverview(reason: "spread")
    }

    /// 张合被系统取消、手势换了：跟着长的概览收回，什么都不开。
    func cancelSpread() {
        spread = nil
        spreadSamples = []
        guard overviewTracking, let view = overview else { return }
        overviewTracking = false
        view.finishTracking(open: false, velocity: 0)
    }

    /// 焦点那一列整列滑出屏幕才换焦点（换焦点就是激活另一个 App，能不换就不换）；焦点不在卷轴里时照旧给一列。
    private func focusVisibleColumn() {
        guard let strip else { return }
        let focusedID = focusedWindow().flatMap { windowID(of: $0) }
        let focusedColumn = focusedID.flatMap { strip.column(of: $0) }
        guard let pick = strip.focusAfterScroll(focused: focusedColumn, from: motionScrollFrom),
              pick != focusedColumn, let target = strip.columns[pick].ids.first else { return }
        lastFocused = target
        focus(target)
        wlog("strip: focus after scroll → column \(pick)")
    }

    private func focus(_ id: CGWindowID) {
        guard let element = elements[id], let pid = pids[id] else { return }
        raiseAXWindow(element)
        focusAXWindow(element, pid: pid)
    }

    // MARK: 卷轴开着时拖标题栏（稿：卷轴.html“拖着挪一扇”，工作包 SS-07；开关默认关）

    /// 拖着卷轴里一扇窗的标题栏挪了一下（TrackpadGestures 旁听到，窗口确实在跟着指针走）。坐标都是 AX。
    /// 在最近的竖缝上画蓝条；靠屏幕边按 30 点 / 100 毫秒 / 每秒 1500 点自动卷（只挪别的窗口的位置，不改大小）。
    /// 返回 true：这一下还归卷轴管，侧拉、画中画的落点提示先不出。卷轴关着、开关没开、竖着拉开了 256 点：返回 false，
    /// 拖窗口和从前一模一样。
    @discardableResult
    func titleDragMoved(_ id: CGWindowID, down: CGPoint, to pointer: CGPoint) -> Bool {
        if titleDrag?.id != id {
            cancelTitleDrag()
            guard overview == nil, !motionActive,
                  let begun = StripTitleDrag.begin(id: id, down: down, strip: strip, enabled: StripTitleDrag.isEnabled())
            else { return false }
            titleDrag = begun
            peek.dismiss(reason: "title drag")
            wlog("strip: title drag on window \(id)")
        }
        guard var drag = titleDrag, let strip else { return false }
        drag.update(pointer: pointer, strip: strip, offset: titleDragOffset)
        titleDrag = drag
        titleEdgePointer = pointer
        guard !drag.leaving else {
            seamBar.hide()
            stopTitleEdgeScroll()
            return false
        }
        showSeam(drag.seam)
        updateTitleEdgeScroll()
        return true
    }

    /// 这一下拖动此刻还归卷轴管（指针还在卷轴里挑缝）。
    func holdsTitleDrag(_ id: CGWindowID) -> Bool {
        guard let titleDrag else { return false }
        return titleDrag.id == id && !titleDrag.leaving
    }

    /// 松手（侧拉、画中画、刘海下面的小岛先判过了，没接走才到这里）。返回 true：卷轴接住了（换到蓝条那道缝，
    /// 或者回原位），甩一下那些判定不再做。返回 false：照从前的拖法走（拉远了就离开卷轴，对账时让出位置）。
    /// stillOpen：三指拖移还没真结束，App 这时不理挪窗口，稍等再摆。
    func titleDragEnded(_ id: CGWindowID, at pointer: CGPoint, intoNotch: Bool = false, stillOpen: Bool = false) -> Bool {
        guard let drag = titleDrag, drag.id == id else { return false }
        guard case .stay(let drop) = drag.end(pointer: pointer, intoNotch: intoNotch) else {
            // 离开卷轴：靠边卷过的话，别的列停在卷到的地方附近，不弹回去；拖着的那扇留在松手的地方，对账时让出位置。
            cancelTitleDrag()
            wlog("strip: title drag on window \(id) leaves the strip")
            return false
        }
        let scrolled = titleDragOffset
        titleDrag = nil
        titleDragOffset = nil
        seamBar.hide()
        stopTitleEdgeScroll()
        guard var strip, strip.column(of: id) != nil else { return false }
        if let scrolled { strip.offset = strip.snapped(scrolled) }
        if let drop { strip.move(id, to: drop) }
        self.strip = strip
        lastFocused = id
        // 拖着的那扇已经被系统挪开了：忘掉上次摆的外框，摆的时候它一定挪回去。
        applied.removeValue(forKey: id)
        if stillOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                MainActor.assumeIsolated { self?.apply() }
            }
        } else {
            apply()
        }
        wlog("strip: title drag on window \(id) → \(drop.map { "\($0)" } ?? "back in place")")
        return true
    }

    /// 这次拖动作废（又按下了一次、晃了一晃、卷轴结束）：蓝条收掉，自动卷停下，窗口由下一次摆放或对账归位。
    func cancelTitleDrag() {
        guard titleDrag != nil || titleDragOffset != nil else { return }
        let dragged = titleDrag?.id
        let scrolled = titleDragOffset
        titleDrag = nil
        titleDragOffset = nil
        seamBar.hide()
        stopTitleEdgeScroll()
        // 靠边卷过：卷轴就停在卷到的地方附近（吸到最近的列边），拖着的那扇不跟着挪（它在指针下）。
        guard let scrolled, var strip else { return }
        strip.offset = strip.snapped(scrolled)
        self.strip = strip
        if let dragged, let raw = strip.frames()[dragged] { applied[dragged] = ArrangeGap.apply(raw, in: strip.area) }
        apply()
    }

    private func showSeam(_ seam: ScrollStrip.Seam?) {
        if let seam { seamBar.show(seam.bar) } else { seamBar.hide() }
    }

    /// 指针进了屏幕边 30 点以内就开刷新时钟（停够 100 毫秒才开始卷），出来就停：不拖、不靠边时没有任何定时器。
    private func updateTitleEdgeScroll() {
        guard let strip else { return }
        _ = titleEdgeTracker.velocity(pointerX: titleEdgePointer.x - strip.area.minX, width: strip.area.width,
                                      now: CACurrentMediaTime())
        guard titleEdgeTracker.isInZone else {
            stopTitleEdgeScroll()
            return
        }
        guard titleEdgeLink == nil, let screen = motionScreen() else { return }
        let link = screen.displayLink(target: titleEdgeProxy, selector: #selector(TitleEdgeLinkProxy.step(_:)))
        link.add(to: .main, forMode: .common)
        titleEdgeLink = link
        titleEdgeLastTick = CACurrentMediaTime()
    }

    private func stopTitleEdgeScroll() {
        titleEdgeLink?.invalidate()
        titleEdgeLink = nil
        titleEdgeTracker.reset()
    }

    /// 靠边自动卷的一帧：卷轴往那一边走，别的窗口只挪位置；蓝条跟着缝走。
    fileprivate func titleEdgeStep() {
        guard var drag = titleDrag, !drag.leaving, let strip else {
            stopTitleEdgeScroll()
            return
        }
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - titleEdgeLastTick)
        titleEdgeLastTick = now
        let velocity = titleEdgeTracker.velocity(pointerX: titleEdgePointer.x - strip.area.minX, width: strip.area.width, now: now)
        guard titleEdgeTracker.isInZone else {
            stopTitleEdgeScroll()
            return
        }
        let current = titleDragOffset ?? strip.offset
        let bounds = strip.scrollBounds
        let next = min(max(current + velocity * dt, bounds.lowerBound), bounds.upperBound)
        guard abs(next - current) >= 0.25 else { return }
        titleDragOffset = next
        for (id, frame) in strip.slidFrames(at: next, sizes: applied, excluding: drag.id, gap: ArrangeGap.points)
        where applied[id] != frame {
            guard let element = elements[id], let pid = pids[id] else { continue }
            applied[id] = frame
            mover.move(element, pid: pid, id: id, to: frame, resize: false)
        }
        busyUntil = CACurrentMediaTime() + 0.9
        drag.update(pointer: titleEdgePointer, strip: strip, offset: next)
        titleDrag = drag
        showSeam(drag.seam)
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
            // 拖着标题栏、还在卷轴里挑缝的那扇不算被拖走：松手才知道它去哪。
            if !leave, quiet, !parked.contains(id), !holdsTitleDrag(id), let actual = bounds[id], let expected = applied[id],
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
            // 你给这个 App 改过宽度就用那一档，没改过照 App 要的地方给。
            let remembered = StripWidthMemory.isEnabled() ? widthMemory.width(for: app?.bundleIdentifier, in: strip.area) : nil
            strip.insert(window.id, width: remembered ?? ScrollStrip.width(for: role, in: strip.area), after: after)
            elements[window.id] = element
            pids[window.id] = window.pid
            gestures.noteJoined(window.id, element: element, before: window.bounds, area: strip.area)
            changed = true
            wlog("strip: new window \(window.id) joins after column \(after)")
        }
        // 点到（或 ⌘Tab 到）停在边上、只露出一部分的窗口：把它整列滑出来。只在焦点换了的时候。
        let focusChanged = facts.focusedID != lastFocused
        let previousColumn = lastFocused.flatMap { strip.column(of: $0) }
        lastFocused = facts.focusedID
        if !changed, focusChanged, !motionActive, let focusedID = facts.focusedID, let index = strip.column(of: focusedID) {
            let target = strip.offsetFor(index, previous: previousColumn)
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
        endScroll(at: t0 + Double(max(1, steps)) * 0.016)
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

/// 拖标题栏靠边自动卷的刷新时钟代理：只弱引用控制器。回调在主线程的 run loop 上。
private final class TitleEdgeLinkProxy: NSObject {
    weak var owner: ScrollStripController?
    init(owner: ScrollStripController) { self.owner = owner }
    @objc func step(_ link: CADisplayLink) {
        let owner = owner
        MainActor.assumeIsolated { owner?.titleEdgeStep() }
    }
}

/// 拖标题栏时画在屏幕竖缝上的蓝条：不接鼠标、不抢焦点，浮在窗口上面（拖动途中窗口归系统画，我们只能在旁边画提示）。
@MainActor
final class StripSeamBar {
    private var panel: NSPanel?

    /// bar：AX 坐标。
    func show(_ bar: CGRect) {
        let frame = cocoaFrame(fromAXPosition: bar.origin, size: bar.size)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if let layer = panel.contentView?.layer {
            panel.contentView?.effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.backgroundColor = NSColor.controlAccentColor.cgColor
            }
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = ScrollStrip.seamThickness / 2
        panel.contentView = view
        panel.setAccessibilityElement(false)
        return panel
    }
}
