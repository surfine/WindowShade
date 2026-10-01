import Cocoa
import CryptoKit
import LocalAuthentication

@main enum NotchAuthenticationTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        NotchAuthenticationController.checkBoundGrants()
        print("PASS authentication: grants only after a verified signature (KEY-01..05), cancellation exactly once, stale callbacks rejected; no real Touch ID")
    }
}

/// Stand-in for the Secure Enclave key: a software P256 key that records how it was asked to sign.
final class FakeDeviceKey: ProtectedKeySigning, @unchecked Sendable {
    enum Mode { case good, wrongKey, fails, invalidated }
    var mode: Mode = .good
    let real = P256.Signing.PrivateKey()
    let other = P256.Signing.PrivateKey()
    var calls = 0
    var lastContext: LAContext?
    var publicKey: P256.Signing.PublicKey? { real.publicKey }
    func prepare() throws -> P256.Signing.PublicKey { real.publicKey }
    func sign(_ message: [UInt8], context: LAContext) throws -> Data {
        calls += 1; lastContext = context
        switch mode {
        case .good: return try real.signature(for: Data(message)).derRepresentation
        case .wrongKey: return try other.signature(for: Data(message)).derRepresentation
        case .fails: throw DeviceKeyError.signingFailed("test")
        case .invalidated: throw DeviceKeyError.keyInvalidated
        }
    }
}

