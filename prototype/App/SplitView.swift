// 分屏（iPadOS Split View）：两扇窗口左右拼满一块屏，中间一根小竖条——拖它两扇一起变宽变窄，松手按速度吸到
// ⅓/½/⅔，推到屏幕边那一扇让开进侧拉、另一扇铺满；竖屏上下拼满时是横条。Apple 支持文档 125309：“拖中间那条来
// 调整两个窗口的大小”。不止两扇：四角、三分、网格、魔法平铺带侧栏，排好的窗口之间每条缝都有一根把手，拖它这条缝
// 两边的窗口一起变（Swish 的“拖分隔线同时调多扇”）；只有两扇拼满时推边上才让一扇进侧拉。什么时候看：切 App、
// 排窗口、换桌面立刻看一次；没缝时两秒一次找新分屏，有把手时靠 WindowStateHub 的窗口事件（挪动、改大小、来了、走了立刻重认，
// 1 秒心跳兜底，SkyLight 通知用不了时退回半秒一次；都只问 WindowServer 一张窗口表，不问各 App）；认缝规则
// 见 Core/SeamLayout.swift。不认收起的、侧拉的、画中画的、收进刘海的、卷轴里的；有别的窗浮在前面时把手收掉。
// 松手后窗口还在滑的那会儿按落点认缝，滑完回读实际外框——App 不肯缩放时按它实际的边再挪一次缝。

import Cocoa

