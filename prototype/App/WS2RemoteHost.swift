// iPhone 上的遥控器：接收端（工作包 M04，见 docs/conductor-v2.md「全流程」「出岔子」）。
//
// 只在遥控模式开着时宣告和监听；关掉就停宣告、关监听和所有连接，本类自己不开任何定时器
// （每条连接的期限挂在那条连接的传输上，连接没了期限也就没了）。
// - 只认严格的 Pair-Setup 加新鲜的 Pair-Verify；配对后的第一条连接被拒、iPhone 自己重连时什么都不说。
// - 配对码只进刘海卡片，不进日志；SRP 通过后先在刘海里用 Touch ID 确认，拿到授权账消费成功的回执才写钥匙串。
// - 同一时间只有一台 iPhone 能遥控；锁屏、睡眠、切换用户时丢掉遥控输入，解锁后不自动发送、不回到原来那一层。
// - 遥控器送来的按键和触控先交给 RemoteMode / ConductorSession；它们给出的 Effect 记类别日志，再交给 WS2RemoteEffects（M09）
//   按层执行（展开那一排、焦点、放回、启动台、收工、音量、提示音、10 秒收回）。环境里没给端口时只记日志。
import Foundation
import CryptoKit
#if canImport(Network)
@preconcurrency import Network
#endif
#if !WS2_REMOTE_HOST_TESTING
import Cocoa
import SystemConfiguration
#endif

// MARK: - 可替换的边界

/// 一条已接受的连接。生产是 WS2CompanionTCPTransport；单测用内存替身。
@MainActor protocol WS2RemoteLink: AnyObject {
    var onFrame: ((WS2CompanionFrame) -> Void)? { get set }
    var onClosed: ((WS2TransportCloseCause) -> Void)? { get set }
    func start()
    /// 一次整批准入；失败时连接已经关了，调用方不能重试已加密的记录。
    @discardableResult func send(_ records: [Data]) -> Bool
    /// 从现在起多少秒没走到下一步就关（0 < seconds ≤ 120）。
    func setDeadline(after seconds: Double)
    func close(_ cause: WS2TransportCloseCause)
}

/// 宣告加监听。cancel 之后不再回调。
@MainActor protocol WS2RemoteListener: AnyObject { func cancel() }

/// 日志只收事件类别：配对码、键码、坐标、设备名都不进来。
@MainActor protocol WS2RemoteLogSink: AnyObject { func record(_ line: String) }

/// 刘海和授权那一侧。单测用替身，App 里是 WS2RemoteNotchPresenter。
@MainActor protocol WS2RemoteHostPresenter: AnyObject {
    /// 三行卡片：在 iPhone 上输入 / 4 8 1 6 / 60 秒内有效。
    func showPairingCode(_ code: String, onCancel: @escaping () -> Void)
    /// 允许这台 iPhone 遥控 / 遥控和指挥都算 / [用 Touch ID 确认]。
    func showEnrollmentConfirmation(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void)
    func hidePairingCard()
    /// 在刘海里用 Touch ID 确认这一台；只有授权账消费成功才回一张回执，其余（取消、超时、锁屏）回 nil。
    func authorizeEnrollment(identifier: Data, publicKey: Data, completion: @escaping (WS2EnrollmentReceipt?) -> Void)
    func cancelEnrollmentAuthorization()
    func announce(_ text: String, symbol: String?, problem: Bool)
    func setRemoteActivity(_ connected: Bool)
}

/// 宿主的外部依赖。全部在主线程上用。
@MainActor struct WS2RemoteHostEnvironment {
    var clock: any WS2Clock
    var makeStorage: () -> any WS2PeerStorage
    /// 宣告名（这台 Mac 的名字）、本机配对标识、接受连接、监听就绪（true）或失败（false）。
    var makeListener: (_ name: String, _ identifier: Data, _ accept: @escaping (any WS2RemoteLink) -> Void,
                       _ state: @escaping (Bool) -> Void) throws -> any WS2RemoteListener
    /// 配对用的 SRP 引擎。App 里还没有原生 SRP 时是 nil：这时只认已经配过对的 iPhone。
    var makePairSetupEngine: ((_ identifier: Data, _ signingSeed: Data) throws -> any WS2PairSetupEngine)?
    var makePIN: () -> String = PairingAttemptWindow.randomPIN
    var macName: () -> String
    /// 遥控器第 0、1 层的效果端口（刘海那一排、启动台、音量、提示音、媒体键、定时）。没给就只记日志，和 M04 一样。
    var makeEffectPort: (() -> any WS2RemoteEffectPort)?
}

extension AuthTarget {
    /// 让一台 iPhone 遥控这台 Mac：目标就是它的配对标识和签名公钥。
    static func remotePeer(identifier: Data, publicKey: Data) -> AuthTarget {
        AuthTarget(purpose: .enrollDevice, kind: "remote.peer.ed25519", fields: [
            Field(name: "identifier", value: Array(identifier)),
            Field(name: "publicKey", value: Array(publicKey)),
        ])
    }
}

/// 刘海和设置里用到的话。按 docs/copy-guide.md：说用户遇到的事。
enum WS2RemoteCopy {
    static let enterOnPhone = WSL10n.text("remote.enterOnPhone", zh: "在 iPhone 上输入")
    static let codeValidity = WSL10n.text("remote.codeValidity", zh: "60 秒内有效")
    static let allowTitle = WSL10n.text("auth.allowRemote", zh: "允许这台 iPhone 遥控")
    static let allowDetail = WSL10n.text("remote.allowDetail", zh: "遥控和指挥都算")
    static let confirmButton = WSL10n.text("remote.confirmTouchID", zh: "用 Touch ID 确认")
    static let connected = WSL10n.text("remote.connected", zh: "iPhone 已连接")
    static let notConnected = WSL10n.text("remote.notConnected", zh: "没连上，在 iPhone 上再选一次")
    static let disconnected = WSL10n.text("conductor.stage.disconnected", zh: "遥控器断开了")
    static let anotherPhone = WSL10n.text("conductor.msg.otheriPhone", zh: "另一台 iPhone 正在遥控")
    static let removed = WSL10n.text("conductor.stage.revoked", zh: "这台 iPhone 不能再遥控了")
    static let coolingDown = WSL10n.text("remote.coolingDown", zh: "错了 3 次，5 分钟后再试")
    static let pairingUnavailable = WSL10n.text("remote.pairingUnavailable", zh: "这台 Mac 现在还不能配对新的 iPhone")
    static let pairedSuffix = WSL10n.text("remote.pairedSuffix", zh: "配一次，两种都能用")
    static let fallbackName = "iPhone"
    /// 4816 → “4 8 1 6”。
    static func spaced(_ code: String) -> String { code.map(String.init).joined(separator: " ") }
}

