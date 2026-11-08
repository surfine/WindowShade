import Cocoa
/// 有界原生会话列表；observed 会话没有 Stop 按钮。审批卡由 A4 独占。
@MainActor final class WS2AgentSessionView: NSView, NotchInteractiveContent {
    var onCancel: (() -> Void)?
    var open: ((WS2.Context) -> Void)?
    var stop: ((WS2.Context) -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    private let rows = NSStackView()
    private var bindings: [ObjectIdentifier:(WS2.Context,Bool)] = [:]
    override init(frame:NSRect) {
        super.init(frame:frame)
        let scroll = NSScrollView(frame:bounds); scroll.autoresizingMask = [.width,.height]
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = rows; addSubview(scroll)
        rows.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive = true
    }
    required init?(coder:NSCoder) { nil }
    func render(_ sessions:[AgentSessions.Session]) {
        bindings.removeAll()
        for view in rows.arrangedSubviews { rows.removeArrangedSubview(view); view.removeFromSuperview() }
        for session in sessions.prefix(64) {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 8
            let status:String
            switch session.status { case .idle:status="空闲";case .running:status="进行中";case .waiting:status="等你确认";
                case .completed:status="已完成";case .failed:status="发生错误";case .stale:status="状态待确认";case .disconnected:status="已断开" }
            let label = NSTextField(wrappingLabelWithString:session.context.session.provider.displayName+" · "+status+"\n"+String(session.summary.prefix(160)))
            label.setAccessibilityLabel(label.stringValue); row.addArrangedSubview(label)
            let owned: Bool
            if case .owned = session.control { owned = true } else { owned = false }
            for (text,isStop) in [("打开",false),("停止",true)] {
                if isStop && (!owned || session.status != .running) { continue }
                let button=NSButton(title:text,target:self,action:#selector(pressed(_:)));button.bezelStyle = .rounded
                bindings[ObjectIdentifier(button)] = (session.context,isStop);row.addArrangedSubview(button)
            }
            rows.addArrangedSubview(row)
        }
        if sessions.isEmpty { rows.addArrangedSubview(NSTextField(labelWithString:"还没有编程会话")) }
    }
    @objc private func pressed(_ sender:NSButton) {
        guard inputIsCurrent(),let (context,isStop) = bindings[ObjectIdentifier(sender)] else { return }
        if isStop { stop?(context) } else { open?(context) }
    }
    override func cancelOperation(_ sender:Any?) { onCancel?() }
    func revoke() { inputIsCurrent = { false }; render([]); bindings.removeAll() }
}
