// Original WS2 host-independent coordinator. Call exclusively on MainActor.
// An input lease is NOT an authorization grant.
//
// 层序（docs/design-grammar.md）：1 放行 > 2 你正在做的（手在按）> 3 你主动打开的 > 4 短暂提醒 > 5 持续活动 > 6 什么都没有。
// - 放行不抢手势：第 2 层进行时，放行排队，松手或取消后再出现；这期间别的层一律不进来，提醒只留次区域的点。
// - 放行对第 3 层仍然抢占：那一页挂起，让出后原样回来（由宿主另拿一份租约，进场不重播）。
// - 同层放行排队：先来先出，连同正在显示的那件最多 8 件；只有队首露面，它有结果后下一件才出现。
// - 次区域的点：提醒撞上第 1-3 层时记点；那一层结束、屏上不再有人时点熄，被消耗，不补说。
// - 刘海那一排只有一个主人 notchShelf（M11）：收着的窗口、正在进行的事（播放、编程会话）是同一排，
//   会话的“去看看”详情页也用这个主人露面；不再有独立的 agentSessions 主人。
// - 系统专注模式开着（quiet 为真）：第 4 层提醒也只留次区域的点，不开口；专注结束点熄，不补说。放行（第 1 层）不经这里，照常问。
import Foundation
@MainActor
final class InteractionCoordinator {
    struct Environment { var unlocked: Bool; var displays: Set<WS2.DisplayID> }
    /// 一条提醒。同一个 key 在合并窗口里只换内容；不同 key 累进同一次露面，由展示层合成一句。
    /// priority 决定排队的先后（大的先说）；holdMilliseconds 是这一条自己的停留（0 用 alert.hold）；
    /// expiresAt 过了还没轮到就作废（原队列的 ttl）。展示用的语气、符号、点按仍由宿主按 key 自己带。
    struct AlertItem: Sendable, Equatable {
        let key: String
        let title: String
        var priority: Int = 0
        var holdMilliseconds: UInt64 = 0
        var expiresAt: WS2.Instant? = nil
    }
    /// 同时等着露面的放行，连同正在显示的那件。与 WS2CodexApprovalHost 的 `reviews.count < 8` 一致。
    static let authorizationQueueLimit = 8
    /// 提醒合并窗口：距上一条不超过这么久，算同一次露面。
    static let alertMergeWindow: UInt64 = 600 * WS2.Duration.millisecond
    /// 一次露面最多带几件不同的提醒；更多的不再累进。
    static let alertItemLimit = 8
    /// 一块屏最多排几条没说的提醒；更多的不再排（与放行队列同一条纪律）。
    static let reminderQueueLimit = 8
    /// 提醒申请的结果。宿主据此决定马上说、等下一句说完、还是已经变成了点。
    enum ReminderOutcome { case showing, merged, queued, dotOnly, dropped }

