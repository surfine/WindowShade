import Cocoa
import ObjectiveC
/// 有界原生会话列表；observed 会话没有 Stop 按钮。审批卡由 A4 独占。
@MainActor final class WS2AgentSessionView: NSView, WS2LeaseContent {
    var interactionSize: NSSize { NSSize(width: 520, height: hasSessions ? 320 : interactionMinimumHeight) }
    var onCancel: (() -> Void)?
    var open: ((WS2.Context) -> Void)?
    var stop: ((WS2.Context) -> Void)?
    /// A3 卡片上停一下「看一眼那扇终端」：参数是会话目录、终端身份、卡片在屏幕上的位置。
    var peek: ((String, TerminalIdentity?, NSRect) -> Void)?
    var peekEnd: (() -> Void)?
    private var peekTimer: Timer?
    private var peekedRow: ObjectIdentifier?
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
        rowContexts.removeAll()
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
            installHover(row: row, context: session.context)
            rowContexts[ObjectIdentifier(row)] = session.context
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
    /// 悬停半秒才看；移开即收。找不找得到窗口由 peek 控制器自己判，这里只报位置。
    private func installHover(row: NSView, context: WS2.Context) {
        let tracker = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .mouseEnteredAndExited, .activeAlways],
                                     owner: self, userInfo: ["row": ObjectIdentifier(row)])
        row.addTrackingArea(tracker)
        objc_setAssociatedObject(row, &Self.peekAssociationKey, tracker, .OBJC_ASSOCIATION_RETAIN)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { cancelPeek() }
    }
    override func mouseEntered(with event: NSEvent) {
        guard let id = event.trackingArea?.userInfo?["row"] as? ObjectIdentifier,
              let row = rowFor(id), id != peekedRow else { return }
        cancelPeek()
        peekedRow = ObjectIdentifier(row)
        let anchor = row.convert(row.bounds, to: nil)
        let frame = window?.convertToScreen(anchor) ?? .zero
        peekTimer = Timer.scheduledTimer(withTimeInterval: WS2SessionTerminalPeekController.dwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let cwd = self.cwd(for: row) else { return }
                self.peek?(cwd, self.terminal(for: row), frame)
            }
        }
    }
    override func mouseExited(with event: NSEvent) {
        cancelPeek()
    }
    private func rowFor(_ id: ObjectIdentifier) -> NSView? {
        subviewsRecursive().first { ObjectIdentifier($0) == id }
    }
    private func subviewsRecursive() -> [NSView] {
        var out: [NSView] = []
        var queue: [NSView] = [self]
        while let view = queue.popLast() {
            out.append(view)
            queue.append(contentsOf: view.subviews)
        }
        return out
    }

    private func cancelPeek() {
        peekTimer?.invalidate(); peekTimer = nil
        if peekedRow != nil { peekedRow = nil; peekEnd?() }
    }
    /// 行对象 → 会话目录／终端身份：渲染时记下（row 的关联对象存 index）。
    private var rowContexts: [ObjectIdentifier: WS2.Context] = [:]
    private func cwd(for row: NSView) -> String? { rowContexts[ObjectIdentifier(row)]?.projectID }
    private func terminal(for row: NSView) -> TerminalIdentity? {
        guard let id = rowContexts[ObjectIdentifier(row)]?.session.id else { return nil }
        return (NSApp.delegate as? AppDelegate)?.ws2Runtime.terminalForSession(id)
    }
    private nonisolated(unsafe) static var peekAssociationKey: UInt8 = 0

    @objc private func pressed(_ sender:NSButton) {
        guard inputIsCurrent(),let (context,isStop) = bindings[ObjectIdentifier(sender)] else { return }
        if isStop { stop?(context) } else { open?(context) }
    }
    override func cancelOperation(_ sender:Any?) { onCancel?() }
    func revoke() { inputIsCurrent = { false }; cancelPeek(); render([]); bindings.removeAll() }

    // 页面级探针：不进鼠标事件，直接驱动悬停路径。
    func probeDwell(context: WS2.Context, frame: NSRect) {
        peek?(context.projectID, (NSApp.delegate as? AppDelegate)?.ws2Runtime.terminalForSession(context.session.id), frame)
    }
    func probeEndPeek() { peekEnd?() }
}

@MainActor private final class WS2AgentSessionDocumentView: NSView {
    override var isFlipped: Bool { true }
}