// MARK: - 宿主

@MainActor final class WS2RemoteHost {
    enum Status: Equatable { case off, starting, listening, failed }
    /// 连接时限（秒）。和 CompanionHID.idleLimit 同源：后台探测 1、验签后没开会话 3、其余 2.5；
    /// 10 秒内没验签成功就算没连上；会话开着时每条验过签的消息续 120 秒（传输层允许的最长一段）。
    enum Limits {
        static let verify: Double = 10
        static let session: Double = 120
        static let pairing: Double = PairingAttemptWindow.lifetime
    }

    private(set) var status: Status = .off
    private(set) var enabled = false
    private(set) var conductorWanted = false
    private(set) var conductor: ConductorSession
    private(set) var remote = RemoteMode()
    /// 正在遥控的那台 iPhone 的配对标识（不是设备名）。
    var operatorIdentifier: Data? { operatorConnection.flatMap { connections[$0]?.peer?.identifier } }
    var isLocked: Bool { !lockReasons.isEmpty }
    var isListening: Bool { listener != nil && status == .listening }
    var connectionCount: Int { connections.count }
    /// 设置页用：启用中的配对设备（遥控模式关着时不读钥匙串，就是空的）。
    var pairedPeers: [WS2PeerRepository.Peer] { repository?.enabledPeers ?? [] }
    /// 宿主自己的定时器个数。设计上恒为 0：期限都挂在各条连接的传输上。
    let timerCount = 0
    var onChange: (() -> Void)?
    weak var presenter: (any WS2RemoteHostPresenter)?

    private let environment: WS2RemoteHostEnvironment
    private let log: (any WS2RemoteLogSink)?
    private var listener: (any WS2RemoteListener)?
    private var repository: WS2PeerRepository?
    private var admission: WS2PairingAdmission?
    private var signingKey: Curve25519.Signing.PrivateKey?
    private var localIdentifier: Data?
    private var connections: [UUID: Connection] = [:]
    private var operatorConnection: UUID?
    private var lockReasons: Set<String> = []
    private var pairingCodeShown = false
    private var pending: (connection: UUID, epoch: UInt64)?
    private var epoch: UInt64 = 0
    private var pressSerial: UInt64 = 0
    private var conductorSequence: UInt64 = 0
    /// 第 0、1 层的宿主与效果执行。随遥控器连上才有状态；环境没给端口时是 nil。
    private(set) var layerEffects: WS2RemoteEffects?

    init(environment: WS2RemoteHostEnvironment, log: (any WS2RemoteLogSink)? = nil) {
        self.environment = environment; self.log = log
        conductor = ConductorSession(bootID: UUID(), emptyDraftDigest: WS2.Digest(Data(SHA256.hash(data: Data())))!)
        if let port = environment.makeEffectPort?() {
            let effects = WS2RemoteEffects(port: port, clock: environment.clock)
            effects.hooks = WS2RemoteEffects.Hooks(
                setRemoteLayer: { [weak self] layer in self?.applyRemoteLayer(layer) },
                setFocusOnSession: { [weak self] on in self?.remote.setFocusOnSession(on) },
                enterSession: { [weak self] listen in self?.record("session-entered listen=\(listen)") },
                leaveSession: { [weak self] in self?.record("session-left") },
                foldSession: { [weak self] in self?.record("session-folded") },
                announce: { [weak self] text, symbol in self?.presenter?.announce(text, symbol: symbol, problem: false) },
                record: { [weak self] line in self?.record(line) })
            layerEffects = effects
        }
    }

    private var now: WS2.Instant { environment.clock.now() }

    // MARK: 开关

    /// 设置里的总开关和它下面的指挥模式。总开关关掉全停；指挥模式跟着总开关。
    /// 设置页每次重画都会调它：状态没变就什么都不做，也不回调 onChange（免得设置页反复重画）。
    func setEnabled(remote: Bool, conductor wantsConductor: Bool) {
        let conductorOn = remote && wantsConductor
        if remote && !enabled && status != .failed { start() } else if !remote && enabled { stop() }
        if !remote { status = .off }
        if conductorWanted != conductorOn {
            conductorWanted = conductorOn
            layerEffects?.setSessionsAllowed(conductorOn)
            handle(conductor.setEnabled(conductorOn, at: now), source: "conductor-switch")
        }
    }

