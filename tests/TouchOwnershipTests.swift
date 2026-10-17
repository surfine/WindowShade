import Foundation

// 规格 R25：触控板手指数按物理设备分开记；丢了离手帧的板过一段时间自动当作离开。
// 纯逻辑：模拟内置触控板（1）和外接妙控板（2）交错送帧，不碰任何真实输入。

@main struct TouchOwnershipTests {
  static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }

  typealias Change = TouchOwnership.Change

  /// 以前的做法：只数一个总数，手指数一变就产出 (count, previous)。用来对照单设备时逐帧一致。
  struct LegacyCounter {
    var touchCount = 0
    mutating func frame(count: Int) -> [(Int, Int)] {
      guard count != touchCount else { return [] }
      defer { touchCount = count }
      return [(count, touchCount)]
    }
  }

  /// 主线程那一侧的判定（和 TrackpadGestures.touchesChanged 一样的规则）：这一下是否在这条变化上结束。
  static func ends(owner: UInt64?, touchedAtDown: Bool, _ change: Change) -> Bool {
    if let owner, owner != change.device { return false }
    return !change.recovered && touchedAtDown && change.count == 0 && change.previous > 0
  }

  static func main() {
    let builtIn: UInt64 = 1, external: UInt64 = 2

    // 1. 单设备：和以前逐帧完全一致（包括没有触点、看不出设备的帧，以及丢了离手帧之后又来手势）。
    do {
      var legacy = LegacyCounter()
      var owner = TouchOwnership()
      let script: [(UInt64?, Int)] = [
        (builtIn, 1), (builtIn, 2), (builtIn, 3), (builtIn, 3), (builtIn, 3), (builtIn, 2), (nil, 0), (nil, 0),
        (builtIn, 3), (builtIn, 3), // 离手帧丢了：停在 3
        (builtIn, 2), (builtIn, 0), (builtIn, 0), (builtIn, 1), (nil, 0),
      ]
      var t: TimeInterval = 100
      for (device, count) in script {
        t += device == nil ? 2.5 : 0.016  // 夹几段很长的空档：单设备时过期恢复不该介入
        let old = legacy.frame(count: count)
        let new = owner.frame(device: device, count: count, time: t)
        expect(new.count == old.count, "single device: same number of changes per frame")
        for (a, b) in zip(old, new) {
          expect(a.0 == b.count && a.1 == b.previous && !b.recovered && b.device == builtIn,
                 "single device: identical count/previous, never recovered")
        }
      }
    }

    // 2. 两块板交错送帧：各数各的，一块板的手指不改写另一块。
    do {
      var owner = TouchOwnership()
      var roster = TouchRoster()
      var t: TimeInterval = 0
      func feed(_ device: UInt64, _ count: Int) -> [Change] {
        t += 0.008
        let changes = owner.frame(device: device, count: count, time: t)
        for change in changes { roster.apply(change) }
        return changes
      }
      expect(feed(builtIn, 3) == [Change(device: builtIn, count: 3, previous: 0, recovered: false)], "built-in starts with three")
      expect(roster.active == builtIn && roster.activeCount == 3, "built-in is the device in use")
      // 三指拖移在内置板上：这一下归内置板。
      let dragOwner = roster.active
      expect(feed(external, 1) == [Change(device: external, count: 1, previous: 0, recovered: false)],
             "external finger counts on its own, previous is its own zero (not the built-in three)")
      var ended = false
      for _ in 0..<20 {
        for change in feed(builtIn, 3) + feed(external, 1) where ends(owner: dragOwner, touchedAtDown: true, change) { ended = true }
      }
      expect(!ended, "interleaved steady frames produce no changes and end nothing")
      expect(owner.count(of: builtIn) == 3 && owner.count(of: external) == 1, "counts stay per device")
      // 外接板抬手：不结束内置板上的这一下。
      for change in feed(external, 0) {
        expect(change.device == external && change.count == 0 && change.previous == 1, "external lift is its own")
        expect(!ends(owner: dragOwner, touchedAtDown: true, change), "external lift does not end the built-in drag")
      }
      expect(roster.active == builtIn && roster.activeCount == 3, "built-in still in use after the external lift")
      // 外接板又放手指、内置板抬手：内置板这一下照常在它自己的离手上结束。
      _ = feed(external, 2)
      let lift = feed(builtIn, 0)
      expect(lift == [Change(device: builtIn, count: 0, previous: 3, recovered: false)], "built-in lift reports its own previous")
      expect(lift.contains { ends(owner: dragOwner, touchedAtDown: true, $0) }, "built-in lift ends the built-in drag")
      expect(roster.active == external && roster.activeCount == 2, "external is in use once the built-in lifts")
      // 反过来：外接板拥有的拖动，不被内置板的放上/抬起结束。
      let externalOwner = roster.active
      for change in feed(builtIn, 1) + feed(builtIn, 0) {
        expect(!ends(owner: externalOwner, touchedAtDown: true, change), "built-in taps do not end the external drag")
      }
      expect(feed(external, 0).contains { ends(owner: externalOwner, touchedAtDown: true, $0) }, "external lift ends it")
      expect(roster.active == nil && roster.activeCount == 0, "no fingers anywhere")
    }

    // 3. 丢了离手帧：那块板很久没帧、另一块板来帧时补一个「已离开」，之后的手势照常归属、照常结束。
    do {
      var owner = TouchOwnership()
      var roster = TouchRoster()
      var t: TimeInterval = 50
      func feed(_ device: UInt64, _ count: Int, after gap: TimeInterval = 0.008) -> [Change] {
        t += gap
        let changes = owner.frame(device: device, count: count, time: t)
        for change in changes { roster.apply(change) }
        return changes
      }
      _ = feed(external, 3)
      _ = feed(external, 3)
      // 外接板的离手帧丢了（蓝牙断续）：它一直记着 3 根。
      // 还没过期：内置板来帧不补恢复。
      expect(feed(builtIn, 1, after: TouchOwnership.staleGap / 2) == [Change(device: builtIn, count: 1, previous: 0, recovered: false)],
             "no recovery before the stale gap")
      expect(owner.count(of: external) == 3, "still counted before the gap")
      _ = feed(builtIn, 0)
      // 过了过期间隔：内置板的下一帧顺带补出外接板的离开，标成 recovered。
      let changes = feed(builtIn, 2, after: TouchOwnership.staleGap)
      expect(changes == [Change(device: external, count: 0, previous: 3, recovered: true),
                         Change(device: builtIn, count: 2, previous: 0, recovered: false)],
             "stale external is recovered first, then the built-in change")
      expect(!changes.contains { ends(owner: external, touchedAtDown: true, $0) }, "a recovered lift never ends a drag")
      expect(roster.active == builtIn && roster.touchingDevices == 1, "the stuck device no longer claims the gesture")
      let next = roster.active
      expect(next == builtIn, "the next drag is owned by the device actually in use")
      expect(feed(builtIn, 0).contains { ends(owner: next, touchedAtDown: true, $0) }, "and ends on its own lift")
      // 外接板回来时从零开始数。
      expect(feed(external, 1) == [Change(device: external, count: 1, previous: 0, recovered: false)], "a recovered device starts from zero")
      // 同一块板自己的帧永远说真话，不靠过期恢复：很久之后同一块板来帧直接覆盖。
      let same = feed(external, 2, after: TouchOwnership.staleGap * 3)
      expect(same == [Change(device: external, count: 2, previous: 1, recovered: false)], "own frames overwrite, no recovery")
    }

    // 4. 看不出设备的帧（没有触点）归到最近那块板；一块都没见过时归到 0。
    do {
      var owner = TouchOwnership()
      expect(owner.key(for: nil) == 0, "unknown device before any frame is bucket 0")
      _ = owner.frame(device: external, count: 2, time: 1)
      expect(owner.key(for: nil) == external, "an empty frame belongs to the last device")
      expect(owner.frame(device: nil, count: 0, time: 1.01) == [Change(device: external, count: 0, previous: 2, recovered: false)],
             "an empty frame lifts the last device")
    }

    print("PASS: touch ownership — single device identical to the old counter, two devices interleaved without overwriting or ending each other, stale lift recovered without ending a drag, empty frames go to the last device")
  }
}
