// 排布历史（Core/ArrangementHistory.swift）：一步步撤回去、被人手挪过的不错撤、只记最近 20 步。
// 用一个假的“屏幕”模拟窗口的状态；还成不成立、撤的时候做什么直接调 App 用的 ArrangementRules。
import CoreGraphics

@main
struct ArrangementHistoryTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    struct Payload { var before: CGRect?; var after: CGRect? }

    /// 假的屏幕：窗口的外框、收起了哪些、刘海里收着哪些、侧拉的是哪扇。
    /// 还成不成立、撤的时候做什么，直接问 App 用的同一套规则（Core 的 ArrangementRules）；
    /// 状态结束时丢步（history.forget）和 App 里收起、刘海、侧拉、画中画各自结束的地方一样。
    struct World {
        var frames: [UInt32: CGRect] = [:]
        var shaded: Set<UInt32> = []
        var tucked: Set<UInt32> = []
        var slideOver: UInt32?
        var slideOverHidden = false
        /// 排布：每扇窗最近那一次排布排好以后的外框（App 的 undoRecords，捏合撤的就是它）。
        var latestPlacement: [UInt32: CGRect] = [:]
        var history = ArrangementHistory<Payload>()
        /// 最近一次撤销 App 会做的事。
        var lastAction: ArrangementUndo?

        mutating func shade(_ id: UInt32, recorded: Bool = true) {
            shaded.insert(id)
            if recorded { history.record(.init(kind: .shade, windowID: id, payload: .init())) }
        }
        /// 别的途径展开（点卷帘条、⌃⌘1…9）：不记，但收起那一类状态结束了。
        mutating func unshadeElsewhere(_ id: UInt32) {
            shaded.remove(id); history.forget(.shade, windowID: id)
        }
        mutating func tuck(_ id: UInt32, recorded: Bool = true) {
            // 收进刘海时窗口也是收着的（和 App 里一样）。
            shaded.insert(id); tucked.insert(id)
            if recorded { history.record(.init(kind: .tuck, windowID: id, payload: .init())) }
        }
        /// 在刘海里点它放回来：不记，但刘海和收起两类状态都结束了。
        mutating func releaseElsewhere(_ id: UInt32) {
            tucked.remove(id); history.forget(.tuck, windowID: id)
            unshadeElsewhere(id)
        }
        mutating func enterSlideOver(_ id: UInt32) {
            history.record(.init(kind: .slideOver, windowID: id, payload: .init(before: frames[id])))
            slideOver = id; slideOverHidden = false
            frames[id] = CGRect(x: 1100, y: 25, width: 340, height: 600)
        }
        mutating func place(_ id: UInt32, _ to: CGRect) {
            let before = frames[id]
            frames[id] = to
            latestPlacement[id] = to
            history.record(.init(kind: .placement, windowID: id, payload: .init(before: before, after: to)))
        }
        /// 人手拖了一下：不记进历史。
        mutating func dragByHand(_ id: UInt32, _ to: CGRect) { frames[id] = to }

        func facts(_ id: UInt32) -> ArrangementWindowFacts {
            var f = ArrangementWindowFacts()
            f.shaded = shaded.contains(id); f.tucked = tucked.contains(id); f.slideOver = slideOver == id
            f.frame = shaded.contains(id) ? nil : frames[id]
            return f
        }
        func stands(_ step: ArrangementStep<Payload>) -> Bool {
            ArrangementRules.stands(step.kind, after: step.payload.after, canMove: true, facts: facts(step.windowID))
        }

        var latestKind: ArrangementStepKind? { history.latest(where: stands)?.kind }

        @discardableResult
        mutating func undo() -> ArrangementStep<Payload>? {
            let world = self
            guard let step = history.popLatest(where: world.stands) else { return nil }
            let id = step.windowID
            let action = ArrangementRules.undo(step.kind, before: step.payload.before, after: step.payload.after,
                                               canMove: true, latestPlacementAfter: latestPlacement[id])
            lastAction = action
            switch action {
            case .unshade?: unshadeElsewhere(id)
            case .releaseFromNotch?: releaseElsewhere(id)
            case .exitSlideOver(let before)?:
                slideOver = nil; slideOverHidden = false
                history.forget(.slideOver, windowID: id)
                if let before { frames[id] = before }
            case .undoLatestPlacement?:
                if let before = step.payload.before { frames[id] = before }
                latestPlacement[id] = nil
            case .moveBack(let before)?: frames[id] = before
            case .exitPictureInPicture?, nil: break
            }
            return step
        }
    }

    static let original = CGRect(x: 100, y: 100, width: 800, height: 600)
    static let leftHalf = CGRect(x: 0, y: 25, width: 720, height: 875)
    static let rightHalf = CGRect(x: 720, y: 25, width: 720, height: 875)
    static let byHand = CGRect(x: 300, y: 240, width: 800, height: 600)

    static func main() {
        // 收起 -> 收进刘海 -> 左半屏，三次撤销依次回去。
        do {
            var w = World()
            w.frames = [1: original, 2: original, 3: original]
            w.shade(1)
            w.tuck(2)
            w.place(3, leftHalf)
            expect(w.latestKind == .placement, "menu names the latest step: placement")
            expect(w.undo()?.kind == .placement && w.frames[3] == original, "undo 1: window 3 back from left half")
            expect(w.shaded.contains(1) && w.tucked.contains(2), "undo 1 leaves the earlier steps alone")
            expect(w.latestKind == .tuck, "menu then names: tuck")
            expect(w.undo()?.kind == .tuck && !w.tucked.contains(2) && !w.shaded.contains(2), "undo 2: window 2 out of the notch")
            expect(w.shaded.contains(1), "undo 2 leaves the shade alone")
            expect(w.undo()?.kind == .shade && !w.shaded.contains(1), "undo 3: window 1 rolled down")
            expect(w.latestKind == nil && w.undo() == nil, "undo 4: nothing left (menu item greyed)")
        }

        // 同一扇窗排两次：一步步回去。
        do {
            var w = World()
            w.frames = [7: original]
            w.place(7, leftHalf)
            w.place(7, rightHalf)
            w.undo()
            expect(w.frames[7] == leftHalf, "two placements: first undo goes back to left half")
            w.undo()
            expect(w.frames[7] == original, "two placements: second undo goes back to the original frame")
        }

        // 手动挪过的窗口不再被错撤：它那几步作废，撤的是更早那一步（另一扇的收起）。
        do {
            var w = World()
            w.frames = [1: original, 4: original]
            w.shade(1)
            w.place(4, leftHalf)
            w.place(4, rightHalf)
            w.dragByHand(4, byHand)
            expect(w.latestKind == .shade, "moved by hand: menu skips its placements and names the shade")
            let undone = w.undo()
            expect(undone?.kind == .shade && undone?.windowID == 1, "moved by hand: undo rolls down window 1 instead")
            expect(w.frames[4] == byHand, "moved by hand: window 4 stays where the user put it")
            expect(w.history.isEmpty, "moved by hand: its stale steps are dropped together")
        }

        // 只是看一眼（菜单重建）不丢任何一步：动作还在半路时不成立，过一会儿又成立。
        do {
            var w = World()
            w.frames = [5: original]
            w.history.record(.init(kind: .tuck, windowID: 5, payload: .init()))
            expect(w.latestKind == nil, "tuck still in flight: menu shows nothing to undo")
            expect(w.history.steps.count == 1, "looking does not drop the in-flight step")
            w.tucked.insert(5); w.shaded.insert(5)
            expect(w.latestKind == .tuck, "tuck landed: menu names it")
        }

        // 只记最近 20 步。
        do {
            var w = World()
            w.frames = [9: original]
            for index in 0..<25 {
                w.place(9, CGRect(x: CGFloat(index), y: 0, width: 400, height: 400))
            }
            expect(w.history.steps.count == ArrangementHistory<Payload>.capacity && ArrangementHistory<Payload>.capacity == 20,
                   "capacity: keeps the latest 20 steps")
            expect(w.history.steps.first?.payload.after?.minX == 5, "capacity: the oldest 5 are dropped")
        }

        // 换屏排回：改写还停在原处的那一步，不算新的一步。
        do {
            var h = ArrangementHistory<Payload>()
            h.record(.init(kind: .placement, windowID: 3, payload: .init(before: original, after: leftHalf)))
            h.update { step in
                if step.windowID == 3, step.payload.after == leftHalf { step.payload.after = rightHalf }
            }
            expect(h.steps.count == 1 && h.steps[0].payload.after == rightHalf, "refit rewrites the step in place")
        }

        // 撤过的那一步被别的途径放回来、之后经不记的路径（全部收进刘海）又进刘海：不再把旧的那一步当成还成立。
        do {
            var w = World()
            w.frames = [1: original, 2: original]
            w.tuck(1)
            w.releaseElsewhere(1)
            w.tuck(1, recorded: false)
            w.tuck(2, recorded: false)
            expect(w.latestKind == nil && w.undo() == nil, "released elsewhere, tucked again by tuck-all: old tuck step is not offered")
            expect(w.tucked == [1, 2], "released elsewhere: tuck-all batch is left alone")
        }

        // 同理：收起后被别的途径展开，专注又把它收起：菜单不提旧的收起。
        do {
            var w = World()
            w.frames = [1: original]
            w.shade(1)
            w.unshadeElsewhere(1)
            w.shade(1, recorded: false)
            expect(w.latestKind == nil, "unshaded elsewhere, shaded again by focus: old shade step is not offered")
        }

        // 侧拉后收在屏幕边外：撤销回到侧拉之前的地方，不留在靠边处。
        do {
            var w = World()
            w.frames = [6: original]
            w.enterSlideOver(6)
            w.slideOverHidden = true
            expect(w.latestKind == .slideOver, "slide over (hidden): menu names it")
            w.undo()
            expect(w.lastAction == .exitSlideOver(backTo: original) && w.frames[6] == original && w.slideOver == nil,
                   "slide over (hidden): undo goes back to the frame before Slide Over")
        }

        // 排布成立的规则（App 用的同一套）：差 4 点以内算没动；拿不到窗口、离开时被排开、在侧拉里、读不到外框都不算。
        do {
            var f = ArrangementWindowFacts()
            f.frame = leftHalf.offsetBy(dx: 4, dy: -4)
            expect(ArrangementRules.stands(.placement, after: leftHalf, canMove: true, facts: f), "placement: within 4 pt still stands")
            f.frame = leftHalf.offsetBy(dx: 5, dy: 0)
            expect(!ArrangementRules.stands(.placement, after: leftHalf, canMove: true, facts: f), "placement: moved 5 pt by hand does not stand")
            f.frame = leftHalf
            expect(!ArrangementRules.stands(.placement, after: leftHalf, canMove: false, facts: f), "placement: no window element does not stand")
            var away = f; away.awayArranged = true
            expect(!ArrangementRules.stands(.placement, after: leftHalf, canMove: true, facts: away), "placement: arranged away does not stand")
            var slide = f; slide.slideOver = true
            expect(!ArrangementRules.stands(.placement, after: leftHalf, canMove: true, facts: slide), "placement: in Slide Over does not stand")
            var unread = f; unread.frame = nil
            expect(!ArrangementRules.stands(.placement, after: leftHalf, canMove: true, facts: unread), "placement: unreadable frame does not stand")
            expect(ArrangementRules.undo(.placement, before: original, after: leftHalf, canMove: true, latestPlacementAfter: leftHalf) == .undoLatestPlacement,
                   "placement undo: the window's latest placement goes the pinch way")
            expect(ArrangementRules.undo(.placement, before: original, after: leftHalf, canMove: true, latestPlacementAfter: rightHalf) == .moveBack(original),
                   "placement undo: an older placement moves straight back")
            expect(ArrangementRules.undo(.tuck, before: nil, after: nil, canMove: false, latestPlacementAfter: nil) == .releaseFromNotch,
                   "tuck undo: releases from the notch")
        }

        if failures > 0 {
            print("\(failures) FAILED")
            exit(1)
        }
        print("all arrangement history tests passed")
    }
}