    private func start() {
        enabled = true; status = .starting
        let storage = environment.makeStorage()
        let repository = WS2PeerRepository(storage: storage)
        repository.onInvalidateAll = { [weak self] in self?.closeAll(silently: true) }
        do {
            do { try repository.load() } catch WS2PeerRepository.Failure.unavailable {
                let identifier = Data(UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased().utf8)
                try repository.provision(identifier: identifier, signingSeed: Curve25519.Signing.PrivateKey().rawRepresentation)
            }
            guard let snapshot = repository.snapshot else { throw WS2PeerRepository.Failure.unavailable }
            signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: snapshot.signingSeed)
            localIdentifier = snapshot.localIdentifier
            self.repository = repository
            let clock = environment.clock
            admission = WS2PairingAdmission(repository: repository, clock: { clock.now().seconds })
            listener = try environment.makeListener(environment.macName(), snapshot.localIdentifier, { [weak self] link in
                self?.accept(link)
            }, { [weak self] ready in self?.listenerState(ready) })
            record("listening-requested")
        } catch {
            record("start-failed")
            stop(); status = .failed
        }
    }

    private func stop() {
        listener?.cancel(); listener = nil
        closeAll(silently: true)
        cancelPairing()
        admission?.cancel(); admission = nil
        repository = nil; signingKey = nil; localIdentifier = nil
        enabled = false; status = .off
        handle(remote.setEnabled(false), source: "remote-off")
        layerEffects?.disconnected()
        // 锁屏观察随遥控模式一起拆掉；留着旧的锁屏原因会让下次打开一直算锁着。
        if isLocked { lockReasons.removeAll(); handle(conductor.setLocked(false, at: now), source: "remote-off") }
        presenter?.setRemoteActivity(false)
        record("stopped")
    }

    private func listenerState(_ ready: Bool) {
        guard enabled, listener != nil else { return }
        if ready { status = .listening; record("listening") }
        else { record("listener-failed"); listener?.cancel(); listener = nil; closeAll(silently: true); status = .failed }
        onChange?()
    }

    // MARK: 锁屏、睡眠、切换用户

    /// reason：screen / session / sleep。任何一个在，就算锁着。
    func setLock(_ reason: String, locked: Bool) {
        let was = isLocked
        if locked { lockReasons.insert(reason) } else { lockReasons.remove(reason) }
        guard was != isLocked else { return }
        if isLocked {
            handle(conductor.setLocked(true, at: now), source: "lock")
            handle(remote.setEnabled(false), source: "lock")
            cancelPairing()
            closeAll(silently: true)
            layerEffects?.disconnected()
            record("locked")
        } else {
            // 不自动发送，也不回到之前那一层：遥控器要重新连上、从第 0 层开始。
            handle(conductor.setLocked(false, at: now), source: "unlock")
            handle(remote.setLayer(.collapsed), source: "unlock")
            record("unlocked")
        }
        onChange?()
    }

    // MARK: 设置里的“移除”

    /// 撤销配对并断开这台的连接。
    @discardableResult func removePeer(identifier: Data) -> Bool {
        guard let repository else { return false }
        do { try repository.revoke(identifier: identifier) } catch { record("revoke-failed"); onChange?(); return false }
        presenter?.announce(WS2RemoteCopy.removed, symbol: "iphone.slash", problem: false)
        record("revoked"); onChange?(); return true
    }

    // MARK: 连接

    private final class Connection {
        enum Phase { case initial, pairVerify, pairSetup, awaitingConfirmation, enrolled, verified, session }
        let id = UUID()
        let link: any WS2RemoteLink
        let acceptedAt: Double
        var phase = Phase.initial
        var verifier: WS2CompanionCrypto?
        var verifyStarted = false
        var fellBack = false
        var setup: WS2PairSetupServer?
        var setupStarted = false
        var session: WS2CompanionCrypto.VerifiedSession?
        var peer: WS2CompanionCrypto.Peer?
        var attempted = false
        var backgroundProbe = false
        var silent = false
        var stopped = false
        var serverSID = UInt64(UInt32.random(in: 1...UInt32.max))
        var buttons: [WS2.Button: (id: UInt64, beganAt: WS2.Instant)] = [:]
        var touch = CompanionHID.Touch()
        var touching = false
        init(link: any WS2RemoteLink, acceptedAt: Double) { self.link = link; self.acceptedAt = acceptedAt }
    }

    private func accept(_ link: any WS2RemoteLink) {
        let unauthenticated = connections.values.filter { $0.session == nil }.count
        guard enabled, !isLocked, repository?.blocked == false, connections.count < WS2ConnectionBudget.totalLimit,
              unauthenticated < WS2ConnectionBudget.unauthenticatedLimit else {
            link.close(.ownerStop); record("connection-refused"); return
        }
        let connection = Connection(link: link, acceptedAt: now.seconds)
        connections[connection.id] = connection
        let id = connection.id
        link.onFrame = { [weak self] frame in self?.receive(frame, on: id) }
        link.onClosed = { [weak self] cause in self?.closed(id, cause: cause) }
        link.start()
        link.setDeadline(after: 2.5)
        record("connection-accepted")
    }

    private func receive(_ frame: WS2CompanionFrame, on id: UUID) {
        guard let connection = connections[id] else { return }
        do {
            guard enabled, !isLocked else { throw Failure.state }
            switch connection.phase {
            case .initial:
                if frame.type == 5 { try beginVerify(connection); try verifyStep(frame, connection) }
                else if frame.type == 3 { try beginSetup(connection); try setupStep(frame, connection) }
                else { throw Failure.state }
            case .pairVerify:
                if frame.type == 3, !connection.fellBack, connection.session == nil {
                    // 不认识这台 Mac 的 iPhone 收到 M2 后改走配对：同一条连接只允许回退一次。
                    connection.fellBack = true; connection.verifier?.close(); connection.verifier = nil
                    try beginSetup(connection); try setupStep(frame, connection)
                } else { try verifyStep(frame, connection) }
            case .pairSetup: try setupStep(frame, connection)
            case .awaitingConfirmation: throw Failure.state
            case .enrolled:
                // 配对完的这条连接不收任何输入（含 Pair-Verify）：静默关掉，iPhone 自己用新鲜的 Pair-Verify 重连。
                connection.silent = true; throw Failure.state
            case .verified, .session: try sessionFrame(frame, connection)
            }
        } catch {
            close(connection, cause: .protocolReject)
        }
    }

    private enum Failure: Error { case state, malformed, unavailable }

    // MARK: Pair-Verify

    private func beginVerify(_ connection: Connection) throws {
        guard let repository, let signingKey, let localIdentifier else { throw Failure.unavailable }
        connection.setup?.cancel(); connection.setup = nil
        connection.verifier = try WS2CompanionCrypto(identity: .init(identifier: localIdentifier, signingKey: signingKey),
            clock: environment.clock, lookup: { identifier in
                guard let p = repository.snapshot?.peers.first(where: { $0.identifier == identifier }) else { return nil }
                return .init(identifier: p.identifier, signingPublicKey: p.publicKey, revision: p.revision, enabled: p.enabled)
            }, isCurrent: { p in repository.current(identifier: p.identifier, publicKey: p.signingPublicKey, revision: p.revision) })
        connection.verifyStarted = false
        connection.phase = .pairVerify
    }

    private func verifyStep(_ frame: WS2CompanionFrame, _ connection: Connection) throws {
        guard let verifier = connection.verifier else { throw Failure.state }
        let (tlv, xid) = try Self.pairingData(frame.payload, allowed: ["_pd", "_auTy", "_x"])
        connection.attempted = true
        if !connection.verifyStarted {
            guard frame.type == 5 else { throw Failure.state }
            // 手机后台探测：_x 的高位置位（暂定，待真机核对），只给 1 秒。
            if let xid, xid & 0x8000_0000 != 0 { connection.backgroundProbe = true; connection.silent = true }
            let m2 = try verifier.answerM1(tlv)
            try sendPairing(m2, type: 6, connection)
            connection.verifyStarted = true
            connection.link.setDeadline(after: remaining(connection, step: connection.backgroundProbe ? 1 : 2.5))
        } else {
            guard frame.type == 6 else { throw Failure.state }
            let result = try verifier.answerM3(tlv)
            do { try sendPairing(result.m4, type: 6, connection) } catch { result.session.close(); throw error }
            connection.session = result.session; connection.peer = result.session.peer
            connection.verifier = nil; connection.phase = .verified
            connection.link.setDeadline(after: 3)
            verified(connection)
        }
    }

    /// 10 秒内要验签成功：每一步的期限不超过从接受连接起的 10 秒。
    private func remaining(_ connection: Connection, step: Double) -> Double {
        let left = connection.acceptedAt + Limits.verify - now.seconds
        return max(0.001, min(step, left))
    }

    private func verified(_ connection: Connection) {
        guard let peer = connection.peer, let repository else { return }
        if let entry = repository.snapshot?.peers.first(where: { $0.identifier == peer.identifier }), entry.awaitingVerification {
            try? repository.markVerified(identifier: peer.identifier, revision: peer.revision)
        }
        // 写钥匙串失败会封锁仓库并关掉所有连接：这条连接也就不算了。
        guard connections[connection.id] != nil else { return }
        if let current = operatorConnection, current != connection.id, let other = connections[current] {
            if other.peer?.identifier == peer.identifier {
                // 同一台重连：换下旧的那条，不重复提醒。
                operatorConnection = connection.id
                close(other, cause: .ownerStop, silently: true, keepOperatorState: true)
                record("operator-reconnected"); return
            }
            // 第二台已配对的 iPhone：验过签也不收它的输入。
            presenter?.announce(WS2RemoteCopy.anotherPhone, symbol: "iphone", problem: true)
            record("second-operator-refused")
            close(connection, cause: .notCurrent, silently: true)
            return
        }
        operatorConnection = connection.id
        handle(remote.setEnabled(true), source: "connected")
        layerEffects?.connected(sessionsAllowed: conductorWanted)
        presenter?.announce(WS2RemoteCopy.connected, symbol: "appletvremote.gen4", problem: false)
        presenter?.setRemoteActivity(true)
        record("operator-verified")
        onChange?()
    }

    // MARK: Pair-Setup

    private func beginSetup(_ connection: Connection) throws {
        guard let repository, let admission, let signingKey, let localIdentifier else { throw Failure.unavailable }
        guard let factory = environment.makePairSetupEngine else {
            presenter?.announce(WS2RemoteCopy.pairingUnavailable, symbol: nil, problem: true)
            record("pairing-unavailable"); connection.silent = true; throw Failure.unavailable
        }
        guard pending == nil else { connection.silent = true; throw Failure.state }
        if !pairingCodeShown {
            do {
                let code = try admission.openByLocalUser(makePIN: environment.makePIN)
                pairingCodeShown = true
                let id = connection.id
                presenter?.showPairingCode(code, onCancel: { [weak self] in self?.userCancelledPairing(id) })
                record("pairing-window-opened")
                // 刘海腾不出地方时卡片会立刻取消，连接已经关了。
                guard connections[id] != nil else { throw Failure.state }
            } catch PairingAttemptWindow.Failure.coolingDown {
                presenter?.announce(WS2RemoteCopy.coolingDown, symbol: nil, problem: true)
                record("pairing-cooling-down"); connection.silent = true; throw Failure.unavailable
            }
        }
        connection.setup = WS2PairSetupServer(connection: connection.id, admission: admission, repository: repository,
                                              engine: try factory(localIdentifier, signingKey.rawRepresentation))
        connection.setupStarted = false
        connection.phase = .pairSetup
        connection.link.setDeadline(after: Limits.pairing)
    }

    private func setupStep(_ frame: WS2CompanionFrame, _ connection: Connection) throws {
        guard let server = connection.setup else { throw Failure.state }
        guard frame.type == (connection.setupStarted ? 4 : 3) else { throw Failure.state }
        let (tlv, _) = try Self.pairingData(frame.payload, allowed: ["_pd", "_pwTy", "_x"], pairingType: true)
        connection.attempted = true
        let reply = try server.receiveDeferringEnrollment(tlv)
        connection.setupStarted = true
        if let reply {
            try sendPairing(reply, type: 4, connection)
            return
        }
        guard let candidate = server.pendingEnrollment else { throw Failure.state }
        // SRP 和 M5 签名都过了：先问本机的人，那之前不写钥匙串、不发 M6。
        connection.phase = .awaitingConfirmation
        epoch &+= 1
        let ticket = epoch, id = connection.id
        pending = (id, ticket)
        presenter?.showEnrollmentConfirmation(onConfirm: { [weak self] in
            self?.confirmEnrollment(ticket, identifier: candidate.identifier, publicKey: candidate.publicKey)
        }, onCancel: { [weak self] in self?.userCancelledPairing(id) })
        record("pairing-awaiting-confirmation")
    }

    private func confirmEnrollment(_ ticket: UInt64, identifier: Data, publicKey: Data) {
        guard let pending, pending.epoch == ticket, connections[pending.connection]?.phase == .awaitingConfirmation else { return }
        presenter?.authorizeEnrollment(identifier: identifier, publicKey: publicKey) { [weak self] receipt in
            self?.authorized(receipt, ticket: ticket)
        }
    }

    /// 授权回来。取消之后、换了一轮、连接没了、锁屏了，晚到的成功一律不算。
    func authorized(_ receipt: WS2EnrollmentReceipt?, ticket: UInt64) {
        guard let pending, pending.epoch == ticket, enabled, !isLocked,
              let connection = connections[pending.connection], connection.phase == .awaitingConfirmation,
              let server = connection.setup, let candidate = server.pendingEnrollment else {
            record("late-confirmation-ignored"); return
        }
        self.pending = nil
        guard let receipt, receipt.identifier == candidate.identifier, receipt.publicKey == candidate.publicKey else {
            record("confirmation-declined")
            connection.silent = true; close(connection, cause: .ownerStop); return
        }
        do {
            let reply = try server.commitEnrollment(receipt)
            try sendPairing(reply, type: 4, connection)
            connection.phase = .enrolled; connection.silent = true
            pairingCodeShown = false
            presenter?.hidePairingCard()
            connection.link.setDeadline(after: Limits.verify)
            record("enrolled"); onChange?()
        } catch {
            record("enroll-failed")
            connection.silent = true; close(connection, cause: .protocolReject)
        }
    }

    private func userCancelledPairing(_ id: UUID) {
        if let connection = connections[id] { connection.silent = true; close(connection, cause: .ownerStop) }
        cancelPairing()
    }

    /// 收掉配对卡、撤回进行中的 Touch ID、关掉配对窗口。失败次数和冷却不会因此清掉。
    private func cancelPairing() {
        if pending != nil { presenter?.cancelEnrollmentAuthorization() }
        pending = nil
        if pairingCodeShown { pairingCodeShown = false; admission?.cancel() }
        presenter?.hidePairingCard()
    }

    // MARK: 会话

    private func sessionFrame(_ frame: WS2CompanionFrame, _ connection: Connection) throws {
        guard frame.type == 8, let session = connection.session else { throw Failure.state }
        let plain = try session.open(frame)
        let message = try Self.envelope(plain)
        var outcome = try profile(message, connection)
        if Self.sessionStarts.contains(message.identifier) || ((message.identifier == "_hidC" || message.identifier == "_hidT") && !connection.stopped) {
            connection.phase = .session
        }
        if connection.phase == .session { connection.link.setDeadline(after: Limits.session) }
        if message.identifier == "_hidC" || message.identifier == "_hidT" { input(message, connection) }
        guard !outcome.isEmpty else { return }
        outcome = Array(outcome.prefix(16))
        let records = try outcome.map { try session.seal(WS2OPACK.encode($0)) }
        guard connection.link.send(records) else { throw Failure.state }
    }

    private static let sessionStarts: Set<String> = ["_sessionStart", "TVRCSessionStart", "_touchStart"]

    private struct Envelope {
        let identifier: String
        let content: [String: WS2OPACK.Value]
        let transaction: UInt64?
        let isRequest: Bool
    }

    private static func envelope(_ plain: Data) throws -> Envelope {
        guard case .dictionary(let fields) = try WS2OPACK.decode(plain),
              case .string(let method) = fields["_i"] ?? fields["model"],
              !method.isEmpty, method.utf8.count <= 128,
              case .dictionary(let content) = fields["_c"] ?? .dictionary([:]) else { throw Failure.malformed }
        let kind = fields["_t"] ?? (fields["_x"] == nil ? .uint(1) : .uint(2))
        guard kind == .uint(1) || kind == .uint(2) else { throw Failure.malformed }
        var transaction: UInt64?
        if let value = fields["_x"] { guard case .uint(let xid) = value else { throw Failure.malformed }; transaction = xid }
        return Envelope(identifier: method, content: content, transaction: transaction, isRequest: kind == .uint(2))
    }

    /// 遥控器要的那几问一答。状态只说这台接收端自己，不读 Mac 的媒体或 App 状态。
    private func profile(_ message: Envelope, _ connection: Connection) throws -> [WS2OPACK.Value] {
        var reply: [String: WS2OPACK.Value]? = message.isRequest ? [:] : nil
        var resultType: UInt64 = 0
        var events: [(String, [String: WS2OPACK.Value], Bool)] = []
        func status(_ name: String) -> [String: WS2OPACK.Value] {
            switch name {
            case "SystemStatus", "TVSystemStatus": return ["state": .uint(3)]
            // 0x0100 = 音量控制可用（atv-core 事实：通告它 iPhone 音量键和 _mcc 5/6 才会来）。
            case "MediaControlStatus": return ["MediaControlFlags": .uint(0x0100)]
            case "_iMC": return ["_mcF": .uint(0x0100)]
            default: return [:]
            }
        }
        switch message.identifier {
        case "_systemInfo", "SystemInfo":
            if case .string(let name) = message.content["name"], let peer = connection.peer, operatorConnection == connection.id {
                try? repository?.setDisplayName(name, identifier: peer.identifier, revision: peer.revision)
            }
            events = [("SystemStatus", status("SystemStatus"), false), ("TVSystemStatus", status("TVSystemStatus"), false)]
        case "_sessionStart":
            if let service = message.content["_srvT"], service != .string("com.apple.tvremoteservices") { throw Failure.malformed }
            connection.stopped = false
            if reply != nil { reply = ["_sid": .uint(connection.serverSID)] }
        case "_sessionStop":
            connection.stopped = true; connection.buttons.removeAll(); connection.touch.reset(); connection.touching = false
            connection.serverSID = UInt64(UInt32.random(in: 1...UInt32.max))
        case "TVRCSessionStart":
            let version = message.content["ProtocolVersionKey"] ?? .string("1.2")
            guard case .string(let text) = version, !text.isEmpty, text.utf8.count <= 32 else { throw Failure.malformed }
            connection.stopped = false
            if reply != nil { reply = ["ProtocolVersionKey": version] }
            events = [("MediaControlStatus", status("MediaControlStatus"), true), ("_iMC", status("_iMC"), true)]
        case "_touchStart":
            connection.stopped = false
            if reply != nil { reply = ["_i": .uint(1)] }
        case "_tiStart": if reply != nil { reply = ["_tiE": .bool(false)] }
        case "_interest":
            guard Set(message.content.keys).isSubset(of: ["_regEvents", "_deregEvents"]) else { throw Failure.malformed }
            if case .array(let names) = message.content["_regEvents"] {
                for case .string(let name) in names.prefix(16)
                where ["MediaControlStatus", "_iMC", "SystemStatus", "TVSystemStatus"].contains(name) {
                    events.append((name, status(name), true))
                }
            }
        case "FetchMediaControlStatus": if reply != nil { reply = ["MediaControlFlags": .uint(0x0100)] }
        case "FetchAttentionState": if reply != nil { reply = ["state": .uint(3)] }
        case "FetchLaunchableApplicationsEvent": resultType = 2
        case "MediaControlCommand", "_mcc":
            if let long = message.content["MediaControlCommand"], let short = message.content["_mcc"], long != short { throw Failure.malformed }
            guard case .uint(let command) = message.content["MediaControlCommand"] ?? message.content["_mcc"] ?? .null else { throw Failure.malformed }
            switch command {
            case 5:
                // 读不到按 0：对端把 0 当静音，不会误报高音量。
                if reply != nil { reply = ["_vol": .real(layerEffects?.mediaVolume() ?? 0)] }
            case 6:
                let value: Double
                switch message.content["_vol"] {
                case .real(let number): value = number
                case .uint(let number): value = Double(number)
                default: throw Failure.malformed
                }
                guard value.isFinite else { throw Failure.malformed }
                layerEffects?.setMediaVolume(value)
            case 12:
                // 字幕开关：这台接收端没有字幕功能。
                if reply != nil { reply = ["_cse": .bool(false)] }
            default:
                break // 参考行为：未知媒体命令回空应答。
            }
        default:
            break // 不认识的方法：有事务号就回空，没有就不说话；都不进输入或动作入口。
        }
        var output: [WS2OPACK.Value] = []
        if let reply {
            var value: [String: WS2OPACK.Value] = ["_i": .string(message.identifier), "_t": .uint(3),
                                                   "_rT": .uint(resultType), "_c": .dictionary(reply)]
            if let xid = message.transaction { value["_x"] = .uint(xid) }
            output.append(.dictionary(value))
        }
        for (name, content, echo) in events {
            var value: [String: WS2OPACK.Value] = ["_i": .string(name), "_t": .uint(1), "_c": .dictionary(content)]
            if echo, let xid = message.transaction { value["_x"] = .uint(xid) }
            output.append(.dictionary(value))
        }
        return output
    }

    // MARK: 输入

    private func input(_ message: Envelope, _ connection: Connection) {
        guard operatorConnection == connection.id, !connection.stopped, enabled, !isLocked else { return }
        let at = now
        func number(_ value: WS2OPACK.Value?) -> Double? {
            switch value { case .real(let n): return n.isFinite ? n : nil
            case .uint(let n): return Double(n)
            default: return nil }
        }
        if message.identifier == "_hidC" {
            guard case .uint(let code) = message.content["_hidC"], case .uint(let state) = message.content["_hBtS"],
                  let button = CompanionHID.button(code: code) else { return }
            if state == 1 {
                guard connection.buttons[button] == nil else { return }
                pressSerial &+= 1
                connection.buttons[button] = (pressSerial, at)
                press(WS2.ButtonEvent(button: button, phase: .down, pressID: pressSerial, beganAt: at, at: at))
            } else if state == 2, let held = connection.buttons.removeValue(forKey: button) {
                press(WS2.ButtonEvent(button: button, phase: .up, pressID: held.id, beganAt: held.beganAt, at: at))
            }
            return
        }
        guard case .uint(let phase) = message.content["_tPh"], let x = number(message.content["_cx"]),
              let y = number(message.content["_cy"]) else { connection.touch.reset(); return }
        if remote.layer == .session, conductor.context != nil {
            let point = WS2.Point(x: x / CompanionHID.touchSide, y: 1 - y / CompanionHID.touchSide)
            let mapped: ConductorSession.TouchPhase? = phase == 1 ? .begin : phase == 2 ? .move : phase == 4 ? .end : nil
            if let mapped { conduct(.touch(mapped, point)) }
            return
        }
        for gesture in connection.touch.feed(phase: phase, x: x, y: y) {
            let button: WS2.Button
            switch gesture {
            case .tap: button = .select
            case .swipe(.up): button = .up
            case .swipe(.down): button = .down
            case .swipe(.left): button = .left
            case .swipe(.right): button = .right
            }
            pressSerial &+= 1
            press(WS2.ButtonEvent(button: button, phase: .clickOnly, pressID: pressSerial, beganAt: at, at: at))
        }
    }

    private func press(_ event: WS2.ButtonEvent) {
        for effect in remote.handle(event) {
            if case .forward(let forwarded) = effect { conduct(.button(forwarded)) }
            else { handle([effect], source: "remote") }
        }
    }

    private func conduct(_ event: ConductorSession.Event) {
        guard let context = conductor.context else { return }
        conductorSequence &+= 1
        let envelope = WS2.Envelope(context: context, sequence: conductorSequence, receivedAt: now,
                                    commandID: nil, turnID: nil, payload: event)
        handle(conductor.receive(envelope), source: "conductor")
    }

    /// 日志只记类别，不带参数（参数里有键位、草稿和项目名）；执行归 WS2RemoteEffects（M09）。
    private func handle(_ effects: [RemoteMode.Effect], source: String) {
        for effect in effects { record("\(source) effect \(Self.label(effect))") }
        layerEffects?.receive(remote: effects)
    }
    private func handle(_ effects: [ConductorSession.Effect], source: String) {
        for effect in effects { record("\(source) effect \(Self.label(effect))") }
        layerEffects?.receive(conductor: effects)
    }
    /// 宿主换层：RemoteMode 按层翻译按键。离开会话层时撤掉手势、候选和录音，草稿留在会话里。
    private func applyRemoteLayer(_ layer: RemoteMode.Layer) {
        let effects = remote.setLayer(layer)
        handle(effects, source: "layer")
        if effects.contains(.cancelConductorInput) { handle(conductor.cancelInput(at: now), source: "layer") }
    }
    static func label(_ effect: RemoteMode.Effect) -> String { String(String(describing: effect).prefix { $0 != "(" }) }
    static func label(_ effect: ConductorSession.Effect) -> String { String(String(describing: effect).prefix { $0 != "(" }) }

    // MARK: 关闭

    private func closed(_ id: UUID, cause: WS2TransportCloseCause) {
        guard let connection = connections[id] else { return }
        finish(connection, cause: cause, keepOperatorState: false)
    }

    private func close(_ connection: Connection, cause: WS2TransportCloseCause, silently: Bool = false,
                       keepOperatorState: Bool = false) {
        if silently { connection.silent = true }
        guard connections[connection.id] != nil else { return }
        finish(connection, cause: cause, keepOperatorState: keepOperatorState)
        connection.link.close(cause)
    }

    private func finish(_ connection: Connection, cause: WS2TransportCloseCause, keepOperatorState: Bool) {
        connections.removeValue(forKey: connection.id)
        connection.link.onFrame = nil; connection.link.onClosed = nil
        connection.verifier?.close(); connection.verifier = nil
        connection.session?.close(); connection.session = nil
        let wasPairing = connection.setup != nil && connection.phase != .enrolled
        connection.setup?.cancel(); connection.setup = nil
        if pending?.connection == connection.id || (wasPairing && pairingCodeShown && pending == nil && !connections.values.contains { $0.setup != nil }) {
            cancelPairing()
        }
        if operatorConnection == connection.id && !keepOperatorState {
            operatorConnection = nil
            // 输入作废，草稿留着；后端照跑。
            handle(remote.setEnabled(false), source: "disconnect")
            handle(conductor.cancelInput(at: now), source: "disconnect")
            layerEffects?.disconnected()
            presenter?.setRemoteActivity(false)
            if !connection.silent && enabled && !isLocked { presenter?.announce(WS2RemoteCopy.disconnected, symbol: "appletvremote.gen4", problem: true) }
            record("operator-disconnected")
            onChange?()
        } else if connection.peer == nil, connection.attempted, !connection.silent, enabled, !isLocked {
            presenter?.announce(WS2RemoteCopy.notConnected, symbol: nil, problem: true)
            record("verify-failed")
        }
        record("connection-closed \(cause.rawValue)")
    }

    private func closeAll(silently: Bool) {
        for connection in Array(connections.values) { close(connection, cause: .ownerStop, silently: silently) }
        operatorConnection = nil
    }

    // MARK: 帧

    private func sendPairing(_ tlv: Data, type: UInt8, _ connection: Connection) throws {
        let bytes = try WS2CompanionFrame(type: type, payload: WS2OPACK.encode(.dictionary(["_pd": .data(tlv)]))).encoded()
        guard connection.link.send([bytes]) else { throw Failure.state }
    }

    private static func pairingData(_ bytes: Data, allowed: Set<String>, pairingType: Bool = false) throws -> (Data, UInt64?) {
        guard case .dictionary(let fields) = try WS2OPACK.decode(bytes), Set(fields.keys).isSubset(of: allowed),
              case .data(let tlv) = fields["_pd"], !tlv.isEmpty, tlv.count <= 4096 else { throw Failure.malformed }
        if let auth = fields["_auTy"], auth != .uint(4) { throw Failure.malformed }
        if pairingType, let kind = fields["_pwTy"], kind != .uint(1) { throw Failure.malformed }
        var xid: UInt64?
        if let value = fields["_x"] { guard case .uint(let number) = value else { throw Failure.malformed }; xid = number }
        return (tlv, xid)
    }

    private func record(_ line: String) { log?.record("remote-host " + line) }
}

