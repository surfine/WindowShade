// R8：什么时候提醒“别的窗口管理工具在抢快捷键”。纯逻辑，不碰系统、不碰 UserDefaults。
import Foundation

@main
struct WindowToolConflictTests {
  static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static func main() {
    let rectangle = "com.knollsoft.Rectangle"
    let magnet = "com.crowdcafe.windowmagnet"
    let finder = "com.apple.finder"

    expect(WindowToolConflict.toRemind(runningBundleIDs: [rectangle], takenShortcutCount: 0, alreadyReminded: [])  == nil,
           "a known tool just running is not a conflict")
    expect(WindowToolConflict.toRemind(runningBundleIDs: [finder], takenShortcutCount: 2, alreadyReminded: []) == nil,
           "shortcuts taken but no known tool running: nothing to name")
    expect(WindowToolConflict.toRemind(runningBundleIDs: [finder, rectangle], takenShortcutCount: 1, alreadyReminded: [])?.name == "Rectangle",
           "taken shortcut plus a running known tool: remind, naming it")
    expect(WindowToolConflict.toRemind(runningBundleIDs: [rectangle], takenShortcutCount: 1, alreadyReminded: [rectangle]) == nil,
           "already reminded about this tool: never again")
    expect(WindowToolConflict.toRemind(runningBundleIDs: [rectangle, magnet], takenShortcutCount: 1, alreadyReminded: [rectangle])?.name == "Magnet",
           "two tools running: skip the one already mentioned, name the other")
    expect(WindowToolConflict.toRemind(runningBundleIDs: [magnet, rectangle], takenShortcutCount: 1, alreadyReminded: [])?.name == "Rectangle",
           "two unmentioned tools: one at a time, in table order")
    expect(WindowToolConflict.toRemind(runningBundleIDs: ["COM.KNOLLSOFT.RECTANGLE"], takenShortcutCount: 1, alreadyReminded: [])?.name == "Rectangle",
           "bundle ids compare without case")
    expect(WindowToolConflict.toRemind(runningBundleIDs: ["com.knollsoft.Hookshot"], takenShortcutCount: 1, alreadyReminded: [rectangle])?.name == "Rectangle Pro",
           "Rectangle Pro is its own tool, not covered by the Rectangle reminder")
    expect(WindowToolConflict.toRemind(runningBundleIDs: ["apple.WindowManager"], takenShortcutCount: 3, alreadyReminded: []) == nil,
           "the system's own tiling agent is always running and is not in the table")

    let ids = WindowToolConflict.known.map { $0.bundleID.lowercased() }
    expect(Set(ids).count == ids.count, "no bundle id appears twice in the table")
    for required in ["com.knollsoft.rectangle", "com.knollsoft.hookshot", "com.crowdcafe.windowmagnet", "com.manytricks.moom",
                     "com.hegenberg.bettertouchtool", "cools.wins.main", "com.mizage.divvy", "com.divisiblebyzero.spectacle",
                     "co.highlyopinionated.swish", "com.mrkai77.loop", "bobko.aerospace", "com.amethyst.amethyst"] {
      expect(ids.contains(required), "table has \(required)")
    }

    if failures == 0 { print("PASS: window tool conflict — remind once per tool, only when a shortcut is taken") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
