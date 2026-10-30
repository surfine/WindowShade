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

    // MARK: 从琥珀点长出来

    /// 内容层以琥珀点为原点放大到位（bloom），透明度同时淡入（calm）；减少动态效果只在原处淡入。
    /// 只播一次：卡被挂起后回来、再次进窗口都不重播。已有动画在跑时从当前画面接着走（位置连续）。
    @MainActor final class Bloom {
        private(set) var played = false
        static func spring(_ token: SessionCardStyle.Token) -> Motion.Spring {
            switch token {
            case .calm: return .calm
            case .settle: return .settle
            case .bloom: return .bloom
            case .reducedNotch: return .reducedNotch
            }
        }
        func playOnce(on content: NSView, origin: CGPoint, reduced: Bool = Motion.reduced) {
            guard !played, let layer = content.layer, content.bounds.width > 0 else { return }
            played = true
            let plan = SessionCardStyle.plan(.enter, reduced: reduced)
            let fadeToken = Self.spring(SessionCardStyle.plan(.resume, reduced: reduced).token)
            let fade = Motion.spring(fadeToken, keyPath: "opacity")
            fade.fromValue = 0; fade.toValue = 1
            layer.opacity = 1
            layer.add(fade, forKey: "session.card.fade")
            guard plan.scale != 1 else { return }
            let center = CGPoint(x: content.bounds.midX, y: content.bounds.midY)
            let start = SessionCardStyle.layerTransform(scale: plan.scale, about: origin, center: center)
            let grow = Motion.spring(Self.spring(plan.token), keyPath: "transform")
            grow.fromValue = NSValue(caTransform3D: CATransform3DMakeAffineTransform(start))
            grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            layer.add(grow, forKey: "session.card.grow")
        }
        /// 视图离开窗口时清掉在途动画，下次不会带着半截动画出现。
        func cancel(on content: NSView) {
            content.layer?.removeAnimation(forKey: "session.card.fade")
            content.layer?.removeAnimation(forKey: "session.card.grow")
        }
    }
}
