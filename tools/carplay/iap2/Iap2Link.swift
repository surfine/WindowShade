import Foundation

// iAP2 链路层的最小实现：marker 探测、同步交换、带校验的数据包、控制会话（session 10）。
// 只做单出窗（发一包等一确认），认证交换每步一个来回，够用且状态少。
// 线格式（参考固定上游，实现原创）：FF 5A | u16 总长 | u8 控制 | u8 序号 | u8 确认 | u8 会话 | u8 校验 | 载荷 | u8 载荷校验
// marker 是 FF 55 02 00 EE 10；同步包控制位 0x80，数据 0x40。

struct Iap2Link {

    // MARK: 常量

    static let marker: [UInt8] = [0xff, 0x55, 0x02, 0x00, 0xee, 0x10]
    static let controlSessionId: UInt8 = 10
    static let headerBytes = 9
    static let checksumBytes = 1
    static let maxFrameBytes = 0xffff
    static let controlSynchronize: UInt8 = 0x80
    static let controlData: UInt8 = 0x40
    static let initialSequence: UInt8 = 99

    /// 同步载荷：版本 1、出窗、最大帧长、超时/重传参数、会话描述（id、kind、version 三元组）。
    struct Synchronization {
        var maxOutgoing: UInt8
        var maxFrameBytes: UInt16
        var sessions: [(id: UInt8, kind: UInt8, version: UInt8)]

        var encoded: [UInt8] {
            var out: [UInt8] = [1, maxOutgoing]
            out += Iap2Csm.be16(maxFrameBytes)
            out += Iap2Csm.be16(4000) // 重传超时 ms
            out += Iap2Csm.be16(500)  // 确认超时 ms
            out += [4, 3]             // 最大重传、最大累计确认
            for session in sessions { out += [session.id, session.kind, session.version] }
            return out
        }

        static func decode(_ bytes: [UInt8]) -> Synchronization? {
            guard bytes.count >= 10, bytes[0] == 1 else { return nil }
            func u16(_ offset: Int) -> UInt16 {
                UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            }
            var sessions: [(UInt8, UInt8, UInt8)] = []
            var offset = 10
            while offset + 3 <= bytes.count {
                sessions.append((bytes[offset], bytes[offset + 1], bytes[offset + 2]))
                offset += 3
            }
            return Synchronization(maxOutgoing: bytes[1], maxFrameBytes: u16(2), sessions: sessions)
        }

        /// 本端声明：控制会话（kind 0 v1）、EA（kind 2 v1）、文件传输（kind 1 v2），出窗 30。
        static func local() -> Synchronization {
            Synchronization(maxOutgoing: 30, maxFrameBytes: UInt16(Iap2Link.maxFrameBytes), sessions: [
                (controlSessionId, 0, 1),
                (11, 2, 1),
                (12, 1, 2),
            ])
        }
    }

    enum Event: Equatable {
        /// 控制会话（session 10）的一整个载荷。
        case control([UInt8])
        /// 链路协商完成，可以发 CSM 了。
        case ready
        case dead(String)
    }

    enum State: Equatable { case detecting, negotiating, running, dead }

    // MARK: 状态

    private(set) var state: State = .detecting
    /// 下一步要写给传输的字节；用完就清。
    private var outgoing: [UInt8] = []
    private var events: [Event] = []
    private var sentSequence: UInt8 = initialSequence
    private var lastReceivedInOrder: UInt8 = 0
    private var received = [UInt8]()
    private var peer: Synchronization?

    var peerSynchronization: Synchronization? { peer }

    // MARK: 生命周期

    /// 开始探测：发 marker，等对方 marker 或同步包。
    mutating func start() {
        guard state == .detecting else { return }
        outgoing += Self.marker
    }

    mutating func takeOutput() -> [UInt8] {
        defer { outgoing.removeAll() }
        return outgoing
    }

    mutating func pollEvent() -> Event? {
        guard !events.isEmpty else { return nil }
        return events.removeFirst()
    }

    /// 收到传输字节（任意分块）。解析出整包，逐包处理。
    mutating func feed(_ chunk: [UInt8]) {
        guard state != .dead else { return }
        received += chunk
        guard received.count <= Self.maxFrameBytes * 2 else {
            state = .dead
            events.append(.dead("接收缓冲超限"))
            return
        }
        while let packet = nextPacket() {
            handle(packet)
            guard state != .dead else { return }
        }
    }

    mutating func feedEof() {
        state = .dead
        events.append(.dead("传输结束"))
    }

    /// 发一个控制会话载荷：切成对方收得下的链路块，逐包递增序号。
    mutating func sendControl(_ payload: [UInt8]) {
        guard state == .running else { return }
        let chunkLimit = payloadLimit
        var offset = 0
        repeat {
            let end = min(offset + chunkLimit, payload.count)
            appendDataPacket(Array(payload[offset..<end]))
            offset = end
        } while offset < payload.count
    }

