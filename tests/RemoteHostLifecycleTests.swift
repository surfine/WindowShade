import Foundation
import CryptoKit

// 替身：没有 socket、没有钥匙串、没有刘海。只有 Pair-Verify 用真实的 CryptoKit 握手。

final class TestClock: WS2Clock, @unchecked Sendable {
    var seconds = 1.0
    func now() -> WS2.Instant { WS2.Instant(seconds: seconds)! }
}

@MainActor final class Store: WS2PeerStorage {
    var bytes: Data?
    var reads = 0
    let receiptRequired: Bool
    init(receiptRequired: Bool) { self.receiptRequired = receiptRequired }
    var requiresEnrollmentReceipt: Bool { receiptRequired }
    func read() throws -> Data? { reads += 1; return bytes }
    func replace(_ bytes: Data, creating: Bool) throws { self.bytes = bytes }
}

@MainActor final class Link: WS2RemoteLink {
    var onFrame: ((WS2CompanionFrame) -> Void)?
    var onClosed: ((WS2TransportCloseCause) -> Void)?
    var started = false
    var sent: [Data] = []
    var deadlines: [Double] = []
    var closedCause: WS2TransportCloseCause?
    func start() { started = true }
    func send(_ records: [Data]) -> Bool { guard closedCause == nil else { return false }; sent += records; return true }
    func setDeadline(after seconds: Double) { deadlines.append(seconds) }
    func close(_ cause: WS2TransportCloseCause) {
        guard closedCause == nil else { return }
        closedCause = cause; let callback = onClosed; onClosed = nil; callback?(cause)
    }
    /// 对端那边断开（Wi-Fi 断、遥控器关了）。
    func peerClosed() { close(.remoteEOF) }
    func push(_ type: UInt8, _ payload: Data) { onFrame?(WS2CompanionFrame(type: type, payload: payload)) }
    func frames() throws -> [WS2CompanionFrame] {
        var decoder = WS2CompanionFrame.Decoder(); return try decoder.feed(sent.reduce(Data(), +))
    }
}

@MainActor final class Listener: WS2RemoteListener {
    var cancelled = false
    func cancel() { cancelled = true }
}

@MainActor final class Log: WS2RemoteLogSink {
    var lines: [String] = []
    func record(_ line: String) { lines.append(line) }
}

@MainActor final class Presenter: WS2RemoteHostPresenter {
    var codes: [String] = []
    var confirm: (() -> Void)?
    var cancelCard: (() -> Void)?
    var cardHidden = 0
    var authorization: ((WS2EnrollmentReceipt?) -> Void)?
    var authorizationCancelled = 0
    var announcements: [String] = []
    var activity: [Bool] = []
    func showPairingCode(_ code: String, onCancel: @escaping () -> Void) { codes.append(code); cancelCard = onCancel }
    func showEnrollmentConfirmation(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        confirm = onConfirm; cancelCard = onCancel
    }
    func hidePairingCard() { cardHidden += 1 }
    func authorizeEnrollment(identifier: Data, publicKey: Data, completion: @escaping (WS2EnrollmentReceipt?) -> Void) {
        authorization = completion
    }
    func cancelEnrollmentAuthorization() { authorizationCancelled += 1 }
    func announce(_ text: String, symbol: String?, problem: Bool) { announcements.append(text) }
    func setRemoteActivity(_ connected: Bool) { activity.append(connected) }
}

/// 只测排序和持久化用的假 SRP。永远不进 App 源码。
@MainActor final class FakeEngine: WS2PairSetupEngine {
    let identifier: Data, publicKey: Data
    init(identifier: Data, publicKey: Data) { self.identifier = identifier; self.publicKey = publicKey }
    func begin(pin: String) throws -> (salt: Data, publicKey: Data) { (Data(repeating: 1, count: 16), Data(repeating: 2, count: 384)) }
    func verify(clientPublicKey: Data, proof: Data) throws -> Data { Data(repeating: 3, count: 64) }
    func finish(encryptedM5: Data) throws -> (identifier: Data, publicKey: Data, encryptedM6: Data) {
        (identifier, publicKey, Data(repeating: 5, count: 128))
    }
    func clear() {}
}

/// 一台 iPhone：真实的 Pair-Verify 客户端和会话加密。
@MainActor final class Phone {
    let identifier: Data
    let signing = Curve25519.Signing.PrivateKey()
    private var ephemeral = Curve25519.KeyAgreement.PrivateKey()
    private var transmit: SymmetricKey?
    private var receive: SymmetricKey?
    private var tx = WS2CompanionCounter(), rx = WS2CompanionCounter()
    init(_ name: String) { identifier = Data(name.utf8) }
    var publicKey: Data { signing.publicKey.rawRepresentation }

