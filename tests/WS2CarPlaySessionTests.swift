import Foundation

@main struct WS2CarPlaySessionTests {
    static func main() {
        var session = WS2CarPlaySession()
        precondition(session.connect(identityAvailable: false) == nil)
        session.enterFullscreen()
        precondition(session.state == .missingIdentity && !session.isFullscreen)
        let old = session.connect(identityAvailable: true)!
        session.becameReady(old)
        session.enterFullscreen()
        session.exitFullscreen()
        precondition(session.state == .ready && session.ticket == old && !session.isFullscreen)
        let current = session.connect(identityAvailable: true)!
        session.becameReady(current)
        session.enterFullscreen()
        session.ended(old, failed: true)
        precondition(session.state == .ready && session.ticket == current && session.isFullscreen)
        session.disconnect()
        session.becameReady(current)
        session.ended(current, failed: true)
        precondition(session.state == .disconnected && session.ticket == nil)
        let third = session.connect(identityAvailable: true)!
        session.ended(third, failed: true)
        session.becameReady(third)
        precondition(session.state == .failed)
        _ = session.connect(identityAvailable: false)
        session.becameReady(old)
        precondition(session.state == .missingIdentity)
        print("PASS CarPlay: missing identity, stale end, stale ready, failure, desktop exit, disconnect")
    }
}