// MARK: - 网络（宣告、监听、传输）

#if canImport(Network)
/// 按 2026-10-08 真机跑通的 atv-core 宣告：Companion、MRP、AirPlay 三个服务，名字是这台 Mac。
/// 只有 Companion 那一路收连接；MRP 和 AirPlay 的连接不读不回、立刻关掉。
@MainActor final class WS2RemoteBonjourListener: WS2RemoteListener {
    private var listeners: [String: NWListener] = [:]
    private var ready: Set<String> = []
    private var cancelled = false
    private var index: UInt64 = 0
    private let serviceCount: Int
    private let accept: (any WS2RemoteLink) -> Void
    private let state: (Bool) -> Void

    init(name: String, identifier: Data, accept: @escaping (any WS2RemoteLink) -> Void,
         state: @escaping (Bool) -> Void) throws {
        let services = Self.services(name: name, compact: String(decoding: identifier, as: UTF8.self))
        serviceCount = services.count; self.accept = accept; self.state = state
        do {
            for (type, txt) in services {
                let listener = try NWListener(using: .tcp, on: .any)
                listeners[type] = listener
                var record = NWTXTRecord()
                for (key, value) in txt { record[key] = value }
                listener.service = NWListener.Service(name: name, type: type, txtRecord: record)
                listener.newConnectionHandler = { [weak self] connection in MainActor.assumeIsolated {
                    guard let self, !self.cancelled, type == "_companion-link._tcp" else { connection.cancel(); return }
                    self.index &+= 1
                    self.accept(WS2RemoteTCPLink(connection: connection, index: self.index))
                } }
                listener.stateUpdateHandler = { [weak self] update in MainActor.assumeIsolated {
                    guard let self, !self.cancelled else { return }
                    switch update {
                    case .ready:
                        guard self.ready.insert(type).inserted, self.ready.count == self.serviceCount else { return }
                        self.state(true)
                    case .failed: self.state(false)
                    default: break
                    }
                } }
            }
            for listener in listeners.values { listener.start(queue: .main) }
        } catch { cancel(); throw error }
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        for listener in listeners.values {
            listener.stateUpdateHandler = nil; listener.newConnectionHandler = nil; listener.cancel()
        }
        listeners.removeAll(); ready.removeAll()
    }

