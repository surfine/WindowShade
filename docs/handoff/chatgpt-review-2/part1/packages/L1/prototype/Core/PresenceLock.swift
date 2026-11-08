// WindowShade 2 · 原创在场 reducer。这里没有密码，也不产生解锁授权。
import Foundation

struct PresenceLock: Sendable {
    enum Device: String, Hashable, Sendable { case phone, watch }
    enum Status: Equatable, Sendable { case unknown, connecting, present, away }
    enum LockState: Sendable { case unknown, unlocked, locked }
    enum Reason: Equatable, Sendable { case devices, camera }
    enum Phase: Equatable, Sendable {
        case idle, grace(deadline: WS2.Instant, reason: Reason), countdown(deadline: WS2.Instant, reason: Reason)
        case prepared(WS2.Token), awaitingReceipt(WS2.Token), locked
    }
    struct Configuration: Sendable {
        var watchRequired = false
        var cameraEnabled = false
        var returnEnabled = false
        var faceEnabled = true // false 时不开放仅手机解锁；Aaron 尚未作这个决定。
        var returnThresholdDBm: Double = -60 // 源规格；不是距离测量。
    }
    enum Event: Sendable {
        case enable, disable, sleep, wake, userInput, sensorUnavailable
        case connected(Device, generation: UInt64)
        case disconnected(Device, generation: UInt64)
        case readStarted(Device, generation: UInt64, request: UInt64)
        case readSucceeded(Device, generation: UInt64, request: UInt64)
        case cameraFrame(personPresent: Bool, healthy: Bool)
        case rssi(generation: UInt64, dbm: Double)
        case systemLocked, systemUnlocked, lockStateUnknown
        /// 只有实际 OS 锁态检查成功并且仍对得上本次请求，桥接器才能发。
        case lockConfirmed(WS2.Token), lockFailed(WS2.Token)
        /// 在同一批次的取消事件全部处理后，再送 commit；不能在 prepare 回调里同步重入。
        case commitLock(WS2.Token)
        case returnAttemptFinished(WS2.Token)
        case tick
    }
    enum Effect: Equatable, Sendable {
        case countdown(Int, Reason), cancelled, prepareCommit(WS2.Token)
        case tuckPrivate(WS2.Token), pauseKnownMedia(WS2.Token), requestLock(WS2.Token)
        /// 只能请求现有身份/授权流程。不能在此效果里读密码或合成解锁按键。
        case requestReturnAuthorization(lock: WS2.Token, attempt: WS2.Token)
        case resumeOwnedMedia(WS2.Token), fault(WS2.Fault)
    }
    private struct Probe: Sendable { let id: UInt64; let deadline: WS2.Instant }
    private struct Link: Sendable {
        var generation: UInt64 = 0; var status = Status.unknown
        var probe: Probe?; var lastRequest: UInt64 = 0; var replyAt: WS2.Instant?
    }
    static let grace: UInt64 = 1_500 * WS2.Duration.millisecond
    static let countdown: UInt64 = 10 * WS2.Duration.second
    static let responseTimeout: UInt64 = 2 * WS2.Duration.second
    static let inputCooldown: UInt64 = 60 * WS2.Duration.second
    static let cameraIdle: UInt64 = 30 * WS2.Duration.second
    static let cameraMissing: UInt64 = 10 * WS2.Duration.second // 推荐，需由主模型冻结。
    static let cameraFreshness: UInt64 = 2 * WS2.Duration.second
    static let returnHold: UInt64 = 2 * WS2.Duration.second
    static let rssiFreshness: UInt64 = 1 * WS2.Duration.second
    static let lockReceiptTimeout: UInt64 = 3 * WS2.Duration.second // 推荐，超时不认作自己锁定。
    private(set) var enabled = false
    private(set) var phase = Phase.idle
    private(set) var lockState = LockState.unknown
    private(set) var returnAttempts = 0
    private(set) var ownedLock: WS2.Token?
    private(set) var configuration: Configuration
    private var links: [Device: Link] = [.phone: Link(), .watch: Link()]
    private var time = WS2.TimeGate()
    private var tokens: WS2.TokenSource
    private var sleeping = false
    private var lastInput = WS2.Instant.zero
    private var cooldownUntil: WS2.Instant?
    private var cameraArmed = false
    private var cameraMissingSince: WS2.Instant?
    private var cameraLastFrame: WS2.Instant?
    private var phoneGenerationAtLock: UInt64 = 0
    private var lockedAt: WS2.Instant?
    private var receiptDeadline: WS2.Instant?
    private var nearSince: WS2.Instant?
    private var lastRSSI: WS2.Instant?
    private var pendingReturn: WS2.Token?

