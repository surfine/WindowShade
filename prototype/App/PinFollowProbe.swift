import Cocoa

/// 置顶跟随（tests/run-glance-probe.sh --pin-follow）：c6040509 把置顶的 0.2 s watchdog 换成 WindowStateHub 订阅之后，
/// 用 AX 挪源窗口量面板跟上的时间、关掉源窗口量置顶消失的时间，和旧的 0.2 s 轮询（加两拍稳定判定最坏约 0.4 s）对照。
extension GlanceProbe {
  func exercisePinFollow(element: AXUIElement, original: CGRect, pid: pid_t) async throws {
    let pins = owner.pinnedPreviewController
    let wid = id
    NSRunningApplication(processIdentifier: pid)?.activate()
    pins.startPreview(targetWindowID: wid, pid: pid, axWindow: element) { _ in }
    try await wait("pinned", timeout: 8) { pins.isRunning(id: wid) && pins.panelVisibleForProbe(id: wid) }
    try await Task.sleep(for: .milliseconds(1200), clock: .suspending)
    guard let start = pins.panelFrameForProbe(id: wid) else { throw EffectError.unavailable("pinned panel has no frame") }

    // 每 5 ms 看一次，直到条件成立或超时；返回用时（秒），超时返回 nil。
    func timeUntil(_ limit: Double, _ done: () -> Bool) async -> Double? {
      let t0 = CACurrentMediaTime()
      while CACurrentMediaTime() - t0 < limit {
        if done() { return CACurrentMediaTime() - t0 }
        try? await Task.sleep(for: .milliseconds(5), clock: .suspending)
      }
      return nil
    }

    var follow: [Double] = []
    for round in 0..<6 {
      let shift: CGFloat = round % 2 == 0 ? 120 : 0
      setAXPosition(element, CGPoint(x: original.minX + shift, y: original.minY))
      let target = start.minX + shift
      let followed = await timeUntil(3, { pins.panelFrameForProbe(id: wid).map { abs($0.minX - target) < 2 } == true })
      if let t = followed {
        follow.append(t)
      } else {
        print("FAIL pin-follow: panel did not follow move \(round) within 3 s")
      }
      try await Task.sleep(for: .milliseconds(700), clock: .suspending)
    }
    let ms = follow.map { Int(($0 * 1000).rounded()) }
    let worst = follow.max() ?? .infinity
    print("\(follow.count == 6 && worst <= 0.4 ? "PASS" : "FAIL") pin-follow: panel follows an AX move in \(ms) ms (worst \(Int((worst * 1000).rounded())) ms; old watchdog 200 ms poll + two-tick stability ≈ 200–400 ms)")

    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &ref) == .success, let button = ref else {
      throw EffectError.unavailable("fixture window has no close button")
    }
    AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
    let goneAt = await timeUntil(3, { !onscreen(wid) })
    let stoppedAt = await timeUntil(3, { !pins.isRunning(id: wid) })
    if let stoppedAt, let goneAt {
      // stoppedAt 从 goneAt 之后才开始计：它就是“窗口离屏 → 置顶结束”的延迟。
      print("\(stoppedAt <= 0.25 ? "PASS" : "FAIL") pin-follow: closing the source ends the pin \(Int((stoppedAt * 1000).rounded())) ms after the window left the screen (window left \(Int((goneAt * 1000).rounded())) ms after the close press; old watchdog ≤ 200 ms)")
    } else {
      print("FAIL pin-follow: closing the source did not end the pin within 3 s (window gone=\(goneAt != nil))")
    }
    pins.stopAllPreviews(reason: "pin-follow done")
  }
}
