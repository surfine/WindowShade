// 张合与轻点两下的只读事件监听：不拦截不改事件，自己的线程上收副本，主线程回调。

import Cocoa

/// 张合与轻点两下的只读监听。触控板手势在事件流里都是“手势”一类（NSEventTypeGesture = 29），
/// 张合、智能缩放（触控板两指 / Magic Mouse 单指轻点两下）是其中两种；只读监听收到的是副本，不拦截、不改事件，也不会被系统等着回调。
/// 放在自己的线程上：手指一放上触控板，这一类事件每秒约 60 个（实测），主线程不必逐个经手。
final class PinchEventTap: @unchecked Sendable {
    /// 在主线程上回调：(相位, 这一帧的缩放增量, AX 坐标)。
    var onMagnify: ((NSEvent.Phase, CGFloat, CGPoint) -> Void)?
    /// 在主线程上回调：轻点两下（智能缩放）的位置，AX 坐标。
    var onSmartMagnify: ((CGPoint) -> Void)?
    /// 在主线程上回调：触控板上接触着的手指数变了。甩一下标题栏靠它知道手指什么时候离开：
    /// 三指拖移结束时系统要再等 0.2–0.7 秒才发“松开”（实测），等它就晚了。
    var onTouchesChanged: ((TouchChange) -> Void)?

    struct TouchChange {
        var count: Int
        var previous: Int
        /// 事件时间戳，和 NSEvent.timestamp 同一个时钟。
        var time: TimeInterval
        /// 刚离开的手指在触控板上的位置（0–1，左下为原点）。
        var lifted: [CGPoint]
        /// 直接触摸（触摸屏一类）。现在的 Mac 上只有触控板的间接触摸；将来有触摸屏时从这里分辨。
        var direct: Bool
        /// 哪块板（规格 R25）：count / previous 都只是这块板上的手指数。
        var device: UInt64 = 0
        /// 过期恢复补出来的离手（见 TouchOwnership）：不据此判定手势结束。
        var recovered = false
    }

    private let lock = NSLock()
    private var port: CFMachPort?
    /// 只在监听线程上读写：每块板各自的手指数（规格 R25）。
    private var touchOwnership = TouchOwnership()
    /// 只在监听线程上读写：上一次查过的设备对象和它的编号，同一块板的帧不再重复去查。
    private var cachedDevice: AnyObject?
    private var cachedDeviceKey: UInt64 = 0
    /// 诊断：头 300 个手势类事件各是什么类型（查触摸流为什么没来）。
    private var typeCounts: [UInt: Int] = [:]
    private var typeSeen = 0
    fileprivate func noteType(_ raw: UInt, subtype: Int64) {
        guard typeSeen < 300 else { return }
        typeCounts[raw * 1000 + UInt(max(0, min(999, subtype))), default: 0] += 1
        typeSeen += 1
        if typeSeen == 300 {
            let summary = typeCounts.sorted { $0.key < $1.key }.map { "type\($0.key / 1000)/sub\($0.key % 1000)×\($0.value)" }.joined(separator: " ")
            DispatchQueue.main.async { wlog("gesture: tap event kinds \(summary)") }
        }
    }

    /// 已经在跑返回 true；没有辅助功能授权时建不起来，返回 false。
    func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let port {
            CGEvent.tapEnable(tap: port, enable: true)
            EventTapHealth.shared.register(port, label: "trackpad-pinch")
            return true
        }
        guard AXIsProcessTrusted() else { return false }
        let mask = CGEventMask(1) << 29
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                           options: .listenOnly, eventsOfInterest: mask,
                                           callback: pinchTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.port = port
        EventTapHealth.shared.register(port, label: "trackpad-pinch")
        let thread = Thread {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
        thread.name = "WindowShade.pinch-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: enabled)
        if enabled {
            EventTapHealth.shared.register(port, label: "trackpad-pinch")
        } else {
            EventTapHealth.shared.unregister(port)
        }
    }

    /// 被系统停掉后重开：主人的意图没变，不动登记表。
    fileprivate func reenable() {
        lock.lock()
        defer { lock.unlock() }
        if let port { CGEvent.tapEnable(tap: port, enable: true) }
    }

