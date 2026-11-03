// // 展开那一排：位移弹簧（RowSpringMotion）、段间竖线、一格的拖出回调与卡片视图（NotchTileView）。

import Cocoa
import ApplicationServices

/// 那一排里的位移弹簧：格子补位、键盘滚动都用它。令牌来自设计系统 §4.6，不另造；
/// 同一根轴上旧弹簧还在飞时，接上它此刻的速度（`MorphRetarget`，岛变形用的同一套），半路改方向速度不断。
@MainActor
enum RowSpringMotion {
    /// 视图的模型 position.x（按 frame 和锚点算，不等 AppKit 把几何同步到图层）。
    static func modelX(_ view: NSView) -> CGFloat {
        view.frame.minX + (view.layer?.anchorPoint.x ?? 0) * view.frame.width
    }
    /// 屏幕上此刻看到的 position.x（有动画在飞就是呈现层的值）。
    static func presentedX(_ view: NSView) -> CGFloat {
        view.layer?.presentation()?.position.x ?? modelX(view)
    }

    /// 屏幕上此刻看到的左边缘（presentedX 去掉锚点的偏移）。
    static func presentedMinX(_ view: NSView) -> CGFloat {
        presentedX(view) - (view.layer?.anchorPoint.x ?? 0) * view.frame.width
    }

    /// 视图的 frame 已经是新的了；`presentedX` 是改之前屏幕上看到的 position.x，`modelX` 是改之后的。从那里弹到新位置。
    static func slide(_ layer: CALayer, key: String, presentedX: CGFloat, modelX target: CGFloat, token: MotionSpring) {
        let from = Double(presentedX - target)
        guard abs(from) > 0.25 else { layer.removeAnimation(forKey: key); return }
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        var live: Double?
        if let old = layer.animation(forKey: key) as? CASpringAnimation, old.isAdditive, old.beginTime > 0, old.duration > 0,
           let oldFrom = (old.fromValue as? NSNumber)?.doubleValue {
            live = MorphRetarget.liveVelocity(of: MorphRetarget.OldAxis(mass: old.mass, stiffness: old.stiffness, damping: old.damping,
                                                                       from: oldFrom, normalizedVelocity: old.initialVelocity,
                                                                       beginTime: old.beginTime, duration: old.duration), at: now)
        } else if let frames = layer.animation(forKey: key) as? CAKeyframeAnimation {
            live = NotchCanvasView.keyframeVelocity(frames, at: now)
        }
        layer.removeAnimation(forKey: key)
        guard let axis = MorphRetarget.handoff(remainingTravel: -from, liveVelocity: live, fallbackVelocity: 0,
                                               response: token.response, dampingRatio: 1 - Double(token.bounce), floor: nil) else { return }
        if let kick = axis.kick {
            let frames = CAKeyframeAnimation(keyPath: "position.x")
            frames.isAdditive = true
            frames.calculationMode = .linear
            frames.values = kick.values.map { NSNumber(value: $0) }
            frames.keyTimes = kick.times.map { NSNumber(value: min(1, $0 / (kick.times.last ?? 1))) }
            frames.duration = kick.times.last ?? 0
            frames.beginTime = now
            layer.add(frames, forKey: key)
            return
        }
        let spring = CASpringAnimation(perceptualDuration: token.response, bounce: token.bounce)
        spring.keyPath = "position.x"
        spring.isAdditive = true
        spring.fromValue = from
        spring.toValue = 0
        spring.initialVelocity = CGFloat(axis.initialVelocity)
        spring.duration = spring.settlingDuration
        spring.beginTime = now
        layer.add(spring, forKey: key)
    }
}

/// 左段窗口和右段正在进行的之间那一条竖线：1pt、白 0.2。只是一道线，读屏不念、指针穿过。
final class NotchRowDivider: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(CGFloat(NotchRow.dividerWhite)).cgColor
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 展开后的一格：窗口的画面（没有画面就放大 App 图标）、左上角标明它是哪一种、右上角有变化的点、App 图标和标题。
/// 点一下回到它该在的地方。卡片圆角 14：外框 28 减去边距 14（HIG：同心）。
/// 左段收着的一格能拖出刘海放回卷轴（SS-04）。enabled：这一格现在能不能拖；moved：拖着的指针位置（Cocoa 屏幕坐标）；
/// finished：松手（point = nil 是作废）。
struct NotchTileDragOut {
    var enabled: @MainActor (CGWindowID) -> Bool
    var moved: @MainActor (CGWindowID, CGPoint) -> Void
    var finished: @MainActor (CGWindowID, CGPoint?) -> Void
}