    static func pd(_ tlv: Data, extra: [String: WS2OPACK.Value] = [:]) throws -> Data {
        var fields = extra; fields["_pd"] = .data(tlv)
        return try WS2OPACK.encode(.dictionary(fields))
    }
    func m1() throws -> Data {
        ephemeral = Curve25519.KeyAgreement.PrivateKey()
        return try Self.pd(PairingTLV.encode([(6, Data([1])), (3, ephemeral.publicKey.rawRepresentation)]))
    }
    func m3(after m2: WS2CompanionFrame) throws -> Data {
        guard case .dictionary(let fields) = try WS2OPACK.decode(m2.payload), case .data(let tlv) = fields["_pd"] else { throw Failure.bad }
        let values = try PairingTLV.decode(tlv, allowed: [3, 5, 6])
        guard let serverKey = values[3] else { throw Failure.bad }
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: serverKey))
        func derive(_ salt: String, _ info: String) -> SymmetricKey {
            shared.hkdfDerivedSymmetricKey(using: SHA512.self, salt: Data(salt.utf8), sharedInfo: Data(info.utf8), outputByteCount: 32)
        }
        let key = derive("Pair-Verify-Encrypt-Salt", "Pair-Verify-Encrypt-Info")
        let mine = ephemeral.publicKey.rawRepresentation
        let signature = try signing.signature(for: mine + identifier + serverKey)
        let proof = try PairingTLV.encode([(1, identifier), (10, signature)])
        let box = try ChaChaPoly.seal(proof, using: key, nonce: .init(data: Data(repeating: 0, count: 4) + Data("PV-Msg03".utf8)))
        transmit = derive("", "ClientEncrypt-main"); receive = derive("", "ServerEncrypt-main")
        return try Self.pd(PairingTLV.encode([(6, Data([3])), (5, box.ciphertext + box.tag)]))
    }
    func seal(_ fields: [String: WS2OPACK.Value]) throws -> Data {
        guard let transmit else { throw Failure.bad }
        let plain = try WS2OPACK.encode(.dictionary(fields))
        let header = try WS2CompanionFrame.header(type: 8, count: plain.count + 16)
        let box = try ChaChaPoly.seal(plain, using: transmit, nonce: .init(data: tx.take()), authenticating: header)
        return box.ciphertext + box.tag
    }
    func open(_ frame: WS2CompanionFrame) throws -> WS2OPACK.Value {
        guard let receive else { throw Failure.bad }
        let header = try WS2CompanionFrame.header(type: frame.type, count: frame.payload.count)
        let box = try ChaChaPoly.SealedBox(nonce: .init(data: rx.take()), ciphertext: frame.payload.dropLast(16), tag: frame.payload.suffix(16))
        return try WS2OPACK.decode(ChaChaPoly.open(box, using: receive, authenticating: header))
    }
    enum Failure: Error { case bad }

    /// 在这条连接上走完 Pair-Verify。
    func verify(on link: Link) throws {
        link.push(5, try m1())
        guard let m2 = try link.frames().last, m2.type == 6 else { throw Failure.bad }
        link.push(6, try m3(after: m2))
    }
    func button(_ code: UInt64, _ state: UInt64, on link: Link) throws {
        link.push(8, try seal(["_i": .string("_hidC"), "_t": .uint(1), "_c": .dictionary(["_hidC": .uint(code), "_hBtS": .uint(state)])]))
    }
}

@MainActor final class Rig {
    let clock = TestClock()
    let store: Store
    let presenter = Presenter()
    let log = Log()
    var listeners: [Listener] = []
    var accept: ((any WS2RemoteLink) -> Void)?
    var ready: ((Bool) -> Void)?
    var storagesMade = 0
    var engine: FakeEngine?
    var pin = "4816"
    private(set) var host: WS2RemoteHost!
    init(receiptRequired: Bool = true, pairing: Bool = true) {
        store = Store(receiptRequired: receiptRequired)
        var environment = WS2RemoteHostEnvironment(clock: clock, makeStorage: { [unowned self] in self.storagesMade += 1; return self.store },
            makeListener: { [unowned self] _, _, accept, state in
                let listener = Listener(); self.listeners.append(listener); self.accept = accept; self.ready = state; return listener
            }, makePairSetupEngine: nil, macName: { "测试 Mac" })
        environment.makePIN = { [unowned self] in self.pin }
        if pairing {
            environment.makePairSetupEngine = { [unowned self] _, _ in
                guard let engine = self.engine else { throw Phone.Failure.bad }; return engine
            }
        }
        host = WS2RemoteHost(environment: environment, log: log)
        host.presenter = presenter
    }
    func connect() -> Link { let link = Link(); accept?(link); return link }
    /// 直接在存储里放好已配对的几台（模拟以前配过）。
    func preEnroll(_ phones: [Phone]) throws {
        let seed = Store(receiptRequired: false)
        let repo = WS2PeerRepository(storage: seed)
        try repo.provision(identifier: Data("MAC".utf8), signingSeed: Curve25519.Signing.PrivateKey().rawRepresentation)
        for phone in phones { _ = try repo.enroll(identifier: phone.identifier, publicKey: phone.publicKey) }
        store.bytes = seed.bytes
    }
    func on(conductor: Bool = false) { host.setEnabled(remote: true, conductor: conductor); ready?(true) }
}

