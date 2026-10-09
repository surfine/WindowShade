// 原生全屏桌面、调度中心开着的时候，刘海让开：不画，也不刷新。
// 判断只看“指针（或面板）所在那块屏当前这张桌面是不是全屏桌面”，不看窗口尺寸：
// 优先读该屏当前桌面的类型（SkyLight 的桌面列表，type == 4 是全屏桌面），
// 读不到时退回前台焦点窗口的 AXFullScreen。两条都读不到就是“未知”，未知时不让开（照旧画）。
// 只在换桌面、前台 App 变化、调度中心开合的通知到来时重算，不轮询；每次通知后只多补一次延后的复核（一次性，不循环）。
// 读取点：私有的桌面列表（SLS 前缀的符号，经 dlsym，读不到静默）和一条 AX 布尔属性，都已登记在 tools/privacy/registry.json。

import Cocoa
import Darwin

/// 三态：读到了是、读到了不是、读不到。
enum NotchSpaceFact: Equatable, Sendable {
    case yes, no, unknown
}

@MainActor
final class NotchSpaceGate {
    // MARK: 纯规则（不碰系统，测试直接用）

    /// SkyLight 里全屏桌面的类型值。
    nonisolated static let fullScreenSpaceType = 4

    /// 让不让开。第 1 层（授权放行、离开就锁倒数）永远不让开；未知不让开。
    nonisolated static func yields(fullScreen: NotchSpaceFact, missionControl: NotchSpaceFact,
                                   authorizationLayer: Bool) -> Bool {
        if authorizationLayer { return false }
        return fullScreen == .yes || missionControl == .yes
    }

    /// 从桌面列表里找出某块屏当前桌面的类型。`displayUUID` 对不上时，列表里只有一块屏（或标识是 "Main"）就取它。
    nonisolated static func currentSpaceType(in displays: [[String: Any]], displayUUID: String?) -> Int? {
        func current(_ entry: [String: Any]) -> Int? {
            ((entry["Current Space"] as? [String: Any])?["type"] as? NSNumber)?.intValue
        }
        if let uuid = displayUUID?.lowercased(),
           let hit = displays.first(where: { (($0["Display Identifier"] as? String)?.lowercased()) == uuid }) {
            return current(hit)
        }
        if displays.count == 1 { return displays.first.flatMap(current) }
        if let main = displays.first(where: { ($0["Display Identifier"] as? String) == "Main" }) { return current(main) }
        return nil
    }

    nonisolated static func fact(forSpaceType type: Int?) -> NotchSpaceFact {
        guard let type else { return .unknown }
        return type == fullScreenSpaceType ? .yes : .no
    }

    /// 岛如果碰到了屏幕边或角（自动隐藏菜单栏、全屏 App 里常见）：只整体平移回屏内，宽高不变，圆角半径不由它改。
    nonisolated static func translatedInside(_ island: CGRect, screen: CGRect) -> CGRect {
        guard island.width <= screen.width, island.height <= screen.height else { return island }
        var moved = island
        if moved.minX < screen.minX { moved.origin.x = screen.minX }
        if moved.maxX > screen.maxX { moved.origin.x = screen.maxX - moved.width }
        if moved.minY < screen.minY { moved.origin.y = screen.minY }
        if moved.maxY > screen.maxY { moved.origin.y = screen.maxY - moved.height }
        return moved
    }

    // MARK: 读系统

    struct Sources {
        /// 某块屏当前桌面的类型；读不到是 nil。
        var spaceType: (CGDirectDisplayID) -> Int?
        /// 前台焦点窗口是不是全屏，以及它大致在哪块屏；读不到是 (nil, .unknown)。
        var focusedWindow: () -> (display: CGDirectDisplayID?, fact: NotchSpaceFact)
        /// 调度中心开着没有。
        var missionControl: () -> NotchSpaceFact
        var displays: () -> [CGDirectDisplayID]
    }

    private let sources: Sources
    private(set) var yielding: Set<CGDirectDisplayID> = []
    /// 让开的集合变了：参数是现在该让开的屏。
    var onChange: ((Set<CGDirectDisplayID>) -> Void)?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var settle: DispatchWorkItem?
    private var started = false

    init(sources: Sources) { self.sources = sources }

