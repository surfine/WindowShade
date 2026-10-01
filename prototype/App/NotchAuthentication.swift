import Cocoa
import CryptoKit
import LocalAuthentication
import LocalAuthenticationEmbeddedUI

@MainActor protocol NotchInteractiveContent: AnyObject { var onCancel: (() -> Void)? { get set } }

/// One explicit, bound authorization transaction, presented by the existing island (docs/touch-id-island.md).
///
/// Success is not "evaluatePolicy returned true". It is: the native Touch ID view authenticated this request's
/// own LAContext, the Secure Enclave device key signed this request's canonical bytes with that same context
/// (no second prompt), and the ledger verified the signature and minted a one-time grant bound to the purpose
/// and target. Callers get the grant and must consume it against the target as it is at execution time.
@MainActor
final class NotchAuthenticationController {
    private weak var owner: NotchController?
    private weak var panel: NotchPanel?
    private let service: AuthorizationService
    private var context: LAContext?
    private var evaluating = false
    private var deadline: TimeInterval = 0
    private var presentation: NotchAuthenticationView?
    private var epoch = 0
    private var task: Task<Void, Never>?
    private var completion: ((AuthorizationGrant?) -> Void)?
    private var request: AuthRequest?
    private var target: AuthTarget?
    private var publicKey: P256.Signing.PublicKey?
    private var previousApplication: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    static let lifetime: TimeInterval = 30
    var isPresenting: Bool { presentation != nil }
    /// The single native evaluation for a request (KEY-05); replaced in tests.
    var evaluate: (LAContext, String, @escaping @Sendable (Bool, Error?) -> Void) -> Void = { context, reason, reply in
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason, reply: reply)
    }

    init(owner: NotchController, service: AuthorizationService? = nil) {
        self.owner = owner
        self.service = service ?? .shared
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel(animated: false, restoreFocus: false) } })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel(animated: false, restoreFocus: false) } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.evaluateIfReady() } })
    }

    /// Whether a confirmation can be shown at all right now: the island exists and Touch ID is set up.
    /// Callers that protect a change ask this first; when it's false there is nothing to confirm with.
    var canAuthorize: Bool {
        guard NotchController.isEnabled, owner?.authenticationPanel() != nil else { return false }
        let probe = LAContext()
        defer { probe.invalidate() }
        var error: NSError?
        return probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) && probe.biometryType == .touchID
    }

    /// Menu 「验证 Touch ID…」: create the device key if missing, sign once with Touch ID, verify. A diagnostic, not protection.
    func selfCheck() {
        guard let raw = try? service.key.prepare().rawRepresentation else { alert(AuthorizationCopy.unavailable); return }
        let target = AuthTarget.deviceKey(publicKeyRaw: Array(raw))
        authorize(target) { [weak self] grant in
            guard let self, let grant else { return }
            _ = self.service.consume(grant, purpose: .enrollDevice, currentTarget: target)
        }
    }

    /// Ask for Touch ID to confirm this concrete target. `completion` gets a one-time grant only after the
    /// signature verified; every other outcome (cancel, timeout, lock, sleep, wrong finger, stale) gets nil, once.
    func authorize(_ target: AuthTarget, completion: @escaping (AuthorizationGrant?) -> Void) {
        if isPresenting && context == nil { cancel(animated: false, restoreFocus: false) }
        guard !isPresenting else { completion(nil); return }
        guard let owner, NotchController.isEnabled, let panel = owner.authenticationPanel() else { completion(nil); return }
        guard !panel.isAuthenticating else { completion(nil); return }
        guard let publicKey = try? service.key.prepare() else {
            alert(AuthorizationCopy.unavailable, on: panel); completion(nil); return
        }
        let context = LAContext()
        context.localizedFallbackTitle = ""; context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              context.biometryType == .touchID,
              case .success(let request) = service.ledger.begin(target: target, ttl: UInt64(Self.lifetime * 1_000_000_000)) else {
            context.invalidate()
            alert(AuthorizationCopy.unavailable, on: panel)
            completion(nil); return
        }
        epoch += 1; let transaction = epoch
        deadline = ProcessInfo.processInfo.systemUptime + Self.lifetime
        let view = NotchAuthenticationView(context: context, reason: AuthorizationCopy.action(for: target))
        view.onCancel = { [weak self] in self?.cancel() }
        self.panel = panel; self.context = context; evaluating = false; self.presentation = view; self.completion = completion
        self.request = request; self.target = target; self.publicKey = publicKey
        previousApplication = NSWorkspace.shared.frontmostApplication
        panel.setAuthentication(view)
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.lifetime))
            guard !Task.isCancelled, let self, self.epoch == transaction else { return }
            self.cancel()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        evaluateIfReady()
    }

    private func evaluateIfReady() {
        // Activation can be asynchronous. Never evaluate while the embedded UI is invisible or inactive.
        guard !evaluating, NSApp.isActive, let context, let panel, panel.isVisible,
              presentation?.window === panel else { return }
        evaluating = true; let transaction = epoch
        evaluate(context, presentation?.reason ?? "") { [weak self] success, _ in
            Task { @MainActor [weak self] in self?.evaluated(success, transaction: transaction) }
        }
    }

    /// Native evaluation finished. On success, sign with the same context off the main thread.
    private func evaluated(_ success: Bool, transaction: Int) {
        guard isCurrent(transaction) else { return }
        guard success else { fail(AuthorizationCopy.notConfirmed(for:)); return }
        guard let context, let request else { return }
        let job = SigningJob(key: service.key, message: request.canonicalBytes(), context: context)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try job.key.sign(job.message, context: job.context) }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.signed(result, transaction: transaction) } }
        }
    }

    private func signed(_ result: Result<Data, Error>, transaction: Int) {
        guard isCurrent(transaction), let request, let publicKey else { return }
        task?.cancel(); task = nil; context?.invalidate(); context = nil
        let signature: Data
        switch result {
        case .success(let value): signature = value
        case .failure(let error):
            fail(error as? DeviceKeyError == .keyInvalidated ? { _ in AuthorizationCopy.fingerprintsChanged } : AuthorizationCopy.notConfirmed(for:))
            return
        }
        guard case .success(let grant) = service.ledger.complete(
            request, signature: signature, publicKey: publicKey, lock: service.lockState()) else {
            fail(AuthorizationCopy.notConfirmed(for:)); return
        }
        self.request = nil  // completed in the ledger; nothing left to cancel there
        let reply = completion; completion = nil
        presentation?.confirm()
        reply?(grant) // Authorization is never delayed until an animation finishes.
        guard epoch == transaction else { return }
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self, self.epoch == transaction else { return }
            self.cancel()
        }
    }

    /// Still this request, still in time, still on its visible host.
    private func isCurrent(_ transaction: Int) -> Bool {
        guard epoch == transaction, context != nil, evaluating else { return false }
        guard ProcessInfo.processInfo.systemUptime < deadline else { cancel(animated: false); return false }
        guard let panel, panel.isVisible, presentation?.window === panel else { cancel(animated: false); return false }
        return true
    }

    private func fail(_ message: (AuthTarget) -> String) {
        let host = panel, target = self.target
        cancel()
        if let host, let target { alert(message(target), on: host) }
    }

    private func alert(_ title: String, on host: NotchPanel? = nil) {
        guard let host = host ?? owner?.authenticationPanel() else { return }
        host.alert(.init(id: 0, icon: nil, title: title, subtitle: "", tone: .problem))
    }

    func cancel(animated: Bool = true, restoreFocus: Bool = true) {
        guard isPresenting || context != nil else { return }
        epoch += 1; task?.cancel(); task = nil
        context?.invalidate(); context = nil; evaluating = false
        if let request { service.ledger.cancel(requestID: request.requestID) }
        request = nil; target = nil; publicKey = nil
        let reply = completion; completion = nil
        panel?.setAuthentication(nil, animated: animated); panel?.resignKey()
        panel = nil; presentation = nil
        let previous = previousApplication; previousApplication = nil
        if restoreFocus, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let previous, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier, !previous.isTerminated {
            previous.activate(options: [])
        }
        reply?(nil)
    }

    func reconcile(panels: [NotchPanel]) {
        if let panel, !panels.contains(where: { $0 === panel }) { cancel(animated: false) }
    }
}

