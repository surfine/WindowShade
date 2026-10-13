import Cocoa
/// 有界原生会话列表；observed 会话没有 Stop 按钮。审批卡由 A4 独占。
@MainActor final class WS2AgentSessionView: NSView, WS2LeaseContent {
    var interactionSize: NSSize { NSSize(width: 520, height: hasSessions ? 320 : interactionMinimumHeight) }
    var onCancel: (() -> Void)?
    var open: ((WS2.Context) -> Void)?
    var stop: ((WS2.Context) -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    private let rows = NSStackView()
    private var hasSessions = false
    private var bindings: [ObjectIdentifier:(WS2.Context,Bool)] = [:]
    override init(frame:NSRect) {
        super.init(frame:frame)
        let scroll = NSScrollView(frame: bounds); scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let document = WS2AgentSessionDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document; addSubview(scroll)
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 14
        rows.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(rows)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            rows.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            rows.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            rows.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12)])
    }
    required init?(coder:NSCoder) { nil }
    func render(_ sessions:[AgentSessions.Session]) {
        hasSessions = !sessions.isEmpty
        bindings.removeAll()
        for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }
        for session in sessions.prefix(64) {
            let row = NSView(); row.translatesAutoresizingMaskIntoConstraints = false
            let status:String
            switch session.status { case .idle:status=WSL10n.text("agent.status.idle", zh: "空闲");case .running:status=WSL10n.text("agent.status.running", zh: "进行中");case .waiting:status=WSL10n.text("agent.status.waiting", zh: "等你确认");
                case .completed:status=WSL10n.text("agent.status.done", zh: "已完成");case .failed:status=WSL10n.text("agent.status.failed", zh: "发生错误");case .stale:status=WSL10n.text("agent.status.stale", zh: "状态待确认");case .disconnected:status=WSL10n.text("owned.status.disconnected", zh: "已断开") }
            let provider = NSTextField(labelWithString: session.context.session.provider.displayName)
            provider.font = .systemFont(ofSize: 13, weight: .semibold)
            let state = NSTextField(labelWithString: status)
            state.font = .systemFont(ofSize: 11); state.textColor = .white.withAlphaComponent(0.68)
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
            icon.contentTintColor = .white.withAlphaComponent(0.68)
            icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
            let heading = NSStackView(views: [icon, provider, state]); heading.spacing = 6; heading.alignment = .centerY
            let summary = NSTextField(wrappingLabelWithString: String(session.summary.prefix(160)))
            summary.font = .systemFont(ofSize: 11); summary.textColor = .white.withAlphaComponent(0.68)
            summary.maximumNumberOfLines = 2; summary.lineBreakMode = .byWordWrapping
            summary.cell?.truncatesLastVisibleLine = true
            summary.toolTip = summary.stringValue
            let content = NSStackView(views: [heading, summary])
            content.orientation = .vertical; content.alignment = .leading; content.spacing = 3
            content.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(content)
            summary.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            let actions = NSStackView(); actions.orientation = .horizontal; actions.spacing = 8
            actions.setHuggingPriority(.required, for: .horizontal)
            actions.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(actions)
            let owned: Bool
            if case .owned = session.control { owned = true } else { owned = false }
            for (text,isStop) in [(WSL10n.text("notch.action.open", zh: "打开"),false),(WSL10n.text("agent.action.stop", zh: "停止"),true)] {
                if isStop && (!owned || session.status != .running) { continue }
                let button=NSButton(title:text,target:self,action:#selector(pressed(_:)));button.bezelStyle = .rounded
                button.controlSize = .small
                button.setContentHuggingPriority(.required, for: .horizontal)
                button.setContentCompressionResistancePriority(.required, for: .horizontal)
                bindings[ObjectIdentifier(button)] = (session.context,isStop);actions.addArrangedSubview(button)
            }
            rows.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: rows.widthAnchor),
                content.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -12),
                content.topAnchor.constraint(equalTo: row.topAnchor),
                content.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                actions.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                actions.centerYAnchor.constraint(equalTo: row.centerYAnchor)])
        }
        if sessions.isEmpty { rows.addArrangedSubview(NSTextField(labelWithString:WSL10n.text("agent.sessions.none", zh: "还没有编程会话"))) }
    }
    @objc private func pressed(_ sender:NSButton) {
        guard inputIsCurrent(),let (context,isStop) = bindings[ObjectIdentifier(sender)] else { return }
        if isStop { stop?(context) } else { open?(context) }
    }
    override func cancelOperation(_ sender:Any?) { onCancel?() }
    func revoke() { inputIsCurrent = { false }; render([]); bindings.removeAll() }
}

@MainActor private final class WS2AgentSessionDocumentView: NSView {
    override var isFlipped: Bool { true }
}
