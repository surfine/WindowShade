// 读屏幕真实形状要用的系统数据（设计系统 §3.4），交给 Core/DisplayShape.swift 校验、换算。
//
// - 私有的 -[NSScreen bezelPath]：只在 macOS 27 上验证过（Aaron 2026-09-29 定：读，带守卫和校验，失败退回机型表）。
//   先 responds(to:)，再看它的返回类型是不是对象，拿到后确认是 NSBezierPath，拆成纯数据；
//   外框、刘海、曲线的校验全在 DisplayShape 里做，不过就退到机型表，机型表也没有就是现版本的几何。
// - 原生面板像素：带 native 标志（kDisplayModeNativeFlag = 0x02000000）的显示模式的像素宽高。
//   当前模式的 pixelWidth 是帧缓冲宽（1710 模式下 3420），不是面板宽（2880），不能拿来换算。
// - 只在启动和屏幕参数变化时算（NotchController.install 在这两个时刻调用），按显示器 + 显示模式 + frame 大小缓存；
//   不轮询、不截图、不加定时器。每真算一次在日志里记一行：用了哪个来源、为什么。
// - 自动只算有真刘海的屏（公开接口报了刘海的那块）：只有它的曲线有人用。没有刘海的 Mac、外接屏、“避开刘海”模式
//   一次也不读 bezelPath。探针用 shape(for:) 可以看任何一块屏。
// - 进程里第一次读 bezelPath 要几十到几百毫秒（命令行实测 50–800，之后 0.2 毫秒），量曲线还要二十几毫秒：
//   都在主线程上做（私有接口不挪到后台）。第一次挪到启动 2 秒之后，而且等人停手 1.5 秒再读：卡住主线程时正好双击标题栏，
//   EventTapCallback 等 0.5 秒没人接手就放行，这次收起就漏了。按着鼠标、手势没结束时也不读（等多久都一样）。
//   算好之前岛照现版本画。

import Cocoa
import ObjectiveC

enum ScreenBezel {
    /// 私有的 bezelPath（全局坐标）。没有这个方法、返回的不是对象或不是 NSBezierPath 时是 nil。
    @MainActor
    static func outline(of screen: NSScreen) -> [OutlineStep]? {
        let selector = NSSelectorFromString("bezelPath")
        guard screen.responds(to: selector), let method = class_getInstanceMethod(type(of: screen), selector) else { return nil }
        // 守卫 1：返回类型必须是对象（"@"），不然 perform 会把别的东西当成对象用。
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        guard String(cString: returnType) == "@",
              let value = screen.perform(selector)?.takeUnretainedValue(), let path = value as? NSBezierPath
        else { return nil }
        var steps: [OutlineStep] = []
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<path.elementCount {
            switch path.element(at: index, associatedPoints: &points) {
            case .moveTo: steps.append(.move(points[0]))
            case .lineTo: steps.append(.line(points[0]))
            case .cubicCurveTo: steps.append(.curve(points[2], control1: points[0], control2: points[1]))
            case .quadraticCurveTo: steps.append(.quad(points[1], control: points[0]))
            case .closePath: steps.append(.close)
            @unknown default: return nil
            }
        }
        return steps
    }

    /// 原生面板的像素宽高：所有显示模式（含重复的低分辨率模式）里带 native 标志的那个。拿不到是 nil。
    static func nativePixels(_ display: CGDirectDisplayID) -> CGSize? {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] else { return nil }
        // 同一块面板常有两个带 native 标志的模式（2× 的 1440×932 和 1× 的 2880×1864），像素一样；取像素最多的。
        guard let native = modes.filter({ $0.ioFlags & 0x0200_0000 != 0 }).max(by: { $0.pixelWidth < $1.pixelWidth }) else {
            return nil
        }
        return CGSize(width: native.pixelWidth, height: native.pixelHeight)
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// 每块屏的形状，按显示器 + 显示模式 + frame 大小（以及旋转、镜像）缓存：只在这些变了以后才重新算。
@MainActor
final class DisplayShapes {
    static let shared = DisplayShapes()

    private struct Key: Hashable {
        var display: CGDirectDisplayID
        var mode: Int32
        var width: CGFloat
        var height: CGFloat
        var rotation: Double
        var mirrored: Bool
    }

    private var cache: [Key: DisplayShape] = [:]
    /// 真算了几次（诊断用：只该在启动和换屏、换显示模式时加一；没有刘海的 Mac 上一直是 0）。
    private(set) var computed = 0
    /// 读过一次 bezelPath 了：之后再读很快，不用再往后挪、也不用等人停手。
    private var warmedUp = false
    /// 已经排上、还没算的那一次：算完挨个回调。
    private var waiting: [() -> Void]?

    /// 第一次读等人停手：键盘、指针、触控板这么久没动过才读。
    private static let idleBeforeFirstRead: CFTimeInterval = 1.5
    /// 人一直没停手就过一会儿再看；最多看这么多次（约一分钟），之后照读，免得一直排着。
    private static let idleRetry: TimeInterval = 3
    private static let idleTries = 20

