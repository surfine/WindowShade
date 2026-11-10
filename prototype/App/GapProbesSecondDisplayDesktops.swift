import Cocoa

// 副屏＋台前调度＋跨桌面 三合一的真机探针（--second-display-desktops）：
// 临时窗先挪到不是主屏的那块屏上，再让临时 App 自己把它挪到那块屏的另一张桌面（不切你的桌面）。
// 台前调度会把贴着边的辅助窗往里挪（2026-11-09 实测副屏上 x=-28 → x=136），
// 而窗口又不在你眼前——两条边界叠在一起时最容易出问题：
//   1) 收起不该把卷帘条冒到当前这张桌面上，也不该带走副屏的桌面；
//   2) 你在当前桌面上看不到任何卷帘条，所以要有一句「已收起到桌面 N」说清它去了哪；
//   3) 展开时窗口要回到副屏上原处，而不是回到被系统挪过的那条卷帘条的位置。
// 只动临时 App 的窗口，全程不切你的桌面；跑完把它放回原处。

extension GlanceProbe {
  func exerciseSecondDisplayDesktops(element: AXUIElement, pid: pid_t) async throws {
    NotchController.probeSilence = true
    guard owner.stageManagerGloballyEnabled() else {
      print("INFO second-display desktops: Stage Manager is off; the strip nudge this probe guards does not happen, skipped")
      return
    }
    let main = NSScreen.screens.first { $0.frame.origin == .zero }
    guard let other = NSScreen.screens.first(where: { $0 !== main }), let display = displayID(for: other) else {
      print("SKIP second-display desktops: only one display is connected")
      return
    }
    guard let original = bounds(id) else { throw EffectError.unavailable("second-display desktops: no fixture window") }
    defer {
      if owner.shaded[id] != nil { _ = owner.unshade(id) }
      setAXPosition(element, original.origin)
      _ = setAXSize(element, original.size)
    }
    let desktops = gapDesktops(on: display)
    guard desktops.count >= 2 else {
      print("INFO second-display desktops: \(desktops.isEmpty ? "desktops could not be read" : "only one desktop on \(other.localizedName)"); skipped (add a desktop on that display in Mission Control to run it)")
      return
    }
    let mover = PrivateSLSWindowMover.shared
    // AX 坐标原点在主屏左上角、y 向下；Cocoa 原点在主屏左下角、y 向上。
    let mainHeight = main?.frame.height ?? 0
    let target = CGPoint(x: other.visibleFrame.minX + 80, y: mainHeight - other.visibleFrame.maxY + 80)
    setAXPosition(element, target)
    let reachedSecond = (try? await wait("window on the other display", timeout: 4) {
      guard let frame = self.bounds(self.id) else { return false }
      let cocoa = CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
      return other.frame.intersects(cocoa) && !(main?.frame.intersects(cocoa) ?? false)
    }) != nil
    guard reachedSecond else {
      print("FAIL second-display desktops: the fixture window could not be moved to \(other.localizedName) (now \(bounds(id).map { "\($0)" } ?? "-"))")
      return
    }
    try await Task.sleep(for: .milliseconds(400), clock: .suspending)
    // 挪到副屏后停下来的外框：展开时要回到这里，而不是回到被台前调度挪过的那条卷帘条。
    let placed = bounds(id)
    // 让临时 App 自己把它挪到这块屏的另一张桌面（它自己的窗口才能这样挪）。
    DistributedNotificationCenter.default().post(
      name: Notification.Name("com.windowshade.fixture.to-other-desktop"), object: nil)
    let movedAway = (try? await wait("window on another desktop of that display", timeout: 8) {
      guard let home = mover.windowSpace(id: self.id),
            let active = mover.currentSpace(displayID: display) else { return false }
      return home != active
    }) != nil
    let here = mover.currentSpace(displayID: display)
    let home = mover.windowSpace(id: id)
    guard movedAway, let home, let here, home != here else {
      print("FAIL second-display desktops: the fixture window could not be moved to another desktop of \(other.localizedName) (window desktop \(home.map(String.init) ?? "-"), you are on \(here.map(String.init) ?? "-"), on-screen \(windowIsOnScreenNow(id)))")
      return
    }
    let stillOnSecond = mover.windowSpace(id: id) != nil && desktops.contains(home)
    print("INFO second-display desktops: window desktop \(home) on \(other.localizedName) (that display has \(desktops.count) desktops), you are on \(here), placed frame \(placed.map { "\($0)" } ?? "-")")
    print("\(stillOnSecond ? "PASS" : "FAIL") second-display desktops: the window is on another desktop of the second display, not carried back to the main one")
    func desktopsKept() -> Bool { mover.currentSpace(displayID: display) == here }
    /// 这张桌面上真的亮着它的卷帘条吗：卷帘条排在别的桌面时 CG 仍报 onscreen=true，
    /// 所以看「贴在这张桌面」+「已经亮出来」，而不是窗口服务器那句 onscreen。
    func stripHere() -> Bool {
      guard let state = owner.shaded[id], let overlay = state.overlay, overlay.isVisible else { return false }
      return overlay.alphaValue > 0.5 && overlay.isOnActiveSpace
    }

    // 1. 收起：这张桌面上不该多出卷帘条，副屏的桌面也不该被带走。
    owner.statusItem?.button?.toolTip = nil
    owner.shade(element, id)
    let folded = (try? await wait("folded", timeout: 8) { self.owner.shaded[self.id] != nil }) != nil
    guard folded else {
      print("FAIL second-display desktops: a window living on another desktop of the second display could not be folded (\(owner.currentOperationState(id).rawValue))")
      return
    }
    try await Task.sleep(for: .milliseconds(400), clock: .suspending)
    print("\(!stripHere() ? "PASS" : "FAIL") second-display desktops: folding it leaves no roll-up strip on this desktop")
    if let state = owner.shaded[id], let overlay = state.overlay {
      print("INFO second-display desktops: strip frame \(overlay.frame) (placed \(placed.map { "\($0)" } ?? "-")), recorded display \(state.sourceDisplayID.map(String.init) ?? "-") target \(display), recorded desktop \(state.sourceSpaceID.map(String.init) ?? "-")")
    }
    print("\(desktopsKept() ? "PASS" : "FAIL") second-display desktops: folding it did not change your desktop on that display (now \(mover.currentSpace(displayID: display) ?? 0), was \(here))")

    // 2. 你在当前桌面上看不到任何卷帘条，所以要说一句它去了哪（桌面编号和调度中心一致）。
    // 隐藏还没当场验证时，这句话要等验证通过才说；菜单栏标题 1.4 秒后会清掉，所以等到它出现就读。
    func spokenNotice() -> String {
      let tip = self.owner.statusItem?.button?.toolTip ?? ""
      return tip == "WindowShade" ? "" : tip
    }
    _ = (try? await wait("it says where the window went", timeout: 3) { !spokenNotice().isEmpty })
    let spoken = spokenNotice()
    if case .desktop(let number)? = ElsewhereWindows.place(of: home, desktops: mover.desktopRows()) {
      let expected = WSL10n.text("notice.shade.foldedOnDesktop", zh: "已收起到桌面 %@", String(number))
      print("\(spoken == expected ? "PASS" : "FAIL") second-display desktops: it says where the window went, in Mission Control's own numbering (\(spoken.isEmpty ? "nothing was said" : spoken), want \(expected))")
    } else {
      // 全屏桌面不编号（调度中心里写的是 App 名字），读不到桌面次序时也只要求说了点什么。
      print(spoken.isEmpty
        ? "FAIL second-display desktops: it says nothing about where the window went"
        : "PASS second-display desktops: it says where the window went (\(spoken)); that desktop is not numbered, so only the sentence was checked")
    }

    // 3. 兜底回切只在收起后 0.8 秒内工作：这段时间过去，桌面仍然不动。
    try await Task.sleep(for: .milliseconds(900), clock: .suspending)
    print("\(desktopsKept() ? "PASS" : "FAIL") second-display desktops: the space-return guard did not pull you to the other desktop within its 0.8 s window (now \(mover.currentSpace(displayID: display) ?? 0), was \(here))")

    // 4. 展开：窗口回到副屏上挪过去时的那一处、恢复记录清掉；台前调度挪过卷帘条也不能把它带偏。
    let before = mover.currentSpace(displayID: display)
    _ = owner.unshade(id)
    let restored = (try? await wait("restored", timeout: 8) {
      self.owner.shaded[self.id] == nil && self.gapRecoveryRecords(mentioning: self.id).isEmpty
    }) != nil
    // 台前调度下解最小化 / 解隐藏要先从侧条卡片长回原尺寸：窗口服务器一露头就报 onscreen，
    // 但这时外框还是卡片大小（实测 94×97）。等它长回去再量。
    if let placed {
      let settled = (try? await wait("window grown back to its placed frame", timeout: 6) {
        self.bounds(self.id).map { self.closeTo($0, placed) } == true
      }) != nil
      print("INFO second-display desktops: frame settled=\(settled) now \(bounds(id).map { "\($0)" } ?? "-") want \(placed)")
    }
    let back = bounds(id)
    let cocoaBack = back.map { CGRect(x: $0.minX, y: mainHeight - $0.maxY, width: $0.width, height: $0.height) }
    let grownBack = placed.map { want in back.map { closeTo($0, want) } == true } ?? true
    print("\(cocoaBack.map { other.frame.intersects($0) && grownBack } == true ? "PASS" : "FAIL") second-display desktops: it comes back on the second display at the size and place it was folded, not at the nudged strip (now \(back.map { "\($0)" } ?? "-"), want \(placed.map { "\($0)" } ?? "-"))")
    let now = mover.currentSpace(displayID: display)
    let windowSpace = mover.windowSpace(id: id)
    print("INFO second-display desktops: after unfolding your desktop on that display is \(now ?? 0) (was \(before ?? 0)), window desktop \(windowSpace.map(String.init) ?? "-") (folded on \(home)), on-screen here \(windowIsOnScreenNow(id)), minimized \(axObservedBoolAttribute(element, kAXMinimizedAttribute as String).map(String.init) ?? "-")")
    let backOnItsDesktop = now == before && windowSpace == home
    let pulledYouThere = now != before && windowSpace == now
    print("\(restored && (backOnItsDesktop || pulledYouThere) ? "PASS" : "FAIL") second-display desktops: the recovery record is gone, and the window is either still on its own desktop (you stayed on \(before ?? 0)) or the system took you there")
    _ = pid
  }
}
