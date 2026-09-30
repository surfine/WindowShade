import Cocoa
import LocalAuthentication
import LocalAuthenticationEmbeddedUI
import QuartzCore

// Independent application-authentication preview. Never observes another app's requests.
@MainActor final class IslandPreview: NSView {
    private let capsule = CALayer()
    private let caption = NSTextField(labelWithString: "Touch ID")
    private let mark = NSImageView()
    private var authentication: LAAuthenticationView?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        appearance = NSAppearance(named: .darkAqua)
        capsule.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(capsule)
        caption.textColor = .white; caption.font = .systemFont(ofSize: 13, weight: .medium)
        caption.frame = NSRect(x: 104, y: 37, width: 195, height: 20)
        mark.frame = NSRect(x: 156, y: 30, width: 28, height: 28)
        mark.contentTintColor = .white
        addSubview(caption); addSubview(mark)
        reset(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    private func shape(expanded: Bool, animated: Bool) {
        let oldWidth = (capsule.presentation() ?? capsule).bounds.width
        CATransaction.begin(); CATransaction.setDisableActions(true)
        capsule.removeAllAnimations()
        capsule.bounds = CGRect(x: 0, y: 0, width: expanded ? 316 : 56, height: 56)
        capsule.position = CGPoint(x: 170, y: 44); capsule.cornerRadius = 28
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let spring = CASpringAnimation(perceptualDuration: 0.28, bounce: 0.02)
            spring.keyPath = "bounds.size.width"; spring.fromValue = oldWidth
            spring.toValue = capsule.bounds.width; spring.duration = spring.settlingDuration
            capsule.add(spring, forKey: "shape")
        }
        CATransaction.commit()
    }
    func begin(_ context: LAContext) {
        authentication?.removeFromSuperview()
        let native = LAAuthenticationView(context: context, controlSize: .small)
        native.frame = NSRect(x: 45, y: 20, width: 48, height: 48)
        addSubview(native); authentication = native
        caption.stringValue = "确认这次动画体验"; caption.isHidden = false; mark.isHidden = true
        shape(expanded: true, animated: true)
    }
    func confirmed() {
        authentication?.removeFromSuperview(); authentication = nil
        caption.stringValue = "已确认"
        mark.frame.origin.x = 55
        mark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "已确认")
        mark.isHidden = false; caption.isHidden = false
        shape(expanded: true, animated: true)
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: "已确认", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
    func reset(animated: Bool = true) {
        authentication?.removeFromSuperview(); authentication = nil
        caption.isHidden = true; mark.isHidden = false
        mark.frame.origin.x = 156
        mark.image = NSImage(systemSymbolName: "touchid", accessibilityDescription: "Touch ID 动画小样")
        shape(expanded: false, animated: animated)
    }
}

@MainActor final class Demo: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 260),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let island = IslandPreview(frame: NSRect(x: 70, y: 118, width: 340, height: 88))
    private let status = NSTextField(labelWithString: "仅体验本应用认证，不会解锁 Mac。")
    private let start = NSButton(title: "体验 Touch ID 动画", target: nil, action: nil)
    private let cancel = NSButton(title: "取消", target: nil, action: nil)
    private var context: LAContext?
    private var epoch = 0
    private var timeout: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        window.title = "Touch ID 动画小样"; window.delegate = self; window.isReleasedWhenClosed = false
        guard let host = window.contentView else { return }
        host.addSubview(island)
        status.frame = NSRect(x: 24, y: 84, width: 432, height: 20)
        status.alignment = .center; host.addSubview(status)
        start.frame = NSRect(x: 117, y: 32, width: 174, height: 32)
        start.bezelStyle = .rounded; start.target = self; start.action = #selector(authenticate)
        cancel.frame = NSRect(x: 300, y: 32, width: 64, height: 32)
        cancel.bezelStyle = .rounded; cancel.target = self; cancel.action = #selector(cancelRequest)
        cancel.keyEquivalent = "\u{1b}"; cancel.isEnabled = false
        host.addSubview(start); host.addSubview(cancel)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancelRequest() } })
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"),
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancelRequest() } })
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func authenticate() {
        guard context == nil else { return }
        let request = LAContext(); request.localizedFallbackTitle = ""
        request.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard request.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
              request.biometryType == .touchID else {
            status.stringValue = "Touch ID 暂时不可用。"; request.invalidate(); return
        }
        epoch += 1; let transaction = epoch
        context = request; start.isEnabled = false; cancel.isEnabled = true
        status.stringValue = "请将手指放在 Touch ID 上。"
        // Attach the system view before evaluation, avoiding the standard authentication alert.
        island.begin(request)
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.epoch == transaction else { return }
            self.cancelRequest()
        }
        request.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "确认这次 Touch ID 动画体验。") { [weak self] success, _ in
            Task { @MainActor [weak self] in self?.complete(success, transaction: transaction) }
        }
    }
    private func complete(_ success: Bool, transaction: Int) {
        guard epoch == transaction, context != nil else { return }
        timeout?.cancel(); timeout = nil
        context?.invalidate(); context = nil; cancel.isEnabled = false
        guard success else {
            island.reset(); start.isEnabled = true
            status.stringValue = "未完成确认，可重新尝试。"; return
        }
        island.confirmed(); status.stringValue = "本应用已确认。"
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, let self, self.epoch == transaction else { return }
            self.island.reset(); self.start.isEnabled = true; self.timeout = nil
        }
    }
    @objc private func cancelRequest() {
        epoch += 1; timeout?.cancel(); timeout = nil
        context?.invalidate(); context = nil
        island.reset(); start.isEnabled = true; cancel.isEnabled = false
        status.stringValue = "已取消。"
    }
    func applicationDidResignActive(_ notification: Notification) { if context != nil { cancelRequest() } }
    func windowWillClose(_ notification: Notification) { cancelRequest(); NSApp.terminate(nil) }
}

let mode = CommandLine.arguments.dropFirst().first ?? "--check"
guard ["--check", "--ui"].contains(mode) else { fatalError("Use --check or --ui") }
let app = NSApplication.shared
if mode == "--check" {
    MainActor.assumeIsolated {
        let context = LAContext(); var error: NSError?
        let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let native = LAAuthenticationView(context: context, controlSize: .small)
        let preview = IslandPreview(frame: NSRect(x: 0, y: 0, width: 340, height: 88))
        preview.begin(context); preview.reset(animated: false)
        print("PASS native embedded view construction/reset; Touch ID available=\(available && context.biometryType == .touchID); no evaluation requested; view=\(type(of: native))")
        context.invalidate()
    }
} else {
    MainActor.assumeIsolated {
        let demo = Demo(); app.setActivationPolicy(.regular); app.delegate = demo
        app.run(); withExtendedLifetime(demo) {}
    }
}
