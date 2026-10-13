import Cocoa

/// 打开「离开就锁」之前的那一页：会读什么、什么时候可能锁错、怎么取消、只锁不解锁。
/// 按「打开」才打开；按「先不开」、按 Esc 或关掉设置窗口都不打开。每次打开前都弹，不记“看过了”。
@MainActor enum PresenceLockRiskSheet {
    static let title = WSL10n.text("presence.risk.title", zh: "离开就锁会这样做")
    /// 每行一个符号加一句（copy-guide 规则 7），一行一件事。
    static let rows: [(symbol: String, text: String)] = [
        ("iphone", WSL10n.text("presence.risk.row.phone", zh: "看你的手机连不连得上、有没有回应")),
        ("exclamationmark.triangle", WSL10n.text("presence.risk.row.battery", zh: "手机没电、关了蓝牙或放在别的房间，也会锁")),
        ("hand.tap", WSL10n.text("presence.risk.row.tap", zh: "倒数时碰一下键盘或触控板就不锁")),
        ("lock", WSL10n.text("presence.risk.row.lock", zh: "只锁屏，不替你解锁")),
    ]
    static let confirm = WSL10n.text("presence.risk.confirm", zh: "打开")
    static let decline = WSL10n.text("presence.risk.decline", zh: "先不开")

    /// `completion(true)` 只在按了「打开」时。
    static func present(from window: NSWindow?, completion: @escaping @MainActor (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.icon = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 40, weight: .regular))
        alert.accessoryView = makeRows()
        alert.addButton(withTitle: confirm)
        let no = alert.addButton(withTitle: decline)
        no.keyEquivalent = "\u{1b}"
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .alertFirstButtonReturn)
        }
        if let window {
            alert.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(alert.runModal())
        }
    }

    private static func makeRows() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        for row in rows {
            let icon = NSImageView(image: NSImage(systemSymbolName: row.symbol, accessibilityDescription: nil) ?? NSImage())
            icon.symbolConfiguration = .init(pointSize: 15, weight: .regular)
            icon.contentTintColor = .secondaryLabelColor
            icon.setAccessibilityElement(false)
            icon.widthAnchor.constraint(equalToConstant: 22).isActive = true
            let label = NSTextField(wrappingLabelWithString: row.text)
            label.font = SystemAppearancePolicy.font(relativeToBody: 0, weight: .regular)
            label.preferredMaxLayoutWidth = 260
            let line = NSStackView(views: [icon, label])
            line.orientation = .horizontal
            line.alignment = .centerY
            line.spacing = 8
            stack.addArrangedSubview(line)
        }
        stack.layoutSubtreeIfNeeded()
        stack.frame = NSRect(origin: .zero, size: NSSize(width: 290, height: stack.fittingSize.height))
        return stack
    }
}
