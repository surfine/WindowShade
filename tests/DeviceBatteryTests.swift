// 设备电量纯逻辑（Core/DeviceBattery.swift），对应交接 v2 的 BATTERY-ISLAND-ACCEPTANCE：
// ID-01/02、DATA-01/02/03/04/07/10/12、ALERT-01/02/03/04/05/09/11、EVENT-02/03/04。
import Foundation

@main
struct DeviceBatteryTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static let mouse = DeviceIdentity(id: "hid.bt:aa", displayName: "妙控鼠标", kind: .mouse)
  static func reading(_ percent: Int?, at: Double, epoch: UInt64 = 1, charging: ChargingState = .unknown,
                      observed: Double? = nil, device: String = "hid.bt:aa") -> BatteryReading {
    BatteryReading(deviceID: device, component: .main, provider: "iokit.hid", providerEpoch: epoch, percent: percent,
                   charging: charging, sourceObservedAt: observed, receivedAt: at)
  }
  static func lows(_ events: [DeviceBatteryEvent]) -> [Int] {
    events.compactMap { if case .low(_, _, let t, _) = $0 { return t }; return nil }
  }

  static func main() {
    do {  // ID-01 两台同名；ID-02 改名
      var book = DeviceBatteryBook()
      let other = DeviceIdentity(id: "hid.bt:bb", displayName: "妙控鼠标", kind: .mouse)
      _ = book.connect(mouse, at: 0, initialSnapshot: false)
      _ = book.connect(other, at: 0, initialSnapshot: false)
      expect(book.devices.count == 2, "ID-01 two devices with the same name stay two devices")
      _ = book.record(reading(8, at: 1), now: 1)
      expect(lows(book.record(reading(8, at: 1, device: "hid.bt:bb"), now: 1)) == [10], "ID-01 each keeps its own reminder record")
      var renamed = mouse
      renamed.displayName = "Aaron 的鼠标"
      expect(book.connect(renamed, at: 2, initialSnapshot: false).isEmpty && book.devices["hid.bt:aa"]?.displayName == "Aaron 的鼠标",
             "ID-02 renaming only changes the shown name, no new device and no new announcement")
      expect(lows(book.record(reading(8, at: 3), now: 3)).isEmpty, "ID-02 and does not replay the low-battery reminder")
    }

    do {  // DATA-01/02/03/04
      var book = DeviceBatteryBook()
      _ = book.connect(mouse, at: 0, initialSnapshot: true)
      expect(book.record(reading(nil, at: 1), now: 1).isEmpty && book.readings.isEmpty, "DATA-01 unknown is not zero and raises nothing")
      expect(lows(book.record(reading(0, at: 2), now: 2)) == [5], "DATA-02 a valid 0% is kept and handled as low")
      for raw in [-1, 101, 255] { expect(BatteryReading.validPercent(raw) == nil, "DATA-03 \(raw) is rejected, not clamped") }
      _ = book.record(reading(nil, at: 3), now: 3)
      expect(book.readings[.init(deviceID: "hid.bt:aa", component: .main)]?.percent == 0,
             "DATA-04 an empty reading does not overwrite the last valid one")
    }

    do {  // DATA-07 连接保活不续期；ALERT-11 旧读数不发新提醒
      var book = DeviceBatteryBook()
      _ = book.connect(mouse, at: 0, initialSnapshot: true)
      _ = book.record(reading(50, at: 0), now: 0)
      book.seen("hid.bt:aa", at: 2_000)
      let key = DeviceBatteryBook.Key(deviceID: "hid.bt:aa", component: .main)
      expect(book.lastSeen["hid.bt:aa"] == 2_000 && book.freshness(key, now: 2_000) == .aged,
             "DATA-07 seeing the device again does not make its battery reading fresh")
      expect(lows(book.record(reading(8, at: 0, observed: 0), now: 2_000)).isEmpty,
             "ALERT-11 a reading sampled long ago raises no new reminder")
    }

    do {  // DATA-10 晚到回调
      var book = DeviceBatteryBook()
      _ = book.connect(mouse, at: 0, initialSnapshot: true)
      _ = book.record(reading(60, at: 5, epoch: 2), now: 5)
      expect(book.record(reading(9, at: 6, epoch: 1), now: 6).isEmpty
             && book.readings[.init(deviceID: "hid.bt:aa", component: .main)]?.percent == 60,
             "DATA-10 a late reading from an older collection round is dropped")
      _ = book.record(reading(55, at: 8, epoch: 2), now: 8)
      _ = book.record(reading(70, at: 7, epoch: 2), now: 8)
      expect(book.readings[.init(deviceID: "hid.bt:aa", component: .main)]?.percent == 55, "an out-of-order reading does not win")
    }

    do {  // DATA-12 电量上涨不等于充电；ALERT-09 充电未知也能提醒
      var book = DeviceBatteryBook()
      _ = book.connect(mouse, at: 0, initialSnapshot: true)
      _ = book.record(reading(40, at: 1), now: 1)
      _ = book.record(reading(45, at: 2), now: 2)
      expect(book.readings[.init(deviceID: "hid.bt:aa", component: .main)]?.charging == .unknown,
             "DATA-12 a rising level with no charging field stays unknown")
      expect(lows(book.record(reading(19, at: 3), now: 3)) == [20], "ALERT-09 an unknown charging state still allows the reminder")
    }

    do {  // ALERT-01/02/03/05
      var book = DeviceBatteryBook()
      _ = book.connect(mouse, at: 0, initialSnapshot: true)
      var all: [Int] = []
      for (i, p) in [21, 20, 21, 20, 19, 20, 12, 10, 11, 10, 9, 6, 5, 4].enumerated() {
        all += lows(book.record(reading(p, at: Double(i)), now: Double(i)))
      }
      expect(all == [20, 10, 5], "ALERT-01/02 hovering on a line reminds once; each lower tier reminds once")
      var fresh = DeviceBatteryBook()
      _ = fresh.connect(mouse, at: 0, initialSnapshot: true)
      expect(lows(fresh.record(reading(8, at: 1), now: 1)) == [10], "ALERT-03 first seen already low reminds once, at its tier")
      _ = fresh.record(reading(30, at: 2, charging: .charging), now: 2)
      expect(lows(fresh.record(reading(19, at: 3, charging: .notCharging), now: 3)) == [20],
             "ALERT-05 after charging, a new discharge can remind again")
      var climbed = DeviceBatteryBook()
      _ = climbed.connect(mouse, at: 0, initialSnapshot: true)
      _ = climbed.record(reading(9, at: 1), now: 1)
      _ = climbed.record(reading(16, at: 2), now: 2)
      expect(lows(climbed.record(reading(10, at: 3), now: 3)) == [10],
             "climbing five points above a reminded tier re-arms that tier")
    }

    do {  // ALERT-04 重连不清空；持久化
      var book = DeviceBatteryBook()
      _ = book.connect(mouse, at: 0, initialSnapshot: false)
      _ = book.record(reading(8, at: 1), now: 1)
      _ = book.disconnect("hid.bt:aa")
      _ = book.connect(mouse, at: 2, initialSnapshot: false)
      expect(lows(book.record(reading(8, at: 3), now: 3)).isEmpty, "ALERT-04 reconnecting while low does not remind again")
      let data = try! JSONEncoder().encode(book.alerted)
      var restarted = DeviceBatteryBook(alerted: try! JSONDecoder().decode([DeviceBatteryBook.Key: Int].self, from: data))
      _ = restarted.connect(mouse, at: 0, initialSnapshot: true)
      expect(lows(restarted.record(reading(8, at: 1), now: 1)).isEmpty, "a restart keeps the reminder record")
    }

    do {  // EVENT-02/03/04
      var book = DeviceBatteryBook()
      expect(book.connect(mouse, at: 0, initialSnapshot: true).isEmpty, "EVENT-02 devices found at launch are not announced")
      expect(book.record(reading(80, at: 1), now: 1).isEmpty, "and their battery is not announced either")
      var live = DeviceBatteryBook()
      expect(live.connect(mouse, at: 0, initialSnapshot: false) == [.connected(deviceID: "hid.bt:aa")],
             "EVENT-03 a new connection is announced at once")
      expect(live.record(reading(80, at: 0.5), now: 0.5) == [.batteryArrived(deviceID: "hid.bt:aa", component: .main, percent: 80)],
             "EVENT-03 the battery fills into the same card when it arrives")
      expect(live.record(reading(79, at: 30), now: 30).isEmpty, "and later readings don't re-announce")
      var slow = DeviceBatteryBook()
      _ = slow.connect(mouse, at: 0, initialSnapshot: false)
      _ = slow.record(reading(nil, at: 3), now: 3)
      expect(slow.readings.isEmpty, "EVENT-04 no battery yet stays unknown, never shown as 0")
      expect(slow.disconnect("hid.bt:aa") == [.disconnected(deviceID: "hid.bt:aa")] && slow.disconnect("hid.bt:aa").isEmpty,
             "disconnect is announced once")
    }

    do {  // 四态、重连留历史、充电盒不拿左右耳填
      var book = DeviceBatteryBook()
      _ = book.connect(mouse, at: 10, initialSnapshot: true)
      let waiting = book.rows(now: 10)
      expect(waiting.count == 1 && waiting[0].presence == .noData && waiting[0].percent == nil
             && waiting[0].unknownReason == "未知" && waiting[0].connectedAt == 10,
             "a connected device with no reading is no-data, not 0%")
      _ = book.record(reading(40, at: 11, observed: 11), now: 11)
      expect(book.rows(now: 11)[0].presence == .connected && book.rows(now: 11)[0].percent == 40
             && book.rows(now: 11)[0].sampledAt == 11, "a fresh reading is connected")
      expect(book.rows(now: 11 + DeviceBatteryBook.freshFor + 1)[0].presence == .stale,
             "an old reading stays on the row but is not current")
      _ = book.disconnect(mouse.id)
      let gone = book.rows(now: 12)
      expect(gone[0].presence == .disconnected && gone[0].percent == 40 && book.connectedAt[mouse.id] == 10,
             "disconnect keeps the last percent and the connection time")
      _ = book.connect(mouse, at: 20, initialSnapshot: false)
      expect(book.readings[.init(deviceID: mouse.id, component: .main)]?.percent == 40
             && book.connectedAt[mouse.id] == 20, "reconnect keeps the reading and records the new connection")
      _ = book.connect(mouse, at: 30, initialSnapshot: false)
      expect(book.connectedAt[mouse.id] == 20, "a repeated connect does not reset the connection time")

      let buds = DeviceIdentity(id: "bt:buds", displayName: "AirPods", kind: .headphones)
      var ears = DeviceBatteryBook()
      _ = ears.connect(buds, at: 1, initialSnapshot: true)
      _ = ears.record(BatteryReading(deviceID: buds.id, component: .left, provider: "test", providerEpoch: 1,
                                    percent: 10, charging: .unknown, sourceObservedAt: 1, receivedAt: 1), now: 1)
      _ = ears.record(BatteryReading(deviceID: buds.id, component: .right, provider: "test", providerEpoch: 1,
                                    percent: 90, charging: .unknown, sourceObservedAt: 1, receivedAt: 1), now: 1)
      let caseRow = ears.rows(now: 1).first { $0.component == .chargingCase }
      expect(caseRow?.percent == nil && caseRow?.presence == .noData && caseRow?.unknownReason == "未知",
             "an unread case is its own unknown row")
      expect(BatterySources.chargingCasePercent(left: 10, right: 90, read: nil) == nil, "the case is not the average of the buds")
      expect(BatterySources.chargingCasePercent(left: 10, right: 90, read: 40) == 40, "a real case reading is kept")
      expect(InternalBattery.percent(InternalBatterySample(current: nil, max: 100, isCharging: nil, name: nil)) == nil,
             "a missing Mac capacity stays unknown")
      expect(InternalBattery.percent(InternalBatterySample(current: 0, max: 0, isCharging: false, name: nil)) == nil,
             "a zero max capacity is not 0%")
      expect(InternalBattery.percent(InternalBatterySample(current: 50, max: 100, isCharging: true, name: nil)) == 50,
             "a present Mac battery keeps its percent")
      expect(InternalBattery.charging(InternalBatterySample(current: 50, max: 100, isCharging: nil, name: nil)) == .unknown,
             "a missing charging flag stays unknown")
      expect(InternalBattery.displayName(InternalBatterySample(current: 1, max: 1, isCharging: nil, name: "InternalBattery-0")) == "这台 Mac",
             "a registry name is not shown")
      expect(BatterySources.notes.allSatisfy { note in
        if case .unproven = note.availability { return note.id != "power.internal" && note.id != "hid.apple-peripheral" }
        return true
      }, "unproven sources stay unproven")
      expect(BatterySources.notes.contains { $0.id == "airpods.case" && $0.availability == .unproven },
             "the case source is listed and unproven")
      expect(!BatterySources.notes.contains { $0.fact.contains("能耗") }, "battery notes do not include energy")
    }

    if failures == 0 { print("PASS: device battery identity, freshness and low-battery tiers") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
