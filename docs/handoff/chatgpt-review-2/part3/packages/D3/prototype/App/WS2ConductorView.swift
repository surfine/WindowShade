import Cocoa
/// 可插入现有 NotchPanel.setInteraction 的原生视图；不创建窗口，不批准助手。
@MainActor final class WS2ConductorView: NSView, NotchInteractiveContent {
    enum Action { case sendDraft, discardDraft, confirmCost, stopTurn, leave, session(Int) }
    var onCancel: (() -> Void)?
    var onAction: ((Action) -> Void)?
    private let stack = NSStackView(), title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let editor = NSTextField(string: "")
    private let path = CAShapeLayer()
    private var buttons: [ObjectIdentifier:Action] = [:]
    var editedDraft: String { editor.stringValue }
    // 宿主必须在租约撤销时先置 false 再移除视图。
    var inputIsCurrent: (() -> Bool) = { false }
    override init(frame:NSRect) {
        super.init(frame:frame); wantsLayer = true
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:leadingAnchor,constant:16),
            stack.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-16),stack.topAnchor.constraint(equalTo:topAnchor,constant:12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo:bottomAnchor,constant:-12)])
        title.font = .systemFont(ofSize:13,weight:.semibold); title.textColor = .white
        detail.font = .systemFont(ofSize:11); detail.textColor = .secondaryLabelColor
        editor.setAccessibilityLabel("待发送草稿"); editor.isEditable = true
        path.strokeColor = NSColor.white.cgColor; path.fillColor = nil; path.lineWidth = 2; layer?.addSublayer(path)
    }
    required init?(coder:NSCoder) { nil }
    @discardableResult func render(_ state: ConductorNotch) -> Bool {
        buttons.removeAll(); path.path = nil
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        title.stringValue = state.text; detail.stringValue = ""
        stack.addArrangedSubview(title)
        switch state {
        case .hidden: isHidden = true; return true
        case .approval, .voiceChallenge, .authenticating:
            // 安全审批必须进入现有 NotchAuthenticationController；不把它降级成普通详情卡。
            title.stringValue = "请在 Mac 上完成确认"; isHidden = false; return false
        case .trajectory(let points,let beats):
            let p = CGMutablePath(); let clean = points.filter { $0.x.isFinite && $0.y.isFinite }.suffix(256)
            for (i,v) in clean.enumerated() {
                let point = CGPoint(x:16+CGFloat(min(1,max(0,v.x)))*max(0,bounds.width-32),y:16+min(1,max(0,v.y))*48)
                if i == 0 { p.move(to:point) } else { p.addLine(to:point) }
            }
            CATransaction.begin(); CATransaction.setDisableActions(true); path.path = p; CATransaction.commit()
            detail.stringValue = "\(beats) 拍 · 抬手后判定"; stack.addArrangedSubview(detail)
        case .sessions(let labels,let selected):
            for (i,label) in labels.prefix(64).enumerated() { button((i == selected ? "✓ " : "")+label,.session(i)) }
        case .draft(let text):
            editor.stringValue = text; stack.addArrangedSubview(editor); button("发送",.sendDraft); button("丢弃",.discardDraft)
        case .cost: button("确认费用",.confirmCost); button("取消",.leave)
        case .running, .steering: button("停止这一轮",.stopTurn)
        case .discardDraft: button("丢弃草稿",.discardDraft)
        case .waitingForAudio, .listening, .transcribing, .connected, .domain, .staged, .next, .sent, .accepted,
             .steered, .stopping, .stopped, .completed, .disconnected, .revoked, .exited, .muted, .message:
            button("返回",.leave)
        }
        isHidden = false; return true
    }
    private func button(_ label:String,_ action:Action) {
        let button = NSButton(title:label,target:self,action:#selector(pressed(_:)))
        button.bezelStyle = .rounded; buttons[ObjectIdentifier(button)] = action; stack.addArrangedSubview(button)
    }
    @objc private func pressed(_ sender:NSButton) {
        guard inputIsCurrent(),let action = buttons[ObjectIdentifier(sender)] else { return }
        onAction?(action)
    }
    override func cancelOperation(_ sender:Any?) { onCancel?() }
    func revoke() { buttons.removeAll(); inputIsCurrent = { false }; editor.stringValue = ""; title.stringValue = ""; detail.stringValue = ""; path.path=nil }
}