    private struct Active {
        let handle: WS2.LeaseHandle
        let layer: WS2.Layer
        let deadline: WS2.Instant
        /// 这一件出现的时刻与当时的输入序号。确认按各自出现的时刻判断新鲜度。
        let shownAt: WS2.Instant
        let shownAfterSequence: UInt64
    }
    private struct Alert { let first: WS2.Instant; var last: WS2.Instant; let deadline: WS2.Instant; var items: [AlertItem] }
    private let clock: any WS2Clock
    private let environment: () -> Environment
    private let cancel: (WS2.LeaseHandle, WS2.LeaseRevocation) -> Void
    private var source: WS2.TokenSource
    private var active: Active?
    private var inTransition = false
    private var exhausted = false
    private var last = WS2.Instant.zero
    private var ongoing: [WS2.DisplayID:[String]] = [:]
    private var alerts: [WS2.DisplayID:Alert] = [:]
    /// 正在露面的一句还没说完时来的提醒：按优先级排，那句说完接着说（过期的作废）。
    /// 撞上第 1-3 层就整队消耗成点，不补说。
    private var pendingAlerts: [WS2.DisplayID:[AlertItem]] = [:]
    /// 面板本地正在进行的输入（音量亮度两耳、拖放落点）：不占租约，但提醒要让，只留点。
    /// 宿主报开始与结束；这里再带一个期限，宿主忘了收尾也自己过期。
    private var hostInteractions: [WS2.DisplayID:WS2.Instant] = [:]
    private var dots: Set<WS2.DisplayID> = []
    /// 因为系统专注模式留下的点：专注一结束就熄。
    private var quietDots: Set<WS2.DisplayID> = []
    private let quiet: @MainActor () -> Bool
    /// 等着露面的放行，先来先出。不变式：队列非空时一定有人占着（第 1 或第 2 层）。
    private var queue: [WS2.LeaseRequest] = []
    /// 排队的放行轮到时发的租约；转换结束后才通知，宿主拿到时 `isCurrent` 已为真。
    private var grants: [WS2.LeaseHandle] = []
    /// 宿主报告的最新输入序号。放行出现时记下它，之前按下的键不能确认这一件。
    private var inputSequence: UInt64 = 0
    private(set) var epoch: UInt64 = 1
    /// 排队的放行轮到了。只有用 `queueing: true` 申请过的宿主才会收到。
    var onGranted: ((WS2.LeaseHandle) -> Void)?
    init(bootID: UUID, clock: any WS2Clock,
         environment: @escaping () -> Environment,
         quiet: @escaping @MainActor () -> Bool = { false },
         cancel: @escaping (WS2.LeaseHandle, WS2.LeaseRevocation) -> Void) {
        self.clock = clock; self.environment = environment; self.cancel = cancel; self.quiet = quiet
        source = WS2.TokenSource(bootID: bootID, domain: .interaction)
    }
    private func permits(_ r: WS2.LeaseRequest) -> Bool {
        switch (r.ownerID,r.layer) {
        case ("authorization",.authorization), ("conductor",.interaction),
             ("conductor",.opened), ("agentReview",.authorization), ("notchShelf",.opened), ("launchpad",.opened),
             ("windowBrowser",.opened), ("pomodoro",.opened), ("nowPlaying",.opened),
             ("ownedCodex",.opened), ("ownedModelPicker",.opened), ("silent",.opened),
             ("faceEnrollment",.opened): return true
        default: return false
        }
    }
    private func withdraw(_ reason: WS2.LeaseRevocation) {
        guard let old = active else { return }
        // Token is invalid BEFORE synchronous input cancellation. The new token is not published yet.
        active = nil; cancel(old.handle,reason)
    }
    private func issue(_ r: WS2.LeaseRequest, at now: WS2.Instant) -> WS2.LeaseHandle? {
        guard let token = source.next() else { exhausted = true; return nil }
        let h = WS2.LeaseHandle(token: token, ownerID: r.ownerID, display: r.display, environmentEpoch: epoch)
        active = Active(handle: h, layer: r.layer, deadline: r.deadline,
                        shownAt: now, shownAfterSequence: inputSequence)
        // Reminders obscured by an interaction never replay later.
        dots.formUnion(alerts.keys); alerts.removeAll()
        // 还排着没说的提醒也一起消耗：第 1-3 层占了屏，点就是它们的样子。
        pendingAlerts.removeAll()
        return h
    }
    /// 屏上的人走了（松手、有结果、过期、取消、撤屏）：排队的放行按先后接上；没人接，点熄。
    private func vacated(_ now: WS2.Instant) {
        guard active == nil else { return }
        if !queue.isEmpty, !exhausted {
            let env = environment()
            guard env.unlocked else { barrier(.locked); return }
            while active == nil, !exhausted, !queue.isEmpty {
                let r = queue.removeFirst()
                // 等着的时候过了期或屏没了：这件不再出现，轮下一件。
                guard env.displays.contains(r.display), now < r.deadline else { continue }
                if let h = issue(r, at: now) { grants.append(h) }
            }
            if exhausted { queue.removeAll() }
        }
        // 点被那一层消耗：结束时熄，不补说。
        if active == nil { dots.removeAll() }
    }
    private func expire(_ now: WS2.Instant) {
        queue.removeAll { now >= $0.deadline }
        if let a = active, now >= a.deadline { withdraw(.expired); vacated(now) }
        alerts = alerts.filter { now < $0.value.deadline }
        // 露面说完了：排着的提醒按优先级顶上来；过期的作废。
        promoteReminders(now)
        for (display, list) in pendingAlerts {
            pendingAlerts[display] = list.filter { $0.expiresAt.map { now < $0 } ?? true }
        }
        hostInteractions = hostInteractions.filter { now < $0.value }
    }
    /// 露面的位子空了（没人占、也没在说）：排着的最高优先级接上，作废的跳过。
    private func promoteReminders(_ now: WS2.Instant) {
        for (display, list) in pendingAlerts where !list.isEmpty {
            guard alerts[display] == nil,
                  active == nil || active?.handle.display != display,
                  hostInteractions[display].map({ now < $0 }) != true else { continue }
            var rest = list
            var next: AlertItem?
            while let top = rest.first {
                rest.removeFirst()
                if top.expiresAt.map({ now < $0 }) ?? true { next = top; break }
            }
            pendingAlerts[display] = rest
            if let top = next {
                let hold = top.holdMilliseconds > 0 ? top.holdMilliseconds : MotionHold.alertMilliseconds
                alerts[display] = Alert(first: now, last: now,
                                        deadline: now.adding(hold * WS2.Duration.millisecond), items: [top])
            }
        }
    }
    /// 优先级大的先说；同优先级先来先说（Swift 的 sort 不保序，带上到达序号）。
    private static func prioritySorted(_ items: [AlertItem]) -> [AlertItem] {
        items.enumerated().sorted { lhs, rhs in
            lhs.element.priority != rhs.element.priority
                ? lhs.element.priority > rhs.element.priority : lhs.offset < rhs.offset
        }.map(\.element)
    }
    /// 转换结束后再通知轮到的放行，这样宿主收到时能马上用这份租约。
    private func announce() {
        guard !inTransition, !grants.isEmpty else { return }
        let pending = grants; grants.removeAll()
        for h in pending where active?.handle == h { onGranted?(h) }
    }
    private var pendingAuthorizations: Int {
        queue.count + (active?.layer == .authorization ? 1 : 0)
    }
    // Explicit navigation may replace only the exact current opened-page lease.
    // Authorization and active-interaction leases still enforce strict priority.
    // `queueing: false` keeps the pre-grammar answer (`.busy`) for hosts that cannot present later.
    func acquire(_ r: WS2.LeaseRequest, replacing expected: WS2.LeaseHandle? = nil,
                 queueing: Bool = true) -> WS2.LeaseDecision {
        guard !inTransition, !exhausted else { return .unavailable }
        defer { announce() }
        inTransition = true; defer { inTransition = false }
        let now = clock.now(), env = environment()
        guard now >= last else { return .unavailable }; last = now
        guard env.unlocked else { barrier(.locked); return .unavailable }
        let entryEpoch = epoch
        expire(now)
        guard epoch == entryEpoch, !exhausted else { return .unavailable }
        if let expected, active?.handle != expected { return .unavailable }
        guard permits(r), env.displays.contains(r.display), r.requestedAt <= now,
              r.deadline > now else { return .unavailable }
        if let old = active {
            if r.layer == .authorization, old.layer <= .interaction {
                // 放行不抢手势，也不换掉正在显示的放行：排到后面，轮到时再出现。
                guard queueing, pendingAuthorizations < Self.authorizationQueueLimit else { return .busy }
                queue.append(r)
                return .queued(position: queue.count)
            }
            let explicitPageSwitch = expected == old.handle && old.layer == .opened && r.layer == .opened
            guard r.layer < old.layer || explicitPageSwitch else { return .busy }
            // 更高的层把已打开的那一页挂起。换页仍是抢占：旧页不回来。
            withdraw(explicitPageSwitch ? .preempted : .suspended)
            // Synchronous cancellation can disable/lock the app. Never lose that barrier.
            guard epoch == entryEpoch, !exhausted else { return .unavailable }
        }
        let refreshed = environment(), sampled = clock.now()
        guard refreshed.unlocked, refreshed.displays.contains(r.display), sampled >= now,
              sampled < r.deadline else { barrier(.locked); return .unavailable }
        guard let h = issue(r, at: sampled) else { return .unavailable }
        return .acquired(h)
    }
    func isCurrent(_ lease: WS2.LeaseHandle) -> Bool {
        guard !inTransition, !exhausted else { return false }
        let now = clock.now(), env = environment()
        return now >= last && env.unlocked && env.displays.contains(lease.display) &&
            active?.handle == lease && active.map { now < $0.deadline } == true
    }
    /// 有结果（允许、不允许）、取消、松手：都走这里。排队的下一件随后出现。
    func release(_ lease: WS2.LeaseHandle, at now: WS2.Instant) {
        guard !inTransition, now >= last, active?.handle == lease else { return }
        defer { announce() }
        inTransition = true; defer { inTransition = false }; last = now
        withdraw(.released)
        vacated(now)
    }
    private func barrier(_ reason: WS2.LeaseRevocation) {
        if epoch == .max { exhausted = true } else { epoch += 1 }
        ongoing.removeAll(); alerts.removeAll(); dots.removeAll(); quietDots.removeAll(); queue.removeAll(); grants.removeAll()
        pendingAlerts.removeAll(); hostInteractions.removeAll()
        withdraw(reason)
    }
    func invalidate(_ reason: WS2.LeaseRevocation, at now: WS2.Instant) {
        // Safety barriers must still invalidate when a broken clock goes backwards.
        if inTransition {
            last = max(now,last); barrier(reason); return
        }
        inTransition = true; defer { inTransition = false }; last = max(now,last)
        barrier(reason)
    }
    func removeDisplay(_ id: WS2.DisplayID, at now: WS2.Instant) {
        // A display-change callback during replacement aborts the whole transition.
        if inTransition { invalidate(.displayRemoved, at: now); return }
        defer { announce() }
        inTransition = true; defer { inTransition = false }; last = max(now,last)
        ongoing[id] = nil; alerts[id] = nil; dots.remove(id); quietDots.remove(id)
        pendingAlerts[id] = nil; hostInteractions[id] = nil
        queue.removeAll { $0.display == id }
        if active?.handle.display == id { withdraw(.displayRemoved); vacated(last) }
    }
    func publishOngoing(_ ids: [String], on display: WS2.DisplayID) {
        guard !inTransition, environment().unlocked, environment().displays.contains(display) else { return }
        var seen = Set<String>()
        ongoing[display] = Array(ids.filter { !$0.isEmpty && $0.utf8.count <= 512 && seen.insert($0).inserted }.prefix(3))
    }
    func remind(on display: WS2.DisplayID, at now: WS2.Instant) {
        remind(AlertItem(key: "", title: ""), on: display, at: now)
    }
    func remind(_ item: AlertItem, on display: WS2.DisplayID, at now: WS2.Instant,
                holdMilliseconds: UInt64 = 0) {
        guard !inTransition, now >= last, environment().unlocked, environment().displays.contains(display),
              item.key.utf8.count <= 512, item.title.utf8.count <= 4096 else { return }
        last = now
        // 第 1-3 层占着（包括手在按的时候、面板本地的两耳与落点）：只留次区域的点。
        if active != nil || hostInteractions[display].map({ now < $0 }) == true {
            dots.insert(display); return
        }
        if quiet() { quietDots.insert(display); return }
        if var a = alerts[display], now < a.deadline,
           now.elapsed(since: a.last) <= Self.alertMergeWindow {
            // 合并刷新不延长第一次提醒的 `alert.hold` 截止。同 key 只换内容，不同 key 累进（优先级大的在前面）。
            a.last = now
            if let i = a.items.firstIndex(where: { $0.key == item.key }) {
                a.items[i] = item
            } else if a.items.count < Self.alertItemLimit {
                a.items.append(item)
                a.items = Self.prioritySorted(a.items)
            }
            alerts[display] = a
        } else {
            let hold = holdMilliseconds > 0 ? holdMilliseconds : MotionHold.alertMilliseconds
            alerts[display] = Alert(first: now, last: now,
                                    deadline: now.adding(hold * WS2.Duration.millisecond),
                                    items: [item])
        }
    }

