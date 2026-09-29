// 魔法平铺、晃一晃的执行：找这块屏上的窗口，按 MagicTiling 的规划摆好，整批记进撤销；晃一晃把别的窗口收走、再放回来。
//
// 入口：标题栏上两指张开（这扇当主角）、⌃⌘M、菜单里的“魔法平铺”（按规则挑主角）；拖着标题栏晃一晃。
// 撤销：捏合排过的任何一扇（或 ⌃⌘↑ 在铺满的那扇上）整批撤回；被人手挪过的那扇不拿旧位置覆盖。

import Cocoa

struct MagicGroup {
    struct Entry {
        let id: CGWindowID
        let element: AXUIElement
        let before: CGRect
        let after: CGRect
    }
    var entries: [Entry]
    var slideOver: CGWindowID?
    /// 侧拉的那扇在平铺之后又被单独排过：撤它时先撤那一步，整批留到下一次。
    var slideOverPlaced = false
    var tucked: [CGWindowID]

    func contains(_ id: CGWindowID) -> Bool { entries.contains { $0.id == id } || slideOver == id }
}

struct ShakeAway {
    let keeper: CGWindowID
    var tucked: [CGWindowID]
    var shaded: [CGWindowID]
}

extension TrackpadGestureController {
    /// 这块屏上能排的窗口：别的 App 的普通窗口、在屏幕上、够大、没收起、不在侧拉或刘海里，最前面的在前。
    func arrangeableWindows(on screen: NSScreen, focused: CGWindowID?) -> [(window: MagicWindow, element: AXUIElement)] {
        let own = getpid()
        let screenAX = CGRect(origin: axPosition(fromCocoaFrame: screen.frame), size: screen.frame.size)
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var candidates: [(id: CGWindowID, pid: pid_t, bounds: CGRect)] = []
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  arrangeOnlyPID.map({ $0 == pid }) ?? true,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let bounds = cgWindowBounds(info), bounds.width >= 240, bounds.height >= 160,
                  screenAX.contains(CGPoint(x: bounds.midX, y: bounds.midY)) else { continue }
            let id = CGWindowID(number.uint32Value)
            guard owner.shaded[id] == nil, !owner.slideOver.isSlideOver(id), !owner.notch.isTucked(id) else { continue }
            candidates.append((id, pid, bounds))
            if candidates.count >= 12 { break }
        }
        var pids: [pid_t] = []
        for candidate in candidates where !pids.contains(candidate.pid) { pids.append(candidate.pid) }
        let windowsByPID = Dictionary(uniqueKeysWithValues: zip(pids, concurrentAppWindows(pids)))
        var result: [(window: MagicWindow, element: AXUIElement)] = []
        for candidate in candidates {
            // 只排标准窗口：对话框、浮动面板、全屏的不动。
            guard let win = windowsByPID[candidate.pid]?.first(where: { windowID(of: $0) == candidate.id }),
                  axSubrole(win) == kAXStandardWindowSubrole as String,
                  !axBoolAttribute(win, "AXFullScreen") else { continue }
            let app = NSRunningApplication(processIdentifier: candidate.pid)
            let category = app?.bundleURL.flatMap {
                Bundle(url: $0)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
            }
            result.append((MagicWindow(id: candidate.id, pid: candidate.pid, bundleID: app?.bundleIdentifier,
                                       category: category, frame: candidate.bounds, focused: candidate.id == focused), win))
        }
        return result
    }

    /// 魔法平铺。main：谁当主角（张开手势落在哪扇上）；nil 时按规则挑（最前面那扇加分）。
    /// announce：不是手势触发的（快捷键、菜单），自己亮出浮窗说结果；手势触发时浮窗已经在了，只补一句。
    @discardableResult
    func magicTile(main preferred: CGWindowID? = nil, element: AXUIElement? = nil, announce: Bool = true) -> Bool {
        let focusedID = focusedWindow().flatMap { windowID(of: $0) }
        let anchorID = preferred ?? focusedID
        let anchorFrame = anchorID.flatMap { cgWindowInfo($0) }.flatMap { cgWindowBounds($0) }
        guard let screen = anchorFrame.flatMap({ screenForAXWindow(pos: $0.origin, size: $0.size) })
                ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return false }
        let visible = screen.visibleFrame
        let area = CGRect(origin: axPosition(fromCocoaFrame: visible), size: visible.size)
        let found = arrangeableWindows(on: screen, focused: focusedID)
        let lookup = Dictionary(found.map { ($0.window.id, $0) }, uniquingKeysWith: { first, _ in first })
        var plan = MagicTiling.plan(found.map(\.window), area: area, preferredMain: preferred,
                                    canSlideOver: owner.slideOver.notchInfo == nil, canTuck: true)
        // 放不下的窗口：屏幕左右两边都空着（没挨着别的显示器）时，往右接成一条卷轴（niri 的做法，谁都不挤）；
        // 竖屏、或者有一边挨着别的显示器（窗口停不到屏幕外）时，收进刘海；刘海也关着就原样不动。
        let canStrip = !plan.vertical && Self.neighbor(of: screen, toward: .left) == nil
            && Self.neighbor(of: screen, toward: .right) == nil
        var stripExtras: [CGWindowID] = []
        if !plan.tuck.isEmpty {
            if canStrip {
                stripExtras = plan.tuck.sorted { (lookup[$0]?.window.frame.minX ?? 0) < (lookup[$1]?.window.frame.minX ?? 0) }
                plan.tuck = []
            } else if !(NotchController.isEnabled && owner.notch.isAvailable) {
                plan.tuck = []
            }
        }
        let names = Dictionary(found.map { ($0.window.id, NSRunningApplication(processIdentifier: $0.window.pid)?.localizedName ?? "") },
                               uniquingKeysWith: { first, _ in first })
        var summary = MagicTiling.summary(plan, names: names)
        if !stripExtras.isEmpty { summary += "，右边还有 \(stripExtras.count) 扇接成卷轴（左右滑过去）" }
        guard !plan.placements.isEmpty else {
            if announce { hud.announce(.magicTile, note: summary, anchor: cocoaMousePoint(fromAXPoint: CGPoint(x: area.midX, y: area.minY + 60)), screen: screen) }
            wlog("magic-tile: nothing to arrange")
            return false
        }
        // 先把旁边的收走、聊天放进侧拉，再摆位置：摆的时候不被它们挡着。
        if let chat = plan.slideOver, let item = lookup[chat] {
            owner.slideOver.enter(item.element, id: chat, pid: item.window.pid,
                                  side: plan.vertical || plan.mainLeading ? .right : .left, on: screen)
        }
        for id in plan.tuck {
            guard let item = lookup[id] else { continue }
            owner.notch.tuck(item.element, id: id, pid: item.window.pid, landed: item.window.frame,
                             home: item.window.frame, velocity: .zero)
        }
        var entries: [MagicGroup.Entry] = []
        for placement in plan.placements {
            guard let item = lookup[placement.id] else { continue }
            let win = item.element, before = item.window.frame
            owner.cancelRestorePin(for: placement.id)
            let target = Self.fitting(ArrangeGap.apply(placement.frame, in: area), window: win, size: before.size, area: area)
            setFrame(win, target)
            var observed = CGRect(origin: axPosition(win) ?? target.origin, size: axSize(win) ?? target.size)
            // 有最小、最大尺寸的窗口没长到那一格：放在那一格正中。
            if abs(observed.width - target.width) > 4 || abs(observed.height - target.height) > 4 {
                let centered = Self.centered(observed.size, in: target, area: area)
                setAXPosition(win, centered.origin)
                observed = CGRect(origin: axPosition(win) ?? centered.origin, size: observed.size)
            }
            unlinkPartner(placement.id)
            undoRecords[placement.id] = PlacementUndo(before: before, after: observed, element: win, layout: nil, area: area)
            entries.append(.init(id: placement.id, element: win, before: before, after: observed))
        }
        // 主角放到最前（其余按原来的前后次序）。
        if let main = plan.placements.first, let item = lookup[main.id] {
            AXUIElementPerformAction(item.element, kAXRaiseAction as CFString)
            NSRunningApplication(processIdentifier: item.window.pid)?.activate()
        }
        if !stripExtras.isEmpty {
            startStrip(plan: plan, extras: stripExtras, lookup: lookup, area: area, screen: screen, entries: &entries)
        } else if strips.isActive, strips.displayID == (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value {
            strips.stop(reason: "rearranged")
        }
        magicGroup = MagicGroup(entries: entries, slideOver: plan.slideOver, tucked: plan.tuck)
        if announce, let main = plan.placements.first {
            hud.announce(.magicTile, note: summary,
                         anchor: cocoaMousePoint(fromAXPoint: CGPoint(x: main.frame.midX, y: main.frame.minY + 60)), screen: screen)
        } else {
            hud.note(summary)
        }
        wlog("magic-tile: \(summary) share=\(plan.share) vertical=\(plan.vertical) windows=\(entries.count) slide=\(plan.slideOver.map { "\($0)" } ?? "-") tucked=\(plan.tuck.count)")
        return true
    }

    /// 主角一列、旁边一列照魔法平铺排好的样子，多出来的每扇一列接在右边，停在屏幕边上。
    private func startStrip(plan: MagicPlan, extras: [CGWindowID],
                            lookup: [CGWindowID: (window: MagicWindow, element: AXUIElement)],
                            area: CGRect, screen: NSScreen, entries: inout [MagicGroup.Entry]) {
        guard let main = plan.placements.first else { return }
        let side = plan.placements.dropFirst().sorted { $0.frame.minY < $1.frame.minY }
        let mainColumn = ScrollStrip.Column(ids: [main.id], width: main.frame.width)
        var columns = [mainColumn]
        if let first = side.first {
            let sideColumn = ScrollStrip.Column(ids: side.map(\.id), shares: side.map { $0.frame.height / area.height },
                                                width: first.frame.width)
            columns = plan.mainLeading ? [mainColumn, sideColumn] : [sideColumn, mainColumn]
        }
        for id in extras {
            guard let item = lookup[id] else { continue }
            let role = MagicTiling.role(bundleID: item.window.bundleID, category: item.window.category)
            columns.append(ScrollStrip.Column(ids: [id], width: ScrollStrip.width(for: role, in: area)))
            owner.cancelRestorePin(for: id)
            unlinkPartner(id)
            undoRecords[id] = PlacementUndo(before: item.window.frame, after: item.window.frame, element: item.element, layout: nil, area: area)
            entries.append(.init(id: id, element: item.element, before: item.window.frame, after: item.window.frame))
        }
        let ids = columns.flatMap(\.ids)
        let elements = Dictionary(ids.compactMap { id in lookup[id].map { (id, $0.element) } }, uniquingKeysWith: { a, _ in a })
        let pids = Dictionary(ids.compactMap { id in lookup[id].map { (id, $0.window.pid) } }, uniquingKeysWith: { a, _ in a })
        strips.start(ScrollStrip(columns: columns, area: area), screen: screen, elements: elements, pids: pids)
        // 第一次接成卷轴：教一下怎么滑过去（教过就在浮窗里说过了）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            MainActor.assumeIsolated { _ = self?.owner.notch.teach(.stripScroll) }
        }
    }

    /// 卷轴里新接进来的窗口也记进这一批：捏合整批撤回时它回到接进来之前的样子。
    func noteJoined(_ id: CGWindowID, element: AXUIElement, before: CGRect, area: CGRect) {
        unlinkPartner(id)
        undoRecords[id] = PlacementUndo(before: before, after: before, element: element, layout: nil, area: area)
        magicGroup?.entries.append(.init(id: id, element: element, before: before, after: before))
    }

    /// 离开卷轴的窗口（被人拖走、关掉、收起）：撤回时不再管它。
    func noteLeft(_ id: CGWindowID) {
        magicGroup?.entries.removeAll { $0.id == id }
    }

    /// 整批撤回：还停在排好位置上的窗口回到原处，侧拉的退出侧拉，收进刘海的放回来。
    /// 卷轴开着时，里面的窗口是我们一直在挪的，不比位置，全部放回原处。
    func undoMagic(_ group: MagicGroup) -> Bool {
        magicGroup = nil
        let inStrip = Set(group.entries.map(\.id).filter { strips.contains($0) })
        if strips.isActive, !inStrip.isEmpty { strips.stop(reason: "undo") }
        var undone = 0
        for entry in group.entries {
            undoRecords.removeValue(forKey: entry.id)
            guard let pos = axPosition(entry.element), let size = axSize(entry.element),
                  inStrip.contains(entry.id) || sameFrame(CGRect(origin: pos, size: size), entry.after) else { continue }
            owner.cancelRestorePin(for: entry.id)
            setFrame(entry.element, entry.before)
            undone += 1
        }
        if let chat = group.slideOver, owner.slideOver.isSlideOver(chat) {
            owner.slideOver.exit(reason: "undo magic tile")
            undone += 1
        }
        for id in group.tucked where owner.notch.isTucked(id) {
            owner.notch.release(id, reason: "undo magic tile")
            undone += 1
        }
        wlog("magic-tile: undone \(undone)")
        return undone > 0
    }

    /// 晃一晃（Aero Shake）：这块屏上别的窗口收进刘海（刘海关着时收成卷帘条）；
    /// 它们还收着时，拖着同一扇再晃一下，全部放回来。
    func shake(keeping id: CGWindowID, pid: pid_t) {
        if let away = shaken, away.keeper == id,
           away.tucked.contains(where: owner.notch.isTucked) || away.shaded.contains(where: { owner.shaded[$0] != nil }) {
            shaken = nil
            for other in away.tucked where owner.notch.isTucked(other) { owner.notch.release(other, reason: "shake") }
            for other in away.shaded where owner.shaded[other] != nil { _ = owner.unshade(other) }
            wlog("shake: brought back \(away.tucked.count + away.shaded.count) around id=\(id)")
            owner.notch.announce("放回了 \(away.tucked.count + away.shaded.count) 扇", tone: .done)
            return
        }
        guard let frame = cgWindowInfo(id).flatMap({ cgWindowBounds($0) }),
              let screen = screenForAXWindow(pos: frame.origin, size: frame.size) else { return }
        let others = arrangeableWindows(on: screen, focused: id).filter { $0.window.id != id }
        guard !others.isEmpty else {
            wlog("shake: nothing else on this screen")
            owner.notch.announce("这块屏上只有它一扇", tone: .info)
            return
        }
        let toNotch = NotchController.isEnabled && owner.notch.isAvailable
        var away = ShakeAway(keeper: id, tucked: [], shaded: [])
        for (window, win) in others {
            if toNotch {
                owner.notch.tuck(win, id: window.id, pid: window.pid, landed: window.frame, home: window.frame, velocity: .zero)
                away.tucked.append(window.id)
            } else {
                owner.shade(win, window.id, trustElement: true)
                away.shaded.append(window.id)
            }
        }
        shaken = away
        owner.notch.coachUsed(.shake)
        owner.notch.announce("别的 \(others.count) 扇\(toNotch ? "收进了刘海" : "收起来了")", detail: "拖着它再晃一下，都放回来", tone: .done)
        wlog("shake: put away \(others.count) around id=\(id) into \(toNotch ? "the notch" : "strips")")
    }
}