@MainActor
final class SplitViewController {
    nonisolated static let enabledKey = "SplitView.divider"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? ReleaseDefaults.value(enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    unowned let owner: AppDelegate
    private var dividers: [SplitDivider] = []
    private var seams: [Seam] = []
    private var timer: Timer?
    /// 有缝时靠 WindowStateHub 的事件维持（不再半秒一次）：盯着屏上的每扇普通窗口（连最小化、orderOut 的也盯，
    /// 它们被叫回来时 SkyLight 只给被盯的窗口发事件），任何一扇挪了/改了/来了/走了就合成一次重认；
    /// 没缝时不盯，仍是 2 秒一次的定时刷新。
    private var windowWatches: [CGWindowID: WindowWatch] = [:]
    private var anyChangeWatch: WindowWatch?
    /// 最近一次后台扫描里要盯的窗口（在屏的普通窗口，有缝时再加上不在屏的，见 SplitScan.isWatchCandidate）。
    private var scannedWindowIDs: [CGWindowID] = []
    /// 1 秒心跳只认这一扇（共享看门狗每拍给每个订阅发一次）：事件盖不到的变化（比如换前后顺序）靠它兜底重认。
    private var heartbeatID: CGWindowID?
    private var eventRefreshQueued = false
    private var lastEventRefreshAt: TimeInterval = 0
    /// 事件来时上一次扫描还没回来：回来后补一次。
    private var refreshAfterScan = false
    /// hub 试过了事件用不了（SkyLight 通知载不到）：不再每次扫描都试，退回半秒一次的定时器。
    private var eventsUnavailable = false
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    /// 认缝在后台算：一次只放一个；锁屏、睡眠时作废在途的结果。
    private static let scanQueue = DispatchQueue(label: "windowshade.splitview.scan", qos: .utility)
    private var scanInFlight = false
    private var scanGeneration = 0
    private var signatureGate = SplitSignatureGate()
    /// 上一次算出来的候选缝（还没按收起、侧拉等过滤）：签名相同时直接拿它再过滤。
    private var candidates: [Seam] = []
    private var pause = SplitPauseState()
    /// 探针/测试用：相同签名跳过的次数。
    var skippedScansForProbe: Int { signatureGate.skipped }
    /// 拖着一根把手：起点那条缝、缝两边窗口的辅助功能元素和各自写外框的那条链、缝现在在哪。
    private var drag: Drag?
    @MainActor private final class Drag {
        let seam: Seam
        let divider: SplitDivider
        var elements: [UInt32: AXUIElement] = [:]
        var writers: [UInt32: LatestValueWriter<CGRect>] = [:]
        /// 缝现在在哪（过了拖动范围带阻力）。
        var position: CGFloat
        /// 手推到哪（不带阻力）：松手时看推没推到屏幕边。
        var proposed: CGFloat
        var ready: Bool { !writers.isEmpty }
        init(seam: Seam, divider: SplitDivider) {
            self.seam = seam; self.divider = divider; position = seam.position; proposed = seam.position
        }
    }
    /// 松手后正在滑向落点的窗口和各自的终点：认缝时按终点算；再抓把手时先停下它们再开写。
    private var glides: [CGWindowID: (glide: WindowGlide, to: CGRect)] = [:]
    /// 松手后还在滑的每一批（一条缝一批，同几扇窗只留最新的一批）：都停下后回读实际外框，挪一次缝或记撤销（见 settle）。
    private var settlings: [Settling] = []
    private final class Settling {
        let seam: Seam
        let position: CGFloat
        let elements: [UInt32: AXUIElement]
        /// 拖之前的框：撤销回到这里。
        let original: [UInt32: CGRect]
        /// 已经按回读挪过一次缝（或者是退回拖之前）：这次滑完不再挪。
        let corrected: Bool
        var observed: [UInt32: CGRect] = [:]
        var pending = 0
        init(seam: Seam, position: CGFloat, elements: [UInt32: AXUIElement], original: [UInt32: CGRect], corrected: Bool) {
            self.seam = seam; self.position = position; self.elements = elements
            self.original = original; self.corrected = corrected
        }
    }

    init(owner: AppDelegate) {
        self.owner = owner
    }

    /// 探针用。
    var seamsForProbe: [Seam] { seams }
    /// 探针用（--hold split）：现在靠什么维持把手——"events"（盯着窗口，没有定时器）、"timer 0.5"/"timer 2"、"none"。
    var maintenanceForProbe: String {
        if let timer { return "timer \(timer.timeInterval)" }
        return anyChangeWatch != nil && !windowWatches.isEmpty ? "events" : "none"
    }
    var dividerFramesForProbe: [NSRect] { dividers.prefix(seams.count).filter(\.isVisible).map(\.frame) }

    /// 探针用：按住第 index 根把手拖到 position（沿缝的法向），以 velocity（点/秒）松手。
    func dragForProbe(_ index: Int = 0, to position: CGFloat, velocity: CGFloat) async {
        guard seams.indices.contains(index) else { return }
        let seam = seams[index], divider = dividers[index]
        beginDrag(divider)
        for _ in 0..<40 where drag?.ready != true { try? await Task.sleep(for: .milliseconds(25), clock: .suspending) }
        let along = position - seam.position
        updateDrag(divider, seam.axis == .vertical ? CGVector(dx: along, dy: 0) : CGVector(dx: 0, dy: -along))
        try? await Task.sleep(for: .milliseconds(150), clock: .suspending)
        endDrag(divider, velocity: seam.axis == .vertical ? CGVector(dx: velocity, dy: 0) : CGVector(dx: 0, dy: -velocity))
    }

    func start() {
        guard FeatureCatalog.isEnabled(.inputEnhancements) else { return }
        guard observers.isEmpty else { return }
        eventsUnavailable = false
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.soon() }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.soon() }
        })
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            let reason: SplitPauseState.Reason = name == NSWorkspace.screensDidSleepNotification ? .screensAsleep : .sessionInactive
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend(reason) }
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let reason: SplitPauseState.Reason = name == NSWorkspace.screensDidWakeNotification ? .screensAsleep : .sessionInactive
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.unsuspend(reason) }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend(.locked) }
        })
        distributedObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.unsuspend(.locked) }
        })
        schedule()
    }

    /// 模块关闭：停掉定时器、拆掉没装完的观察者。
    func stop() {
        timer?.invalidate()
        timer = nil
        dropWatches()
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
        for observer in distributedObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        distributedObservers.removeAll()
        scanGeneration += 1
        scanInFlight = false
    }

    /// 锁屏、屏幕睡眠、会话切走：停掉定时器，作废在途的结果。
    private func suspend(_ reason: SplitPauseState.Reason) {
        guard pause.pause(reason) else { return }
        timer?.invalidate()
        timer = nil
        dropWatches()
        scanGeneration += 1
        scanInFlight = false
    }

    /// 解锁、亮屏、会话回来：全回来了就立刻看一次再恢复定时器。
    private func unsuspend(_ reason: SplitPauseState.Reason) {
        guard pause.resume(reason) else { return }
        signatureGate.reset()
        refresh()
        schedule()
    }

    /// 换了桌面：上一张桌面的把手先收掉，等窗口落定再按这张桌面重新认。
    private func spaceChanged() {
        if drag == nil { for divider in dividers { divider.hide() } }
        soon()
    }

    /// 排了窗口、切了 App：窗口还在动，稍等一下再看。
    func soon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard !pause.isPaused else { dropWatches(); return }
        if seams.isEmpty || eventsUnavailable { dropWatches() } else { syncWatches() }
        let eventDriven = !windowWatches.isEmpty && WindowStateHub.shared.isEventDriven
        if !seams.isEmpty, !windowWatches.isEmpty, !eventDriven { eventsUnavailable = true }
        switch SplitScan.maintenance(hasSeams: !seams.isEmpty, eventDriven: eventDriven) {
        case .events:
            return
        case .timer(let interval):
            // 有缝却用不了事件（hub 退回轮询）：别让 hub 白白多查，退回改动前的定时器。
            if !seams.isEmpty { dropWatches() }
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            t.tolerance = interval * 0.2
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    /// 让订阅和最近一次扫描里在屏的窗口一致；只在有缝时调用。
    private func syncWatches() {
        let hub = WindowStateHub.shared
        let wanted = Set(scannedWindowIDs)
        for id in Array(windowWatches.keys) where !wanted.contains(id) {
            windowWatches[id]?.cancel()
            windowWatches[id] = nil
        }
        // 心跳那扇走了（或还没有）就换一扇：留着旧的订阅不动，只改认哪一扇。
        if heartbeatID == nil || !wanted.contains(heartbeatID!) { heartbeatID = wanted.min() }
        for id in wanted.sorted() where windowWatches[id] == nil {
            windowWatches[id] = hub.watch(id, fallbackInterval: SplitScan.seamInterval, heartbeat: true) {
                [weak self] change, _ in
                if change == .heartbeat { self?.heartbeat(from: id) }
            }
        }
        if anyChangeWatch == nil {
            anyChangeWatch = hub.observeAnyChange { [weak self] batch in self?.anyChange(batch) }
        }
    }

    private func dropWatches() {
        for watch in windowWatches.values { watch.cancel() }
        windowWatches.removeAll()
        anyChangeWatch?.cancel()
        anyChangeWatch = nil
        heartbeatID = nil
        refreshAfterScan = false
    }

    /// hub 的 1 秒心跳：事件盖不到的变化（前后顺序）靠它兜底。事件突然不可用了就退回定时器。
    private func heartbeat(from id: CGWindowID) {
        guard id == heartbeatID else { return }
        if !WindowStateHub.shared.isEventDriven { eventsUnavailable = true; schedule(); return }
        refresh()
    }

    /// hub 的一批变化。只有桌面成员事件（1325/1326，菜单、提示框、弹出框都有）时先查一次这几扇的层级，
    /// 有别家的普通窗口才重认；被盯窗口的变化、叠放次序变化（808）直接重认。
    private func anyChange(_ batch: WindowHubBatch) {
        if SplitScan.needsSpaceWindowCheck(windowChanges: batch.changes.count, reordered: batch.reordered.count,
                                           spaceEvents: batch.spaceEvents.count) {
            let ids = Array(Set(batch.spaceEvents.map(\.windowID)))
            let windows = WindowStateHub.describeWindows(ids).map {
                (layer: ($0[kCGWindowLayer as String] as? NSNumber)?.intValue,
                 pid: ($0[kCGWindowOwnerPID as String] as? NSNumber).map { pid_t($0.int32Value) })
            }
            guard SplitScan.spaceWindowsWarrantScan(windows, me: getpid()) else { return }
        }
        queueEventRefresh()
    }

    /// 窗口事件来了：合成一次刷新（松手后窗口滑动时每帧都有事件，最多每 0.1 秒认一次）。
    private func queueEventRefresh() {
        guard !eventRefreshQueued else { return }
        eventRefreshQueued = true
        let delay = SplitScan.eventRefreshDelay(sinceLast: ProcessInfo.processInfo.systemUptime - lastEventRefreshAt)
        MainTimer.fire(after: delay, tolerance: 0) { [weak self] in
            guard let self else { return }
            self.eventRefreshQueued = false
            self.lastEventRefreshAt = ProcessInfo.processInfo.systemUptime
            self.refresh()
        }
    }

    /// 平时的刷新：CGWindowList 和认缝在后台串行队列算，回到主线程再按收起、侧拉等状态过滤、摆把手。
    func refresh() {
        guard SplitScan.canRefresh(dragging: drag != nil, paused: pause.isPaused, inFlight: scanInFlight) else {
            if scanInFlight, drag == nil, !pause.isPaused, anyChangeWatch != nil { refreshAfterScan = true }
            return
        }
        guard Self.isEnabled && AXIsProcessTrusted() else {
            candidates = []; signatureGate.reset()
            show([])
            return
        }
        let glideTargets = glides.mapValues(\.to)
        let areas = Self.areas()
        let gap = ArrangeGap.points
        let lastSignature = signatureGate.last
        let generation = scanGeneration
        scanInFlight = true
        Self.scanQueue.async { [weak self] in
            let windows = Self.windows(glideTargets: glideTargets)
            let signature = SplitScan.signature(windows: windows, areas: areas)
            let fresh: [Seam]? = signature == lastSignature ? nil : Self.candidateSeams(windows, areas: areas, gap: gap)
            // 要盯的集合只在窗口有变（签名不同）时重算，和以前一样；有候选缝时再查一次全部窗口，把不在屏的
            // 普通窗口也算进来（窗口最小化、移走都会让签名变，所以集合不会过期）。没缝的平时不多查。
            var watchIDs: [CGWindowID]?
            if let fresh {
                var ids = windows.map(\.id)
                if !fresh.isEmpty {
                    let onScreen = Set(ids)
                    ids += Self.offScreenWatchCandidates(areas: areas).filter { !onScreen.contains($0) }
                }
                watchIDs = ids.sorted()
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finishScan(generation: generation, signature: signature, fresh: fresh, watchIDs: watchIDs)
                }
            }
        }
    }

    private func finishScan(generation: Int, signature: Int, fresh: [Seam]?, watchIDs: [CGWindowID]?) {
        guard generation == scanGeneration else { return }
        scanInFlight = false
        // 扫描期间又来过事件：回来补一次（队列里排，不在这里递归）。
        defer { if refreshAfterScan { refreshAfterScan = false; queueEventRefresh() } }
        // 拖着把手时不刷新：结果丢掉，松手后会重认。
        guard drag == nil, !pause.isPaused else { return }
        _ = signatureGate.shouldCompute(signature)   // 不同则记下，相同则计一次跳过
        if let watchIDs { scannedWindowIDs = watchIDs }
        if let fresh { candidates = fresh }
        let found = filtered(candidates)
        // 候选和收起、侧拉等状态都没变：把手已经摆好，不用再 show。
        if fresh == nil, found == seams { return }
        show(found)
        // 窗口集合变了（来了新窗口、关了旧的）而有没有缝没变：show 不会重排维护，这里补上订阅。
        if !seams.isEmpty {
            if anyChangeWatch != nil {
                syncWatches()
            } else if timer != nil, !eventsUnavailable, !scannedWindowIDs.isEmpty {
                schedule()   // 之前没窗口可盯、先用了定时器：现在有了，改成靠事件
            }
        }
    }

    /// 松手后马上重认：一次性、要立刻拿到结果，仍在主线程同步算。
    private func currentSeams() -> [Seam] {
        guard Self.isEnabled && AXIsProcessTrusted() else { return [] }
        let windows = Self.windows(glideTargets: glides.mapValues(\.to))
        let found = Self.candidateSeams(windows, areas: Self.areas(), gap: ArrangeGap.points)
        candidates = found
        signatureGate = SplitSignatureGate()
        return filtered(found)
    }

    /// 按认出来的缝摆好把手（except 那根正在自己走、手上正拖着的那根，都不去动）；有没有缝变了，就换看的频率。
    private func show(_ found: [Seam], except moving: SplitDivider? = nil) {
        let changedActivity = seams.isEmpty != found.isEmpty
        seams = found
        while dividers.count < found.count { dividers.append(makeDivider()) }
        for (index, divider) in dividers.enumerated() where divider !== moving && divider !== drag?.divider {
            if index < found.count {
                divider.show(at: barCenter(found[index], among: found), vertical: found[index].axis == .vertical)
            } else {
                divider.hide()
            }
        }
        if changedActivity {
            schedule()
            // 第一次拼出分屏：在刘海上教一下拖中间那根条。
            if !found.isEmpty { _ = owner.notch.teach(.splitBar) }
        }
    }

    private func makeDivider() -> SplitDivider {
        let divider = SplitDivider()
        divider.onBegin = { [weak self, weak divider] in if let divider { self?.beginDrag(divider) } }
        divider.onDrag = { [weak self, weak divider] delta in if let divider { self?.updateDrag(divider, delta) } }
        divider.onEnd = { [weak self, weak divider] velocity in if let divider { self?.endDrag(divider, velocity: velocity) } }
        return divider
    }

    /// 每块屏的可用区域（AX 坐标）。只能在主线程取。
    private static func areas() -> [CGRect] {
        NSScreen.screens.map { screen in
            let visible = screen.visibleFrame
            return CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
        }
    }

    /// 前后排好的普通窗口。松手后还在滑的窗口按终点算：滑到一半两边对不上，把手不该跟着消失又出现。
    nonisolated private static func windows(glideTargets: [CGWindowID: CGRect]) -> [SplitWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let me = getpid()
        var windows: [SplitWindow] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  var bounds = cgWindowBounds(info) else { continue }
            if let target = glideTargets[id] { bounds = target }
            guard bounds.width > 80, bounds.height > 60 else { continue }
            windows.append(SplitWindow(id: id, frame: bounds))
        }
        return windows
    }

    /// 候选缝：只看窗口外框，不碰收起、侧拉这些主线程状态（回到主线程再过滤）。
    nonisolated private static func candidateSeams(_ windows: [SplitWindow], areas: [CGRect], gap: CGFloat) -> [Seam] {
        areas.flatMap { SeamLayout.seams(frontToBack: windows, area: $0, gap: gap) }
    }

    /// 不在屏的普通窗口（最小化、orderOut、别的桌面上的）：有缝时也盯着，它们被叫回到缝上时才有事件。
    nonisolated private static func offScreenWatchCandidates(areas: [CGRect]) -> [CGWindowID] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let me = getpid()
        return list.compactMap { info in
            guard (info[kCGWindowIsOnscreen as String] as? Bool) != true,
                  SplitScan.isWatchCandidate(layer: info[kCGWindowLayer as String] as? Int,
                                             pid: info[kCGWindowOwnerPID as String] as? pid_t, me: me,
                                             bounds: cgWindowBounds(info), areas: areas) else { return nil }
            return info[kCGWindowNumber as String] as? CGWindowID
        }
    }

    /// 收起的、侧拉的、画中画的、收进刘海的、卷轴里的窗口不认。
    private func filtered(_ candidates: [Seam]) -> [Seam] {
        let gestures = owner.gestures
        return candidates.filter { seam in
            let ids = (seam.before + seam.after).map(\.id)
            return !ids.contains(where: { owner.shaded[$0] != nil || owner.slideOver.isSlideOver($0) || owner.pip.isInPictureInPicture($0)
                || owner.notch.isTucked($0) || gestures.strips.contains($0) })
        }
    }

    /// 把手放在缝的中点；另一方向的缝正好从中间穿过时（四角），挪到被隔开的较长一段的中点，两根把手不叠在一起。
    private func barCenter(_ seam: Seam, among all: [Seam]) -> CGPoint {
        let crossings = all.filter { other in
            other.axis != seam.axis && other.span.contains(seam.position) && seam.span.contains(other.position)
        }.map(\.position).sorted()
        var center = (seam.span.lowerBound + seam.span.upperBound) / 2
        if crossings.contains(where: { abs($0 - center) < 60 }) {
            let cuts = [seam.span.lowerBound] + crossings + [seam.span.upperBound]
            let segments = zip(cuts, cuts.dropFirst()).map { ($0, $1) }
            if let longest = segments.max(by: { ($0.1 - $0.0) < ($1.1 - $1.0) }) { center = (longest.0 + longest.1) / 2 }
        }
        return seam.axis == .vertical ? CGPoint(x: seam.position, y: center) : CGPoint(x: center, y: seam.position)
    }

    // MARK: - 拖一根把手

    private func beginDrag(_ divider: SplitDivider) {
        guard drag == nil, let index = dividers.firstIndex(where: { $0 === divider }), seams.indices.contains(index) else { return }
        let stale = seams[index]
        divider.stopAnimation()
        // 把手可能早就过期了：同一个 App 里关窗、拖走窗口都不发通知。开写之前按现在的窗口重认一遍
        // （收起、侧拉、画中画、收进刘海的都不算；刚松手还在滑的按落点算），还是同一条缝、同几扇窗才拖；
        // 不是就按现在的样子重摆把手，这一下不拖。
        let current = currentSeams()
        show(current)
        guard current.indices.contains(index), Self.sameWindows(current[index], stale),
              abs(current[index].position - stale.position) <= SeamLayout.tolerance else {
            wlog("split-view: bar was stale, windows changed; not dragging")
            return
        }
        let seam = current[index]
        let d = Drag(seam: seam, divider: divider)
        drag = d
        owner.notch.coachUsed(.splitBar)
        timer?.invalidate()
        let ids = (seam.before + seam.after).map(\.id)
        // 找窗口的辅助功能元素要问各个 App：放到后台去问，找到之前拖动只挪把手。
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            var found: [UInt32: AXUIElement] = [:]
            for id in ids { if let element = Self.element(for: id) { found[id] = element } }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.drag === d, found.count == ids.count else { return }
                    // 这几扇窗上一次松手的滑行还没停：先停下再开写，免得它收尾校准时把这次拖好的位置盖回去。
                    // 别的缝（比如另一块屏上）那一批不相干，照样滑完、校准、记撤销。
                    self.settlings.removeAll { Self.shareWindows($0.seam, seam) }
                    self.stopGlides(ids)
                    d.elements = found
                    d.writers = found.mapValues { Self.writer($0) }
                    self.apply(d)
                }
            }
        }
        wlog("split-view: drag begins \(seam.axis) at \(Int(seam.position)) windows=\(ids)")
    }

    private func updateDrag(_ divider: SplitDivider, _ delta: CGVector) {
        guard let d = drag, d.divider === divider else { return }
        let along = d.seam.axis == .vertical ? delta.dx : -delta.dy
        d.proposed = d.seam.position + along
        d.position = SeamLayout.dragged(d.proposed, seam: d.seam, gap: ArrangeGap.points)
        divider.place(at: moved(barCenter(d.seam, among: seams), seam: d.seam, to: d.position), vertical: d.seam.axis == .vertical)
        apply(d)
    }

    private func moved(_ center: CGPoint, seam: Seam, to position: CGFloat) -> CGPoint {
        seam.axis == .vertical ? CGPoint(x: position, y: center.y) : CGPoint(x: center.x, y: position)
    }

    private func apply(_ d: Drag) {
        for (id, frame) in SeamLayout.frames(d.seam, position: d.position, gap: ArrangeGap.points) {
            d.writers[id]?.submit(frame)
        }
    }

    /// velocity：离手速度（Cocoa 坐标，点/秒）。
    private func endDrag(_ divider: SplitDivider, velocity: CGVector) {
        guard let d = drag, d.divider === divider else { return }
        drag = nil
        let along = d.seam.axis == .vertical ? velocity.dx : -velocity.dy
        let landing = SeamLayout.landing(position: d.proposed, velocity: along, seam: d.seam, gap: ArrangeGap.points)
        wlog("split-view: released at \(Int(d.position)) pushed to \(Int(d.proposed)) velocity=\(Int(along)) → \(landing)")
        guard d.ready else {
            divider.place(at: barCenter(d.seam, among: seams), vertical: d.seam.axis == .vertical)
            schedule()
            return
        }
        let group = DispatchGroup()
        for writer in d.writers.values { group.enter(); writer.stop { group.leave() } }
        group.notify(queue: .main) { [weak self] in
            MainActor.assumeIsolated { self?.land(d, landing: landing, velocity: along) }
        }
    }

    private func land(_ d: Drag, landing: SeamLayout.Landing, velocity: CGFloat) {
        // 松手到这里的一瞬间又抓住了同几扇窗的把手、已经在写：这次落点作废，交给新的拖动（它松手时会接回定时刷新）。
        if let current = drag, current.ready, Self.shareWindows(current.seam, d.seam) { return }
        // 不管落到哪、半路退出，都把定时刷新接回来：拖动开始时停掉了它。
        defer { schedule() }
        let gap = ArrangeGap.points
        let now = SeamLayout.frames(d.seam, position: d.position, gap: gap)
        let original = Dictionary((d.seam.before + d.seam.after).map { ($0.id, $0.frame) }, uniquingKeysWith: { a, _ in a })
        switch landing {
        case .position(let position):
            let v = d.seam.axis == .vertical ? CGVector(dx: velocity, dy: 0) : CGVector(dx: 0, dy: velocity)
            slide(d.seam, to: position, from: now, velocity: v, elements: d.elements, original: original, corrected: false)
            // 缝马上按落点重认：松手后马上再抓把手，拖的是落好的这条缝，不是拖之前那条。
            relocate(d.seam)
        case .beforeLeaves, .afterLeaves:
            // 两扇拼满时被推到边上的那一扇让开：进侧拉，靠它被推过去的那一边；另一扇铺满。
            guard let stayWindow = (landing == .beforeLeaves ? d.seam.after : d.seam.before).first,
                  let goWindow = (landing == .beforeLeaves ? d.seam.before : d.seam.after).first,
                  let stay = d.elements[stayWindow.id], let go = d.elements[goWindow.id],
                  let from = now[stayWindow.id] else { return }
            var pid: pid_t = 0
            AXUIElementGetPid(go, &pid)
            let side: SlideOverController.Side = d.seam.axis == .vertical ? (landing == .beforeLeaves ? .left : .right) : .right
            owner.slideOver.enter(go, id: goWindow.id, pid: pid, side: side)
            guard owner.slideOver.isSlideOver(goWindow.id) else {
                // 侧拉没接住（两边都挨着别的屏幕、记不下恢复记录）：两扇都回到拖之前，不留一扇铺满压着另一扇。
                slide(d.seam, to: d.seam.position, from: now, velocity: .zero, elements: d.elements, original: original, corrected: true)
                relocate(d.seam)
                return
            }
            let gestures = owner.gestures
            // 这两扇都换了地方：魔法平铺整批撤回时不再管它们，跟别的窗配的撤销对也作废。
            for id in original.keys { gestures.noteLeft(id) }
            clearPartners(original.keys)
            let fill = ArrangeGap.apply(d.seam.area, in: d.seam.area)
            let before = original[stayWindow.id] ?? from
            let area = d.seam.area
            glide(stayWindow.id, stay, from: from, to: fill, velocity: .zero) { [weak self] report in
                // 撤销记实际落下的外框：按字符格取整的终端差几个点也认得出。
                guard let self, !report.cancelled else { return }
                self.owner.gestures.undoRecords[stayWindow.id] = .init(before: before, after: report.observed,
                                                                        element: stay, layout: .fill, area: area)
            }
            show(currentSeams())
        }
    }

    /// 缝两边的窗口一起滑到 position，记下这一批：都停下后回读（settle）。
    private func slide(_ seam: Seam, to position: CGFloat, from: [UInt32: CGRect], velocity: CGVector,
                       elements: [UInt32: AXUIElement], original: [UInt32: CGRect], corrected: Bool) {
        let s = Settling(seam: seam, position: position, elements: elements, original: original, corrected: corrected)
        settlings.removeAll { Self.shareWindows($0.seam, seam) }
        settlings.append(s)
        for (id, frame) in SeamLayout.frames(seam, position: position, gap: ArrangeGap.points) {
            guard let element = elements[id], let start = from[id] else { continue }
            s.pending += 1
            glide(id, element, from: start, to: frame, velocity: velocity) { [weak self] report in
                s.observed[id] = report.observed
                s.pending -= 1
                if s.pending == 0 { self?.settle(s) }
            }
        }
        if s.pending == 0 { settlings.removeAll { $0 === s } }
    }

    /// 一批滑完：回读实际外框。有的 App 不肯缩到（或放大到）要的大小，就按它实际的边挪一次缝，
    /// 另一边跟着重排，两扇不压在一起；两边都不肯让就回到拖之前。落定之后记撤销：记实际的外框，
    /// 两边各一扇时配成一对，撤销其中一扇另一扇一起回去。
    /// 这时手上正拖着别的缝也照样做：只有同几扇窗的拖动开写时才作废这一批（见 beginDrag）。
    private func settle(_ s: Settling) {
        guard let index = settlings.firstIndex(where: { $0 === s }) else { return }
        settlings.remove(at: index)
        if let d = drag, d.ready, Self.shareWindows(d.seam, s.seam) { return }
        if !s.corrected {
            let fitted = SeamLayout.fitted(s.seam, position: s.position, observed: s.observed, gap: ArrangeGap.points)
                ?? s.seam.position
            if abs(fitted - s.position) > 0.5 {
                wlog("split-view: an app kept its own size, seam \(Int(s.position)) → \(Int(fitted))")
                slide(s.seam, to: fitted, from: s.observed, velocity: .zero, elements: s.elements, original: s.original, corrected: true)
                relocate(s.seam)
                return
            }
        }
        soon()
        // 回到了拖之前的位置：什么都没变，原来的撤销记录照样有效。
        guard abs(s.position - s.seam.position) > 0.5 else { return }
        let gestures = owner.gestures
        for (id, after) in s.observed {
            guard let element = s.elements[id], let before = s.original[id] else { continue }
            gestures.undoRecords[id] = .init(before: before, after: after, element: element, area: s.seam.area)
            // 魔法平铺排过的窗：整批撤回时不再管它，撤销走这次拖动。
            gestures.noteLeft(id)
        }
        clearPartners(s.observed.keys)
        if s.seam.before.count == 1, s.seam.after.count == 1,
           let a = s.seam.before.first?.id, let b = s.seam.after.first?.id,
           gestures.undoRecords[a] != nil, gestures.undoRecords[b] != nil {
            gestures.undoPartners[a] = b
            gestures.undoPartners[b] = a
        }
    }

    /// 这几扇窗跟别的窗配成的撤销对作废：它们已经不在当时那个位置了。
    private func clearPartners<S: Sequence>(_ ids: S) where S.Element == CGWindowID {
        let ids = Set(ids)
        let gestures = owner.gestures
        for (key, value) in gestures.undoPartners where ids.contains(key) || ids.contains(value) {
            gestures.undoPartners.removeValue(forKey: key)
        }
    }

    /// 松手后按落点马上重认一遍缝（还在滑的窗口按终点算），这条缝的把手跟着窗口一起滑到新位置。
    private func relocate(_ seam: Seam) {
        let found = currentSeams()
        if let old = seams.firstIndex(where: { Self.sameWindows($0, seam) }),
           let new = found.firstIndex(where: { Self.sameWindows($0, seam) }), old == new,
           dividers.indices.contains(new), dividers[new] !== drag?.divider, let from = dividers[new].center {
            let divider = dividers[new]
            show(found, except: divider)
            divider.animate(from: from, to: barCenter(found[new], among: found), vertical: seam.axis == .vertical)
        } else {
            show(found)
        }
    }

    /// 同一个方向、两边是同几扇窗：认作同一条缝（位置可以不同）。
    private static func sameWindows(_ a: Seam, _ b: Seam) -> Bool {
        a.axis == b.axis && a.before.map(\.id) == b.before.map(\.id) && a.after.map(\.id) == b.after.map(\.id)
    }

    /// 两条缝牵着至少一扇同样的窗。
    private static func shareWindows(_ a: Seam, _ b: Seam) -> Bool {
        !Set((a.before + a.after).map(\.id)).isDisjoint(with: (b.before + b.after).map(\.id))
    }

    private func glide(_ id: CGWindowID, _ element: AXUIElement, from: CGRect, to: CGRect, velocity: CGVector,
                       completion: @escaping @MainActor (WindowGlide.Report) -> Void) {
        let g = WindowGlide(id: id, element: element, path: .honoringMotion(from: from, to: to, velocity: velocity),
                            after: glides[id]?.glide)
        glides[id] = (g, to)
        g.start { [weak self] report in
            if let self, self.glides[id]?.glide === g { self.glides.removeValue(forKey: id) }
            completion(report)
        }
    }

    /// 停下这几扇窗还没滑完的滑行，等它们真的停手（先一起喊停，再逐个等，只等一帧左右）。
    private func stopGlides(_ ids: [CGWindowID]) {
        let running = ids.compactMap { glides.removeValue(forKey: $0)?.glide }
        running.forEach { $0.cancel() }
        running.forEach { $0.cancelAndWait() }
    }

    nonisolated private static func element(for id: CGWindowID) -> AXUIElement? {
        guard let info = cgWindowInfo(id), let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return nil }
        return appWindows(pid: pid).first { windowID(of: $0) == id }
    }

    nonisolated private static func writer(_ element: AXUIElement) -> LatestValueWriter<CGRect> {
        LatestValueWriter<CGRect>(apply: { frame in
            _ = setAXSize(element, frame.size)
            setAXPosition(element, frame.origin)
        })
    }
}

