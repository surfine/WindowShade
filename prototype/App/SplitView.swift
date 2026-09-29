// 分屏（iPadOS 的 Split View）：两扇窗口刚好左右拼满一块屏（半屏 + 半屏、魔法平铺的 6:4……），
// 中间出现一根小竖条。拖它，两扇一起变宽变窄；松手按速度吸到 ⅓、½、⅔；推到屏幕边，那一扇让开进侧拉，另一扇铺满。
// 竖着放的屏幕上下拼满时是一根横条。Apple 支持文档 125309：“拖中间那条来调整两个窗口的大小”。
// 不止两扇：四角、三分、网格、魔法平铺带侧栏，排好的窗口之间每条缝都有一根把手，拖它这条缝两边的窗口一起变
// （Swish 的“拖分隔线同时调多扇”）；只有两扇拼满时推到边上才让一扇进侧拉。
//
// 什么时候看：切了 App、排了窗口、换了桌面时立刻看一次；平时两秒看一次，有把手时半秒一次
// （只问 WindowServer 一张窗口表，不问各个 App）。认缝的规则见 Core/SeamLayout.swift。
// 不认：收起的、侧拉的、画中画的、收进刘海的、卷轴里的窗口；有别的窗口浮在这些窗口前面时把手收掉。
// 松手后窗口还在滑的那一会儿，按落点认缝；滑完回读实际外框，App 不肯缩放时按它实际的边再挪一次缝。

import Cocoa

@MainActor
final class SplitViewController {
    nonisolated static let enabledKey = "SplitView.divider"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    unowned let owner: AppDelegate
    private var dividers: [SplitDivider] = []
    private var seams: [Seam] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    /// 拖着一根把手：起点那条缝、缝两边窗口的辅助功能元素和各自写外框的那条链、缝现在在哪。
    private var drag: Drag?
    private final class Drag {
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
    var dividerFramesForProbe: [NSRect] { dividers.prefix(seams.count).filter(\.isVisible).map(\.frame) }

    /// 探针用：按住第 index 根把手拖到 position（沿缝的法向），以 velocity（点/秒）松手。
    func dragForProbe(_ index: Int = 0, to position: CGFloat, velocity: CGFloat) async {
        guard seams.indices.contains(index) else { return }
        let seam = seams[index], divider = dividers[index]
        beginDrag(divider)
        for _ in 0..<40 where drag?.ready != true { try? await Task.sleep(nanoseconds: 25_000_000) }
        let along = position - seam.position
        updateDrag(divider, seam.axis == .vertical ? CGVector(dx: along, dy: 0) : CGVector(dx: 0, dy: -along))
        try? await Task.sleep(nanoseconds: 150_000_000)
        endDrag(divider, velocity: seam.axis == .vertical ? CGVector(dx: velocity, dy: 0) : CGVector(dx: 0, dy: -velocity))
    }

    func start() {
        guard observers.isEmpty else { return }
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
        let interval: TimeInterval = seams.isEmpty ? 2 : 0.5
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        guard drag == nil else { return }
        show(currentSeams())
    }

    private func currentSeams() -> [Seam] {
        Self.isEnabled && AXIsProcessTrusted() ? findSeams() : []
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

    /// 每块屏上排好的窗口之间的缝。
    private func findSeams() -> [Seam] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let me = getpid()
        let gestures = owner.gestures
        var windows: [SplitWindow] = []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  var bounds = cgWindowBounds(info) else { continue }
            // 松手后还在滑的窗口按终点算：滑到一半两边对不上，把手不该跟着消失又出现。
            if let target = glides[id]?.to { bounds = target }
            guard bounds.width > 80, bounds.height > 60 else { continue }
            windows.append(SplitWindow(id: id, frame: bounds))
        }
        var result: [Seam] = []
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
            for seam in SeamLayout.seams(frontToBack: windows, area: area, gap: ArrangeGap.points) {
                let ids = (seam.before + seam.after).map(\.id)
                if ids.contains(where: { owner.shaded[$0] != nil || owner.slideOver.isSlideOver($0) || owner.pip.isInPictureInPicture($0)
                    || owner.notch.isTucked($0) || gestures.strips.contains($0) }) {
                    continue
                }
                result.append(seam)
            }
        }
        return result
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
        DispatchQueue.global(qos: .userInteractive).async {
            var found: [UInt32: AXUIElement] = [:]
            for id in ids { if let element = Self.element(for: id) { found[id] = element } }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
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
    private var animation: Timer?
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
            context.duration = 0.18
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

    /// 松手后吸到落点：和窗口一起走过去（缓出）。
    func animate(from: CGPoint, to: CGPoint, vertical: Bool) {
        animation?.invalidate()
        let began = CACurrentMediaTime()
        let duration = Motion.reduced ? 0.12 : 0.32
        let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                let p = min(1, (CACurrentMediaTime() - began) / duration)
                let eased = CGFloat(1 - pow(1 - p, 3))
                self?.place(at: CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased), vertical: vertical)
                if p >= 1 { timer.invalidate() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        animation = t
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
        setAccessibilityLabel("拖动调整两个窗口的大小")
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