@main struct RemoteHostLifecycleTests {
    @MainActor static func main() throws {
        var failures: [String] = [], assertions = 0, current = ""
        func scene(_ name: String) { current = name; print("SCENE \(name)") }
        func check(_ condition: Bool, _ why: String) {
            assertions += 1; if !condition { failures.append("\(current): \(why)"); print("FAIL \(why)") }
        }
        let m1 = try Phone.pd(PairingTLV.encode([(0, Data([0])), (6, Data([1]))]))
        let m3 = try Phone.pd(PairingTLV.encode([(6, Data([3])), (3, Data([2])), (4, Data(repeating: 1, count: 64))]))
        let m5 = try Phone.pd(PairingTLV.encode([(6, Data([5])), (5, Data(repeating: 1, count: 32))]))

        scene("L01 关着时没有 listener，也不读钥匙串")
        do {
            let rig = Rig()
            rig.host.setEnabled(remote: false, conductor: true)
            check(rig.listeners.isEmpty && rig.storagesMade == 0 && rig.store.reads == 0, "off creates nothing")
            check(!rig.host.isListening && rig.host.status == .off && rig.host.timerCount == 0, "off state")
            check(!rig.host.conductor.enabled, "conductor follows master switch")
        }

        scene("L02 打开才宣告监听；关掉停宣告、关连接、什么都不留")
        do {
            let rig = Rig()
            rig.host.setEnabled(remote: true, conductor: true)
            check(rig.listeners.count == 1 && rig.host.status == .starting && !rig.host.isListening, "listening requested")
            rig.ready?(true)
            check(rig.host.isListening && rig.host.conductor.enabled, "listening + conductor sub-item on")
            rig.host.setEnabled(remote: true, conductor: true)
            check(rig.listeners.count == 1, "idempotent re-apply")
            let link = rig.connect()
            check(link.started && link.deadlines.first == 2.5 && rig.host.connectionCount == 1, "accepted with 2.5 s limit")
            rig.host.setEnabled(remote: false, conductor: true)
            check(rig.listeners[0].cancelled && link.closedCause == .ownerStop && rig.host.connectionCount == 0, "all closed")
            check(!rig.host.isListening && rig.host.status == .off && !rig.host.conductor.enabled, "off")
            check(rig.presenter.announcements.isEmpty && rig.host.timerCount == 0, "quiet, no timers")
            let late = Link(); rig.accept?(late)
            check(late.closedCause == .ownerStop && rig.host.connectionCount == 0, "late accept refused")
        }

        scene("L03 仓库：持久存储没有回执就拒绝，且不封锁仓库")
        do {
            let store = Store(receiptRequired: true), repo = WS2PeerRepository(storage: store)
            try repo.provision(identifier: Data("MAC".utf8), signingSeed: Data(repeating: 7, count: 32))
            let key = Data(repeating: 4, count: 32)
            var denied = false
            do { _ = try repo.enroll(identifier: Data("a".utf8), publicKey: key) } catch WS2PeerRepository.Failure.denied { denied = true }
            check(denied && !repo.blocked && repo.snapshot?.peers.isEmpty == true, "no receipt denied")
            denied = false
            let other = WS2EnrollmentReceipt(consumedGrantFor: Data("b".utf8), publicKey: key)
            do { _ = try repo.enroll(identifier: Data("a".utf8), publicKey: key, receipt: other) } catch WS2PeerRepository.Failure.denied { denied = true }
            check(denied && !repo.blocked, "receipt for another phone denied")
            let good = WS2EnrollmentReceipt(consumedGrantFor: Data("a".utf8), publicKey: key)
            check((try? repo.enroll(identifier: Data("a".utf8), publicKey: key, receipt: good)) != nil, "matching receipt enrolls")
            try repo.revoke(identifier: Data("a".utf8))
            denied = false
            do { _ = try repo.enroll(identifier: Data("c".utf8), publicKey: key, receipt: good) } catch WS2PeerRepository.Failure.denied { denied = true }
            check(denied, "spent receipt cannot enroll anything else")
        }

        scene("L04 配对：卡片三行、Touch ID 回执之前不写钥匙串、配对码不进日志")
        do {
            let rig = Rig(); let phone = Phone("phone-1")
            rig.engine = FakeEngine(identifier: phone.identifier, publicKey: phone.publicKey)
            rig.on()
            let link = rig.connect()
            link.push(3, m1)
            check(rig.presenter.codes == ["4816"] && link.deadlines.last == 60, "code shown, 60 s window")
            link.push(4, m3); link.push(4, m5)
            check(rig.presenter.confirm != nil && rig.host.pairedPeers.isEmpty, "waits for Touch ID, nothing stored")
            let beforeConfirm = try link.frames().count
            rig.presenter.confirm?()
            let afterConfirm = try link.frames().count
            check(rig.presenter.authorization != nil && afterConfirm == beforeConfirm, "no M6 before receipt")
            rig.presenter.authorization?(WS2EnrollmentReceipt(consumedGrantFor: phone.identifier, publicKey: phone.publicKey))
            check(rig.host.pairedPeers.map(\.identifier) == [phone.identifier], "enrolled after receipt")
            let lastType = try link.frames().last?.type
            check(lastType == 4 && rig.presenter.cardHidden > 0, "M6 sent, card gone")
            // 配对后的第一条连接被拒：什么都不说。
            link.push(8, Data(repeating: 9, count: 40))
            check(link.closedCause == .protocolReject && rig.presenter.announcements.isEmpty, "first connection rejected silently")
            let logged = rig.log.lines.joined(separator: "\n")
            check(!logged.contains("4816") && !logged.contains("4 8 1 6") && !logged.contains("phone-1"), "no code or name in log")
            check(WS2RemoteCopy.spaced("4816") == "4 8 1 6", "spaced digits")
            // 重连走新鲜 Pair-Verify：只说一次“iPhone 已连接”，左耳出遥控器。
            let again = rig.connect()
            try phone.verify(on: again)
            check(rig.presenter.announcements == [WS2RemoteCopy.connected] && rig.presenter.activity.last == true, "connected once")
            check(rig.host.operatorIdentifier == phone.identifier, "operator set")
        }

        scene("L04b 配对后的同一条连接收到 Pair-Verify 也静默拒绝")
        do {
            let rig = Rig(); let phone = Phone("phone-1b")
            rig.engine = FakeEngine(identifier: phone.identifier, publicKey: phone.publicKey)
            rig.on()
            let link = rig.connect()
            link.push(3, m1); link.push(4, m3); link.push(4, m5)
            rig.presenter.confirm?()
            rig.presenter.authorization?(WS2EnrollmentReceipt(consumedGrantFor: phone.identifier, publicKey: phone.publicKey))
            check(rig.host.pairedPeers.count == 1, "enrolled")
            let sent = try link.frames().count
            link.push(5, Data(repeating: 9, count: 40))
            check(link.closedCause == .protocolReject && rig.presenter.announcements.isEmpty, "type-5 on enrolled connection rejected silently")
            check(try link.frames().count == sent, "nothing answered")
            let again = rig.connect()
            try phone.verify(on: again)
            check(rig.presenter.announcements == [WS2RemoteCopy.connected], "fresh reconnect still verifies")
        }

        scene("L05 取消之后晚到的成功不算；拒绝也不算")
        do {
            let rig = Rig(); let phone = Phone("phone-2")
            rig.engine = FakeEngine(identifier: phone.identifier, publicKey: phone.publicKey)
            rig.on()
            let link = rig.connect()
            link.push(3, m1); link.push(4, m3); link.push(4, m5)
            rig.presenter.confirm?()
            let late = rig.presenter.authorization
            rig.presenter.cancelCard?()
            late?(WS2EnrollmentReceipt(consumedGrantFor: phone.identifier, publicKey: phone.publicKey))
            check(rig.host.pairedPeers.isEmpty && link.closedCause != nil, "late success after cancel ignored")
            check(rig.log.lines.contains { $0.contains("late-confirmation-ignored") }, "logged as late")
            check(rig.presenter.announcements.isEmpty, "user cancel is quiet")
            rig.pin = "1357"
            let second = rig.connect()
            second.push(3, m1); second.push(4, m3); second.push(4, m5)
            rig.presenter.confirm?()
            rig.presenter.authorization?(nil)
            check(rig.host.pairedPeers.isEmpty && second.closedCause != nil, "declined Touch ID never enrolls")
            let third = rig.connect()
            third.push(3, m1); third.push(4, m3); third.push(4, m5)
            rig.presenter.confirm?()
            let wrong = Phone("someone-else")
            rig.presenter.authorization?(WS2EnrollmentReceipt(consumedGrantFor: wrong.identifier, publicKey: wrong.publicKey))
            check(rig.host.pairedPeers.isEmpty, "receipt for another phone never enrolls")
        }

        scene("L06 同一时间只有一台：第二台验签后也不收它的输入")
        do {
            let rig = Rig(); let a = Phone("phone-a"), b = Phone("phone-b")
            try rig.preEnroll([a, b]); rig.on(conductor: true)
            let la = rig.connect(); try a.verify(on: la)
            check(rig.host.operatorIdentifier == a.identifier, "first is operator")
            let lb = rig.connect(); try b.verify(on: lb)
            check(rig.presenter.announcements.last == WS2RemoteCopy.anotherPhone, "second told")
            check(lb.closedCause != nil && rig.host.operatorIdentifier == a.identifier, "second closed, first stays")
            let before = rig.log.lines.count
            lb.onFrame?(WS2CompanionFrame(type: 8, payload: Data(repeating: 0, count: 32)))
            check(rig.log.lines.count == before, "second's frames go nowhere")
            try a.button(1, 1, on: la); try a.button(1, 2, on: la)
            check(rig.log.lines.contains { $0.contains("remote effect action") }, "operator input reaches RemoteMode")
            check(!rig.log.lines.contains { $0.contains("focusUp") }, "effect parameters not logged")
            la.peerClosed()
            check(rig.presenter.announcements.last == WS2RemoteCopy.disconnected && rig.presenter.activity.last == false, "disconnect said")
        }

        scene("L07 锁屏清空：丢掉遥控输入、断开、不说断开；解锁不自动发、回到第 0 层")
        do {
            let rig = Rig(); let a = Phone("phone-lock")
            try rig.preEnroll([a]); rig.on(conductor: true)
            let link = rig.connect(); try a.verify(on: link)
            check(rig.host.remote.enabled, "remote input on")
            let spoken = rig.presenter.announcements.count
            rig.host.setLock("screen", locked: true)
            check(rig.host.conductor.locked && !rig.host.remote.enabled && rig.host.conductor.draft == nil, "locked and cleared")
            check(link.closedCause != nil && rig.host.connectionCount == 0, "dropped")
            check(rig.presenter.announcements.count == spoken, "no disconnect line while locked")
            let refused = rig.connect()
            check(refused.closedCause == .ownerStop, "no connections while locked")
            rig.host.setLock("screen", locked: false)
            check(!rig.host.conductor.locked && rig.host.remote.layer == .collapsed && !rig.host.remote.enabled, "unlock: layer 0, waits for reconnect")
            check(!rig.log.lines.contains { $0.contains("submitDraft") }, "nothing sent on unlock")
            rig.host.setLock("sleep", locked: true); rig.host.setLock("session", locked: true); rig.host.setLock("sleep", locked: false)
            check(rig.host.isLocked, "any reason keeps it locked")
        }

        scene("L08 没配过的 iPhone 验签失败：没连上")
        do {
            let rig = Rig(pairing: false); let stranger = Phone("stranger")
            try rig.preEnroll([]); rig.on()
            let link = rig.connect(); try stranger.verify(on: link)
            check(link.closedCause == .protocolReject && rig.presenter.announcements == [WS2RemoteCopy.notConnected], "not connected said")
            let probe = rig.connect()
            probe.push(3, m1)
            check(probe.closedCause != nil && rig.presenter.announcements.last == WS2RemoteCopy.pairingUnavailable, "no engine, no pairing")
        }

        scene("L09 移除：撤销配对、断开、提醒")
        do {
            let rig = Rig(); let a = Phone("phone-gone")
            try rig.preEnroll([a]); rig.on()
            let link = rig.connect(); try a.verify(on: link)
            check(rig.host.removePeer(identifier: a.identifier), "revoked")
            check(link.closedCause != nil && rig.host.pairedPeers.isEmpty, "disconnected, not listed")
            check(rig.presenter.announcements.last == WS2RemoteCopy.removed, "removed said")
            let back = rig.connect(); try a.verify(on: back)
            check(back.closedCause != nil && rig.host.operatorIdentifier == nil, "revoked phone cannot verify again")
        }

        print("RESULT assertions=\(assertions) failures=\(failures.count)")
        if !failures.isEmpty { for failure in failures { print("FAILURE \(failure)") }; exit(1) }
    }
}