// MARK: - 中间那根把手

/// 一根小胶囊：竖着分的时候是 6×56 点的竖条，上下分的时候横过来；指针移上去变粗变亮。
/// 面板比胶囊大一圈（28×160），好抓。
@MainActor
final class SplitDivider {
    var onBegin: (() -> Void)?
    var onDrag: ((CGVector) -> Void)?
    var onEnd: ((CGVector) -> Void)?
    private var panel: NSPanel?
    private var animation: FrameTicker?
    static let grab = CGSize(width: 28, height: 160)

    var isVisible: Bool { panel?.isVisible ?? false }
    var frame: NSRect { panel?.frame ?? .zero }
    /// 把手中心（AX 坐标）；没摆出来是 nil。
    var center: CGPoint? {
        guard let panel, panel.isVisible else { return nil }
        let origin = axPosition(fromCocoaFrame: panel.frame)
        return CGPoint(x: origin.x + panel.frame.width / 2, y: origin.y + panel.frame.height / 2)
    }

    /// center：把手中心（AX 坐标）；vertical：竖着的把手（左右分）。
    func show(at center: CGPoint, vertical: Bool) {
        // 还挂在别的桌面上（切过桌面）也算新摆：拿下来重新放到眼前这张桌面。
        let fresh = !isVisible || panel?.isOnActiveSpace == false
        place(at: center, vertical: vertical)
        guard fresh, let panel else { return }
        if panel.isVisible { panel.orderOut(nil) }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.fadeDuration
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        animation?.invalidate(); animation = nil
        panel?.orderOut(nil)
    }

