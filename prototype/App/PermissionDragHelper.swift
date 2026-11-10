// 打开「隐私与安全性」里还没允许的那一栏时，在清单下面放一张浮层。
// 材料、圆角、字级和间距用设计系统 §4 的浮层令牌（玻璃或 popover，窗口圆角 13，行 8）。
// 浮层里不再叠一层玻璃：那一行只是填充。允许了、或自己关掉，卡片就走。
// 不抢系统设置的焦点，所以拖过去时那一栏还是落点。

import Cocoa

enum PermissionDragKind: Equatable {
    case accessibility
    case screenRecording

    var isGranted: Bool {
        switch self {
        case .accessibility: return hasAccessibilityPermission()
        case .screenRecording: return hasScreenRecordingPermission()
        }
    }
}

@MainActor
final class PermissionDragHelper: NSObject {
    static let shared = PermissionDragHelper()

    private static let cardWidth: CGFloat = 300
    private static let inset: CGFloat = 16
    private static let rowHeight: CGFloat = 44

    private var panel: NSPanel?
    private var titleField: NSTextField?
    private var detailField: NSTextField?
    private var row: PermissionDragRow?
    private var polling = false
    private var kind: PermissionDragKind?
    private var watchingAppearance = false

    func show(_ kind: PermissionDragKind) {
        self.kind = kind
        let panel = panel ?? makePanel()
        self.panel = panel
        let title = WSL10n.text("permission.drag.title", zh: "在上面的清单里打开 %@。", Self.appName)
        let detail = WSL10n.text("permission.drag.detail", zh: "没有的话，把下面这一行拖进去。")
        titleField?.stringValue = title
        detailField?.stringValue = detail
        panel.title = title
        panel.setAccessibilityLabel("\(title) \(detail)")
        watchAppearanceIfNeeded()
        place(panel)
        panel.orderFrontRegardless()
        poll()
    }

    @objc func closeFromButton() { hide() }

    @objc private func appearanceChanged() {
        guard panel?.isVisible == true else { return }
        restyle()
    }

    private func hide() {
        polling = false
        kind = nil
        panel?.orderOut(nil)
    }

    private func poll() {
        guard !polling else { return }
        polling = true
        step()
    }

    private func step() {
        guard polling, panel?.isVisible == true else { polling = false; return }
        if kind?.isGranted == true { hide(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    private static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "WindowShade"
    }

    private func place(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { panel.center(); return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.minY + 28)
        panel.setFrame(frame, display: false)
    }

    private func watchAppearanceIfNeeded() {
        guard !watchingAppearance else { return }
        watchingAppearance = true
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged),
                                               name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                               object: NSWorkspace.shared)
    }

    private func makePanel() -> NSPanel {
        let title = WSL10n.text("permission.drag.title", zh: "在上面的清单里打开 %@。", Self.appName)
        let detail = WSL10n.text("permission.drag.detail", zh: "没有的话，把下面这一行拖进去。")
        let textWidth = Self.cardWidth - Self.inset * 2 - 28
        let titleFont = NSFont.systemFont(ofSize: 13)
        let detailFont = NSFont.systemFont(ofSize: 11)
        func measured(_ string: String, font: NSFont) -> CGFloat {
            ceil((string as NSString).boundingRect(
                with: NSSize(width: textWidth, height: 80),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font]).height)
        }
        let titleHeight = measured(title, font: titleFont)
        let detailHeight = measured(detail, font: detailFont)
        let height = Self.inset + Self.rowHeight + 12 + detailHeight + 2 + titleHeight + Self.inset
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.cardWidth, height: height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        let titleField = NSTextField(wrappingLabelWithString: title)
        titleField.font = titleFont
        titleField.textColor = .labelColor
        titleField.alignment = .left
        titleField.frame = NSRect(x: Self.inset, y: height - Self.inset - titleHeight, width: textWidth, height: titleHeight)
        self.titleField = titleField

        let detailField = NSTextField(wrappingLabelWithString: detail)
        detailField.font = detailFont
        detailField.textColor = .secondaryLabelColor
        detailField.alignment = .left
        detailField.frame = NSRect(x: Self.inset, y: titleField.frame.minY - 2 - detailHeight,
                                   width: Self.cardWidth - Self.inset * 2, height: detailHeight)
        self.detailField = detailField

        let row = PermissionDragRow(frame: NSRect(x: Self.inset, y: Self.inset,
                                                  width: Self.cardWidth - Self.inset * 2, height: Self.rowHeight))
        self.row = row

