// 看一眼怎么挑画面来源（Core/NotchGlancePlan.swift）和格子缩略图的规矩（Core/NotchThumbnailPolicy.swift）。
import CoreGraphics
import Foundation

@main
struct NotchGlanceTests {
  nonisolated(unsafe) static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static let noFacts = NotchGlancePlan.Facts(permission: false, stripOnActiveSpace: false, slideOverHidden: false,
                                             windowOnScreen: false, carriedStripVisible: false,
                                             snapshotAvailable: false)
  /// 什么都占：权限、卷帘条在眼前、停在边上、窗口在屏幕上、卷帘条面板看得见、有存下来的画面。
  static let allFacts = NotchGlancePlan.Facts(permission: true, stripOnActiveSpace: true, slideOverHidden: true,
                                              windowOnScreen: true, carriedStripVisible: true, snapshotAvailable: true)

  static func route(_ kind: NotchGlancePlan.Kind, _ f: NotchGlancePlan.Facts) -> NotchGlancePlan.Route {
    NotchGlancePlan.route(kind, f)
  }

  /// 六件事的全排列：给“最小化 / 藏起来的 App 绝不用那两种”兜底。
  static func everyFacts() -> [NotchGlancePlan.Facts] {
    var result: [NotchGlancePlan.Facts] = []
    for bits in 0..<64 {
      result.append(NotchGlancePlan.Facts(permission: bits & 1 != 0, stripOnActiveSpace: bits & 2 != 0,
                                          slideOverHidden: bits & 4 != 0, windowOnScreen: bits & 8 != 0,
                                          carriedStripVisible: bits & 16 != 0, snapshotAvailable: bits & 32 != 0))
    }
    return result
  }

