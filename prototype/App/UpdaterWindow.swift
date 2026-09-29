// 应用内更新：更新小窗。版本、改动最多三条、“更新前，窗口会先恢复原样。”、按钮；进行中只显示一行和进度条。
// 只有要他动手或出了结果时才出现（手动检查、他点了菜单那一项、没装上、换回了、要先做一步）。

import Cocoa

struct UpdaterWindowContent {
    struct Button {
        var title: String
        var action: () -> Void
        init(_ title: String, _ action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }
    }

    var title: String
    var lines: [String] = []
    var notes: [String] = []
    var reminder: String?
    var showsReleaseLink = false
    /// nil：没有进度条；-1：不确定进度；0…1：确定进度。
    var progress: Double?
    var buttons: [Button] = []

    static func message(_ title: String, _ text: String, ok: @escaping () -> Void) -> UpdaterWindowContent {
        UpdaterWindowContent(title: title, lines: [text], buttons: [Button(UpdateCopy.ok, ok)])
    }

    static func progress(_ title: String, _ text: String, fraction: Double?) -> UpdaterWindowContent {
        UpdaterWindowContent(title: title, lines: [text], progress: fraction ?? -1)
    }
}

@MainActor
final class UpdaterWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var progressBar: NSProgressIndicator?
    private var actions: [() -> Void] = []
    private var showingProgress = false

    func show(_ content: UpdaterWindowContent) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = makeContent(content)
        panel.layoutIfNeeded()
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 420, height: 160))
        if !panel.isVisible { panel.center() }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func updateProgress(_ fraction: Double) {
        guard let bar = progressBar else { return }
        bar.isIndeterminate = false
        bar.doubleValue = fraction
    }

    func bringToFront() {
        guard let panel, panel.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        showingProgress = false
    }

    func closeIfShowingProgress() {
        if showingProgress { close() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
                            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        panel.title = "WindowShade"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.delegate = self
        return panel
    }

    private func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font
        field.textColor = color
        field.preferredMaxLayoutWidth = 348
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    private func makeContent(_ content: UpdaterWindowContent) -> NSView {
        actions = content.buttons.map(\.action)
        progressBar = nil
        showingProgress = content.progress != nil

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 48).isActive = true

        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 6
        text.addArrangedSubview(label(content.title, font: .boldSystemFont(ofSize: NSFont.systemFontSize + 2)))
        for line in content.lines {
            text.addArrangedSubview(label(line, font: .systemFont(ofSize: NSFont.systemFontSize)))
        }
        for note in content.notes.prefix(3) {
            text.addArrangedSubview(label("• " + note, font: .systemFont(ofSize: NSFont.smallSystemFontSize),
                                          color: .secondaryLabelColor))
        }
        if content.showsReleaseLink {
            let link = NSButton(title: UpdateCopy.fullNotes, target: self, action: #selector(openReleaseNotes))
            link.isBordered = false
            link.contentTintColor = .linkColor
            link.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            text.addArrangedSubview(link)
        }
        if let reminder = content.reminder {
            text.addArrangedSubview(label(reminder, font: .systemFont(ofSize: NSFont.smallSystemFontSize),
                                          color: .secondaryLabelColor))
        }
        if let progress = content.progress {
            let bar = NSProgressIndicator()
            bar.style = .bar
            bar.minValue = 0
            bar.maxValue = 1
            bar.isIndeterminate = progress < 0
            if progress < 0 { bar.startAnimation(nil) } else { bar.doubleValue = progress }
            bar.widthAnchor.constraint(equalToConstant: 348).isActive = true
            text.addArrangedSubview(bar)
            progressBar = bar
        }

        let top = NSStackView(views: [icon, text])
        top.orientation = .horizontal
        top.alignment = .top
        top.spacing = 14

        let root = NSStackView(views: [top])
        root.orientation = .vertical
        root.alignment = .trailing
        root.spacing = 16
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 18, right: 20)
        root.widthAnchor.constraint(equalToConstant: 440).isActive = true

        if !content.buttons.isEmpty {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 10
            // 默认按钮放最右边：苹果的对话框按钮顺序。
            for (index, button) in content.buttons.enumerated().reversed() {
                let control = NSButton(title: button.title, target: self, action: #selector(buttonPressed(_:)))
                control.tag = index
                control.bezelStyle = .push
                if index == 0 { control.keyEquivalent = "\r" }
                row.addArrangedSubview(control)
            }
            root.addArrangedSubview(row)
        }
        return root
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }

    @objc private func openReleaseNotes() {
        NSWorkspace.shared.open(UpdateLinks.releaseNotes)
    }
}