        let close = NSButton(frame: NSRect(x: Self.cardWidth - Self.inset - 20, y: height - Self.inset - 18, width: 20, height: 20))
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        close.imageScaling = .scaleProportionallyDown
        close.contentTintColor = .tertiaryLabelColor
        close.target = self
        close.action = #selector(closeFromButton)
        close.setAccessibilityLabel(WSL10n.text("menu.close", zh: "关闭"))

        let content = PermissionCardContent(frame: NSRect(x: 0, y: 0, width: Self.cardWidth, height: height))
        content.addSubview(titleField)
        content.addSubview(detailField)
        content.addSubview(row)
        content.addSubview(close)
        installSurface(on: panel, content: content)
        return panel
    }

    /// 设计系统 §4.2：浮层在 macOS 26+ 用 Regular 玻璃，内容放进 contentView；
    /// 更早的系统用 popover 磨砂；减少透明度时用不透明的窗口底色。增强对比度时补 1 pt 边，玻璃不加边。
    private func installSurface(on panel: NSPanel, content: NSView) {
        let capabilities = SystemAppearanceCapabilities.current
        let bounds = NSRect(origin: .zero, size: panel.frame.size)
        content.frame = bounds
        let host: NSView
        if capabilities.reduceTransparency {
            let opaque = PermissionOpaqueSurface(frame: bounds)
            SystemCornerRadius.apply(to: opaque, radius: SystemCornerRadius.window, masksToBounds: true)
            opaque.addSubview(content)
            host = opaque
        } else if capabilities.supportsGlass {
            #if WINDOWSHADE_SDK_HAS_GLASS
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: bounds)
                glass.style = .regular
                glass.cornerRadius = SystemCornerRadius.window
                glass.contentView = content
                host = glass
            } else {
                host = visualEffect(bounds: bounds, content: content)
            }
            #else
            host = visualEffect(bounds: bounds, content: content)
            #endif
        } else {
            host = visualEffect(bounds: bounds, content: content)
        }
        if capabilities.increaseContrast, capabilities.reduceTransparency || !capabilities.supportsGlass {
            host.wantsLayer = true
            host.layer?.borderWidth = 1
            host.effectiveAppearance.performAsCurrentDrawingAppearance {
                host.layer?.borderColor = NSColor.labelColor.cgColor
            }
        }
        panel.contentView = host
    }

    private func visualEffect(bounds: NSRect, content: NSView) -> NSView {
        let effect = NSVisualEffectView(frame: bounds)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        SystemCornerRadius.apply(to: effect, radius: SystemCornerRadius.window, masksToBounds: true)
        effect.addSubview(content)
        return effect
    }

    private func restyle() {
        guard let panel, let content = titleField?.superview else { return }
        content.removeFromSuperview()
        installSurface(on: panel, content: content)
        row?.needsDisplay = true
    }
}

/// 卡片里的内容。深浅色一变，把增强对比度的那条边重新取一次色。
@MainActor
final class PermissionCardContent: NSView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard let border = superview?.layer, border.borderWidth > 0 else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            border.borderColor = NSColor.labelColor.cgColor
        }
    }
}

/// 减少透明度时的底。颜色在 updateLayer 里取，深浅色切换不会停在旧的那一帧。
@MainActor
final class PermissionOpaqueSurface: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}

@MainActor
final class PermissionDragRow: NSView, NSDraggingSource {
    private var dragArmed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        SystemCornerRadius.apply(to: self, radius: SystemCornerRadius.item)

        let iconSide: CGFloat = 28
        let icon = NSImageView(frame: NSRect(x: 8, y: (frameRect.height - iconSide) / 2, width: iconSide, height: iconSide))
        let image = NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)
        image.size = NSSize(width: iconSide, height: iconSide)
        icon.image = image
        icon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(icon)

        let name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "WindowShade"
        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        let labelX: CGFloat = 8 + iconSide + 8
        label.frame = NSRect(x: labelX, y: (frameRect.height - 16) / 2,
                              width: frameRect.width - labelX - 12, height: 16)
        addSubview(label)
        setAccessibilityLabel(WSL10n.text("permission.drag.row", zh: "拖到上面的清单里：%@", name))
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill = dragArmed ? NSColor.unemphasizedSelectedContentBackgroundColor
                                 : NSColor.controlBackgroundColor
            layer?.backgroundColor = fill.cgColor
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragArmed = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragArmed = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragArmed else { return }
        dragArmed = false
        needsDisplay = true
        let file = Bundle.main.bundleURL
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: file.path)
        icon.size = NSSize(width: 48, height: 48)
        let origin = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: origin.x - 24, y: origin.y - 24, width: 48, height: 48), contents: icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
