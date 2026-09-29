// 看一眼的画面：一张单独的卡片，和真窗口分得开。
// 收起的窗口：原貌卷帘条不动，卡片挂在它下面、隔一道缝，显示标题栏以下的内容。
// 带到每张桌面的窗口：卡片挂在那条卷帘条下面，整扇窗按比例缩小。
// 缩略图：卡片就是整扇窗口，从缩略图长回原来的大小，移开时缩回去（grow / shrink）。
// 卡片四个角都用真窗口的圆角（从截图里量），带自己的投影；有画面时不铺底色。
// 被隐藏的 App 临时在原处取消隐藏时，缝和圆角缺口底下垫一张真实背景，真窗口露不出来。
// 面板不激活 WindowShade、不抢键盘焦点；单击卡片才真正打开那扇窗。

import AVFoundation
import Cocoa

final class GlancePanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        title = "WindowShade 看一眼"
        level = .floating
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        isOpaque = false
        backgroundColor = .clear
        // 投影画在卡片上：窗口自带的投影会连背景垫片一起勾出一个方框。
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        tabbingMode = .disallowed
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class GlanceContentView: NSView {
    /// 卡片四周给投影留的边距（点）。
    static let shadowMargin: CGFloat = 24

    var onClick: (() -> Void)?

    /// 卡片在本视图里的位置（非翻转坐标）。
    let cardFrame: NSRect
    /// 整扇窗口的画面在卡片里的位置；超出卡片的部分（标题栏、屏幕外）被裁掉。
    let pictureFrame: NSRect

    private let backdropLayer = CALayer()
    private let shadowLayer = CALayer()
    private let cardLayer = CALayer()
    private let snapshotLayer = CALayer()
    private weak var videoLayer: AVSampleBufferDisplayLayer?
    private let rollMask = CALayer()
    private let badge: GlanceBadge
    private let message = NSTextField(labelWithString: "")
    /// badge 和 message 装在这一层里。缩略图的卡片长大、缩回时它们不跟着缩放：整层先藏起来，
    /// 卡片整张铺开再露出来。各自该不该显示仍由 setStaleNoticeVisible / refreshPlaceholder 管，这里不动。
    private let notices = NSView()
    /// 每次长大、缩回、停住都加一：过时的“铺开了再露出提示”不再生效。
    private var noticesGeneration = 0
    private(set) var hasSnapshot = false
    /// 视频层挂在画面里，且盖在截图上面。
    var showsVideo: Bool { videoLayer?.superlayer === cardLayer && snapshotLayer.isHidden }
    private(set) var isLive = false

    init(frame: NSRect, cardFrame: NSRect, pictureFrame: NSRect, cornerRadius: CGFloat,
         staleText: String, accessibilityTitle: String) {
        self.cardFrame = cardFrame
        self.pictureFrame = pictureFrame
        badge = GlanceBadge(text: staleText)
        super.init(frame: frame)
        wantsLayer = true
        let root = CALayer()
        layer = root
        root.masksToBounds = true
        backdropLayer.contentsGravity = .resize
        backdropLayer.isHidden = true
        root.addSublayer(backdropLayer)
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.26
        shadowLayer.shadowRadius = 14
        shadowLayer.shadowOffset = CGSize(width: 0, height: -6)
        root.addSublayer(shadowLayer)
        cardLayer.masksToBounds = true
        cardLayer.cornerRadius = cornerRadius
        cardLayer.cornerCurve = .continuous
        root.addSublayer(cardLayer)
        snapshotLayer.contentsGravity = .resize
        snapshotLayer.minificationFilter = .trilinear
        cardLayer.addSublayer(snapshotLayer)
        rollMask.backgroundColor = NSColor.black.cgColor
        rollMask.anchorPoint = CGPoint(x: 0, y: 1)
        root.mask = rollMask
        shadowLayer.shadowPath = CGPath(roundedRect: cardFrame, cornerWidth: cornerRadius,
                                        cornerHeight: cornerRadius, transform: nil)

        message.font = SystemAppearancePolicy.font(relativeToBody: 0, weight: .medium)
        message.textColor = .secondaryLabelColor
        message.alignment = .center
        message.isHidden = true
        notices.addSubview(message)
        badge.isHidden = true
        notices.addSubview(badge)
        notices.frame = bounds
        notices.autoresizingMask = [.width, .height]
        addSubview(notices)
        applySystemAppearance()

        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("看一眼：\(accessibilityTitle)")
        setAccessibilityHelp("单击打开这个窗口")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 只有卡片本身接单击；缝、投影边距上点了不算打开。
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return cardFrame.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard cardFrame.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onClick else { return false }
        onClick()
        return true
    }

    override func accessibilityFrame() -> NSRect {
        window?.convertToScreen(convert(cardFrame, to: nil)) ?? super.accessibilityFrame()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // 用 bounds + position 摆，不用 frame：缩略图的看一眼长大、缩回时这两层带着变换，
        // 那时写 frame 会被变换折算错。没有变换时两种写法一样。
        shadowLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        shadowLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        cardLayer.bounds = CGRect(origin: .zero, size: cardFrame.size)
        cardLayer.position = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
        snapshotLayer.frame = pictureFrame
        videoLayer?.frame = pictureFrame
        if rollMask.animationKeys()?.isEmpty ?? true {
            rollMask.bounds = CGRect(x: 0, y: 0, width: bounds.width,
                                     height: rollMask.bounds.height)
            rollMask.position = CGPoint(x: 0, y: bounds.height)
        }
        notices.frame = bounds
        message.sizeToFit()
        message.frame = NSRect(x: cardFrame.minX + 16,
                               y: floor(cardFrame.midY - message.frame.height / 2),
                               width: max(0, cardFrame.width - 32), height: message.frame.height)
        badge.fitToLabel()
        badge.setFrameOrigin(NSPoint(x: cardFrame.maxX - badge.frame.width - 12,
                                     y: cardFrame.minY + 12))
        CATransaction.commit()
    }

    /// 真窗口临时在底下时：把那块区域原本的背景垫在卡片下面（缝与圆角缺口里看到的就是它）。
    func setBackdrop(_ image: CGImage, frame: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer.contents = image
        backdropLayer.frame = frame
        backdropLayer.isHidden = false
        CATransaction.commit()
    }

    func setSnapshot(_ image: CGImage?) {
        hasSnapshot = image != nil
        snapshotLayer.contents = image
        refreshPlaceholder()
    }

    func attachVideo(_ layer: AVSampleBufferDisplayLayer) {
        videoLayer?.removeFromSuperlayer()
        layer.videoGravity = .resize
        layer.backgroundColor = NSColor.clear.cgColor
        cardLayer.addSublayer(layer)
        videoLayer = layer
        needsLayout = true
    }

    /// 实时画面到了：盖住截图，去掉“不是实时画面”的提示。
    func setLive(_ live: Bool) {
        isLive = live
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        snapshotLayer.isHidden = live && videoLayer != nil
        CATransaction.commit()
        refreshPlaceholder()
    }

    /// 右下角“收起时的画面”此刻看得见（探针用）。
    var showsStaleNotice: Bool { !notices.isHidden && !badge.isHidden }

    /// 实时画面等不到时，照实说这是哪个时候的画面。
    func setStaleNoticeVisible(_ visible: Bool) {
        badge.isHidden = !(visible && hasSnapshot && !isLive)
        needsLayout = true
    }

    private func refreshPlaceholder() {
        let nothing = !hasSnapshot && !isLive
        message.stringValue = nothing ? "画面暂时看不到" : ""
        message.isHidden = !nothing
        if isLive { badge.isHidden = true }
        applySystemAppearance()
        needsLayout = true
    }

    /// 卡片的底色与细边只在什么画面都没有时出现：窗口画面自带边缘，多一层会在角上露出月牙。
    func applySystemAppearance(capabilities: SystemAppearanceCapabilities = .current) {
        let bare = !hasSnapshot && !isLive
        cardLayer.borderWidth = bare ? SystemAppearancePolicy.edgeWidth(capabilities) : 0
        cardLayer.borderColor = SystemAppearancePolicy.cgColor(NSColor.separatorColor, for: self)
        cardLayer.backgroundColor = bare
            ? SystemAppearancePolicy.cgColor(NSColor.windowBackgroundColor, for: self)
            : NSColor.clear.cgColor
    }

    // MARK: 卷下 / 卷上

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func rollDown(duration: CFTimeInterval = 0.18) {
        layoutSubtreeIfNeeded()
        let full = bounds.height
        rollMask.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rollMask.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: full)
        rollMask.position = CGPoint(x: 0, y: full)
        CATransaction.commit()
        if reduceMotion {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.12
            layer?.add(fade, forKey: "glance-fade")
            return
        }
        let roll = CABasicAnimation(keyPath: "bounds.size.height")
        roll.fromValue = 0
        roll.toValue = full
        roll.duration = duration
        roll.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        rollMask.add(roll, forKey: "glance-roll")
    }

    /// 手指在卷帘条上往下拉：卡片跟着手指卷下 fraction（0...1），不做动画。
    func setRoll(_ fraction: CGFloat) {
        layoutSubtreeIfNeeded()
        let f = max(0, min(1, fraction))
        rollMask.removeAllAnimations()
        layer?.removeAnimation(forKey: "glance-fade")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rollMask.position = CGPoint(x: 0, y: bounds.height)
        if reduceMotion {
            layer?.opacity = Float(f)
            rollMask.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        } else {
            layer?.opacity = 1
            rollMask.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * f)
        }
        CATransaction.commit()
    }

    /// 没拉满就松手：从手指停下的地方接着卷到全开，停在“看一眼”。返回要多久。
    @discardableResult
    func settleRoll() -> CFTimeInterval {
        let full = bounds.height
        let current = rollMask.presentation()?.bounds.height ?? rollMask.bounds.height
        rollMask.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = 1
        rollMask.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: full)
        rollMask.position = CGPoint(x: 0, y: full)
        CATransaction.commit()
        guard !reduceMotion, full > 1, current < full - 0.5 else { return 0 }
        let duration = 0.18 * Double(max(0.3, (full - current) / full))
        let roll = CABasicAnimation(keyPath: "bounds.size.height")
        roll.fromValue = current
        roll.toValue = full
        roll.duration = duration
        roll.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        rollMask.add(roll, forKey: "glance-roll")
        return duration
    }

    /// 卷上（或缩回缩略图）途中指针又回来了：停在全开，不重播卷下。
    func cancelRollUp() {
        rollMask.removeAllAnimations()
        layer?.removeAnimation(forKey: "glance-fade")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = 1
        rollMask.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        rollMask.position = CGPoint(x: 0, y: bounds.height)
        for grown in [shadowLayer, cardLayer] {
            grown.removeAnimation(forKey: "glance-grow")
            grown.transform = CATransform3DIdentity
        }
        CATransaction.commit()
        // 卡片停在全开：缩回时藏起来的提示照各自的状态露出来。
        noticesGeneration += 1
        notices.isHidden = false
    }

    // MARK: 从缩略图长回原大小 / 缩回缩略图

    /// 卡片 delay 秒后整张铺开：到时再露出提示（中途又缩回、停住就作废）。
    private func revealNotices(after delay: CFTimeInterval) {
        noticesGeneration += 1
        let generation = noticesGeneration
        notices.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.noticesGeneration == generation else { return }
                self.notices.isHidden = false
            }
        }
    }

    /// 卡片（连同投影）缩在 rect（本视图坐标）里的样子：把卡片外框映到 rect 上的变换。
    private func shrunkTransform(for target: CALayer, into rect: NSRect) -> CATransform3D {
        guard cardFrame.width > 0, cardFrame.height > 0 else { return CATransform3DIdentity }
        let kx = rect.width / cardFrame.width
        let ky = rect.height / cardFrame.height
        let p = target.position
        let tx = rect.minX + kx * (p.x - cardFrame.minX) - p.x
        let ty = rect.minY + ky * (p.y - cardFrame.minY) - p.y
        return CATransform3DConcat(CATransform3DMakeScale(kx, ky, 1), CATransform3DMakeTranslation(tx, ty, 0))
    }

    /// 缩略图上停够了：卡片从缩略图（rect，本视图坐标）长回窗口原来的大小，弹簧 0.3 / 不回弹。
    /// 返回多久之后卡片整张盖住原处（被隐藏的 App 要等到那时才在下面取消隐藏）。
    @discardableResult
    func grow(from rect: NSRect) -> CFTimeInterval {
        layoutSubtreeIfNeeded()
        rollMask.removeAllAnimations()
        layer?.removeAnimation(forKey: "glance-fade")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = 1
        rollMask.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        rollMask.position = CGPoint(x: 0, y: bounds.height)
        for grown in [shadowLayer, cardLayer] {
            grown.removeAnimation(forKey: "glance-grow")
            grown.transform = CATransform3DIdentity
        }
        CATransaction.commit()
        if reduceMotion {
            // 整张一起淡入，提示跟着淡入就行。
            noticesGeneration += 1
            notices.isHidden = false
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.12
            layer?.add(fade, forKey: "glance-fade")
            return 0.12
        }
        var settle: CFTimeInterval = 0
        for grown in [shadowLayer, cardLayer] {
            let spring = CASpringAnimation(perceptualDuration: 0.3, bounce: 0)
            spring.keyPath = "transform"
            spring.fromValue = NSValue(caTransform3D: shrunkTransform(for: grown, into: rect))
            spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            spring.duration = spring.settlingDuration
            settle = spring.settlingDuration
            grown.add(spring, forKey: "glance-grow")
        }
        // 临界阻尼的弹簧到 0.45 秒已差不到 0.1%：千点宽的窗口也露不出一点。
        let covered = min(settle, 0.45)
        // 右下角“收起时的画面”、正中“画面暂时看不到”不跟着缩放：卡片铺开了再露出来。
        revealNotices(after: covered)
        return covered
    }

    /// 指针移开：卡片缩回缩略图（rect，本视图坐标），0.16 秒，缩完再交回 completion。
    func shrink(to rect: NSRect, completion: @escaping () -> Void) {
        rollMask.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        CATransaction.setDisableActions(true)
        if reduceMotion {
            layer?.opacity = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.1
            layer?.add(fade, forKey: "glance-fade")
        } else {
            for grown in [shadowLayer, cardLayer] {
                let from = grown.presentation()?.transform ?? grown.transform
                let to = shrunkTransform(for: grown, into: rect)
                grown.removeAnimation(forKey: "glance-grow")
                grown.transform = to
                let shrink = CABasicAnimation(keyPath: "transform")
                shrink.fromValue = NSValue(caTransform3D: from)
                shrink.toValue = NSValue(caTransform3D: to)
                shrink.duration = 0.16
                shrink.timingFunction = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
                grown.add(shrink, forKey: "glance-grow")
            }
            // 画面缩小时右下角“收起时的画面”那块提示不跟着缩：整层先藏起来（各自的状态留着，
            // 指针中途回来时 cancelRollUp 照原样露出来）。
            noticesGeneration += 1
            notices.isHidden = true
        }
        CATransaction.commit()
    }

    func rollUp(duration: CFTimeInterval = 0.14, completion: @escaping () -> Void) {
        let current = rollMask.presentation()?.bounds.height ?? rollMask.bounds.height
        rollMask.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        CATransaction.setDisableActions(true)
        if reduceMotion {
            layer?.opacity = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = 0.1
            layer?.add(fade, forKey: "glance-fade")
        } else {
            rollMask.bounds.size.height = 0
            let roll = CABasicAnimation(keyPath: "bounds.size.height")
            roll.fromValue = current
            roll.toValue = 0
            roll.duration = duration * Double(max(0.3, current / max(1, bounds.height)))
            roll.timingFunction = CAMediaTimingFunction(controlPoints: 0.65, 0, 0.35, 1)
            rollMask.add(roll, forKey: "glance-roll")
        }
        CATransaction.commit()
    }
}

/// 右下角的小提示：只在画面不是实时的时候出现。
private final class GlanceBadge: NSView {
    private let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        addSubview(label)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    func fitToLabel() {
        label.sizeToFit()
        let size = NSSize(width: ceil(label.frame.width) + 16, height: 18)
        setFrameSize(size)
        label.setFrameOrigin(NSPoint(x: 8, y: floor((size.height - label.frame.height) / 2)))
    }
}
