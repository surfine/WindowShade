// 替身滑行：真窗口一时动不了的时候，先让它的替身滑。
//
// 实测（2026-09-26 日志）：三指拖移刚抬手、系统还没发“松开”时，那个 App 还在拖动里，不理移动请求——
// 第一次移动要等 0.4–1 秒才生效，窗口先僵住再一跳。有的 App 平时移动一次也要几十毫秒。
// 这时照 iPadOS 的手感：抬手那一刻，窗口截图就带着甩出去的速度弹到目标，原处先盖一张窗口后面的背景
// （拖动时在后台截好），真窗口能动了一次挪过去，再撤掉替身和背景。替身和背景都是我们自己的窗口，
// 弹簧由系统的渲染进程播（Core Animation），主线程再忙也不掉帧。

import Cocoa
import QuartzCore

/// 拖着标题栏时在后台截好的两张图：窗口本身、它所在那块屏去掉它之后的样子。
struct DragPictures {
    var window: CGImage?
    /// 整块屏（AX 坐标）去掉这扇窗之后的样子。
    var background: (image: CGImage, rect: CGRect)?

    /// 截给拖动用：窗口本身 + 它所在那块屏的背景。大屏上两张加起来几十毫秒，只在后台做。
    static func capture(id: CGWindowID, screenAX: CGRect) -> DragPictures {
        DragPictures(window: FastCapture.window(id),
                     background: FastCapture.composite(excluding: [id], rect: screenAX).map { ($0, screenAX) })
    }

    /// 背景里 rect（AX 坐标）那一块。
    func background(covering rect: CGRect) -> CGImage? {
        guard let background else { return nil }
        let area = rect.intersection(background.rect)
        guard !area.isNull, area.width >= 1, area.height >= 1 else { return nil }
        let scale = CGFloat(background.image.width) / background.rect.width
        let pixels = CGRect(x: (area.minX - background.rect.minX) * scale, y: (area.minY - background.rect.minY) * scale,
                            width: area.width * scale, height: area.height * scale).integral
        return background.image.cropping(to: pixels)
    }
}

/// 盖在窗口原处的一张背景：真窗口还没挪走（或还没藏好）之前，别让它露出来。
@MainActor
final class BackgroundPlate {
    private let panel: NSPanel

    /// rect：AX 坐标。
    init(image: CGImage, rect: CGRect) {
        let frame = cocoaFrame(fromAXPosition: rect.origin, size: rect.size)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = true
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .transient]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resize
        panel.contentView = view
        panel.orderFrontRegardless()
    }

    func remove() {
        panel.orderOut(nil)
    }
}

/// 窗口截图从一个外框弹到另一个外框（Core Animation 的弹簧，参数和真窗口滑行同一套）。
/// 面板一次开够整条路径（含冲过头的余量），之后只动里面那一层：窗口本身一帧都不挪。
@MainActor
final class SnapshotFlight {
    private let panel: NSPanel
    private let picture = CALayer()
    private let area: NSRect

    /// from、to：Cocoa 坐标。joinsAllSpaces = false：只留在现在这张桌面上（先盖在原处、过一会儿才飞的那种，
    /// 中途切了桌面不能跟过去）。
    init(image: CGImage, from: NSRect, to: NSRect, level: NSWindow.Level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1),
         joinsAllSpaces: Bool = true) {
        area = from.union(to).insetBy(dx: -80, dy: -80)
        panel = NSPanel(contentRect: area, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = level
        panel.collectionBehavior = joinsAllSpaces
            ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
            : [.fullScreenAuxiliary, .ignoresCycle, .transient]
        let root = NSView(frame: NSRect(origin: .zero, size: area.size))
        root.wantsLayer = true
        picture.contents = image
        picture.contentsGravity = .resize
        picture.cornerRadius = 10
        picture.masksToBounds = true
        picture.frame = from.offsetBy(dx: -area.minX, dy: -area.minY)
        root.layer?.addSublayer(picture)
        panel.contentView = root
        panel.orderFrontRegardless()
    }

    /// 面板开出的那块地方够不够飞到 target（Cocoa 坐标）：够不着的部分会被面板边裁掉。
    func canReach(_ target: NSRect) -> Bool {
        area.contains(target)
    }

    /// velocity：点/秒，Cocoa 坐标（y 向上）。fadeOut：一路缩小时最后一段淡掉（飞进刘海）。
    func fly(to target: NSRect, velocity: CGVector, response: Double = 0.42, bounce: CGFloat = 0.12,
             cornerRadius: CGFloat? = nil, fadeOut: Bool = false, done: @escaping () -> Void) {
        let end = target.offsetBy(dx: -area.minX, dy: -area.minY)
        if Motion.reduced {
            dissolve(to: end, cornerRadius: cornerRadius, fadeOut: fadeOut, done: done)
            return
        }
        let start = picture.frame

        CATransaction.begin()
        CATransaction.setCompletionBlock { done() }
        // 横竖各一条弹簧（WWDC18：二维运动拆成独立的轴），各自接上甩出去的那一分量的速度——
        // 只把速度投到连线上会丢掉横着的那一分量，斜着甩时起步会拐一下。
        // CASpringAnimation 的初速度按“这条轴剩下的路程每秒走几倍”算。
        func axis(_ keyPath: String, from: CGFloat, to: CGFloat, speed: CGFloat) -> CASpringAnimation {
            let spring = CASpringAnimation(perceptualDuration: response, bounce: bounce)
            spring.keyPath = keyPath
            spring.fromValue = from
            spring.toValue = to
            let distance = to - from
            spring.initialVelocity = abs(distance) > 1 ? max(-40, min(40, speed / distance)) : 0
            spring.duration = spring.settlingDuration
            return spring
        }
        let positionX = axis("position.x", from: start.midX, to: end.midX, speed: velocity.dx)
        let positionY = axis("position.y", from: start.midY, to: end.midY, speed: velocity.dy)
        let position = positionX.duration >= positionY.duration ? positionX : positionY
        let size = CASpringAnimation(perceptualDuration: response * 0.9, bounce: 0)
        size.keyPath = "bounds.size"
        size.fromValue = NSValue(size: start.size)
        size.toValue = NSValue(size: end.size)
        size.duration = size.settlingDuration
        var animations: [CAAnimation] = [positionX, positionY, size]
        if let cornerRadius {
            let corner = CABasicAnimation(keyPath: "cornerRadius")
            corner.fromValue = picture.cornerRadius
            corner.toValue = cornerRadius
            corner.duration = size.duration
            corner.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            animations.append(corner)
        }
        if fadeOut {
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.6, 1]
            fade.duration = min(position.duration, 0.55)
            animations.append(fade)
        }
        CATransaction.setDisableActions(true)
        picture.position = CGPoint(x: end.midX, y: end.midY)
        picture.bounds = CGRect(origin: .zero, size: end.size)
        if let cornerRadius { picture.cornerRadius = cornerRadius }
        if fadeOut { picture.opacity = 0 }
        for animation in animations { picture.add(animation, forKey: (animation as? CAPropertyAnimation)?.keyPath) }
        CATransaction.commit()
    }

    /// 减少动态效果时不飞：原处淡出，目标处淡入（飞进刘海时只淡出）。
    private func dissolve(to end: CGRect, cornerRadius: CGFloat?, fadeOut: Bool, done: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { done() }
        let out = CABasicAnimation(keyPath: "opacity")
        out.fromValue = 1
        out.toValue = 0
        out.duration = 0.2
        picture.opacity = 0
        picture.add(out, forKey: "dissolve")
        if !fadeOut {
            let arrival = CALayer()
            arrival.contents = picture.contents
            arrival.contentsGravity = .resize
            arrival.cornerRadius = cornerRadius ?? picture.cornerRadius
            arrival.masksToBounds = true
            arrival.frame = end
            picture.superlayer?.addSublayer(arrival)
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.toValue = 1
            fadeIn.duration = 0.2
            arrival.add(fadeIn, forKey: "dissolve")
        }
        CATransaction.commit()
    }

    func remove(fade: Bool = true) {
        let panel = self.panel
        guard fade else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }
}