final class NotchTileView: NSView {
    /// 点一下：带上画面此刻在屏幕上的位置（窗口从这里飞回去）。
    var onClick: ((NSRect?) -> Void)?
    /// 点在右下角那个 24 点的小键上（音乐的播放 / 暂停）。
    var onAccessory: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var tile: NotchTile
    var tileID: CGWindowID { tile.id }
    var changed: Bool { tile.changed }

    /// 后台截到这一格的画面：原地换上，不重建格子（指针正停在上面时，停留计时和悬停都不受影响）。
    /// 从没有画面换成有画面时淡入 0.15 秒；减弱动态效果时直接换。
    func setSnapshot(_ image: CGImage?) {
        guard image !== tile.snapshot else { return }
        let fadeIn = tile.snapshot == nil && image != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        tile.snapshot = image
        if fadeIn {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = Motion.fadeDuration
            layer?.add(fade, forKey: "snapshot")
        }
        needsDisplay = true
    }
    private var hovering = false { didSet { needsDisplay = true } }
    private var dwell: Timer?
    /// SS-04：左段收着的一格按下、拖、松手的判定（Core/StripNotchTileDrag）。
    private var drag = StripNotchTileDrag()
    /// SS-04：拖出刘海放回卷轴的口子，NotchController 在卷轴接上刘海时设；nil 时这一格和从前一样。
    static var dragOut: NotchTileDragOut?
    /// 键盘焦点亮在这一格上（M07）：放大 1.1 倍、上移 4 点、白色描边。指针一进来由 NotchPanel 先熄掉。
    private(set) var keyboardFocused = false

    init(tile: NotchTile) {
        self.tile = tile
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        describe()
        syncSpinner()
        syncQuantity()
    }

    /// 提示和读屏念的话。竖线右边的格子念整句（“项目，在等你”），不加动词。
    private func describe() {
        if let away = tile.away {
            toolTip = [away.title, away.subtitle].filter { !$0.isEmpty }.joined(separator: "\n")
            setAccessibilityLabel(away.spoken)
            setAccessibilityRole(away.isActionable ? .button : .staticText)
            // 灰掉的格子标为不可用（念出原因在 label 里：「已经不在了」），不只靠变灰。
            setAccessibilityEnabled(!away.isGone)
            return
        }
        if let ongoing = tile.ongoing {
            toolTip = ongoing.subtitle.isEmpty ? tile.title : "\(tile.title)\n\(ongoing.subtitle)"
            setAccessibilityLabel(ongoing.spoken)
            alphaValue = ongoing.isStale ? CGFloat(NotchActivity.staleAlpha) : 1
        } else {
            toolTip = "\(tile.title)\n\(tile.parked != nil ? Self.kindName(tile.kind) : (tile.place ?? Self.kindName(tile.kind)))"
            if let parked = tile.parked {
                setAccessibilityLabel(parked.spoken(title: tile.title))
            } else {
                let name = NotchFocusController.label(for: tile.title)
                switch tile.kind {
                case .elsewhere, .session, .playing, .activity:
                    setAccessibilityLabel("\(Self.verb(tile.kind)) \(name)")
                default:
                    // 「回到原处」念成整句，英文把窗口名放进句子里（Aaron 10-30）。
                    setAccessibilityLabel(WSL10n.text("notch.tile.backInPlaceSpoken", zh: "回到原处 %@", name))
                }
            }
        }
    }

    /// 正在进行的格内容变了（会话换了状态、曲名变了）：原地换，不重建格子。
    func updateOngoing(_ next: NotchTile) {
        guard next.kind.isOngoing, next.id == tile.id, next.ongoingSignature != tile.ongoingSignature else { return }
        tile = next
        describe()
        syncSpinner()
        syncQuantity()
        needsDisplay = true
    }

