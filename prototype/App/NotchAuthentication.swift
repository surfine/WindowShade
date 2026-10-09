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
    /// 这一次的指纹画面离开刘海时调一次（成功后对勾收走、取消、失败都算）。给了它，没确认的文案由调用方写在自己的卡上。
    private var gone: (() -> Void)?
    private var request: AuthRequest?
    private var target: AuthTarget?
    private var publicKey: P256.Signing.PublicKey?
    private var previousApplication: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    static let lifetime: TimeInterval = 30
    var isPresenting: Bool { presentation != nil }
    // Runtime assigns all three together. Nil preserves the legacy standalone diagnostic fixture.
    var acquireInteraction: ((NotchPanel) -> Bool)?
    var releaseInteraction: (() -> Void)?
    var isInteractionCurrent: (() -> Bool)?
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
    /// `whenGone`：画面真正离开刘海之后调（只在画面出现过时调）；调用方据此接上排在后面的下一件。
    func authorize(_ target: AuthTarget, whenGone: (() -> Void)? = nil,
                   completion: @escaping (AuthorizationGrant?) -> Void) {
        if isPresenting && context == nil { cancel(animated: false, restoreFocus: false) }
        guard !isPresenting else { completion(nil); return }
        guard let owner, NotchController.isEnabled, let panel = owner.authenticationPanel() else { completion(nil); return }
        if let acquireInteraction, !acquireInteraction(panel) { completion(nil); return }
        var adoptedInteraction = false
        defer { if !adoptedInteraction { releaseInteraction?() } }
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
        adoptedInteraction = true
        self.panel = panel; self.context = context; evaluating = false; self.presentation = view; self.completion = completion
        self.request = request; self.target = target; self.publicKey = publicKey; self.gone = whenGone
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
        // 助手审批这里不写“已允许”：应答还没送出，调用方拿到真回执后用 showReceipt 写。
        presentation?.confirm(target.flatMap(AuthorizationCopy.confirmation(for:)))
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
        if let isInteractionCurrent, !isInteractionCurrent() { cancel(animated:false,restoreFocus:false); return false }
        guard ProcessInfo.processInfo.systemUptime < deadline else { cancel(animated: false); return false }
        guard let panel, panel.isVisible, presentation?.window === panel else { cancel(animated: false); return false }
        return true
    }

    private func fail(_ message: (AuthTarget) -> String) {
        let host = panel, target = self.target, callerReports = gone != nil
        cancel()
        if !callerReports, let host, let target { alert(message(target), on: host) }
    }

    /// 调用方拿到这次请求的真回执后调：写在还亮着的那一行上并念出来。画面已经收走时，只有没成的才补一条提醒。
    func showReceipt(_ text: String, succeeded: Bool) {
        if let presentation, presentation.isConfirmed { presentation.showReceipt(text, succeeded: succeeded); return }
        if !succeeded { alert(text) }
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
        let left = gone; gone = nil
        panel?.setAuthentication(nil, animated: animated); panel?.resignKey()
        panel = nil; presentation = nil
        releaseInteraction?()
        let previous = previousApplication; previousApplication = nil
        if restoreFocus, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let previous, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier, !previous.isTerminated {
            previous.activate(options: [])
        }
        reply?(nil)
        left?()
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
    private let check = AuthorizationCheckmark()
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
        check.setAccessibilityLabel("已确认"); check.isHidden = true
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
    /// 对勾出现。`text` 为 nil 时那一行先不变，等调用方的真回执（showReceipt）。
    func confirm(_ text: String? = AuthorizationCopy.confirmed) {
        native.removeFromSuperview(); isConfirmed = true
        check.isHidden = false; check.pop(reduceMotion: Motion.reduced); cancelButton.isHidden = true
        if let text { purpose.stringValue = text; announce(text) }
    }
    func showReceipt(_ text: String, succeeded: Bool) {
        check.isHidden = !succeeded; purpose.stringValue = text; announce(text)
    }
    private func announce(_ text: String) {
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    @objc private func cancelRequest() { onCancel?() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// 授权对勾：用描边画出来。出现时 scale 0.9→1、opacity 0→1（0.18 秒）、描边从头画到尾；
/// 减少动态效果时只淡入。只在验签成功后由 confirm() 叫出，失败路径永远不画。
final class AuthorizationCheckmark: NSView {
    static let duration: CFTimeInterval = 0.18
    private let stroke = CAShapeLayer()
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        stroke.fillColor = nil
        stroke.strokeColor = NSColor.white.cgColor
        stroke.lineWidth = 2.4
        stroke.lineCap = .round; stroke.lineJoin = .round
        layer?.addSublayer(stroke)
        setAccessibilityElement(true); setAccessibilityRole(.image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func layout() {
        super.layout()
        stroke.frame = bounds
        let w = bounds.width, h = bounds.height
        let path = CGMutablePath()
        // layer 的 y 向上：短撇在左下，长捺向右上。
        path.move(to: CGPoint(x: w * 0.20, y: h * 0.50))
        path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.28))
        path.addLine(to: CGPoint(x: w * 0.80, y: h * 0.72))
        stroke.path = path
    }
    func pop(reduceMotion: Bool) {
        guard let layer else { return }
        layer.removeAllAnimations(); stroke.removeAllAnimations()
        let timing = CAMediaTimingFunction(name: .easeOut)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = Self.duration; fade.timingFunction = timing
        layer.add(fade, forKey: "check.fade")
        guard !reduceMotion else { return }
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0; draw.toValue = 1; draw.duration = Self.duration; draw.timingFunction = timing
        stroke.add(draw, forKey: "check.draw")
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.9; scale.toValue = 1
        scale.duration = Self.duration; scale.timingFunction = timing
        stroke.add(scale, forKey: "check.scale")
    }
}
