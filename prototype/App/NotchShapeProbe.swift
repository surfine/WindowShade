// 刘海贴合硬件的真机探针（--notch-shape，设计系统 §7）。
//
// 先把每块屏的形状记下来：从哪来（bezelPath / 机型表 / 现版本）、pxPerPt、刘海底角和肩、屏幕的角、和机型表差多少面板像素；
// 再问一遍，确认是按屏缓存的（不重复算，不增加常驻耗电）。然后在带刘海那块屏上直接摆出几种样子，量岛和肩：
// - 静止：岛不画，肩和硬件的肩重合；
// - 紧凑样式、两边空 34 点：肩从两侧扣（S1），外沿和面板都和现版本一样宽，肩贴在岛的上角，肩那层窗口不接指针（S2）；
// - 紧凑样式、两边只空 30 点：扣完不够 26 点，不画肩，和现版本一样；
// - 下巴（一边只空 10 点）：主体和刘海一样宽，肩和硬件的肩重合；
// - 展开一排：肩直接收掉（从和硬件重合的地方出发，不先亮出来再缩；S3）；收回下巴时一路不长，停稳后换回和硬件重合；
// - 假装不知道硬件形状：没有肩那层窗口，底角回到 10 / 12（帕累托：和现版本逐一相等）。
// 只动刘海面板自己（紧凑样式用假的内容和给定的空位），不动任何 App 的窗口；跑完（或者中途被取消）都收回原样。
//
// 亲眼校准（--notch-calibrate，§7.3）另起一个入口：在屏幕最上面盖一条校准图停 90 秒，给 Aaron 用放大镜或手机微距看，不自动判。

import Cocoa

extension GlanceProbe {
  func exerciseNotchShape(pid: pid_t) async throws {
    let shapes = DisplayShapes.shared
    for screen in NSScreen.screens {
      let shape = shapes.shape(for: screen)
      let curves = shape.notchCurves.map { String(format: "notch bottom %.2f shoulder %.2f pt", $0.bottomRadius, $0.shoulderRadius) }
        ?? "no notch curves"
      print("INFO notch-shape: \(screen.localizedName) \(Int(screen.frame.width))×\(Int(screen.frame.height)) source=\(shape.source.rawValue) "
        + "pxPerPt=\(shape.pxPerPt.map { String(format: "%.3f", $0) } ?? "-") \(curves) "
        + String(format: "screen top %.2f bottom %.2f pt", shape.topCorner, shape.bottomCorner) + " — \(shape.note)")
      if shape.source == .bezel, let read = shape.notchCurves, let k = shape.pxPerPt,
        let table = shapes.tableOnly(for: screen)?.notchCurves {
        print(String(format: "INFO notch-shape: bezelPath vs table on %@: bottom %+.2f px, shoulder %+.2f px",
                     screen.localizedName, (read.bottomRadius - table.bottomRadius) * k, (read.shoulderRadius - table.shoulderRadius) * k))
      }
    }
    let computed = shapes.computed
    for screen in NSScreen.screens { _ = shapes.shape(for: screen) }
    owner.notch.install()
    print("\(shapes.computed == computed ? "PASS" : "FAIL") notch-shape: asking again (and reinstalling the notch) reuses the cached shapes (computed \(computed) → \(shapes.computed))")

    let notch = owner.notch
    guard let screen = NotchController.notchScreen(), let rect = NotchController.notchRect(on: screen),
      let panel = notch.notchPanelForProbe else {
      print("INFO notch-shape: this Mac has no notch showing (lid closed?); island checks skipped")
      return
    }
    // 中途被取消（Task.sleep 抛错）也要收回原样：硬件形状、展开、紧凑样式。
    let original = panel.hardware
    defer {
      panel.hardware = original
      panel.collapse()
      panel.setCompact(nil, room: nil)
    }
    let fake = NotchPanel.Compact(pid: nil, icon: NSImage(named: NSImage.applicationIconName), count: 1, changed: false)

    /// 摆出一种样子，等岛停稳（这一次变形的动画播完、外框 0.3 秒不变）；中途被别的刷新改掉就再摆一次。
    func settle(_ arrange: () -> Void, until ready: (NSRect) -> Bool) async throws -> (island: NSRect, radius: CGFloat, panel: NSRect,
                                                                                         shoulders: NotchShoulders.Probe?)? {
      for _ in 0..<3 {
        arrange()
        var last: NSRect?
        var steady = 0
        for _ in 0..<30 where steady < 3 {
          try await Task.sleep(nanoseconds: 100_000_000)
          let now = panel.shapeForProbe?.island
          steady = now == last && now.map(ready) == true && panel.isSettledForProbe ? steady + 1 : 0
          last = now
        }
        if steady >= 3 { return panel.shapeForProbe }
      }
      return nil
    }
    func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }
    func describe(_ s: NotchShoulders.Probe?) -> String {
      guard let s else { return "no shoulders" }
      return String(format: "shoulders %.2f@(%.2f, %.2f) %.2f@(%.2f, %.2f) e=%.2f",
                    s.leading.scale, s.leading.corner.x, s.leading.corner.y, s.trailing.scale, s.trailing.corner.x, s.trailing.corner.y, s.extent)
    }