// This test is appended to the production file by the harnesses, so no test hooks ship.
extension NotchAuthenticationController {
    @MainActor fileprivate static func checkBoundGrants() {
        let application = AppDelegate()
        let owner = NotchController(owner: application)
        let key = FakeDeviceKey()
        let service = AuthorizationService(ledger: AuthorizationLedger(), key: key)
        service.lockState = { .unlocked }
        let controller = NotchAuthenticationController(owner: owner, service: service)
        let screen = NSScreen.main!
        let host = NotchPanel(notch: NSRect(x: screen.frame.midX - 95, y: screen.frame.maxY - 24, width: 190, height: 24), virtual: true)
        let off = AuthTarget.setting("SUEnableAutomaticChecks", from: true, to: false)
        var replies: [AuthorizationGrant?] = []

        func stage(_ transaction: Int) -> LAContext {
            let context = LAContext()
            controller.epoch = transaction; controller.context = context; controller.panel = host
            controller.evaluating = true
            controller.deadline = ProcessInfo.processInfo.systemUptime + 30
            let view = NotchAuthenticationView(context: context, reason: AuthorizationCopy.action(for: off))
            controller.presentation = view
            host.setAuthentication(view, animated: false)
            guard case .success(let request) = service.ledger.begin(target: off, ttl: 30_000_000_000) else {
                preconditionFailure("ledger begin")
            }
            controller.request = request; controller.target = off; controller.publicKey = key.publicKey
            controller.completion = { replies.append($0) }
            return context
        }
        func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

        // Copy: the island line and the system reason name the concrete change, never "verify identity".
        precondition(AuthorizationCopy.action(for: off) == "关闭自动检查更新", "The purpose line names the exact change")
        precondition(AuthorizationCopy.notConfirmed(for: off) == "没有确认，自动检查更新仍然开着", "Failure says nothing changed")

        // KEY-04: the key needs this fingerprint set, and nothing falls back to the device password.
        precondition(AuthKeyPolicy.flags.contains(.biometryCurrentSet) && AuthKeyPolicy.flags.contains(.privateKeyUsage)
                     && !AuthKeyPolicy.flags.contains(.devicePasscode) && !AuthKeyPolicy.flags.contains(.userPresence)
                     && !AuthKeyPolicy.flags.contains(.or),
                     "KEY-04 the device key is bound to the current fingerprints with no password fallback")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let noKey = DeviceAuthorizationKey(directory: directory)
        let probeContext = LAContext()
        _ = try? noKey.sign([1, 2, 3], context: probeContext)
        precondition(probeContext.interactionNotAllowed, "KEY-05 the real key never lets signing raise a second prompt")

        // Success: a verified signature yields a grant that is consumable once for exactly this change.
        let context = stage(1)
        controller.evaluated(true, transaction: 1)
        pump()
        precondition(key.calls == 1 && key.lastContext === context,
                     "KEY-05 signing uses the very context the embedded view authenticated, once")
        precondition(replies.count == 1, "One reply per request")
        guard let grant = replies[0] else { preconditionFailure("A verified signature yields a grant") }
        precondition((controller.presentation?.isConfirmed ?? false), "The check mark appears only after verification")
        precondition(service.consume(grant, purpose: .changeSecurityPolicy, currentTarget: off) == nil
                     && service.consume(grant, purpose: .changeSecurityPolicy, currentTarget: off) == .alreadyConsumed,
                     "The grant authorizes this change exactly once")
        controller.cancel(animated: false, restoreFocus: false)
        precondition(replies.count == 1, "Tearing down after success does not reply again")

        // KEY-03: the system saying no means no signing and no grant.
        replies = []; key.calls = 0
        _ = stage(3)
        controller.evaluated(false, transaction: 3)
        pump()
        precondition(replies.count == 1 && replies[0] == nil && key.calls == 0 && !controller.isPresenting,
                     "KEY-03 a failed evaluation never reaches the key and yields nothing")
        precondition(service.ledger.pendingCount == 0, "and its request is withdrawn from the ledger")

        // KEY-01: evaluation succeeded, but the signature is not from the device key: no grant, no check mark.
        replies = []; key.mode = .wrongKey
        _ = stage(5)
        let wrongView = controller.presentation
        controller.evaluated(true, transaction: 5)
        pump()
        precondition(replies.count == 1 && replies[0] == nil && wrongView?.isConfirmed == false,
                     "KEY-01 capability plus a successful evaluation is not authorization; only the device key's signature is")

        // KEY-02: signing fails: request cancelled, nothing granted.
        for mode in [FakeDeviceKey.Mode.fails, .invalidated] {
            replies = []; key.mode = mode
            _ = stage(7)
            controller.evaluated(true, transaction: 7)
            pump()
            precondition(replies.count == 1 && replies[0] == nil && service.ledger.pendingCount == 0,
                         "KEY-02 a signing failure (\(mode)) cancels the request and grants nothing")
        }
        key.mode = .good

        // Cancellation replies once; a late success for a cancelled request does nothing (TXN-07).
        replies = []; key.calls = 0
        _ = stage(9)
        controller.cancel(animated: false, restoreFocus: false)
        controller.cancel(animated: false, restoreFocus: false)
        controller.evaluated(true, transaction: 9)
        pump()
        precondition(replies.count == 1 && replies[0] == nil && key.calls == 0 && controller.context == nil,
                     "Cancelled transaction replies once and never signs on a late success")

        // An old callback can't sign for, authorize or clear a newer request.
        replies = []
        let newer = stage(11)
        let newerView = controller.presentation
        controller.evaluated(true, transaction: 9)
        pump()
        precondition(controller.context === newer && controller.presentation === newerView && replies.isEmpty && key.calls == 0,
                     "Old callback can't authorize or clear the new request")

        // Removing the display cancels the pending request.
        controller.reconcile(panels: [])
        precondition(replies.count == 1 && replies[0] == nil && !controller.isPresenting && service.ledger.pendingCount == 0,
                     "Removing the display cancels and withdraws pending authentication")

        // Expired before the timeout task ran: rejected even after a successful evaluation.
        replies = []
        _ = stage(13)
        let expired = controller.presentation!
        controller.deadline = ProcessInfo.processInfo.systemUptime - 1
        controller.evaluated(true, transaction: 13)
        pump()
        precondition(replies.count == 1 && replies[0] == nil && !expired.isConfirmed && !controller.isPresenting,
                     "Expired success is rejected even if the timeout task has not run yet")

        // Locking or sleeping between signing and issuing revokes everything (TXN-06 through the service).
        replies = []
        _ = stage(15)
        service.lockState = { .locked }
        controller.evaluated(true, transaction: 15)
        pump()
        precondition(replies.count == 1 && replies[0] == nil, "No grant while the session is locked")
        service.lockState = { .unlocked }

        host.orderOut(nil)
        withExtendedLifetime((application, owner)) {}
    }
}