    init(configuration: Configuration = Configuration(), bootID: UUID) {
        self.configuration = configuration
        tokens = WS2.TokenSource(bootID: bootID, domain: .presenceLock)
    }
    func status(of device: Device) -> Status { links[device]?.status ?? .unknown }
    /// 批次内部先取消/环境，再设备事实，再期限/提交。不同批次不承诺能撤回已执行的 OS 动作。
    mutating func handleBatch(_ events: [Event], at now: WS2.Instant) -> [Effect] {
        let sorted = events.enumerated().sorted {
            let a = priority($0.element), b = priority($1.element)
            return a == b ? $0.offset < $1.offset : a < b
        }
        return sorted.flatMap { handle($0.element, at: now) }
    }
    mutating func handle(_ event: Event, at now: WS2.Instant) -> [Effect] {
        guard time.accept(now) else { return [.fault(.timeReversed)] }
        var effects: [Effect] = []
        var allowReturn = false
        switch event {
        case .enable: enabled = true
        case .disable:
            enabled = false; effects += cancelCountdown(); forgetSignals(); ownedLock = nil; pendingReturn = nil
            receiptDeadline = nil; phase = lockState == .locked ? .locked : .idle
        case .sleep:
            sleeping = true; effects += cancelCountdown(); forgetSignals(); ownedLock = nil; pendingReturn = nil; lockState = .unknown
        case .wake:
            sleeping = false; lockState = .unknown; forgetSignals()
        case .lockStateUnknown:
            lockState = .unknown; effects += cancelCountdown(); ownedLock = nil; pendingReturn = nil
        case .sensorUnavailable:
            effects += cancelCountdown(); forgetSignals()
        case .userInput:
            lastInput = now
            if cooldownUntil != nil { cooldownUntil = now.adding(Self.inputCooldown) }
            switch phase {
            case .grace, .countdown, .prepared:
                cooldownUntil = now.adding(Self.inputCooldown); effects += cancelCountdown()
            default: break
            }
            cameraMissingSince = nil
        case .connected(let device, let generation):
            guard enabled, !sleeping, generation > links[device, default: Link()].generation else { return [] }
            links[device] = Link(generation: generation, status: .connecting)
            effects += cancelCountdown(); nearSince = nil; lastRSSI = nil
        case .disconnected(let device, let generation):
            guard enabled, !sleeping, generation == links[device, default: Link()].generation,
                  generation > 0, links[device]?.status != .unknown else { return [] }
            links[device]?.status = .away; links[device]?.probe = nil; links[device]?.replyAt = nil
            if device == .phone { nearSince = nil; lastRSSI = nil }
        case .readStarted(let device, let generation, let request):
            guard enabled, !sleeping, var link = links[device], link.generation == generation,
                  link.status == .connecting || link.status == .present,
                  request > link.lastRequest, link.probe == nil else { return [] }
            link.lastRequest = request
            link.probe = Probe(id: request, deadline: now.adding(Self.responseTimeout))
            links[device] = link
        case .readSucceeded(let device, let generation, let request):
            guard enabled, !sleeping, var link = links[device], link.generation == generation,
                  let probe = link.probe, probe.id == request, now < probe.deadline else { break }
            link.probe = nil; link.replyAt = now; link.status = .present; links[device] = link
            effects += cancelCountdown()
        case .cameraFrame(let present, let healthy):
            guard enabled, !sleeping, configuration.cameraEnabled, lockState == .unlocked else { break }
            if !healthy {
                cameraArmed = false; cameraMissingSince = nil; cameraLastFrame = nil
            } else {
                if let last = cameraLastFrame, now.elapsed(since: last) >= Self.cameraFreshness { cameraMissingSince = nil }
                cameraLastFrame = now
                if present { cameraArmed = true; cameraMissingSince = nil }
                else if cameraArmed && now.elapsed(since: lastInput) >= Self.cameraIdle {
                    if cameraMissingSince == nil { cameraMissingSince = now }
                }
            }
        case .systemLocked:
            // 非本次 requestLock 的明确回执，包括手动锁；不借用之前的自动锁归属。
            phase = .locked; lockState = .locked; ownedLock = nil; receiptDeadline = nil
            pendingReturn = nil; nearSince = nil; lastRSSI = nil
        case .systemUnlocked:
            guard lockState != .unlocked else { return [] }
            let wasLocked = lockState == .locked
            if let owner = ownedLock { effects.append(.resumeOwnedMedia(owner)) }
            phase = .idle; lockState = .unlocked; ownedLock = nil; pendingReturn = nil
            receiptDeadline = nil; returnAttempts = 0; nearSince = nil; lastRSSI = nil
            cooldownUntil = wasLocked ? now.adding(Self.inputCooldown) : nil
        case .lockConfirmed(let token):
            guard enabled, !sleeping, case .awaitingReceipt(let expected) = phase, expected == token,
                  let deadline = receiptDeadline, now < deadline else { return [] }
            phase = .locked; lockState = .locked; ownedLock = token; lockedAt = now
            phoneGenerationAtLock = links[.phone, default: Link()].generation
            returnAttempts = 0; pendingReturn = nil; nearSince = nil; lastRSSI = nil; receiptDeadline = nil
        case .lockFailed(let token):
            guard case .awaitingReceipt(let expected) = phase, token == expected else { return [] }
            phase = .idle; receiptDeadline = nil; cooldownUntil = now.adding(Self.inputCooldown)
            effects.append(.fault(.missingDependency))
        case .commitLock(let token):
            guard enabled, !sleeping, lockState == .unlocked, case .prepared(let expected) = phase,
                  token == expected, absence(at: now) != nil else { return [] }
            phase = .awaitingReceipt(token); receiptDeadline = now.adding(Self.lockReceiptTimeout)
            effects += [.tuckPrivate(token), .pauseKnownMedia(token), .requestLock(token)]
        case .rssi(let generation, let dbm):
            if links[.phone]?.generation == generation && (!dbm.isFinite || !(-127 ... 20).contains(dbm)) {
                nearSince = nil; lastRSSI = nil
                break
            }
            guard enabled, !sleeping, lockState == .locked, ownedLock != nil,
                  configuration.returnEnabled, configuration.faceEnabled,
                  configuration.returnThresholdDBm.isFinite, (-100 ... -20).contains(configuration.returnThresholdDBm),
                  dbm.isFinite, (-127 ... 20).contains(dbm),
                  let phone = links[.phone], phone.generation == generation, generation > phoneGenerationAtLock,
                  phone.status == .present, let reply = phone.replyAt, let lockedAt, reply >= lockedAt else { break }
            if dbm <= configuration.returnThresholdDBm {
                nearSince = nil; lastRSSI = nil
            } else {
                if lastRSSI.map({ now.elapsed(since: $0) > Self.rssiFreshness }) ?? true { nearSince = now }
                lastRSSI = now; allowReturn = true
            }
        case .returnAttemptFinished(let token):
            guard pendingReturn == token else { return [] }
            pendingReturn = nil; nearSince = nil; lastRSSI = nil
        case .tick: break
        }
        effects += reconcile(at: now, allowReturn: allowReturn)
        return effects
    }
    var nextWake: WS2.Instant? {
        var deadlines = links.values.compactMap { $0.probe?.deadline }
        switch phase {
        case .grace(let deadline, _): deadlines.append(deadline)
        case .countdown(let deadline, _):
            let now = time.last ?? .zero
            let remaining = deadline.elapsed(since: now)
            let step = remaining == 0 ? 0 : ((remaining - 1) % WS2.Duration.second) + 1
            deadlines.append(now.adding(step))
        default: break
        }
        if let receiptDeadline { deadlines.append(receiptDeadline) }
        if let cooldownUntil, cooldownUntil > (time.last ?? .zero) { deadlines.append(cooldownUntil) }
        // 摄像头和 RSSI 由真实回调推进；没有帧/样本不能由 timer 编造“连续”。
        return deadlines.min()
    }
    private mutating func reconcile(at now: WS2.Instant, allowReturn: Bool) -> [Effect] {
        guard enabled, !sleeping else { return [] }
        var effects: [Effect] = []
        for device in [Device.phone, .watch] {
            if let probe = links[device]?.probe, now >= probe.deadline {
                links[device]?.probe = nil; links[device]?.status = .away; links[device]?.replyAt = nil
            }
        }
        if case .awaitingReceipt = phase, let receiptDeadline, now >= receiptDeadline {
            self.receiptDeadline = nil; phase = .idle; lockState = .unknown
            effects.append(.fault(.missingDependency)) // 不谎报已锁，更不能取得自动解锁归属。
        }
        if allowReturn, lockState == .locked, let owner = ownedLock, configuration.returnEnabled, configuration.faceEnabled,
           returnAttempts < 3, pendingReturn == nil, let since = nearSince, let last = lastRSSI,
           now.elapsed(since: since) >= Self.returnHold, now.elapsed(since: last) <= Self.rssiFreshness,
           links[.phone]?.status == .present, let attempt = tokens.next() {
            returnAttempts += 1; pendingReturn = attempt; nearSince = nil; lastRSSI = nil
            effects.append(.requestReturnAuthorization(lock: owner, attempt: attempt))
        }
        guard lockState == .unlocked else { return effects }
        guard let reason = absence(at: now) else { effects += cancelCountdown(); return effects }
        switch phase {
        case .idle:
            phase = .grace(deadline: now.adding(Self.grace), reason: reason)
        case .grace(let deadline, let oldReason):
            if oldReason != reason { phase = .grace(deadline: now.adding(Self.grace), reason: reason) }
            else if now >= deadline {
                let end = deadline.adding(Self.countdown)
                if now >= end { effects += prepare() }
                else { phase = .countdown(deadline: end, reason: reason); effects.append(.countdown(seconds(to: end, from: now), reason)) }
            }
        case .countdown(let deadline, let oldReason):
            if oldReason != reason { effects += cancelCountdown(); phase = .grace(deadline: now.adding(Self.grace), reason: reason) }
            else if now >= deadline { effects += prepare() }
            else { effects.append(.countdown(seconds(to: deadline, from: now), reason)) }
        default: break
        }
        return effects
    }
    private func absence(at now: WS2.Instant) -> Reason? {
        guard enabled, !sleeping, lockState == .unlocked,
              cooldownUntil.map({ now >= $0 }) ?? true else { return nil }
        if links[.phone]?.status == .away && (!configuration.watchRequired || links[.watch]?.status == .away) { return .devices }
        if configuration.cameraEnabled, cameraArmed, let since = cameraMissingSince, let last = cameraLastFrame,
           now.elapsed(since: last) < Self.cameraFreshness, now.elapsed(since: lastInput) >= Self.cameraIdle,
           now.elapsed(since: since) >= Self.cameraMissing { return .camera }
        return nil
    }
    private mutating func prepare() -> [Effect] {
        guard let token = tokens.next() else { phase = .idle; return [.fault(.generationExhausted)] }
        phase = .prepared(token)
        return [.prepareCommit(token)]
    }
    private mutating func cancelCountdown() -> [Effect] {
        switch phase {
        case .grace, .countdown, .prepared: phase = .idle; return [.cancelled]
        default: return []
        }
    }
    private mutating func forgetSignals() {
        // 保留 generation 的高水位；不能接受旧连接回调。
        for device in [Device.phone, .watch] {
            links[device]?.status = .unknown; links[device]?.probe = nil; links[device]?.replyAt = nil
        }
        cameraArmed = false; cameraMissingSince = nil; cameraLastFrame = nil; nearSince = nil; lastRSSI = nil
    }
    private func seconds(to deadline: WS2.Instant, from now: WS2.Instant) -> Int {
        let n = deadline.elapsed(since: now); return Int(n / WS2.Duration.second + (n % WS2.Duration.second == 0 ? 0 : 1))
    }
    private func priority(_ event: Event) -> Int {
        switch event {
        case .disable, .sleep, .sensorUnavailable, .lockStateUnknown, .userInput, .systemLocked, .systemUnlocked: return 0
        case .tick, .commitLock: return 2
        default: return 1
        }
    }
}
