// 带到每张桌面：窗口不收起，留在它自己的桌面；别的桌面右上角出现它的一条卷帘条。
// 停在卷帘条上看一眼（画面从那张桌面实时抓过来），单击画面就回到那扇窗。
// 给一张桌面只放一个 App、靠触控板切桌面的人用：要瞄一眼另一张桌面上的资料，
// 不用滑过去再滑回来。
//
// 实测（macOS 27.0）：别的桌面上的 Safari、备忘录窗口开流后 86ms 拿到当前画面；
// 内容不变时系统只送状态帧。最小化或被隐藏的窗口拿不到画面，这时给带着时的截图。

import Cocoa

final class CarryStripPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "WindowShade 带到每张桌面"
        level = .floating
        // 每张桌面都在，包括全屏 App 的桌面；不进 ⌘` 的窗口轮换。
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        tabbingMode = .disallowed
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class CarryStripView: NSView {
    /// 右端“不再带着”按钮占的宽度：停在那里不开始看一眼。
    static let closeZoneWidth: CGFloat = 30

    var onClick: (() -> Void)?
    var onOpen: (() -> Void)?
    var onStop: (() -> Void)?

    private let material = SystemMaterialView(purpose: .floatingChrome)
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let stopButton = NSButton()

    init(frame: NSRect, appIcon: NSImage?, title: String) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        material.layer?.cornerRadius = 9
        addSubview(material)
        icon.image = appIcon
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)
        stopButton.bezelStyle = .regularSquare
        stopButton.isBordered = false
        stopButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                   accessibilityDescription: "不再带到每张桌面")
        stopButton.contentTintColor = .tertiaryLabelColor
        stopButton.toolTip = "不再带到每张桌面"
        stopButton.target = self
        stopButton.action = #selector(stopPressed)
        addSubview(stopButton)
        setTitle(title)
        layer?.borderWidth = SystemAppearancePolicy.edgeWidth(.current)
        layer?.borderColor = SystemAppearancePolicy.cgColor(NSColor.separatorColor, for: self)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp("停在上面看一眼，单击画面回到这个窗口")
    }

    required init?(coder: NSCoder) { nil }

    var appIconForMenu: NSImage? {
        guard let image = icon.image?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    func setTitle(_ title: String) {
        titleLabel.stringValue = title
        toolTip = title
        setAccessibilityLabel("带到每张桌面：\(title)")
    }

    override func layout() {
        super.layout()
        material.frame = bounds
        let side: CGFloat = 16
        icon.frame = NSRect(x: 9, y: floor((bounds.height - side) / 2), width: side, height: side)
        stopButton.frame = NSRect(x: bounds.width - 26, y: floor((bounds.height - 20) / 2),
                                  width: 20, height: 20)
        titleLabel.sizeToFit()
        let left = icon.frame.maxX + 7
        titleLabel.frame = NSRect(x: left, y: floor((bounds.height - titleLabel.frame.height) / 2),
                                  width: max(0, stopButton.frame.minX - 4 - left),
                                  height: titleLabel.frame.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        if event.clickCount >= 2 {
            onOpen?()
        } else {
            onClick?()
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onOpen else { return false }
        onOpen()
        return true
    }

    @objc private func stopPressed() {
        onStop?()
    }
}

/// 系统菜单入口，外层沿用卷帘条的非激活面板。
private final class CarryMoreView: NSView {
    let button = NSButton(title: "更多窗口", target: nil, action: nil)
    var onPress: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12)
        button.target = self
        button.action = #selector(pressed)
        button.setAccessibilityLabel("更多窗口")
        updateHelp(previewsEnabled: GlanceController.isEnabled)
        addSubview(button)
    }
    required init?(coder: NSCoder) { nil }
    func updateHelp(previewsEnabled: Bool) {
        let help = previewsEnabled ? "选择一个窗口看一眼，不切换桌面" : "选择一个窗口，显示它的卷帘条"
        button.toolTip = help
        button.setAccessibilityHelp(help)
    }
    override func layout() {
        super.layout()
        button.frame = bounds
        button.title = bounds.width >= 72 ? "更多窗口" : "•••"
    }
    @objc private func pressed() { onPress?() }
}

private final class CarryMenuSelection: NSObject {
    var id: CGWindowID?
    @objc func selectWindow(_ sender: NSMenuItem) {
        id = (sender.representedObject as? NSNumber)?.uint32Value
    }
}

@MainActor
final class CarryController: GlanceCarrySource {
    static let stripSize = CarryShelfLayout.stripSize

