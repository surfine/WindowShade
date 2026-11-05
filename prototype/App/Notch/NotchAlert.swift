// // 提醒样式视图：刘海下面一行（App 图标、窗口新标题、App 名字）；真刘海屏上照 HIG 分四块（《两耳的岛》§五）。

import Cocoa
import ApplicationServices

/// 提醒样式：刘海下面一行，App 图标、窗口新标题、App 名字。
final class NotchAlertView: NSView {
    private var alert: NotchPanel.Alert?
    private var demoView: NotchDemoView?
    private var demoTip: CoachTip?

    /// 倒数大数字放在自己的文字图层里：每秒原地换字，不跟整块一起重画。两层轮流顶替，不用随换随删。
    private let earLayers = [CATextLayer(), CATextLayer()]
    private var earActive = 0
    private var earShown: String?
    private static let earMargin: CGFloat = 14

    override init(frame: NSRect) {
        super.init(frame: frame)
        setUp()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }
    private func setUp() {
        wantsLayer = true
        for layer in earLayers {
            layer.opacity = 0
            layer.alignmentMode = .right
            layer.isWrapped = false
            layer.actions = ["opacity": NSNull(), "contents": NSNull(), "string": NSNull(), "bounds": NSNull(), "position": NSNull()]
            self.layer?.addSublayer(layer)
        }
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for layer in earLayers { layer.contentsScale = scale }
    }

