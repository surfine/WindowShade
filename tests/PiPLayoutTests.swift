// 画中画的大小、吸附到角、推到边上藏起来、只看一块的换算：纯逻辑，不碰任何窗口。
import CoreGraphics
import Foundation

@main
struct PiPLayoutTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        // 一块 1728×1117 的屏：上面留菜单栏（可见范围从 y=70 起），下面留 Dock。
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let area = CGRect(x: 0, y: 70, width: 1728, height: 1010)
        let hd = CGSize(width: 1280, height: 720)   // 16:9
        let small = PiPLayout.size(source: hd, level: .small, area: area)
        let medium = PiPLayout.size(source: hd, level: .medium, area: area)

        // 三种大小：16:9 的窗口在各档下按比例放进一块。
        do {
            let large = PiPLayout.size(source: hd, level: .large, area: area)
            expect(small == CGSize(width: 240, height: 135), "a 16:9 window is 240×135 at the small size (got \(small))")
            expect(medium == CGSize(width: 360, height: 203), "360×203 at the medium size (got \(medium))")
            expect(large == CGSize(width: 520, height: 293), "520×293 at the large size (got \(large))")
            expect(medium.width.rounded() == medium.width && medium.height.rounded() == medium.height,
                   "the size is rounded to whole points (\(medium))")
        }

        // 特别高的窗口：高度封顶到可见高度的六成，比例照旧。
        do {
            let tall = PiPLayout.size(source: CGSize(width: 400, height: 1200), level: .small, area: area)
            expect(tall.height == area.height * 0.6, "a very tall source is capped at 60% of the visible height (got \(tall))")
            expect(abs(tall.width / tall.height - 400.0 / 1200.0) < 0.02, "and keeps its aspect ratio (\(tall))")
            expect(tall.width >= 120, "and does not fall under the minimum width (\(tall))")
        }

        // 特别宽的窗口：宽度不超过可见宽度的四成半。
        do {
            for level in PiPSizeLevel.allCases {
                let flat = PiPLayout.size(source: CGSize(width: 4000, height: 200), level: level, area: area)
                expect(flat.width <= area.width * 0.45,
                       "at \(level) a very wide source stays within 45% of the visible width (\(flat))")
            }
        }

        // 又小又怪的来源：不许小过 120×60，撑不下就只顶到最小。
        do {
            let flat = PiPLayout.size(source: CGSize(width: 1000, height: 50), level: .small, area: area)
            expect(flat == CGSize(width: 240, height: 60),
                   "a flat source keeps its width but stops at 60 high (got \(flat))")
            let thin = PiPLayout.size(source: CGSize(width: 40, height: 2000), level: .small, area: area)
            expect(thin == CGSize(width: 120, height: 606),
                   "a thin source stops at 120 wide and keeps the capped height (got \(thin))")
        }

        // 四个角：都从可见范围的边上让出 16 点。
        do {
            let size = CGSize(width: 240, height: 135)
            for corner in PiPCorner.allCases {
                let frame = PiPLayout.frame(corner: corner, size: size, area: area)
                expect(frame.width == size.width && frame.height == size.height, "\(corner) keeps the size")
                expect(frame.minX == area.minX + 16 || frame.maxX == area.maxX - 16,
                       "\(corner) is inset 16 from the left or right visible edge (\(frame))")
                expect(frame.minY == area.minY + 16 || frame.maxY == area.maxY - 16,
                       "\(corner) is inset 16 from the top or bottom visible edge (\(frame))")
            }
            let topLeft = PiPLayout.frame(corner: .topLeft, size: size, area: area)
            expect(topLeft.minX == 16 && topLeft.maxY == 1064, "the top-left corner sits at (16, up to 1064) (\(topLeft))")
            let bottomRight = PiPLayout.frame(corner: .bottomRight, size: size, area: area)
            expect(bottomRight.maxX == 1712 && bottomRight.minY == 86, "the bottom-right corner sits at (up to 1712, 86) (\(bottomRight))")
        }

        // 同一个角上的第二块：顺着竖直方向摞在后面，贴的还是同一条侧边，中间留 12 点。
        do {
            let first = CGSize(width: 240, height: 135)
            let second = CGSize(width: 360, height: 203)
            let bottom = [
                PiPLayout.frame(corner: .bottomRight, size: first, area: area),
                PiPLayout.frame(corner: .bottomRight, size: second, area: area, stackedBefore: [first]),
            ]
            expect(bottom[1].minY - bottom[0].maxY == 12,
                   "the second in bottomRight sits 12 above the first (\(bottom[0]) / \(bottom[1]))")
            expect(bottom[0].maxX == bottom[1].maxX && bottom[0].maxX == area.maxX - 16,
                   "both keep the same right edge")
            let top = [
                PiPLayout.frame(corner: .topLeft, size: first, area: area),
                PiPLayout.frame(corner: .topLeft, size: second, area: area, stackedBefore: [first]),
            ]
            expect(top[0].minY - top[1].maxY == 12,
                   "in topLeft the second goes downward (\(top[0]) / \(top[1]))")
            expect(top[0].minX == top[1].minX && top[0].minX == area.minX + 16,
                   "both keep the same left edge")
        }

        // 象限：点在哪个角。
        do {
            expect(PiPLayout.corner(nearest: CGPoint(x: 100, y: 1000), area: area) == .topLeft, "a point up and to the left is topLeft")
            expect(PiPLayout.corner(nearest: CGPoint(x: 1600, y: 1000), area: area) == .topRight, "up and to the right is topRight")
            expect(PiPLayout.corner(nearest: CGPoint(x: 100, y: 100), area: area) == .bottomLeft, "down and to the left is bottomLeft")
            expect(PiPLayout.corner(nearest: CGPoint(x: 1600, y: 100), area: area) == .bottomRight, "down and to the right is bottomRight")
            expect(PiPLayout.corner(nearest: CGPoint(x: area.midX, y: area.midY), area: area) == .topRight,
                   "a tie on the centre lines goes to the right and the top")
        }

        // 松手：慢慢放下的贴最近的角；甩过屏幕边就藏起来。
        do {
            let size = CGSize(width: 240, height: 135)
            let topLeft = PiPLayout.frame(corner: .topLeft, size: size, area: area)
            expect(PiPLayout.landing(frame: topLeft, velocity: .zero, area: area, screen: screen) == .corner(.topLeft),
                   "released at rest near the top-left it sticks to that corner")
            let topRight = PiPLayout.frame(corner: .topRight, size: size, area: area)
            expect(PiPLayout.landing(frame: topRight, velocity: CGVector(dx: 3000, dy: 0), area: area, screen: screen) == .stash(.right),
                   "a fast fling to the right from the middle-right hides it on the right edge")
            let lowerLeft = CGRect(x: 500, y: area.minY, width: size.width, height: size.height)
            expect(PiPLayout.landing(frame: lowerLeft, velocity: CGVector(dx: -3000, dy: 0), area: area, screen: screen) == .stash(.left),
                   "a fast fling to the left hides it on the left edge")
            expect(PiPLayout.landing(frame: lowerLeft, velocity: .zero, area: area, screen: screen) == .corner(.bottomLeft),
                   "the same frame at rest falls to the corner it is nearest (ties to the right and the top)")
        }

        // 斜着甩：按同一套惯性公式先算出中心会飘到哪，再认角。
        do {
            let size = CGSize(width: 240, height: 135)
            let topLeft = PiPLayout.frame(corner: .topLeft, size: size, area: area)
            let velocity = CGVector(dx: 1500, dy: -1500)
            let projected = CGPoint(x: topLeft.midX + CGFloat(FluidMotion.projection(velocity: Double(velocity.dx))),
                                    y: topLeft.midY + CGFloat(FluidMotion.projection(velocity: Double(velocity.dy))))
            let expected = PiPLayout.corner(nearest: projected, area: area)
            expect(expected == .bottomRight, "the projection really lands down and to the right (\(projected))")
            let landing = PiPLayout.landing(frame: topLeft, velocity: velocity, area: area, screen: screen)
            expect(landing == .corner(expected), "a diagonal fling from the top-left ends at \(expected) (got \(landing))")
            expect(landing != .corner(.topLeft), "and it does not stay where it started")
        }

        // 藏起来的整块：完全推出屏幕那一边，y 不动。
        do {
            let frame = CGRect(x: 100, y: 500, width: 240, height: 135)
            let left = PiPLayout.stashedFrame(frame, side: .left, screen: screen)
            expect(left.maxX == screen.minX, "stashed on the left the whole panel is past x=0 (got \(left))")
            expect(left.minY == frame.minY && left.size == frame.size, "and it keeps its y and size")
            let right = PiPLayout.stashedFrame(frame, side: .right, screen: screen)
            expect(right.minX == screen.maxX, "stashed on the right the whole panel is past the far edge (got \(right))")
        }

        // 边上留着的小标签：贴着那一边，靠近屏顶时被压回可见范围里。
        do {
            let high = PiPLayout.tabFrame(side: .left, midY: area.maxY - 10, area: area, screen: screen)
            expect(high.minX == screen.minX && high.width == PiPLayout.tabSize.width && high.height == PiPLayout.tabSize.height,
                   "the tab is flush with the left screen edge and tab-sized (\(high))")
            expect(high.maxY == area.maxY, "near the top it is pushed back inside the visible frame (got \(high))")
            let middle = PiPLayout.tabFrame(side: .right, midY: 500, area: area, screen: screen)
            expect(middle.maxX == screen.maxX, "on the right it is flush with the right screen edge (\(middle))")
            expect(middle.midY == 500 && middle.minY >= area.minY && middle.maxY <= area.maxY,
                   "and it is centred on the given y inside the visible frame (\(middle))")
        }

        // 选一块：面板里的框换算到窗口自己那儿（y 翻过来）。
        do {
            let viewSize = CGSize(width: 400, height: 300)
            let showing = CGRect(x: 0, y: 0, width: 800, height: 600)
            let rightHalf = PiPLayout.crop(selection: CGRect(x: 200, y: 0, width: 200, height: 300),
                                           viewSize: viewSize, showing: showing)
            expect(rightHalf == CGRect(x: 400, y: 0, width: 400, height: 600),
                   "selecting the right half of the view picks the right half of the window (got \(String(describing: rightHalf)))")
            let topHalf = PiPLayout.crop(selection: CGRect(x: 0, y: 150, width: 400, height: 150),
                                         viewSize: viewSize, showing: showing)
            expect(topHalf == CGRect(x: 0, y: 0, width: 800, height: 300),
                   "selecting the top half picks the window's top rows (got \(String(describing: topHalf)))")
        }

        // 小得像个点击：什么也不裁。
        do {
            let viewSize = CGSize(width: 400, height: 300)
            let showing = CGRect(x: 0, y: 0, width: 800, height: 600)
            expect(PiPLayout.crop(selection: CGRect(x: 100, y: 100, width: 3, height: 3),
                                  viewSize: viewSize, showing: showing) == nil,
                   "a 3×3 selection is a click, not a crop")
            expect(PiPLayout.crop(selection: CGRect(x: 100, y: 100, width: 7.5, height: 40),
                                  viewSize: viewSize, showing: showing) == nil,
                   "one side just under 8 points is still a click")
        }

        // 拖了一点点：裁出来那块不到 60×40，就围着它长到最小，并且不跑出正在显示的范围。
        do {
            let viewSize = CGSize(width: 400, height: 300)
            let showing = CGRect(x: 0, y: 0, width: 80, height: 60)   // 面板这一小块代表窗口里的 80×60 点
            let middle = PiPLayout.crop(selection: CGRect(x: 195, y: 145, width: 10, height: 10),
                                        viewSize: viewSize, showing: showing)
            expect(middle?.size == CGSize(width: 60, height: 40),
                   "a 10×10 view selection grows to the 60×40 minimum (got \(String(describing: middle)))")
            expect(middle.map { showing.contains($0) } == true,
                   "and it stays inside what the view was showing (got \(String(describing: middle)))")
            let corner = PiPLayout.crop(selection: CGRect(x: 0, y: 0, width: 10, height: 10),
                                        viewSize: viewSize, showing: showing)
            expect(corner?.size == CGSize(width: 60, height: 40) && corner.map { showing.contains($0) } == true,
                   "grown at the corner it is shifted back inside (got \(String(describing: corner)))")
        }

        // 真窗躲到哪（AX 坐标，y 向下）：推到近的那一边屏幕外，只留 2 点露着。
        do {
            let screenAX = CGRect(x: 0, y: 0, width: 1728, height: 1117)
            let left = CGRect(x: 100, y: 200, width: 400, height: 300)
            let parkedLeft = PiPLayout.parked(left, screenAX: screenAX)
            expect(parkedLeft.map { $0.maxX == 2 && $0.minY == left.minY && $0.size == left.size } == true,
                   "a window on the left half is pushed past the left edge leaving 2 points (\(String(describing: parkedLeft)))")
            let right = CGRect(x: 1200, y: 200, width: 400, height: 300)
            let parkedRight = PiPLayout.parked(right, screenAX: screenAX)
            expect(parkedRight.map { screenAX.maxX - $0.minX == 2 && $0.minY == right.minY && $0.size == right.size } == true,
                   "a window on the right half is pushed past the right edge leaving 2 points (\(String(describing: parkedRight)))")
        }

        // 旁边还有别的屏幕：推过去会整扇露在那块屏上，换另一边；两边都挨着就不让开（返回 nil）。
        do {
            let laptop = CGRect(x: 0, y: 0, width: 1728, height: 1117)
            let external = CGRect(x: 1728, y: -200, width: 2560, height: 1440)   // 右边并排、上下有重叠
            let leftOfIt = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
            let right = CGRect(x: 1200, y: 200, width: 400, height: 300)
            let moved = PiPLayout.parked(right, screenAX: laptop, others: [external])
            expect(moved.map { $0.maxX == laptop.minX + 2 && !$0.intersects(external) } == true,
                   "with a display to the right, a window on the right half steps aside past the left edge instead (\(String(describing: moved)))")
            expect(PiPLayout.parked(right, screenAX: laptop, others: [external, leftOfIt]) == nil,
                   "with displays on both sides there is nowhere to step aside")
            let above = CGRect(x: 1728, y: -1440, width: 2560, height: 1440)   // 在右上方，和这块屏上下不重叠
            let kept = PiPLayout.parked(right, screenAX: laptop, others: [above])
            expect(kept.map { laptop.maxX - $0.minX == 2 } == true,
                   "a display that does not overlap the parked window vertically does not count (\(String(describing: kept)))")
        }

        // 原处在别的屏幕上（从另一块屏拖进这块屏的角落）：躲的时候 y 夹回这块屏，露着的 2 点还在这块屏上。
        do {
            let screenAX = CGRect(x: 0, y: 0, width: 1728, height: 1117)
            let far = CGRect(x: 1200, y: -900, width: 400, height: 300)
            let parked = PiPLayout.parked(far, screenAX: screenAX)
            expect(parked.map { $0.minY == screenAX.minY && $0.intersection(screenAX).width == 2 } == true,
                   "a window whose y is off this screen is parked with its 2 points still on this screen (\(String(describing: parked)))")
            let tall = CGRect(x: 1200, y: 900, width: 400, height: 600)
            let tallParked = PiPLayout.parked(tall, screenAX: screenAX)
            expect(tallParked.map { $0.maxY == screenAX.maxY } == true,
                   "a window hanging off the bottom is lifted so it stays within the screen's height (\(String(describing: tallParked)))")
        }

        // 回到原处：标题栏还在屏幕上就原样放回，贴着可见范围的边也不挪。
        do {
            let visible = CGRect(x: 0, y: 37, width: 1728, height: 1010)
            let leftHalf = CGRect(x: 0, y: 37, width: 864, height: 1010)
            expect(PiPLayout.restored(leftHalf, areas: [visible]) == leftHalf,
                   "a window flush with the visible edges goes back exactly where it was")
            let hanging = CGRect(x: 1500, y: 900, width: 600, height: 500)
            expect(PiPLayout.restored(hanging, areas: [visible]) == hanging,
                   "a window partly off the screen but with its title bar showing also goes back as it was")
        }

        // 原处那块屏幕不在了：挪进离它最近的一块，大小不变，离边 10 点。
        do {
            let visible = CGRect(x: 0, y: 37, width: 1728, height: 1010)
            let onUnplugged = CGRect(x: 2200, y: 300, width: 900, height: 700)
            let back = PiPLayout.restored(onUnplugged, areas: [visible])
            expect(back.size == onUnplugged.size && visible.contains(back),
                   "a window from an unplugged display comes back whole onto the remaining one (\(back))")
            expect(back.maxX == visible.maxX - 10 && back.minY == onUnplugged.minY,
                   "moved in just far enough, 10 points from the edge (\(back))")
            let huge = CGRect(x: -3000, y: -2000, width: 2000, height: 1400)
            let hugeBack = PiPLayout.restored(huge, areas: [visible])
            expect(hugeBack.minX == visible.minX + 10 && hugeBack.minY == visible.minY + 10 && hugeBack.size == huge.size,
                   "a window bigger than the screen keeps its size with its title bar 10 points in (\(hugeBack))")
            let other = CGRect(x: -1920, y: 0, width: 1920, height: 1050)
            let nearOther = CGRect(x: -2600, y: 200, width: 500, height: 400)
            expect(other.contains(PiPLayout.restored(nearOther, areas: [visible, other])),
                   "with two displays left it goes to the one nearest to it")
            expect(PiPLayout.restored(onUnplugged, areas: []) == onUnplugged, "with no display at all it is left alone")
        }

        if failures == 0 {
            print("PASS: pip layout — three sizes (aspect fit, caps, minimums), corner frames and stacking, quadrants, fling landing (snap, hide on an edge), stashed frames and edge tabs, crop mapping with a minimum, where the real window parks (away from neighbouring displays), and where it goes back when its display is gone")
        } else {
            print("FAILED \(failures)")
            exit(1)
        }
    }
}