    private final class Carried {
        let id: CGWindowID
        let pid: pid_t
        let bundleID: String
        let appName: String
        var title: String
        let axWindow: AXUIElement
        var windowSize: CGSize
        let panel: CarryStripPanel
        let view: CarryStripView
        var snapshot: CGImage?

        init(id: CGWindowID, pid: pid_t, bundleID: String, appName: String, title: String,
             axWindow: AXUIElement, windowSize: CGSize, panel: CarryStripPanel, view: CarryStripView) {
            self.id = id
            self.pid = pid
            self.bundleID = bundleID
            self.appName = appName
            self.title = title
            self.axWindow = axWindow
            self.windowSize = windowSize
            self.panel = panel
            self.view = view
        }
    }

    unowned let owner: AppDelegate
    private var carried: [CGWindowID: Carried] = [:]
    private var order: [CGWindowID] = []
    private var timer: Timer?
    private var promotedID: CGWindowID?
    private var overflowIDs: [CGWindowID] = []
    private var morePanel: CarryStripPanel?
    private var moreView: CarryMoreView?
    /// 读系统状态的入口；测试只替换这些读取，不移动真实窗口。
    var sourceExists: (CGWindowID, pid_t) -> Bool = { cgWindowInfo($0) != nil && runningApp(pid: $1) != nil }
    var sourceIsOnScreen: (CGWindowID) -> Bool = { windowIsOnScreenNow($0) }
    var shelfVisibleFrame: () -> CGRect? = { NSScreen.screens.first?.visibleFrame }

    /// 探针：在窗口自己的桌面上也显示卷帘条（平时自己的桌面上不需要它）。
    var showsOnOwnDesktop = false

    init(owner: AppDelegate) {
        self.owner = owner
        owner.glance.carrySource = self
    }

    var carriedIDs: [CGWindowID] { order }

    func isCarried(_ id: CGWindowID) -> Bool { carried[id] != nil }

    func stripPanel(_ id: CGWindowID) -> NSPanel? { carried[id]?.panel }

    // MARK: 带上 / 放下

    /// 菜单与快捷键：当前窗口没带着就带上，带着就放下。
    func toggleCurrentWindow() {
        guard hasAccessibilityPermission() else {
            owner.quietNotice("需要辅助功能权限", log: "carry: accessibility missing")
            return
        }
        owner.pinnedPreviewController.refreshCurrentTarget(reason: "carry", force: true) {
            [weak self] target, _ in
            guard let self else { return }
            guard let target else {
                self.owner.quietNotice("没有可以带着的窗口", log: "carry: no focused window")
                return
            }
            if self.carried[target.windowID] != nil {
                self.stop(target.windowID, reason: "toggle")
            } else {
                self.carry(target.axWindow, id: target.windowID)
            }
        }
    }

    func carry(_ win: AXUIElement, id: CGWindowID) {
        guard carried[id] == nil else { return }
        guard owner.shaded[id] == nil else {
            owner.quietNotice("先展开这个窗口，再带到每张桌面", log: "carry: refused shaded id=\(id)")
            return
        }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        guard pid > 0, pid != getpid() else { return }
        let appName = appDisplayName(pid: pid)
        let title = descriptiveDisplayTitle(appName: appName, windowTitle: axTitle(win))
        let size = axSize(win) ?? cgWindowInfo(id).flatMap(cgWindowBounds)?.size ?? .zero
        guard size.width >= 80, size.height >= 60 else { return }
        let panel = CarryStripPanel(frame: NSRect(origin: .zero, size: Self.stripSize))
        let view = CarryStripView(frame: NSRect(origin: .zero, size: Self.stripSize),
                                  appIcon: runningApp(pid: pid)?.icon, title: title)
        panel.contentView = view
        let item = Carried(id: id, pid: pid, bundleID: appBundleID(pid: pid), appName: appName,
                           title: title, axWindow: win, windowSize: size, panel: panel, view: view)
        view.onClick = { [weak self] in self?.owner.glance.stripClicked(id) }
        view.onOpen = { [weak self] in self?.openCarriedWindow(id) }
        view.onStop = { [weak self] in self?.stop(id, reason: "strip-button") }
        carried[id] = item
        order.append(id)
        refreshVisibility(reason: "carry")
        refreshSnapshot(item)
        ensureTimer()
        owner.quietNotice("已带到每张桌面", log: "carry: start id=\(id) app=\(appName)")
        owner.rebuildMenu()
    }

    func stop(_ id: CGWindowID, reason: String) {
        guard let item = carried.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        if promotedID == id { promotedID = nil }
        owner.glance.detach(id: id)
        item.panel.orderOut(nil)
        layout()
        if carried.isEmpty {
            timer?.invalidate()
            timer = nil
        }
        wlog("carry: stop id=\(id) reason=\(reason)")
        owner.rebuildMenu()
    }