    /// 队列并进第 4 层后的唯一入口：露面位子空着就说、正在说且在合并窗口里就并进那一次露面、
    /// 正在说但过了窗口就按优先级排队等下一句、撞上第 1-3 层（或面板本地输入）就变成点并消耗。
    /// 展示属性（语气、符号、点按）宿主按 key 自己带；这里只裁先后与准入。
    func admit(_ item: AlertItem, on display: WS2.DisplayID, at now: WS2.Instant) -> ReminderOutcome {
        guard !inTransition, !exhausted, now >= last, environment().unlocked,
              environment().displays.contains(display),
              item.key.utf8.count <= 512, item.title.utf8.count <= 4096 else { return .dropped }
        last = now
        if active != nil || hostInteractions[display].map({ now < $0 }) == true {
            dots.insert(display); pendingAlerts[display] = nil
            return .dotOnly
        }
        if quiet() { quietDots.insert(display); return .dotOnly }
        promoteReminders(now)
        if var a = alerts[display], now < a.deadline {
            if now.elapsed(since: a.last) <= Self.alertMergeWindow {
                a.last = now
                if let i = a.items.firstIndex(where: { $0.key == item.key }) {
                    a.items[i] = item
                } else if a.items.count < Self.alertItemLimit {
                    a.items.append(item)
                    a.items = Self.prioritySorted(a.items)
                }
                alerts[display] = a
                return .merged
            }
            var list = pendingAlerts[display, default: []]
            list.removeAll { $0.key == item.key }
            list.append(item)
            if list.count > Self.reminderQueueLimit { list.removeLast() }
            pendingAlerts[display] = Self.prioritySorted(list)
            return .queued
        }
        let hold = item.holdMilliseconds > 0 ? item.holdMilliseconds : MotionHold.alertMilliseconds
        alerts[display] = Alert(first: now, last: now,
                                deadline: now.adding(hold * WS2.Duration.millisecond), items: [item])
        return .showing
    }