    let tuckTarget = NotchIsland.tuckTarget(notch: rect, curves: panel.hardware)
    print("\(rect.contains(tuckTarget) || panel.hardware == nil ? "PASS" : "FAIL") notch-shape: a tucked window flies into \(tuckTarget) (notch \(rect))")

    guard let curves = panel.hardware else {
      let bare = try await settle({ panel.setCompact(nil, room: nil) }, until: { $0 == rect })
      print("\(bare?.shoulders == nil && bare.map { near($0.radius, 10) } == true ? "PASS" : "FAIL") notch-shape: the shape of this notch is unknown, so the island keeps today's geometry: no shoulders, 10 pt corners (\(bare.map { "\($0.island) r\($0.radius)" } ?? "-"))")
      return
    }
    let e = curves.shoulderExtent
    let sideWidth = NotchPanel.sideWidth

    // 静止：岛就是刘海，不画；肩和硬件的肩重合。
    let bare = try await settle({ panel.setCompact(nil, room: nil) }, until: { $0 == rect })
    let bareOK = bare.map { b in
      near(b.radius, curves.bottomRadius) && b.shoulders.map {
        $0.ignoresMouse && $0.leading.scale == 1 && $0.trailing.scale == 1
          && near($0.leading.corner.x, rect.minX) && near($0.trailing.corner.x, rect.maxX) && near($0.leading.corner.y, rect.maxY)
      } == true
    } == true
    print("\(bareOK && notch.isBareNotch ? "PASS" : "FAIL") notch-shape: at rest the island is the notch itself, hugged with its own \(String(format: "%.2f", curves.bottomRadius)) pt corners, and the shoulders sit on the hardware ones (\(bare.map { "\($0.island) r\($0.radius) \(describe($0.shoulders))" } ?? "did not settle"))")

    // 紧凑样式，两边空 34 点：S1 从两侧扣掉肩；外沿、面板和现版本一样宽；肩贴在岛的上角，不接指针。
    let full = MenuBarRoom.Sides(leading: 34, trailing: 34)
    let sides = try await settle({ panel.setCompact(fake, room: full) }, until: { $0.width > rect.width + 40 })
    let sidesOK = sides.map { s in
      let body = sideWidth - e
      let expectedPanel = NSIntegralRectWithOptions(rect.insetBy(dx: -sideWidth, dy: 0), .alignAllEdgesOutward)
      return near(s.island.minX, rect.minX - body) && near(s.island.maxX, rect.maxX + body) && s.panel == expectedPanel
        && near(s.radius, curves.bottomRadius)
        && s.shoulders.map {
          $0.ignoresMouse && $0.leading.scale == 1 && $0.trailing.scale == 1
            && near($0.leading.corner.x, s.island.minX) && near($0.trailing.corner.x, s.island.maxX)
            && near($0.leading.corner.x - $0.extent, rect.minX - sideWidth) && near($0.trailing.corner.x + $0.extent, rect.maxX + sideWidth)
        } == true
    } == true
    print("\(sidesOK && notch.islandFillsPanel ? "PASS" : "FAIL") notch-shape: compact sides with 34 pt free take the shoulders out of the sides (body \(String(format: "%.2f", sideWidth - e)) + shoulder \(String(format: "%.2f", e))), reach no further than before, keep the panel as wide as before, and the shoulders ride the island's top corners without taking clicks (\(sides.map { "island \($0.island) panel \($0.panel) \(describe($0.shoulders))" } ?? "did not settle"))")