    /// 量变了（同一种画法）：只改数字和环的终点。画法不同不会走到这里（签名变了，整格换内容）。
    func setQuantity(_ quantity: NotchActivity.Quantity, text: String?) {
        guard tile.ongoing != nil, tile.ongoing?.quantity != quantity || tile.ongoing?.quantityText != text else { return }
        tile.ongoing?.quantity = quantity
        tile.ongoing?.quantityText = text
        syncQuantity()
        needsDisplay = true
    }

    /// 右上角的量（M12）：比例是环加数字，只有个数是字，不确定是转着的弧。环和弧是子图层，Core Animation 自己转。
    private let part = NotchProgressPartLayers()
    private func syncQuantity() {
        let quantity = tile.ongoing?.quantity ?? .unknown
        if quantity.drawing != .none, part.root.superlayer == nil { layer?.addSublayer(part.root) }
        placePart()
        part.apply(quantity, tone: .playback)
        // 读屏的“值”随进度变；标签（“项目，正在下载”）不跟着变。
        setAccessibilityValue(tile.ongoing?.quantityText)
    }
    private func placePart() {
        let side = NotchProgressPartLayers.side
        CATransaction.begin(); CATransaction.setDisableActions(true)
        part.root.position = CGPoint(x: bounds.width - 10 - side / 2, y: bounds.height - 10 - side / 2)
        CATransaction.commit()
    }

    /// 会话在跑：格子右上角转圈。Core Animation 自己转，不起计时器；格子离开屏幕就停。
    private let spinner = NotchSessionSpinner.makeLayer()
    private func syncSpinner() {
        let running = tile.ongoing?.phase == .running
        if running {
            if spinner.superlayer == nil { layer?.addSublayer(spinner) }
            placeSpinner()
            spinner.isHidden = false
            if window != nil { NotchSessionSpinner.start(spinner) }
        } else {
            NotchSessionSpinner.stop(spinner)
            spinner.isHidden = true
        }
    }
    private func placeSpinner() {
        let side = NotchSessionSpinner.diameter
        spinner.position = CGPoint(x: bounds.width - 10 - side / 2, y: bounds.height - 10 - side / 2)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { NotchSessionSpinner.stop(spinner) } else if tile.ongoing?.phase == .running { NotchSessionSpinner.start(spinner) }
        part.setAttached(window != nil)
    }

    /// 读屏念“第几个，共几个”（和焦点挪动时的播报同一个说法）。
    func setPosition(_ index: Int, of count: Int) {
        let position = WSL10n.text("notch.alert.index", zh: "第 %@ 个，共 %@ 个", String(index + 1), String(count))
        if let help = tile.away?.help, !help.isEmpty { setAccessibilityHelp(help + "，" + position); return }
        setAccessibilityHelp(position)
    }

    /// 亮起或熄灭键盘焦点。`bump` 不为空：到头了，朝那个方向轻轻顶 6 点再弹回。
    func setFocused(_ focused: Bool, bump: FocusNavigator.Direction? = nil, animated: Bool = true) {
        let was = keyboardFocused
        keyboardFocused = focused
        if focused != was { needsDisplay = true }
        layer?.zPosition = focused ? 1 : 0
        guard let layer else { return }
        let rest = focusTransform(focused: focused, bump: nil)
        if let bump, focused, animated, !Motion.reduced {
            // 模型值落在原位，动画从“顶出去”的位置弹回来。
            layer.removeAnimation(forKey: "transform")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = rest
            CATransaction.commit()
            let animation = Motion.spring(.flyOut, keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: focusTransform(focused: true, bump: bump))
            animation.toValue = NSValue(caTransform3D: rest)
            layer.add(animation, forKey: "transform")
            return
        }
        if animated {
            layer.springTransform(rest, .calm, reduced: Motion.reduced)
        } else {
            layer.removeAnimation(forKey: "transform")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = rest
            CATransaction.commit()
        }
    }

