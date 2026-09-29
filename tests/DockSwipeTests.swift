// Dock 图标上的两指上下滑：认不认、往哪边，以及“指针在不在 Dock 那一带”。纯逻辑，不碰 Dock、不碰窗口。
import CoreGraphics
import Foundation

@main
struct DockSwipeTests {
  static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  /// 按 8ms 一帧喂同样的位移，返回松手时的结论。
  static func swipe(up: CGFloat = 0, right: CGFloat = 0, steps: Int, frame: TimeInterval = 0.008,
                    then more: [(up: CGFloat, right: CGFloat, steps: Int)] = []) -> DockSwipeDirection? {
    var track = DockSwipeTrack(startedAt: 100)
    var t: TimeInterval = 100
    for (u, r, n) in [(up, right, steps)] + more {
      for _ in 0..<n {
        t += frame
        track.add(fingerUp: u, fingerRight: r)
      }
    }
    return track.verdict(endedAt: t)
  }

  static func main() {
    expect(swipe(up: 8, steps: 10) == .up, "a clean 80-point swipe up is up")
    expect(swipe(up: -8, steps: 10) == .down, "a clean 80-point swipe down is down")
    expect(swipe(up: 5, steps: 10) == nil, "50 points is not enough (the title bar needs 56 too)")
    expect(swipe(up: 7, steps: 8) == .up, "exactly 56 points is enough")
    expect(swipe(up: 6, right: 4, steps: 12) == nil, "a diagonal (72 up, 48 across) is not a vertical swipe")
    expect(swipe(up: 8, right: 3, steps: 12) == .up, "a little sideways drift (96 up, 36 across) still counts")
    expect(swipe(right: 8, steps: 20) == nil, "a sideways swipe along the Dock is not ours")
    expect(swipe(up: 10, steps: 12, then: [(up: -10, right: 0, steps: 5)]) == nil,
           "up 120 then back 50: most of the way was undone, so it is not a swipe")
    expect(swipe(up: 10, steps: 10, then: [(up: -2, right: 0, steps: 3)]) == .up,
           "a small wobble back at the end (100 up, 6 back) is still up")
    expect(swipe(up: 1, steps: 200) == nil, "a slow 1.6-second creep is scrolling, not a swipe")
    expect(swipe(up: 4, steps: 20, frame: 0.07) == .up, "a deliberate 1.4-second swipe still counts")

    // 指针在不在 Dock 可能出现的那一带（Cocoa 坐标，左下原点）。
    let main = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let side = CGRect(x: 1728, y: 200, width: 1920, height: 1080)
    expect(DockSwipeTrack.nearDockEdge(CGPoint(x: 860, y: 30), screen: main), "just above the bottom edge is near the Dock")
    expect(DockSwipeTrack.nearDockEdge(CGPoint(x: 860, y: 170), screen: main), "a magnified icon 170 points up still counts")
    expect(!DockSwipeTrack.nearDockEdge(CGPoint(x: 860, y: 600), screen: main), "the middle of the screen is not")
    expect(DockSwipeTrack.nearDockEdge(CGPoint(x: 20, y: 600), screen: main), "the left edge is (Dock on the left)")
    expect(DockSwipeTrack.nearDockEdge(CGPoint(x: 1710, y: 600), screen: main), "the right edge is (Dock on the right)")
    expect(!DockSwipeTrack.nearDockEdge(CGPoint(x: 860, y: 1100), screen: main), "the top edge is not: the Dock never sits there")
    expect(!DockSwipeTrack.nearDockEdge(CGPoint(x: 2500, y: 230), screen: main), "a point on another screen is not this screen's")
    expect(DockSwipeTrack.nearDockEdge(CGPoint(x: 2500, y: 230), screen: side), "but it is near the bottom of that screen")

    if failures == 0 { print("PASS: Dock swipe — up/down verdicts, travel, straightness, duration, Dock edge band") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