    // 两边只空 30 点：扣完不够 26 点，不画肩，和现版本一样。
    let narrow = try await settle({ panel.setCompact(fake, room: MenuBarRoom.Sides(leading: 30, trailing: 30)) },
                                  until: { near($0.width, rect.width + 60) })
    let narrowOK = narrow.map { n in
      near(n.island.minX, rect.minX - 30) && near(n.island.maxX, rect.maxX + 30)
        && n.shoulders.map { $0.leading.scale == 0 && $0.trailing.scale == 0 } == true
    } == true
    print("\(narrowOK ? "PASS" : "FAIL") notch-shape: with only 30 pt free there is no room for a shoulder, so the sides are today's 30 pt (\(narrow.map { "island \($0.island) \(describe($0.shoulders))" } ?? "did not settle"))")

    // 一边只空 10 点：退回下巴（门槛不变），主体和刘海一样宽，肩和硬件的肩重合。
    let chin = try await settle({ panel.setCompact(fake, room: MenuBarRoom.Sides(leading: 10, trailing: 34)) },
                                until: { near($0.width, rect.width) && $0.height > rect.height + 4 })
    let chinOK = chin.map { c in
      near(c.radius, curves.bottomRadius) && c.shoulders.map {
        $0.leading.scale == 1 && $0.trailing.scale == 1 && near($0.leading.corner.x, rect.minX) && near($0.trailing.corner.x, rect.maxX)
      } == true
    } == true
    print("\(chinOK ? "PASS" : "FAIL") notch-shape: with one side taken it falls back to the chin, as wide as the notch, shoulders on the hardware ones (\(chin.map { "island \($0.island) r\($0.radius) \(describe($0.shoulders))" } ?? "did not settle"))")

    // 展开一排：肩收掉（外沿在量过的空位以外），停稳后再收回。
    panel.setCompact(fake, room: full)
    let expanded = try await settle({ panel.expand(with: []) }, until: { $0.height > rect.height + 40 })
    let expandedOK = expanded?.shoulders.map { $0.leading.scale == 0 && $0.trailing.scale == 0 } == true
    panel.collapse()
    print("\(expandedOK ? "PASS" : "FAIL") notch-shape: the expanded row has no shoulders (\(expanded.map { describe($0.shoulders) } ?? "did not settle"))")

    // 从下巴（肩和硬件重合，看不出来）展开：肩当场收掉，不先亮出来再一边外移一边缩；收回下巴时一路不长，停稳后换回和硬件重合。
    _ = try await settle({ panel.setCompact(fake, room: MenuBarRoom.Sides(leading: 10, trailing: 34)) },
                         until: { near($0.width, rect.width) && $0.height > rect.height + 4 })
    func hidden(_ s: NotchShoulders.Probe?) -> Bool { s.map { $0.leading.scale == 0 && $0.trailing.scale == 0 && !$0.resizing } == true }
    panel.expand(with: [])
    let snapped = hidden(panel.shapeForProbe?.shoulders)
    _ = try await settle({}, until: { $0.height > rect.height + 40 })
    panel.collapse()
    let held = hidden(panel.shapeForProbe?.shoulders)
    let back = try await settle({}, until: { near($0.width, rect.width) && $0.height < rect.height + 20 })
    let backOK = back?.shoulders.map { $0.leading.scale == 1 && $0.trailing.scale == 1 && !$0.resizing } == true
    print("\(snapped && held && backOK ? "PASS" : "FAIL") notch-shape: from the chin the unseen shoulders go at once when the row expands (not shown and shrunk), stay off on the way back, and sit on the hardware ones again once settled (snap \(snapped), held \(held), \(back.map { describe($0.shoulders) } ?? "did not settle"))")

