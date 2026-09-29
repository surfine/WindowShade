// Rectangle 键位表的账、方向键换成字母（Swish 的键位），以及“放大一点 / 缩小一点 / 居中 / 高度占满”：纯逻辑，不碰任何窗口。
import CoreGraphics
import Foundation

@main
struct RectangleKeymapTests {
  static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  // 照着某张表拼出整张字典（有键位的才收）。
  static func table(_ f: (RectangleCommand) -> KeyCombo?) -> [RectangleCommand: KeyCombo] {
    var out: [RectangleCommand: KeyCombo] = [:]
    for c in RectangleCommand.allCases { if let combo = f(c) { out[c] = combo } }
    return out
  }

  static func main() {
    // 修饰键位：Cocoa 的位换成 Carbon 的；不认识的位置零。
    do {
      expect(RectangleKeymap.carbonModifiers(fromCocoa: 0x40000 | 0x80000) == 0x1800,
             "⌃⌥ is Carbon 0x1800")
      expect(RectangleKeymap.carbonModifiers(fromCocoa: 0x100000 | 0x80000 | 0x20000) == 0x0B00,
             "⌘⌥⇧ is Carbon 0x0B00")
      expect(RectangleKeymap.carbonModifiers(fromCocoa: 0x10000 | 0x800000) == 0,
             "caps lock and function bits are ignored")
      expect(RectangleKeymap.carbonModifiers(fromCocoa: 0x10000 | 0x800000 | 0x40000 | 0x1) == 0x1000,
             "stray bits around ⌃ do not change it")
    }

    // 两套默认表。
    do {
      expect(RectangleKeymap.recommended(.leftHalf) == KeyCombo(keyCode: 123, carbonModifiers: 0x1800),
             "the recommended set puts Left Half on ⌃⌥←")
      expect(RectangleKeymap.recommended(.restore) == KeyCombo(keyCode: 51, carbonModifiers: 0x1800),
             "and Restore on ⌃⌥Delete")
      expect(RectangleKeymap.recommendedSet.count == 21, "the recommended table has 21 shortcuts (got \(RectangleKeymap.recommendedSet.count))")
      expect(RectangleKeymap.spectacle(.topLeft) == KeyCombo(keyCode: 123, carbonModifiers: 0x1100),
             "the Spectacle set puts Top Left on ⌃⌘←")
      expect(RectangleKeymap.spectacle(.firstThird) == nil, "Spectacle has no thirds")
      expect(RectangleCommand.topLeft.raycastName == "Top Left Quarter", "Top Left Quarter is the Raycast name")
    }

    // 照着偏好设置算：没存过就是 Spectacle 那套，选了“推荐”就是推荐那套。
    do {
      let spectacle = RectangleKeymap.resolve(preferences: [:])
      expect(spectacle == table(RectangleKeymap.spectacle),
             "empty preferences give the Spectacle set (\(spectacle.count) entries)")
      let recommended = RectangleKeymap.resolve(preferences: ["alternateDefaultShortcuts": true])
      expect(recommended == RectangleKeymap.recommendedSet, "alternateDefaultShortcuts gives the recommended set")
    }

    // 用户自己改过的：存了就用存的，空的就没了，坏的照默认走，NSNumber 也认。
    do {
      let custom: [String: Any] = ["alternateDefaultShortcuts": true,
                                   "leftHalf": ["keyCode": 0, "modifierFlags": 0x180000],
                                   "maximize": [:]]
      let resolved = RectangleKeymap.resolve(preferences: custom)
      expect(resolved[.leftHalf] == KeyCombo(keyCode: 0, carbonModifiers: 0x0900),
             "a stored combo for Left Half wins over the default (got \(String(describing: resolved[.leftHalf])))")
      expect(resolved[.maximize] == nil, "an empty dictionary means the user cleared that shortcut")
      expect(resolved[.rightHalf] == RectangleKeymap.recommended(.rightHalf),
             "everything the user did not touch keeps the default")

      let numbers = RectangleKeymap.resolve(preferences: ["alternateDefaultShortcuts": true,
                                                          "leftHalf": ["keyCode": NSNumber(value: 123),
                                                                       "modifierFlags": NSNumber(value: 0x180000)]])
      expect(numbers[.leftHalf] == KeyCombo(keyCode: 123, carbonModifiers: 0x0900),
             "NSNumber keyCode and modifierFlags work too")

      let malformed = RectangleKeymap.resolve(preferences: ["alternateDefaultShortcuts": true,
                                                            "leftHalf": "nope",
                                                            "rightHalf": ["modifierFlags": 0x180000],
                                                            "topHalf": ["keyCode": -1, "modifierFlags": 0]])
      expect(malformed[.leftHalf] == RectangleKeymap.recommended(.leftHalf),
             "a value that is not a dictionary falls back to the default")
      expect(malformed[.rightHalf] == RectangleKeymap.recommended(.rightHalf),
             "a dictionary without keyCode falls back to the default")
      expect(malformed[.topHalf] == RectangleKeymap.recommended(.topHalf),
             "a negative keyCode falls back to the default")
    }

    // 照着导出的 RectangleConfig.json 算：只收出现且合法的已知动作。
    do {
      let json = """
      {"bundleId":"com.knollsoft.Rectangle","version":"1.2.3",
       "defaults":{"alternateDefaultShortcuts":{"bool":true}},
       "shortcuts":{"leftHalf":{"keyCode":0,"modifierFlags":393216},
                    "topHalf":{"keyCode":126,"modifierFlags":524288},
                    "unknownThing":{"keyCode":10,"modifierFlags":0},
                    "maximize":{"keyCode":-1,"modifierFlags":0}}}
      """
      if let resolved = RectangleKeymap.resolve(configJSON: Data(json.utf8)) {
        expect(resolved.count == 2, "only the two valid known shortcuts come through (got \(resolved.count))")
        expect(resolved[.leftHalf] == KeyCombo(keyCode: 0, carbonModifiers: 0x1200),
               "Left Half comes from the config file")
        expect(resolved[.topHalf] == KeyCombo(keyCode: 126, carbonModifiers: 0x0800),
               "Top Half comes from the config file")
      } else {
        expect(false, "a valid config file resolves")
      }
      expect(RectangleKeymap.resolve(configJSON: Data("not json".utf8)) == nil, "garbage is not a config")
      expect(RectangleKeymap.resolve(configJSON: Data("[1,2,3]".utf8)) == nil, "a JSON array is not a config")
      expect(RectangleKeymap.resolve(configJSON: Data("{\"bundleId\":\"x\"}".utf8)) == nil, "a config without shortcuts is not a config")
    }

    // 放大 / 缩小 / 居中 / 高度占满。
    do {
      let area = CGRect(x: 0, y: 25, width: 1728, height: 1080)
      let middle = CGRect(x: 600, y: 400, width: 400, height: 300)

      let centered = ResizeStep.centered(middle, in: area)
      expect(centered.size == middle.size, "centering keeps the size")
      expect(centered.midX == area.midX && centered.midY == area.midY, "and puts the window in the middle")

      let oversize = CGRect(x: -50, y: -50, width: 2000, height: 1400)
      let shrunk = ResizeStep.centered(oversize, in: area)
      expect(shrunk.size == area.size, "a window bigger than the screen shrinks to the screen")

      let bigger = ResizeStep.larger(middle, in: area)
      expect(bigger.size == CGSize(width: 460, height: 360), "Larger adds 30 points on every side (got \(bigger.size))")
      expect(bigger.midX == middle.midX && bigger.midY == middle.midY, "and grows around the same center")

      let onLeftEdge = CGRect(x: area.minX, y: 400, width: 400, height: 300)
      let grownFromEdge = ResizeStep.larger(onLeftEdge, in: area)
      expect(grownFromEdge.minX == area.minX && grownFromEdge.width == 460,
             "a window on the left edge grows to the right and stays put (\(grownFromEdge))")
      expect(grownFromEdge.maxX <= area.maxX && grownFromEdge.minY >= area.minY && grownFromEdge.maxY <= area.maxY,
             "Larger never leaves the screen")

      let small = ResizeStep.smaller(middle, in: area)
      expect(small.size == CGSize(width: 340, height: 240), "Smaller takes 30 points off every side (got \(small.size))")
      expect(small.midX == middle.midX && small.midY == middle.midY, "and shrinks around the same center")

      let corner = CGRect(x: area.minX, y: area.minY, width: 400, height: 300)
      let shrunkCorner = ResizeStep.smaller(corner, in: area)
      expect(shrunkCorner.minX == area.minX && shrunkCorner.minY == area.minY,
             "a window stuck to the top left keeps both its edges (\(shrunkCorner))")

      var floored = middle
      for _ in 0..<20 { floored = ResizeStep.smaller(floored, in: area) }
      expect(floored.width >= 240 && floored.height >= 160, "Smaller never goes below 240×160 (got \(floored.size))")
      let alreadyTiny = CGRect(x: 400, y: 400, width: 200, height: 100)
      expect(ResizeStep.smaller(alreadyTiny, in: area).size == alreadyTiny.size, "a window already tiny keeps its size")

      // 小一点也不出屏幕：半截在屏幕外的窗口缩完被拉回来，连按不会一步步走出去。
      let hanging = CGRect(x: area.maxX - 100, y: area.maxY - 80, width: 400, height: 300)
      let pulledIn = ResizeStep.smaller(hanging, in: area)
      expect(pulledIn.size == CGSize(width: 340, height: 240), "Smaller still shrinks a window hanging off the screen (got \(pulledIn.size))")
      expect(pulledIn.maxX <= area.maxX && pulledIn.maxY <= area.maxY && pulledIn.minX >= area.minX && pulledIn.minY >= area.minY,
             "and pulls it back inside the screen (\(pulledIn))")

      // 按实际拿到的大小重新摆：大小没变就一点不挪；保中心、保贴着的边，都在屏幕里。
      for frame in [middle, corner, CGRect(x: area.maxX - 420, y: area.maxY - 330, width: 400, height: 300)] {
        expect(ResizeStep.placed(frame.size, from: frame, in: area) == frame,
               "the same size puts the window back exactly where it was (\(frame))")
      }
      let keptCenter = ResizeStep.placed(CGSize(width: 380, height: 280), from: middle, in: area)
      expect(keptCenter.midX == middle.midX && keptCenter.midY == middle.midY,
             "a size the app capped stays around the same center (\(keptCenter))")
      let onRight = CGRect(x: area.maxX - 400, y: area.maxY - 300, width: 400, height: 300)
      let keptEdges = ResizeStep.placed(CGSize(width: 360, height: 270), from: onRight, in: area)
      expect(keptEdges.maxX == area.maxX && keptEdges.maxY == area.maxY,
             "a window stuck to the bottom right keeps both those edges (\(keptEdges))")
      let tooBig = ResizeStep.placed(CGSize(width: 2000, height: 1400), from: middle, in: area)
      expect(tooBig.minX == area.minX && tooBig.minY == area.minY && tooBig.size == CGSize(width: 2000, height: 1400),
             "a window bigger than the screen keeps its size and sits at the top left (\(tooBig))")
      let nearEdge = CGRect(x: area.maxX - 420, y: 400, width: 400, height: 300)
      let grownNearEdge = ResizeStep.placed(CGSize(width: 460, height: 300), from: nearEdge, in: area)
      expect(grownNearEdge.maxX <= area.maxX && grownNearEdge.width == 460,
             "a wider size near the edge is moved back inside (\(grownNearEdge))")

      let tall = ResizeStep.fullHeight(middle, in: area)
      expect(tall.minX == middle.minX && tall.width == middle.width, "full height leaves x and width alone")
      expect(tall.minY == area.minY && tall.height == area.height, "and stretches the window from top to bottom")

      let pushedOut = ResizeStep.fullHeight(CGRect(x: area.maxX - 100, y: 400, width: 400, height: 300), in: area)
      expect(pushedOut.maxX <= area.maxX && pushedOut.width == 400, "full height keeps the window inside the screen")
    }

    // 方向键换成字母（Swish 的 WASD / IJKL / HJKL；Dvorak 的 ,AOE 就是 WASD 那几个位置）。
    do {
      let ctrlCmd: UInt32 = 0x1100, ctrlOpt: UInt32 = 0x1800
      let arrows = DirectionKeySet.arrows.bindings
      expect(arrows == [.up: KeyCombo(keyCode: 126, carbonModifiers: ctrlCmd), .down: KeyCombo(keyCode: 125, carbonModifiers: ctrlCmd),
                        .left: KeyCombo(keyCode: 123, carbonModifiers: ctrlCmd), .right: KeyCombo(keyCode: 124, carbonModifiers: ctrlCmd)],
             "the arrow set is ⌃⌘↑↓←→, the shipped defaults")
      expect(DirectionKeySet.wasd.labelOrder.map { DirectionKeySet.wasd.keyCode($0) } == [13, 0, 1, 2],
             "WASD reads W A S D (up, left, down, right) — the same keys Swish's Dvorak set calls , A O E")
      expect(DirectionKeySet.ijkl.labelOrder.map { DirectionKeySet.ijkl.keyCode($0) } == [34, 38, 40, 37], "IJKL reads I J K L")
      expect(DirectionKeySet.hjkl.labelOrder.map { DirectionKeySet.hjkl.keyCode($0) } == [4, 38, 40, 37],
             "HJKL reads H J K L (left, down, up, right), like Vim")
      expect(DirectionKeySet.hjkl.combo(.up) == KeyCombo(keyCode: 40, carbonModifiers: ctrlOpt), "in HJKL, K is up")
      for set in DirectionKeySet.allCases where set != .arrows {
        expect(set.modifiers == ctrlOpt, "\(set.rawValue) uses ⌃⌥, never ⌘ (⌃⌘W, ⌃⌘D, ⌃⌘S, ⌃⌘L are taken)")
      }
      let names: [DirectionSlot: String] = [.up: "变小一级", .down: "变大一级", .left: "左半屏", .right: "右半屏"]
      for set in DirectionKeySet.allCases {
        expect(Set(set.bindings.values).count == 4, "\(set.rawValue) has four different keys")
        expect(DirectionKeySet.matching(set.bindings) == set, "\(set.rawValue) is recognised as itself")
        // IJKL 和 HJKL 共用 J K L、意思不同：从一套换到另一套是四个方向互相换位，不算撞车。
        for other in DirectionKeySet.allCases where other != set {
          let hop = DirectionKeys.plan(desired: other.bindings, current: set.bindings, holders: [:], titles: names)
          expect(hop.result == other.bindings && hop.clashes.isEmpty,
                 "\(set.rawValue) → \(other.rawValue) switches all four with no clash")
        }
      }
      var partial = DirectionKeySet.wasd.bindings
      partial[.left] = KeyCombo(keyCode: 6, carbonModifiers: ctrlOpt)
      expect(DirectionKeySet.matching(partial) == nil, "a set with one key changed by hand is no set")

      let titles: [DirectionSlot: String] = [.up: "变小一级", .down: "变大一级", .left: "左半屏", .right: "右半屏"]
      let wasd = DirectionKeySet.wasd.bindings

      let clean = DirectionKeys.plan(desired: wasd, current: arrows, holders: [:], titles: titles)
      expect(clean.result == wasd && clean.changed == Set(DirectionSlot.allCases) && clean.clashes.isEmpty,
             "with nothing in the way all four directions switch")

      // 别的动作先占着 ⌃⌥D（比如换上 Rectangle 后的左三分之一）：右半屏不换，说出是谁。
      let dTaken = KeyCombo(keyCode: 2, carbonModifiers: ctrlOpt)
      let blocked = DirectionKeys.plan(desired: wasd, current: arrows, holders: [dTaken: "左三分之一"], titles: titles)
      expect(blocked.result[.right] == arrows[.right] && !blocked.changed.contains(.right),
             "a combo another action already uses stays with it; that direction keeps its old key")
      expect(blocked.clashes == [DirectionKeyPlan.Clash(slot: .right, combo: dTaken, holder: "左三分之一")],
             "and the clash names who holds it (\(blocked.clashes))")
      expect(blocked.changed == [.up, .down, .left], "the other three still switch")

      // 连锁：变小一级自己录过 ⌃⌥A 又因为 ⌃⌥W 被占没换，左半屏就不能换成它还占着的 ⌃⌥A。
      var custom = arrows
      custom[.up] = KeyCombo(keyCode: 0, carbonModifiers: ctrlOpt)
      let wTaken = KeyCombo(keyCode: 13, carbonModifiers: ctrlOpt)
      let chained = DirectionKeys.plan(desired: wasd, current: custom, holders: [wTaken: "置顶"], titles: titles)
      expect(chained.result[.up] == custom[.up] && chained.result[.left] == custom[.left],
             "a direction that stays keeps its key, and nobody else may switch onto it (\(chained.result))")
      expect(chained.clashes.map(\.holder) == ["置顶", "变小一级"], "both clashes are reported (\(chained.clashes.map(\.holder)))")
      expect(Set(chained.result.values).count == chained.result.count, "no two directions end up on the same combo")

      // 想要同一个组合的两个方向：前面的先占上。
      let twice = DirectionKeys.plan(desired: [.up: wTaken, .down: wTaken], current: [:], holders: [:], titles: titles)
      expect(twice.result == [.up: wTaken] && twice.clashes.first?.holder == "变小一级",
             "two directions asking for the same combo: the first one gets it")

      let off = DirectionKeys.plan(desired: [.up: arrows[.up]!, .left: arrows[.left]!, .right: arrows[.right]!],
                                   current: arrows, holders: [:], titles: titles)
      expect(off.changed == [.down] && off.result[.down] == nil, "a direction missing from the wish is turned off")

      // 换回来：第一次换之前的样子记下来；换完后自己录过的方向听自己的。
      let first = DirectionKeyRecord.updated(nil, before: arrows, after: wasd)
      expect(first.previous == arrows && first.canRestore(wasd) && first.restoring(wasd) == arrows,
             "switching to WASD can be undone back to the arrows")
      var touched = wasd
      touched[.left] = KeyCombo(keyCode: 6, carbonModifiers: ctrlOpt)
      let back = first.restoring(touched)
      expect(back[.left] == touched[.left] && back[.up] == arrows[.up] && back[.right] == arrows[.right],
             "a direction recorded by hand after the switch is left as the user set it")
      let ijkl = DirectionKeySet.ijkl.bindings
      let second = DirectionKeyRecord.updated(first, before: touched, after: ijkl)
      expect(second.previous[.up] == arrows[.up] && second.previous[.left] == touched[.left],
             "switching on from WASD to IJKL keeps the original arrows, and the hand-recorded key as the original for its direction")
      expect(second.restoring(ijkl)[.left] == touched[.left] && second.restoring(ijkl)[.down] == arrows[.down],
             "so going back from IJKL gives the arrows plus the key the user chose")
      expect(!second.canRestore(arrows), "nothing to undo once the keys no longer look like the switch left them")
      var wasOff = arrows
      wasOff[.down] = nil
      expect(DirectionKeyRecord.updated(nil, before: wasOff, after: wasd).restoring(wasd)[.down] == nil,
             "a direction that was turned off goes back to off")

      // 注册不上（被别的 App 占着）时退回：IJKL → HJKL，⌃⌥J 被别的 App 占着，变大一级换不成 J。
      // 它原来的 ⌃⌥K 已经给了变小一级：变小一级也跟着不换，谁都不会被关掉。
      let hjkl = DirectionKeySet.hjkl.bindings
      let hop = DirectionKeys.plan(desired: hjkl, current: ijkl, holders: [:], titles: titles)
      expect(hop.changed == [.up, .down, .left], "IJKL → HJKL moves up, down and left; L stays right")
      let fell = DirectionKeys.fallBack(hop, current: ijkl, refused: [.down], titles: titles)
      expect(fell.result[.down] == ijkl[.down] && fell.result[.up] == ijkl[.up],
             "the refused direction goes back to its old key, and so does the one that had taken it (\(fell.result))")
      expect(fell.result[.left] == hjkl[.left] && fell.result[.right] == hjkl[.right],
             "directions that do not stand in the way still switch")
      expect(fell.returned == [.up, .down], "both returned directions are reported (\(fell.returned))")
      expect(fell.clashes == [DirectionKeyPlan.Clash(slot: .up, combo: ijkl[.down]!, holder: "变大一级")],
             "the one that followed is told who keeps its wanted key (\(fell.clashes))")
      expect(fell.result.count == 4 && Set(fell.result.values).count == 4,
             "every direction still has a key, and no two share one")

      let wRefused = DirectionKeys.fallBack(clean, current: arrows, refused: [.up], titles: titles)
      expect(wRefused.result[.up] == arrows[.up] && wRefused.returned == [.up] && wRefused.clashes.isEmpty,
             "arrows → WASD with ⌃⌥W held elsewhere: only up stays on ⌃⌘↑")
      expect(wRefused.result[.left] == wasd[.left], "the other three keep their new keys")

      let fromOff = DirectionKeys.fallBack(DirectionKeys.plan(desired: wasd, current: wasOff, holders: [:], titles: titles),
                                           current: wasOff, refused: [.down], titles: titles)
      expect(fromOff.result[.down] == nil && fromOff.returned == [.down],
             "a direction that was off and could not switch stays off")
      let untouched = DirectionKeys.fallBack(blocked, current: arrows, refused: [.right], titles: titles)
      expect(untouched.result == blocked.result && untouched.returned.isEmpty,
             "a direction the plan never changed is not the switch's to undo")

      // 账怎么记：点“方向键”盖掉了自己录的组合，也要能换回来。
      var own = arrows
      own[.left] = KeyCombo(keyCode: 38, carbonModifiers: 0x0900)   // ⌥⌘J
      own[.right] = KeyCombo(keyCode: 37, carbonModifiers: 0x0900)  // ⌥⌘L
      let overwrote = DirectionKeyRecord.afterChoosing(.arrows, restoring: false, saved: nil, before: own, after: arrows)
      expect(overwrote?.canRestore(arrows) == true && overwrote?.restoring(arrows) == own,
             "choosing the arrows over hand-recorded keys keeps them, so choosing the arrows again brings them back")
      expect(DirectionKeyRecord.afterChoosing(.arrows, restoring: false, saved: first, before: arrows, after: arrows) == nil,
             "already on the arrows: nothing to undo")
      expect(DirectionKeyRecord.afterChoosing(.arrows, restoring: true, saved: first, before: wasd, after: arrows) == nil,
             "once switched back, the record is done")
      var halfBack = arrows
      halfBack[.up] = wasd[.up]
      expect(DirectionKeyRecord.afterChoosing(.arrows, restoring: true, saved: first, before: wasd, after: halfBack) == first,
             "a direction that could not go back keeps the record, so the next try can finish it")
      expect(DirectionKeyRecord.afterChoosing(.wasd, restoring: false, saved: first, before: wasd, after: wasd) == first,
             "choosing a set that changes nothing leaves the record alone")
      expect(DirectionKeyRecord.afterChoosing(.ijkl, restoring: false, saved: first, before: wasd, after: ijkl)
             == DirectionKeyRecord.updated(first, before: wasd, after: ijkl),
             "switching on to another set keeps the first original")

      let stored = DirectionKeyRecord(plist: second.plist as Any)
      expect(stored == second, "the record survives a trip through preferences")
      let numbers: [String: Any] = ["previous": ["up": [NSNumber(value: 126), NSNumber(value: 0x1100)]],
                                    "applied": ["up": [NSNumber(value: 13), NSNumber(value: 0x1800)]]]
      expect(DirectionKeyRecord(plist: numbers)?.previous[.up] == arrows[.up], "NSNumber pairs read back")
      expect(DirectionKeyRecord(plist: "nope") == nil, "garbage is no record")
      expect(DirectionKeyRecord(plist: ["previous": ["up": [-1, 0]], "applied": [:]]) == nil, "a negative key code is no record")
      expect(DirectionKeyRecord(plist: ["previous": ["sideways": [1, 0]], "applied": [:]]) == nil, "an unknown direction is no record")
    }

    if failures == 0 { print("PASS: Rectangle keymap — recommended/Spectacle tables, preference and config resolution, grow/shrink/center/full-height, re-placing a capped size; direction keys — arrow/WASD/IJKL/HJKL sets, clashes, falling back, undo record") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