    /// 字段名和常量照固定的 atv-core 接收端；哈希是发现用的标记，不是签名公钥，也不证明身份。
    static func services(name: String, compact: String) -> [(String, [String: String])] {
        func tag(_ label: String, bytes: Int, uppercase: Bool = true) -> String {
            let hex = SHA256.hash(data: Data((label + compact).utf8)).prefix(bytes).map { String(format: "%02x", $0) }.joined()
            return uppercase ? hex.uppercased() : hex
        }
        let deviceID = "02:" + SHA256.hash(data: Data(("deviceID:" + compact).utf8)).prefix(5)
            .map { String(format: "%02X", $0) }.joined(separator: ":")
        var dashed = compact
        if compact.count == 32 {
            let c = Array(compact)
            dashed = [c[0..<8], c[8..<12], c[12..<16], c[16..<20], c[20..<32]].map { String($0) }.joined(separator: "-")
        }
        let model = "AppleTV14,1"
        return [
            ("_mediaremotetv._tcp", ["Name": name, "UniqueIdentifier": compact, "SystemBuildVersion": "22K160",
                "LocalAirPlayReceiverPairingIdentity": tag("airplay-identity:", bytes: 8),
                "ModelName": "Apple TV", "AllowPairing": "YES"]),
            ("_companion-link._tcp", ["rpMac": "1", "rpHA": deviceID.replacingOccurrences(of: ":", with: ""),
                "rpHN": tag("rpHN:", bytes: 6), "rpVr": "715.2", "rpMd": model, "rpFl": "0x36782",
                "rpAD": tag("rpAD:", bytes: 6), "rpHI": tag("rpHI:", bytes: 6), "rpBA": deviceID]),
            ("_airplay._tcp", ["deviceid": deviceID, "features": "0x5A7FFFF7,0x1E", "flags": "0x44",
                "model": model, "srcvers": "715.2", "vv": "2", "pi": dashed,
                "pk": tag("pk:", bytes: 16, uppercase: false), "name": name]),
        ]
    }
}

