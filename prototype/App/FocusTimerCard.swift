import Cocoa
import QuartzCore
@MainActor final class FocusTimerCard: NSView, WS2LeaseContent {
    var onCancel: (() -> Void)?
    var inputIsCurrent: (() -> Bool) = { false }
    /// 休息视图照稿约 2.7:1（324×120）；其余照旧。
    var interactionSize: NSSize { resting ? NSSize(width: 324, height: 120) : NSSize(width: 320, height: 210) }
    private var resting = false
    func revoke() { inputIsCurrent = { false }; ring.removeAllAnimations(); breath.removeAllAnimations() }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    private let time = NSTextField(labelWithString:"")
    private let detail = NSTextField(labelWithString:"")
    private let ring = CAShapeLayer()
    private let breath = CAShapeLayer()
    private let restTime = NSTextField(labelWithString:"")
    private let restHint = NSTextField(labelWithString:"看看远处 · 点一下回来")
    private let stack = NSStackView()
    /// 休息视图右上角的小文字按钮：留一条结束休息的路（沿用 .skip）。
    private let restSkip = NSButton(title:"跳过休息",target:nil,action:nil)
    /// 休息绿 #5FD38A。
    private static let restGreen = NSColor(srgbRed:0x5F/255,green:0xD3/255,blue:0x8A/255,alpha:1)
    private let pause = NSButton()
    private let skip = NSButton()
    private let end = NSButton()
    private let host: FocusTimerHost
    init(host:FocusTimerHost) {
        self.host = host; super.init(frame:.zero); wantsLayer = true; layer?.addSublayer(ring); layer?.addSublayer(breath)
        restTime.font = .monospacedDigitSystemFont(ofSize:17,weight:.medium); restTime.alignment = .center
        restHint.font = .systemFont(ofSize:12); restHint.textColor = .secondaryLabelColor; restHint.alignment = .center
        addSubview(restTime); addSubview(restHint); restTime.isHidden = true; restHint.isHidden = true
        restSkip.isBordered = false; restSkip.font = .systemFont(ofSize:11); restSkip.contentTintColor = .secondaryLabelColor
        restSkip.target = self; restSkip.action = #selector(skipAction); restSkip.setAccessibilityLabel("跳过休息")
        restSkip.toolTip = "跳过休息"; restSkip.isHidden = true; addSubview(restSkip)
        time.font = .monospacedDigitSystemFont(ofSize:28,weight:.medium)
        detail.font = .systemFont(ofSize:12); detail.textColor = .secondaryLabelColor
        let buttons = NSStackView(views:[pause,skip,end]); buttons.orientation = .horizontal
        stack.setViews([time,detail,buttons],in:.center); stack.orientation = .vertical; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:centerXAnchor),stack.centerYAnchor.constraint(equalTo:centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant:240),heightAnchor.constraint(greaterThanOrEqualToConstant:110)])
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
        // 休息：光环在上、时间在环中间，提示在下。
        let d: CGFloat = 64, hintH: CGFloat = 16, gap: CGFloat = 8
        let top = (bounds.height - d - gap - hintH) / 2 + hintH + gap
        let circle = CGRect(x:(bounds.width - d)/2,y:top,width:d,height:d)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        breath.bounds = CGRect(origin:.zero,size:circle.size); breath.position = CGPoint(x:circle.midX,y:circle.midY)
        breath.path = CGPath(ellipseIn:breath.bounds.insetBy(dx:1.5,dy:1.5),transform:nil)
        CATransaction.commit()
        restTime.frame = CGRect(x:circle.minX,y:circle.midY - 11,width:d,height:22)
        restHint.frame = CGRect(x:0,y:circle.minY - gap - hintH,width:bounds.width,height:hintH)
        restSkip.sizeToFit()
        restSkip.frame = CGRect(x:bounds.width - restSkip.frame.width - 10,y:bounds.height - restSkip.frame.height - 8,
                                width:restSkip.frame.width,height:restSkip.frame.height)
    }
    /// 休息时点卡片也回来（屏幕上别处的点由 FocusRestReturnMonitor 接）。
    override func mouseDown(with event: NSEvent) {
        guard resting, inputIsCurrent() else { super.mouseDown(with:event); return }
        host.handle(.dismissRestWindows)
    }
    func render(_ model:FocusTimer,at now:WS2.Instant) {
        let rest = model.phase == .rest
        if rest != resting { resting = rest; needsLayout = true }
        stack.isHidden = rest; restTime.isHidden = !rest; restHint.isHidden = !rest; restSkip.isHidden = !rest
        ring.isHidden = rest; breath.isHidden = !rest
        time.stringValue = model.phase == .idle ? "开始专注" : model.expandedText(at:now)
        detail.stringValue = "今天完成 \(model.completedToday) 个"
        restTime.stringValue = model.expandedText(at:now)
        let action = model.phase == .idle ? "开始" : model.isPaused ? "继续" : "暂停"
        configure(pause,model.phase == .idle || model.isPaused ? "play.fill" : "pause.fill",action,#selector(pauseAction))
        skip.isEnabled = model.phase != .idle; end.isEnabled = model.phase != .idle
        ring.removeAllAnimations(); breath.removeAllAnimations()
        ring.fillColor = NSColor.clear.cgColor; ring.lineWidth = 2; ring.strokeColor = NSColor.systemRed.cgColor
        breath.fillColor = NSColor.clear.cgColor; breath.lineWidth = 3; breath.strokeColor = Self.restGreen.cgColor
        let total = model.phaseDuration
        let fraction = model.phase == .idle ? 0 : Double(model.remaining(at:now))/Double(total)
        CATransaction.begin(); CATransaction.setDisableActions(true); ring.strokeEnd = min(1,max(0,fraction)); CATransaction.commit()
        if !model.isPaused,model.phase == .focus,window != nil {
            let a = CABasicAnimation(keyPath:"strokeEnd"); a.fromValue = ring.strokeEnd; a.toValue = 0
            a.duration = Double(model.remaining(at:now))/1e9
            // 倒计时进度是时间映射，保持线性；位移弹簧不套在这里。
            a.timingFunction = CAMediaTimingFunction(name: .linear)
            let r = FocusBreath.countdownFrameRate
            a.preferredFrameRateRange = CAFrameRateRange(minimum:r.minimum,maximum:r.maximum,preferred:r.preferred)
            ring.add(a,forKey:"countdown")
        }
        if FocusBreath.breathes(phase:model.phase,reduceMotion:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion),window != nil {
            let r = FocusBreath.breathFrameRate
            let range = CAFrameRateRange(minimum:r.minimum,maximum:r.maximum,preferred:r.preferred)
            // 周期 5.5 秒 = 来回各 2.75 秒。
            func make(_ key:String,_ low:Double) -> CABasicAnimation {
                let b = CABasicAnimation(keyPath:key); b.fromValue = low; b.toValue = 1
                b.duration = FocusBreath.period/2; b.autoreverses = true; b.repeatCount = .infinity
                b.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut); b.preferredFrameRateRange = range
                return b
            }
            breath.add(make("transform.scale",FocusBreath.scaleLow),forKey:"breathScale")
            breath.add(make("opacity",FocusBreath.opacityLow),forKey:"breathOpacity")
        }
        let spoken = rest ? "\(restTime.stringValue)，\(restHint.stringValue)" : "\(time.stringValue)，\(detail.stringValue)"
        setAccessibilityLabel(spoken)
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { ring.removeAllAnimations(); breath.removeAllAnimations() } }
    @objc private func pauseAction() { guard inputIsCurrent() else { return }; host.handle(host.model.phase == .idle ? .start : host.model.isPaused ? .resume : .pause) }
    @objc private func skipAction() { guard inputIsCurrent() else { return }; host.handle(.skip) }
    @objc private func endAction() { guard inputIsCurrent() else { return }; host.handle(.end) }
}
