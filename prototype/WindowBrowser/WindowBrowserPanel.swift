// Dock 面板与键盘面板共用的 AppKit 容器。
//
// 显示模式决定键盘语义：
// - dock：nonactivating、不抢 key window、不把其他应用输入焦点转走；
// - keyboard：用户明确打开，可以成为 key window 并编辑搜索框。
// 不能把 canBecomeKey 永久设为 false，也不能在每次悬停时 makeKeyAndOrderFront。

import Cocoa

final class WindowBrowserPanel: NSPanel {
    let mode: WindowBrowserPanelMode
    let browserContentView: WindowBrowserContentView
    var onCancel: (() -> Void)?
    var onBecomeKeyStateChanged: ((Bool) -> Void)?

    init(mode: WindowBrowserPanelMode, frame: NSRect,
         params: WindowBrowserLayoutParams = .standard) {
        self.mode = mode
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
        // 无边框窗口默认没有标题，VoiceOver 会读成无名窗口；这里给两种用途明确名称。
        title = mode == .dock ? "窗口浏览" : "窗口选择"
        isExcludedFromWindowsMenu = true
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
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        browserContentView.focusSearch()
        // app 激活是异步的：激活完成可能晚于 makeKeyAndOrderFront，这里有限重试
        // 直到面板成为 key window，避免搜索框拿不到输入。
        for delay in [0.12, 0.3, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isVisible, !self.isKeyWindow else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.makeKeyAndOrderFront(nil)
                self.browserContentView.focusSearch()
            }
        }
    }

    func presentDockPanel() {
        orderFrontRegardless()
    }

    func setPanelFrame(_ frame: NSRect) {
        setFrame(frame, display: true)
        browserContentView.frame = NSRect(origin: .zero, size: frame.size)
        browserContentView.needsLayout = true
    }
}
