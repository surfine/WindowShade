import Cocoa

// 多桌面摺叠的真机探针（--fold-desktops）：
// 临时 App 自己把窗口挪到另一张桌面（不切换你的桌面），再走生产收起路径，
// 核对卷帘条不会冒到当前这张桌面上、兜底回切不会把你拽走，展开后窗口回到它自己的桌面、恢复记录清掉。
// 只动临时 App 的窗口，全程不切你的桌面。

extension GlanceProbe {
  func exerciseFoldDesktops(element: AXUIElement, pid: pid_t) async throws {
    NotchController.probeSilence = true
    guard let original = bounds(id),
          let screen = screenForAXWindow(pos: original.origin, size: original.size),
          let display = displayID(for: screen) else {
      throw EffectError.unavailable("fold desktops: no fixture window")
    }
    let desktops = gapDesktops(on: display)
    guard desktops.count >= 2 else {
      print("INFO fold desktops: \(desktops.isEmpty ? "desktops could not be read" : "only one desktop on this screen"); skipped (add a desktop in Mission Control to run it)")
      return
    }
    let mover = PrivateSLSWindowMover.shared
    // 让临时 App 自己把参考窗挪到另一张桌面（自己的窗口才能这样挪），挪的时机由探针定，
    // 不和台前调度激活 App 抢先后。
    DistributedNotificationCenter.default().post(
      name: Notification.Name("com.windowshade.fixture.to-other-desktop"), object: nil)
    let movedAway = (try? await wait("window on another desktop", timeout: 8) {
      guard let home = mover.windowSpace(id: self.id),
            let active = mover.currentSpace(displayID: display) else { return false }
      return home != active
    }) != nil
    let here = mover.currentSpace(displayID: display)
    let home = mover.windowSpace(id: id)
    guard movedAway, let home, let here, home != here else {
      print("FAIL fold desktops: the fixture window could not be moved to another desktop (window desktop \(home.map(String.init) ?? "-"), you are on \(here.map(String.init) ?? "-"), on-screen \(windowIsOnScreenNow(id)))")
      return
    }
    print("INFO fold desktops: the window is on desktop \(home), you are on \(here) (\(desktops.count) desktops)")
    func desktopsKept() -> Bool { mover.currentSpace(displayID: display) == here }
    /// 这张桌面上真的亮着它的卷帘条吗：卷帘条排在别的桌面时 CG 仍报 onscreen=true，
    /// 所以看「贴在这张桌面」+「已经亮出来」，而不是窗口服务器那句 onscreen。
    func stripHere() -> Bool {
      guard let state = owner.shaded[id], let overlay = state.overlay, overlay.isVisible else { return false }
      return overlay.alphaValue > 0.5 && overlay.isOnActiveSpace
    }
    defer {
      if owner.shaded[id] != nil { _ = owner.unshade(id) }
    }

    // 1. 收起挂在别的桌面上的窗：这张桌面不该多出卷帘条，你的桌面也不该被带走。
    owner.statusItem?.button?.toolTip = nil
    owner.shade(element, id)
    let folded = (try? await wait("folded", timeout: 8) { self.owner.shaded[self.id] != nil }) != nil
    guard folded else {
      print("FAIL fold desktops: a window living on another desktop could not be folded (\(owner.currentOperationState(id).rawValue))")
      return
    }
    try await Task.sleep(for: .milliseconds(400), clock: .suspending)
    print("\(!stripHere() ? "PASS" : "FAIL") fold desktops: folding a window that lives on another desktop leaves no roll-up strip on this desktop")
    if let state = owner.shaded[id], let overlay = state.overlay {
      let overlayID = state.overlayID
      print("INFO fold desktops: strip id=\(overlayID.map(String.init) ?? "-") space=\(overlayID.flatMap { mover.windowSpace(id: $0) }.map(String.init) ?? "-") visible=\(overlay.isVisible) alpha=\(String(format: "%.2f", overlay.alphaValue)) onActiveSpace=\(overlay.isOnActiveSpace) onscreen=\(overlayID.map { cgWindowIsCurrentlyOnScreen($0) }.map(String.init) ?? "-") frame=\(overlay.frame) | source space=\(state.sourceSpaceID.map(String.init) ?? "-") display=\(state.sourceDisplayID.map(String.init) ?? "-") active now=\(mover.currentSpace(displayID: display).map(String.init) ?? "-") window space=\(mover.windowSpace(id: id).map(String.init) ?? "-") window onscreen=\(windowIsOnScreenNow(id))")
    }
    let rightAfter = mover.currentSpace(displayID: display)
    print("\(desktopsKept() ? "PASS" : "FAIL") fold desktops: folding it did not change your desktop (now \(rightAfter ?? 0), was \(here))")
    let foldedHide = owner.shaded[id]?.hide.rawValue ?? "-"
    let foldedSpace = owner.shaded[id]?.sourceSpaceID
    print("INFO fold desktops: hide=\(foldedHide) recorded source desktop=\(foldedSpace.map(String.init) ?? "-") window desktop=\(home)")
    // 这张桌面上看不到卷帘条，所以要说一句它去了哪。隐藏验证是异步的，菜单栏标题 1.4 秒后会清掉。
    func spokenNotice() -> String {
      let tip = self.owner.statusItem?.button?.toolTip ?? ""
      return tip == "WindowShade" ? "" : tip
    }
    _ = (try? await wait("it says where the window went", timeout: 3) { !spokenNotice().isEmpty })
    let spoken = spokenNotice()
    if case .desktop(let number)? = ElsewhereWindows.place(of: home, desktops: mover.desktopRows()) {
      let expected = WSL10n.text("notice.shade.foldedOnDesktop", zh: "已收起到桌面 %@", String(number))
      print("\(spoken == expected ? "PASS" : "FAIL") fold desktops: it says where the window went (\(spoken.isEmpty ? "nothing was said" : spoken), want \(expected))")
    } else {
      print(spoken.isEmpty
        ? "FAIL fold desktops: it says nothing about where the window went"
        : "PASS fold desktops: it says where the window went (\(spoken))")
    }

    // 2. 兜底回切只在收起后 0.8 秒内工作：这段时间过去，桌面仍然不动。
    try await Task.sleep(for: .milliseconds(900), clock: .suspending)
    let afterGuard = mover.currentSpace(displayID: display)
    print("\(desktopsKept() ? "PASS" : "FAIL") fold desktops: the space-return guard did not pull you to the other desktop within its 0.8 s window (now \(afterGuard ?? 0), was \(here))")

    // 3. 展开：窗口回到原处，恢复记录清掉；它要么还在自己的桌面（你没被带走），要么系统把你带过去并露出来。
    let before = mover.currentSpace(displayID: display)
    _ = owner.unshade(id)
    let restored = (try? await wait("restored", timeout: 8) {
      self.owner.shaded[self.id] == nil && self.gapRecoveryRecords(mentioning: self.id).isEmpty
    }) != nil
    try await Task.sleep(for: .milliseconds(600), clock: .suspending)
    let now = mover.currentSpace(displayID: display)
    let windowSpace = mover.windowSpace(id: id)
    let minimized = axObservedBoolAttribute(element, kAXMinimizedAttribute as String)
    let frameBack = bounds(id).map { self.closeTo($0, original) } == true
    let visibleHere = windowIsOnScreenNow(id)
    let movedYou = now != before
    print("INFO fold desktops: after unfolding desktop is \(now ?? 0) (was \(before ?? 0)), window desktop \(windowSpace.map(String.init) ?? "-"), on-screen here \(visibleHere), minimized \(minimized.map(String.init) ?? "-"), frame \(bounds(id).map { "\($0)" } ?? "-") original \(original), frame back \(frameBack)")
    let backOnItsDesktop = !movedYou && windowSpace == home
    let pulledYouThere = movedYou && windowSpace == now
    print("\(restored && frameBack && (backOnItsDesktop || pulledYouThere) ? "PASS" : "FAIL") fold desktops: unfolding puts the window back at its original frame on the desktop it lives on, either without touching your desktop (it stayed on \(home)) or by taking you there and showing it, and its recovery record is gone")
    _ = pid
  }
}
