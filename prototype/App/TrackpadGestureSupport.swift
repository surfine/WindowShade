// 手势的支撑件：排布撤销载荷、AX 父链/命中/坐标换算、标题栏长按菜单目标、冲突 App 缓存。

import Cocoa

/// 排布历史里每一步撤回去要用的东西。
struct ArrangementPayload {
    var element: AXUIElement?
    /// 排布：排之前；侧拉：进侧拉之前（AX 坐标）。
    var before: CGRect?
    /// 排布：排好以后（AX 坐标）；用来认出窗口被人手挪过。
    var after: CGRect?
}

func axParent(_ element: AXUIElement) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &ref) == .success,
          let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

/// 指针下的元素和它往上到窗口的（角色, 子角色）链。只读，不碰主线程上的状态，后台线程上也能问。
func axElementChain(at point: CGPoint) -> (AXUIElement, [GestureOwnership.Element])? {
    var hitRef: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x),
                                           Float(point.y), &hitRef) == .success,
          let hit = hitRef else { return nil }
    var chain: [GestureOwnership.Element] = []
    var node: AXUIElement? = hit
    for _ in 0..<12 {
        guard let current = node else { break }
        let role = axRole(current) ?? ""
        if role == (kAXWindowRole as String) { break }
        chain.append((role, axSubrole(current)))
        node = axParent(current)
    }
    return (hit, chain)
}

func axPoint(fromCocoa point: NSPoint) -> CGPoint {
    CGPoint(x: point.x, y: coordinateBaselineY() - point.y)
}

@MainActor
final class TitlebarHoldMenuTarget: NSObject {
    private let callback: (GestureAction) -> Void
    init(_ callback: @escaping (GestureAction) -> Void) { self.callback = callback }
    @objc func activateAction(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let action = GestureAction(rawValue: raw) else { return }
        callback(action)
    }
}

/// `conflictingApp()` 的结果缓存：App 启动 / 退出时置脏，最多 30 秒重算一次兜底。
/// 任意线程都会来问（主线程、手势队列），状态只在锁里读写。
final class ConflictingAppCache: @unchecked Sendable {
    static let shared = ConflictingAppCache()
    private let lock = NSLock()
    private var cached: NSRunningApplication?
    private var computedAt: CFAbsoluteTime = 0
    private var dirty = true
    private static let maxAge: CFTimeInterval = 30

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.markDirty() }
        }
    }

    private func markDirty() {
        lock.lock(); dirty = true; lock.unlock()
    }

    func value(_ compute: () -> NSRunningApplication?) -> NSRunningApplication? {
        lock.lock()
        if !dirty, CFAbsoluteTimeGetCurrent() - computedAt < Self.maxAge, cached?.isTerminated != true {
            defer { lock.unlock() }
            return cached
        }
        // 先清脏再算：算的途中又有 App 启动 / 退出，会重新置脏，下一次照样重算，不会被这次覆盖掉。
        dirty = false
        lock.unlock()
        let result = compute()
        lock.lock()
        cached = result
        computedAt = CFAbsoluteTimeGetCurrent()
        lock.unlock()
        return result
    }
}