    /// 手又按上来了：停掉上一次松手的吸附动画，免得它和拖动抢位置。
    func stopAnimation() {
        animation?.invalidate(); animation = nil
    }

    func place(at center: CGPoint, vertical: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = vertical ? Self.grab : CGSize(width: Self.grab.height, height: Self.grab.width)
        let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
        panel.setFrame(cocoaFrame(fromAXPosition: rect.origin, size: rect.size), display: false)
        (panel.contentView as? SplitDividerView)?.vertical = vertical
    }

    /// 松手后吸到落点：与 `settle` / `reducedWindow` 解析弹簧同口径（可掉帧不走样）。
    func animate(from: CGPoint, to: CGPoint, vertical: Bool) {
        animation?.invalidate()
        let began = CACurrentMediaTime()
        let token = Motion.reduced ? Motion.Spring.reducedWindow : Motion.Spring.settle
        let omega = token.angularFrequency
        let zeta = token.dampingRatio
        animation = FrameTicker(screen: panel?.screen ?? screenForAXWindow(pos: from, size: Self.grab)) { [weak self] ticker in
            let elapsed = max(0, CACurrentMediaTime() - began)
            let x = FluidMotion.spring(elapsed, from: Double(from.x), to: Double(to.x),
                                       velocity: 0, zeta: zeta, omega: omega)
            let y = FluidMotion.spring(elapsed, from: Double(from.y), to: Double(to.y),
                                       velocity: 0, zeta: zeta, omega: omega)
            self?.place(at: CGPoint(x: x, y: y), vertical: vertical)
            let dx = abs(x - Double(to.x)), dy = abs(y - Double(to.y))
            if elapsed > token.response * 4 || (dx < 0.25 && dy < 0.25) {
                self?.place(at: to, vertical: vertical)
                ticker.invalidate()
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.grab), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // 摆出来时放到眼前这张桌面（不跟着所有桌面走：换桌面时缝不一样，由 refresh 重新摆）。
        panel.collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        panel.animationBehavior = .none
        let view = SplitDividerView(frame: NSRect(origin: .zero, size: Self.grab))
        view.onBegin = { [weak self] in self?.onBegin?() }
        view.onDrag = { [weak self] in self?.onDrag?($0) }
        view.onEnd = { [weak self] in self?.onEnd?($0) }
        panel.contentView = view
        return panel
    }
}

final class SplitDividerView: NSView {
    var vertical = true { didSet { if vertical != oldValue { needsDisplay = true; window?.invalidateCursorRects(for: self) } } }
    var onBegin: (() -> Void)?
    var onDrag: ((CGVector) -> Void)?
    var onEnd: ((CGVector) -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private var down: NSPoint?
    private var dragging = false
    private var samples: [FlickSample] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel(WSL10n.text("split.a11y.resize", zh: "拖动调整两个窗口的大小"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: vertical ? .resizeLeftRight : .resizeUpDown) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // 接得住点击的底：几乎全透明。
        NSColor(white: 0, alpha: 0.005).setFill()
        bounds.fill()
        let active = hovering || pressed
        let long: CGFloat = active ? 72 : 56, thick: CGFloat = active ? 8 : 6
        let size = vertical ? NSSize(width: thick, height: long) : NSSize(width: long, height: thick)
        let rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        let pill = NSBezierPath(roundedRect: rect, xRadius: thick / 2, yRadius: thick / 2)
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor(white: 0, alpha: 0.30)
        shadow.set()
        (dark ? NSColor(white: active ? 0.75 : 0.62, alpha: 0.96) : NSColor(white: active ? 1 : 0.94, alpha: 0.98)).setFill()
        pill.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0, alpha: dark ? 0.35 : 0.16).setStroke()
        pill.lineWidth = 0.5
        pill.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        down = NSEvent.mouseLocation
        dragging = false
        pressed = true
        samples = [FlickSample(time: event.timestamp, point: NSEvent.mouseLocation)]
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down else { return }
        let now = NSEvent.mouseLocation
        if !dragging { dragging = true; onBegin?() }
        samples.append(FlickSample(time: event.timestamp, point: now))
        if samples.count > 12 { samples.removeFirst(samples.count - 12) }
        onDrag?(CGVector(dx: now.x - down.x, dy: now.y - down.y))
    }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        defer { down = nil; dragging = false }
        guard dragging else { return }
        onEnd?(FlickRelease.measure(samples, lift: event.timestamp)?.velocity ?? .zero)
    }
}
