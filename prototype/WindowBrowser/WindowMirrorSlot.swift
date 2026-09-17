// 置顶预览的单槽镜像所有权。
//
// 原来的 mirrorLayer 是裸单槽：菜单预览关闭时无条件 nil 会把刚挂上的
// Dock/键盘面板镜像一起摘掉。这里用 owner token 明确归属：只有当前 owner
// 的释放才真正解除；旧 owner 的迟到释放是空操作。

import AVFoundation
import CoreGraphics
import Foundation

final class WindowMirrorSlot {
    private let lock = NSLock()
    private var owner: UUID?
    private var windowID: CGWindowID?
    private var layer: AVSampleBufferDisplayLayer?

    @discardableResult
    func attach(owner newOwner: UUID, windowID newWindowID: CGWindowID,
                layer newLayer: AVSampleBufferDisplayLayer) -> Bool {
        lock.lock()
        owner = newOwner
        windowID = newWindowID
        layer = newLayer
        lock.unlock()
        return true
    }

    /// 返回被解除的窗口 ID；返回 nil 表示当前 owner 不是调用者，什么都不做。
    func release(owner releasedOwner: UUID) -> CGWindowID? {
        lock.lock()
        defer { lock.unlock() }
        guard owner == releasedOwner else { return nil }
        let released = windowID
        owner = nil
        windowID = nil
        layer = nil
        return released
    }

    /// 会话停止时强制清掉该窗口的槽位，无论 owner 是谁。
    func clear(windowID clearedWindowID: CGWindowID) {
        lock.lock()
        if windowID == clearedWindowID {
            owner = nil
            windowID = nil
            layer = nil
        }
        lock.unlock()
    }

    var currentOwner: UUID? {
        lock.lock()
        defer { lock.unlock() }
        return owner
    }

    var currentWindowID: CGWindowID? {
        lock.lock()
        defer { lock.unlock() }
        return windowID
    }
}
