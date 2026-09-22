// 只读大图预览（Space 打开）。

import Cocoa

// MARK: - 只读大图预览

/// Space 打开的大图预览：只有画面与标题/说明，没有任何会改动窗口的控件。
final class WindowBrowserQuickLookView: NSView {
    /// 点击画面任意位置关闭（系统 Quick Look 的习惯）；Escape 走面板的取消路径。
    var onDismiss: (() -> Void)?
    private let material = SystemMaterialView(purpose: .transientPeek)
    private let imageView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let messageField = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private var params = WindowBrowserLayoutParams.standard
    private var chromeHeight: CGFloat = 44

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        SystemCornerRadius.apply(to: self, radius: params.panelCornerRadius,
                                 masksToBounds: true)
        addSubview(material)
        material.frame = bounds

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityElement(false)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(false)
        titleField.font = WindowBrowserTypography.title
        titleField.lineBreakMode = .byTruncatingTail
        titleField.textColor = .labelColor
        messageField.font = WindowBrowserTypography.detail
        messageField.textColor = .secondaryLabelColor
        messageField.lineBreakMode = .byTruncatingTail
        for view in [imageView, iconView, titleField, messageField] { addSubview(view) }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    required init?(coder: NSCoder) { nil }

    func update(record: WindowRecord, image: CGImage?, icon: NSImage?,
                message: String?, params: WindowBrowserLayoutParams) {
        self.params = params
        chromeHeight = params.cardStatusHeight + params.spacingLarge + params.spacingSmall
        titleField.stringValue = record.displayTitle
        titleField.toolTip = record.displayTitle
        imageView.image = image.map { NSImage(cgImage: $0, size: .zero) }
        imageView.isHidden = image == nil
        iconView.image = icon
        iconView.isHidden = image != nil || icon == nil
        messageField.stringValue = message ?? ""
        messageField.isHidden = message == nil
        setAccessibilityLabel("窗口大图预览：\(record.displayTitle)")
        setAccessibilityValue(message ?? "")
        let veil = SystemAppearancePolicy.contentVeilColor(.transientPeek, .current)
        material.layer?.backgroundColor = SystemAppearancePolicy.cgColor(
            NSColor.clear, for: material)
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = SystemAppearancePolicy.cgColor(veil, for: imageView)
        SystemCornerRadius.apply(to: imageView,
                                 radius: SystemCornerRadius.concentric(
                                    outer: params.panelCornerRadius,
                                    inset: params.spacingMedium),
                                 masksToBounds: true)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        material.frame = bounds
        let padding = params.spacingMedium
        let chrome = chromeHeight
        let imageFrame = NSRect(x: padding, y: chrome, width: max(1, bounds.width - padding * 2),
                                height: max(1, bounds.height - chrome - padding))
        imageView.frame = imageFrame
        let iconSide = min(64, max(24, min(imageFrame.width, imageFrame.height) * 0.25))
        iconView.frame = NSRect(x: imageFrame.midX - iconSide / 2,
                                y: imageFrame.midY - iconSide / 2 + chrome / 4,
                                width: iconSide, height: iconSide)
        titleField.frame = NSRect(x: padding, y: chrome - params.cardStatusHeight - 4,
                                  width: max(1, bounds.width - padding * 2),
                                  height: WindowBrowserTypography.lineHeight(
                                    WindowBrowserTypography.title))
        messageField.frame = NSRect(x: padding, y: 6,
                                    width: max(1, bounds.width - padding * 2),
                                    height: params.cardStatusHeight)
    }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.borderColor = SystemAppearancePolicy.cgColor(NSColor.separatorColor, for: self)
        layer?.borderWidth = SystemAppearancePolicy.edgeWidth(.current)
    }
}