/// 替身滑行本身：盖背景、放替身、真窗口在后台一次挪到目标；两边都完了再撤。
@MainActor
final class WindowProxyGlide {
    let id: CGWindowID
    private let element: AXUIElement
    private let target: CGRect
    private let flight: SnapshotFlight
    private let plate: BackgroundPlate?
    private var flown = false
    private var moved: CGRect?
    private var finished = false
    private var completion: ((CGRect) -> Void)?
    private let began = CACurrentMediaTime()

    /// from、to：AX 坐标；velocity：点/秒，AX 坐标（y 向下）。
    init(id: CGWindowID, element: AXUIElement, from: CGRect, to: CGRect, velocity: CGVector,
         snapshot: CGImage, background: CGImage?) {
        self.id = id
        self.element = element
        self.target = to
        plate = background.map { BackgroundPlate(image: $0, rect: from) }
        let fromCocoa = cocoaFrame(fromAXPosition: from.origin, size: from.size)
        let toCocoa = cocoaFrame(fromAXPosition: to.origin, size: to.size)
        flight = SnapshotFlight(image: snapshot, from: fromCocoa, to: toCocoa)
        flight.fly(to: toCocoa, velocity: CGVector(dx: velocity.dx, dy: -velocity.dy)) { [weak self] in
            self?.flown = true
            self?.finishIfReady()
        }
    }

    /// completion：真窗口最后的外框（AX 坐标）。
    func start(completion: @escaping (CGRect) -> Void) {
        self.completion = completion
        let element = self.element, target = self.target, id = self.id
        DispatchQueue.global(qos: .userInteractive).async {
            // App 还在拖动里时这几下会排队，等它能动了一起生效。
            setAXSize(element, target.size)
            setAXPosition(element, target.origin)
            setAXSize(element, target.size)
            setAXPosition(element, target.origin)
            // 等 WindowServer 里真的到位（最多 2.5 秒）。
            let deadline = CACurrentMediaTime() + 2.5
            var observed = target
            while CACurrentMediaTime() < deadline {
                if let info = cgWindowInfo(id), let bounds = cgWindowBounds(info) {
                    observed = bounds
                    if abs(bounds.minX - target.minX) <= 4, abs(bounds.minY - target.minY) <= 4 { break }
                }
                usleep(16_000)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { [weak self] in
                    self?.moved = observed
                    self?.finishIfReady()
                }
            }
        }
    }

    /// 被再次按住：马上撤掉替身和背景。
    func cancel() {
        guard !finished else { return }
        finished = true
        flight.remove(fade: false)
        plate?.remove()
    }

    private func finishIfReady() {
        guard !finished, flown, let moved else { return }
        finished = true
        plate?.remove()
        flight.remove()
        wlog(String(format: "gesture: proxy glide id=%d took=%.0fms landed=(%.0f,%.0f %.0fx%.0f)", id,
                    (CACurrentMediaTime() - began) * 1000, moved.minX, moved.minY, moved.width, moved.height))
        completion?(moved)
    }
}
