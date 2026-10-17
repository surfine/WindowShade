// “这一版新开了这几样”（N1，1.0.18）：升级上来、没动过这些开关的人，告诉他一次新开了什么。
//
// 设计稿：docs/design-drafts/首次打开 1.0.17 小样.html 的 N1（720 × 440 pt）。三行各一句，只列真变了的
// （Core/WhatsNew1018Changes.swift 算）；“在设置里改…”打开对应那一页，“看看怎么用”打开欢迎窗口，“好”和关窗口都算看过。
// 这一版先做最简的样子：讲解动画（SettingsExplainer）由欢迎窗口那一路接到 `WhatsNew1018Window.makeHero` 上。

import Cocoa

@MainActor
final class WhatsNew1018Window: NSObject, NSWindowDelegate {
    typealias Group = WhatsNew1018Changes.Group

    /// 讲解动画的挂点：欢迎窗口那一路做好讲解视图后在这里给出一块视图（放在导语和三行之间，宽 640 pt）；
    /// nil 或返回 nil 时不占位置。
    static var makeHero: ((_ groups: [Group]) -> NSView?)?

    /// “在设置里改…”：打开那一行对应的设置页。
    var onChange: ((Group) -> Void)?
    /// “看看怎么用”：打开欢迎窗口（T 的刘海一段）。
    var onTour: (() -> Void)?

    private var window: NSWindow?
    static let width: CGFloat = 720
    private static let padding: CGFloat = 40

    var isVisible: Bool { window?.isVisible == true }

    static var title: String { WSL10n.text("whatsNew1018.title", zh: "这一版新开了这几样") }

    func show(groups: [Group]) {
        let window = self.window ?? makeWindow()
        self.window = window
        let content = makeContent(groups: groups)
        let background = NSVisualEffectView()
        let appearance = SystemAppearanceCapabilities.current
        background.material = SystemAppearancePolicy.usesOpaqueFallback(appearance) ? .contentBackground : .underPageBackground
        background.blendingMode = .withinWindow
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        window.contentView = background
        background.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: Self.width, height: max(320, content.fittingSize.height)))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        wlog("whats-new-1018: shown groups=\(groups.map(\.rawValue).joined(separator: ","))")
    }

    func close() { window?.close() }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 440),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = Self.title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        return window
    }

    private func makeContent(groups: [Group]) -> NSView {
        let eyebrow = NSTextField(labelWithString: "WindowShade 1.0.18")
        eyebrow.font = .systemFont(ofSize: 12)
        eyebrow.textColor = .tertiaryLabelColor
        let title = NSTextField(labelWithString: Self.title)
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.setAccessibilityRole(.staticText)
        let lede = NSTextField(wrappingLabelWithString: WSL10n.text("whatsNew1018.lede", zh: "你没动过的开关，现在是开着的。不想要哪样，在设置里关掉。"))
        lede.font = .systemFont(ofSize: 14)
        lede.textColor = .secondaryLabelColor

        let text = NSStackView(views: [eyebrow, title, lede])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        text.setCustomSpacing(4, after: eyebrow)

        let rows = NSStackView(views: groups.map(makeRow))
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 14

        var sections: [NSView] = [text]
        if let hero = Self.makeHero?(groups) { sections.append(hero) }
        sections.append(rows)

        let tour = NSButton(title: WSL10n.text("whatsNew1018.tour", zh: "看看怎么用"), target: self, action: #selector(tourPressed))
        let ok = NSButton(title: UpdateCopy.ok, target: self, action: #selector(okPressed))
        ok.keyEquivalent = "\r"
        for button in [tour, ok] { button.controlSize = .large; button.bezelStyle = .push }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let foot = NSStackView(views: [spacer, tour, ok])
        foot.orientation = .horizontal
        foot.spacing = 10

        let body = NSStackView(views: sections)
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 24

        let root = NSStackView(views: [body, foot])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 28
        root.edgeInsets = NSEdgeInsets(top: 48, left: Self.padding, bottom: 24, right: Self.padding)
        let inner = Self.width - Self.padding * 2
        for view in [text, rows, foot, body] { view.widthAnchor.constraint(equalToConstant: inner).isActive = true }
        for view in rows.arrangedSubviews { view.widthAnchor.constraint(equalToConstant: inner).isActive = true }
        lede.preferredMaxLayoutWidth = inner
        return root
    }

    private func makeRow(_ group: Group) -> NSView {
        let (symbol, name, detail): (String, String, String)
        switch group {
        case .notch:
            symbol = "macwindow.on.rectangle"
            name = WSL10n.text("settings.section.notch", zh: "刘海")
            detail = WSL10n.text("whatsNew1018.notch.detail", zh: "窗口能收进刘海；按错快捷键时刘海说一句；音乐、下载这些显示在刘海上。")
        case .dockHover:
            symbol = "dock.rectangle"
            name = WSL10n.text("settings.browser.dockHover.name", zh: "Dock 悬停查看窗口")
            detail = WSL10n.text("whatsNew1018.dock.detail", zh: "指针停在 Dock 图标上，这个 App 的窗口排出来。")
        case .shelfAndDock:
            symbol = "tray.full"
            name = WSL10n.text("whatsNew1018.shelf.title", zh: "文件架和 Dock 图标")
            detail = WSL10n.text("whatsNew1018.shelf.detail", zh: "拖到刘海的文件放进文件架；再点一下 Dock 图标，让开这个 App。")
        }
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        icon.setAccessibilityElement(false)
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.preferredMaxLayoutWidth = 470
        let labels = NSStackView(views: [nameLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.setContentHuggingPriority(.init(1), for: .horizontal)

        let change = NSButton(title: WSL10n.text("whatsNew1018.change", zh: "在设置里改…"), target: self, action: #selector(changePressed(_:)))
        change.bezelStyle = .push
        change.identifier = NSUserInterfaceItemIdentifier(group.rawValue)
        change.setAccessibilityHelp(name)
        change.setContentHuggingPriority(.required, for: .horizontal)
        change.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [icon, labels, change])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    @objc private func changePressed(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let group = Group(rawValue: raw) else { return }
        onChange?(group)
    }

    @objc private func tourPressed() {
        window?.close()
        onTour?()
    }

    @objc private func okPressed() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        wlog("whats-new-1018: closed")
    }
}