extension TrackpadGestureController {
    /// 当前窗口移到下一块屏幕（按系统里屏幕的顺序转一圈），排法不变：半屏还是半屏、铺满还是铺满，
    /// 没排过的按它在原来那块屏上的相对位置和大小放过去。上下摆的显示器也行（左右梯子只走得到左右两边）。
    @discardableResult
    func moveToNextDisplay(backward: Bool = false) -> Bool {
        let screens = NSScreen.screens
        guard screens.count > 1 else {
            owner.notch.announce("只有一块屏幕", detail: "接上另一块显示器再用", tone: .info)
            return false
        }
        let focused = focusedWindow()
        let focusedID = focused.flatMap { windowID(of: $0) }
        if let id = focusedID, let step = awayStep(id) {
            owner.notch.announce("\(step)，\(backward ? "再移到上一块屏幕" : "再移到另一块屏幕")", tone: .problem)
            wlog("display-move: refused, id=\(id) is not in its place")
            return false
        }
        guard let win = focused, let id = focusedID, cgWindowIsCurrentlyOnScreen(id), !isSettling(id),
              let pos = axPosition(win), let size = axSize(win),
              let current = screenForAXWindow(pos: pos, size: size),
              let index = screens.firstIndex(of: current) else {
            owner.notch.announce("没有可以移的窗口", tone: .problem)
            return false
        }
        let next = screens[(index + (backward ? screens.count - 1 : 1)) % screens.count]
        func area(_ screen: NSScreen) -> CGRect {
            CGRect(origin: axPosition(fromCocoaFrame: screen.visibleFrame), size: screen.visibleFrame.size)
        }
        let from = area(current), to = area(next)
        let frame = CGRect(origin: pos, size: size)
        let target: CGRect
        if let tile = ScreenTile.all.first(where: { sameFrame(frame, $0.frame(in: from)) }) {
            target = tile.frame(in: to)
        } else if sameFrame(frame, from) || sameFrame(frame, ArrangeGap.apply(from, in: from)) {
            target = ArrangeGap.apply(to, in: to)
        } else {
            target = DisplayRefit.mapped(frame, from: from, to: to)
        }
        owner.cancelRestorePin(for: id)
        let fitted = Self.fitting(target, window: win, size: size, area: to)
        setFrame(win, fitted)
        let observed = CGRect(origin: axPosition(win) ?? fitted.origin, size: axSize(win) ?? fitted.size)
        noteReplaced(id)
        undoRecords[id] = PlacementUndo(before: frame, after: observed, element: win, layout: nil, area: to)
        hud.announce(backward ? .toLeftDisplay : .toRightDisplay, note: "移到了\(next.localizedName)",
                     anchor: cocoaMousePoint(fromAXPoint: CGPoint(x: observed.midX, y: observed.minY + 60)), screen: next)
        wlog("display-move: id=\(id) \(current.localizedName) → \(next.localizedName)")
        return true
    }
}
