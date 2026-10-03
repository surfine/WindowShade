// 内部已认证事件总线。不是 Companion 网络帧，更不能把 plaintext 接到这里。
import Foundation
struct RemoteEventRouter: Sendable {
    enum Event: Equatable, Sendable { case touch(String,Double,Double), button(String,String), clickOnly(String), cancel }
    enum Failure: Error { case unverified, revoked, stale, gap, malformed, exhausted }
    struct Session: Equatable, Sendable { let peer: String; let epoch: UInt64; let keyRevision: UInt64 }
    private(set) var session: Session?
    private var nextSequence: UInt64 = 0
    private var invalidated = false
    // 仅 D5b 验证客户端签名、登记公钥与加密通道之后调用；UI 层不得签发 session。
    mutating func begin(_ value: Session) throws {
        guard !invalidated, session == nil, !value.peer.isEmpty, value.peer.utf8.count <= 256,
              value.epoch > 0, value.keyRevision > 0 else { throw Failure.unverified }
        session = value; nextSequence = 0
    }
    mutating func route(_ event: Event, session expected: Session, sequence: UInt64) throws -> Event {
        guard !invalidated, let session, expected == session else { throw Failure.unverified }
        guard sequence == nextSequence else { invalidate(); throw Failure.stale }
        switch event {
        case .touch(let phase,let x,let y):
            guard ["begin","move","end","cancel"].contains(phase), x.isFinite,y.isFinite,(0...1).contains(x),(0...1).contains(y) else { invalidate(); throw Failure.malformed }
        case .button(let id,let phase):
            guard Self.buttons.contains(id),["down","up","cancel"].contains(phase) else { invalidate(); throw Failure.malformed }
        case .clickOnly(let id): guard Self.buttons.contains(id) else { invalidate(); throw Failure.malformed }
        case .cancel: break
        }
        guard nextSequence < .max else { invalidate(); throw Failure.exhausted }
        nextSequence += 1; return event
    }
    mutating func invalidate() { session = nil; invalidated = true }
    static let buttons: Set<String> = ["tv","playPause","back","mute","power","side"]
}