    /// 等宽圆体大数字（稿：离开就锁）：1 和 10 一样宽，换数字时不挪位置。
    static func earAttributed(_ ear: String, red: Bool) -> NSAttributedString {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: base.pointSize) } ?? base
        return NSAttributedString(string: ear, attributes: [.font: font, .foregroundColor: red ? NSColor.systemRed : NSColor.white])
    }

    private func earFrame(for text: NSAttributedString) -> CGRect {
        let size = text.size()
        let width = ceil(size.width), height = ceil(size.height)
        if let strip = notchStrip {
            // 四块：状态贴着刘海右边（内侧 2），竖直居中在刘海那一条里。
            return CGRect(x: strip.trailingX, y: strip.midY - height / 2, width: width, height: height)
        }
        return CGRect(x: bounds.width - Self.earMargin - width, y: (bounds.height - height) / 2, width: width, height: height)
    }

    /// 真刘海屏四块排法里刘海那一条：左边符号的右缘、右边状态的左缘（都离刘海 2）、那一条的竖直中线、下面句子区的高。
    private var notchStrip: (leadingX: CGFloat, trailingX: CGFloat, midY: CGFloat, below: CGFloat)? {
        guard let notch = alert?.besideNotch, alert?.peek == nil, alert?.demo == nil, bounds.height > notch.height else { return nil }
        let notchX = (bounds.width - notch.width) / 2
        let gap = IslandMetrics.earInnerGap
        return (notchX - gap, notchX + notch.width + gap, bounds.height - notch.height / 2, bounds.height - notch.height)
    }

    /// 倒数数字变了：旧字淡出 0.10 下移 2 点，新字从上 2 点淡入并 pop 0.9→1；减少动态效果只交叉淡化 0.18。
    private func syncEar(_ alert: NotchPanel.Alert?) {
        let ear = (alert?.peek == nil && alert?.demo == nil) ? alert?.ear.flatMap { $0.isEmpty ? nil : $0 } : nil
        let previous = earShown
        earShown = ear
        let outgoing = earLayers[earActive]
        guard let ear else {
            for layer in earLayers { layer.removeAllAnimations(); layer.opacity = 0 }
            return
        }
        let text = Self.earAttributed(ear, red: alert?.earRed ?? false)
        if previous == nil {
            outgoing.removeAllAnimations()
            outgoing.string = text
            outgoing.frame = earFrame(for: text)
            outgoing.opacity = 1
            return
        }
        // 字没变（只是提醒被重放）就不动。
        if (outgoing.string as? NSAttributedString)?.isEqual(to: text) == true { outgoing.frame = earFrame(for: text); return }
        let incoming = earLayers[1 - earActive]
        earActive = 1 - earActive
        incoming.removeAllAnimations()
        outgoing.removeAllAnimations()
        incoming.string = text
        incoming.frame = earFrame(for: text)
        incoming.opacity = 1
        outgoing.opacity = 0
        let plan = Motion.DigitSwap.plan(reduced: Motion.reduced)
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0; fadeIn.toValue = 1; fadeIn.duration = plan.inDuration
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        incoming.add(fadeIn, forKey: "ear.in")
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1; fadeOut.toValue = 0; fadeOut.duration = plan.outDuration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        outgoing.add(fadeOut, forKey: "ear.out")
        guard plan.shift > 0 else { return }
        // 图层坐标 y 向上：旧字往下（−2），新字从上（+2）落回。
        let drop = CABasicAnimation(keyPath: "transform.translation.y")
        drop.fromValue = 0; drop.toValue = -plan.shift; drop.duration = plan.outDuration
        drop.timingFunction = CAMediaTimingFunction(name: .easeIn)
        outgoing.add(drop, forKey: "ear.drop")
        let settle = Motion.spring(.pop, keyPath: "transform.translation.y")
        settle.fromValue = plan.shift; settle.toValue = 0
        incoming.add(settle, forKey: "ear.settle")
        let pop = Motion.spring(.pop, keyPath: "transform.scale")
        pop.fromValue = plan.popFrom; pop.toValue = 1
        incoming.add(pop, forKey: "ear.pop")
    }

    func update(_ alert: NotchPanel.Alert?) {
        self.alert = alert
        syncEar(alert)
        if alert?.demo != demoTip {
            demoView?.removeFromSuperview()
            demoView = alert?.demo.map { NotchDemoView(tip: $0) }
            demoTip = alert?.demo
            if let demoView { addSubview(demoView) }
        }
        needsDisplay = true
        needsLayout = true
        setAccessibilityElement(alert != nil)
        setAccessibilityRole(.staticText)
        if let alert {
            let ear = alert.ear.map { "，\($0)" } ?? ""
            let action = alert.actionLabel.map { WSL10n.text("notch.alert.action", zh: "，点一下%@", $0) } ?? ""
            if let peek = alert.peek {
                setAccessibilityLabel(NowPlayingPeek.spoken(title: peek.title, artist: peek.artist))
            } else {
                setAccessibilityLabel("\(alert.subtitle)：\(alert.title)\(ear)\(action)")
            }
        }
    }

    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// §6-4：图标 24，四周 14，不留额头。
    static func iconRect(in bounds: NSRect) -> NSRect {
        NSRect(x: 14, y: (bounds.height - 24) / 2, width: 24, height: 24)
    }

    /// 这一句的图标画在哪：真刘海屏贴着刘海左边、竖直居中在刘海那一条里（和两耳的左耳同一个位置）；其余照 §6-4。
    private var iconRect: NSRect {
        guard let strip = notchStrip else { return Self.iconRect(in: bounds) }
        let side = min(24, max(0, bounds.height - strip.below - 6))
        return NSRect(x: strip.leadingX - side, y: strip.midY - side / 2, width: side, height: side)
    }

    /// 窗口提醒里的图标此刻在屏幕上的位置；没有图标（教手势、没显示）就是 nil。
    var iconScreenRect: NSRect? {
        guard let alert, alert.demo == nil, alert.icon != nil, let window, !isHidden else { return nil }
        return window.convertToScreen(convert(iconRect, to: nil))
    }

    /// 卡住提示里新的那排键帽按一下（见 CoachEcho）。
    func echoKeys() { demoView?.echoKeys() }

    override func layout() {
        super.layout()
        if earShown != nil, let text = earLayers[earActive].string as? NSAttributedString {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            earLayers[earActive].frame = earFrame(for: text)
            CATransaction.commit()
        }
        demoView?.frame = NSRect(x: 14, y: (bounds.height - NotchDemoView.size.height) / 2,
                                 width: NotchDemoView.size.width, height: NotchDemoView.size.height)
    }

    /// 换歌一瞥：一行，歌名 13 半粗白，空 6，歌手 11 取封面字色；整行在宽度里居中，太长从尾巴截。
    private func drawPeek(_ peek: NotchPanel.PeekLine) {
        let margin = CGFloat(NowPlayingPeek.sideMargin)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let line = NSMutableAttributedString(string: peek.title, attributes: [
            .font: NSFont.systemFont(ofSize: CGFloat(NowPlayingPeek.titleSize), weight: .semibold),
            .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        if !peek.artist.isEmpty {
            // 稿的“空 6”：1 点的空格加 6 点字距，宽度约 6。
            line.append(NSAttributedString(string: " ", attributes: [
                .font: NSFont.systemFont(ofSize: 1), .kern: CGFloat(NowPlayingPeek.gap), .paragraphStyle: paragraph]))
            line.append(NSAttributedString(string: peek.artist, attributes: [
                .font: NSFont.systemFont(ofSize: CGFloat(NowPlayingPeek.artistSize), weight: .medium),
                .foregroundColor: peek.artistColor ?? NSColor.white.withAlphaComponent(0.6), .paragraphStyle: paragraph]))
        }
        let height = ceil(line.size().height)
        line.draw(with: NSRect(x: margin, y: (bounds.height - height) / 2, width: max(0, bounds.width - margin * 2), height: height),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// 四块排法（真刘海屏）：符号、状态在刘海两侧（状态的数字在 earLayers 里），刘海下面主句 15 半粗白、
    /// 副句 13 白 0.62，左对齐到边距 14；有“加入”按钮时它在句子右边。
    private func drawBesideNotch(_ alert: NotchPanel.Alert, strip: (leadingX: CGFloat, trailingX: CGFloat, midY: CGFloat, below: CGFloat)) {
        let margin: CGFloat = 14
        alert.icon?.draw(in: iconRect)
        var width = max(0, bounds.width - margin * 2)
        if let label = alert.actionLabel, !label.isEmpty {
            drawAction(label, in: NSRect(x: bounds.width - margin - 74, y: (strip.below - 26) / 2, width: 74, height: 26))
            width = max(0, width - 74 - 10)
        }
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingMiddle
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(string: alert.title, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: titleParagraph])
        let subtitle = NSAttributedString(string: alert.subtitle, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white.withAlphaComponent(0.62), .paragraphStyle: paragraph])
        let titleHeight = ceil(title.size().height)
        let subtitleHeight = alert.subtitle.isEmpty ? 0 : ceil(subtitle.size().height)
        let block = titleHeight + (subtitleHeight > 0 ? 1 + subtitleHeight : 0)
        let bottom = max(0, (strip.below - block) / 2)
        if subtitleHeight > 0 {
            subtitle.draw(with: NSRect(x: margin, y: bottom, width: width, height: subtitleHeight),
                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        title.draw(with: NSRect(x: margin, y: bottom + (subtitleHeight > 0 ? subtitleHeight + 1 : 0), width: width, height: titleHeight),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// 绿色小按钮（稿：74 × 26，圆头，摄像机加字）。点整条提醒都是同一件事。
    private func drawAction(_ label: String, in pill: NSRect) {
        NSColor(srgbRed: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 13, yRadius: 13).fill()
        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
        let glyph = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold).applying(.init(paletteColors: [.white])))
        let glyphWidth = glyph?.size.width ?? 0
        let gap: CGFloat = glyph == nil ? 0 : 4
        let total = glyphWidth + gap + ceil(text.size().width)
        var x = pill.midX - total / 2
        if let glyph {
            glyph.draw(in: NSRect(x: x, y: pill.midY - glyph.size.height / 2, width: glyph.size.width, height: glyph.size.height))
            x += glyphWidth + gap
        }
        text.draw(at: NSPoint(x: x, y: pill.midY - text.size().height / 2))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let alert else { return }
        if let peek = alert.peek { drawPeek(peek); return }
        if let strip = notchStrip { drawBesideNotch(alert, strip: strip); return }
        let margin: CGFloat = 14
        let iconRect = self.iconRect
        if alert.demo == nil { alert.icon?.draw(in: iconRect) }
        let textX = alert.demo == nil ? iconRect.maxX + 10 : margin + NotchDemoView.size.width + 12
        if alert.demo != nil {
            // 教手势：一句话可以折成两行，下面一行小字说“点一下不再提示”。
            let width = max(0, bounds.width - textX - margin)
            let title = NSAttributedString(string: alert.title, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white])
            let small = NSAttributedString(string: alert.subtitle, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.6)])
            let titleBox = title.boundingRect(with: NSSize(width: width, height: 40), options: [.usesLineFragmentOrigin])
            let smallHeight = ceil(small.size().height)
            let block = ceil(titleBox.height) + 4 + smallHeight
            let bottom = (bounds.height - block) / 2
            small.draw(with: NSRect(x: textX, y: bottom, width: width, height: smallHeight), options: [.usesLineFragmentOrigin])
            title.draw(with: NSRect(x: textX, y: bottom + smallHeight + 4, width: width, height: ceil(titleBox.height)),
                       options: [.usesLineFragmentOrigin])
            return
        }
        var width = max(0, bounds.width - textX - margin)
        if let label = alert.actionLabel, !label.isEmpty {
            drawAction(label, in: NSRect(x: bounds.width - margin - 74, y: (bounds.height - 26) / 2, width: 74, height: 26))
            width = max(0, width - 74 - 10)
        }
        if let ear = alert.ear, !ear.isEmpty {
            // 数字本身画在 earLayers 里（原地换字）；这里只给主句、副句让出位置。
            let size = Self.earAttributed(ear, red: alert.earRed).size()
            width = max(0, width - ceil(size.width) - 10)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        // 主句里的设备名、App 名从中间省略（“Aaron…iPhone”）；副句仍从尾部省略。
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingMiddle
        let title = NSAttributedString(string: alert.title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.white,
            .paragraphStyle: titleParagraph,
        ])
        let subtitle = NSAttributedString(string: alert.subtitle, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.white.withAlphaComponent(0.6),
            .paragraphStyle: paragraph,
        ])
        let titleHeight = ceil(title.size().height), subtitleHeight = ceil(subtitle.size().height)
        let block = titleHeight + 1 + subtitleHeight
        let bottom = (bounds.height - block) / 2
        subtitle.draw(with: NSRect(x: textX, y: bottom, width: width, height: subtitleHeight),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        title.draw(with: NSRect(x: textX, y: bottom + subtitleHeight + 1, width: width, height: titleHeight),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
