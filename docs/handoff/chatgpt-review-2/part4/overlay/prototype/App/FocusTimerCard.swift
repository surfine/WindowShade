import Cocoa
import QuartzCore
@MainActor final class FocusTimerCard: NSView, WS2LeaseContent {
    var onCancel: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    var interactionSize: NSSize { NSSize(width: 320, height: 210) }
    func revoke() { inputIsCurrent = { false }; ring.removeAllAnimations() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    private let time = NSTextField(labelWithString:"")
    private let detail = NSTextField(labelWithString:"")
    private let ring = CAShapeLayer()
    private let pause = NSButton()
    private let skip = NSButton()
    private let end = NSButton()
    private let host: FocusTimerHost
    init(host:FocusTimerHost) {
        self.host = host; super.init(frame:.zero); wantsLayer = true; layer?.addSublayer(ring)
        time.font = .monospacedDigitSystemFont(ofSize:28,weight:.medium)
        detail.font = .systemFont(ofSize:12); detail.textColor = .secondaryLabelColor
        let buttons = NSStackView(views:[pause,skip,end]); buttons.orientation = .horizontal
        let stack = NSStackView(views:[time,detail,buttons]); stack.orientation = .vertical; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:centerXAnchor),stack.centerYAnchor.constraint(equalTo:centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant:240),heightAnchor.constraint(greaterThanOrEqualToConstant:170)])
        configure(pause,"pause.fill","暂停",#selector(pauseAction)); configure(skip,"forward.end.fill","跳过",#selector(skipAction))
        configure(end,"stop.fill","结束",#selector(endAction))
    }
    required init?(coder:NSCoder) { nil }
    private func configure(_ b:NSButton,_ symbol:String,_ label:String,_ action:Selector) {
        b.image = NSImage(systemSymbolName:symbol,accessibilityDescription:label); b.imagePosition = .imageOnly
        b.bezelStyle = .circular; b.target = self; b.action = action; b.toolTip = label; b.setAccessibilityLabel(label)
    }
    override func layout() {
        super.layout(); ring.frame = bounds
        ring.path = CGPath(ellipseIn:bounds.insetBy(dx:12,dy:12),transform:nil)
    }
    func render(_ model:FocusTimer,at now:WS2.Instant) {
        time.stringValue = model.phase == .idle ? "开始专注" : model.expandedText(at:now)
        detail.stringValue = model.phase == .rest ? "看看远处" : "今天完成 \(model.completedToday) 个"
        let action = model.phase == .idle ? "开始" : model.isPaused ? "继续" : "暂停"
        configure(pause,model.phase == .idle || model.isPaused ? "play.fill" : "pause.fill",action,#selector(pauseAction))
        skip.isEnabled = model.phase != .idle; end.isEnabled = model.phase != .idle
        ring.removeAllAnimations(); ring.fillColor = NSColor.clear.cgColor; ring.lineWidth = 2
        ring.strokeColor = (model.phase == .rest ? NSColor.systemGreen : NSColor.systemRed).cgColor
        let total = model.phaseDuration
        let fraction = model.phase == .idle ? 0 : Double(model.remaining(at:now))/Double(total)
        CATransaction.begin(); CATransaction.setDisableActions(true); ring.strokeEnd = min(1,max(0,fraction)); CATransaction.commit()
        if !model.isPaused,model.phase != .idle,window != nil {
            let a = CABasicAnimation(keyPath:"strokeEnd"); a.fromValue = ring.strokeEnd; a.toValue = 0
            a.duration = Double(model.remaining(at:now))/1e9; a.timingFunction = CAMediaTimingFunction(name:.linear)
            ring.add(a,forKey:"countdown")
            if model.phase == .rest, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let breath = CABasicAnimation(keyPath:"opacity"); breath.fromValue = 0.45; breath.toValue = 1
                breath.duration = 2; breath.autoreverses = true; breath.repeatCount = .infinity; ring.add(breath,forKey:"rest")
            }
        }
        setAccessibilityLabel("\(time.stringValue)，\(detail.stringValue)")
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { ring.removeAllAnimations() } }
    @objc private func pauseAction() { guard inputIsCurrent() else { return }; host.handle(host.model.phase == .idle ? .start : host.model.isPaused ? .resume : .pause) }
    @objc private func skipAction() { guard inputIsCurrent() else { return }; host.handle(.skip) }
    @objc private func endAction() { guard inputIsCurrent() else { return }; host.handle(.end) }
}