    convenience init(missionControl: @escaping () -> NotchSpaceFact) {
        self.init(sources: Sources(
            spaceType: { NotchSpaceGate.readSpaceType($0) },
            focusedWindow: { NotchSpaceGate.readFocusedWindow() },
            missionControl: missionControl,
            displays: { NSScreen.screens.compactMap {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value } }))
    }

    /// 这块屏现在是不是全屏桌面（现读，不看缓存）。读不到当未知。
    func fullScreenFact(on display: CGDirectDisplayID) -> NotchSpaceFact {
        if let type = sources.spaceType(display) { return Self.fact(forSpaceType: type) }
        let focused = sources.focusedWindow()
        if focused.display == display { return focused.fact }
        return .unknown
    }

    func missionControlFact() -> NotchSpaceFact { sources.missionControl() }

    /// 重算一遍；变了才通知。第 1 层放行由面板按自己的层处理，这里只给“系统层面该不该让开”。
    @discardableResult
    func recompute() -> Set<CGDirectDisplayID> {
        let mission = sources.missionControl()
        var next: Set<CGDirectDisplayID> = []
        for display in sources.displays()
        where Self.yields(fullScreen: fullScreenFact(on: display), missionControl: mission, authorizationLayer: false) {
            next.insert(display)
        }
        if next != yielding {
            yielding = next
            onChange?(next)
        }
        return next
    }

    func start() {
        guard !started else { return }
        started = true
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let names: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.activeSpaceDidChangeNotification),
            (workspace, NSWorkspace.didActivateApplicationNotification),
            (distributed, .init("com.apple.expose.awake")),
            (distributed, .init("com.apple.expose.front.awake")),
            (distributed, .init("com.apple.expose.sleep")),
            (distributed, .init("com.apple.expose.front.sleep")),
        ]
        for (center, name) in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.eventArrived() }
            }
            observers.append((center, token))
        }
        recompute()
    }

    func stop() {
        guard started else { return }
        started = false
        for item in observers { item.center.removeObserver(item.token) }
        observers = []
        settle?.cancel(); settle = nil
    }

    /// 通知一到先算一次，再在系统动画落定后复核一次（一次性，不循环）。
    private func eventArrived() {
        recompute()
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { _ = self?.recompute() }
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    // MARK: 私有读取（失败静默，当未知）

    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let skyLight: (main: MainConnection, spaces: CopySpaces)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainSymbol = dlsym(handle, "SLSMainConnectionID"),
              let spacesSymbol = dlsym(handle, "SLSCopyManagedDisplaySpaces") else { return nil }
        return (unsafeBitCast(mainSymbol, to: MainConnection.self), unsafeBitCast(spacesSymbol, to: CopySpaces.self))
    }()

    private static func readSpaceType(_ display: CGDirectDisplayID) -> Int? {
        guard let skyLight, let raw = skyLight.spaces(skyLight.main())?.takeRetainedValue(),
              let displays = raw as? [[String: Any]] else { return nil }
        var uuid: String?
        if let cf = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() {
            uuid = CFUUIDCreateString(nil, cf) as String?
        }
        return currentSpaceType(in: displays, displayUUID: uuid)
    }

    /// 退路：前台 App 的焦点窗口有没有 AXFullScreen，窗口中心落在哪块屏。
    private static func readFocusedWindow() -> (display: CGDirectDisplayID?, fact: NotchSpaceFact) {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return (nil, .unknown) }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() else { return (nil, .unknown) }
        let window = windowRef as! AXUIElement
        var flag: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &flag) == .success,
              let flag, CFGetTypeID(flag) == CFBooleanGetTypeID() else { return (nil, .unknown) }
        let isFull = CFBooleanGetValue((flag as! CFBoolean))
        var display: CGDirectDisplayID?
        var position: CFTypeRef?, size: CFTypeRef?
        var origin = CGPoint.zero, extent = CGSize.zero
        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
           AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
           let position, let size,
           AXValueGetValue(position as! AXValue, .cgPoint, &origin),
           AXValueGetValue(size as! AXValue, .cgSize, &extent) {
            var found = CGDirectDisplayID()
            var count: UInt32 = 0
            let center = CGPoint(x: origin.x + extent.width / 2, y: origin.y + extent.height / 2)
            if CGGetDisplaysWithPoint(center, 1, &found, &count) == .success, count == 1 { display = found }
        }
        return (display, isFull ? .yes : .no)
    }
}
