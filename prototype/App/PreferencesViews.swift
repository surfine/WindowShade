// 设置页用到的独立控件与看护："之前常用"分段、快捷键录制、按通知重画一行的容器、等辅助功能打开的看护。

import Cocoa
import Carbon.HIToolbox

final class SwitcherOriginControl: NSSegmentedControl {
    /// 分段标题（第31批）：名字统一走 SwitcherOrigin.titleText（和欢迎窗口第二步、刘海问来处同一份）。
    static func localizedTitles() -> [String] {
        SwitcherOrigin.answers.compactMap(\.titleText)
    }

    static func make() -> SwitcherOriginControl {
        let control = SwitcherOriginControl(labels: localizedTitles(),
                                            trackingMode: .selectOne, target: nil, action: nil)
        control.target = control
        control.action = #selector(picked)
        control.setAccessibilityLabel(WSL10n.text("settings.shade.origin.name", zh: "之前常用"))
        control.showCurrent()
        NotificationCenter.default.addObserver(control, selector: #selector(showCurrent),
                                               name: SwitcherOrigin.didChangeNotification, object: nil)
        return control
    }

    @objc private func picked() {
        guard SwitcherOrigin.answers.indices.contains(selectedSegment) else { return }
        SwitcherOrigin.current = SwitcherOrigin.answers[selectedSegment]
    }

    @objc private func showCurrent() {
        if let at = SwitcherOrigin.answers.firstIndex(of: SwitcherOrigin.current) {
            selectedSegment = at
        } else {
            for segment in 0..<segmentCount { setSelected(false, forSegment: segment) }
        }
    }
}

/// 快捷键记录器：只在设置页明确聚焦时读取键盘事件，不安装任何全局监听。
final class HotKeyRecorderView: NSControl {
    typealias HotKey = WindowBrowserSettings.HotKey
    var onCapture: ((HotKey?) -> Void)?
    /// 录到的组合不能用时返回原因（显示在标签里）；能用返回 nil。
    var validate: ((HotKey) -> String?)?
    private let label = NSTextField(labelWithString: WSL10n.text("settings.shortcuts.notSet", zh: "未设置"))
    private let recordButton = NSButton(title: WSL10n.text("settings.shortcuts.record", zh: "录制…"), target: nil, action: nil)
    private let clearButton = NSButton(title: WSL10n.text("settings.shortcuts.clear", zh: "清除"), target: nil, action: nil)
    private var current: HotKey?
    private var recording = false
    private var messageWork: DispatchWorkItem?

    init(accessibilityName: String) {
        super.init(frame: .zero)
        label.font = WindowBrowserTypography.monospacedDigits
        label.lineBreakMode = .byTruncatingTail
        for button in [recordButton, clearButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
        }
        recordButton.target = self
        recordButton.action = #selector(beginRecording)
        clearButton.target = self
        clearButton.action = #selector(clearHotKey)
        for view in [label, recordButton, clearButton] { addSubview(view) }
        widthAnchor.constraint(equalToConstant: 280).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(accessibilityName)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    func configure(current: HotKey?) {
        self.current = current
        messageWork?.cancel()
        showText(current.map { WindowBrowserSettings.displayName(for: $0) } ?? WSL10n.text("settings.shortcuts.notSet", zh: "未设置"))
        clearButton.isEnabled = current != nil
    }

    private func showText(_ text: String) {
        label.stringValue = text
        label.toolTip = text
        setAccessibilityValue(text)
        needsLayout = true
    }

    /// 录到不能用的组合：提示音 + 标签里说明原因，1.8 秒后回到当前组合。
    private func reject(_ message: String) {
        shadeSounds.beep()
        showText(message)
        messageWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.configure(current: self.current)
        }
        messageWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    override func layout() {
        super.layout()
        clearButton.frame = NSRect(x: bounds.width - 56, y: (bounds.height - 24) / 2,
                                   width: 56, height: 24)
        recordButton.frame = NSRect(x: bounds.width - 56 - 6 - 64,
                                    y: (bounds.height - 24) / 2, width: 64, height: 24)
        label.frame = NSRect(x: 0, y: (bounds.height - 16) / 2,
                             width: max(60, recordButton.frame.minX - 8), height: 16)
    }

    @objc private func beginRecording() {
        recording = true
        messageWork?.cancel()
        showText(WSL10n.text("settings.shortcuts.pressKeys", zh: "请按快捷键…"))
        window?.makeFirstResponder(self)
    }

    @objc private func clearHotKey() {
        recording = false
        onCapture?(nil)
    }

    override func resignFirstResponder() -> Bool {
        if recording {
            recording = false
            configure(current: current)
        }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            recording = false
            configure(current: current)
            return
        }
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    private func capture(_ event: NSEvent) {
        // 只按修饰键不构成快捷键：保持录制状态，等真正的键。
        guard !WindowBrowserSettings.isModifierOnlyKeyCode(event.keyCode) else { return }
        recording = false
        let hotKey = HotKey(keyCode: UInt32(event.keyCode),
                            modifiers: Self.carbonModifiers(from: event.modifierFlags))
        if WindowBrowserSettings.isReserved(hotKey) {
            let hasControlOrOption = hotKey.modifiers & UInt32(controlKey | optionKey) != 0
            reject(hasControlOrOption ? WSL10n.text("settings.shortcuts.reject.systemInUse", zh: "系统在用这个组合") : WSL10n.text("settings.shortcuts.reject.needsModifier", zh: "组合里要有 ⌃ 或 ⌥"))
            return
        }
        if let message = validate?(hotKey) {
            reject(message)
            return
        }
        onCapture?(hotKey)
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}


/// 装着"有人在看时收起私人窗口"那一行；私人 App 名单一变就按最新名单重画，不用重进页面。
/// 装着设置页的一行；对应通知一到（名单变了、开关状态变了）就按最新状态重画整行，不用重进页面。
/// 视图没了就把自己的监听摘掉；摘的时机是下一次通知。
@MainActor final class NotificationReloadHost: NSStackView {
    private let build: () -> NSView
    init(name: Notification.Name, build: @escaping () -> NSView) {
        self.build = build
        super.init(frame: .zero)
        orientation = .vertical; spacing = 0; alignment = .leading
        place(build())
        let token = ObserverToken()
        token.value = NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    if let value = token.value { NotificationCenter.default.removeObserver(value) }
                    return
                }
                self.reload()
            }
        }
    }
    private final class ObserverToken: @unchecked Sendable { var value: NSObjectProtocol? }
    private func place(_ row: NSView) {
        addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    required init?(coder: NSCoder) { nil }
    private func reload() {
        for view in arrangedSubviews { removeArrangedSubview(view); view.removeFromSuperview() }
        place(build())
    }
}

