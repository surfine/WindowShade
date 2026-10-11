// 离开就锁的蓝牙在场判定（Core/WS2BluetoothPresenceModel.swift）。纯时间驱动，不碰 IOBluetooth。
import Foundation

@main struct WS2BluetoothPresenceTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        // 地址归一化
        do {
            expect(WS2BluetoothPresenceModel.normalize("AA:BB:CC:DD:EE:FF") == "AA:BB:CC:DD:EE:FF", "canonical address stays")
            expect(WS2BluetoothPresenceModel.normalize("aa-bb-cc-dd-ee-ff") == "AA:BB:CC:DD:EE:FF", "dash form normalizes")
            expect(WS2BluetoothPresenceModel.normalize("aabbccddeeff") == "AA:BB:CC:DD:EE:FF", "bare hex normalizes")
            expect(WS2BluetoothPresenceModel.normalize("aabbccddeef") == nil, "11 hex digits refused")
            expect(WS2BluetoothPresenceModel.normalize("aabbccddeefg") == nil, "non-hex refused")
            expect(WS2BluetoothPresenceModel.normalize(nil) == nil, "nil refused")
            expect(WS2BluetoothPresenceModel.normalize("") == nil, "empty refused")
        }

        // 连着→断开持续 60 秒才算离开；期间重连不发声
        do {
            var m = WS2BluetoothPresenceModel(chosenAddress: "AA:BB:CC:DD:EE:FF", awayDebounce: 60, pollInterval: 5)
            expect(m.poll(connected: true, at: 0) == .connect, "first sighting connects")
            expect(m.poll(connected: true, at: 5) == nil, "staying connected is silent")
            expect(m.poll(connected: false, at: 10) == nil, "brief drop stays silent")
            expect(m.poll(connected: false, at: 40) == nil, "drop under 60 s stays silent")
            expect(m.poll(connected: true, at: 55) == .connect, "reconnect cancels the away window")
            expect(m.poll(connected: false, at: 100) == nil, "new drop starts a fresh window")
            expect(m.poll(connected: false, at: 159) == nil, "59 s of absence still silent")
            expect(m.poll(connected: false, at: 160) == .disconnect, "60 s of absence reports away")
            expect(m.poll(connected: false, at: 200) == nil, "away stays silent")
            expect(m.poll(connected: true, at: 260) == .connect, "coming back reconnects")
        }

        // 启动时就不在：不算离开（必须先见过它连着）
        do {
            var m = WS2BluetoothPresenceModel(chosenAddress: "AA:BB:CC:DD:EE:FF", awayDebounce: 60, pollInterval: 5)
            expect(m.poll(connected: false, at: 0) == nil, "absent at start is not away")
            expect(m.poll(connected: false, at: 500) == nil, "still absent, still silent")
            expect(m.poll(connected: true, at: 600) == .connect, "late arrival connects")
            expect(m.poll(connected: false, at: 601) == nil, "then a drop begins the window")
            expect(m.poll(connected: false, at: 700) == .disconnect, "sustained drop reports away")
        }

        // 设备被解除配对（nil 读数）：当作离开一次，之后沉默
        do {
            var m = WS2BluetoothPresenceModel(chosenAddress: "AA:BB:CC:DD:EE:FF", awayDebounce: 60, pollInterval: 5)
            _ = m.poll(connected: true, at: 0)
            expect(m.poll(connected: nil, at: 10) == .disconnect, "unpair while connected counts as away")
            expect(m.poll(connected: nil, at: 20) == nil, "stays silent after unpair")
            expect(m.poll(connected: true, at: 100) == .connect, "re-pair and return connects again")
        }

        // 没选设备：一切读数都沉默
        do {
            var m = WS2BluetoothPresenceModel(chosenAddress: nil)
            expect(!m.isConfigured, "unconfigured reports so")
            expect(m.poll(connected: true, at: 0) == nil, "unconfigured stays silent")
        }

        if failures > 0 { print("\(failures) FAILED"); exit(1) }
        print("PASS presence model")
    }
}
