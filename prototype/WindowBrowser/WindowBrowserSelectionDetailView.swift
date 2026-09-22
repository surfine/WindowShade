// 列表模式右侧的选中项详情。

import Cocoa

// MARK: - 选中项详情

final class WindowBrowserSelectionDetailView: NSView {
    private let imageView = NSImageView()
    private let titleField = NSTextField(wrappingLabelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private let statusIconView = NSImageView()
    private let liveHost = NSView()
    private var mountedLiveView: NSView?
    private var params = WindowBrowserLayoutParams.standard
    private(set) var cardSurface: WindowBrowserCardSurface = .solid

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityElement(false)
        titleField.font = WindowBrowserTypography.title
        titleField.maximumNumberOfLines = 2
        titleField.lineBreakMode = .byTruncatingTail
        statusField.font = WindowBrowserTypography.detail
        statusField.textColor = .secondaryLabelColor
        statusIconView.imageScaling = .scaleProportionallyDown
        for view in [imageView, liveHost, titleField, statusIconView, statusField] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    func update(record: WindowRecord, status: WindowBrowserStatusPresentation,
                image: CGImage?, params: WindowBrowserLayoutParams) {
        self.params = params
        titleField.stringValue = record.displayTitle
        titleField.toolTip = record.displayTitle
        statusField.stringValue = status.text
        statusField.textColor = SystemAppearancePolicy.statusTextColor(warning: status.isWarning)
        statusIconView.image = WindowBrowserSymbol.image(
            named: status.symbolName, accessibilityDescription: status.text,
            pointSize: WindowBrowserTypography.detailSize)
        statusIconView.isHidden = status.symbolName == nil
        statusField.isHidden = status.text.isEmpty
        imageView.image = image.map { NSImage(cgImage: $0, size: .zero) }
        imageView.isHidden = image == nil && mountedLiveView == nil
        setAccessibilityLabel("\(record.appName)，\(record.displayTitle)")
        setAccessibilityValue(status.text)
        refreshAppearance()
        needsLayout = true
    }

    func setImage(_ image: CGImage?) {
        imageView.image = image.map { NSImage(cgImage: $0, size: .zero) }
        imageView.isHidden = image == nil && mountedLiveView == nil
        needsLayout = true
    }

    @discardableResult
    func mountLiveView(_ view: NSView) -> Bool {
        if mountedLiveView === view, view.superview === liveHost { return false }
        unmountLiveView()
        mountedLiveView = view
        liveHost.addSubview(view)
        view.frame = liveHost.bounds
        view.autoresizingMask = [.width, .height]
        liveHost.isHidden = false
        imageView.isHidden = true
        return true
    }

    func unmountLiveView() {
        guard let view = mountedLiveView else { return }
        mountedLiveView = nil
        if view.superview === liveHost { view.removeFromSuperview() }
        liveHost.isHidden = true
        imageView.isHidden = imageView.image == nil
    }

    var hasLiveView: Bool { mountedLiveView != nil }

    override func layout() {
        super.layout()
        // 自上而下：画面（按比例，最高为栏高的 55%）→ 标题（最多两行）→ 状态，
        // 与 Finder 预览栏的阅读顺序一致；不再把画面压到栏底。
        let padding = params.selectionPanePadding
        let width = max(1, bounds.width - padding * 2)
        let imageHeight = max(40, min(floor(width * 0.625),
                                      floor((bounds.height - padding * 2) * 0.55)))
        let imageBox = NSRect(x: padding, y: bounds.height - padding - imageHeight,
                              width: width, height: imageHeight)
        if mountedLiveView == nil, let image = imageView.image, image.size.width > 0 {
            imageView.frame = WindowBrowserSurfaceStyle.fittedRect(for: image.size, in: imageBox)
        } else {
            imageView.frame = imageBox
        }
        liveHost.frame = imageBox
        mountedLiveView?.frame = liveHost.bounds
        let titleBlock = params.cardTitleHeight
        let titleY = imageBox.minY - params.spacingSmall - titleBlock
        titleField.frame = NSRect(x: padding, y: titleY, width: width, height: titleBlock)
        let statusBlock = params.cardStatusHeight
        let statusY = titleY - params.spacingTight - statusBlock
        statusIconView.frame = NSRect(x: padding, y: statusY,
                                      width: statusBlock, height: statusBlock)
        let statusX = statusIconView.isHidden ? padding
            : padding + statusBlock + params.spacingTight
        statusField.frame = NSRect(x: statusX, y: statusY,
                                   width: max(1, padding + width - statusX), height: statusBlock)
    }
}

extension WindowBrowserSelectionDetailView: WindowBrowserAppearanceRefreshable,
                                            WindowBrowserCardSurfaceHosting {
    /// 详情区自己重算层颜色（图片区域与卡片共享同一套规则）。
    func refreshAppearance() {
        WindowBrowserSurfaceStyle.applyCard(self, selected: false, params: params)
        WindowBrowserSurfaceStyle.applyImageArea(imageView, surface: cardSurface, params: params)
    }

    func adoptCardSurface(_ surface: WindowBrowserCardSurface) {
        guard surface != cardSurface else { return }
        cardSurface = surface
        refreshAppearance()
    }
}