    /// 绕格子中心放大再上抬；NSView 的图层锚点不在中心，平移由 NotchFocusController.Style 按锚点补回。
    private func focusTransform(focused: Bool, bump: FocusNavigator.Direction?) -> CATransform3D {
        let anchor = layer?.anchorPoint ?? .zero
        let t = NotchFocusController.Style.transform(
            width: Double(bounds.width), height: Double(bounds.height),
            pivotX: Double(anchor.x * bounds.width), pivotY: Double(anchor.y * bounds.height),
            focused: focused, bump: bump)
        return CATransform3DScale(CATransform3DMakeTranslation(CGFloat(t.translationX), CGFloat(t.translationY), 0),
                                  CGFloat(t.scale), CGFloat(t.scale), 1)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed, spinner.superlayer != nil { placeSpinner() }
        if changed, part.root.superlayer != nil { placePart() }
        if changed, keyboardFocused { setFocused(true, animated: false) }
    }

    /// 键盘上的 Return：和指针点一下是同一条路（带上画面此刻的位置，窗口从这里飞回去）。
    func activateFromKeyboard() {
        let picture = pictureRect.flatMap { rect in window.map { $0.convertToScreen(convert(rect, to: nil)) } }
        onClick?(picture)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 点下去会发生什么（和菜单里的说法一致）。
    static func verb(_ kind: NotchTile.Kind) -> String {
        switch kind {
        // 那一排里窗口回到你面前的都叫“回到原处”，别的桌面上的是你过去，叫“去”（拍板 10-29 第 15 条）。
        // 各表面自己的动词（卷帘条上展开、侧拉拉出、刘海放回）留在各自的表面上，不在这一排里。
        case .tucked, .strip, .thumbnail, .slideOver, .carried, .minimized, .hiddenApp, .parked:
            return WSL10n.text("notch.verb.backInPlace", zh: "回到原处")
        case .elsewhere: return WSL10n.text("notch.verb.goTo", zh: "去")
        case .session: return WSL10n.text("notch.action.goThere", zh: "过去")
        case .playing, .activity: return WSL10n.text("notch.action.open", zh: "打开")
        case .away: return ""
        }
    }

    static func kindName(_ kind: NotchTile.Kind) -> String {
        switch kind {
        case .tucked: return WSL10n.text("silent.window.tuck", zh: "收进刘海")
        case .strip: return WSL10n.text("notch.where.strip", zh: "收起的窗口")
        case .thumbnail: return WSL10n.text("notch.where.thumbnail", zh: "收成缩略图的窗口")
        case .slideOver: return WSL10n.text("notch.where.slideOver", zh: "侧拉")
        case .carried: return WSL10n.text("menu.carryToAllDesktops", zh: "带到每张桌面")
        case .minimized: return WSL10n.text("notch.where.minimized", zh: "已最小化")
        case .hiddenApp: return WSL10n.text("notch.where.hiddenApp", zh: "已隐藏")
        case .elsewhere: return WSL10n.text("notch.where.elsewhere", zh: "在别的桌面")
        case .parked: return WSL10n.text("notch.where.parked", zh: "停在屏幕外的一列")
        case .session: return WSL10n.text("notch.kind.session", zh: "编程会话")
        case .playing: return WSL10n.text("say.preview.playing", zh: "正在播放")
        case .activity: return WSL10n.text("notch.where.activity", zh: "正在进行")
        case .away: return AwaySummary.heading
        }
    }

    private static func badge(_ kind: NotchTile.Kind) -> NSImage? {
        let name: String
        switch kind {
        case .tucked, .elsewhere, .session, .playing, .activity, .parked, .away: return nil
        case .strip: name = "rectangle.topthird.inset.filled"
        // 缩略图格子的专属角标，和卷帘条的 rectangle.topthird 区分。
        case .thumbnail: name = "photo"
        case .slideOver: name = "rectangle.rightthird.inset.filled"
        case .carried: name = "rectangle.stack"
        case .minimized: name = "dock.rectangle"
        case .hiddenApp: name = "eye.slash"
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// 停 `Motion.Hold.tileDwell`（0.20 秒）才看：指针从一格划到另一格时不闪。
    override func mouseEntered(with event: NSEvent) {
        hovering = true
        dwell?.invalidate()
        dwell = Timer.scheduledTimer(withTimeInterval: Motion.Hold.tileDwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.onHover?(true) }
        }
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        dwell?.invalidate()
        onHover?(false)
    }
    override func mouseDown(with event: NSEvent) {
        if let rect = accessoryRect, tile.ongoing?.accessory != nil,
           rect.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil)) {
            onAccessory?()
            return
        }
        // 左段收着的一格：卷轴开着、接线开关开着时，按下先不算点一下，松手时没拖起来才算（SS-04）；其它时候照旧。
        if tile.kind == .tucked, Self.dragOut?.enabled(tile.id) == true {
            drag.press(tile.id, at: NSEvent.mouseLocation)
            return
        }
        let picture = pictureRect.flatMap { rect in window.map { $0.convertToScreen(convert(rect, to: nil)) } }
        onClick?(picture)
    }

