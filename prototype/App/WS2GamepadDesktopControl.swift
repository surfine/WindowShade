// R09：手柄控制这台 Mac。公开的 GameController 接口；只算意图，动作走 NotchController.perform 这一个出口。
import Cocoa
@preconcurrency import GameController

/// 每台手柄一个“控制这台 Mac”开关，默认关；同一时间只有一台能操作，另一台只能看。
/// 十字键、×、○、△、Options 走 NotchController.perform（启动台和播放暂停走遥控器同一条端口）。
/// 游戏在前台时手柄整个让开：不装回调、不读、不改、不震。不轮询：前台变化、空间切换、睡眠、连接变化时才重算。
@MainActor final class WS2GamepadDesktopControl {
    static let shared = WS2GamepadDesktopControl()
    static let keysDefaultsKey = "WS2.gamepad.controlKeys"

    struct Row: Equatable {
        let id: UUID
        let name: String
        let access: GamepadSeats.Access
        /// 游戏在前台，手柄正让开着。
        let yielding: Bool
        /// 指挥页或选模型页正在用这台手柄，先让给它；离开页面后自动收回。
        var yieldingToPage = false
    }

    @MainActor private final class Pad {
        let controller: GCController
        let id = UUID()
        let serial: Int
        var table = GamepadButtonTable()
        var last: [String: Bool] = [:]
        var buttons: [(String, GCControllerButtonInput)] = []
        var ownsHandler = false
        var previousQueue: DispatchQueue?
        var holdTimer: Timer?
        init(_ controller: GCController, serial: Int) { self.controller = controller; self.serial = serial }
        var key: String { GamepadSeats.key(vendor: controller.vendorName, category: controller.productCategory) }
    }

    /// 已打开的手柄键（厂商名 + 类别）。GameController 没有持久 ID，这是尽力而为的识别。
    static var enabledKeys: Set<String> { Set(UserDefaults.standard.stringArray(forKey: keysDefaultsKey) ?? []) }
    private static func save(_ keys: Set<String>) { UserDefaults.standard.set(Array(keys).sorted(), forKey: keysDefaultsKey) }

    var onChange: (() -> Void)?
    private let port = WS2RemoteSystemPort()
    private var pads: [ObjectIdentifier: Pad] = [:]
    private var seats = GamepadSeats()
    private var access: [UUID: GamepadSeats.Access] = [:]
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var running = false
    private var nextSerial = 0
    private var yielding = true

    /// 启动时和设置变化时调用：有手柄开着才监听，全关就停。
    /// 不通知设置页：设置页重画时会再调到这里，通知会绕成圈。
    func applyPreferences() {
        let before = notifying
        notifying = false
        defer { notifying = before }
        if Self.enabledKeys.isEmpty { stop() } else { start() }
    }
    private var notifying = true
    private func notify() { if notifying { onChange?() } }

    /// 设置页用：当前连着的手柄。只看一眼，不装回调。
    func rows() -> [Row] {
        reconcile()
        return ordered().map { Row(id: $0.id, name: $0.controller.vendorName ?? "游戏手柄",
                                   access: access[$0.id] ?? .off, yielding: running && yielding,
                                   yieldingToPage: WS2GamepadHandlerSeats.shared.pageHolds($0.controller)) }
    }

    func setEnabled(_ on: Bool, padID: UUID) {
        guard let pad = pads.values.first(where: { $0.id == padID }) else { return }
        var keys = Self.enabledKeys
        if on { keys.insert(pad.key) } else { keys.remove(pad.key) }
        Self.save(keys)
        applyPreferences()
        refresh()
    }

    private func ordered() -> [Pad] { pads.values.sorted { $0.serial < $1.serial } }