  static func main() {
    do {  // 逐条规矩
      expect(route(.tucked, noFacts) == .held && route(.tucked, allFacts) == .held,
             "a tucked window keeps the glance it already has, whatever the facts")
      expect(route(.strip, allFacts) == .held, "a strip visible on this desktop uses the glance attached to it")
      expect(route(.strip, noFacts) == .staticPeek, "a strip not on this desktop falls back to the stored peek")
      var strip = noFacts; strip.stripOnActiveSpace = true
      expect(route(.strip, strip) == .held, "the strip only needs to be on the active space for that")
      var parked = noFacts; parked.permission = true; parked.slideOverHidden = true
      expect(route(.slideOver, parked) == .liveFromTile, "a slide-over parked off the edge streams live from the tile")
      parked.slideOverHidden = false; parked.windowOnScreen = true
      expect(route(.slideOver, parked) == .none, "a slide-over sitting visibly on screen shows nothing")
      parked.slideOverHidden = true
      expect(route(.slideOver, parked) == .liveFromTile, "parked wins even when the window is still on screen")
      parked.slideOverHidden = false; parked.windowOnScreen = false
      expect(route(.slideOver, parked) == .liveFromTile, "a slide-over whose window is off screen streams live from the tile")
      var slid = allFacts; slid.permission = false
      expect(route(.slideOver, slid) == .none, "without screen recording the slide-over shows nothing")
      var carried = allFacts; carried.windowOnScreen = false; carried.carriedStripVisible = false
      expect(route(.carried, carried) == .liveFromTile, "a carried window off screen streams live from the tile")
      var carriedHere = allFacts; carriedHere.carriedStripVisible = false
      expect(route(.carried, carriedHere) == .none, "a carried window still on screen shows nothing")
      var carriedStrip = noFacts; carriedStrip.carriedStripVisible = true
      expect(route(.carried, carriedStrip) == .held, "a carried window whose strip panel is visible keeps the held glance")
      expect(route(.elsewhere, noFacts) == .none && route(.elsewhere, allFacts) == .liveFromTile,
             "another desktop streams live from the tile only with permission")
      var still = noFacts; still.permission = true; still.snapshotAvailable = true
      expect(route(.minimized, still) == .stillFromTile && route(.hiddenApp, still) == .stillFromTile,
             "a minimized window or hidden app shows a still from the tile when there is a snapshot")
      var noShot = still; noShot.snapshotAvailable = false
      expect(route(.minimized, noShot) == .none && route(.hiddenApp, noShot) == .none,
             "a minimized window or hidden app shows nothing without a snapshot")
    }

    do {  // 没有权限：除了收起窗口和自己看得见的卷帘条面板，其余都什么都不显示
      for kind in [NotchGlancePlan.Kind.slideOver, .carried, .minimized, .hiddenApp, .elsewhere] {
        // “能给”的前提：窗口不在眼前（带到每张桌面的窗口就在屏上时本来就什么都不给）。
        var f = allFacts; f.carriedStripVisible = false; f.windowOnScreen = false
        expect(route(kind, f) != .none, "\(kind) can show something when the facts allow it")
        f.permission = false
        expect(route(kind, f) == .none, "\(kind) shows nothing without screen recording permission")
      }
      // 扛着的窗口：卷帘条面板看得见就还是用挂着的那一眼，不看权限。
      var f = noFacts; f.carriedStripVisible = true
      expect(route(.carried, f) == .held, "a carried strip panel visible here is held without needing permission")
    }

    do {  // 最小化和藏起来的 App 在六件事的任何组合下都不会走到 held / liveFromTile
      for facts in everyFacts() {
        for kind in [NotchGlancePlan.Kind.minimized, .hiddenApp] {
          let r = route(kind, facts)
          expect(r != .held && r != .liveFromTile, "\(kind) never uses held or liveFromTile (facts \(facts))")
        }
      }
    }

    do {  // 一张画面什么样才收：正在缩小的、形状不对的不要，1x / 2x 的要
      let expected = CGSize(width: 800, height: 600)
      expect(NotchThumbnailPolicy.acceptsPicture(pixelWidth: 240, pixelHeight: 180, expectedPoints: expected) == false,
             "a frame caught at 30% size (mid minimize) is rejected")
      expect(NotchThumbnailPolicy.acceptsPicture(pixelWidth: 800, pixelHeight: 700, expectedPoints: expected) == false,
             "a frame whose shape is off by more than a tenth is rejected")
      expect(NotchThumbnailPolicy.acceptsPicture(pixelWidth: 800, pixelHeight: 600, expectedPoints: expected),
             "a full-size 1x capture is accepted")
      expect(NotchThumbnailPolicy.acceptsPicture(pixelWidth: 1600, pixelHeight: 1200, expectedPoints: expected),
             "a 2x full-size capture is accepted")
      expect(NotchThumbnailPolicy.acceptsPicture(pixelWidth: 720, pixelHeight: 540, expectedPoints: expected),
             "a 0.9x capture is just big enough")
      expect(NotchThumbnailPolicy.acceptsPicture(pixelWidth: 1, pixelHeight: 1, expectedPoints: .zero),
             "with nothing expected there is nothing to check")
      expect(NotchThumbnailPolicy.acceptsPicture(pixelWidth: 880, pixelHeight: 660, expectedPoints: expected),
             "a shape within a tenth passes even when it is a little wider")
    }

    do {  // 整张留还是只留缩略图：拿 16M 像素画的那条线两边各试一下
      expect(NotchThumbnailPolicy.stillQuality(windowPoints: CGSize(width: 1920, height: 1080)) == .full,
             "a 1080p window (8.3M pixels) keeps the full still")
      expect(NotchThumbnailPolicy.stillQuality(windowPoints: CGSize(width: 3840, height: 2160)) == .thumbnail,
             "a 4K window (33M pixels) is only kept as a thumbnail")
      expect(NotchThumbnailPolicy.stillQuality(windowPoints: CGSize(width: 2000, height: 2000)) == .full,
             "exactly one pixel under the line is still full")
      expect(NotchThumbnailPolicy.stillQuality(windowPoints: CGSize(width: 2000, height: 2001)) == .thumbnail,
             "one pixel over the line tips over to a thumbnail")
      expect(NotchThumbnailPolicy.stillQuality(windowPoints: CGSize(width: 4000, height: 1000)) == .full,
             "16M pixels exactly is not over the line")
      expect(NotchThumbnailPolicy.stillQuality(windowPoints: .zero) == .full, "an empty window keeps the full still")
    }

    do {  // 一张画面算不算新鲜：10 秒是那条线
      expect(NotchThumbnailPolicy.isFresh(capturedAt: 0, now: 9.9), "a picture 9.9s old is still fresh")
      expect(NotchThumbnailPolicy.isFresh(capturedAt: 0, now: 10) == false, "a picture exactly 10s old is not fresh")
      expect(NotchThumbnailPolicy.isFresh(capturedAt: 5, now: 5), "a picture taken just now is fresh")
      expect(NotchThumbnailPolicy.ttl == 10 && NotchThumbnailPolicy.maxInFlight == 2 && NotchThumbnailPolicy.tileMaxPixel == 320,
             "the tile picture stays fresh 10s, at most 2 captures at once, shrunk to 320px")
    }

    print(failures == 0 ? "all notch glance tests passed" : "\(failures) failure(s)")
    if failures > 0 { exit(1) }
  }
}
