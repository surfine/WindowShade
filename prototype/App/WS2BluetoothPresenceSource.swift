import CoreBluetooth
import Foundation
import IOBluetooth

// 离开就锁的蓝牙在场来源（App 侧）。IOBluetooth 桥：
// - 按用户选的地址在已配对列表里找那台设备；
// - 每 pollInterval 秒读一次 isConnected()（属性读，不起射频扫描）；
// - 连着时把真实 rawRSSI() 一并送进 reducer（读不到就不送 rssi，只送探针回执）；
// - 断开要持续 awayDebounce 秒才算离开（模型里判）。
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

@MainActor
final class WS2BluetoothPresenceSource: PresenceSource {
    private var model = WS2BluetoothPresenceModel(chosenAddress: WS2BluetoothPresenceChoice.address)
    private var device: IOBluetoothDevice?
    private var timer: Timer?
    private var emit: (([PresenceLock.Event]) -> Void)?
    private var generation: UInt64 = 0
    private var request: UInt64 = 0
    private let deviceType: PresenceLock.Device = .phone

    func start(emit: @escaping @MainActor ([PresenceLock.Event]) -> Void) {
        self.emit = emit
        generation &+= 1
        model = WS2BluetoothPresenceModel(chosenAddress: WS2BluetoothPresenceChoice.address)
        resolveDevice()
        pollOnce()
        scheduleNext()
    }

    func restart() {
        generation &+= 1
        resolveDevice()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        emit = nil
        device = nil
    }

    // MARK: 内部

    private func resolveDevice() {
        device = nil
        guard WS2BluetoothPresenceChoice.bluetoothAuthorized,
              let address = model.chosenAddress,
              let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        device = devices.first { WS2BluetoothPresenceModel.normalize($0.addressString) == address }
    }

    private func scheduleNext() {
        timer?.invalidate()
        let timer = Timer(timeInterval: model.pollInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollOnce()
                self?.scheduleNext()
            }
        }
        timer.tolerance = model.pollInterval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func pollOnce() {
        guard let emit else { return }
        guard let device else {
            // 选的设备不在配对列表里：按离开处理一次，之后沉默（模型保证不重复发）。
            if let event = model.poll(connected: nil, at: now) {
                emit([presenceEvent(event)])
            }
            return
        }
        let connected = device.isConnected()
        guard let event = model.poll(connected: connected, at: now) else {
            if connected { emit(probeBatch(rssi: readableRSSI(device))) }
            return
        }
        emit([presenceEvent(event)])
        // 连上或离开的这一次也带一次探针回执，reducer 状态立即可用。
        if connected { emit(probeBatch(rssi: readableRSSI(device))) }
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

    private func readableRSSI(_ device: IOBluetoothDevice) -> Int? {
        let value = Int(device.rawRSSI())
        return (-127 ... -1).contains(value) ? value : nil
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}