    /// 这块屏此刻该说的那一句（露面的队首）；没在露面时为 nil。宿主渲染完一条、露面结束时来取下一条。
    func currentAlertItem(on display: WS2.DisplayID, at now: WS2.Instant) -> AlertItem? {
        guard !inTransition, environment().unlocked else { return nil }
        promoteReminders(now)
        guard let a = alerts[display], now < a.deadline, let first = a.items.first else { return nil }
        return first
    }
    /// 这块屏还有没有没说完、没说出的提醒（插电那一下撞上就不出）。
    func hasReminderWork(on display: WS2.DisplayID, at now: WS2.Instant) -> Bool {
        if let a = alerts[display], now < a.deadline { return true }
        if let list = pendingAlerts[display], list.contains(where: { $0.expiresAt.map { now < $0 } ?? true }) { return true }
        return false
    }
    /// 面板本地输入开始（音量亮度、拖放落点）：不占租约，但提醒要让。deadline 是兜底，宿主收尾也要报；
    /// 同一块屏再报一次就是「还在进行」，期限重新算。
    func hostInteraction(on display: WS2.DisplayID, at now: WS2.Instant, deadline: WS2.Instant) {
        guard environment().displays.contains(display) else { return }
        hostInteractions[display] = deadline
    }
    func endHostInteraction(on display: WS2.DisplayID) {
        hostInteractions[display] = nil
    }
    /// 锁屏、睡眠期间宿主收掉排着与露面的提醒（解锁后不补播）。
    func clearReminders() {
        alerts.removeAll(); pendingAlerts.removeAll()
    }
    /// 这块屏正在露面的提醒，按先来后到。展示层据此合成一句；没在露面时为空。
    func alertItems(on display: WS2.DisplayID, at now: WS2.Instant) -> [AlertItem] {
        guard !inTransition, environment().unlocked, let a = alerts[display], now < a.deadline else { return [] }
        return a.items
    }
    func snapshots(at now: WS2.Instant) -> [WS2.VisibilitySnapshot] {
        guard !inTransition else { return [] }
        defer { announce() }
        inTransition = true; defer { inTransition = false }
        guard now >= last else { return [] }; last = now
        let env = environment()
        if !quietDots.isEmpty, !quiet() { quietDots.removeAll() }
        if !env.unlocked { barrier(.locked) }
        if let h = active?.handle, !env.displays.contains(h.display) { withdraw(.displayRemoved); vacated(now) }
        let sampledEpoch = epoch
        expire(now)
        guard epoch == sampledEpoch else { return [] }
        return env.displays.sorted().map { d in
            let a = active?.handle.display == d ? active : nil
            let ids = env.unlocked ? ongoing[d,default:[]] : []
            let layer: WS2.Layer = a?.layer ?? (alerts[d] != nil ? .alert : ids.isEmpty ? .idle : .ongoing)
            return .init(display:d,environmentEpoch:epoch,layer:layer,lease:a?.handle,
                         ongoingIDs:ids,hasSecondaryDot:env.unlocked && (dots.contains(d) || quietDots.contains(d)))
        }
    }
    /// 宿主报告输入事件的序号（单调）。放行出现时记下当时的序号。
    func noteInput(sequence: UInt64) {
        inputSequence = max(inputSequence, sequence)
    }
    /// 当前这件放行出现的时刻与当时的输入序号；不是当前租约时为 nil。
    func presentation(of lease: WS2.LeaseHandle) -> (shownAt: WS2.Instant, shownAfterSequence: UInt64)? {
        guard let a = active, a.handle == lease else { return nil }
        return (a.shownAt, a.shownAfterSequence)
    }
    /// 按这一件自己出现的时刻判断：排在后面的放行，不能被前一件期间按下的键确认。
    func confirmationIsFresh(lease: WS2.LeaseHandle, beganAt: WS2.Instant, sequence: UInt64) -> Bool {
        guard let shown = presentation(of: lease) else { return false }
        return confirmationIsFresh(lease: lease, beganAt: beganAt, sequence: sequence,
                                   shownAt: shown.shownAt, shownAfterSequence: shown.shownAfterSequence)
    }
    func confirmationIsFresh(lease: WS2.LeaseHandle, beganAt: WS2.Instant, sequence: UInt64,
                             shownAt: WS2.Instant, shownAfterSequence: UInt64) -> Bool {
        isCurrent(lease) && lease.ownerID == "authorization" && beganAt >= shownAt &&
            beganAt <= clock.now() && sequence > shownAfterSequence
    }
}
