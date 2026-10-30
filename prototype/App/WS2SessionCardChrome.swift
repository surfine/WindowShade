import Cocoa
import QuartzCore

/// 编程会话审批卡的共用外观（设计稿《刘海里的编程会话》§3）：琥珀点、药丸按钮、风险一行，
/// 以及内容从右耳琥珀点长出来的弹簧。两张卡（Claude Code 的 hook、Codex 的命令审批）共用，只换皮，不碰放行逻辑。
@MainActor enum WS2SessionCardChrome {
    // MARK: 药丸按钮

    /// 稿里的 `.pill`：高 28、两端全圆；主按钮用强调色，其余是白 14%。`symbol` 在字前面（Touch ID 那一个带 touchid）。
    static func stylePill(_ button: NSButton, primary: Bool, symbol: String? = nil) {
        button.isBordered = false; button.wantsLayer = true
        button.layer?.cornerRadius = SessionCardStyle.buttonHeight / 2
        button.layer?.backgroundColor = (primary ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.14)).cgColor
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            button.contentTintColor = .white; button.imagePosition = .imageLeading
        }
        button.focusRingType = .exterior
    }

    static func pillWidth(_ button: NSButton) -> CGFloat { ceil(button.attributedTitle.size().width) + 28 + (button.image == nil ? 0 : 18) }

    /// 把按钮从右往左排进 `bottom` 那一行；返回最左边的 x。
    @discardableResult
    static func layoutPills(_ buttons: [NSButton], rightEdge: CGFloat) -> CGFloat {
        var x = rightEdge
        for button in buttons where !button.isHidden {
            let width = pillWidth(button)
            x -= width
            button.frame = NSRect(x: x, y: SessionCardStyle.buttonBottom, width: width, height: SessionCardStyle.buttonHeight)
            x -= SessionCardStyle.buttonGap
        }
        return x
    }

    // MARK: 零件

    /// 右耳的琥珀点（systemOrange 实心；和“出了问题”靠形状区分，点对描边）。
    static func makeAmberDot() -> NSView {
        let dot = NSView(); dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        dot.layer?.cornerRadius = SessionCardStyle.dotDiameter / 2
        dot.setAccessibilityElement(false)
        return dot
    }

    static func makeEar() -> NSImageView {
        let ear = NSImageView()
        ear.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        ear.contentTintColor = .white; ear.symbolConfiguration = .init(pointSize: 13, weight: .semibold)
        return ear
    }

    /// 风险一行：符号 + 一句原因，不只靠颜色。
    @MainActor final class RiskLine: NSView {
        private let icon = NSImageView()
        private let label = NSTextField(labelWithString: "")
        init(note: AgentApprovalCard.RiskNote) {
            super.init(frame: .zero)
            icon.image = NSImage(systemSymbolName: note.symbol, accessibilityDescription: nil)
            icon.contentTintColor = .systemOrange; icon.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
            label.stringValue = note.text; label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .white.withAlphaComponent(0.85)
            label.lineBreakMode = .byTruncatingTail; label.maximumNumberOfLines = 1
            addSubview(icon); addSubview(label)
            setAccessibilityElement(true); setAccessibilityRole(.staticText)
            setAccessibilityLabel(note.text)
        }
        required init?(coder: NSCoder) { nil }
        override func layout() {
            super.layout()
            icon.frame = NSRect(x: 0, y: (bounds.height - 13) / 2, width: 13, height: 13)
            label.frame = NSRect(x: 18, y: 0, width: max(0, bounds.width - 18), height: bounds.height)
        }
    }

    // MARK: 从琥珀点长出来、缩回琥珀点

    /// 内容层以琥珀点为原点放大到位（bloom），透明度同时淡入（calm）；缩回时反过来（settle）。
    /// 减少动态效果：只在原处淡入淡出。缩回可以被打断：新卡接上来时从此刻的位置和速度继续（`snapshot` / `resume`）。
    @MainActor final class Bloom {
        private(set) var played = false
        private(set) var isRetreating = false
        /// 新卡接在一次缩回后面时，第一次进场从这里起步。
        var resume: SessionCardStyle.RetreatSnapshot?
        private var run: (spring: SessionCardStyle.SpringRun, start: CFTimeInterval)?
        private static let scaleKey = "session.card.scale", fadeKey = "session.card.fade"
        private static let txKey = "session.card.tx", tyKey = "session.card.ty"

        static func spring(_ token: SessionCardStyle.Token) -> Motion.Spring {
            switch token {
            case .calm: return .calm
            case .settle: return .settle
            case .bloom: return .bloom
            case .reducedNotch: return .reducedNotch
            }
        }

        /// 层的锚点在层里的位置（AppKit 的背层锚点是左下 (0,0)，不是中心）：缩放的不动点要按它算。
        private static func anchorCenter(_ content: NSView, _ layer: CALayer) -> CGPoint {
            CGPoint(x: content.bounds.width * layer.anchorPoint.x, y: content.bounds.height * layer.anchorPoint.y)
        }

        /// 把层从缩放 `from` 弹到 `to`（以 `origin` 为不动点），初速度是缩放每秒变多少。
        private func animateScale(_ layer: CALayer, content: NSView, origin: CGPoint, from: CGFloat, to: CGFloat,
                                  velocity: CGFloat, token: SessionCardStyle.Token) {
            let center = Self.anchorCenter(content, layer)
            let dx = origin.x - center.x, dy = origin.y - center.y
            func add(_ keyPath: String, _ key: String, _ a: CGFloat, _ b: CGFloat, _ v: CGFloat) {
                let animation = Motion.spring(Self.spring(token), keyPath: keyPath)
                animation.fromValue = a; animation.toValue = b; animation.initialVelocity = v
                layer.add(animation, forKey: key)
            }
            add("transform.scale", Self.scaleKey, from, to, velocity)
            add("transform.translation.x", Self.txKey, (1 - from) * dx, (1 - to) * dx, -velocity * dx)
            add("transform.translation.y", Self.tyKey, (1 - from) * dy, (1 - to) * dy, -velocity * dy)
        }

        private func setModel(_ layer: CALayer, content: NSView, origin: CGPoint, scale: CGFloat, opacity: Float) {
            let center = Self.anchorCenter(content, layer)
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.setAffineTransform(SessionCardStyle.layerTransform(scale: scale, about: origin, center: center))
            layer.opacity = opacity
            CATransaction.commit()
        }

        func playOnce(on content: NSView, origin: CGPoint, reduced: Bool = Motion.reduced) {
            guard !played, let layer = content.layer, content.bounds.width > 0 else { return }
            played = true
            let plan = SessionCardStyle.plan(.enter, reduced: reduced)
            let fadeToken = SessionCardStyle.plan(.resume, reduced: reduced).token
            // 接在缩回后面：从那一刻的状态起步，速度反向接上。
            let start = resume.map { SessionCardStyle.pose(progress: $0.progress, plan: SessionCardStyle.plan(.retreat, reduced: reduced)) }
            let fromOpacity = start?.opacity ?? 0
            let fade = Motion.spring(Self.spring(fadeToken), keyPath: "opacity")
            fade.fromValue = fromOpacity; fade.toValue = 1
            fade.initialVelocity = CGFloat(-(resume?.velocity ?? 0))
            setModel(layer, content: content, origin: origin, scale: 1, opacity: 1)
            layer.add(fade, forKey: Self.fadeKey)
            guard plan.scale != 1 else { resume = nil; return }
            let fromScale = start?.scale ?? plan.scale
            let dsdt = CGFloat(-(resume?.velocity ?? 0)) * (1 - plan.scale)
            animateScale(layer, content: content, origin: origin, from: fromScale, to: 1, velocity: dsdt, token: plan.token)
            resume = nil
        }

        /// 缩回琥珀点：内容缩向点并淡出，终点是口子，不回弹。减少动态效果：原处淡出。
        func retreat(on content: NSView, origin: CGPoint, reduced: Bool = Motion.reduced, completion: @escaping () -> Void) {
            guard let layer = content.layer, !isRetreating else { completion(); return }
            isRetreating = true
            let plan = SessionCardStyle.plan(.retreat, reduced: reduced)
            let spring = Self.spring(plan.token)
            // 进场还在播时从当前画面接着缩回（位置连续）。
            let presentation = layer.presentation()
            let fromOpacity = presentation?.opacity ?? layer.opacity
            let fromScale = CGFloat(presentation?.value(forKeyPath: "transform.scale") as? Double ?? 1)
            layer.removeAnimation(forKey: Self.fadeKey)
            layer.removeAnimation(forKey: Self.scaleKey); layer.removeAnimation(forKey: Self.txKey); layer.removeAnimation(forKey: Self.tyKey)
            run = (SessionCardStyle.SpringRun(response: spring.response, dampingRatio: spring.dampingRatio, from: 0, to: 1), CACurrentMediaTime())
            setModel(layer, content: content, origin: origin, scale: plan.scale, opacity: 0)
            CATransaction.begin()
            CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
            let fade = Motion.spring(spring, keyPath: "opacity")
            fade.fromValue = fromOpacity; fade.toValue = 0
            layer.add(fade, forKey: Self.fadeKey)
            if plan.scale != 1 { animateScale(layer, content: content, origin: origin, from: fromScale, to: plan.scale, velocity: 0, token: plan.token) }
            CATransaction.commit()
        }

        /// 缩回走到哪了、有多快；没在缩回就是 nil。
        func snapshot(at now: CFTimeInterval = CACurrentMediaTime()) -> SessionCardStyle.RetreatSnapshot? {
            guard isRetreating, let run else { return nil }
            let t = now - run.start
            return .init(progress: run.spring.position(at: t), velocity: run.spring.velocity(at: t))
        }

        /// 视图离开窗口时清掉在途动画，下次不会带着半截动画出现。
        func cancel(on content: NSView) {
            for key in [Self.fadeKey, Self.scaleKey, Self.txKey, Self.tyKey] { content.layer?.removeAnimation(forKey: key) }
        }
    }
}

/// 能“缩回琥珀点”的卡：被岛收走时，岛先让它播完缩回再拿掉视图（见 `NotchCanvasView.setAuthentication`）。
@MainActor protocol SessionCardRetreating: AnyObject {
    /// 收走时要不要缩回。交给 Touch ID 之类的“换成别的画面”不缩回。
    var retreatsOnRemoval: Bool { get set }
    func beginRetreat(completion: @escaping () -> Void)
    func retreatSnapshot() -> SessionCardStyle.RetreatSnapshot?
    func adoptRetreat(_ snapshot: SessionCardStyle.RetreatSnapshot)
}