/// Values handed to the signing queue. The context is used there exactly once and then only invalidated on main.
private struct SigningJob: @unchecked Sendable {
    let key: ProtectedKeySigning
    let message: [UInt8]
    let context: LAContext
}

/// The fingerprint is the system's own embedded view; only purpose/cancel/result belong to us.
@MainActor
final class NotchAuthenticationView: NSView, NotchInteractiveContent {
    var onCancel: (() -> Void)?
    let reason: String
    private let native: LAAuthenticationView
    private let purpose = NSTextField(labelWithString: "")
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let check = NSImageView()
    private(set) var isConfirmed = false
    init(context: LAContext, reason: String) {
        self.reason = reason
        native = LAAuthenticationView(context: context, controlSize: .small)
        super.init(frame: .zero)
        wantsLayer = true; appearance = NSAppearance(named: .darkAqua)
        purpose.stringValue = reason
        purpose.textColor = .white; purpose.font = .systemFont(ofSize: 12, weight: .medium)
        purpose.lineBreakMode = .byTruncatingTail; purpose.maximumNumberOfLines = 2
        cancelButton.isBordered = false; cancelButton.bezelStyle = .inline
        cancelButton.font = .systemFont(ofSize: 11); cancelButton.contentTintColor = .white.withAlphaComponent(0.65)
        cancelButton.target = self; cancelButton.action = #selector(cancelRequest)
        cancelButton.keyEquivalent = "\u{1b}"
        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "已确认")
        check.contentTintColor = .white; check.isHidden = true
        for view in [native, purpose, cancelButton, check] { addSubview(view) }
        setAccessibilityLabel("WindowShade Touch ID 认证")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layout() {
        super.layout()
        native.frame = NSRect(x: 16, y: (bounds.height - 40) / 2, width: 40, height: 40)
        check.frame = NSRect(x: 22, y: (bounds.height - 24) / 2, width: 24, height: 24)
        purpose.frame = NSRect(x: 68, y: (bounds.height - 32) / 2, width: max(0, bounds.width - 134), height: 32)
        cancelButton.frame = NSRect(x: bounds.width - 60, y: (bounds.height - 26) / 2, width: 44, height: 26)
    }
    func confirm() {
        native.removeFromSuperview(); isConfirmed = true
        check.isHidden = false; purpose.stringValue = "已确认"; cancelButton.isHidden = true
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "已确认", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    @objc private func cancelRequest() { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
