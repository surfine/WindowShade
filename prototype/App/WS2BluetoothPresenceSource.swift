import CoreBluetooth
import Foundation
import IOBluetooth

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
    static var bluetoothAuthorized: Bool {
        CBCentralManager().authorization == .allowedAlways
    }

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
