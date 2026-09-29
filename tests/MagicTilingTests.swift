// 魔法平铺的规划与晃一晃的识别：纯逻辑，不碰任何窗口。
import CoreGraphics
import Foundation

@main
struct MagicTilingTests {
  static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static func window(_ id: CGWindowID, _ bundle: String, x: CGFloat = 100, y: CGFloat = 100,
                     w: CGFloat = 900, h: CGFloat = 700, focused: Bool = false) -> MagicWindow {
    MagicWindow(id: id, pid: pid_t(id), bundleID: bundle, category: nil,
                frame: CGRect(x: x, y: y, width: w, height: h), focused: focused)
  }

  static func main() {
    let area = CGRect(x: 0, y: 25, width: 1728, height: 1080)

    // 浏览器 + 写作：浏览器当主角 6:4，在左；写作在右；聊天放侧拉。
    do {
      let plan = MagicTiling.plan([window(1, "com.apple.Notes", x: 900, focused: true),
                                   window(2, "com.google.Chrome", x: 50),
                                   window(3, "com.tencent.xinWeChat", x: 1200, w: 400)], area: area)
      expect(plan.placements.first?.id == 2, "the browser takes the main part even when notes is in front")
      expect(plan.share == 0.6, "browser and a writing app split 6:4 (got \(plan.share))")
      expect(plan.mainLeading && plan.placements.first?.frame.minX == area.minX, "the browser stays on the left where it was")
      expect(plan.slideOver == 3, "the chat app goes to slide over")
      expect(plan.placements.count == 2 && plan.placements[1].frame.minX == plan.placements[0].frame.maxX,
             "notes fills the rest beside it")
      expect(!plan.vertical, "a landscape screen splits left and right")
    }

    // 两个浏览器：5:5。主角在右边时留在右边。
    do {
      let plan = MagicTiling.plan([window(1, "com.apple.Safari", x: 1000), window(2, "com.google.Chrome", x: 20)],
                                  area: area, preferredMain: 1)
      expect(plan.placements.first?.id == 1, "the window the spread landed on is the main one")
      expect(plan.share == 0.5, "two browsers split 5:5 (got \(plan.share))")
      expect(!plan.mainLeading && plan.placements[0].frame.maxX == area.maxX, "the main window stays on the right")
    }

    // 浏览器 + 访达：7:3。
    do {
      let plan = MagicTiling.plan([window(1, "com.google.Chrome", focused: true), window(2, "com.apple.finder", x: 1000)], area: area)
      expect(plan.share == 0.7, "a browser beside Finder gets 7:3 (got \(plan.share))")
    }

    // 竖着放的屏：上下分。
    do {
      let portrait = CGRect(x: 0, y: 25, width: 1080, height: 1895)
      let plan = MagicTiling.plan([window(1, "com.google.Chrome", y: 60, focused: true), window(2, "com.apple.Notes", y: 1200)],
                                  area: portrait)
      expect(plan.vertical, "a portrait screen splits top and bottom")
      expect(plan.placements[0].frame.minY == portrait.minY && plan.placements[0].frame.width == portrait.width,
             "the main window takes the top part across the full width")
      expect(plan.placements[1].frame.minY == plan.placements[0].frame.maxY, "the other one sits below it")
    }

    // 一扇窗：铺满；太多窗口：旁边一列放得下的放，其余收进刘海（刘海关着就不动）。
    do {
      let alone = MagicTiling.plan([window(1, "com.apple.Notes")], area: area)
      expect(alone.placements == [.init(id: 1, frame: area, role: .reference)], "a lone window just fills")
      let many = (1...7).map { window(CGWindowID($0), "com.apple.TextEdit", y: CGFloat($0) * 40) }
      let plan = MagicTiling.plan(many, area: area)
      expect(plan.placements.count == 4 && plan.tuck.count == 3, "a 1080-point tall screen fits three beside the main one; the rest go to the notch")
      let heights = plan.placements.dropFirst().map(\.frame.height).reduce(0, +)
      expect(abs(heights - area.height) < 0.5, "the side column is filled top to bottom")
      let kept = MagicTiling.plan(many, area: area, canTuck: false)
      expect(kept.tuck.isEmpty, "with the notch off, extra windows are left where they are")
    }

    // 旁边太窄就退一档：小屏幕上 7:3 的那一列不够 420 点。
    expect(MagicTiling.share(main: 3.6, side: 1.3, extent: 1280, minSide: 420) == 0.6,
           "on a 1280-point screen the side column stays at least 420 points wide")

    // 类别兜底：没见过的聊天 App 按类别放侧拉。
    expect(MagicTiling.role(bundleID: "com.example.chat", category: "public.app-category.social-networking") == .chat,
           "an unknown social app counts as chat")
    expect(MagicTiling.role(bundleID: "com.jetbrains.intellij", category: nil) == .wide, "JetBrains IDEs want room")

    // 晃一晃：来回三次以上才算；一直往一边拖不算；慢慢挪不算。
    do {
      var shake: [FlickSample] = []
      var t: TimeInterval = 0
      for leg in 0..<5 {
        for step in 0..<6 {
          let x = CGFloat(leg % 2 == 0 ? step : 6 - step) * 12
          shake.append(FlickSample(time: t, point: CGPoint(x: 400 + x, y: 300)))
          t += 0.016
        }
      }
      expect(WindowShake.detected(in: shake), "a quick left-right shake is recognized")
      let drag = (0..<40).map { FlickSample(time: Double($0) * 0.016, point: CGPoint(x: 400 + CGFloat($0) * 8, y: 300)) }
      expect(!WindowShake.detected(in: drag), "dragging steadily one way is not a shake")
      let slow = shake.map { FlickSample(time: $0.time * 4, point: $0.point) }
      expect(!WindowShake.detected(in: slow), "wobbling slowly over several seconds is not a shake")
    }

    // 卷轴：一列挨一列，屏幕外的停在边上露一条边；松手停在列边上；变宽变窄走 ⅓ ½ ⅔ 整屏；新窗口接在右边不挤别人。
    do {
      let screen = CGRect(x: 0, y: 25, width: 1500, height: 900)
      var strip = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2, 3], width: 750), .init(ids: [4], width: 500)],
                              area: screen)
      expect(strip.maxOffset == 750, "three columns (⅔, ½, ⅓) of a 1500-point screen reach 750 points past it")
      let frames = strip.frames()
      expect(frames[1] == CGRect(x: 0, y: 25, width: 1000, height: 900), "the first column sits at the left edge, full height")
      expect(frames[2]?.minX == 1000 && frames[2]?.height == 450 && frames[3]?.minY == 475, "the second column is half on screen, its two windows stacked")
      expect(frames[4]?.minX == 1500 - ScrollStrip.sliver, "the third column is off screen and parks at the right edge with a sliver showing")
      expect(strip.parked().right == [2] && strip.parked().left.isEmpty, "only the last column is parked")
      expect(strip.snapped(600) == 750, "a throw that would stop at 600 settles where the last column's right edge meets the screen")
      expect(strip.snapped(380) == 250, "one that would stop at 380 settles where the second column's right edge meets the screen (250)")
      expect(strip.revealing(2) == 750 && strip.revealing(0) == 0, "revealing a column scrolls the least that shows all of it")
      expect(strip.steppedWidth(2, wider: true) == 750 && strip.steppedWidth(2, wider: false) == nil,
             "a third-wide column widens to half; it is already the narrowest")
      expect(strip.steppedWidth(0, wider: true) == 1500, "a two-thirds column widens to the full screen")
      strip.insert(9, width: 750, after: 0)
      expect(strip.columns.map(\.ids) == [[1], [9], [2, 3], [4]] && strip.columns[0].width == 1000,
             "a new window gets its own column right after the current one, and nothing else gets narrower")
      expect(strip.offset == 250, "and the strip scrolls just enough to show it")
      strip.remove(2)
      expect(strip.columns[2].ids == [3] && strip.columns[2].shares == [1], "closing one of two stacked windows gives the other the whole column")
      strip.remove(9)
      expect(strip.columns.map(\.ids) == [[1], [3], [4]], "closing the only window of a column removes the column")
      var wide = ScrollStrip(columns: [.init(ids: [1], width: 1500), .init(ids: [2], width: 1500)], area: screen, offset: 1500)
      expect(wide.parked().left == [0] && wide.frames()[1]?.maxX == ScrollStrip.sliver, "a column scrolled past the left edge parks there with a sliver")
      wide.offset = wide.clamped(99999)
      expect(wide.offset == 1500, "scrolling never goes past the last column")
    }

    // 窗口之间留缝：贴屏幕边让一整道，挨着别的窗口让半道，两扇之间合起来正好一道。
    do {
      let screen = CGRect(x: 0, y: 25, width: 1200, height: 800)
      let left = ArrangeGap.apply(CGRect(x: 0, y: 25, width: 600, height: 800), in: screen, gap: 8)
      let right = ArrangeGap.apply(CGRect(x: 600, y: 25, width: 600, height: 800), in: screen, gap: 8)
      expect(left == CGRect(x: 8, y: 33, width: 588, height: 784), "a left half keeps a full gap at the screen edges and half at the middle (\(left))")
      expect(right.minX - left.maxX == 8, "two halves end up exactly one gap apart")
      expect(ArrangeGap.apply(screen, in: screen, gap: 8) == screen.insetBy(dx: 8, dy: 8), "fill keeps a gap all round")
      expect(ArrangeGap.apply(left, in: screen, gap: 0) == left, "no gap leaves frames as they were")
    }

    // Dock 留在一块屏上：只在别的屏的底边、而且下面没有屏接着时才把指针往上推。
    do {
      let builtIn = CGRect(x: 0, y: 0, width: 1710, height: 1107)
      let studio = CGRect(x: -435, y: 1107, width: 2560, height: 1440)
      let screens = [builtIn, studio]
      expect(DockLockRule.shouldNudge(CGPoint(x: -200, y: 1107.5), screens: screens, locked: builtIn),
             "the part of the upper display's bottom edge with nothing below it is an edge: nudge")
      expect(!DockLockRule.shouldNudge(CGPoint(x: 800, y: 1107.5), screens: screens, locked: builtIn),
             "where the built-in display continues below, the pointer just passes through")
      expect(!DockLockRule.shouldNudge(CGPoint(x: 800, y: 0.5), screens: screens, locked: builtIn),
             "the bottom edge of the display the Dock stays on is left alone")
      expect(!DockLockRule.shouldNudge(CGPoint(x: -200, y: 1300), screens: screens, locked: builtIn),
             "away from the edge nothing happens")
    }

    // 在刘海上教手势：三次为限、用过就不教、五分钟一条、点掉就不再出；绕远路到第三下才教。
    do {
      var coach = GestureCoach()
      expect(coach.canShow(.halves, at: 0), "a tip can show the first time")
      coach.didShow(.halves, at: 0)
      expect(!coach.canShow(.magic, at: 100), "another tip waits five minutes")
      expect(coach.canShow(.magic, at: 301), "after five minutes the next tip may show")
      coach.didShow(.halves, at: 400); coach.didShow(.halves, at: 800)
      expect(!coach.canShow(.halves, at: 5000), "a tip shows at most three times")
      coach.used(.magic)
      expect(!coach.canShow(.magic, at: 9000), "once the gesture has been used, it is never taught again")
      coach.dismiss(.shake)
      expect(!coach.canShow(.shake, at: 9000), "a tip clicked away does not come back")
      let data = try? JSONEncoder().encode(coach)
      expect(data.flatMap { try? JSONDecoder().decode(GestureCoach.self, from: $0) } == coach, "the coach remembers across launches")
    }

    if failures == 0 { print("PASS: magic tiling — roles, ratios 5:5/6:4/7:3, main side kept, portrait split, chat to slide over, extras to the notch, narrow side column, shake recognition, scroll strip (parking, snapping, reveal, width ladder, insert without squeezing, removal), gaps, Dock lock edge, gesture coach") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