/// 把已有的有界 TCP 传输接到宿主上。期限、发送队列和关闭首因都还是传输自己管。
@MainActor final class WS2RemoteTCPLink: WS2RemoteLink {
    private let transport: WS2CompanionTCPTransport
    var onFrame: ((WS2CompanionFrame) -> Void)?
    var onClosed: ((WS2TransportCloseCause) -> Void)?
    init(connection: NWConnection, index: UInt64) {
        transport = WS2CompanionTCPTransport(connection: connection, connectionIndex: index,
            clock: { ProcessInfo.processInfo.systemUptime }, isCurrent: { true })
        transport.onFrame = { [weak self] frame in self?.onFrame?(frame) }
        transport.onCloseWithDiagnostics = { [weak self] snapshot in
            let callback = self?.onClosed; self?.onClosed = nil; callback?(snapshot.cause)
        }
    }
    func start() { transport.start() }
    @discardableResult func send(_ records: [Data]) -> Bool {
        transport.enqueueBatch(records, deadline: ProcessInfo.processInfo.systemUptime + 5)
    }
    func setDeadline(after seconds: Double) {
        transport.setProtocolDeadline(ProcessInfo.processInfo.systemUptime + min(120, max(0.001, seconds)))
    }
    func close(_ cause: WS2TransportCloseCause) { onClosed = nil; transport.close(cause: cause) }
}
#endif

