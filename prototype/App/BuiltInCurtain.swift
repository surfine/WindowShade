// 指针离开内屏就遮住（吸收 cursor-curtain 的内屏遮罩，MIT；照思路自写，没有拷代码）。
// 接着外接屏时，指针移到别的屏，MacBook 内建屏盖上不透明黑色；指针回来就揭开。
// - 只在指针移动和屏幕配置变化时判断，不轮询（cursor-curtain 是 0.1 秒一次的计时器）；不需要任何权限。
// - 只有一块屏、内屏在镜像、内屏不在（合盖）时不遮。
// - 层级在菜单栏之上、刘海面板之下（刘海 = mainMenu + 3）：内屏的菜单栏一起盖住，刘海的岛照常看得见。
// - 纯黑一种：挡得最彻底、不耗渲染；内容层不加材质（设计系统 P5）。
// - 淡入 0.18 / 淡出 0.10（设计系统 fade-in / fade-out）；减少动态效果时直接出现、消失。
// 这是方便遮挡，不是锁屏：退出、崩溃或系统界面都可能露出内屏。离开电脑用系统锁屏（离开就锁）。
import Cocoa

@MainActor
final class BuiltInCurtain {
    static let enabledKey = "Privacy.builtInCurtain.enabled"
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private var panel: NSPanel?
    private var builtInID: CGDirectDisplayID?
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var covered = false

    /// 按设置开或关；设置变化时再调一次。
    func apply() {
        if Self.isEnabled { start() } else { stop() }
    }

    private func start() {
        guard monitors.isEmpty else { refresh(); return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.refresh() }
            return event
        }) { monitors.append(local) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        rebuild()
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel?.orderOut(nil)
        panel = nil
        builtInID = nil
        covered = false
    }

    /// 屏幕变了：重新找内屏、按它的大小重建遮罩窗口。
    private func rebuild() {
        let builtIn = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
        }
        builtInID = builtIn.flatMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
        panel?.orderOut(nil)
        panel = nil
        covered = false
        if let builtIn {
            let p = NSPanel(contentRect: builtIn.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.backgroundColor = .black
            p.isOpaque = true
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.alphaValue = 0
            p.setFrame(builtIn.frame, display: false)
            panel = p
        }
        refresh()
    }

    private func refresh() {
        guard let panel else { return }
        let mirrored = builtInID.map { CGDisplayIsInMirrorSet($0) != 0 } ?? false
        let cover = BuiltInCurtainPolicy.shouldCover(enabled: Self.isEnabled, builtIn: panel.frame,
                                                     screenCount: NSScreen.screens.count, mirrored: mirrored,
                                                     pointer: NSEvent.mouseLocation)
        guard cover != covered else { return }
        covered = cover
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if cover { panel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduce ? 0 : (cover ? 0.18 : 0.10)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = cover ? 1 : 0
        }, completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                // 动画中途又改了主意（快速来回）就别把它收掉。
                guard let self, let panel, !self.covered else { return }
                panel.orderOut(nil)
            }
        })
    }
}
