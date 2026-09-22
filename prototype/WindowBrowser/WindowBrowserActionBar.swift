// 卡片与列表行共用的紧凑操作条和操作按钮。

import Cocoa

// MARK: - 动作条

/// 操作条里的无边框符号按钮：悬停出现 6 pt 圆角的系统填充底（按下更深一级），
/// 与系统工具栏按钮的反馈一致。跟踪区域不依赖 key window（Dock 面板永远不是 key）。
final class WindowBrowserActionButton: NSButton {
    private var hovering = false
    private var trackingAreaRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        refreshBackground()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        refreshBackground()
    }

    override func mouseDown(with event: NSEvent) {
        refreshBackground(pressed: true)
        super.mouseDown(with: event)
        refreshBackground()
    }

    override var isEnabled: Bool {
        didSet { refreshBackground() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
    }

    private var hasBackground = false

    private func refreshBackground(pressed: Bool = false) {
        let visible = isEnabled && (pressed || hovering)
        // 静止按钮没有底：不解析颜色、不动图层（面板冷启动时成批创建按钮，这里要便宜）。
        guard visible || hasBackground else { return }
        hasBackground = visible
        wantsLayer = true
        guard visible else {
            layer?.backgroundColor = nil
            return
        }
        SystemCornerRadius.apply(to: self, radius: SystemCornerRadius.control)
        let fill: NSColor = pressed ? .tertiarySystemFill : .quaternarySystemFill
        layer?.backgroundColor = SystemAppearancePolicy.cgColor(fill, for: self)
    }
}

/// 紧凑操作条：只在悬停或键盘选中时显示符号按钮，空间始终预留。
final class WindowBrowserActionBar: NSView {
    weak var delegate: WindowBrowserItemDelegate?
    private(set) var windowKey: WindowKey?
    private var buttons: [NSButton] = []
    private var items: [WindowBrowserActionItem] = []
    /// 窗口有动作正在执行时，按钮前方显示一个小号转圈指示（其余动作按策略置灰）。
    private var busyIndicator: NSProgressIndicator?
    var buttonPointSize: CGFloat = 12
    var isBusy: Bool { busyIndicator != nil }

