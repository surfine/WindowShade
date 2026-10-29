// 排布历史（Core/ArrangementHistory.swift）：一步步撤回去、被人手挪过的不错撤、只记最近 20 步。
// 用一个假的“屏幕”模拟窗口的状态；还成不成立、怎么撤回去照 App 里（TrackpadGestures 的排布历史一节）的同一套判断。
import CoreGraphics

@main
struct ArrangementHistoryTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    struct Payload { var before: CGRect?; var after: CGRect? }

    /// 假的屏幕：窗口的外框、收起了哪些、刘海里收着哪些。
    struct World {
        var frames: [UInt32: CGRect] = [:]
        var shaded: Set<UInt32> = []
        var tucked: Set<UInt32> = []
        var history = ArrangementHistory<Payload>()

        mutating func shade(_ id: UInt32) {
            shaded.insert(id)
            history.record(.init(kind: .shade, windowID: id, payload: .init()))
        }
        mutating func tuck(_ id: UInt32) {
            // 收进刘海时窗口也是收着的（和 App 里一样）。
            shaded.insert(id); tucked.insert(id)
            history.record(.init(kind: .tuck, windowID: id, payload: .init()))
        }
        mutating func place(_ id: UInt32, _ to: CGRect) {
            let before = frames[id]
            frames[id] = to
            history.record(.init(kind: .placement, windowID: id, payload: .init(before: before, after: to)))
        }
        /// 人手拖了一下：不记进历史。
        mutating func dragByHand(_ id: UInt32, _ to: CGRect) { frames[id] = to }

        func stands(_ step: ArrangementStep<Payload>) -> Bool {
            let id = step.windowID
            switch step.kind {
            case .shade: return shaded.contains(id) && !tucked.contains(id)
            case .tuck: return tucked.contains(id)
            case .slideOver, .pictureInPicture: return false
            case .placement:
                guard let after = step.payload.after, !shaded.contains(id), let now = frames[id] else { return false }
                return now == after
            }
        }

        var latestKind: ArrangementStepKind? { history.latest(where: stands)?.kind }

        @discardableResult
        mutating func undo() -> ArrangementStep<Payload>? {
            let world = self
            guard let step = history.popLatest(where: world.stands) else { return nil }
            switch step.kind {
            case .shade: shaded.remove(step.windowID)
            case .tuck: tucked.remove(step.windowID); shaded.remove(step.windowID)
            case .placement: frames[step.windowID] = step.payload.before
            case .slideOver, .pictureInPicture: break
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

        if failures > 0 {
            print("\(failures) FAILED")
            exit(1)
        }
        print("all arrangement history tests passed")
    }
}
