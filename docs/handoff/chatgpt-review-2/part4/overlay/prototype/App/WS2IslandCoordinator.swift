import Cocoa
/// Uses the existing NotchPanel. No overlay window, no parallel authorization UI.
@MainActor protocol WS2LeaseContent: NotchInteractiveContent {
    var inputIsCurrent: (() -> Bool) { get set }
    var interactionSize: NSSize { get }
    func revoke()
}
@MainActor final class WS2IslandCoordinator {
    private weak var owner: NotchController?
    private let clock: any WS2Clock
    private var view: (NSView & WS2LeaseContent)?
    private weak var panel: NotchPanel?
    private var handle: WS2.LeaseHandle?
    private var authHandle: WS2.LeaseHandle?
    private var dismissed: ((WS2.LeaseRevocation) -> Void)?
    private var deadlineTask: Task<Void,Never>?
    private var screenObserver: NSObjectProtocol?
    private lazy var leases = InteractionCoordinator(bootID: UUID(), clock: clock, environment: { [weak self] in
        .init(unlocked: self?.unlocked == true, displays: Set(NSScreen.screens.compactMap(Self.displayID)))
    }, cancel: { [weak self] lease, reason in self?.revoked(lease, reason: reason) })
    private var unlocked: Bool { NotchController.isEnabled && AuthorizationService.shared.lockState() == .unlocked }
    init(owner: NotchController, clock: any WS2Clock) {
        self.owner = owner; self.clock = clock
        owner.authentication.acquireInteraction = { [weak self] panel in self?.beginAuthorization(on: panel) ?? false }
        owner.authentication.releaseInteraction = { [weak self] in self?.endAuthorization() }
        owner.authentication.isInteractionCurrent = { [weak self] in
            guard let self, let lease = self.authHandle else { return false }; return self.leases.isCurrent(lease)
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.reconcileDisplays() } }
    }
    private static func displayID(_ screen: NSScreen) -> WS2.DisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { .init(value:$0.uint32Value) }
    }
    @discardableResult func show(_ content: NSView & WS2LeaseContent, ownerID: String, layer: WS2.Layer = .opened,
                                 onDismiss: @escaping (WS2.LeaseRevocation) -> Void = { _ in }) -> Bool {
        guard unlocked, owner?.authentication.isPresenting != true, let panel = owner?.authenticationPanel(),
              let screen = panel.screen ?? NSScreen.main, let display = Self.displayID(screen) else { return false }
        // Explicit user navigation replaces our old content; it never replaces native authentication.
        dismiss()
        let now = clock.now(), end = now.adding(120 * WS2.Duration.second)
        guard case .acquired(let lease) = leases.acquire(.init(ownerID:ownerID,display:display,layer:layer,
            requestedAt:now,deadline:end,containsPrivateContent:true)) else { return false }
        self.view = content; self.panel = panel; handle = lease; dismissed = onDismiss
        content.inputIsCurrent = { [weak self] in self?.leases.isCurrent(lease) == true }
        content.onCancel = { [weak self, weak content] in
            guard let content else { return }; self?.dismiss(ifShowing:content)
        }
        panel.setInteraction(content)
        panel.makeKeyAndOrderFront(nil)
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds:120 * WS2.Duration.second) } catch { return }
            guard let self, self.handle == lease else { return }
            _ = self.leases.snapshots(at:self.clock.now())
        }
        return true
    }
    /// Close the preview without reporting a cancellation to its approval host; Touch ID takes over next.
    func handOffToAuthorization() { dismissed = nil; dismiss() }
    func dismiss() { if let handle { leases.release(handle, at: clock.now()) } }
    func dismiss(ifShowing content: NSView) { if view === content { dismiss() } }
    func handOffToAuthorization(ifShowing content: NSView) -> Bool {
        guard view === content else { return false }; handOffToAuthorization(); return true
    }
    private func revoked(_ lease: WS2.LeaseHandle, reason: WS2.LeaseRevocation) {
        if handle == lease {
            let content = view, oldPanel = panel, callback = dismissed
            handle = nil; view = nil; panel = nil; dismissed = nil; deadlineTask?.cancel(); deadlineTask = nil
            content?.inputIsCurrent = { false }; content?.revoke()
            if let content, oldPanel?.isShowingInteraction(content) == true { oldPanel?.setInteraction(nil) }
            callback?(reason)
        }
        if authHandle == lease {
            authHandle = nil // clear before native cancel calls releaseInteraction again
            owner?.authentication.cancel(animated:false,restoreFocus:false)
        }
    }
    private func beginAuthorization(on panel: NotchPanel) -> Bool {
        guard unlocked, let screen = panel.screen ?? NSScreen.main, let display = Self.displayID(screen) else { return false }
        let now = clock.now()
        guard case .acquired(let lease) = leases.acquire(.init(ownerID:"authorization",display:display,layer:.authorization,
            requestedAt:now,deadline:now.adding(31 * WS2.Duration.second),containsPrivateContent:true)) else { return false }
        authHandle = lease; return true
    }
    private func endAuthorization() { if let authHandle { leases.release(authHandle,at:clock.now()) }; authHandle = nil }
    func invalidate(_ reason: WS2.LeaseRevocation) { leases.invalidate(reason,at:clock.now()) }
    private func reconcileDisplays() { _ = leases.snapshots(at:clock.now()) }
    func stop() {
        invalidate(.disabled)
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }; screenObserver = nil
        owner?.authentication.acquireInteraction = nil; owner?.authentication.releaseInteraction = nil
        owner?.authentication.isInteractionCurrent = nil
    }
}
