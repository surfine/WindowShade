// 简单卷帘条窗口池：截图条 / 经典条（OverlayWindow）复用，避免频繁创建 NSWindow。
// 代理标题栏（NativeProxyOverlayWindow）带大量每窗口状态（交通灯配置、delegate、
// 窗口管理能力），不复用。
//
// 池内窗口 isReleasedWhenClosed = false（makeBaseOverlay 设置）；内容视图在
// 回收与取出时清空，避免闭包（unshade 等）滞留形成引用环。

import Cocoa

final class ShadeStripPool {
    static let shared = ShadeStripPool()

    private var available: [OverlayWindow] = []
    private let maxPooled = 4

    func take() -> OverlayWindow? {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !available.isEmpty else { return nil }
        let window = available.removeLast()
        window.contentView = nil
        return window
    }

    func recycle(_ window: OverlayWindow) {
        dispatchPrecondition(condition: .onQueue(.main))
        window.contentView = nil
        if available.count < maxPooled {
            available.append(window)
        } else {
            window.close()
        }
    }
}