    func stopIfCarried(_ id: CGWindowID, reason: String) {
        if carried[id] != nil { stop(id, reason: reason) }
    }

    func stop(pid: pid_t, reason: String) {
        for id in order where carried[id]?.pid == pid { stop(id, reason: reason) }
    }

    // MARK: 位置与可见性

    /// 只为当前需要的卷帘条占位，溢出项从菜单访问。
    func layout() {
        let eligible = order.filter { id in
            guard let item = carried[id] else { return false }
            return sourceExists(id, item.pid) && (showsOnOwnDesktop || !sourceIsOnScreen(id))
        }
        if let promotedID, !eligible.contains(promotedID) { self.promotedID = nil }
        let plan = shelfVisibleFrame().map {
            CarryShelfLayout.compute(ids: eligible, visibleFrame: $0, promotedID: promotedID)
        } ?? CarryShelfLayout.Result()
        let frames = Dictionary(uniqueKeysWithValues: plan.strips.map { ($0.id, $0.frame) })
        for id in order {
            guard let item = carried[id] else { continue }
            guard let frame = frames[id] else {
                if item.panel.isVisible || owner.glance.hasSession(id) {
                    owner.glance.detach(id: id)
                    item.panel.orderOut(nil)
                }
                continue
            }
            let changed = !framesAlmostEqual(item.panel.frame, frame)
            let showing = !item.panel.isVisible
            if changed || showing {
                owner.glance.detach(id: id)
                item.panel.setFrame(frame, display: true)
                item.panel.orderFrontRegardless()
                owner.glance.attach(id: id, overlay: item.panel)
            }
        }
        overflowIDs = plan.overflow
        if let frame = plan.moreFrame, !overflowIDs.isEmpty {
            if morePanel == nil {
                let panel = CarryStripPanel(frame: frame)
                panel.title = "更多窗口"
                let view = CarryMoreView(frame: NSRect(origin: .zero, size: frame.size))
                view.onPress = { [weak self] in self?.showOverflowMenu() }
                panel.contentView = view
                morePanel = panel
                moreView = view
            }
            moreView?.updateHelp(previewsEnabled: GlanceController.isEnabled)
            morePanel?.setFrame(frame, display: true)
            if morePanel?.isVisible == false { morePanel?.orderFrontRegardless() }
        } else {
            morePanel?.orderOut(nil)
            morePanel = nil
            moreView = nil
        }
    }

    /// 先移除消失的来源，再一次性排布；不能把溢出项重新 orderFront。
    func refreshVisibility(reason: String) {
        for id in order {
            guard let item = carried[id] else { continue }
            if !sourceExists(id, item.pid) { stop(id, reason: "window-gone") }
        }
        layout()
    }

    private func makeOverflowMenu(selection: CarryMenuSelection) -> NSMenu {
        let menu = NSMenu(title: "更多窗口")
        menu.autoenablesItems = false
        for id in overflowIDs {
            guard let item = carried[id] else { continue }
            let entry = NSMenuItem(title: item.title, action: #selector(CarryMenuSelection.selectWindow(_:)),
                                   keyEquivalent: "")
            entry.target = selection
            entry.representedObject = NSNumber(value: id)
            entry.image = item.view.appIconForMenu
            entry.toolTip = GlanceController.isEnabled ? "看一眼" : "显示卷帘条"
            menu.addItem(entry)
        }
        return menu
    }