    override func mouseDragged(with event: NSEvent) {
        guard drag.isPressed, let hooks = Self.dragOut else { return }
        let point = NSEvent.mouseLocation
        switch drag.move(to: point) {
        case .none: return
        case .began:
            alphaValue = 0.5
            hooks.moved(tile.id, point)
        case .moved:
            hooks.moved(tile.id, point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard drag.isPressed else { return }
        alphaValue = 1
        switch drag.release(at: NSEvent.mouseLocation) {
        case .click:
            let picture = pictureRect.flatMap { rect in window.map { $0.convertToScreen(convert(rect, to: nil)) } }
            onClick?(picture)
        case .drop(let id, let point):
            Self.dragOut?.finished(id, point)
        case .none:
            break
        }
    }

    /// 拖着的时候这一格被收走（那一排收起、换桌面、锁屏）：这次拖动作废，窗口还在刘海里。
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, drag.cancel() else { return }
        let id = tile.id
        DispatchQueue.main.async { MainActor.assumeIsolated { Self.dragOut?.finished(id, nil) } }
    }

    /// 右下角的小键（NP-4）：24 点的圆，离格子右边和下边各 10。只有带 accessory 的格子有。
    private var accessoryRect: NSRect? {
        guard tile.ongoing?.accessory != nil else { return nil }
        let side = CGFloat(NotchRow.OngoingCell.accessorySide)
        return NSRect(x: card.maxX - 10 - side, y: card.minY + 10, width: side, height: side)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var card: NSRect { NSRect(x: 0, y: 20, width: bounds.width, height: max(0, bounds.height - 20)) }

    private static func symbolImage(_ name: String, pointSize: CGFloat, color: NSColor,
                                    weight: NSFont.Weight = .regular) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(.init(paletteColors: [color]))
        return NotchActivitySymbol.image(name.isEmpty ? "circle.fill" : name)?.withSymbolConfiguration(configuration)
    }

    /// 竖线右边的格子：一个大符号、一行副句，右上角是这件事的状态——
    /// 会话在跑转圈（子图层）、等你是 8 点的橙点加“等你”、做完是对勾；音乐暂停时是暂停符号。
    /// 文件架这一格：最新的三张叠在一起（缩略图或类型图标），后面的往左上错开一点。
    private func drawFileShelfStack(in card: NSRect, count: Int) {
        let art = FileShelfCellArt.images(limit: min(3, count))
        guard !art.isEmpty else { return }
        let side: CGFloat = 52
        let center = NSPoint(x: card.midX, y: card.midY + 8)
        for (index, image) in art.enumerated().reversed() {
            let offset = CGFloat(index) * 7
            let rect = NSRect(x: center.x - side / 2 - offset + 7, y: center.y - side / 2 + offset - 7, width: side, height: side)
            let size = image.size
            guard size.width > 0, size.height > 0 else { continue }
            let scale = min(side / size.width, side / size.height)
            let drawn = NSSize(width: size.width * scale, height: size.height * scale)
            let target = NSRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: target, xRadius: 12, yRadius: 12).addClip()
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: index == 0 ? 1 : 0.7)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.35).setStroke()
            let outline = NSBezierPath(roundedRect: target.insetBy(dx: 0.5, dy: 0.5), xRadius: 11.5, yRadius: 11.5)
            outline.lineWidth = 1
            outline.stroke()
        }
    }

    /// 量的完整说法放不下时，个数沿用右耳的短写；保字号与真实数，不把总数截成另一个数。
    static func quantityLabel(_ quantity: NotchActivity.Quantity, text: String, font: NSFont, availableWidth: CGFloat, color: NSColor? = nil) -> NSAttributedString {
        func label(_ string: String) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                .font: font, .foregroundColor: color ?? NSColor.white.withAlphaComponent(0.92),
            ])
        }
        let full = label(text)
        guard full.size().width > availableWidth, let short = quantity.shortCountText else { return full }
        return label(short)
    }

    private func drawOngoing(in card: NSRect) {
        guard let ongoing = tile.ongoing else { return }
        if let count = ongoing.shelfCount {
            drawFileShelfStack(in: card, count: count)
            return
        }
        if let image = Self.symbolImage(ongoing.symbol, pointSize: 30, color: NSColor.white.withAlphaComponent(0.92)) {
            let size = image.size
            image.draw(in: NSRect(x: card.midX - size.width / 2, y: card.midY - size.height / 2 + 8,
                                  width: size.width, height: size.height))
        }
        // 右下角留一个 24 点的播放 / 暂停键（音乐，NP-4）；副句让出它占的那一截，左对齐。
        let key = accessoryRect
        if !ongoing.subtitle.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = key == nil ? .center : .left
            paragraph.lineBreakMode = .byTruncatingTail
            let left = card.minX + (key == nil ? 8 : 12)
            let right = key.map { $0.minX - 6 } ?? card.maxX - 8
            NSAttributedString(string: ongoing.subtitle, attributes: [
                .font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor.white.withAlphaComponent(0.6),
                .paragraphStyle: paragraph,
            ]).draw(with: NSRect(x: left, y: card.minY + 8, width: max(0, right - left), height: 14),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        if let key {
            NSColor.white.withAlphaComponent(0.16).setFill()
            NSBezierPath(ovalIn: key).fill()
            if let icon = Self.symbolImage(ongoing.isPaused ? "play.fill" : "pause.fill", pointSize: 11,
                                           color: NSColor.white.withAlphaComponent(0.92), weight: .semibold) {
                let size = icon.size
                icon.draw(in: NSRect(x: key.midX - size.width / 2, y: key.midY - size.height / 2, width: size.width, height: size.height))
            }
        }
        // 右上角的量：环（或弧，子图层）左边写数字；只有个数就只写字。和紧凑右耳同一套。
        var quantityLeft = card.maxX - 10
        switch ongoing.quantity.drawing {
        case .ring, .spinningArc: quantityLeft -= CGFloat(NotchProgressPart.ringDiameter) + CGFloat(NotchProgressPart.textGap)
        case .countText, .none: break
        }
        if let text = ongoing.quantityText, !text.isEmpty {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
            let available = max(0, quantityLeft - card.minX - 10)
            let label = Self.quantityLabel(ongoing.quantity, text: text, font: rounded, availableWidth: available, color: ongoing.phase == .quotaLow ? .systemOrange : nil)
            let size = label.size()
            let width = min(ceil(size.width), available)
            label.draw(with: NSRect(x: quantityLeft - width, y: card.maxY - 10 - 7 - size.height / 2, width: width, height: size.height),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            quantityLeft -= width + CGFloat(NotchProgressPart.textGap)
        }
        switch ongoing.phase {
        case .waiting?:
            let diameter = CGFloat(NotchInfoDot.diameter)
            let dot = NSRect(x: card.maxX - 10 - diameter, y: card.maxY - 10 - diameter, width: diameter, height: diameter)
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: dot).fill()
            let label = NSAttributedString(string: WSL10n.text("notch.session.waitingTag", zh: "等你"), attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.systemOrange,
            ])
            let size = label.size()
            label.draw(at: NSPoint(x: dot.minX - 4 - size.width, y: dot.midY - size.height / 2))
        case .done?:
            Self.symbolImage("checkmark.circle.fill", pointSize: 14, color: .systemGreen, weight: .semibold)?
                .draw(in: NSRect(x: card.maxX - 10 - 14, y: card.maxY - 10 - 14, width: 14, height: 14))
        case .running?, .quota?, .quotaLow?, nil:
            if ongoing.phase == nil, ongoing.isPaused {
                // 暂停符号在量（环、数字）的左边，不叠在上面。
                let drawsQuantity = ongoing.quantity.drawing != .none
                Self.symbolImage("pause.fill", pointSize: 11, color: NSColor.white.withAlphaComponent(0.7), weight: .semibold)?
                    .draw(in: NSRect(x: (drawsQuantity ? quantityLeft : card.maxX - 10) - 12, y: card.maxY - 10 - 12, width: 12, height: 12))
            }
        }
    }

    /// 画面在格子里的位置（等比放进卡片，四周留 6 点）。
    private var pictureRect: NSRect? {
        guard let snapshot = tile.snapshot, snapshot.width > 0, snapshot.height > 0 else { return nil }
        let size = NSSize(width: snapshot.width, height: snapshot.height)
        let scale = min((card.width - 12) / size.width, (card.height - 12) / size.height)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: card.midX - drawn.width / 2, y: card.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
    }

    /// 离开期间的一格（稿「每个格子」）：同样大的圆角卡；窗口是 App 图标加名字加副句，设备是名字加大号百分比，
    /// 下载是文件名，有人动过是盾牌加原话，窄格只写「还有」「N 件」。已经不在了的整格变灰。底部一行是动词（不能点的没有）。
    private func drawAwayCell(_ away: NotchTile.AwayCell) {
        let card = self.card
        NSColor(white: hovering && away.isActionable ? 0.22 : 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
        let dim: CGFloat = away.isGone ? 0.4 : 1
        func draw(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, alpha: CGFloat, in rect: NSRect,
                  rounded: Bool = false, align: NSTextAlignment = .center) {
            guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = align
            paragraph.lineBreakMode = .byTruncatingTail
            var font = NSFont.systemFont(ofSize: size, weight: weight)
            if rounded, let descriptor = font.fontDescriptor.withDesign(.rounded), let r = NSFont(descriptor: descriptor, size: size) { font = r }
            NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: NSColor.white.withAlphaComponent(alpha * dim), .paragraphStyle: paragraph,
            ]).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        let inner = card.insetBy(dx: 8, dy: 0)
        if away.isNarrow {
            draw(away.title, size: 11, alpha: 0.6, in: NSRect(x: card.minX, y: card.midY + 1, width: card.width, height: 14))
            draw(away.subtitle, size: 13, weight: .semibold, alpha: 0.92, in: NSRect(x: card.minX, y: card.midY - 17, width: card.width, height: 16))
        } else {
            var top = card.maxY - 10
            if let big = away.big {
                draw(away.title, size: 11, weight: .semibold, alpha: 0.92, in: NSRect(x: inner.minX, y: top - 14, width: inner.width, height: 14))
                top -= 18
                draw(big, size: 26, weight: .semibold, alpha: 0.95, in: NSRect(x: inner.minX, y: top - 32, width: inner.width, height: 32), rounded: true)
                top -= 32
                draw(away.subtitle, size: 10.5, alpha: 0.6, in: NSRect(x: inner.minX, y: top - 14, width: inner.width, height: 14))
            } else {
                let side: CGFloat = 24
                let slot = NSRect(x: card.midX - side / 2, y: top - side, width: side, height: side)
                if let icon = tile.icon {
                    NSGraphicsContext.saveGraphicsState()
                    icon.draw(in: slot, from: .zero, operation: .sourceOver, fraction: dim)
                    NSGraphicsContext.restoreGraphicsState()
                } else if let name = away.symbol,
                          let image = Self.symbolImage(name, pointSize: 20, color: NSColor.white.withAlphaComponent(0.92 * dim)) {
                    let size = image.size
                    image.draw(in: NSRect(x: slot.midX - size.width / 2, y: slot.midY - size.height / 2, width: size.width, height: size.height))
                }
                top -= side + 4
                let isSentence = tile.away?.item?.kind == .intrusion
                if isSentence {
                    draw(away.title, size: 10.5, alpha: 0.85, in: NSRect(x: inner.minX, y: card.minY + 4, width: inner.width, height: top - card.minY - 4))
                } else {
                    draw(away.title, size: 11, weight: .semibold, alpha: 0.92, in: NSRect(x: inner.minX, y: top - 14, width: inner.width, height: 14))
                    top -= 16
                    draw(away.subtitle, size: 10.5, alpha: 0.6, in: NSRect(x: inner.minX, y: card.minY + 3, width: inner.width, height: top - card.minY - 3))
                }
            }
            if let verb = away.verb {
                draw(verb, size: 11, weight: .medium, alpha: hovering ? 1 : 0.8, in: NSRect(x: 4, y: 3, width: bounds.width - 8, height: 14))
            }
        }
        if keyboardFocused {
            let width = CGFloat(NotchFocusController.Style.stroke(increasedContrast: SystemAppearanceCapabilities.current.increaseContrast))
            NSColor.white.setStroke()
            let ring = NSBezierPath(roundedRect: card.insetBy(dx: width / 2, dy: width / 2), xRadius: 14 - width / 2, yRadius: 14 - width / 2)
            ring.lineWidth = width
            ring.stroke()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let away = tile.away { drawAwayCell(away); return }
        let card = self.card
        NSColor(white: hovering ? 0.22 : 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
        if tile.kind.isOngoing {
            drawOngoing(in: card)
        } else if let snapshot = tile.snapshot, let rect = pictureRect {
            let size = NSSize(width: snapshot.width, height: snapshot.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).addClip()
            NSImage(cgImage: snapshot, size: size).draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        } else if let icon = tile.icon {
            icon.draw(in: NSRect(x: card.midX - 22, y: card.midY - 22, width: 44, height: 44))
        }
        if let badge = Self.badge(tile.kind) {
            let circle = NSRect(x: card.minX + 6, y: card.maxY - 24, width: 18, height: 18)
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(ovalIn: circle).fill()
            let size = badge.size
            badge.draw(in: NSRect(x: circle.midX - size.width / 2, y: circle.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
        if let place = tile.place {
            // 别的桌面上的窗口：左上角一枚小签，写它在哪张桌面。
            let text = NSAttributedString(string: place, attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.white,
            ])
            let size = text.size()
            let pill = NSRect(x: card.minX + 6, y: card.maxY - 24, width: ceil(size.width) + 12, height: 18)
            NSColor.black.withAlphaComponent(0.6).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9).fill()
            text.draw(at: NSPoint(x: pill.minX + 6, y: pill.midY - size.height / 2))
        }
        if keyboardFocused {
            let width = CGFloat(NotchFocusController.Style.stroke(increasedContrast: SystemAppearanceCapabilities.current.increaseContrast))
            NSColor.white.setStroke()
            let ring = NSBezierPath(roundedRect: card.insetBy(dx: width / 2, dy: width / 2),
                                    xRadius: 14 - width / 2, yRadius: 14 - width / 2)
            ring.lineWidth = width
            ring.stroke()
        }
        if tile.changed {
            let ring = NSRect(x: card.maxX - 16, y: card.maxY - 16, width: 12, height: 12)
            NSColor.black.setFill()
            NSBezierPath(ovalIn: ring).fill()
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: ring.insetBy(dx: 2, dy: 2)).fill()
        }
        if let icon = tile.icon {
            icon.draw(in: NSRect(x: 0, y: 1, width: 16, height: 16))
        } else if let ongoing = tile.ongoing,
                  let image = Self.symbolImage(ongoing.symbol, pointSize: 11, color: NSColor.white.withAlphaComponent(0.8)) {
            image.draw(in: NSRect(x: 1, y: 3, width: 14, height: 14))
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(hovering ? 1 : 0.8),
        ]
        let title = NSAttributedString(string: tile.title, attributes: attributes)
        title.draw(with: NSRect(x: 20, y: 3, width: bounds.width - 20, height: 14),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
