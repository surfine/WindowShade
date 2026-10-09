// 拖窗口落到另一扇上：松手时指针在另一扇普通窗口上，两扇并排（谁占哪边见 MagicTiling.dropSplit）。
//
// 默认关闭（设置里“拖到窗口上并排”）。落点小岛、屏幕边（拖边平铺、侧拉、画中画）、甩一下标题栏都比它先接；
// 这里只接它们都不要的那一下。撤销：两扇各记一条排布记录并互为一对，捏合或 ⌃⌘↑ 其中一扇，两扇一起回去。
// 没有预览：目前没有能复用的半屏提示浮层，不另起一个。

import Cocoa

extension TrackpadGestureController {
    nonisolated static let dropSplitKey = "Gestures.dropSplit.enabled"

    nonisolated static var dropSplitEnabled: Bool {
        get { UserDefaults.standard.object(forKey: dropSplitKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: dropSplitKey) }
    }

    /// 松手时接住“拖到另一扇窗口上”。接住返回 true（之后的排布在窗口真能挪的时候做）；没接住返回 false，什么都没动。
    /// release、down：Cocoa 坐标。stillOpen：系统还没发“松开”（三指拖移刚抬手），App 暂时不理挪窗口，等一会儿再排。
    func dropSplit(id: CGWindowID, pid: pid_t, frameAtDown: CGRect, down: CGPoint, release: CGPoint,
                   stillOpen: Bool) -> Bool {
        guard Self.dropSplitEnabled,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(release) }),
              let info = freshWindowInfo(id), (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
              let landed = cgWindowBounds(info),
              abs(landed.width - frameAtDown.width) <= 2, abs(landed.height - frameAtDown.height) <= 2,
              // 窗口确实跟着指针动了：拖的是标题栏，不是在窗口里拖文字、文件。
              FlickClassifier.windowFollowed(
                  moved: CGVector(dx: landed.minX - frameAtDown.minX, dy: landed.minY - frameAtDown.minY),
                  pointer: CGVector(dx: release.x - down.x, dy: -(release.y - down.y))) else { return false }
        let pointer = CGPoint(x: release.x, y: coordinateBaselineY() - release.y)
        let screenAX = CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size)
        let found = arrangeableWindows(on: screen, focused: id)
        let lookup = Dictionary(found.map { ($0.window.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let dragged = lookup[id], !strips.contains(id) else { return false }
        // 指针下最上面的那扇说了算：窗口表本来就是最前面的在前。对话框、浮动面板压在上面就什么都不做。
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var stack: [MagicTiling.DropWindow] = []
        for entry in infos {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  ((entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let number = entry[kCGWindowNumber as String] as? NSNumber, let bounds = cgWindowBounds(entry),
                  bounds.contains(pointer) else { continue }
            let windowID = CGWindowID(number.uint32Value)
            // 被拖的这扇用松手时的外框（窗口表里的可能慢一拍）。
            let frame = windowID == id ? landed : bounds
            stack.append(.init(id: windowID, frame: frame, eligible: lookup[windowID] != nil))
        }
        // 不在岛上（岛上的已经在前面接走了）；侧拉和画中画的提示还亮着时也让给它们。
        let hintsActive = owner.slideOver.dropHint.isTracking(id) || owner.pip.dropHint.isTracking(id)
        let decision = MagicTiling.dropTarget(pointer: pointer, onNotchIsland: false, screen: screenAX,
                                              windows: stack, dragged: id)
        guard !hintsActive, case .window(let targetID) = decision, let target = lookup[targetID],
              !strips.contains(targetID) else { return false }
        let visible = screen.visibleFrame
        let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
        guard let split = MagicTiling.dropSplit(target: target.window.frame, pointer: pointer, area: area,
                                                gap: ArrangeGap.points) else {
            wlog("drop-split: id=\(id) onto \(targetID) skipped, a half would be too small")
            return false
        }
        let action: GestureAction
        switch split.side {
        case .left: action = .leftHalf
        case .right: action = .rightHalf
        case .top: action = .topHalf
        case .bottom: action = .bottomHalf
        }
        let job = DropSplitJob(id: id, targetID: targetID, split: split, area: area, screen: screen,
                               action: action, draggedElement: dragged.element, targetElement: target.element,
                               draggedBefore: frameAtDown, targetBefore: target.window.frame, draggedSize: landed.size)
        if stillOpen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                MainActor.assumeIsolated { self?.perform(job) }
            }
        } else {
            perform(job)
        }
        return true
    }

    private struct DropSplitJob {
        let id: CGWindowID
        let targetID: CGWindowID
        let split: MagicTiling.Split
        let area: CGRect
        let screen: NSScreen
        let action: GestureAction
        let draggedElement: AXUIElement
        let targetElement: AXUIElement
        let draggedBefore: CGRect
        let targetBefore: CGRect
        let draggedSize: CGSize
    }

    private func perform(_ job: DropSplitJob) {
        // 先让被压的那扇，再放被拖的：放的时候不被它挡着。
        let rest = place(job.targetElement, id: job.targetID, frame: job.split.target, size: job.targetBefore.size, area: job.area)
        let mine = place(job.draggedElement, id: job.id, frame: job.split.dragged, size: job.draggedSize, area: job.area)
        for (windowID, element, before, after) in [(job.targetID, job.targetElement, job.targetBefore, rest),
                                                   (job.id, job.draggedElement, job.draggedBefore, mine)] {
            noteReplaced(windowID)
            undoRecords[windowID] = PlacementUndo(before: before, after: after, element: element, layout: nil, area: job.area)
        }
        undoPartners[job.id] = job.targetID
        undoPartners[job.targetID] = job.id
        announceFlick(job.action, id: job.id, at: mine, screen: job.screen)
        wlog("drop-split: id=\(job.id) onto \(job.targetID) side=\(job.split.side)")
    }

    /// 把一扇窗摆进 frame，返回实际落下的外框。改不了大小、或者没长到那一格的，放在那一格正中。
    private func place(_ win: AXUIElement, id: CGWindowID, frame: CGRect, size: CGSize, area: CGRect) -> CGRect {
        owner.cancelRestorePin(for: id)
        let target = Self.fitting(frame, window: win, size: size, area: area)
        setFrame(win, target)
        var observed = CGRect(origin: axPosition(win) ?? target.origin, size: axSize(win) ?? target.size)
        if abs(observed.width - target.width) > 4 || abs(observed.height - target.height) > 4 {
            let centered = Self.centered(observed.size, in: target, area: area)
            setAXPosition(win, centered.origin)
            observed = CGRect(origin: axPosition(win) ?? centered.origin, size: observed.size)
        }
        return observed
    }
}
