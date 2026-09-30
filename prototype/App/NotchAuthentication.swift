import Cocoa
import LocalAuthentication
import LocalAuthenticationEmbeddedUI

@MainActor protocol NotchInteractiveContent: AnyObject { var onCancel: (() -> Void)? { get set } }

/// A single, explicit application-authentication transaction, presented by the existing island.
@MainActor
final class NotchAuthenticationController {
    private weak var owner: NotchController?
    private weak var panel: NotchPanel?
    private var context: LAContext?
    private var evaluating = false
    private var deadline: TimeInterval = 0
    private var presentation: NotchAuthenticationView?
    private var epoch = 0
    private var task: Task<Void, Never>?
    private var completion: ((Bool) -> Void)?
    private var previousApplication: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    var isPresenting: Bool { presentation != nil }

    init(owner: NotchController) {
        self.owner = owner
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel(animated: false, restoreFocus: false) } })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel(animated: false, restoreFocus: false) } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.evaluateIfReady() } })
    }

    func authenticate(reason: String = "确认你正在使用 WindowShade。", completion: @escaping (Bool) -> Void = { _ in }) {
        if isPresenting && context == nil { cancel(animated: false, restoreFocus: false) }
        guard !isPresenting else { completion(false); return }
        guard let owner, NotchController.isEnabled, let panel = owner.authenticationPanel() else { completion(false); return }
        guard !panel.isAuthenticating else { completion(false); return }
        let context = LAContext()
        context.localizedFallbackTitle = ""; context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              context.biometryType == .touchID else {
            context.invalidate()
            panel.alert(.init(id: 0, icon: nil, title: "Touch ID 暂时不可用", subtitle: "", tone: .problem))
            completion(false); return
        }
        epoch += 1; let transaction = epoch
        deadline = ProcessInfo.processInfo.systemUptime + 30
        let view = NotchAuthenticationView(context: context, reason: reason)
        view.onCancel = { [weak self] in self?.cancel() }
        self.panel = panel; self.context = context; evaluating = false; self.presentation = view; self.completion = completion
        previousApplication = NSWorkspace.shared.frontmostApplication
        panel.setAuthentication(view)
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
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
        let reason = presentation?.reason ?? "确认你正在使用 WindowShade。"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, _ in
            Task { @MainActor [weak self] in self?.finish(success, transaction: transaction) }
        }
    }

    private func finish(_ success: Bool, transaction: Int) {
        guard epoch == transaction, context != nil, evaluating else { return }
        guard ProcessInfo.processInfo.systemUptime < deadline else { cancel(animated: false); return }
        guard let panel, panel.isVisible, presentation?.window === panel else { cancel(animated: false); return }
        task?.cancel(); task = nil; context?.invalidate(); context = nil
        let reply = completion; completion = nil
        if !success { cancel(); reply?(false); return }
        presentation?.confirm()
        reply?(true) // Authorization is never delayed until an animation finishes.
        guard epoch == transaction else { return }
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self, self.epoch == transaction else { return }
            self.cancel()
        }
    }

    func cancel(animated: Bool = true, restoreFocus: Bool = true) {
        guard isPresenting || context != nil else { return }
        epoch += 1; task?.cancel(); task = nil
        context?.invalidate(); context = nil; evaluating = false
        let reply = completion; completion = nil
        panel?.setAuthentication(nil, animated: animated); panel?.resignKey()
        panel = nil; presentation = nil
        let previous = previousApplication; previousApplication = nil
        if restoreFocus, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
           let previous, previous.processIdentifier != ProcessInfo.processInfo.processIdentifier, !previous.isTerminated {
            previous.activate(options: [])
        }
        reply?(false)
    }

    func reconcile(panels: [NotchPanel]) {
        if let panel, !panels.contains(where: { $0 === panel }) { cancel(animated: false) }
    }
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