    /// 浮层样式：卡片上的操作按钮悬停时浮在画面右上角，需要一块圆角底托住符号，
    /// 让它在任意窗口画面上都清楚。底用窗口背景色（不透明度 0.9）+ 细边，不用玻璃。
    var overlayStyle = false {
        didSet { refreshOverlayBackground() }
    }
    /// 浮层四周的内边距（按钮与底托边缘之间）。
    static let overlayInset: CGFloat = 2

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshOverlayBackground()
    }

    private func refreshOverlayBackground() {
        wantsLayer = true
        guard overlayStyle else {
            layer?.backgroundColor = nil
            layer?.borderWidth = 0
            layer?.shadowOpacity = 0
            return
        }
        SystemCornerRadius.apply(to: self, radius: SystemCornerRadius.control + Self.overlayInset)
        layer?.backgroundColor = SystemAppearancePolicy.cgColor(
            NSColor.windowBackgroundColor.withAlphaComponent(0.9), for: self)
        layer?.borderColor = SystemAppearancePolicy.cgColor(NSColor.separatorColor, for: self)
        layer?.borderWidth = WindowBrowserSurfaceStyle.hairlineWidth(for: self)
    }

    override var isFlipped: Bool { true }

    /// 紧凑操作条末尾固定的“更多操作”入口：不随动作数量变化，始终可在
    /// 悬停/选中状态的一条里发现（右键菜单仍然是同一份菜单）。
    var showsMoreButton = true
    private(set) var moreButtonIdentifier = "window-browser-more"

    func configure(items: [WindowBrowserActionItem], key: WindowKey,
                   target: AnyObject, action: Selector, busy: Bool = false) {
        windowKey = key
        self.items = items
        for button in buttons { button.removeFromSuperview() }
        buttons.removeAll()
        setBusy(busy)
        for item in items {
            let button = WindowBrowserActionButton(title: "", target: target, action: action)
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.imagePosition = .imageOnly
            button.image = WindowBrowserSymbol.image(
                named: item.symbolName,
                accessibilityDescription: item.title,
                pointSize: buttonPointSize)
            if button.image == nil {
                button.title = item.title
                button.font = WindowBrowserTypography.control
            }
            button.isEnabled = item.isEnabled
            button.contentTintColor = item.isDestructive ? .systemRed
                : (item.isOn ? .controlAccentColor : nil)
            button.toolTip = item.disabledReason.map { "\(item.title)（\($0)）" } ?? item.title
            button.setAccessibilityLabel(item.title)
            if let reason = item.disabledReason {
                button.setAccessibilityHelp(reason)
            }
            button.identifier = NSUserInterfaceItemIdentifier(item.action.rawValue)
            addSubview(button)
            buttons.append(button)
        }
        // 溢出入口：始终放在末尾，像系统工具栏一样靠右。
        if showsMoreButton {
            let more = WindowBrowserActionButton(title: "", target: target, action: action)
            more.isBordered = false
            more.bezelStyle = .regularSquare
            more.imagePosition = .imageOnly
            more.image = WindowBrowserSymbol.image(named: "ellipsis",
                                                   accessibilityDescription: "更多操作",
                                                   pointSize: buttonPointSize)
            if more.image == nil { more.title = "更多" }
            more.toolTip = "更多操作（与右键菜单相同）"
            more.setAccessibilityLabel("更多操作")
            more.identifier = NSUserInterfaceItemIdentifier(moreButtonIdentifier)
            addSubview(more)
            buttons.append(more)
        }
    }

    func reset() {
        for button in buttons { button.removeFromSuperview() }
        buttons.removeAll()
        items.removeAll()
        setBusy(false)
        windowKey = nil
    }

    private func setBusy(_ busy: Bool) {
        if busy, busyIndicator == nil {
            let indicator = NSProgressIndicator()
            indicator.style = .spinning
            indicator.controlSize = .small
            indicator.isDisplayedWhenStopped = false
            indicator.setAccessibilityLabel("正在执行")
            addSubview(indicator)
            indicator.startAnimation(nil)
            busyIndicator = indicator
        } else if !busy, let indicator = busyIndicator {
            indicator.stopAnimation(nil)
            indicator.removeFromSuperview()
            busyIndicator = nil
        }
    }

    /// 放在强调色选中底上时，符号改用选中文字色（白），与系统列表一致；
    /// 开启态与危险动作保留各自的语义色以外，其余一律跟随。
    func setEmphasized(_ emphasized: Bool) {
        for (index, button) in buttons.enumerated() {
            let item = items.indices.contains(index) ? items[index] : nil
            let base: NSColor? = item.map { $0.isDestructive ? .systemRed
                : ($0.isOn ? .controlAccentColor : nil) } ?? nil
            button.contentTintColor = emphasized ? .alternateSelectedControlTextColor : base
        }
    }

    private var arrangedViews: [NSView] {
        (busyIndicator.map { [$0] } ?? []) + buttons
    }

    /// 按钮实际占用的宽度（28 pt 命中区 + 4 pt 间距；浮层样式再加两侧内边距）。
    var requiredWidth: CGFloat {
        let count = arrangedViews.count
        guard count > 0 else { return 0 }
        let inset = overlayStyle ? Self.overlayInset * 2 : 0
        return CGFloat(count) * 28 + CGFloat(count - 1) * 4 + inset
    }

    override func layout() {
        super.layout()
        let views = arrangedViews
        guard !views.isEmpty else { return }
        // 命中区 28 × 28（HIG：macOS 默认控件尺寸），按钮之间 4 pt。
        let spacing: CGFloat = 4
        let area = overlayStyle ? bounds.insetBy(dx: Self.overlayInset, dy: Self.overlayInset)
            : bounds
        let side = min(28, area.height)
        let width = min(28, max(18, (area.width - spacing * CGFloat(views.count - 1))
                                / CGFloat(views.count)))
        let total = width * CGFloat(views.count) + spacing * CGFloat(views.count - 1)
        var x = area.minX + max(0, area.width - total)
        let y = area.minY + floor((area.height - side) / 2)
        for view in views {
            if view === busyIndicator {
                let spin: CGFloat = 16
                view.frame = NSRect(x: x + (width - spin) / 2, y: y + (side - spin) / 2,
                                    width: spin, height: spin)
            } else {
                view.frame = NSRect(x: x, y: y, width: width, height: side)
            }
            x += width + spacing
        }
    }
}
