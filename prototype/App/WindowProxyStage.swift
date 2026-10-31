// 代理先动、真窗后到：画在屏幕上的那一层（整合计划第 13–14 步）。
//
// 一块透明面板，里面三层：原处的背景（盖住还没挪走的真窗口，只在有截图时有）、目标处半透明的落点外框、
// 代理本身（有屏幕录制时是窗口截图，没有时是窗口圆角的描边）。面板不接鼠标、不抢焦点、不进窗口循环。
// 落定的弹簧按 ProxyMotion 的解析解采样成关键帧交给 Core Animation：渲染进程播放，主线程忙也不掉帧；
// 同一份解析解随时能算出此刻的位置和速度，所以中途接住、改道时位置和速度都接得上。

import Cocoa
import QuartzCore

@MainActor
final class WindowProxyStage {
    private let panel: NSPanel
    private let plate = CALayer()
    private let landing = CALayer()
    private let proxy = CALayer()
    /// 面板在屏幕上占的地方（Cocoa 坐标）：起点、终点外加余量；改道到外面时再放大。
    private var area: NSRect
    private(set) var look: ProxyLook
    private let cornerRadius: CGFloat
    /// 代理此刻的外框（AX 坐标）：静止或跟手时就是它；在飞时以 motion 为准。
    private var resting: CGRect
    private(set) var motion: ProxyMotion?
    /// 每次重新播放加一：旧动画被替换时它的完成回调不再算数。
    private var generation = 0
    var clock: () -> Double = { CACurrentMediaTime() }

    /// frame：代理一开始在哪（AX 坐标，通常就是真窗口此刻的外框）。
    init(frame: CGRect, look: ProxyLook, snapshot: CGImage?, cornerRadius: CGFloat) {
        self.look = look
        self.cornerRadius = cornerRadius
        resting = frame
        area = Self.cocoa(frame).insetBy(dx: -160, dy: -160)
        panel = NSPanel(contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        let root = NSView(frame: NSRect(origin: .zero, size: area.size))
        root.wantsLayer = true
        panel.contentView = root
        for layer in [plate, landing, proxy] {
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull(), "contents": NSNull(),
                             "borderColor": NSNull(), "backgroundColor": NSNull()]
            root.layer?.addSublayer(layer)
        }
        plate.isHidden = true
        plate.contentsGravity = .resize
        landing.cornerRadius = cornerRadius
        landing.cornerCurve = .continuous
        landing.borderWidth = 1.5
        landing.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        landing.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        landing.opacity = 0
        proxy.cornerRadius = cornerRadius
        proxy.cornerCurve = .continuous
        proxy.masksToBounds = true
        proxy.contentsGravity = .resize
        apply(look: look, snapshot: snapshot)
        place(proxy, frame)
        panel.orderFrontRegardless()
    }

    // MARK: - 长相

    /// 截图后到（后台截好）：描边换成截图。原处的背景同时铺上，真窗口看起来就是“被代理拿走了”。
    func adopt(snapshot: CGImage, background: CGImage?, over original: CGRect) {
        apply(look: .snapshot, snapshot: snapshot)
        if let background { showPlate(background, over: original) }
    }

    func showPlate(_ image: CGImage, over original: CGRect) {
        plate.contents = image
        place(plate, original)
        plate.isHidden = false
    }

    func hidePlate() { plate.isHidden = true }

    private func apply(look: ProxyLook, snapshot: CGImage?) {
        self.look = look
        switch look {
        case .snapshot:
            proxy.contents = snapshot
            proxy.borderWidth = 0
            proxy.backgroundColor = nil
        case .outline:
            proxy.contents = nil
            proxy.borderWidth = 2
            proxy.borderColor = NSColor.controlAccentColor.cgColor
            proxy.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        }
    }

    // MARK: - 跟手

    /// 代理此刻的外框（AX 坐标）。
    var presentedFrame: CGRect {
        if let motion { return motion.frame(at: clock()) }
        return resting
    }

    /// 跟手：直接放到 frame（AX 坐标），不带动画；还在飞的动画就地停下。
    func follow(_ frame: CGRect) {
        stop()
        resting = frame
        place(proxy, frame)
    }

    /// 落点外框：nil 收起。opacity 见 ProxyFollow.landingOpacity。
    func setLanding(_ frame: CGRect?, opacity: CGFloat) {
        guard let frame else { landing.opacity = 0; return }
        place(landing, frame)
        landing.opacity = Float(opacity)
    }

    // MARK: - 落定