/// 点"允许…"之后等你在系统设置里打开辅助功能：设置窗口在前台时每 1 秒看一次，最多 2 分钟；
/// 窗口不在前台就停，回到前台再看一次、接着数；不在后台轮询。允许了就马上装监听，不用重开。
@MainActor final class LevelAllowWatcher {
    static let shared = LevelAllowWatcher()
    private var watch: NotchLevelAllowWatch?
    private var timer: Timer?
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func start(window: NSWindow?) {
        finish()
        self.window = window
        watch = NotchLevelAllowWatch(startedAt: now)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        })
        if let window {
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            })
        }
        evaluate()
    }

    private func evaluate() {
        guard let watch else { return }
        let inFront = window.map { $0.isVisible && $0.isKeyWindow && NSApp.isActive } ?? false
        switch watch.step(now: now, trusted: hasAccessibilityPermission(), windowInFront: inFront) {
        case .allowed:
            finish()
            (NSApp.delegate as? AppDelegate)?.notch.installLevelTapIfAllowed()
            NotificationCenter.default.post(name: NotchLevelSetting.didChange, object: nil)
        case .expired:
            finish()
        case .paused:
            stopTimer()
        case .waiting:
            guard timer == nil else { return }
            let next = Timer.scheduledTimer(withTimeInterval: NotchLevelAllowWatch.interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
            next.tolerance = NotchLevelAllowWatch.interval / 4
            RunLoop.main.add(next, forMode: .common)
            timer = next
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func finish() {
        stopTimer()
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
        watch = nil
        window = nil
    }
}


/// 垂直设置页栈：钉在给定 root 四边、顶对齐不满挤。设置页（spacing 6）与效果页（14、.fill）共用。
func makeSettingsStack(
    in root: NSView, spacing: CGFloat, distribution: NSStackView.Distribution = .gravityAreas
) -> NSStackView {
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.distribution = distribution
    stack.spacing = spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        stack.topAnchor.constraint(equalTo: root.topAnchor),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor),
    ])
    return stack
}

// 设置页与效果页共用的装配尾奏：入栈即钉满宽（可带后续间距）、只入栈带间距。
extension NSStackView {
    @discardableResult
    func addFullWidth(_ view: NSView, spacing: CGFloat? = nil) -> NSView {
        addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        if let spacing { setCustomSpacing(spacing, after: view) }
        return view
    }

    @discardableResult
    func addSpaced(_ view: NSView, spacing: CGFloat) -> NSView {
        addArrangedSubview(view)
        setCustomSpacing(spacing, after: view)
        return view
    }
}
