// 缩略图的真机探针（--thumbnail）。只动临时 App（tests/fixtures/GlanceFixture.swift）那扇 640 宽的“参考”窗
// （GlanceProbe 的 id）。GlanceProbe 启动临时 App 时带不带 --single 都能跑：两扇窗时收起走移到屏幕外，
// 看一眼给实时画面；--single 时走整体隐藏，按隐藏方式判断该不该有实时画面。
//
// 1. 用设置的入口（setAppearanceMode）把“收起后的样子”换成缩略图；结束时换回原来的选项（连存下来的设置一起）。
// 2. 收起：原处出现缩略图，左上角对着窗口的左上角、大小照 ThumbnailLayout、带着收起那一刻的截图；
//    平时不开流（等一秒再看一次）。标题变了时缩略图右上角亮点，刘海不开口。
// 3. 指针停上去（模拟指针，不动真指针）：看一眼的卡片从缩略图长回原大小、左上角不动；能拿实时画面的
//    接上实时画面且一直在更新；只有截图的，卡片长大途中不露“收起时的画面”，铺开后露出来；前台 App 不变。
// 4. 移开，卡片缩回途中指针又回来：卡片停在全开、原大小，提示照旧；再移开：卡片收回，流停，窗口还收着。
// 5. 单击缩略图：截图飞回原处，窗口在原处展开。
// 6. 再收起，⌃⌘0（arrangeShadedWindows）排到屏幕下边一排，直接单击排好的缩略图：窗口回整理前的原位展开。
// 7. 再收起、整理，指针停到排好的缩略图上，单击卡片（glance.expand）：窗口同样回原位展开。
// 8. 再收起、整理，再按一次放回原位（离屏幕边不到 8 点时会夹进来一点），最后展开：窗口在缩略图那里展开。

import Cocoa

