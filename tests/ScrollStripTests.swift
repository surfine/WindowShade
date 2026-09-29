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

    if failures == 0 { print("PASS: scroll strip — edge slivers (nearest and farther parked columns), the column resting on the edge beside a parked one leaving its sliver free (not one running past it), the outermost points at the edge still reaching a sliver under a column running past it, no resizing while the strip slides, peek card placement, overview layout and viewport") }
    else { print("FAILED \(failures)"); exit(1) }
  }
}
