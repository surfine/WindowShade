import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import os

// 离开就锁的蓝牙在场来源（App 侧）。IOBluetooth 桥，事件驱动、没有周期轮询：
// - 按用户选的地址在已配对列表里找那台设备；
// - 启动和唤醒后读一次 isConnected() 当快照，之后靠 IOBluetooth 的连接／断开通知推进；
// - 断开要持续 awayDebounce 秒才算离开（模型里判）：断开时只排一个 awayDebounce 秒的一次性计时，
//   到点再读一次 isConnected() 喂模型，重连就取消；
// - 连上那一次把真实 rawRSSI() 一并送进 reducer（读不到就不送 rssi，只送探针回执）。
// RSSI 现在没有任何判定在用：PresenceLock 只在 returnEnabled 且 faceEnabled 时才吃 .rssi，
// 而这两个开关 App 里没有地方打开。将来打开「回来自动解锁」时，要在锁屏期间重新周期读 RSSI。
// 事件序列按 PresenceLock 的探针协议合成：readStarted → readSucceeded（+rssi）。

/// 选择存在 defaults 里的随身设备。
enum WS2BluetoothPresenceChoice {
    static let key = "Presence.lock.device"

    static var address: String? {
        WS2BluetoothPresenceModel.normalize(UserDefaults.standard.string(forKey: key))
    }