extension GlanceProbe {
  func exerciseThumbnail(pid: pid_t) async throws {
    let glance = owner.glance
    guard let element = appWindows(pid: pid).first(where: { windowID(of: $0) == id }),
          let original = bounds(id) else {
      throw EffectError.unavailable("thumbnail: no fixture window")
    }
    let defaults = UserDefaults.standard
    let savedSetting = defaults.object(forKey: shadeAppearanceModeDefaultsKey)
    let savedMode = owner.appearanceMode
    defer {
      if let savedSetting {
        defaults.set(savedSetting, forKey: shadeAppearanceModeDefaultsKey)
      } else {
        defaults.removeObject(forKey: shadeAppearanceModeDefaultsKey)
      }
      owner.appearanceMode = savedMode
    }
    owner.setAppearanceMode(.thumbnail)
    guard owner.appearanceMode == .thumbnail,
          defaults.string(forKey: shadeAppearanceModeDefaultsKey) == ShadeAppearanceMode.thumbnail.rawValue else {
      throw EffectError.unavailable("thumbnail: the setting did not switch to thumbnails")
    }
    print("PASS thumbnail: the “收起后的样子” setting switched to 缩略图 (restored at the end)")

    let windowFrame = cocoaFrame(fromWindowServerBounds: original)
    func fold() async throws -> (ShadeThumbnailWindow, ShadeThumbnailView) {
      await ShareableContentCache.shared.prefetch()
      owner.shade(element, id)
      try await wait("thumbnail shown", timeout: 6) {
        guard let overlay = self.owner.shaded[self.id]?.overlay as? ShadeThumbnailWindow,
              let view = overlay.contentView as? ShadeThumbnailView else { return false }
        return overlay.isVisible && overlay.alphaValue > 0.9 && !view.hasPendingEntrance && view.restingOpacity > 0.25
      }
      guard let overlay = owner.shaded[id]?.overlay as? ShadeThumbnailWindow,
            let view = overlay.contentView as? ShadeThumbnailView else {
        throw EffectError.unavailable("thumbnail: the window was not put away as a thumbnail")
      }
      return (overlay, view)
    }
    /// ⌃⌘0：排到屏幕下边一排，返回整理前的外框。
    func tidy(_ overlay: ShadeThumbnailWindow) async throws -> NSRect {
      let home = overlay.frame
      guard let screen = screenForCocoaFrame(home) else { throw EffectError.unavailable("thumbnail: no screen") }
      let slot = ThumbnailLayout.tidy([ThumbnailLayout.thumbnail(inOverlayFrame: home).size], in: screen.visibleFrame)[0]
      let tidied = ThumbnailLayout.overlayFrame(thumbnail: slot)
      owner.arrangeShadedWindows()
      try await wait("thumbnails tidied", timeout: 2) { self.closeTo(overlay.frame, tidied) }
      guard owner.hasArrangedOverlayFrames, owner.thumbnailsInUse else {
        throw EffectError.unavailable("thumbnail: tidy did not remember where the thumbnail came from")
      }
      return home
    }
    /// 窗口展开了，而且就在收起前的地方。
    func openedInPlace() -> Bool {
      owner.shaded[id] == nil && onscreen(id) && bounds(id).map { closeTo($0, original) } == true
    }

    // 2. 收起：原处的缩略图。
    let (overlay, view) = try await fold()
    guard let state = owner.shaded[id], state.appearanceMode == .thumbnail else {
      throw EffectError.unavailable("thumbnail: shade state is not a thumbnail")
    }
    let thumbnail = ThumbnailLayout.thumbnail(inOverlayFrame: overlay.frame)
    let expected = ThumbnailLayout.size(for: original.size)
    guard abs(thumbnail.minX - windowFrame.minX) < 1, abs(thumbnail.maxY - windowFrame.maxY) < 1,
          abs(thumbnail.width - expected.width) < 1, abs(thumbnail.height - expected.height) < 1 else {
      throw EffectError.unavailable("thumbnail: misplaced thumbnail=\(thumbnail) window=\(windowFrame) expected size=\(expected)")
    }
    guard view.hasPicture, state.previewImage != nil else {
      throw EffectError.unavailable("thumbnail: no picture from the moment it was put away")
    }
    guard !onscreen(id) else { throw EffectError.unavailable("thumbnail: the real window is still on screen") }
    guard !glance.hasSession(id), glance.captureForProbe(id) == nil else {
      throw EffectError.unavailable("thumbnail: a stream started right after putting it away")
    }
    try await Task.sleep(nanoseconds: 1_000_000_000)
    guard !glance.hasSession(id), glance.captureForProbe(id) == nil else {
      throw EffectError.unavailable("thumbnail: a stream runs while nobody is looking")
    }
    print(String(format: "PASS thumbnail: put away in place as a %.0fx%.0f thumbnail (top-left kept, picture from that moment, no stream while idle; hide=%@)",
                 thumbnail.width, thumbnail.height, state.hide.rawValue))

    // 2b. 收起后标题变了：缩略图右上角亮点，刘海不开口；看过（清掉）后熄。
    // 刚收起的 2 秒里变化按设计不算（ChangeAlertPolicy.quietAfterBaseline），所以重试到过了安静期：
    // 每次换一个标题，因为被忽略的那一次也会把基准标题更新掉。
    if NotchController.isEnabled, NotchController.alertsEnabled {
      let notch = owner.notch
      notch.syncWatchersForProbe()
      var dotted = false
      let deadline = CACurrentMediaTime() + 4
      while CACurrentMediaTime() < deadline {
        notch.simulateTitleChange(id, title: "缩略图探针 · 标题变了 \(Int(CACurrentMediaTime() * 1000))")
        try await Task.sleep(nanoseconds: 400_000_000)
        if view.showsChange { dotted = true; break }
      }
      let quiet = !notch.isAlerting
      notch.clearChange(id)
      view.showsChange = false
      print("\(dotted && quiet ? "PASS" : "FAIL") thumbnail: a new title lights the dot on the thumbnail and the notch stays quiet (dot=\(dotted) notch quiet=\(quiet))")
    } else {
      print("INFO thumbnail: the notch or its change alerts are off in settings; dot check skipped")
    }

    // 3. 指针停上去：卡片从缩略图长回原大小。
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
    let viaUnhide = state.hide == .hidden && GlanceController.unhideForLiveEnabled
    let liveExpected = state.hide == .offscreen || state.hide == .privateOffscreen || viaUnhide
    let onThumbnail = NSPoint(x: thumbnail.midX, y: thumbnail.midY)
    pointer = onThumbnail
    let entered = CACurrentMediaTime()
    glance.pointerEntered(id)
    try await wait("glance over the thumbnail", timeout: 2) { glance.isShown(self.id) }
    let shownMs = (CACurrentMediaTime() - entered) * 1000
    guard shownMs >= 180 else {
      throw EffectError.unavailable(String(format: "thumbnail: glance opened after only %.0fms (dwell is 0.22s)", shownMs))
    }
    // 卡片刚开始长大：提示还不该出来（它不跟着缩放）。
    let noticeWhileGrowing = glance.showsStaleNoticeForProbe(id)
    guard let card = glance.cardFrame(for: id) else { throw EffectError.unavailable("thumbnail: no card") }
    func cardAtFullSize(_ card: NSRect) -> Bool {
      abs(card.minX - thumbnail.minX) < 1 && abs(card.maxY - thumbnail.maxY) < 1
        && abs(card.width - original.width) < 1 && abs(card.height - original.height) < 1
    }
    guard cardAtFullSize(card) else {
      throw EffectError.unavailable("thumbnail: card should grow back to the window's size in place: card=\(card) thumbnail=\(thumbnail) window=\(original.size)")
    }
    var capture: WindowStreamCapture?
    if liveExpected {
      try await wait("live frame", timeout: 2.5) { glance.isLive(self.id) }
      capture = glance.captureForProbe(id)
      let before = glance.pixelFrames(id)
      try await Task.sleep(nanoseconds: 1_000_000_000)
      let perSecond = glance.pixelFrames(id) - before
      guard perSecond >= 8, capture?.isRunning == true else {
        throw EffectError.unavailable("thumbnail: glance picture is not live (\(perSecond) frames/s)")
      }
      print(String(format: "PASS thumbnail: resting on it grows the glance card back to %.0fx%.0f in place after %.0fms, live picture (%d frames in 1s)",
                   card.width, card.height, shownMs, Int(perSecond)))
    } else {
      try await Task.sleep(nanoseconds: 700_000_000)
      guard glance.diagnostics.lastShowedStaleNotice, glance.showsStaleNoticeForProbe(id) else {
        throw EffectError.unavailable("thumbnail: snapshot shown without saying so")
      }
      guard Motion.reduced || !noticeWhileGrowing else {
        throw EffectError.unavailable("thumbnail: “收起时的画面” showed while the card was still growing")
      }
      print(String(format: "PASS thumbnail: resting on it grows the glance card back in place after %.0fms (snapshot, labelled once grown; hide=%@)",
                   shownMs, state.hide.rawValue))
    }
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == front else {
      throw EffectError.unavailable("thumbnail: glance changed the frontmost app")
    }

    // 4. 移开，缩回途中又回来：停在全开；再移开：收回、流停。
    pointer = NSPoint(x: -9000, y: -9000)
    var caughtClosing = true
    do {
      try await wait("card shrinking", timeout: 1.5) { glance.isClosingForProbe(self.id) }
    } catch {
      caughtClosing = false
    }
    pointer = onThumbnail
    glance.pointerEntered(id)
    try await wait("glance back while shrinking", timeout: 2) { glance.isShown(self.id) }
    try await Task.sleep(nanoseconds: 600_000_000)
    guard glance.isShown(id), let back = glance.cardFrame(for: id), cardAtFullSize(back) else {
      throw EffectError.unavailable("thumbnail: coming back while it shrank did not leave the card open at full size")
    }
    if !liveExpected, !glance.showsStaleNoticeForProbe(id) {
      throw EffectError.unavailable("thumbnail: coming back while it shrank lost “收起时的画面”")
    }
    print(caughtClosing
          ? "PASS thumbnail: coming back while the card shrinks keeps it open at full size\(liveExpected ? "" : " (still labelled)")"
          : "INFO thumbnail: the card closed before the pointer came back; reopened at full size instead")
    capture = glance.captureForProbe(id) ?? capture
    pointer = NSPoint(x: -9000, y: -9000)
    let left = CACurrentMediaTime()
    try await wait("glance closed", timeout: 2) { !glance.hasSession(self.id) }
    if let capture, capture.isRunning {
      throw EffectError.unavailable("thumbnail: the stream kept running after the pointer left")
    }
    guard owner.shaded[id] != nil, !onscreen(id) else {
      throw EffectError.unavailable("thumbnail: leaving the glance did not keep the window put away")
    }
    print(String(format: "PASS thumbnail: leaving closes the card after %.0fms and stops the stream; still put away",
                 (CACurrentMediaTime() - left) * 1000))

    // 5. 单击：原地展开。
    try await Task.sleep(nanoseconds: 300_000_000)
    let clicked = CACurrentMediaTime()
    view.onClick?()
    try await wait("unrolled in place", timeout: 3) { openedInPlace() }
    print(String(format: "PASS thumbnail: a click opens the window in place in %.0fms", (CACurrentMediaTime() - clicked) * 1000))

    // 6. 整理后直接单击排好的缩略图：回整理前的原位展开。
    try await Task.sleep(nanoseconds: 700_000_000)
    let (tidiedOverlay, tidiedView) = try await fold()
    _ = try await tidy(tidiedOverlay)
    print("PASS thumbnail: ⌃⌘0 lines the thumbnail up along the bottom of the screen (menu says 恢复缩略图原位)")
    tidiedView.onClick?()
    try await wait("tidied thumbnail opens in place", timeout: 3) { openedInPlace() }
    guard !owner.hasArrangedOverlayFrames else {
      throw EffectError.unavailable("thumbnail: opening a tidied thumbnail left a remembered tidy position")
    }
    print("PASS thumbnail: clicking a tidied thumbnail opens the window where it was, not along the bottom")

    // 7. 整理后停到缩略图上，单击卡片：同样回原位展开。
    try await Task.sleep(nanoseconds: 700_000_000)
    let (peekOverlay, _) = try await fold()
    let peekHome = try await tidy(peekOverlay)
    let homeThumbnail = ThumbnailLayout.thumbnail(inOverlayFrame: peekHome)
    let tidiedThumbnail = ThumbnailLayout.thumbnail(inOverlayFrame: peekOverlay.frame)
    // 刚收起的 0.7 秒里不开看一眼（hoverPreviewSuppressedUntil）：等过去再停上去。
    try await Task.sleep(nanoseconds: 400_000_000)
    pointer = NSPoint(x: tidiedThumbnail.midX, y: tidiedThumbnail.midY)
    glance.pointerEntered(id)
    try await wait("glance over the tidied thumbnail", timeout: 2) { glance.isShown(self.id) }
    guard let homeCard = glance.cardFrame(for: id),
          abs(homeCard.minX - homeThumbnail.minX) < 1, abs(homeCard.maxY - homeThumbnail.maxY) < 1 else {
      throw EffectError.unavailable("thumbnail: after tidying, the card should open where the window was: card=\(String(describing: glance.cardFrame(for: id))) home=\(homeThumbnail)")
    }
    glance.expand(id)
    try await wait("card opens the window in place", timeout: 3) { openedInPlace() }
    pointer = NSPoint(x: -9000, y: -9000)
    try await wait("glance gone after opening", timeout: 2) { !glance.hasSession(self.id) }
    print("PASS thumbnail: after tidying, clicking the glance card opens the window where it was")

    // 8. 整理、放回原位，再展开：在缩略图那里展开。
    try await Task.sleep(nanoseconds: 700_000_000)
    let (again, _) = try await fold()
    let home = try await tidy(again)
    // 放回时按屏幕可用区域夹进 8 点（restoreArrangedOverlayFrames），贴着边收起的会往里挪一点。
    let putBack = owner.clampedFrame(home, margin: 8, preferredDisplayID: owner.shaded[id]?.sourceDisplayID)
    owner.arrangeShadedWindows()
    try await wait("thumbnails back", timeout: 2) { self.closeTo(again.frame, putBack) }
    guard !owner.hasArrangedOverlayFrames else {
      throw EffectError.unavailable("thumbnail: putting back left a remembered tidy position")
    }
    print("PASS thumbnail: ⌃⌘0 again puts it back where it was")
    let restingAt = again.frame
    owner.unshade(id)
    try await wait("opened at the end", timeout: 3) {
      guard self.owner.shaded[self.id] == nil, self.onscreen(self.id), let b = self.bounds(self.id) else { return false }
      let opened = cocoaFrame(fromWindowServerBounds: b)
      return abs(opened.minX - restingAt.minX) < 2 && abs(opened.maxY - restingAt.maxY) < 2
        && abs(opened.width - original.width) < 2 && abs(opened.height - original.height) < 2
    }
    print("PASS thumbnail: opens where the thumbnail sits after being put back")
  }
}