    // 假装不知道硬件形状：没有肩那层窗口，底角回到 10 / 12，紧凑样式两侧 34 点（和现版本逐一相等）。
    panel.hardware = nil
    let legacyBare = try await settle({ panel.setCompact(nil, room: nil) }, until: { $0 == rect })
    let legacySides = try await settle({ panel.setCompact(fake, room: full) }, until: { near($0.width, rect.width + 2 * sideWidth) })
    panel.hardware = curves
    let legacyOK = legacyBare.map { $0.shoulders == nil && near($0.radius, 10) } == true
      && legacySides.map { $0.shoulders == nil && near($0.radius, 12) && near($0.island.minX, rect.minX - sideWidth) } == true
    print("\(legacyOK ? "PASS" : "FAIL") notch-shape: with the shape unknown the island is exactly today's (no shoulders, 10 pt at rest, 12 pt compact, 34 pt sides) (\(legacySides.map { "\($0.island) r\($0.radius)" } ?? "did not settle"))")
  }

  /// 亲眼校准（--notch-calibrate，设计系统 §7.3）：自动测试只能证明“和 bezelPath 一致”，这一步看它和实物是不是一致。
  /// 只在面板像素和屏幕像素一一对应时画（内建屏切到 1440×932，pxPerPt = 2 = backingScaleFactor），而且要读到了 bezelPath。
  /// 在屏幕最上面盖一条不接指针的窗口：bezelPath 算出的刘海左右竖边、底边各画 5 列（行）1 像素宽、红青交替的线，
  /// 正中那一列（行）是 bezelPath 说的最靠边的一列（行）刘海像素，画成红的：bezelPath 和实物一致时，贴着刘海露出来的那一列（行）是青的。
  /// 肩和屏幕两个顶角沿 45° 各画一串 1 像素的阶梯。停 90 秒：看硬件边缘挡住了哪一列、哪一行，阶梯从第几格开始露出来，拍照留档。
  func exerciseNotchCalibration(pid: pid_t) async throws {
    guard let screen = NotchController.notchScreen() else {
      print("INFO notch-calibrate: no notch showing (lid closed?); nothing to calibrate")
      return
    }
    let shape = DisplayShapes.shared.shape(for: screen)
    guard let k = shape.pxPerPt, abs(k - screen.backingScaleFactor) < 0.001, let body = shape.notchOutline,
      let curves = shape.notchCurves else {
      print("INFO notch-calibrate: switch the built-in display to 1440×932 first (panel px must equal screen px) and read bezelPath "
        + "(now pxPerPt=\(shape.pxPerPt.map { String(format: "%.3f", $0) } ?? "-") backing=\(screen.backingScaleFactor) source=\(shape.source.rawValue))")
      return
    }
    let band: CGFloat = 60
    let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - band, width: screen.frame.width, height: band)
    let width = Int((frame.width * k).rounded()), height = Int((band * k).rounded())
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1), cyan = CGColor(red: 0, green: 1, blue: 1, alpha: 1)
    /// 面板像素：x 从左数，row 从屏幕顶往下数。
    func dot(_ x: Int, _ row: Int, _ color: CGColor) {
      guard x >= 0, x < width, row >= 0, row < height else { return }
      context.setFillColor(color)
      context.fill(CGRect(x: x, y: height - 1 - row, width: 1, height: 1))
    }
    let left = Int((body.minX * k).rounded()), right = Int((body.maxX * k).rounded())
    let bottom = Int(((screen.frame.height - body.minY) * k).rounded())
    // 竖边：以 bezelPath 说的最靠边的一列刘海像素为正中（红），左右各两列，从刘海底往上 40 行画到往下 20 行。
    for edgeColumn in [left, right - 1] {
      for (i, column) in (edgeColumn - 2...edgeColumn + 2).enumerated() {
        for row in max(0, bottom - 40)..<(bottom + 20) { dot(column, row, i % 2 == 0 ? red : cyan) }
      }
    }
    // 底边：以 bezelPath 说的最下面一行刘海像素为正中（红），上下各两行，画在刘海平直的那一段下面。
    for (i, row) in (bottom - 3...bottom + 1).enumerated() {
      for column in (left + 60)..<(right - 60) { dot(column, row, i % 2 == 0 ? red : cyan) }
    }
    // 45° 阶梯：肩从（竖边, 顶边）往刘海外面走，屏幕顶角从角上往里走。
    for i in 0..<24 {
      let color = i % 2 == 0 ? red : cyan
      dot(left - 1 - i, i, color)
      dot(right + i, i, color)
      dot(i, i, color)
      dot(width - 1 - i, i, color)
    }
    guard let image = context.makeImage() else { return }
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 5)
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
    view.wantsLayer = true
    view.layer?.contents = image
    view.layer?.contentsScale = k
    view.layer?.contentsGravity = .topLeft
    view.layer?.magnificationFilter = .nearest
    panel.contentView = view
    panel.orderFrontRegardless()
    // 中途被取消也要撤掉：不然这条盖在菜单栏上的校准图要留到进程退出。
    defer { panel.orderOut(nil) }
    let d45 = { (r: CGFloat) in String(format: "%.1f", r * ContinuousCorner.inset45 * k) }
    print("INFO notch-calibrate: bezelPath puts the notch's edge columns at \(left) and \(right - 1) and its bottom row at \(bottom - 1) (drawn red); "
      + "if it matches the hardware, the column or row showing right next to the notch is cyan. The shoulder staircase should start showing "
      + "about \(d45(curves.shoulderRadius)) steps out, the screen corners' about \(d45(shape.topCorner)) steps in. "
      + "Showing for 90 s: look with a loupe or a phone macro lens and take a photo.")
    try await Task.sleep(nanoseconds: 90_000_000_000)
  }
}
