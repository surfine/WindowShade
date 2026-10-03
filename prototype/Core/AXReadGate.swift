import Foundation

/// 跨 App 的 AX 读取名额。时间由调用方传入。
/// 每次读取的身份由调用方给，这里沿用已有的 stamp，不另造代次。
/// 超时只让那一次的结果作废，名额要等这次调用真正返回才放开。
/// `resultLifetime` 与既有 fold 回调的 2 秒围栏相同，是工程参数，不是耗时承诺。
struct AXReadGate<App: Hashable & Sendable, Identity: Equatable & Sendable>: Sendable {
    struct Ticket: Equatable, Sendable {
        let app: App
        let identity: Identity
        let admittedAt: TimeInterval
    }

    enum Reason: Equatable, Sendable {
        case resultVoided
        case unknownTicket
    }

    enum Completion: Equatable, Sendable {
        case apply(Ticket)
        case discard(Ticket, Reason)
        case absent
    }

    static var defaultBudget: Int { 4 }
    static var resultLifetime: TimeInterval { 2 }

    private(set) var budget: Int
    private(set) var enabled = true
    private var inFlight: [App: Ticket] = [:]
    private var voided: Set<App> = []
    private var queue: [App] = []

    init(budget: Int = AXReadGate<App, Identity>.defaultBudget) {
        self.budget = budget > 0 ? budget : 0
    }

    var occupiedCount: Int { inFlight.count }

    func isOccupied(_ app: App) -> Bool { inFlight[app] != nil }

    mutating func setEnabled(_ on: Bool) {
        enabled = on
        if !on { queue.removeAll() }
    }

    /// 用当前想读的 App 替换等待队列。已经在途的不重复排队，关掉期间也不把旧名单攒下来。
    mutating func replaceWanted(_ apps: some Sequence<App>) {
        var seen: Set<App> = []
        var wanted: [App] = []
        for app in apps where seen.insert(app).inserted {
            wanted.append(app)
        }
        let wantedSet = Set(wanted)
        queue.removeAll { !wantedSet.contains($0) || inFlight[$0] != nil }
        for app in wanted where inFlight[app] == nil && !queue.contains(app) {
            queue.append(app)
        }
    }

    /// `identity` 返回空时这次不发，该 App 仍留在队列里，也不占用名额。
    mutating func admit(now: TimeInterval, identity: (App) -> Identity?) -> [Ticket] {
        guard enabled, now.isFinite, budget > 0 else { return [] }
        var issued: [Ticket] = []
        var deferred: [App] = []
        while inFlight.count < budget, !queue.isEmpty {
            let app = queue.removeFirst()
            if inFlight[app] != nil { continue }
            guard let id = identity(app) else {
                deferred.append(app)
                continue
            }
            let ticket = Ticket(app: app, identity: id, admittedAt: now)
            inFlight[app] = ticket
            issued.append(ticket)
        }
        if !deferred.isEmpty {
            queue.insert(contentsOf: deferred, at: 0)
        }
        return issued
    }

    /// 超过时限的结果不再采用，但名额继续算占用，直到 `complete`。
    mutating func voidExpired(now: TimeInterval, lifetime: TimeInterval) -> [Ticket] {
        guard now.isFinite, lifetime.isFinite, lifetime > 0 else { return [] }
        var newly: [Ticket] = []
        for (app, ticket) in inFlight where !voided.contains(app) {
            guard now >= ticket.admittedAt, now - ticket.admittedAt >= lifetime else { continue }
            voided.insert(app)
            newly.append(ticket)
        }
        return newly
    }

    mutating func complete(_ ticket: Ticket) -> Completion {
        guard let current = inFlight[ticket.app] else { return .absent }
        guard current == ticket else { return .discard(ticket, .unknownTicket) }
        inFlight.removeValue(forKey: ticket.app)
        let resultVoided = voided.remove(ticket.app) != nil
        if resultVoided { return .discard(ticket, .resultVoided) }
        return .apply(ticket)
    }
}
