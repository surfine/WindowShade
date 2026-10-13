import Cocoa
import UniformTypeIdentifiers

/// 设置里的“私人 App”名单：App 图标 + 名字 + 移除，“添加…”从 /Applications 里选，
/// 另给几个常见建议（默认不勾，点了才加）。名单本身在 Core/PrivateAppList。
enum PrivateAppSuggestions {
    struct Item { let name: String; let bundleID: String }
    static let items: [Item] = [
        Item(name: "信息", bundleID: "com.apple.MobileSMS"),
        Item(name: "邮件", bundleID: "com.apple.mail"),
        Item(name: "微信", bundleID: "com.tencent.xinWeChat"),
        Item(name: "密码", bundleID: "com.apple.Passwords"),
    ]
}

@MainActor
final class PrivateAppListPanel: NSObject {
    static let rowTitle = "私人 App"  // 设置行：显示时走 WSL10n
    static let rowSubtitle = "有人在看、离开就锁、专注时共用"
    private static var current: PrivateAppListPanel?

    private let list: PrivateAppList
    private let panel: NSPanel
    private let listStack = NSStackView()
    private var observer: NSObjectProtocol?
    private weak var parent: NSWindow?

    /// 打开名单；已经开着就带到前面。有设置窗口时作为它的表单，没有就单独显示。
    static func present(from parent: NSWindow?, list: PrivateAppList = .shared) {
        if let open = current { open.panel.makeKeyAndOrderFront(nil); return }
        let controller = PrivateAppListPanel(list: list, parent: parent)
        current = controller
        controller.show()
    }

    private init(list: PrivateAppList, parent: NSWindow?) {
        self.list = list
        self.parent = parent
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 440),
                        styleMask: [.titled, .closable], backing: .buffered, defer: true)
        super.init()
        panel.title = Self.rowTitle
        panel.isReleasedWhenClosed = false
        panel.contentView = buildContent()
        observer = NotificationCenter.default.addObserver(
            forName: PrivateAppList.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    private func show() {
        if let parent {
            parent.beginSheet(panel) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func finish() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        panel.orderOut(nil)
        Self.current = nil
    }

    @objc private func done() {
        if let parent, parent.attachedSheet === panel { parent.endSheet(panel) } else { finish() }
    }

    private func buildContent() -> NSView {
        let title = NSTextField(labelWithString: Self.rowTitle)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let hint = NSTextField(wrappingLabelWithString: Self.rowSubtitle)
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 6
        listStack.translatesAutoresizingMaskIntoConstraints = false
        let holder = FlippedView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(listStack)
        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: holder.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = holder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        holder.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true

        let add = NSButton(title: WSL10n.text("settings.privateApps.add", zh: "添加…"), target: self, action: #selector(addFromDisk))
        let close = NSButton(title: WSL10n.text("settings.privateApps.done", zh: "完成"), target: self, action: #selector(done))
        close.keyEquivalent = "\r"
        let buttons = NSStackView(views: [add, NSView(), close])
        buttons.orientation = .horizontal

        let root = NSStackView(views: [title, hint, scroll, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        root.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        for view in [scroll, buttons] {
            view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true
        }
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        return root
    }

    private func reload() {
        listStack.arrangedSubviews.forEach { listStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let ids = list.bundleIDs
        if ids.isEmpty {
            let empty = NSTextField(wrappingLabelWithString: WSL10n.text("settings.privateApps.empty", zh: "名单里还没有 App"))
            empty.textColor = .secondaryLabelColor
            listStack.addArrangedSubview(empty)
        }
        for id in ids { listStack.addArrangedSubview(row(bundleID: id, removable: true)) }
        let pending = PrivateAppSuggestions.items.filter { !list.contains(bundleID: $0.bundleID) }
        if !pending.isEmpty {
            let label = NSTextField(labelWithString: WSL10n.text("settings.privateApps.common", zh: "常见的"))
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = .secondaryLabelColor
            listStack.addArrangedSubview(label)
            listStack.setCustomSpacing(14, after: listStack.arrangedSubviews[listStack.arrangedSubviews.count - 2])
            for item in pending { listStack.addArrangedSubview(row(bundleID: item.bundleID, fallbackName: item.name, removable: false)) }
        }
    }

    private func row(bundleID: String, fallbackName: String? = nil, removable: Bool) -> NSView {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? fallbackName ?? bundleID
        let icon = NSImageView()
        icon.image = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let label = NSTextField(labelWithString: name)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let button = NSButton(title: removable ? WSL10n.text("settings.privateApps.remove", zh: "移除") : WSL10n.text("settings.privateApps.addShort", zh: "添加"), target: self,
                              action: removable ? #selector(removeTapped(_:)) : #selector(addSuggestionTapped(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(bundleID)
        button.setAccessibilityLabel(WSL10n.text("settings.privateApps.a11y", zh: "%@%@", removable ? WSL10n.text("settings.privateApps.remove", zh: "移除") : WSL10n.text("settings.privateApps.addShort", zh: "添加"), name))
        let row = NSStackView(views: [icon, label, NSView(), button])
        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    @objc private func removeTapped(_ sender: NSButton) {
        if let id = sender.identifier?.rawValue { list.remove(bundleID: id) }
    }

    @objc private func addSuggestionTapped(_ sender: NSButton) {
        if let id = sender.identifier?.rawValue { list.add(bundleID: id) }
    }

    @objc private func addFromDisk() {
        let open = NSOpenPanel()
        open.directoryURL = URL(fileURLWithPath: "/Applications")
        open.allowedContentTypes = [.applicationBundle]
        open.allowsMultipleSelection = true
        open.canChooseDirectories = false
        open.prompt = WSL10n.text("settings.privateApps.addShort", zh: "添加")
        open.beginSheetModal(for: panel) { [weak self] response in
            let urls = open.urls
            MainActor.assumeIsolated {
                guard response == .OK, let self else { return }
                for url in urls {
                    if let id = Bundle(url: url)?.bundleIdentifier { self.list.add(bundleID: id) }
                }
            }
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