#if !WS2_REMOTE_HOST_TESTING
// MARK: - App 里的刘海、授权和锁屏

/// 写进 ~/Library/Logs/WindowShade 的那份日志。只收类别。
@MainActor final class WS2RemoteDiagnosticsLog: WS2RemoteLogSink {
    func record(_ line: String) { wlog(line) }
}

extension WS2RemoteHost {
    /// App 里的宿主：钥匙串存配对、Bonjour 宣告、刘海里说话。原生 SRP 已接（WS2PureSRP），能配新 iPhone。
    static func makeForApp() -> WS2RemoteHost {
        let environment = WS2RemoteHostEnvironment(
            clock: WS2ContinuousClock(),
            makeStorage: { WS2KeychainPeerStorage(service: "WindowShade.Remote.peers") },
            makeListener: { name, identifier, accept, state in
                try WS2RemoteBonjourListener(name: name, identifier: identifier, accept: accept, state: state)
            },
            makePairSetupEngine: { identifier, signingSeed in
                // 纯 Swift SRP（真机第四轮起 srptoolsMinimal 规约配对通过；C 交叉验证见 tests/run-srp-cross-check.sh）。
                try WS2PairSetupCrypto(srp: WS2PureSRP(convention: .srptoolsMinimal),
                                       identifier: identifier, signingSeed: signingSeed)
            },
            macName: { (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac" },
            makeEffectPort: { WS2RemoteSystemPort() })
        let host = WS2RemoteHost(environment: environment, log: WS2RemoteDiagnosticsLog())
        return host
    }
}

/// 锁屏、睡眠、快速切换用户。只在遥控模式开着时装。
@MainActor final class WS2RemoteLockObserver {
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    init(host: WS2RemoteHost) {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let pairs: [(NotificationCenter, Notification.Name, String, Bool)] = [
            (workspace, NSWorkspace.willSleepNotification, "sleep", true),
            (workspace, NSWorkspace.didWakeNotification, "sleep", false),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, "session", true),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, "session", false),
            (distributed, .init("com.apple.screenIsLocked"), "screen", true),
            (distributed, .init("com.apple.screenIsUnlocked"), "screen", false),
        ]
        for (center, name, reason, locked) in pairs {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak host] _ in
                MainActor.assumeIsolated { host?.setLock(reason, locked: locked) }
            }))
        }
    }
    func invalidate() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}

