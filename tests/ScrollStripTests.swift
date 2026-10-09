// 卷轴的看一眼与概览：停在边上的那一条在哪（包括叠在底下、更远的列）、停稳时正好停在屏幕边上的那一列让出它
// （伸过屏幕边的不让，它在上层时屏幕边最外面几点照样算那一条）、滑动中不改大小、卡片放在哪、整条缩小铺开后每列在哪。
// 纯逻辑，不碰任何窗口。
import CoreGraphics
import Foundation

@main
struct ScrollStripTests {
  static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  static func main() {
    let screen = CGRect(x: 0, y: 25, width: 1500, height: 900)

    // 露出来的那一条：只给每一边离屏幕最近的那一列，叠着的几扇各占自己那一段。
    do {
      let strip = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2, 3], width: 750),
                                        .init(ids: [4], width: 500), .init(ids: [5], width: 500)], area: screen)
      let slivers = strip.slivers()
      expect(slivers.map(\.id) == [4], "with two columns parked on the right, only the nearer one offers its sliver (got \(slivers.map(\.id)))")
      expect(slivers.first?.side == .right && slivers.first?.band == CGRect(x: 1490, y: 25, width: 10, height: 900),
             "its sliver is the last 10 points of the screen, full height")
      expect(slivers.first?.window.minX == 1490 && slivers.first?.window.width == 500, "and it knows where the window really is")

      var scrolled = strip
      scrolled.offset = scrolled.maxOffset
      let left = scrolled.slivers()
      expect(left.map(\.id) == [1] && left.first?.side == .left && left.first?.band.minX == 0,
             "scrolled to the end, the first column parks on the left and offers its sliver there")

      let stacked = ScrollStrip(columns: [.init(ids: [1, 2], width: 750), .init(ids: [3], width: 1500), .init(ids: [4], width: 1500)],
                                area: screen, offset: 750)
      let bands = stacked.slivers()
      expect(bands.map(\.id) == [1, 2, 4], "a parked column of two stacked windows offers one sliver per window (got \(bands.map(\.id)))")
      expect(bands[0].band == CGRect(x: 0, y: 25, width: 10, height: 450) && bands[1].band == CGRect(x: 0, y: 475, width: 10, height: 450),
             "each covering its own half of the edge")
      let gapped = stacked.slivers(gap: 8)
      expect(gapped[0].band.minY == 33 && gapped[0].band.height == 438,
             "with gaps between windows the sliver follows the gapped frame (\(gapped[0].band))")
      expect(ScrollStrip(columns: [.init(ids: [1], width: 750), .init(ids: [2], width: 750)], area: screen).slivers().isEmpty,
             "a strip that fits on screen has nothing parked and nothing to peek at")

      // 更远那列恰好在上层时，指针下露着的是它：也能算出它那一条。
      expect(strip.sliver(of: 5) == ScrollStrip.Sliver(id: 5, side: .right, band: CGRect(x: 1490, y: 25, width: 10, height: 900),
                                                        window: CGRect(x: 1490, y: 25, width: 500, height: 900)),
             "the farther column parked under it has its own sliver at the same edge (\(String(describing: strip.sliver(of: 5))))")
      expect(slivers.allSatisfy { strip.sliver(of: $0.id) == $0 }, "the nearer column's sliver is the same either way")
      expect(strip.sliver(of: 1) == nil && strip.sliver(of: 2) == nil && strip.sliver(of: 99) == nil,
             "a window on screen, or not in the strip, has no sliver")
      expect(stacked.sliver(of: 2, gap: 8) == gapped[1] && stacked.sliver(of: 3) == nil,
             "a stacked parked window keeps its own half with gaps, and the window on screen has none")
    }

    // 停稳时正好停在屏幕边上、挨着停靠列的那一列让出那一条：边沿挪到那一条里侧、另一边不动；伸出屏幕的列不收窄。
    do {
      let right = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2], width: 500), .init(ids: [3], width: 500)],
                              area: screen)
      let frames = right.frames()
      let band = right.slivers().first?.band
      expect(frames[2] == CGRect(x: 1000, y: 25, width: 490, height: 900),
             "a column ending at the right edge next to a parked one stops 10 points short of it (\(String(describing: frames[2])))")
      expect(band.map { band in [1, 2].allSatisfy { frames[$0].map { $0.maxX <= band.minX } == true } } == true,
             "so no window on screen reaches into the sliver")
      expect(frames[1] == CGRect(x: 0, y: 25, width: 1000, height: 900) && frames[3]?.minX == 1490,
             "the first column and the parked one stay where they were")
      expect(right.trueFrame(column: 1).width == 500 && right.columns[1].width == 500,
             "the column itself keeps its width; only where it is put at rest changes")

      let gapped = ArrangeGap.apply(frames[2]!, in: screen, gap: 8)
      let parkedGapped = ArrangeGap.apply(frames[3]!, in: screen, gap: 8)
      expect(parkedGapped.minX - gapped.maxX == 8 && band.map { parkedGapped.minX <= $0.midX } == true,
             "with an 8-point gap the parked window and the column beside it keep one gap between them, and the middle of the sliver is on the parked window (\(gapped.maxX)…\(parkedGapped.minX))")

      let left = ScrollStrip(columns: [.init(ids: [1], width: 500), .init(ids: [2], width: 750), .init(ids: [3], width: 750)],
                             area: screen, offset: 500)
      let leftFrames = left.frames()
      expect(left.parked().left == [0] && leftFrames[2] == CGRect(x: 10, y: 25, width: 740, height: 900),
             "on the left the column starting at the edge starts 10 points in, its right edge unchanged (\(String(describing: leftFrames[2])))")
      expect(leftFrames[3] == CGRect(x: 750, y: 25, width: 750, height: 900),
             "the last column, with nothing parked past it, still reaches the right edge")

      let both = ScrollStrip(columns: [.init(ids: [1], width: 500), .init(ids: [2], width: 1500), .init(ids: [3], width: 500)],
                             area: screen, offset: 500)
      expect(both.frames()[2] == CGRect(x: 10, y: 25, width: 1480, height: 900),
             "a full-width column between two parked ones gives up both slivers (\(String(describing: both.frames()[2])))")

      let partial = ScrollStrip(columns: [.init(ids: [1], width: 500), .init(ids: [2], width: 500), .init(ids: [3], width: 1000),
                                          .init(ids: [4], width: 500)], area: screen, offset: 750)
      let partialFrames = partial.frames()
      expect(partial.parked().left == [0] && partialFrames[2] == CGRect(x: -250, y: 25, width: 500, height: 900),
             "a column already reaching past the edge keeps its width; the column parked there lies under it")
      expect(partial.overhanging(.left) == 1 && partial.overhanging(.right) == nil, "and it is the one reported as running past that edge")
      expect(ScrollStrip(columns: [.init(ids: [1], width: 750), .init(ids: [2], width: 750)], area: screen).frames()[2]
               == CGRect(x: 750, y: 25, width: 750, height: 900),
             "with nothing parked, columns reach the screen edges as before")
    }

    // 列宽不一样（刚排好的 ⅔ ½ ⅓）：第二列伸过屏幕右边。它不收窄（要让出 10 点得压窄 260 点），停靠列那一条叠在它底下，
    // 谁在上层露谁：那一条照样给出来，指针停上去时看一眼再看上层是谁（停着的那扇在上层就开，伸过来的那列在上层就不开）。
    do {
      let mixed = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2], width: 750), .init(ids: [3], width: 500)],
                              area: screen)
      expect(mixed.overhanging(.right) == 1 && mixed.overhanging(.left) == nil,
             "with ⅔, ½ and ⅓ columns at the start, the ½ column runs past the right edge over the parked ⅓ one")
      expect(mixed.frames()[2] == CGRect(x: 1000, y: 25, width: 750, height: 900), "it keeps its full width")
      expect(mixed.slivers().map(\.id) == [3] && mixed.slivers().first?.band == CGRect(x: 1490, y: 25, width: 10, height: 900),
             "the parked column still offers its sliver; what is on top there is checked when the pointer stops")
      var flushRight = mixed
      flushRight.offset = mixed.snapped(250)
      expect(flushRight.offset == 250 && flushRight.overhanging(.right) == nil
               && flushRight.frames()[2] == CGRect(x: 750, y: 25, width: 740, height: 900),
             "once the ½ column rests with its right edge on the screen edge, it gives the sliver up (\(String(describing: flushRight.frames()[2])))")

      // 列宽取整：1511 点宽的屏幕上两列 ½ 各 756，加起来伸出屏幕 1 点，也算正好停在屏幕边上。
      let odd = CGRect(x: 0, y: 25, width: 1511, height: 900)
      let halves = ScrollStrip(columns: [.init(ids: [1], width: 756), .init(ids: [2], width: 756), .init(ids: [3], width: 504)],
                               area: odd)
      expect(halves.overhanging(.right) == nil && halves.frames()[2]?.maxX == 1501 && halves.frames()[3]?.minX == 1501,
             "a column one point past the edge from rounding still gives the sliver up (\(String(describing: halves.frames()[2])))")
    }

    // 伸过屏幕边的那一列在上层：屏幕边最外面 4 点照样算那一条（指针甩到屏幕边就停在这里），往里不算；
    // 盖着的那扇自己的边离屏幕边不到 24 点（滚动条、改大小的边可能就在那里）时也不算。
    do {
      let mixed = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2], width: 750), .init(ids: [3], width: 500)],
                              area: screen)
      guard let sliver = mixed.slivers().first, let cover = mixed.frames()[2] else {
        expect(false, "the mixed-width strip has a parked sliver and a column over it")
        return
      }
      let y = sliver.band.midY
      expect(sliver.showsThrough(cover, at: CGPoint(x: 1499, y: y)) && sliver.showsThrough(cover, at: CGPoint(x: 1496, y: y)),
             "with the ½ column on top, the pointer pushed against the right edge (the last 4 points) still counts as on the sliver")
      expect(!sliver.showsThrough(cover, at: CGPoint(x: 1495, y: y)) && !sliver.showsThrough(cover, at: CGPoint(x: 1490, y: y)),
             "5 points in or more it is on that column's content and does not count")
      expect(!sliver.showsThrough(CGRect(x: 750, y: 25, width: 750, height: 900), at: CGPoint(x: 1499, y: y)),
             "a column ending right at the edge (not yet narrowed by its app) keeps its own edge: no glance through it")
      expect(!sliver.showsThrough(CGRect(x: 760, y: 25, width: 760, height: 900), at: CGPoint(x: 1499, y: y)),
             "nor a window that runs only 20 points past the edge, whose scroll bar may sit right there")
      expect(!sliver.showsThrough(cover, at: CGPoint(x: 1499, y: 10)) && !sliver.showsThrough(CGRect(x: 1000, y: 25, width: 750, height: 400),
                                                                                             at: CGPoint(x: 1499, y: 600)),
             "outside the sliver, or where that window does not reach, it does not count")

      let partial = ScrollStrip(columns: [.init(ids: [1], width: 500), .init(ids: [2], width: 500), .init(ids: [3], width: 1000),
                                          .init(ids: [4], width: 500)], area: screen, offset: 750)
      if let left = partial.slivers().first(where: { $0.side == .left }), let over = partial.frames()[2] {
        expect(left.showsThrough(over, at: CGPoint(x: 0, y: 400)) && left.showsThrough(over, at: CGPoint(x: 3.5, y: 400))
                 && !left.showsThrough(over, at: CGPoint(x: 4, y: 400)),
               "on the left the same: the first 4 points from the edge count, the rest is that column's")
      } else {
        expect(false, "a strip scrolled to the middle parks a column on the left under the one running past it")
      }
    }

    // 常见摆法（列宽都是 ⅓ ½ ⅔ 整屏，停在任何一个吸附位置，不留缝和留缝时）：有列停着的那一边，指针甩到屏幕边
    // 总能看一眼——要么挨着的那一列让出了那一条，要么伸过来的那一列边在屏幕外够远、借最外面那几点。
    // 取整会差一点的屏宽（1511）也一样。
    do {
      var checked = 0
      var misses: [String] = []
      for width in [CGFloat(1710), 1511, 1512] {
        let area = CGRect(x: 0, y: 25, width: width, height: 900)
        let presets = ScrollStrip.presets.map { (width * $0).rounded() }
        for gap in ArrangeGap.choices {
          for a in presets { for b in presets { for c in presets { for d in presets {
            var strip = ScrollStrip(columns: [a, b, c, d].enumerated().map { .init(ids: [CGWindowID($0.offset + 1)], width: $0.element) },
                                    area: area)
            let stops = Set(strip.columns.indices.flatMap { [strip.start(of: $0), strip.start(of: $0) + strip.columns[$0].width - width] }
              .map(strip.clamped))
            for stop in stops {
              strip.offset = stop
              let (left, right) = strip.parked()
              let parkedIDs = Set((left + right).flatMap { strip.columns[$0].ids })
              let covers = strip.frames().filter { !parkedIDs.contains($0.key) }.mapValues { ArrangeGap.apply($0, in: area, gap: gap) }
              for sliver in strip.slivers(gap: gap) {
                checked += 1
                let edge = CGPoint(x: sliver.side == .right ? sliver.band.maxX - 1 : sliver.band.minX, y: sliver.band.midY)
                if !covers.values.filter({ $0.contains(edge) }).allSatisfy({ sliver.showsThrough($0, at: edge) }) {
                  misses.append("\(Int(width)) gap \(Int(gap)) widths \([a, b, c, d].map { Int($0) }) offset \(Int(stop)) \(sliver.side)")
                }
              }
            }
          }}}}
        }
      }
      expect(checked > 1000 && misses.isEmpty,
             "in every preset layout at every resting place, the pointer pushed against an edge with a parked column reaches its sliver, whichever column is on top (\(checked) slivers; misses \(misses.prefix(3)))")
    }

    // 滑动中只挪位置、不改大小：往回滑、滑一下又弹回原处都不改；朝停靠列那边滑出去，它一滑进屏幕，挨着它的那列放回原宽。
    do {
      let strip = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2], width: 500), .init(ids: [3], width: 500)],
                              area: screen)
      /// 从停稳处沿着一串位置滑过去、停在 settle：一共改了几次窗口大小（停稳 → 滑动中每一帧 → 停稳）。
      func resizes(along path: [CGFloat], settle: CGFloat) -> Int {
        var settled = strip
        settled.offset = settle
        let steps = [strip.frames()] + path.map { strip.frames(at: $0, moving: true) } + [settled.frames()]
        return zip(steps, steps.dropFirst()).reduce(0) { total, pair in
          total + pair.0.filter { id, was in
            pair.1[id].map { abs($0.width - was.width) > 0.5 || abs($0.height - was.height) > 0.5 } ?? false
          }.count
        }
      }
      expect(strip.frames(at: 0, moving: true) == strip.frames(), "starting to move changes nothing")
      let nudged = strip.frames(at: 6, moving: true)
      expect(nudged[2] == CGRect(x: 994, y: 25, width: 490, height: 900) && nudged[3]?.minX == 1490,
             "a nudge toward the parked column moves the column beside it without resizing it (\(String(describing: nudged[2])))")
      let pulled = strip.frames(at: -40, moving: true)
      expect(pulled[2]?.width == 490 && pulled[3] == CGRect(x: 1490, y: 25, width: 500, height: 900),
             "pulling the other way keeps every width; that column slides over the parked one")
      let entering = strip.frames(at: 60, moving: true)
      expect(entering[2] == CGRect(x: 940, y: 25, width: 500, height: 900) && entering[3]?.minX == 1440,
             "once the parked column slides onto the screen, the one beside it is back to full width with no gap between them")
      expect(resizes(along: [3, 6, 9, 6, 3, 0], settle: 0) == 0, "a small swipe that springs back resizes nothing")
      expect(resizes(along: [-20, -40, -20, 0], settle: 0) == 0, "pulling past the end and springing back resizes nothing")
      let reveal = resizes(along: [100, 300, 450, 500], settle: 500)
      expect(reveal == 1, "sliding the parked column into view resizes one window, once (\(reveal))")
      let back = resizes(along: [20, 40, 20, 0], settle: 0)
      expect(back == 2, "a longer swipe toward it that springs back grows that window once and shrinks it once (\(back))")

      let left = ScrollStrip(columns: [.init(ids: [1], width: 500), .init(ids: [2], width: 750), .init(ids: [3], width: 750)],
                             area: screen, offset: 500)
      expect(left.frames(at: 540, moving: true)[2] == CGRect(x: -30, y: 25, width: 740, height: 900)
               && left.frames(at: 480, moving: true)[2] == CGRect(x: 20, y: 25, width: 750, height: 900),
             "on the left the same: it keeps giving the sliver up until the parked column slides in, then is back to full width")
    }

    // 卡片：整扇窗缩小，最宽占半屏，贴着那一条、隔一道缝，上下对着那扇窗，放不下就挪进屏幕。
    do {
      let strip = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2, 3], width: 750),
                                        .init(ids: [4], width: 500)], area: screen)
      guard let right = strip.slivers().first, let card = ScrollStrip.peekCard(for: right, in: screen) else {
        expect(false, "a parked column on the right has a card")
        return
      }
      expect(card == CGRect(x: 996, y: 35, width: 488, height: 880),
             "a third-wide window on the right shrinks just enough to fit the screen height and sits left of the sliver (\(card))")
      var scrolled = ScrollStrip(columns: strip.columns + [.init(ids: [5], width: 500)], area: screen)
      scrolled.offset = scrolled.maxOffset
      if let left = scrolled.slivers().first, let leftCard = ScrollStrip.peekCard(for: left, in: screen) {
        expect(leftCard == CGRect(x: 16, y: 138, width: 750, height: 675),
               "a two-thirds window on the left shrinks to half the screen width and sits right of the sliver, level with it (\(leftCard))")
      } else {
        expect(false, "a parked column on the left has a card")
      }
      let stacked = ScrollStrip(columns: [.init(ids: [1, 2], width: 750), .init(ids: [3], width: 1500), .init(ids: [4], width: 1500)],
                                area: screen, offset: 750)
      if let top = stacked.slivers().first, let topCard = ScrollStrip.peekCard(for: top, in: screen) {
        expect(topCard == CGRect(x: 16, y: 35, width: 750, height: 450),
               "a window that already fits keeps its size, and is nudged down to stay on screen (\(topCard))")
      } else {
        expect(false, "a stacked parked window has a card")
      }
      expect(ScrollStrip.peekCard(for: right, in: CGRect(x: 0, y: 0, width: 120, height: 900)) == nil,
             "a screen too narrow for a card shows none")
      expect(!card.intersects(right.band), "the card never covers the sliver the pointer rests on")
    }

    // 概览：整条缩小铺开、居中，列间留空；露着的那一段框出来，正好落在列边上时不跨进空隙。
    do {
      var strip = ScrollStrip(columns: [.init(ids: [1], width: 1000), .init(ids: [2, 3], width: 750),
                                        .init(ids: [4], width: 500)], area: screen)
      guard let view = strip.overview(in: screen) else {
        expect(false, "a strip has an overview")
        return
      }
      expect(view.scale == 0.5, "three columns fit at half size, the most it shrinks to (\(view.scale))")
      expect(view.columns == [CGRect(x: 171.5, y: 250, width: 500, height: 450), CGRect(x: 687.5, y: 250, width: 375, height: 450),
                              CGRect(x: 1078.5, y: 250, width: 250, height: 450)],
             "columns keep their order and relative widths, sixteen points apart, centred (\(view.columns))")
      expect(view.windows[2] == CGRect(x: 687.5, y: 250, width: 375, height: 225) && view.windows[3]?.minY == 475,
             "two stacked windows split their column as they do on screen")
      expect(view.viewport == CGRect(x: 171.5, y: 250, width: 766, height: 450),
             "the part on screen now runs from the first column into two thirds of the second (\(view.viewport))")
      strip.offset = strip.maxOffset
      expect(strip.overview(in: screen).map { $0.viewport.minX == 546.5 && $0.viewport.maxX == 1328.5 } == true,
             "scrolled to the end, it ends exactly at the last column")
      strip.offset = 1000
      expect(strip.overview(in: screen)?.viewport.minX == 687.5, "starting exactly at a column edge, it starts at that column, not in the gap")
      let long = ScrollStrip(columns: (1...10).map { .init(ids: [CGWindowID($0)], width: 1500) }, area: screen)
      if let far = long.overview(in: screen) {
        expect(far.columns.last.map { $0.maxX <= screen.maxX - 48 + 0.001 } == true && far.columns.first.map { $0.minX >= 48 - 0.001 } == true,
               "ten full-screen columns shrink until they all fit inside the margins (scale \(far.scale))")
      } else {
        expect(false, "a long strip still has an overview")
      }
      expect(ScrollStrip(columns: [], area: screen).overview(in: screen) == nil, "an empty strip has no overview")
    }

    // 松手速度：只看松手前最后 0.15 秒，松手那一刻补一个没再动的点。
    do {
      typealias Sample = (time: TimeInterval, offset: CGFloat)
      // 手指匀速 1000 点/秒，每 16 毫秒一个点，滑了 0.4 秒。
      var steady: [Sample] = []
      for i in 0...25 { steady.append((time: 10 + Double(i) * 0.016, offset: CGFloat(i) * 16)) }
      let end = steady.last!.time
      let quick = ScrollStrip.releaseVelocity(samples: steady, releaseTime: end + 0.004)
      expect(quick > 650 && quick < 1350, "swiping steadily and lifting at once keeps about the finger's speed (\(Int(quick)) pt/s)")
      var backward: [Sample] = []
      for sample in steady { backward.append((time: sample.time, offset: -sample.offset)) }
      expect(ScrollStrip.releaseVelocity(samples: backward, releaseTime: end + 0.004) < -650, "and the sign follows the direction of travel")
      expect(ScrollStrip.releaseVelocity(samples: steady, releaseTime: end + 0.2) == 0, "pausing 200 ms before lifting does not fling the strip")
      expect(ScrollStrip.releaseVelocity(samples: [], releaseTime: 5) == 0, "no samples, no velocity")
      expect(ScrollStrip.releaseVelocity(samples: [(time: 5, offset: 100)], releaseTime: 5.01) == 0, "a single sample, no velocity")
      // 很久以前的快速滑动不算：松手前 150 毫秒里只有一个点和松手点。
      let old: [Sample] = [(time: 1.0, offset: 0), (time: 1.016, offset: 50), (time: 1.032, offset: 100), (time: 1.2, offset: 100)]
      expect(ScrollStrip.releaseVelocity(samples: old, releaseTime: 1.25) == 0, "fast samples older than 150 ms are ignored")
      // 松手前最后 150 毫秒匀速，更早的更快：只取近的。
      var slowing: [Sample] = [(time: 0.0, offset: 0), (time: 0.016, offset: 100)]
      for i in 0...9 { slowing.append((time: 1.0 + Double(i) * 0.016, offset: 100 + CGFloat(i) * 8)) }
      let recent = ScrollStrip.releaseVelocity(samples: slowing, releaseTime: 1.144)
      expect(recent > 400 && recent < 600, "only the last 150 ms counts, so earlier fast motion does not inflate it (\(Int(recent)) pt/s)")
    }

    // 卷轴停下来那一段的阻尼弹簧（和官网那段动画同一条公式）：起点、初速、终点都对，
    // 并且和细步长的数值积分一致——解析解算错的话，这里会立刻看出来。
    do {
      func integrate(_ T: Double, from: Double, to: Double, velocity: Double,
                     zeta: Double, omega: Double) -> (position: Double, velocity: Double) {
        var x = from, v = velocity, t = 0.0
        let dt = 1e-5
        while t < T {
          let a = -omega * omega * (x - to) - 2 * zeta * omega * v
          v += a * dt
          x += v * dt
          t += dt
        }
        return (x, v)
      }
      let cases: [(from: Double, to: Double, v: Double, zeta: Double, omega: Double)] = [
        (0, 300, 0, 0.88, 2 * .pi / 0.42),      // 松手时没速度（慢慢停下）
        (0, -450, 900, 0.88, 2 * .pi / 0.42),   // 往左滑、带着速度
        (0, 300, 1500, 0.88, 2 * .pi / 0.42),   // 往右滑、速度很大
        (100, 100, 0, 0.88, 2 * .pi / 0.42),    // 不用动
        (0, 300, -800, 1.0, 2 * .pi / 0.2),     // 减少动态效果：临界阻尼、更短
      ]
      for c in cases {
        let atZero = FluidMotion.springState(0, from: c.from, to: c.to, velocity: c.v, zeta: c.zeta, omega: c.omega)
        expect(abs(atZero.position - c.from) < 1e-9, "弹簧 t=0 时还在出发的地方（\(c.from) → \(c.to)）")
        expect(abs(atZero.velocity - c.v) < 1e-6, "弹簧 t=0 时带着松手那一刻的速度（\(c.v)）")
        let rest = FluidMotion.springState(2, from: c.from, to: c.to, velocity: c.v, zeta: c.zeta, omega: c.omega)
        expect(abs(rest.position - c.to) < 0.5 && abs(rest.velocity) < 1,
               "弹簧最终停在目标上（\(c.to)），速度归零")
        for T in [0.05, 0.2, 0.5, 1.0] {
          let analytic = FluidMotion.springState(T, from: c.from, to: c.to, velocity: c.v, zeta: c.zeta, omega: c.omega)
          let numeric = integrate(T, from: c.from, to: c.to, velocity: c.v, zeta: c.zeta, omega: c.omega)
          expect(abs(analytic.position - numeric.position) < 0.1 && abs(analytic.velocity - numeric.velocity) < 1,
                 "弹簧在 t=\(T)s 和细步长数值积分一致（位置差 \(String(format: "%.4f", abs(analytic.position - numeric.position))) 点）")
        }
      }
      // 官网上松手滑出去多远：r=0.998 时大约是速度的一半（点），和脚本里那条投影公式同一条。
      expect(abs(FluidMotion.projection(velocity: 1000) - 499) < 1,
             "惯性投影：1000 点/秒大约再滑 499 点（r=0.998，和官网一致）")
    }

    // 概览里拖着窗口靠边自动滑。
    do {
      let z = EdgeScroll.zone, d = EdgeScroll.dwellRequired
      expect(EdgeScroll.edgeScrollSpeed(distanceToEdge: z, dwell: 1) == 0 && EdgeScroll.edgeScrollSpeed(distanceToEdge: 200, dwell: 1) == 0,
             "outside the 30 pt zone the strip does not scroll")
      expect(EdgeScroll.edgeScrollSpeed(distanceToEdge: 0, dwell: d - 0.001) == 0, "inside the zone but before 100 ms it does not scroll")
      expect(EdgeScroll.edgeScrollSpeed(distanceToEdge: 15, dwell: d) > 0, "at 100 ms it starts")
      var last: CGFloat = 0, monotonic = true
      for depth in stride(from: CGFloat(29), through: 0, by: -1) {
        let v = EdgeScroll.edgeScrollSpeed(distanceToEdge: depth, dwell: 1)
        if v < last { monotonic = false }
        last = v
      }
      expect(monotonic, "speed rises with depth into the zone")
      expect(EdgeScroll.edgeScrollSpeed(distanceToEdge: 0, dwell: 1) == 1500, "exactly at the edge it is 1500 pt/s")
      expect(EdgeScroll.edgeScrollSpeed(distanceToEdge: -20, dwell: 5) <= 1500 && EdgeScroll.edgeScrollSpeed(distanceToEdge: 0, dwell: 99) <= 1500,
             "never exceeds 1500 pt/s (even past the edge)")
      let l = EdgeScroll.velocity(pointerX: 10, width: 1000, dwell: 1), r = EdgeScroll.velocity(pointerX: 990, width: 1000, dwell: 1)
      expect(l < 0 && r > 0 && l == -r, "left and right edges are symmetric with opposite sign")
      var t = EdgeScrollTracker()
      expect(t.velocity(pointerX: 0, width: 1000, now: 10) == 0, "tracker: entering the zone starts the dwell clock")
      expect(t.velocity(pointerX: 0, width: 1000, now: 10.11) == -1500, "tracker: after 100 ms at the left edge it scrolls left")
      expect(t.velocity(pointerX: 500, width: 1000, now: 10.2) == 0 && !t.isInZone, "tracker: leaving the zone stops at once")
      expect(t.velocity(pointerX: 0, width: 1000, now: 10.3) == 0, "tracker: re-entering restarts the dwell")
      t.reset()
      expect(!t.isInZone, "tracker: ending the drag clears it")
    }

    // 居中三种（稿：卷轴.html 的 snapCands / offsetFor）：贴边（默认，等于从前）/ 居中 / 放不下才居中，和“放得下就居中”。
    do {
      let W: CGFloat = 1500
      let fractions: [CGFloat] = [1.0 / 3, 0.5, 2.0 / 3, 1]
      func strip(_ widths: [CGFloat], _ mode: ScrollStrip.Centering = .edge, fits: Bool = false) -> ScrollStrip {
        var s = ScrollStrip(columns: widths.enumerated().map { .init(ids: [CGWindowID($0.offset + 1)], width: $0.element) }, area: screen)
        s.centering = mode
        s.centersWhenFits = fits
        return s
      }
      // 具体数：500 / 750 / 1000 三列，总宽 2250，最大 offset 750。
      let a = strip([500, 750, 1000], .always)
      expect(a.offsetFor(0) == -500 && a.offsetFor(1) == 125 && a.offsetFor(2) == 1000, "always: the focused column sits in the middle (got \(a.offsetFor(0)), \(a.offsetFor(1)), \(a.offsetFor(2)))")
      expect(a.snapped(-9999) == -500 && a.snapped(9999) == 1000 && a.snapped(100) == 125, "always: release snaps to a column's centre, and the ends are the first/last centres")
      expect(a.clamped(-9999) == -500 && a.clamped(9999) == 1000, "always: the stretch limits are the first and last centres")
      let o = strip([500, 750, 1000], .overflow)
      expect(o.offsetFor(1, previous: 0) == 0, "overflow: two neighbours that fit one screen are just revealed, not centred")
      expect(o.offsetFor(2, previous: 1) == 750, "overflow: two that do not fit one screen centre the new one, held inside the strip's ends (got \(o.offsetFor(2, previous: 1)))")
      expect(o.offsetFor(0, previous: nil) == 0 && o.offsetFor(2, previous: 2) == o.revealing(2), "overflow: no previous focus, or the same column, falls back to edge")
      expect(o.snapped(-9999) == 0 && o.snapped(9999) == 750, "overflow: snap points stay inside [0, maxOffset]")
      let e = strip([500, 750, 1000])
      expect(e.offsetFor(1, previous: 0) == e.revealing(1) && e.snapped(400) == 500 && e.clamped(-5) == 0 && e.clamped(5000) == 750,
             "edge (default) is today: revealing, [0, maxOffset]")

      // 放得下就居中：总宽不到一屏，整组放正中；开关关着（默认）不动。
      let f = strip([500, 500], .edge, fits: true)
      expect(f.fitOffset == -250 && f.offsetFor(0) == -250 && f.offsetFor(1) == -250 && f.snapped(900) == -250 && f.clamped(0) == -250,
             "fits-and-centers: the whole group sits in the middle whatever the focus, release or clamp")
      let fa = strip([500, 500], .always, fits: true)
      expect(fa.offsetFor(0) == -250 && fa.snapped(-300) == -250, "fits-and-centers wins over the centring mode while everything fits")
      let off = strip([500, 500])
      expect(off.offsetFor(1) == 0 && off.snapped(300) == 0 && off.clamped(-5) == 0, "fits-and-centers off: nothing changes")
      expect(!strip([1000, 1000], .edge, fits: true).fitsAndCenters && strip([1000, 500], .edge, fits: true).fitsAndCenters,
             "fits-and-centers only while the columns add up to at most one screen")
      var grow = strip([500, 500], .edge, fits: true)
      grow.setWidth(1000, of: 1)
      expect(grow.offset == 0 && grow.fitsAndCenters, "a strip that grows to exactly one screen is centred at 0")
      grow.setWidth(1000, of: 0)
      expect(!grow.fitsAndCenters && grow.offset == 0, "once it no longer fits, edge rules take over again")
      var shrink = strip([1000, 1000], .edge, fits: true)
      shrink.offset = 400
      shrink.remove(2)
      expect(shrink.offset == -250, "closing a window until everything fits centres the group (got \(shrink.offset))")
      var inserted = strip([500], .always)
      inserted.insert(9, width: 750, after: 0)
      expect(inserted.offset == 500 + 375 - 750, "always: a freshly opened window is centred")
      var widened = strip([500, 750, 1000], .always)
      widened.setWidth(1000, of: 1)
      expect(widened.offset == 500 + 500 - 750, "always: widening a column keeps it centred")

      // ⅓ ½ ⅔ 整屏的所有三列组合（64 种）：三种方式的吸附点与走列位置。
      var bad: [String] = []
      for x in fractions { for y in fractions { for z in fractions {
        let widths = [x, y, z].map { ($0 * W).rounded() }
        let tag = "\(widths)"
        let total = widths.reduce(0, +), maxOff = max(0, total - W)
        let edge = strip(widths), always = strip(widths, .always), over = strip(widths, .overflow)
        for i in 0..<3 {
          let start = widths.prefix(i).reduce(0, +), mid = start + widths[i] / 2 - W / 2
          if always.offsetFor(i) != mid { bad.append("always \(tag) col \(i)") }
          if abs(always.snapped(always.offsetFor(i)) - mid) > 0.001 { bad.append("always snap \(tag) col \(i)") }
          for prev in [nil, 0, 1, 2] as [Int?] {
            let got = over.offsetFor(i, previous: prev)
            var expected = edge.revealing(i)
            if let prev, prev != i {
              let lo = min(start, widths.prefix(prev).reduce(0, +)), hi = max(start + widths[i], widths.prefix(prev + 1).reduce(0, +))
              if hi - lo > W { expected = min(max(mid, 0), maxOff) }
            }
            if got != expected { bad.append("overflow \(tag) col \(i) prev \(String(describing: prev)): \(got) vs \(expected)") }
            if got < 0 || got > maxOff { bad.append("overflow out of range \(tag)") }
            if edge.offsetFor(i, previous: prev) != edge.revealing(i) { bad.append("edge \(tag)") }
          }
        }
        // 吸附：任何位置落在候选里，候选在界限内；贴边的候选与从前一致。
        for projected in stride(from: CGFloat(-2000), through: total + 2000, by: 137) {
          let ea = edge.snapped(projected)
          if ea < 0 || ea > maxOff { bad.append("edge snap range \(tag)") }
          let ov = over.snapped(projected)
          if ov < -0.001 || ov > maxOff + 0.001 || !over.snapCandidates().contains(ov) { bad.append("overflow snap \(tag) \(projected)") }
          let al = always.snapped(projected)
          if !always.snapCandidates().contains(al) { bad.append("always snap cand \(tag) \(projected)") }
        }
      } } }
      expect(bad.isEmpty, "⅓ ½ ⅔ full-width: all 64 column combinations agree with the draft's rules in all three modes (\(bad.prefix(3)))")

      // 存法：没有总开关；方式默认贴边（等于从前的手感），放得下就居中默认开。
      expect(ScrollStrip.resolvedCentering(mode: nil, whenFits: nil) == (.edge, true), "nothing stored: edge, and centred while everything fits")
      expect(ScrollStrip.resolvedCentering(mode: "always", whenFits: false) == (.always, false), "stored mode and fit-centring are read as stored")
      expect(ScrollStrip.resolvedCentering(mode: "overflow", whenFits: nil) == (.overflow, true), "fit-centring defaults on whichever mode is stored")
      expect(ScrollStrip.resolvedCentering(mode: "bogus", whenFits: false) == (.edge, false), "an unknown stored mode is edge")
      expect(ScrollStrip(columns: [.init(ids: [1], width: 500)], area: screen).centersWhenFits, "a new strip centres a group that fits (Aaron's default)")

      // 整组居中时（负的 offset）：不算停在屏幕外、不让边、概览框不伸出概览之外、手指能拉的范围就是那一个点。
      let bounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
      var centred = strip([500, 500], .edge, fits: true)
      centred.offset = centred.fitOffset
      expect(centred.offset == -250 && centred.parked().left.isEmpty && centred.parked().right.isEmpty && centred.slivers().isEmpty,
             "a centred group has nothing parked past either edge")
      expect(centred.frames()[1] == CGRect(x: 250, y: 25, width: 500, height: 900) && centred.frames()[2] == CGRect(x: 750, y: 25, width: 500, height: 900),
             "its windows sit in the middle at their full width (\(String(describing: centred.frames())))")
      expect(centred.scrollBounds == (-250)...(-250) && centred.clamped(300) == -250 && centred.clamped(-900) == -250,
             "the finger can only stretch it around the one centred position")
      if let view = centred.overview(in: bounds) {
        expect(bounds.contains(view.viewport) && view.viewport.width > 0 && view.viewport.minX <= view.columns[0].minX && view.viewport.maxX >= view.columns[1].maxX,
               "the overview's frame around what is on screen stays inside the overview and encloses the whole centred group (\(view.viewport))")
      } else { expect(false, "a centred group has an overview") }
      // 居中方式下停在最后一列正中：左边的列照样只露 10 点；第一列居中：左边是空的，没有列停在那里。
      var wide = strip([500, 750, 1000], .always)
      wide.offset = wide.offsetFor(2)
      expect(wide.offset == 1000 && wide.parked().left == [0] && wide.frames()[1]?.minX == -490,
             "always: scrolled to the last column centred, the first column still parks with a 10-point sliver (\(String(describing: wide.frames()[1])))")
      wide.offset = wide.offsetFor(0)
      expect(wide.offset == -500 && wide.frames()[1] == CGRect(x: 500, y: 25, width: 500, height: 900) && wide.parked().left.isEmpty,
             "always: the first column centred leaves empty screen on its left, nothing parks there (\(String(describing: wide.frames()[1])))")
      if let view = wide.overview(in: bounds) {
        expect(bounds.contains(view.viewport), "the overview frame is kept inside the overview when the first column is centred (\(view.viewport))")
      } else { expect(false, "an always-centred strip has an overview") }
    }

    // 并进和拆出（SS-02）：每扇至少 280 点高；满列拒绝、拆出保宽、刚开的窗口并进后再关仍回原位、整组居中时的位置。
    do {
      let bounds = CGRect(x: 0, y: 0, width: 1470, height: 956)
      func make(_ columns: [ScrollStrip.Column], offset: CGFloat = 0, fits: Bool = false) -> ScrollStrip {
        var s = ScrollStrip(columns: columns, area: screen, offset: offset)
        s.centersWhenFits = fits
        return s
      }
      let w: CGFloat = 500
      expect(make([.init(ids: [1], width: w)]).rowCapacity == 3, "900 points of height hold 3 windows of at least 280")
      expect(ScrollStrip(columns: [], area: CGRect(x: 0, y: 0, width: 1500, height: 559)).rowCapacity == 1
               && ScrollStrip(columns: [], area: CGRect(x: 0, y: 0, width: 1500, height: 560)).rowCapacity == 2, "559 holds one, 560 holds two")

      var a = make([.init(ids: [1], width: w), .init(ids: [2], width: 750), .init(ids: [3], width: w)])
      // 并进右边：2 叠到 3 底下，3 的宽度不变，高度平分，2 那一列没了。
      expect(a.join(2, toward: .right) == .merged(column: 1) && a.columns.map(\.ids) == [[1], [3, 2]] && a.columns[1].width == w
               && a.columns[1].shares == [0.5, 0.5], "joining right stacks the window under that column, evenly, at that column's width")
      expect(a.join(2, toward: .right) == .split(column: 2) && a.columns.map(\.ids) == [[1], [3], [2]] && a.columns[2].width == w,
             "pressing again while in a column splits it out to the right at the same width")
      expect(a.columns.allSatisfy { $0.shares == [1] }, "the column it left is whole again")
      var b = make([.init(ids: [1], width: w), .init(ids: [2], width: 750)])
      expect(b.join(1, toward: .left) == .none && b.join(2, toward: .right) == .none, "no column on that side: nothing to join")
      expect(b.columns.map(\.ids) == [[1], [2]], "and nothing moves")
      // 往左并进、再往左拆出：拆出的那一列在原来那一列的左边。
      expect(b.join(2, toward: .left) == .merged(column: 0) && b.columns.map(\.ids) == [[1, 2]] && b.columns[0].width == w,
             "joining left appends to the bottom of the left column and keeps its width")
      expect(b.join(2, toward: .left) == .split(column: 0) && b.columns.map(\.ids) == [[2], [1]] && b.columns.map(\.width) == [w, w],
             "splitting toward the left puts the window's new column on the left")
      // 拆出：三扇不等高的列拆掉中间一扇，剩下两扇按原来的比例补满，新列宽度同原列。
      var c = make([.init(ids: [1, 2, 3], shares: [0.5, 0.25, 0.25], width: 600)])
      expect(c.join(2, toward: .right) == .split(column: 1) && c.columns[0].ids == [1, 3] && abs(c.columns[0].shares[0] - 2.0 / 3) < 1e-9
               && abs(c.columns[0].shares.reduce(0, +) - 1) < 1e-9 && c.columns[1].width == 600, "splitting keeps the column's width and refills the rest by proportion")
      // 满列拒绝：已有 3 扇（Air 15 英寸），不并进，告诉界面哪一列要晃。
      var full = make([.init(ids: [1], width: w), .init(ids: [2, 3, 4], width: 750)])
      let beforeFull = full
      expect(full.join(1, toward: .right) == .full(column: 1) && full == beforeFull, "a full column refuses the join and nothing changes")
      expect(full.join(3, toward: .left) == .split(column: 1) && full.columns.map(\.ids) == [[1], [3], [2, 4]], "but a window can always leave a full column")
      // 刚开的窗口并进后再关：回到开它之前的位置（合并前的 offset 记忆）。
      var strip = make([.init(ids: [1], width: 1000), .init(ids: [2], width: 750)], offset: 250)
      let opened = strip.offset
      strip.insert(9, width: 750, after: 1)
      expect(strip.offset != opened, "the new window scrolls into view")
      expect(strip.join(9, toward: .left) == .merged(column: 1), "the new window joins the column on its left")
      strip.remove(9)
      expect(strip.columns.map(\.ids) == [[1], [2]] && strip.offset == opened, "closing it right after restores the position from before it opened (\(strip.offset))")
      var split = make([.init(ids: [1], width: 1000), .init(ids: [2], width: 750)], offset: 250)
      split.insert(9, width: 750, after: 1)
      _ = split.join(9, toward: .left)
      _ = split.join(9, toward: .right)
      split.remove(9)
      expect(split.columns.map(\.ids) == [[1], [2]] && split.offset == opened, "join then split then close still goes back to where it was")
      // 中间动过别的（滑了一下、并了别的窗口）就不再回原位。
      var moved = make([.init(ids: [1], width: 1000), .init(ids: [2], width: 750)], offset: 250)
      moved.insert(9, width: 750, after: 1)
      _ = moved.join(9, toward: .left)
      moved.offset = 100
      moved.remove(9)
      expect(moved.offset == 100, "a slide in between cancels the memory")
      var other = make([.init(ids: [1], width: 1000), .init(ids: [2], width: 750), .init(ids: [3], width: 750)], offset: 500)
      other.insert(9, width: 750, after: 2)
      expect(other.join(3, toward: .right) == .merged(column: 2), "another window joins the new window's column")
      let keptOffset = other.offset
      other.remove(9)
      expect(other.columns.map(\.ids) == [[1], [2], [3]] && other.offset == other.clamped(keptOffset),
             "closing the new window afterwards does not use a memory that is no longer true")

      // 整组居中时：并进之后总宽变了，整组重新放在正中，概览里露着的那一段不越界。
      var group = make([.init(ids: [1], width: 500), .init(ids: [2], width: 500), .init(ids: [3], width: 500)], fits: true)
      expect(group.fitsAndCenters && group.fitOffset == 0, "three thirds fill the screen exactly: centred is 0")
      expect(group.join(3, toward: .left) == .merged(column: 1) && group.totalWidth == 1000 && group.offset == -250,
             "joining narrows the group to 1000 and the group is centred again (\(group.offset))")
      expect(group.frames()[1]?.minX == 250 && group.frames()[2]?.minX == 750 && group.frames()[3]?.minX == 750,
             "so the windows sit at 250 and 750 (\(String(describing: group.frames())))")
      if let view = group.overview(in: bounds) {
        expect(bounds.contains(view.viewport), "the overview viewport of the centred group is inside the overview (\(view.viewport))")
      } else { expect(false, "the centred group has an overview") }
      expect(group.join(3, toward: .right) == .split(column: 2) && group.totalWidth == 1500 && group.offset == 0,
             "splitting again fills the screen: centred is 0")
      // 贴边方式、放不下：并进后位置仍在 [0, maxOffset] 里。
      var plain = make([.init(ids: [1], width: 1000), .init(ids: [2], width: 750), .init(ids: [3], width: 750)], offset: 1000)
      _ = plain.join(3, toward: .left)
      expect(plain.offset >= 0 && plain.offset <= plain.maxOffset, "edge mode keeps the offset inside [0, maxOffset] after a join")
    }

    // 概览里拖着换位置（SS-03）：最近的缝、满列改画新开一列、等于没动的缝不算、松手一次摆好、VoiceOver 落点。
    do {
      func make(_ cols: [ScrollStrip.Column]) -> ScrollStrip {
        var s = ScrollStrip(columns: cols, area: screen); s.centersWhenFits = false; return s
      }
      let strip = make([.init(ids: [1], width: 500), .init(ids: [2, 3], width: 500), .init(ids: [4], width: 500)])
      guard let layout = strip.overview(in: CGRect(x: 0, y: 0, width: 1000, height: 700)) else { expect(false, "drag: layout"); exit(1) }
      let c0 = layout.columns[0], c1 = layout.columns[1], c2 = layout.columns[2]
      let rowSeamY = layout.windows[2]!.maxY
      let between = CGPoint(x: (c0.maxX + c1.minX) / 2, y: c0.midY)
      expect(strip.seam(nearest: between, dragging: 4, in: layout)?.drop == .newColumn(at: 1), "pointer on the vertical seam opens a new column there")
      let inside = CGPoint(x: c1.midX, y: rowSeamY + 3)
      let join = strip.seam(nearest: inside, dragging: 4, in: layout)
      expect(join?.drop == .join(column: 1, row: 1), "pointer near the horizontal seam joins that column (\(String(describing: join?.drop)))")
      expect(join?.bar.minX == c1.minX && join?.bar.width == c1.width && abs((join?.bar.midY ?? 0) - rowSeamY) < 0.01, "the bar sits on the seam, as wide as the column")
      let nearEdge = CGPoint(x: c1.minX - 3, y: rowSeamY)
      expect(strip.seam(nearest: nearEdge, dragging: 4, in: layout)?.drop == .newColumn(at: 1), "close to the column edge the vertical seam wins")
      expect(strip.seam(nearest: CGPoint(x: c0.minX - 30, y: c0.midY), dragging: 4, in: layout)?.drop == .newColumn(at: 0), "left of the first column opens a column at the start")
      expect(strip.seam(nearest: CGPoint(x: c2.maxX + 30, y: c2.midY), dragging: 1, in: layout)?.drop == .newColumn(at: 3), "right of the last column opens a column at the end")
      let own = strip.seam(nearest: between, dragging: 1, in: layout)
      expect(own?.drop != .newColumn(at: 0) && own?.drop != .newColumn(at: 1), "a lone window's own two seams do not attract it (\(String(describing: own?.drop)))")
      let own3 = strip.seam(nearest: inside, dragging: 3, in: layout)
      expect(own3?.drop != .join(column: 1, row: 1), "the seam right beside the dragged window inside its column is skipped")
      expect(strip.seam(nearest: CGPoint(x: c1.maxX + 8, y: c1.midY), dragging: 3, in: layout)?.drop == .newColumn(at: 2), "but it can be pulled out into its own column")

      // 满列（一列最多 3 扇）：横缝改画成新开一列，靠指针那一边
      let full = make([.init(ids: [1, 2, 3], width: 500), .init(ids: [4], width: 500), .init(ids: [5], width: 500)])
      let fl = full.overview(in: CGRect(x: 0, y: 0, width: 1000, height: 700))!
      let seamY = fl.windows[1]!.maxY
      let fc = fl.columns[0]
      expect(full.rowCapacity == 3, "this screen holds 3 per column")
      expect(full.seam(nearest: CGPoint(x: fc.maxX - 10, y: seamY), dragging: 5, in: fl)?.drop == .newColumn(at: 1), "a full column draws a new column on the pointer's right side")
      expect(full.seam(nearest: CGPoint(x: fc.minX + 10, y: seamY), dragging: 5, in: fl)?.drop == .newColumn(at: 0), "or on the left side")
      expect(full.seam(nearest: CGPoint(x: fc.midX, y: seamY), dragging: 3, in: fl)?.drop == .join(column: 0, row: 1), "the dragged window's own column is not full for it")

      // 松手：新开一列、宽度同原来那一列
      var a = strip
      expect(a.move(4, to: .newColumn(at: 0)) && a.columns.map(\.ids) == [[4], [1], [2, 3]], "moving 4 to the front reorders the columns (\(a.columns.map(\.ids)))")
      var b = strip
      expect(b.move(1, to: .newColumn(at: 3)) && b.columns.map(\.ids) == [[2, 3], [4], [1]], "moving a lone window past others closes its old column")
      var w = make([.init(ids: [1], width: 750), .init(ids: [2, 3], width: 500)])
      expect(w.move(3, to: .newColumn(at: 0)) && w.columns.map(\.ids) == [[3], [1], [2]] && w.columns[0].width == 500 && w.columns[2].shares == [1],
             "a window pulled out of a stack keeps that column's width and the rest fill its height")
      var j = strip
      expect(j.move(4, to: .join(column: 1, row: 1)) && j.columns.map(\.ids) == [[1], [2, 4, 3]] && j.columns[1].shares.allSatisfy { abs($0 - 1.0 / 3) < 0.0001 },
             "joining slots between the two and shares the height evenly (\(j.columns.map(\.ids)))")
      var k = strip
      expect(k.move(1, to: .join(column: 2, row: 1)) && k.columns.map(\.ids) == [[2, 3], [4, 1]], "joining a later column adjusts for the vanished source column")
      var r = strip
      expect(r.move(2, to: .join(column: 1, row: 2)) && r.columns.map(\.ids) == [[1], [3, 2], [4]], "reordering inside one column works")
      var n = strip
      expect(!n.move(1, to: .newColumn(at: 1)) && n == strip, "dropping where it already is does nothing")
      var fullStrip = full
      expect(!fullStrip.move(4, to: .join(column: 0, row: 1)) && fullStrip == full, "joining a full column is refused and nothing changes")
      expect(j.offset >= 0 && j.offset <= j.maxOffset, "the offset stays inside the strip after a move")

      // VoiceOver 动作
      expect(strip.drop(for: 4, toward: .left, joining: false) == .newColumn(at: 1), "move a lone window one column to the left")
      expect(strip.drop(for: 4, toward: .right, joining: false) == nil, "nothing to the right of the last column")
      expect(strip.drop(for: 1, toward: .right, joining: false) == .newColumn(at: 2), "a lone window moves right past the next column")
      expect(strip.drop(for: 3, toward: .left, joining: false) == .newColumn(at: 1), "a stacked window moves out to the left as its own column")
      expect(strip.drop(for: 4, toward: .left, joining: true) == .join(column: 1, row: 2), "join the column on the left")
      expect(full.drop(for: 4, toward: .left, joining: true) == nil, "a full column cannot be joined from the side either")
    }

    if failures == 0 { print("PASS: scroll strip — edge slivers (nearest and farther parked columns), the column resting on the edge beside a parked one leaving its sliver free (not one running past it), the outermost points at the edge still reaching a sliver under a column running past it, no resizing while the strip slides, peek card placement, overview layout and viewport, dragging in the overview (nearest seam, full column, one-shot move, VoiceOver drops)") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
