// 别的桌面上的窗口进刘海（Core/ElsewhereWindows.swift）：哪些算、怎么排、写“桌面几”。
import CoreGraphics
import Foundation

@main
struct ElsewhereWindowsTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static func window(_ id: CGWindowID, pid: pid_t = 100, spaces: [UInt64], onScreen: Bool = false, layer: Int = 0,
                     size: CGSize = CGSize(width: 800, height: 600), alpha: Double = 1) -> ElsewhereCandidate {
    ElsewhereCandidate(id: id, pid: pid, layer: layer, bounds: CGRect(origin: CGPoint(x: 40, y: 60), size: size),
                       alpha: alpha, isOnScreen: onScreen, spaces: spaces)
  }

  // 一块屏：桌面 1（当前）、桌面 2、全屏的 Xcode、桌面 3。
  static let row = DesktopRow(spaces: [.init(id: 1, isFullScreen: false), .init(id: 2, isFullScreen: false),
                                       .init(id: 9, isFullScreen: true), .init(id: 3, isFullScreen: false)],
                              current: 1)

  static func ids(_ plan: [ElsewhereWindow]) -> [CGWindowID] { plan.map(\.id) }

  static func main() {
    do {
      let plan = ElsewhereWindows.plan(
        windows: [window(10, spaces: [1], onScreen: true), window(20, pid: 200, spaces: [2]),
                  window(30, pid: 300, spaces: [9]), window(40, pid: 400, spaces: [3])],
        desktops: [row], exclude: [], ownPID: 1)
      expect(ids(plan) == [20, 30, 40], "windows on other desktops are listed, the current desktop's are not")
      expect(plan.map(\.place) == [.desktop(2), .fullScreen, .desktop(3)],
             "desktops are numbered like Mission Control, skipping full-screen spaces")
      expect(plan.map { ElsewhereWindows.label($0.place) } == ["桌面 2", "全屏", "桌面 3"], "labels read 桌面 N / 全屏")
    }

    do {  // 在所有桌面上的窗口、最小化（没有桌面）、隐藏后在当前桌面上的，都不算别处
      let plan = ElsewhereWindows.plan(
        windows: [window(11, spaces: [1, 2, 3]), window(12, spaces: []), window(13, spaces: [1])],
        desktops: [row], exclude: [], ownPID: 1)
      expect(plan.isEmpty, "sticky, minimized and hidden-on-this-desktop windows are not 'elsewhere'")
    }

    do {  // 已经在那一排里的、自己的、太小的、透明的、不是普通层的
      let plan = ElsewhereWindows.plan(
        windows: [window(21, spaces: [2]), window(22, pid: 1, spaces: [2]),
                  window(23, spaces: [2], size: CGSize(width: 100, height: 300)),
                  window(24, spaces: [2], alpha: 0), window(25, spaces: [2], layer: 3), window(26, spaces: [2])],
        desktops: [row], exclude: [21], ownPID: 1)
      expect(ids(plan) == [26], "excluded, own, tiny, transparent and non-normal windows are skipped")
    }

    do {  // 次序跟窗口列表走（最近用过的在前）；同一个 App 最多 3 扇；总数有上限
      var windows: [ElsewhereCandidate] = []
      for n in 1...5 { windows.append(window(CGWindowID(100 + n), pid: 7, spaces: [2])) }
      for n in 1...5 { windows.append(window(CGWindowID(200 + n), pid: pid_t(800 + n), spaces: [3])) }
      let plan = ElsewhereWindows.plan(windows: windows, desktops: [row], exclude: [], ownPID: 1)
      expect(ids(plan) == [101, 102, 103, 201, 202, 203], "order follows recency, at most 3 per app, at most 6 in all")
    }

    do {  // 显示器各有一组桌面：每块屏从 1 数；看得见的是每块屏各自的当前桌面
      let external = DesktopRow(spaces: [.init(id: 50, isFullScreen: false), .init(id: 51, isFullScreen: false)],
                                current: 50)
      let plan = ElsewhereWindows.plan(
        windows: [window(31, spaces: [50], onScreen: false), window(32, spaces: [51]), window(33, spaces: [2])],
        desktops: [row, external], exclude: [], ownPID: 1)
      expect(ids(plan) == [32, 33], "the other display's current desktop counts as visible")
      expect(plan.first?.place == .desktop(5), "numbering continues across displays like Mission Control (3 here, then 4, 5 there)")
    }

    do {  // 读到一半桌面变了：不认识的桌面不放
      let plan = ElsewhereWindows.plan(windows: [window(41, spaces: [77])], desktops: [row], exclude: [], ownPID: 1)
      expect(plan.isEmpty, "a window on an unknown desktop is left out rather than mislabelled")
    }

    do {  // 同一个 id 出现两次（窗口列表重复）只放一次
      let plan = ElsewhereWindows.plan(windows: [window(51, spaces: [2]), window(51, spaces: [2])],
                                       desktops: [row], exclude: [], ownPID: 1)
      expect(ids(plan) == [51], "a duplicated window id is listed once")
    }

    do {  // 画面放在哪：这块屏上的窗口在原处、原大小；放不下等比缩小、留在可用区域里；别的屏上的挂在格子下面
      let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
      let visible = CGRect(x: 0, y: 70, width: 1470, height: 849)
      let tile = CGRect(x: 600, y: 780, width: 124, height: 120)
      let small = CGRect(x: 200, y: 200, width: 700, height: 500)
      expect(ElsewhereWindows.cardFrame(window: small, visible: visible, screen: screen, tile: tile) == small,
             "a window that fits is shown exactly where it is, at its own size")
      let full = CGRect(x: 0, y: 0, width: 1470, height: 956)
      let card = ElsewhereWindows.cardFrame(window: full, visible: visible, screen: screen, tile: tile)
      expect(visible.contains(card) && abs(card.width / card.height - full.width / full.height) < 0.01
             && abs(card.midX - full.midX) < 1, "a full-screen window is scaled to the usable area, keeping its shape")
      let low = CGRect(x: 1000, y: 10, width: 600, height: 400)
      let clamped = ElsewhereWindows.cardFrame(window: low, visible: visible, screen: screen, tile: tile)
      expect(visible.contains(clamped) && clamped.size == low.size && clamped.origin == CGPoint(x: 870, y: 70),
             "a window hanging off the edge is moved back inside the usable area")
      let other = CGRect(x: 2000, y: 100, width: 1600, height: 1000)
      let hung = ElsewhereWindows.cardFrame(window: other, visible: visible, screen: screen, tile: tile)
      expect(hung.maxY <= tile.minY - 7.9 && hung.width <= visible.width * 0.72 + 0.5 && visible.contains(hung)
             && abs(hung.width / hung.height - 1.6) < 0.01, "a window on another display hangs under the tile, scaled down")
      expect(ElsewhereWindows.cardFrame(window: .zero, visible: visible, screen: screen, tile: tile) == .zero,
             "an empty window gives no card")
    }

    do {  // 怎么过去：激活能准确切过去就激活，否则在指针那块屏上按“移动一个空间”走过去
      let left = ElsewhereWindows.SpaceKey(keyCode: 123, flags: 0x840000)
      let right = ElsewhereWindows.SpaceKey(keyCode: 124, flags: 0x840000)
      let easy = ElsewhereWindows.GoFacts(appHasWindowHere: false, targetIsAppFront: true, activationSwitches: true,
                                          appIsFrontmost: false, targetOnPointerDisplay: true)
      func go(_ facts: ElsewhereWindows.GoFacts, _ r: DesktopRow = row, _ t: UInt64 = 3,
              right rk: ElsewhereWindows.SpaceKey? = right) -> ElsewhereWindows.GoPlan {
        ElsewhereWindows.goPlan(facts, row: r, target: t, moveLeft: left, moveRight: rk)
      }
      expect(go(easy) == .activate, "an app with no window here, target its front window: just activate (the system switches)")
      var here = easy; here.appHasWindowHere = true
      expect(go(here) == .keys(right, count: 3), "with a window here too, walk right past the full-screen space: 3 steps")
      expect(go(here, DesktopRow(spaces: row.spaces, current: 3), 2) == .keys(left, count: 2), "and walk left when the target is to the left")
      var notFront = easy; notFront.targetIsAppFront = false
      expect(go(notFront) == .keys(right, count: 3), "the app's front window is on another desktop: activating would land there, so walk")
      var noSwitch = easy; noSwitch.activationSwitches = false
      expect(go(noSwitch) == .keys(right, count: 3), "switch-on-activate turned off: walk")
      var frontmost = easy; frontmost.appIsFrontmost = true
      expect(go(frontmost) == .keys(right, count: 3), "the app is already frontmost: activating does nothing, so walk")
      var otherDisplay = here; otherDisplay.targetOnPointerDisplay = false
      expect(go(otherDisplay) == .activate, "the target is on another display: the shortcut would move the wrong display, so activate")
      expect(go(here, right: nil) == .activate, "with the shortcut turned off it falls back to activating")
      expect(go(here, row, 77) == .activate, "an unknown target desktop falls back to activating")
      expect(ElsewhereWindows.spaceKey(nil, defaultKeyCode: 124) == right, "an untouched shortcut is the system default ⌃→")
      expect(ElsewhereWindows.spaceKey(["enabled": false], defaultKeyCode: 124) == nil, "a disabled shortcut is not used")
      let custom: [String: Any] = ["enabled": true, "value": ["parameters": [NSNumber(value: 65535), NSNumber(value: 2), NSNumber(value: 0x100000)]]]
      expect(ElsewhereWindows.spaceKey(custom, defaultKeyCode: 124) == ElsewhereWindows.SpaceKey(keyCode: 2, flags: 0x100000),
             "a rebound shortcut is followed as the user set it")
    }

    do {  // 藏起来的 App 叫哪一扇：跳过太小的、透明的，取第一扇够大的；都不够大就退回第一扇普通层的
      func row(_ id: CGWindowID, layer: Int = 0, alpha: Double = 1, size: CGSize = CGSize(width: 800, height: 600),
               pid: pid_t = 7) -> ElsewhereWindows.WindowRow {
        ElsewhereWindows.WindowRow(id: id, pid: pid, layer: layer, bounds: CGRect(origin: .zero, size: size), alpha: alpha)
      }
      let rows = [row(1, alpha: 0), row(2, size: CGSize(width: 200, height: 30)),
                  row(3, size: CGSize(width: 90, height: 300)), row(4, layer: 3), row(5), row(6)]
      expect(ElsewhereWindows.hiddenAppWindow(rows, pid: 7) == 5,
             "the hidden app's first window big enough is picked (skipping tiny, toolbar and transparent ones)")
      expect(ElsewhereWindows.hiddenAppWindow([row(1), row(2, size: CGSize(width: 119, height: 400))], pid: 7) == 1,
             "the first normal-layer window is picked when none is big enough")
      expect(ElsewhereWindows.hiddenAppWindow([row(2, pid: 9), row(3, layer: 1)], pid: 7) == nil,
             "a pid with no normal-layer window gets nothing")
      expect(ElsewhereWindows.hiddenAppWindow([row(1, pid: 9), row(2, pid: 9)], pid: 7) == nil,
             "another app's windows are not used")
    }

    do {  // 挂在格子下面：等比缩小、压在格子下边、整张留在可用区域里
      let visible = CGRect(x: 0, y: 70, width: 1470, height: 849)
      let tile = CGRect(x: 600, y: 780, width: 124, height: 120)
      let size = CGSize(width: 1600, height: 1000)
      let card = ElsewhereWindows.cardFrame(size: size, visible: visible, tile: tile)
      expect(card.maxY <= tile.minY - 7.9 && abs(card.midX - tile.midX) < 1 && visible.contains(card),
             "the card hangs under the tile, centred on it and inside the usable area")
      expect(abs(card.width / card.height - 1.6) < 0.01 && card.width <= visible.width * 0.72 + 0.5,
             "the card keeps its shape and stays within 72% of the usable width")
      let shallow = CGRect(x: 0, y: 70, width: 800, height: 100)
      // 格子下边离可用区域底边不到 8 + 10 点：放不下。
      expect(ElsewhereWindows.cardFrame(size: size, visible: shallow, tile: CGRect(x: 300, y: 85, width: 124, height: 20)) == .zero,
             "with no room below the tile there is no card")
      expect(ElsewhereWindows.cardFrame(size: .zero, visible: visible, tile: tile) == .zero
             && ElsewhereWindows.cardFrame(size: size, visible: .zero, tile: tile) == .zero,
             "an empty size or an empty usable area gives no card")
    }

    print(failures == 0 ? "all elsewhere window tests passed" : "\(failures) failure(s)")
    if failures > 0 { exit(1) }
  }
}