/// 刘海一侧：配对卡走共享岛（和指挥模式同一个主人），Touch ID 走现有的认证控制器，记 enrollDevice。
@MainActor final class WS2RemoteNotchPresenter: WS2RemoteHostPresenter {
    private weak var card: WS2RemotePairingCard?
    private var authorizing = false
    private var notch: NotchController? { (NSApp.delegate as? AppDelegate)?.notch }

    func showPairingCode(_ code: String, onCancel: @escaping () -> Void) {
        present { $0.showCode(code) } onCancel: { onCancel() }
    }

    func showEnrollmentConfirmation(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        present { card in
            card.showConfirmation { [weak self, weak card] in
                guard let self, let card, card.inputIsCurrent() else { return }
                // 交给原生认证：这不是取消，不回报 onCancel。
                _ = self.notch?.leases.handOffToAuthorization(ifShowing: card)
                onConfirm()
            }
        } onCancel: { onCancel() }
    }

    private func present(_ configure: (WS2RemotePairingCard) -> Void, onCancel: @escaping () -> Void) {
        if let card, notch?.leases.inputHandle(for: card) != nil {
            configure(card); card.cancelled = onCancel; return
        }
        let view = WS2RemotePairingCard()
        configure(view); view.cancelled = onCancel
        guard let notch, notch.leases.show(view, ownerID: "conductor", onDismiss: { [weak view] _ in
            view?.cancelled?()
        }) else { onCancel(); return }
        card = view
    }

    func hidePairingCard() {
        guard let card else { return }
        card.cancelled = nil
        notch?.leases.dismiss(ifShowing: card)
        self.card = nil
    }

    func authorizeEnrollment(identifier: Data, publicKey: Data, completion: @escaping (WS2EnrollmentReceipt?) -> Void) {
        guard let notch, !authorizing else { completion(nil); return }
        let target = AuthTarget.remotePeer(identifier: identifier, publicKey: publicKey)
        authorizing = true
        notch.authentication.authorize(target) { [weak self] grant in
            self?.authorizing = false
            // 原生指纹成功、签名验过、授权账发了这张一次性授权，并且按当时的目标消费成功，才算回执。
            guard let grant, AuthorizationService.shared.consume(grant, purpose: .enrollDevice, currentTarget: target) == nil else {
                completion(nil); return
            }
            completion(WS2EnrollmentReceipt(consumedGrantFor: identifier, publicKey: publicKey))
        }
    }

    func cancelEnrollmentAuthorization() {
        guard authorizing else { return }
        notch?.authentication.cancel(animated: false, restoreFocus: false)
    }

    func announce(_ text: String, symbol: String?, problem: Bool) {
        notch?.announce(text, tone: problem ? .problem : .info, symbol: symbol, duration: MotionHold.alertSeconds)
    }

    func setRemoteActivity(_ connected: Bool) { notch?.activities.ws2PublishRemote(connected: connected) }
}

/// 刘海里的配对卡：三行配对码，或者确认这一台。
@MainActor final class WS2RemotePairingCard: NSView, WS2LeaseContent {
    var onCancel: (() -> Void)?
    var cancelled: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    var interactionSize: NSSize { NSSize(width: 300, height: 132) }
    private let first = NSTextField(labelWithString: "")
    private let second = NSTextField(labelWithString: "")
    private let third = NSTextField(labelWithString: "")
    private let button = NSButton(title: WS2RemoteCopy.confirmButton, target: nil, action: nil)
    private var confirm: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; appearance = NSAppearance(named: .darkAqua)
        for field in [first, second, third] {
            field.alignment = .center; field.textColor = .white; field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
        }
        first.font = .systemFont(ofSize: 13, weight: .medium)
        third.font = .systemFont(ofSize: 11); third.textColor = .white.withAlphaComponent(0.65)
        button.bezelStyle = .rounded; button.target = self; button.action = #selector(confirmPressed)
        button.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [first, second, third, button])
        stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
        ])
        onCancel = { [weak self] in self?.cancelled?() }
    }
    required init?(coder: NSCoder) { nil }

    /// 第二行数字隔开写，SF Pro Rounded 等宽数字。
    func showCode(_ code: String) {
        confirm = nil
        first.stringValue = WS2RemoteCopy.enterOnPhone
        second.stringValue = WS2RemoteCopy.spaced(code)
        second.font = Self.roundedDigits(size: 30)
        third.stringValue = WS2RemoteCopy.codeValidity; third.isHidden = false
        button.isHidden = true
        second.setAccessibilityLabel(WSL10n.text("remote.pairingCode", zh: "配对码 %@", WS2RemoteCopy.spaced(code)))
        announce(WS2RemoteCopy.enterOnPhone)
    }

    func showConfirmation(_ action: @escaping () -> Void) {
        confirm = action
        first.stringValue = WS2RemoteCopy.allowTitle
        second.stringValue = WS2RemoteCopy.allowDetail
        second.font = .systemFont(ofSize: 12); second.setAccessibilityLabel(WS2RemoteCopy.allowDetail)
        third.isHidden = true
        button.isHidden = false
        announce(WS2RemoteCopy.allowTitle)
    }

    private static func roundedDigits(size: CGFloat) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
        guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: rounded, size: size) ?? base
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    @objc private func confirmPressed() { guard inputIsCurrent() else { return }; confirm?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    func revoke() { inputIsCurrent = { false }; confirm = nil; second.stringValue = "" }
}
#endif
