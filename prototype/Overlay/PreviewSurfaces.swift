// 悬停/菜单缩略图与置顶预览的表面视图。
//
// 这些视图只负责画面与材质，不持有任何窗口状态；材质、薄纱、边线与阴影全部来自
// SystemAppearancePolicy，因此减少透明度/提高对比度/浅深色切换时能被同一处刷新。
// 单独成文件也让离屏回归（tests/run-paper-tests.sh）能直接编译到生产视图。

import Cocoa

final class SafariStylePreviewView: NSView {
    let imageView = NSImageView()
    private let materialView = SystemMaterialView(purpose: .transientPeek)
    private let thumbnailClipView = NSView()

    /// 悬停缩略图要说明自己展示的是哪个窗口（tooltip + VoiceOver）。
    private(set) var windowTitleForAccessibility: String = ""

    init(frame: NSRect, image: NSImage, windowTitle: String = "") {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        materialView.layer?.cornerRadius = 10
        materialView.layer?.masksToBounds = true
        addSubview(materialView)

        thumbnailClipView.wantsLayer = true
        thumbnailClipView.layer?.cornerRadius = 6
        thumbnailClipView.layer?.cornerCurve = .continuous
        thumbnailClipView.layer?.masksToBounds = true
        thumbnailClipView.shadow = PaperSurfaceStyle.shadow()
        addSubview(thumbnailClipView)

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.clear.cgColor
        imageView.setAccessibilityElement(false)
        thumbnailClipView.addSubview(imageView)

        // 悬停缩略图是画面内容而不是控件，VoiceOver 只读出窗口名。
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        configureWindowTitle(windowTitle.isEmpty ? (image.accessibilityDescription ?? "")
                                                 : windowTitle)
        applySystemAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 设置该缩略图对应的窗口名：VoiceOver 朗读 + 鼠标悬停 tooltip。
    func configureWindowTitle(_ title: String) {
        windowTitleForAccessibility = title
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        setAccessibilityLabel(PaperSurfaceAccessibility.previewLabel(windowTitle: clean))
        toolTip = clean.isEmpty ? "窗口预览" : clean
    }

    /// 诊断/回归：当前实际使用的材质与最近一次应用的外观读数。
    var appliedMaterialForDiagnostics: NSVisualEffectView.Material { materialView.material }
    var appliedCapabilitiesForDiagnostics: SystemAppearanceCapabilities? {
        materialView.appliedCapabilities
    }

    /// 外观开关变化时局部刷新材质、薄纱与阴影，不动布局。
    func applySystemAppearance(capabilities: SystemAppearanceCapabilities = .current) {
        materialView.apply(capabilities: capabilities)
        layer?.borderWidth = SystemAppearancePolicy.edgeWidth(capabilities)
        layer?.borderColor = SystemAppearancePolicy.cgColor(NSColor.separatorColor, for: self)
        let veil = SystemAppearancePolicy.contentVeilColor(.transientPeek, capabilities)
        thumbnailClipView.layer?.backgroundColor = SystemAppearancePolicy.cgColor(
            veil, for: thumbnailClipView)
        thumbnailClipView.shadow = PaperSurfaceStyle.shadow(capabilities: capabilities)
    }

    override func layout() {
        super.layout()
        materialView.frame = bounds

        let padding: CGFloat = 10
        thumbnailClipView.isHidden = false
        thumbnailClipView.frame = bounds.insetBy(dx: padding, dy: padding)
        imageView.frame = thumbnailClipView.bounds
    }
}
