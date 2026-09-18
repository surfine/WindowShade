// Dock 面板与键盘面板共用的 AppKit 容器。
//
// 显示模式决定键盘语义：
// - dock：nonactivating、不抢 key window、不把其他应用输入焦点转走；
// - keyboard：用户明确打开，可以成为 key window 并编辑搜索框。
// 不能把 canBecomeKey 永久设为 false，也不能在每次悬停时 makeKeyAndOrderFront。
//
// 键盘面板的有限激活重试携带打开请求代数：用户切到其他应用后不再抢回焦点。

import Cocoa

final class WindowBrowserPanel: NSPanel {
    let mode: WindowBrowserPanelMode
    let browserContentView: WindowBrowserContentView
    var onCancel: (() -> Void)?
    var onBecomeKeyStateChanged: ((Bool) -> Void)?

    /// 打开请求代数：每次打开/关闭都递增，过期的延迟激活重试直接失效。
    private var presentationGeneration: UInt64 = 0
    private var animationParams = WindowBrowserLayoutParams.standard

    init(mode: WindowBrowserPanelMode, frame: NSRect,
         params: WindowBrowserLayoutParams = .standard) {
        self.mode = mode
        self.animationParams = params
        self.browserContentView = WindowBrowserContentView(
            frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        browserContentView.params = params
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        // 键盘面板是用户明确打开的浮动面板：像系统面板一样可以拖背景移动。
        // Dock 面板锚定在图标下方，保持不可拖动，避免与锚点/过渡区域打架。
        isMovableByWindowBackground = mode == .keyboard
        // 无边框窗口默认没有标题，VoiceOver 会读成无名窗口；这里给两种用途明确名称。
        title = mode == .dock ? "窗口浏览" : "窗口选择"
        isExcludedFromWindowsMenu = true
        // 无边框浮层不应参与系统标签页合并（防御性设置，正常情况下也不会被合并）。
        tabbingMode = .disallowed
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .moveToActiveSpace]
        contentView = browserContentView
        // 与置顶预览面板同一套纸面阴影。曾怀疑它会激活 app，但面板探针的对照实验
        // （不显示窗口 / 同进程第二次显示）证明激活来自“新进程首次出窗”，阴影不是
        // 原因；阴影子窗口还额外改成不可成为 key/main，不会再抢键盘焦点。
        PaperSurfaceStyle.installShadow(on: self)
    }

    override var canBecomeKey: Bool { mode == .keyboard }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        if mode == .keyboard {
            onCancel?()
        } else {
            super.cancelOperation(sender)
        }
    }

    /// ⌘W 等系统关闭路径也必须回到控制器，避免面板已关闭但控制器仍以为可见。
    override func performClose(_ sender: Any?) {
        onCancel?()
    }

    override func becomeKey() {
        super.becomeKey()
        onBecomeKeyStateChanged?(true)
    }

    override func resignKey() {
        super.resignKey()
        onBecomeKeyStateChanged?(false)
    }

    func presentKeyboardPanel() {
        // 用户明确打开（菜单/快捷键）时面板应当获得键盘焦点；菜单栏状态项点击有时
        // 不构成 app 激活，因此这里显式激活一次，并在激活完成晚于 makeKey 时补一次。
        presentationGeneration &+= 1
        let token = presentationGeneration
        // macOS 14 起的协作式激活：不再强制抢占前台（实测在最少用户手势的场景下
        // 同样能让面板成为 key window，见 scripts/check-standard-menu.sh）。
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        browserContentView.focusSearch()
        // app 激活是异步的：激活完成可能晚于 makeKeyAndOrderFront，这里有限重试
        // 直到面板成为 key window，避免搜索框拿不到输入。重试携带本次打开代数，
        // 并且只在 app 仍然是前台时执行：用户主动切走以后不再把焦点抢回来。
        for delay in [0.12, 0.3, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.presentationGeneration == token,
                      self.isVisible,
                      !self.isKeyWindow,
                      NSApp.isActive else { return }
                NSApp.activate()
                self.makeKeyAndOrderFront(nil)
                self.browserContentView.focusSearch()
            }
        }
    }

    func presentDockPanel() {
        orderFrontRegardless()
        animateAppearanceIfAllowed()
    }

    /// 消失约 100–120 ms；减少动态效果时立即关闭，不留下延迟的残留窗口。
    /// completion 在窗口真正移出屏幕后调用一次（调用方负责关闭与释放）。
    func dismiss(animated: Bool = true, completion: @escaping () -> Void) {
        cancelPendingPresentation()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = WindowBrowserAnimationPolicy.duration(animationParams.disappearDuration,
                                                             reduceMotion: reduceMotion)
        guard animated, duration > 0, isVisible else {
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: completion)
    }

    /// 面板出现约 140–180 ms；减少动态效果时直接显示，不做位移或缩放。
    private func animateAppearanceIfAllowed() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard WindowBrowserAnimationPolicy.shouldAnimate(reduceMotion: reduceMotion) else {
            alphaValue = 1
            return
        }
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = WindowBrowserAnimationPolicy.duration(
                animationParams.appearDuration, reduceMotion: reduceMotion)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func setPanelFrame(_ frame: NSRect, animated: Bool = false) {
        guard animated,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setFrame(frame, display: true)
            browserContentView.frame = NSRect(origin: .zero, size: frame.size)
            browserContentView.needsLayout = true
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationParams.selectionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(frame, display: true)
        }
        browserContentView.frame = NSRect(origin: .zero, size: frame.size)
        browserContentView.needsLayout = true
    }

    /// 关闭或切换会话时调用：过期的延迟激活重试立即失效。
    func cancelPendingPresentation() {
        presentationGeneration &+= 1
    }
}
