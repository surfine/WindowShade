// 离开就锁的蓝牙在场来源（App/WS2BluetoothPresenceSource.swift）：用假的 IOBluetooth 接缝驱动
// 连接／断开通知和一次性去抖计时，核对事件序列。不碰真蓝牙。
import Foundation

// 测试里不带 PresenceLockDriver，协议在这里照原样声明。
@MainActor protocol PresenceSource: AnyObject {
    func start(emit: @escaping @MainActor ([PresenceLock.Event]) -> Void)
    func restart()
    func stop()
}

@MainActor final class FakeLink: WS2BluetoothLinkDevice {
    var isConnected = false
    var rssi = -50
    var disconnectHandler: (@MainActor () -> Void)?
    var disconnectRegistrations = 0
    func registerDisconnect(_ handler: @escaping @MainActor () -> Void) -> () -> Void {
        disconnectRegistrations += 1
        disconnectHandler = handler
        return { [weak self] in self?.disconnectHandler = nil }
    }
}

@MainActor final class FakeBackend: WS2BluetoothBackend {
    var link: FakeLink?
    var connectHandler: (@MainActor (String?) -> Void)?
    func pairedDevice(address: String) -> WS2BluetoothLinkDevice? { link }
    func registerConnect(_ handler: @escaping @MainActor (String?) -> Void) -> () -> Void {
        connectHandler = handler
        return { [weak self] in self?.connectHandler = nil }
    }
}

@MainActor final class Harness {
    static let address = "AA:BB:CC:DD:EE:FF"
    let backend = FakeBackend()
    let link = FakeLink()
    var now: TimeInterval = 1000
    var timers: [(delay: TimeInterval, due: TimeInterval, fire: @MainActor () -> Void, live: Bool)] = []
    var batches: [[PresenceLock.Event]] = []
    var source: WS2BluetoothPresenceSource!

    init() {
        backend.link = link
        source = WS2BluetoothPresenceSource(
            backend: backend,
            schedule: { [unowned self] delay, fire in
                timers.append((delay, now + delay, fire, true))
                let index = timers.count - 1
                return { self.timers[index].live = false }
            },
            uptime: { [unowned self] in now })
    }
    var liveTimers: Int { timers.filter { $0.live }.count }
    /// 去抖计时（60 秒那个）；连着时的 5 秒保底另算。
    var liveDebounce: Int { timers.filter { $0.live && $0.delay > 5 }.count }
    var liveSafety: Int { timers.filter { $0.live && $0.delay == 5 }.count }
    var flat: [PresenceLock.Event] { batches.flatMap { $0 } }
    func start() { source.start { [self] in batches.append($0) } }
    /// 假装通知到达：先改设备状态（和真机一样，通知在状态变化之后）。
    func connectNotification() { link.isConnected = true; backend.connectHandler?(Harness.address) }
    func disconnectNotification() { link.isConnected = false; link.disconnectHandler?() }
    /// 时间往前走：按到期先后触发，触发里新排的计时只要也在这段时间内到期就接着触发（保底会自己续排）。
    func advance(_ seconds: TimeInterval) {
        let end = now + seconds
        while let index = timers.indices.filter({ timers[$0].live && timers[$0].due <= end }).min(by: { timers[$0].due < timers[$1].due }) {
            now = max(now, timers[index].due)
            timers[index].live = false
            timers[index].fire()
        }
        now = end
    }
    func count(_ match: (PresenceLock.Event) -> Bool) -> Int { flat.filter(match).count }
}

@main struct WS2BluetoothPresenceSourceTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }
    static func isConnected(_ e: PresenceLock.Event) -> Bool { if case .connected = e { return true } else { return false } }
    static func isDisconnected(_ e: PresenceLock.Event) -> Bool { if case .disconnected = e { return true } else { return false } }
    static func isReadStarted(_ e: PresenceLock.Event) -> Bool { if case .readStarted = e { return true } else { return false } }
    static func isRSSI(_ e: PresenceLock.Event) -> Bool { if case .rssi = e { return true } else { return false } }

    @MainActor static func run() {
        // 启动时已连着：一次快照给出 connected + 探针回执（含 rssi），之后没有周期计时
        do {
            let h = Harness(); h.link.isConnected = true
            h.start()
            expect(h.count(isConnected) == 1, "start while connected emits connected once")
            expect(h.count(isReadStarted) == 1 && h.count(isRSSI) == 1, "start snapshot carries one probe with rssi")
            expect(h.liveTimers == 1 && h.liveSafety == 1, "while connected only the 5 s safety re-read is armed")
            h.batches = []; h.advance(60)
            expect(h.flat.isEmpty && h.liveSafety == 1, "safety re-reads stay silent while still connected")
            expect(h.backend.connectHandler != nil && h.link.disconnectHandler != nil, "connect and disconnect notifications registered")
        }

        // 断开通知：先静默，计时到点才认离开；到点前重连则取消，什么都不发
        do {
            let h = Harness(); h.link.isConnected = true
            h.start(); h.batches = []
            h.disconnectNotification()
            expect(h.flat.isEmpty, "disconnect notification alone stays silent (debounce)")
            expect(h.liveDebounce == 1 && h.liveSafety == 0, "one 60 s one-shot timer armed, safety stopped")
            h.advance(30); h.connectNotification()
            expect(h.liveDebounce == 0 && h.liveSafety == 1, "reconnect cancels the debounce timer and resumes the safety re-read")
            expect(h.count(isDisconnected) == 0, "reconnect inside 60 s never reports away")
            h.disconnectNotification(); h.advance(60)
            expect(h.count(isDisconnected) == 1, "60 s after disconnect reports away once")
            expect(h.liveTimers == 0, "no timer left after away is reported")
            h.advance(600)
            expect(h.count(isDisconnected) == 1, "stays silent after away")
        }

        // 离开后回来：connect 通知换来 connected + 探针；断开通知被重新登记
        do {
            let h = Harness(); h.link.isConnected = true
            h.start(); h.disconnectNotification(); h.advance(60)
            h.batches = []
            h.connectNotification()
            expect(h.count(isConnected) == 1 && h.count(isReadStarted) == 1, "return emits connected plus a probe")
            expect(h.link.disconnectHandler != nil, "disconnect notification re-registered after connect")
        }

        // 到点时设备其实又连着（漏了 connect 通知）：读到就当回来，不误报离开
        do {
            let h = Harness(); h.link.isConnected = true
            h.start(); h.batches = []
            h.disconnectNotification()
            h.link.isConnected = true // 没有通知
            h.advance(60)
            expect(h.count(isDisconnected) == 0, "timer re-read finds it connected, no false away")
        }

        // 断开通知漏发：5 秒保底读到断开，从那时起去抖 60 秒
        do {
            let h = Harness(); h.link.isConnected = true
            h.start(); h.batches = []
            h.link.isConnected = false // 没有通知
            h.advance(5)
            expect(h.flat.isEmpty && h.liveDebounce == 1, "safety re-read notices the drop within 5 s and starts the away window")
            h.advance(60)
            expect(h.count(isDisconnected) == 1, "missed disconnect notification still reports away (≤ 5 s + 60 s)")
        }

        // 启动时不在：不算离开，没有计时；它连上再断才开始计
        do {
            let h = Harness(); h.link.isConnected = false
            h.start()
            expect(h.flat.isEmpty && h.liveTimers == 0, "absent at start is silent with no timer")
            h.advance(500)
            expect(h.flat.isEmpty, "still silent")
            h.connectNotification()
            expect(h.count(isConnected) == 1, "late arrival connects")
            h.disconnectNotification(); h.advance(60)
            expect(h.count(isDisconnected) == 1, "then a sustained drop reports away")
        }

        // 别的设备连上：不理
        do {
            let h = Harness(); h.link.isConnected = true
            h.start(); h.batches = []
            h.backend.connectHandler?("11:22:33:44:55:66")
            expect(h.flat.isEmpty, "other device's connect notification ignored")
        }

        // 解除配对：断开通知里列表已空，立即按离开处理
        do {
            let h = Harness(); h.link.isConnected = true
            h.start(); h.batches = []
            h.backend.link = nil
            h.link.isConnected = false; h.link.disconnectHandler?()
            expect(h.count(isDisconnected) == 1, "unpair counts as away at once")
            expect(h.liveTimers == 0, "no timer after unpair")
        }

        // 唤醒 restart：补一次快照；睡着时断开的，从这时起算 60 秒
        do {
            let h = Harness(); h.link.isConnected = true
            h.start(); h.batches = []
            h.link.isConnected = false
            h.source.restart()
            expect(h.flat.isEmpty && h.liveTimers == 1, "restart snapshot starts the away window")
            h.advance(60)
            expect(h.count(isDisconnected) == 1, "away reported 60 s after the wake snapshot")
        }

        // stop：注销通知、取消计时，之后通知不再发事件
        do {
            let h = Harness(); h.link.isConnected = true
            h.start(); h.disconnectNotification()
            let connect = h.backend.connectHandler
            h.source.stop(); h.batches = []
            expect(h.backend.connectHandler == nil && h.link.disconnectHandler == nil, "stop unregisters both notifications")
            expect(h.liveTimers == 0, "stop cancels the timer")
            connect?(Harness.address); h.advance(120)
            expect(h.flat.isEmpty, "nothing emitted after stop")
        }

        if failures > 0 { print("\(failures) FAILED"); exit(1) }
        print("PASS presence source")
    }

    static func main() {
        WS2BluetoothPresenceChoice.setAddress(Harness.addressForDefaults)
        MainActor.assumeIsolated { run() }
        WS2BluetoothPresenceChoice.setAddress(nil)
    }
}
extension Harness { nonisolated static var addressForDefaults: String { "AA:BB:CC:DD:EE:FF" } }