    // MARK: 内部

    private var payloadLimit: Int {
        let peerMax = Int(peer?.maxFrameBytes ?? UInt16(Self.maxFrameBytes))
        return max(1, min(peerMax, Self.maxFrameBytes) - Self.headerBytes - Self.checksumBytes)
    }

    private mutating func handle(_ packet: Packet) {
        switch packet.kind {
        case .marker:
            if state == .detecting {
                state = .negotiating
                // 对方 marker 到了，直接发同步（无线配件主动起同步）。
                appendSyncPacket()
            }
        case .sync:
            guard let sync = Synchronization.decode(packet.payload) else {
                state = .dead
                events.append(.dead("同步载荷解不开"))
                return
            }
            peer = sync
            if state != .running {
                state = .running
                events.append(.ready)
            }
        case .data:
            lastReceivedInOrder = packet.sequence
            if packet.session == Self.controlSessionId, !packet.payload.isEmpty {
                events.append(.control(packet.payload))
            }
            // 只有带载荷的包才回确认；纯确认包不回，避免互相确认死循环。
            if !packet.payload.isEmpty {
                appendAckPacket()
            }
        }
    }

    private mutating func appendSyncPacket() {
        outgoing += Self.encode(payload: Synchronization.local().encoded,
                                sequence: sentSequence,
                                control: Self.controlSynchronize,
                                session: 0,
                                acknowledgement: lastReceivedInOrder)
    }

    private mutating func appendDataPacket(_ payload: [UInt8]) {
        sentSequence &+= 1
        outgoing += Self.encode(payload: payload,
                                sequence: sentSequence,
                                control: Self.controlData,
                                session: Self.controlSessionId,
                                acknowledgement: lastReceivedInOrder)
    }

    private mutating func appendAckPacket() {
        outgoing += Self.encode(payload: nil,
                                sequence: sentSequence,
                                control: Self.controlData,
                                session: 0,
                                acknowledgement: lastReceivedInOrder)
    }

    private struct Packet {
        enum Kind { case marker, sync, data }
        var kind: Kind
        var sequence: UInt8
        var session: UInt8
        var payload: [UInt8]
    }

    /// 从缓冲解出一个完整链路包（或 marker）；垃圾与坏校验的字节跳过后继续找，找不到返回 nil 且不动缓冲。
    private mutating func nextPacket() -> Packet? {
        while !received.isEmpty {
            if received.starts(with: Self.marker) {
                received.removeFirst(Self.marker.count)
                return Packet(kind: .marker, sequence: 0, session: 0, payload: [])
            }
            guard received.count >= 2, received[0] == 0xff, received[1] == 0x5a else {
                received.removeFirst()
                continue
            }
            guard received.count >= Self.headerBytes else { return nil }
            let length = Int(Iap2Csm.be16At(received, 2))
            guard length >= Self.headerBytes, length <= Self.maxFrameBytes else {
                received.removeFirst()
                continue
            }
            guard received.count >= length else { return nil }
            let whole = Array(received[0..<length])
            guard Self.checksumValid(whole) else {
                received.removeFirst()
                continue
            }
            received.removeFirst(length)
            let control = whole[4]
            let sequence = whole[5]
            let session = whole[7]
            let payload = length > Self.headerBytes + Self.checksumBytes
                ? Array(whole[Self.headerBytes..<(length - Self.checksumBytes)])
                : []
            let kind: Packet.Kind = (control & Self.controlSynchronize) != 0 ? .sync : .data
            return Packet(kind: kind, sequence: sequence, session: session, payload: payload)
        }
        return nil
    }

    // MARK: 编码

    static func encode(payload: [UInt8]?, sequence: UInt8, control: UInt8, session: UInt8, acknowledgement: UInt8) -> [UInt8] {
        // 空载荷只有 9 字节头，没有载荷校验位（和上游一致）。
        let total = payload == nil ? Self.headerBytes : Self.headerBytes + payload!.count + Self.checksumBytes
        var out: [UInt8] = [0xff, 0x5a]
        out += Iap2Csm.be16(UInt16(total))
        out += [control, sequence, acknowledgement, session]
        var sum: UInt8 = 0
        for byte in out { sum &+= byte }
        out.append(0 &- sum) // 头校验：头 8 字节之和的补
        if let payload {
            out += payload
            var payloadSum: UInt8 = 0
            for byte in payload { payloadSum &+= byte }
            out.append(0 &- payloadSum)
        }
        return out
    }

    /// 全包按字节求和为 0（头校验 + 载荷校验的设计正好满足）。
    static func checksumValid(_ whole: [UInt8]) -> Bool {
        var sum: UInt8 = 0
        for byte in whole { sum &+= byte }
        return sum == 0
    }
}