    static func setAddress(_ raw: String?) {
        let normalized = WS2BluetoothPresenceModel.normalize(raw)
        if let normalized { UserDefaults.standard.set(normalized, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    /// 蓝牙授权状态（查询本身不触发弹窗）。设置页只在 allowedAlways 时才碰 IOBluetooth——
    /// 未授权就调 pairedDevices() 会被 TCC 直接杀进程（真机验收 2026-10-11 实证）。
    /// 读的是 CBManager 的类属性：不建管理器，所以不会顺手弹系统框；要授权走 WS2BluetoothAuthorizationRequest。
    static var authorization: CBManagerAuthorization { CBManager.authorization }
    static var bluetoothAuthorized: Bool { authorization == .allowedAlways }

    /// 已配对设备清单（地址大写冒号 + 名字），给设置里的选择器用。未授权返回 nil（调用方显示引导）。
    static func pairedDevices() -> [(address: String, name: String)]? {
        guard bluetoothAuthorized else { return nil }
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return devices.compactMap { device in
            guard let address = WS2BluetoothPresenceModel.normalize(device.addressString) else { return nil }
            return (address, device.name ?? "")
        }.sorted { $0.name < $1.name }
    }
}

/// 向系统要一次蓝牙授权。以前只查不要：没决定过的人在系统设置的蓝牙列表里根本找不到 WindowShade，
/// 离开就锁打不开（2026-11-13 真机发现）。只在用户在设置里按「允许蓝牙…」时调用；系统弹窗用 Info.plist 的
/// NSBluetoothAlwaysUsageDescription。管理器要留到状态回来，否则弹窗还没出现它就被释放了。结果出来后发 didChange。
@MainActor final class WS2BluetoothAuthorizationRequest: NSObject, CBCentralManagerDelegate {
    static let shared = WS2BluetoothAuthorizationRequest()
    static let didChange = Notification.Name("WindowShade.bluetoothAuthorizationDidChange")
    nonisolated private static let log = Logger(subsystem: "com.windowshade.prototype", category: "presence")
    private var manager: CBCentralManager?
    private var activeObserver: NSObjectProtocol?
    /// 按「允许蓝牙…」的那扇设置窗口。系统框是别的进程弹的，按完焦点交回之前最前面的 App，
    /// 菜单栏 App 的设置窗口就被压到后面（11-13 真机）；有结果时把它叫回最前。
    private weak var returnWindow: NSWindow?

    func request(from window: NSWindow? = nil) {
        returnWindow = window
        guard WS2BluetoothPresenceChoice.authorization == .notDetermined, manager == nil else {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
            return
        }
        manager = CBCentralManager(delegate: self, queue: .main)
        // 系统框是别的进程弹的：按完「允许」焦点回到我们这边。状态回调不一定在那一刻到（11-13 真机：
        // 设置那一列没自己换成选择器），所以回到前台时也查一次。
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settleIfDecided() }
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Self.log.info("bluetooth central state \(central.state.rawValue, privacy: .public)")
        MainActor.assumeIsolated { settleIfDecided() }
    }

    private func settleIfDecided() {
        guard manager != nil, WS2BluetoothPresenceChoice.authorization != .notDetermined else { return }
        manager = nil
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        Self.log.info("bluetooth authorization decided: \(WS2BluetoothPresenceChoice.authorization.rawValue, privacy: .public) window=\(self.returnWindow != nil, privacy: .public) active=\(NSApp.isActive, privacy: .public)")
        if let window = returnWindow {
            // macOS 14 起协作式激活：背景 App 自己 activate() 会被系统拒绝。orderFrontRegardless 不需要先成为
            // 前台就能把窗口叠到别的 App 上面；再请求一次激活，让键盘焦点也回来（被拒也不影响窗口在前）。
            window.orderFrontRegardless()
            window.makeKey()
            NSApp.activate()
        }
        returnWindow = nil
    }
}

/// IOBluetooth 的接缝：来源只认这两个协议，测试用假实现驱动通知。
@MainActor protocol WS2BluetoothLinkDevice: AnyObject {
    var isConnected: Bool { get }
    var rssi: Int { get }
    /// 登记这台设备的断开通知，返回注销闭包。
    func registerDisconnect(_ handler: @escaping @MainActor () -> Void) -> () -> Void
}

@MainActor protocol WS2BluetoothBackend: AnyObject {
    /// 按归一化地址在已配对列表里找设备；未授权或不在列表里返回 nil。
    func pairedDevice(address: String) -> WS2BluetoothLinkDevice?
    /// 登记全局连接通知（参数是连上那台设备的归一化地址），返回注销闭包。
    func registerConnect(_ handler: @escaping @MainActor (String?) -> Void) -> () -> Void
}

/// 一次通知登记的接收端：IOBluetooth 只认 selector，所以要一个 NSObject。通知走主 run loop。
@MainActor private final class WS2IOBluetoothReceiver: NSObject {
    private let handler: @MainActor (IOBluetoothDevice) -> Void
    init(handler: @escaping @MainActor (IOBluetoothDevice) -> Void) { self.handler = handler }
    @objc func fired(_ note: IOBluetoothUserNotification, fromDevice device: IOBluetoothDevice) { handler(device) }
}

@MainActor private final class WS2IOBluetoothLinkDevice: WS2BluetoothLinkDevice {
    private let device: IOBluetoothDevice
    init(_ device: IOBluetoothDevice) { self.device = device }
    var isConnected: Bool { device.isConnected() }
    var rssi: Int { Int(device.rawRSSI()) }

    func registerDisconnect(_ handler: @escaping @MainActor () -> Void) -> () -> Void {
        let receiver = WS2IOBluetoothReceiver { _ in handler() }
        let note = device.register(forDisconnectNotification: receiver, selector: #selector(WS2IOBluetoothReceiver.fired(_:fromDevice:)))
        return { _ = receiver; note?.unregister() } // 注销闭包同时持有接收端，通知不持有它
    }
}

@MainActor final class WS2IOBluetoothBackend: WS2BluetoothBackend {
    func pairedDevice(address: String) -> WS2BluetoothLinkDevice? {
        guard WS2BluetoothPresenceChoice.bluetoothAuthorized,
              let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        return devices.first { WS2BluetoothPresenceModel.normalize($0.addressString) == address }
            .map { WS2IOBluetoothLinkDevice($0) }
    }

    func registerConnect(_ handler: @escaping @MainActor (String?) -> Void) -> () -> Void {
        // 未授权就调 IOBluetooth 会被 TCC 杀进程，所以没授权什么都不登记。
        guard WS2BluetoothPresenceChoice.bluetoothAuthorized else { return {} }
        let receiver = WS2IOBluetoothReceiver { handler(WS2BluetoothPresenceModel.normalize($0.addressString)) }
        let note = IOBluetoothDevice.register(forConnectNotifications: receiver, selector: #selector(WS2IOBluetoothReceiver.fired(_:fromDevice:)))
        return { _ = receiver; note?.unregister() }
    }
}

@MainActor
final class WS2BluetoothPresenceSource: PresenceSource {
    private var model = WS2BluetoothPresenceModel(chosenAddress: WS2BluetoothPresenceChoice.address)
    private let backend: WS2BluetoothBackend
    /// 排一次性计时，返回取消闭包；测试注入假的。
    private let schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void
    private let uptime: @MainActor () -> TimeInterval
    private var device: WS2BluetoothLinkDevice?
    private var unregisterConnect: (() -> Void)?
    private var unregisterDisconnect: (() -> Void)?
    private var cancelDebounce: (() -> Void)?
    private var cancelSafety: (() -> Void)?
    private var awayStart: TimeInterval?
    private var seenConnected = false
    private var emit: (([PresenceLock.Event]) -> Void)?
    private var generation: UInt64 = 0
    private var request: UInt64 = 0
    private let deviceType: PresenceLock.Device = .phone

    // 默认值在函数体里取：参数默认表达式在部分编译模式下按非隔离上下文检查，调不了主线程的初始化。
    init(backend: WS2BluetoothBackend? = nil,
         schedule: (@MainActor (TimeInterval, @escaping @MainActor () -> Void) -> () -> Void)? = nil,
         uptime: (@MainActor () -> TimeInterval)? = nil) {
        self.backend = backend ?? WS2IOBluetoothBackend()
        self.schedule = schedule ?? { WS2BluetoothPresenceSource.runLoopTimer($0, $1) }
        self.uptime = uptime ?? { ProcessInfo.processInfo.systemUptime }
    }

    func start(emit: @escaping @MainActor ([PresenceLock.Event]) -> Void) {
        unregisterAll()
        self.emit = emit
        generation &+= 1
        model = WS2BluetoothPresenceModel(chosenAddress: WS2BluetoothPresenceChoice.address)
        seenConnected = false; awayStart = nil
        unregisterConnect = backend.registerConnect { [weak self] address in self?.connectArrived(address) }
        resolveDevice()
        observe()
    }

    func restart() {
        generation &+= 1
        resolveDevice()
        observe() // 唤醒后补一次快照：睡着时错过的通知靠它追上
    }

    func stop() {
        unregisterAll()
        emit = nil
    }

    // MARK: 内部

    private func unregisterAll() {
        cancelDebounce?(); cancelDebounce = nil
        cancelSafety?(); cancelSafety = nil
        unregisterConnect?(); unregisterConnect = nil
        unregisterDisconnect?(); unregisterDisconnect = nil
        device = nil
    }

    private func resolveDevice() {
        unregisterDisconnect?(); unregisterDisconnect = nil
        device = model.chosenAddress.flatMap { backend.pairedDevice(address: $0) }
        unregisterDisconnect = device?.registerDisconnect { [weak self] in self?.disconnectArrived() }
    }

    private func connectArrived(_ address: String?) {
        guard emit != nil, let address, address == model.chosenAddress else { return }
        resolveDevice() // 重新登记断开通知，也能认出解除配对后重新配对的设备
        observe()
    }

    private func disconnectArrived() {
        guard emit != nil else { return }
        resolveDevice() // 解除配对会连带断开：列表里没了就按「读不到」立即处理
        observe(connectedOverride: false)
    }

    /// 取一次读数喂模型。connectedOverride：断开通知本身就是权威，不等 isConnected() 追上。
    private func observe(connectedOverride: Bool? = nil) {
        guard let emit else { return }
        let connected: Bool? = device.map { connectedOverride ?? $0.isConnected }
        let at = uptime()
        let event = model.poll(connected: connected, at: at)
        if connected == true { seenConnected = true }
        if let event {
            emit([presenceEvent(event)])
            // 连上那一次也带一次探针回执，reducer 状态立即可用。
            if event == .connect, let device { emit(probeBatch(rssi: readableRSSI(device))) }
            if event == .disconnect { seenConnected = false }
        }
        // 模型只在「见过连着」之后才会判离开；断开期间排一次计时，到点再读一次。
        if connected == false, seenConnected, event == nil {
            if awayStart == nil { awayStart = at }
            armDebounce(at: at)
        } else {
            awayStart = nil
            cancelDebounce?(); cancelDebounce = nil
        }
        // 保底（Aaron 11-06 定）：连着的时候每 pollInterval 秒再读一次 isConnected()，不读 RSSI。
        // 万一断开通知漏发，最多晚这么久开始去抖，和改动前的 5 秒轮询一样；断开期间由去抖计时接手。
        cancelSafety?(); cancelSafety = nil
        if connected == true {
            cancelSafety = schedule(model.pollInterval) { [weak self] in
                self?.cancelSafety = nil
                self?.observe()
            }
        }
    }

    private func armDebounce(at now: TimeInterval) {
        guard cancelDebounce == nil, let awayStart else { return }
        let remaining = max(0.5, awayStart + model.awayDebounce - now)
        cancelDebounce = schedule(remaining) { [weak self] in
            self?.cancelDebounce = nil
            self?.observe()
        }
    }

    private func probeBatch(rssi: Int?) -> [PresenceLock.Event] {
        request &+= 1
        var events: [PresenceLock.Event] = [.readStarted(deviceType, generation: generation, request: request),
                                            .readSucceeded(deviceType, generation: generation, request: request)]
        if let rssi, (-127 ... -1).contains(rssi) {
            events.append(.rssi(generation: generation, dbm: Double(rssi)))
        }
        return events
    }

    private func presenceEvent(_ event: WS2BluetoothPresenceModel.Event) -> PresenceLock.Event {
        switch event {
        case .connect: return .connected(deviceType, generation: generation)
        case .disconnect: return .disconnected(deviceType, generation: generation)
        }
    }

    private func readableRSSI(_ device: WS2BluetoothLinkDevice) -> Int? {
        let value = device.rssi
        return (-127 ... -1).contains(value) ? value : nil
    }

    nonisolated static func runLoopTimer(_ delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> () -> Void {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { fire() } }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }
}