    /// 在飞的动画停在此刻的位置，返回此刻的外框和速度（接住时用）。
    @discardableResult
    func stop() -> (frame: CGRect, velocity: ProxyVelocity) {
        let now = clock()
        let state = motion?.state(at: now) ?? (resting, .zero)
        generation += 1
        motion = nil
        proxy.removeAllAnimations()
        resting = state.frame
        place(proxy, state.frame)
        return state
    }

    /// 按 motion 播放（它的 start 应当是“现在”）；落定后回调 done。
    func play(_ motion: ProxyMotion, done: @escaping @MainActor () -> Void) {
        generation += 1
        let mine = generation
        self.motion = motion
        resting = motion.target
        ensureArea(covering: [motion.frame(at: motion.start), motion.target])
        let samples = motion.samples()
        let total = samples.times.last ?? 0
        let local = samples.frames.map { local($0) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == mine else { return }
                self.motion = nil
                done()
            }
        }
        proxy.removeAllAnimations()
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = local.map { NSValue(point: CGPoint(x: $0.midX, y: $0.midY)) }
        let bounds = CAKeyframeAnimation(keyPath: "bounds.size")
        bounds.values = local.map { NSValue(size: $0.size) }
        for animation in [position, bounds] {
            animation.keyTimes = samples.times.map { NSNumber(value: total > 0 ? $0 / total : 1) }
            animation.duration = max(total, 1.0 / 120)
            animation.calculationMode = .linear
        }
        place(proxy, motion.target)
        proxy.add(position, forKey: "proxy.position")
        proxy.add(bounds, forKey: "proxy.size")
        CATransaction.commit()
    }

    /// 减少动态效果：代理在原处淡出，目标处淡入（不平移、不缩放）。淡完回调 done。
    func dissolve(to target: CGRect, done: @escaping @MainActor () -> Void) {
        stop()
        generation += 1
        let mine = generation
        ensureArea(covering: [resting, target])
        let duration = MotionSpring.reducedNotch.response
        let leaving = CALayer()
        leaving.contents = proxy.contents
        leaving.contentsGravity = .resize
        leaving.cornerRadius = proxy.cornerRadius
        leaving.cornerCurve = .continuous
        leaving.masksToBounds = true
        leaving.borderWidth = proxy.borderWidth
        leaving.borderColor = proxy.borderColor
        leaving.backgroundColor = proxy.backgroundColor
        place(leaving, resting)
        proxy.superlayer?.insertSublayer(leaving, below: proxy)
        resting = target
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak leaving] in
            MainActor.assumeIsolated {
                leaving?.removeFromSuperlayer()
                guard let self, self.generation == mine else { return }
                done()
            }
        }
        place(proxy, target)
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = duration
        proxy.add(fadeIn, forKey: "proxy.dissolve")
        leaving.opacity = 0
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = duration
        leaving.add(fadeOut, forKey: "proxy.dissolve")
        CATransaction.commit()
    }

    /// 真窗口到位以后收场：背景马上撤（它盖着的地方真窗口已经走了），代理淡出露出底下的真窗口。
    func finish(fade: Bool = true, duration: TimeInterval = Motion.Fade.out) {
        generation += 1
        plate.isHidden = true
        landing.opacity = 0
        let panel = self.panel
        guard fade else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }

    // MARK: - 坐标

    private static func cocoa(_ ax: CGRect) -> NSRect { cocoaFrame(fromAXPosition: ax.origin, size: ax.size) }

    /// AX 外框 → 面板里的层坐标。
    private func local(_ ax: CGRect) -> CGRect {
        Self.cocoa(ax).offsetBy(dx: -area.minX, dy: -area.minY)
    }

    private func place(_ layer: CALayer, _ ax: CGRect) {
        let rect = local(ax)
        layer.bounds = CGRect(origin: .zero, size: rect.size)
        layer.position = CGPoint(x: rect.midX, y: rect.midY)
    }

    /// 改道、冲过头会走到面板外面：放大面板，层跟着换算回去（各层在屏幕上的位置不变）。
    private func ensureArea(covering frames: [CGRect]) {
        var wanted = area
        for frame in frames { wanted = wanted.union(Self.cocoa(frame).insetBy(dx: -80, dy: -80)) }
        guard wanted != area else { return }
        let dx = area.minX - wanted.minX, dy = area.minY - wanted.minY
        area = wanted
        panel.setFrame(wanted, display: false)
        panel.contentView?.frame = NSRect(origin: .zero, size: wanted.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [plate, landing, proxy] {
            layer.position = CGPoint(x: layer.position.x + dx, y: layer.position.y + dy)
        }
        CATransaction.commit()
    }
}