    fileprivate func deliverDoubleTap(_ location: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            self?.onSmartMagnify?(location)
        }
    }

    /// 在监听线程上：这个触点来自哪块板。系统的触控设备对象带一个设备号；取不到时用对象本身，再不行就是 nil（归到最近那块板）。
    private func deviceKey(_ touch: NSTouch) -> UInt64? {
        guard let raw = touch.device else { return nil }
        let device = raw as AnyObject
        if let cachedDevice, cachedDevice === device { return cachedDeviceKey }
        let key: UInt64
        if let object = device as? NSObject, object.responds(to: NSSelectorFromString("deviceID")),
           let number = object.value(forKey: "deviceID") as? NSNumber {
            key = number.uint64Value
        } else {
            key = UInt64(UInt(bitPattern: ObjectIdentifier(device)))
        }
        cachedDevice = device
        cachedDeviceKey = key
        return key
    }

    /// 在监听线程上：只在某块板的手指数变化时回主线程，手指在触控板上移动的每一帧都不打扰主线程。
    /// 两块板按设备分开数（规格 R25），一块板的手指不会改写另一块板的计数。
    fileprivate func noteTouches(_ event: NSEvent) {
        let touching = event.touches(matching: .touching, in: nil)
        var counts: [UInt64: Int] = [:]
        var direct: Set<UInt64> = []
        for touch in touching {
            let key = touchOwnership.key(for: deviceKey(touch))
            counts[key, default: 0] += 1
            if touch.type == .direct { direct.insert(key) }
        }
        // 只有手指数可能变了才去取离开的触点：手指在板上移动的每一帧不多做事。
        let only: (key: UInt64, value: Int)? = counts.isEmpty ? (touchOwnership.key(for: nil), 0)
            : counts.count == 1 ? counts.first : nil
        if let only, touchOwnership.key(for: nil) == only.key, touchOwnership.count(of: only.key) == only.value {
            // 这块板没变；可能顺带补出别的板的过期离手。
            let recovered = touchOwnership.frame(device: only.key, count: only.value, time: event.timestamp)
            guard !recovered.isEmpty else { return }
            let changes = recovered.map {
                TouchChange(count: $0.count, previous: $0.previous, time: event.timestamp, lifted: [], direct: false,
                            device: $0.device, recovered: $0.recovered)
            }
            DispatchQueue.main.async { [weak self] in
                for change in changes { self?.onTouchesChanged?(change) }
            }
            return
        }
        let ended = event.touches(matching: [.ended, .cancelled], in: nil)
        var lifted: [UInt64: [CGPoint]] = [:]
        for touch in ended {
            let key = touchOwnership.key(for: deviceKey(touch))
            lifted[key, default: []].append(touch.normalizedPosition)
            if counts[key] == nil { counts[key] = 0 }
        }
        if counts.isEmpty { counts[touchOwnership.key(for: nil)] = 0 }
        var changes: [TouchChange] = []
        for (key, count) in counts.sorted(by: { $0.key < $1.key }) {
            for change in touchOwnership.frame(device: key, count: count, time: event.timestamp) {
                let own = change.device == key && !change.recovered
                changes.append(TouchChange(count: change.count, previous: change.previous, time: event.timestamp,
                                           lifted: own ? lifted[key] ?? [] : [],
                                           direct: own && direct.contains(key),
                                           device: change.device, recovered: change.recovered))
            }
        }
        guard !changes.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            for change in changes { self?.onTouchesChanged?(change) }
        }
    }

    fileprivate func deliver(_ phase: NSEvent.Phase, _ delta: CGFloat, _ location: CGPoint) {
        DispatchQueue.main.async { [weak self] in
            self?.onMagnify?(phase, delta, location)
        }
    }
}

private func pinchTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<PinchEventTap>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        tap.reenable()
        return Unmanaged.passUnretained(event)
    }
    if type.rawValue == 29, let gesture = NSEvent(cgEvent: event) {
        tap.noteType(gesture.type.rawValue, subtype: event.getIntegerValueField(CGEventField(rawValue: 110)!))
        if gesture.type == .magnify {
            tap.deliver(gesture.phase, gesture.magnification, event.location)
        } else if gesture.type == .smartMagnify {
            tap.deliverDoubleTap(event.location)
        } else if gesture.type == .gesture {
            tap.noteTouches(gesture)
        }
    }
    return Unmanaged.passUnretained(event)
}