    private func showOverflowMenu() {
        guard let view = moreView else { return }
        owner.glance.cancelAll(reason: "carry-menu")
        let candidates = Dictionary(uniqueKeysWithValues: overflowIDs.compactMap { id in
            carried[id].map { (id, $0) }
        })
        let selection = CarryMenuSelection()
        let menu = makeOverflowMenu(selection: selection)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: view)
        // popUp 返回后菜单已关闭；等本轮输入结束，再交给预览。
        guard let id = selection.id, let item = candidates[id] else { return }
        DispatchQueue.main.async { [weak self] in self?.previewOverflowItem(id, expected: item) }
    }

    @discardableResult
    private func previewOverflowItem(_ id: CGWindowID, expected: Carried? = nil) -> Bool {
        guard let item = carried[id], expected == nil || item === expected,
              sourceExists(id, item.pid),
              showsOnOwnDesktop || !sourceIsOnScreen(id) else { return false }
        promotedID = id
        layout()
        guard item.panel.isVisible else { return false }
        owner.glance.previewFromMenu(id)
        return true
    }

    /// 换桌面：切换动画结束后窗口的在屏状态才准，稍后再核对一次。
    func activeSpaceChanged() {
        refreshVisibility(reason: "space")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.refreshVisibility(reason: "space-settled")
            for item in self.carried.values where !windowIsOnScreenNow(item.id) {
                self.refreshSnapshot(item)
            }
        }
    }

    private func ensureTimer() {
        guard timer == nil, !carried.isEmpty else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.periodicRefresh() }
        }
        timer.tolerance = 0.5
        self.timer = timer
    }

    private func periodicRefresh() {
        refreshVisibility(reason: "timer")
        for item in carried.values {
            let title = descriptiveDisplayTitle(appName: item.appName, windowTitle: axTitle(item.axWindow))
            if title != item.title {
                item.title = title
                item.view.setTitle(title)
            }
            if let size = cgWindowInfo(item.id).flatMap(cgWindowBounds)?.size,
               size.width >= 80, size.height >= 60 {
                item.windowSize = size
            }
        }
    }

    /// 留一张画面，实时画面拿不到时用（窗口被最小化或 App 被隐藏）。
    private func refreshSnapshot(_ item: Carried) {
        guard hasScreenRecordingPermission() else { return }
        let id = item.id
        let size = item.windowSize
        Task { @MainActor [weak self] in
            guard let self else { return }
            let image = await self.owner.captureWindow(id: id, axPos: .zero, size: size,
                                                       maxPixelSize: CGSize(width: 1600, height: 1100))
            if let image, let current = self.carried[id] { current.snapshot = image }
        }
    }

    // MARK: 看一眼

    func carriedStripFrame(_ id: CGWindowID) -> NSRect? {
        guard let panel = carried[id]?.panel, panel.isVisible else { return nil }
        return panel.frame
    }

    /// 卡片挂在卷帘条下面、隔一道缝、右边对齐；整扇窗按比例缩小，最宽占屏幕的七成。
    func glanceTarget(forCarried id: CGWindowID) -> GlanceTarget? {
        guard let item = carried[id], item.panel.isVisible else { return nil }
        let strip = item.panel.frame
        let visible = owner.visibleFrame(for: strip)
        let size = item.windowSize
        let gap = GlanceController.cardGap
        let maxWidth = visible.width * 0.72
        let maxHeight = strip.minY - gap - (visible.minY + 10)
        guard size.width > 0, size.height > 0, maxHeight >= 80 else { return nil }
        let scale = min(1, maxWidth / size.width, maxHeight / size.height)
        let cardSize = NSSize(width: floor(size.width * scale), height: floor(size.height * scale))
        var x = strip.maxX - cardSize.width
        x = max(visible.minX + 8, min(x, visible.maxX - 8 - cardSize.width))
        let card = NSRect(x: x, y: strip.minY - gap - cardSize.height,
                          width: cardSize.width, height: cardSize.height)
        let margin = GlanceContentView.shadowMargin
        let panel = NSRect(x: card.minX - margin, y: card.minY - margin,
                           width: card.width + 2 * margin, height: card.height + margin + gap)
        let radius = owner.glance.windowCornerRadius(id, snapshot: item.snapshot,
                                                     windowWidth: size.width) * scale
        return GlanceTarget(
            strip: strip, panel: panel, card: card.offsetBy(dx: -panel.minX, dy: -panel.minY),
            picture: NSRect(origin: .zero, size: cardSize), backdropArea: nil,
            cornerRadius: radius,
            source: hasScreenRecordingPermission() ? .stream : .snapshotOnly,
            snapshot: item.snapshot, pid: item.pid, bundleID: item.bundleID,
            accessibilityTitle: item.title, staleText: "不是实时画面")
    }

    /// 回到那扇窗：激活它的 App 并把窗口提到前面，系统会切到它所在的桌面。
    func openCarriedWindow(_ id: CGWindowID) {
        guard let item = carried[id] else { return }
        owner.glance.cancelAll(reason: "carry-open")
        let opened = Self.restoreForOpening(item.axWindow) {
            owner.bringRestoredWindowToFront(item.axWindow, pid: item.pid, reason: "carry-open id=\(id)")
        }
        if !opened { wlog("carry: failed to unminimize id=\(id)") }
    }

    /// 先退出最小化，再前置。注入 AX 操作可在不碰用户窗口的情况下验证失败分支。
    static func restoreForOpening(
        _ window: AXUIElement,
        isMinimized: (AXUIElement) -> Bool = { axBoolAttribute($0, kAXMinimizedAttribute as String) },
        unminimize: (AXUIElement) -> AXError = { setAXMinimizedReturningError($0, false) },
        bringForward: () -> Void
    ) -> Bool {
        if isMinimized(window), unminimize(window) != .success { return false }
        bringForward()
        return true
    }
}