    private func key(for screen: NSScreen) -> Key? {
        guard let id = ScreenBezel.displayID(screen) else { return nil }
        return Key(display: id, mode: CGDisplayCopyDisplayMode(id)?.ioDisplayModeID ?? -1,
                   width: screen.frame.width, height: screen.frame.height,
                   rotation: CGDisplayRotation(id), mirrored: CGDisplayIsInMirrorSet(id) != 0)
    }

    /// 已经算好的形状；还没算过是 nil（这时照现版本画，并用 prepare 排上）。
    func known(for screen: NSScreen) -> DisplayShape? {
        key(for: screen).flatMap { cache[$0] }
    }

    /// 要自动算的屏：只有公开接口报了刘海的（真刘海面板所在的那块）。隐形刘海不画曲线，算了也没人用。
    private static var notched: [NSScreen] {
        NSScreen.screens.filter { NotchController.notchRect(on: $0) != nil }
    }

    /// 键盘、指针、触控板有一阵没动过了：这时卡一下主线程，不会压住正在做的双击、拖动。
    private static var userIsIdle: Bool {
        guard let any = CGEventType(rawValue: ~0) else { return true }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any) >= idleBeforeFirstRead
    }

    /// 正按着鼠标（拖动里停住不动也算）、手势还没结束、甩出去的窗口还在滑：第一次读绝不挑这时候，
    /// 等了一分钟也一样（停手不动时“没动过”也会成立，所以要单独看）。
    private static var inputInProgress: Bool {
        NSEvent.pressedMouseButtons != 0 || appDelegate?.gestures.isTracking == true
    }

    /// 有刘海的屏里还有没算过的：稍后在主线程上算好，算完回调一次（进程里第一次挪到 2 秒后、等人停手，之后下一轮就算）。
    /// 都算过了、或者没有刘海，什么也不做。
    func prepare(then done: @escaping () -> Void) {
        guard Self.notched.contains(where: { known(for: $0) == nil }) else { return }
        if waiting != nil {
            waiting?.append(done)
            return
        }
        waiting = [done]
        run(after: warmedUp ? 0 : 2, tries: 0)
    }

    private func run(after delay: TimeInterval, tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.warmedUp, Self.inputInProgress || (tries < Self.idleTries && !Self.userIsIdle) {
                    self.run(after: Self.idleRetry, tries: tries + 1)
                    return
                }
                // 到这时再看一遍有哪些屏（这几秒里可能换过屏）。
                for screen in Self.notched { _ = self.shape(for: screen) }
                let callbacks = self.waiting ?? []
                self.waiting = nil
                callbacks.forEach { $0() }
            }
        }
    }

    /// 这块屏的形状：算过就用缓存，没算过就当场算（探针和 prepare 用；平时走 known + prepare）。
    func shape(for screen: NSScreen) -> DisplayShape {
        guard let id = ScreenBezel.displayID(screen), let key = key(for: screen) else {
            return DisplayShape.resolve(DisplayShapeInput(frame: screen.frame, notch: NotchController.notchRect(on: screen), isBuiltIn: false))
        }
        if let known = cache[key] { return known }
        warmedUp = true
        let started = CACurrentMediaTime()
        let bezel = ScreenBezel.outline(of: screen)
        let read = CACurrentMediaTime()
        let input = DisplayShapeInput(frame: screen.frame, notch: NotchController.notchRect(on: screen),
                                      isBuiltIn: CGDisplayIsBuiltin(id) != 0, rotation: key.rotation, mirrored: key.mirrored,
                                      nativePixels: ScreenBezel.nativePixels(id), bezel: bezel)
        let shape = DisplayShape.resolve(input)
        cache[key] = shape
        computed += 1
        let curves = shape.notchCurves.map { String(format: "notch bottom %.2f shoulder %.2f", $0.bottomRadius, $0.shoulderRadius) } ?? "no notch curves"
        // 记下花了多久：第一次读 bezelPath 最慢，这一行能看出它在 App 里实际卡了主线程多久。
        wlog("display shape: display=\(id) \(screen.localizedName) \(Int(screen.frame.width))x\(Int(screen.frame.height)) "
            + "source=\(shape.source.rawValue) pxPerPt=\(shape.pxPerPt.map { String(format: "%.3f", $0) } ?? "-") \(curves) "
            + String(format: "top %.2f bottom %.2f", shape.topCorner, shape.bottomCorner) + " — \(shape.note) "
            + String(format: "(computed %d; bezelPath %.0f ms, the rest %.0f ms)", computed,
                     (read - started) * 1000, (CACurrentMediaTime() - read) * 1000))
        return shape
    }

    /// 探针用：只按机型表算（不读 bezelPath），和实际用的对照。
    func tableOnly(for screen: NSScreen) -> DisplayShape? {
        guard let id = ScreenBezel.displayID(screen) else { return nil }
        return DisplayShape.resolve(DisplayShapeInput(frame: screen.frame, notch: NotchController.notchRect(on: screen),
                                                      isBuiltIn: CGDisplayIsBuiltin(id) != 0, rotation: CGDisplayRotation(id),
                                                      mirrored: CGDisplayIsInMirrorSet(id) != 0,
                                                      nativePixels: ScreenBezel.nativePixels(id), bezel: nil))
    }
}
