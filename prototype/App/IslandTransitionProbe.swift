// 岛转场探针（--glance-probe --island-transition-probe，Phase 5）。
//
// 驱动真实 NotchPanel 走「紧凑（thinking）→ 展开（response）→ 收合（hidden）→ 提醒（transient）
// → 展开途中反向收合」，按 60 Hz 读**呈现层**上的岛宽（不是已经设好的目标），验证：
//   - 每一段都有足够的采样，相邻两帧的宽度变化不超过 120 点（没有模型跳变）；
//   - 展开 120 ms 后反向收合，宽度在反向点连续（速度接力，不是先停再跳）；
//   - 收合后岛停稳（isSettledForProbe）。
// 只动刘海面板自己，不动任何 App 的窗口；跑完收回原样。
// 需要真刘海屏；没有刘海时打印 skip。真机用法见 docs/reverse-engineering/island-parity-plan.md。

import Cocoa
import QuartzCore

extension GlanceProbe {
  func exerciseIslandTransitions(pid: pid_t) async throws {
    owner.notch.install()
    guard let screen = NotchController.notchScreen(), let rect = NotchController.notchRect(on: screen),
          let panel = owner.notch.notchPanelForProbe else {
      print("INFO island-transition: this Mac has no notch showing; skipped")
      return
    }
    print("INFO island-transition: notch \(rect) on \(screen.localizedName), reduced=\(Motion.reduced)")

    let compact = NotchPanel.Compact(pid: nil, icon: nil, count: 2, changed: false)
    let room = MenuBarRoom.Sides(leading: 240, trailing: 240)
    defer {
      panel.setCompact(nil, room: nil)
      panel.collapse()
    }

    func sleep(_ milliseconds: Int) async throws {
      try await Task.sleep(for: .milliseconds(milliseconds), clock: .suspending)
    }

    /// 跑一次转场：arrange 之后按 60 Hz 采样 seconds 秒，返回这一段呈现层宽度。
    func sample(seconds: Double, _ arrange: () -> Void) async throws -> [CGFloat] {
      arrange()
      var widths: [CGFloat] = []
      let end = CACurrentMediaTime() + seconds
      while CACurrentMediaTime() < end {
        if let width = panel.islandPresentationForProbe?.width { widths.append(width) }
        try await sleep(16)
      }
      return widths
    }

    func check(_ widths: [CGFloat], _ name: String, from: CGFloat? = nil) -> Bool {
      guard widths.count >= 8 else {
        print("FAIL island-transition: \(name) only \(widths.count) samples")
        return false
      }
      var previous = from ?? widths[0]
      var maxStep: CGFloat = 0
      for width in widths {
        maxStep = max(maxStep, abs(width - previous))
        previous = width
      }
      let start = from ?? widths[0]
      let ok = maxStep <= 120
      print("\(ok ? "PASS" : "FAIL") island-transition: \(name) width \(Int(start))→\(Int(widths.last ?? start)), "
        + "max frame step \(String(format: "%.1f", maxStep)) over \(widths.count) samples")
      return ok
    }

    var ok = true

    // 静止 → 紧凑两耳（thinking）：从刘海宽度长到两侧耳朵。
    panel.collapse()
    panel.setCompact(nil, room: nil)
    try await sleep(700)
    ok = try await check(sample(seconds: 0.8) { panel.setCompact(compact, room: room) }, "compact/thinking") && ok
    try await sleep(300)

    // 紧凑 → 展开（response）。
    ok = try await check(sample(seconds: 0.9) { panel.expand(with: []) }, "expand/response") && ok
    try await sleep(300)

    // 展开 → 收合（hidden）：收合本身在系统里由外层的 window sizing 承接，
    // 这里量的是 WindowShade 自己那根 islandSizing 的连续性。
    ok = try await check(sample(seconds: 0.9) { panel.collapse() }, "collapse/hidden") && ok
    try await sleep(300)

    // 收合 → 提醒（transient）：提醒 0.6 秒后自己收，收回去也要连续。
    panel.setCompact(nil, room: nil)
    try await sleep(400)
    let alertWidths = try await sample(seconds: 0.9) {
      panel.alert(NotchPanel.Alert(id: 0, icon: nil, title: "island-transition", subtitle: "probe"), duration: 0.6)
    }
    ok = check(alertWidths, "alert/transient") && ok
    try await sleep(1200)

    // 展开途中反向：120 ms 时收合，整段（含反向点）的相邻帧变化要连续。
    panel.setCompact(nil, room: nil)
    try await sleep(400)
    var reversal: [CGFloat] = []
    let started = CACurrentMediaTime()
    panel.expand(with: [])
    while CACurrentMediaTime() - started < 0.12 {
      if let width = panel.islandPresentationForProbe?.width { reversal.append(width) }
      try await sleep(16)
    }
    panel.collapse()
    while CACurrentMediaTime() - started < 1.0 {
      if let width = panel.islandPresentationForProbe?.width { reversal.append(width) }
      try await sleep(16)
    }
    ok = check(reversal, "expand→120ms→collapse") && ok

    // 停稳：收合后等动画播完。
    try await sleep(800)
    let settled = panel.isSettledForProbe
    print("\(settled ? "PASS" : "FAIL") island-transition: settles after collapse (island \(panel.shapeForProbe?.island ?? .zero))")
    ok = settled && ok
    print(ok ? "PASS island-transition: all transitions continuous" : "FAIL island-transition: see lines above")
  }
}
