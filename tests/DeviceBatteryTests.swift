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
    for charging in [ChargingState.charging, .notCharging] {
      var book = DeviceBatteryBook()
      _ = book.connect(mouse, at: 0, initialSnapshot: true)
      expect(lows(book.record(reading(8, at: 1), now: 1)) == [10], "initial low recorded")
      _ = book.record(reading(80, at: 2000, charging: charging, observed: 0), now: 2000)
      expect(lows(book.record(reading(8, at: 2001), now: 2001)).isEmpty,
             "stale charging/recovery cannot rearm a repeated low reminder")
    }
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

    do {  // 蓝牙耳机：system_profiler JSON 解析
      func profile(connected: String, notConnected: String = "") -> Data {
        Data("""
        {"SPBluetoothDataType":[{"controller_properties":{},"device_connected":[\(connected)],"device_not_connected":[\(notConnected)]}]}
        """.utf8)
      }
      func entry(_ name: String, address: String, minor: String, extra: String = "") -> String {
        "{\"\(name)\":{\"device_address\":\"\(address)\",\"device_minorType\":\"\(minor)\",\"device_productID\":\"0x2024\",\"device_vendorID\":\"0x004C\"\(extra)}}"
      }
      let triple = BluetoothBatteryParse.parse(profile(connected: entry(
        "测试耳机", address: "AA:BB:CC:00:11:22", minor: "Headphones",
        extra: ",\"device_batteryLevelLeft\":\"85%\",\"device_batteryLevelRight\":\"84%\",\"device_batteryLevelCase\":\"60%\"")))
      expect(triple.count == 1 && triple[0].id == "spbt:aa-bb-cc-00-11-22" && triple[0].name == "测试耳机"
             && triple[0].kind == .headphones
             && triple[0].percents == [.left: 85, .right: 84, .chargingCase: 60],
             "BT left + right + case are read with a lowercase dash id")

      let leftOnly = BluetoothBatteryParse.parse(profile(connected: entry(
        "测试耳机", address: "AA:BB:CC:00:11:22", minor: "Headphones", extra: ",\"device_batteryLevelLeft\":\"7%\"")))
      expect(leftOnly.count == 1 && leftOnly[0].percents == [.left: 7], "BT left only leaves right and case with no reading")

      let main = BluetoothBatteryParse.parse(profile(connected: entry(
        "测试头戴", address: "AA:BB:CC:00:11:33", minor: "Headphones", extra: ",\"device_batteryLevelMain\":\"0%\"")))
      expect(main.count == 1 && main[0].percents == [.main: 0], "BT single battery maps to main and a real 0% stays 0")

      let bad = BluetoothBatteryParse.parse(profile(connected: entry(
        "测试耳机", address: "AA:BB:CC:00:11:22", minor: "Headphones",
        extra: ",\"device_batteryLevelLeft\":\"105%\",\"device_batteryLevelRight\":\"abc\",\"device_batteryLevelCase\":\"-3%\",\"device_batteryLevelMain\":\"50%\"")))
      expect(bad.count == 1 && bad[0].percents == [.main: 50], "BT out-of-range, garbled and negative values are unknown, never clamped")

      let none = BluetoothBatteryParse.parse(profile(connected: entry(
        "测试耳机", address: "AA:BB:CC:00:11:22", minor: "Headphones",
        extra: ",\"device_batteryLevelLeft\":\"105%\",\"device_batteryLevelRight\":\"abc\"")
        + "," + entry("测试音箱", address: "AA:BB:CC:00:11:44", minor: "Speaker")))
      expect(none.isEmpty, "BT devices with no valid battery value are left out")

      let mixed = BluetoothBatteryParse.parse(profile(
        connected: entry("测试鼠标", address: "AA:BB:CC:00:11:55", minor: "Mouse", extra: ",\"device_batteryLevelMain\":\"40%\"")
          + "," + entry("测试耳机", address: "AA:BB:CC:00:11:22", minor: "Headphones", extra: ",\"device_batteryLevelLeft\":\"50%\""),
        notConnected: entry("旧耳机", address: "AA:BB:CC:00:11:66", minor: "Headphones", extra: ",\"device_batteryLevelLeft\":\"90%\"")))
      expect(mixed.map(\.id) == ["spbt:aa-bb-cc-00-11-22", "spbt:aa-bb-cc-00-11-55"]
             && mixed.first { $0.id.hasSuffix("55") }?.kind == .mouse,
             "BT only device_connected counts, and kinds follow device_minorType")
      expect(BluetoothBatteryParse.kind(minorType: "Keyboard") == .keyboard && BluetoothBatteryParse.kind(minorType: "Trackpad") == .trackpad
             && BluetoothBatteryParse.kind(minorType: "Speaker") == .other && BluetoothBatteryParse.kind(minorType: nil) == .other,
             "BT minor types map to device kinds")
      let noAddress = BluetoothBatteryParse.parse(Data("""
        {"SPBluetoothDataType":[{"device_connected":[{"无地址":{"device_batteryLevelLeft":"50%"}}]}]}
        """.utf8))
      expect(noAddress.isEmpty, "BT a device without an address gets no id and is skipped")
      expect(BluetoothBatteryParse.parse(Data("not json".utf8)).isEmpty && BluetoothBatteryParse.parse(Data()).isEmpty
             && BluetoothBatteryParse.parse(Data("{\"SPBluetoothDataType\":5}".utf8)).isEmpty,
             "BT broken or unexpected JSON gives an empty list")
      expect(BluetoothBatteryParse.percent("100%") == 100 && BluetoothBatteryParse.percent(" 5 % ") == 5
             && BluetoothBatteryParse.percent("85.5%") == nil && BluetoothBatteryParse.percent("%") == nil
             && BluetoothBatteryParse.percent("+85%") == nil && BluetoothBatteryParse.percent(nil) == nil,
             "BT percent strings are strict integers 0...100")

      var book = DeviceBatteryBook()
      _ = book.connect(DeviceIdentity(id: triple[0].id, displayName: triple[0].name, kind: triple[0].kind), at: 1, initialSnapshot: true)
      for (component, value) in triple[0].percents {
        _ = book.record(BatteryReading(deviceID: triple[0].id, component: component, provider: "system_profiler",
                                       providerEpoch: 1, percent: value, charging: .unknown, sourceObservedAt: nil,
                                       receivedAt: 1, sampleMethod: "system_profiler"), now: 1)
      }
      let rows = book.rows(now: 2)
      expect(rows.map(\.component) == [.left, .right, .chargingCase] && rows.map(\.percent) == [85, 84, 60]
             && rows.allSatisfy { $0.presence == .connected && $0.sampleMethod == "system_profiler" },
             "BT parsed values feed the ledger as three headphone rows")
    }

    do {  // PWR-1：系统推送才读，变了才回调，台式 Mac 不建来源，低电量档位不变
      final class Counter { var reads = 0; var lpm = false; var sample: InternalBatterySample? }
      let box = Counter()
      box.sample = InternalBatterySample(current: 80, max: 100, isCharging: false, name: nil, isCharged: false)
      var gate = InternalPowerGate(readBattery: { box.reads += 1; return box.sample }, readLowPower: { box.lpm })
      expect(box.reads == 0, "PWR-1 building the gate reads nothing")
      expect(gate.refresh() != nil, "PWR-1 first push reports the reading")
      expect(box.reads == 1, "PWR-1 one push is one read")
      expect(gate.refresh() == nil && box.reads == 2, "PWR-1 an unchanged reading does not call back")
      box.sample?.isCharging = true
      expect(gate.refresh()?.isCharging == true, "PWR-1 plugging in calls back")
      box.lpm = true
      let lpm = gate.refresh()
      expect(lpm?.lowPowerMode == true && lpm?.isCharged == false, "PWR-1 low power mode change calls back and carries isCharged")
      box.sample?.isCharged = true
      expect(gate.refresh()?.isCharged == true, "PWR-1 fully charged calls back")
      gate.reset()
      expect(gate.refresh() != nil, "PWR-1 a restarted source reports once")
      box.sample = nil
      let desktop = InternalPowerGate(readBattery: { box.reads += 1; return box.sample }, readLowPower: { false })
      expect(!desktop.hasInternalBattery(), "PWR-1 a desktop Mac builds no source")
      box.sample = InternalBatterySample(current: 50, max: 100, isCharging: nil, name: nil)
      expect(desktop.hasInternalBattery(), "PWR-1 a laptop builds the source")
      var book = DeviceBatteryBook()
      let mac = DeviceIdentity(id: InternalBattery.deviceID, displayName: "这台 Mac", kind: .mac)
      _ = book.connect(mac, at: 0, initialSnapshot: true)
      func macReading(_ percent: Int, at: Double) -> BatteryReading {
        BatteryReading(deviceID: mac.id, component: .main, provider: "iops.internal", providerEpoch: 1,
                       percent: percent, charging: .notCharging, sourceObservedAt: nil, receivedAt: at,
                       isCharged: false, lowPowerMode: true)
      }
      var tiers: [Int] = []
      for (i, percent) in [30, 20, 19, 10, 9, 5, 4].enumerated() {
        tiers += lows(book.record(macReading(percent, at: Double(i + 1)), now: Double(i + 1)))
      }
      expect(tiers == [20, 10, 5], "PWR-1 the 20/10/5 low-battery tiers are unchanged")
      // 读数没变、一个小时没有推送：Mac 那一行仍是已连接；期间不读电源。
      var quiet = DeviceBatteryBook()
      _ = quiet.connect(mac, at: 0, initialSnapshot: true)
      _ = quiet.record(macReading(100, at: 1), now: 1)
      let readsBefore = box.reads
      let later = 1.0 + 60 * 60
      let macRow = quiet.rows(now: later).first { $0.deviceID == mac.id }
      expect(macRow?.presence == .connected && macRow?.percent == 100,
             "PWR-1 an unchanged push-fed Mac reading stays connected after an hour")
      expect(quiet.freshness(DeviceBatteryBook.Key(deviceID: mac.id, component: .main), now: later) == .currentEnough,
             "PWR-1 push-fed reading does not age")
      expect(box.reads == readsBefore, "PWR-1 no push means no read")
      // 其它来源仍按 15 分钟过期。
      var polled = DeviceBatteryBook()
      let pad = DeviceIdentity(id: "hid.bt:aa", displayName: "键盘", kind: .keyboard)
      _ = polled.connect(pad, at: 0, initialSnapshot: true)
      _ = polled.record(BatteryReading(deviceID: pad.id, component: .main, provider: "hid.apple-peripheral", providerEpoch: 1,
                                       percent: 50, charging: .unknown, sourceObservedAt: nil, receivedAt: 1), now: 1)
      expect(polled.rows(now: later).first { $0.deviceID == pad.id }?.presence == .stale,
             "PWR-1 polled sources still go stale after 15 minutes")
    }

    if failures == 0 { print("PASS: device battery identity, freshness and low-battery tiers") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