    private func start() {
        guard !running else { refresh(); return }
        running = true
        WS2GamepadHandlerSeats.shared.onPageReleased = { [weak self] in self?.refresh() }
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.deactivateAll(); self?.notify() }
            })
        }
        refresh()
    }

    private func stop() {
        guard running else { return }
        running = false
        WS2GamepadHandlerSeats.shared.onPageReleased = nil
        deactivateAll()
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceObservers.removeAll()
        access = access.mapValues { _ in .off }
        notify()
    }

    private func reconcile() {
        let current = GCController.controllers(), present = Set(current.map(ObjectIdentifier.init))
        for key in Array(pads.keys) where !present.contains(key) {
            if let pad = pads.removeValue(forKey: key) { deactivate(pad) }
        }
        for c in current where pads[ObjectIdentifier(c)] == nil {
            guard let g = c.extendedGamepad else { continue }
            nextSerial += 1
            let pad = Pad(c, serial: nextSerial); pads[ObjectIdentifier(c)] = pad
            pad.buttons = [("a", g.buttonA), ("b", g.buttonB), ("y", g.buttonY), ("menu", g.buttonMenu),
                           ("up", g.dpad.up), ("down", g.dpad.down), ("left", g.dpad.left), ("right", g.dpad.right)]
        }
    }

    fileprivate func refresh() {
        reconcile()
        yielding = running ? Self.frontYields() : true
        let list = ordered()
        access = seats.update(pads: list.map { GamepadSeats.Pad(id: $0.id, key: $0.key) }, enabledKeys: running ? Self.enabledKeys : [])
        let unlocked = AuthorizationService.shared.lockState() == .unlocked
        for pad in list {
            if access[pad.id] == .controls, !yielding, unlocked { activate(pad) } else { deactivate(pad) }
        }
        notify()
    }

    private func deactivateAll() { for pad in pads.values { deactivate(pad) } }

    // MARK: 装回调、拿回调
    private func activate(_ pad: Pad) {
        guard !pad.ownsHandler, let g = pad.controller.extendedGamepad else { return }
        // 不抢别的子系统的回调（指挥页的手柄开着时，这里就保持不动）。
        guard g.valueChangedHandler == nil, WS2GamepadHandlerSeats.shared.claim(pad.controller, by: .desktop) else { return }
        pad.previousQueue = pad.controller.handlerQueue
        pad.controller.handlerQueue = .main
        pad.ownsHandler = true
        pad.last.removeAll()
        g.valueChangedHandler = { [weak self, weak pad] _, _ in MainActor.assumeIsolated {
            guard let self, let pad else { return }
            self.handle(pad)
        } }
    }

    private func deactivate(_ pad: Pad) {
        pad.holdTimer?.invalidate(); pad.holdTimer = nil
        pad.table.cancelAll(); pad.last.removeAll()
        guard pad.ownsHandler else { return }
        pad.ownsHandler = false
        pad.controller.extendedGamepad?.valueChangedHandler = nil
        if let queue = pad.previousQueue { pad.controller.handlerQueue = queue }
        pad.previousQueue = nil
        WS2GamepadHandlerSeats.shared.release(pad.controller, by: .desktop)
    }

    // MARK: 按键
    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    private func handle(_ pad: Pad) {
        guard pad.ownsHandler else { return }
        // 锁着就整个撤掉，不处理这一下。
        guard AuthorizationService.shared.lockState() == .unlocked else { refresh(); return }
        for (name, button) in pad.buttons {
            let pressed = button.isPressed
            guard pad.last[name] != pressed else { continue }
            pad.last[name] = pressed
            let at = Self.now()
            if pressed {
                if let intent = pad.table.press(name, at: at) { dispatch(intent) }
                if GamepadButtonTable.isHoldKey(name) { armHold(pad, name) }
            } else {
                if GamepadButtonTable.isHoldKey(name) { pad.holdTimer?.invalidate(); pad.holdTimer = nil }
                if let intent = pad.table.release(name, at: at) { dispatch(intent) }
            }
        }
    }

    /// 一次性定时器，不轮询；松开或让开时就作废。
    private func armHold(_ pad: Pad, _ name: String) {
        pad.holdTimer?.invalidate()
        let timer = Timer(timeInterval: GamepadButtonTable.holdSeconds, repeats: false) { [weak self, weak pad] _ in
            MainActor.assumeIsolated {
                guard let self, let pad, pad.ownsHandler else { return }
                pad.holdTimer = nil
                if let intent = pad.table.holdElapsed(name, at: Self.now()) { self.dispatch(intent) }
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        pad.holdTimer = timer
    }

    private func dispatch(_ intent: PadButtonIntent) {
        switch intent {
        case .focusUp: _ = port.perform(.focusUp)
        case .focusDown: _ = port.perform(.focusDown)
        case .focusLeft: _ = port.perform(.focusLeft)
        case .focusRight: _ = port.perform(.focusRight)
        case .activate: _ = port.perform(.activateFocused)
        case .back: _ = port.perform(.back)
        case .returnToRow: _ = port.perform(.notchShelf)
        case .launchpad: port.openLaunchpad()
        case .mediaPlayPause: port.postPlayPause()
        }
    }

    // MARK: 游戏在前台
    /// 前台 App 是游戏（Info.plist 分类），或前台 App 全屏而且手柄正被用着：让开。读不到当作游戏。
    static func frontYields() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return true }
        var category: String?
        var readable = false
        if let url = app.bundleURL, let bundle = Bundle(url: url) {
            readable = true
            category = bundle.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        }
        return GameFrontPolicy.yields(category: GameFrontPolicy.classify(bundleReadable: readable, category: category),
                                      fullScreen: frontHasFullScreenWindow(pid: app.processIdentifier),
                                      controllerInUse: GCController.current != nil)
    }

    /// 前台 App 有没有一扇和某块屏一样大的窗口。只比大小，不读标题。读不到返回 nil。
    private static func frontHasFullScreenWindow(pid: pid_t) -> Bool? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let sizes = NSScreen.screens.map(\.frame.size)
        for window in info {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            if sizes.contains(where: { abs($0.width - rect.width) < 1 && abs($0.height - rect.height) < 1 }) { return true }
        }
        return false
    }
}
