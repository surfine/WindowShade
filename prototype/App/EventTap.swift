// 全局快捷键与事件 tap：注册 ⌃⌘ 快捷键、标题栏双击/三击处理、
// 事件 tap 生命周期与退避重启用。作为 AppDelegate 扩展实现。

import Cocoa
import Carbon.HIToolbox

extension AppDelegate {
    func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            if let event,
               GetEventParameter(event,
                                 EventParamName(kEventParamDirectObject),
                                 EventParamType(typeEventHotKeyID),
                                 nil,
                                 MemoryLayout<EventHotKeyID>.size,
                                 nil,
                                 &id) == noErr {
                DispatchQueue.main.async { appDelegate?.handleHotKey(id: id.id) }
            }
            return noErr
        }, 1, &eventType, nil, nil)

        func register(_ keyCode: Int, _ id: UInt32) {
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x57534844), id: id) // 'WSHD'
            RegisterEventHotKey(UInt32(keyCode), UInt32(cmdKey | controlKey),
                                hkID, GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }

        register(kVK_ANSI_C, 1)
        register(kVK_ANSI_0, 2)
        register(kVK_ANSI_P, 3)
        let digitKeys = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
        ]
        for (index, key) in digitKeys.enumerated() {
            register(key, UInt32(101 + index))
        }
    }
    func handleHotKey(id: UInt32) {
        if id == 1 {
            toggle()
            return
        }
        if id == 2 {
            focusCurrentAppCycle()
            return
        }
        if id == 3 {
            pinnedPreviewController.pinCurrentTargetPreview()
            return
        }
        guard id >= 101, id <= 109 else { return }
        expandShadedWindow(atMenuIndex: Int(id - 101))
    }
    func expandShadedWindow(atMenuIndex index: Int) {
        let entries = sortedShadedEntries()
        guard entries.indices.contains(index) else {
            quietNotice("没有对应窗口", log: "hotkey: no shaded window at index=\(index)")
            return
        }
        unshade(entries[index].0)
    }
    func scheduleEventTapReenable(delay: TimeInterval) {
        eventTapReenableWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.eventTapReenableWorkItem = nil
            if let tap = self?.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        }
        eventTapReenableWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    func handleTitleBarDoubleClick(at point: CGPoint) -> Bool {
        let startedAt = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            if elapsedMilliseconds >= 50 {
                wlog("slow: titlebar-double-click took \(elapsedMilliseconds)ms")
            }
        }
        guard titlebarDoubleClickEnabled else { return false }
        guard AXIsProcessTrusted() else { return false }
        // 先用 WindowServer 廉价排除内容区双击（选词等高频操作），
        // 避免在 tap 回调里对目标 app 做同步 AX 命中测试。
        guard pointMayLieInTitlebarBand(point) else { return false }
        // 缓存 profile 明确是"纯标准标题栏"（标题栏带里除交通灯外没有控件）时，
        // 直接走几何 fast path，跳过对目标 app 的 AX 命中测试——忙 app 的
        // AX IPC 可能拖住整个 event tap 数秒。profile 缺失/过期/含控件时返回
        // nil，继续走原有完整路径，行为与之前完全一致。
        if let hit = cachedTitlebarBlankFastPath(at: point) {
            wlog("titlebar-double-click: cached-profile fast path id=\(hit.id) at=(\(Int(point.x)),\(Int(point.y)))")
            return handleTitleBarDoubleClick(win: hit.win, point: point, source: "cached-profile-fast")
        }
        // 过了带内预过滤的点击都是"疑似标题栏双击"，低频且用户可感——
        // 此后的每个拒绝分支都要留日志，否则"有时候折叠不了"无从排查。
        let sysWide = AXUIElementCreateSystemWide()
        var elRef: AXUIElement?
        let hitErr = AXUIElementCopyElementAtPosition(sysWide, Float(point.x), Float(point.y), &elRef)
        if hitErr == .success, let el = elRef {
            // 交通灯、地址栏、搜索框、工具栏按钮等控件不抢；标签放行（见谓词注释）。
            let role = axRole(el)
            if stealsTitlebarDoubleClick(role) {
                wlog("titlebar-double-click: refused control role=\(role ?? "?") at=(\(Int(point.x)),\(Int(point.y)))")
                return false
            }
            if let win = containingWindow(el) {
                return handleTitleBarDoubleClick(win: win, point: point, source: "ax-hit")
            }
            // After Effects 等 Adobe 自绘窗口的 AX 命中元素是 AXUnknown 且没有
            // 窗口祖先（AX 树残缺）——几何回退，titlebarContains 仍会校验标题栏带。
            wlog("titlebar-double-click: no containing window role=\(role ?? "?") at=(\(Int(point.x)),\(Int(point.y))); trying geometry fallback")
            if let win = frontmostWindowContaining(point: point, requireCompatProfile: false) {
                return handleTitleBarDoubleClick(win: win, point: point, source: "geometry-after-orphan-hit")
            }
        } else if hitErr != .success {
            // 目标 app 忙时 AX 命中测试会超时/出错（此前静默死掉，正是"有时候
            // 双击没反应"的一类来源）。降级用几何回退判定标题栏。
            wlog("titlebar-double-click: ax hit-test failed err=\(hitErr.rawValue); trying geometry fallback")
            if let win = frontmostWindowContaining(point: point, requireCompatProfile: false) {
                return handleTitleBarDoubleClick(win: win, point: point, source: "geometry-after-ax-error")
            }
        }

        if let win = frontmostWindowContaining(point: point) {
            return handleTitleBarDoubleClick(win: win, point: point, source: "frontmost-geometry")
        }

        return false
    }

    // 只有缓存 profile 明确是纯标准标题栏、点击点落在命中带内且不在交通灯簇上
    // 的"确定空白区"，才允许跳过 AX 命中测试。所有不确定情况一律返回 nil，
    // 把决定交还给原有 hit test / geometry fallback 路径。
    private func cachedTitlebarBlankFastPath(at point: CGPoint)
        -> (win: AXUIElement, id: CGWindowID, pid: pid_t)? {
        guard let info = topmostOnScreenWindowInfo(at: point),
              let number = info[kCGWindowNumber as String] as? NSNumber,
              let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
              let bounds = cgWindowBounds(info) else { return nil }
        let id = CGWindowID(number.uint32Value)
        let pid = owner.int32Value
        guard let profile = ChromeProfileCache.shared
            .cachedStandardTitleBarOnlyProfile(id: id, cgSize: bounds.size) else { return nil }
        let hitH = profile.hitBarHeight
        guard point.y >= bounds.minY, point.y <= bounds.minY + hitH,
              point.x >= bounds.minX, point.x <= bounds.maxX else { return nil }
        // 避开左侧交通灯簇：标准标题栏 3 颗灯最右约 72pt，留 4pt 余量。
        guard point.x >= bounds.minX + 76 else { return nil }
        // 双击第二下时窗口已经激活：只信任前台 app 的聚焦窗口，且 windowID
        // 必须与 WindowServer 在屏窗口一致，防止误折叠同几何的兄弟窗口。
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let focused = focusedWindow(),
              windowID(of: focused) == id else { return nil }
        return (focused, id, pid)
    }

    // WindowServer 在屏列表按 z 序（前到后）返回；取第一层 layer 0 且不透明
    // 的命中窗口。纯 WindowServer 数据，不依赖目标 app 是否响应。
    private func topmostOnScreenWindowInfo(at point: CGPoint) -> [String: Any]? {
        for info in WindowListCache.shared.onScreenWindows() {
            guard let bounds = cgWindowBounds(info), bounds.contains(point) else { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard alpha > 0, layer == 0 else { continue }
            return info
        }
        return nil
    }

    func clearExpiredPendingTitlebarTripleClick() {
        if let pending = pendingTitlebarTripleClick, pending.deadline < Date() {
            pendingTitlebarTripleClick = nil
        }
    }
    func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
    func pendingTitlebarTripleClickMatches(_ pending: PendingTitlebarTripleClick,
                                                   point: CGPoint) -> Bool {
        if squaredDistance(point, pending.point) <= 96 * 96 { return true }
        guard let overlay = shaded[pending.id]?.overlay else { return false }
        let cocoaPoint = cocoaMousePoint(fromAXPoint: point)
        return overlay.frame.insetBy(dx: -28, dy: -28).contains(cocoaPoint)
    }
    var shouldBypassTitlebarEventTap: Bool {
        if let deadline = titlebarEventTapBypassUntil, deadline >= Date() {
            return true
        }
        titlebarEventTapBypassUntil = nil
        return false
    }
    func hasPendingTitlebarTripleClick(at point: CGPoint) -> Bool {
        guard titlebarDoubleClickEnabled else { return false }
        guard systemTitlebarDoubleClickAction() != .none else {
            pendingTitlebarTripleClick = nil
            return false
        }
        clearExpiredPendingTitlebarTripleClick()
        guard let pending = pendingTitlebarTripleClick,
              pending.deadline >= Date() else { return false }
        return pendingTitlebarTripleClickMatches(pending, point: point)
    }
    func titlebarContains(point: CGPoint, in win: AXUIElement) -> (CGWindowID, pid_t)? {
        guard let id = windowID(of: win), !isDesktopWidgetWindow(id: id) else { return nil }
        if overlayIDs.contains(id) { return nil }
        guard let pos = axPosition(win), let size = axSize(win) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        if isStickies(pid: pid) { return nil }
        let barH = titlebarHitHeight(of: win, id: id, winTop: pos.y, winSize: size, pid: pid)
        guard point.y >= pos.y, point.y <= pos.y + barH,
              point.x >= pos.x, point.x <= pos.x + size.width else { return nil }
        return (id, pid)
    }
    func handleTitleBarTripleClick(at point: CGPoint) -> Bool {
        let startedAt = CFAbsoluteTimeGetCurrent()
        defer {
            let elapsedMilliseconds = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
            if elapsedMilliseconds >= 50 {
                wlog("slow: titlebar-triple-click took \(elapsedMilliseconds)ms")
            }
        }
        guard titlebarDoubleClickEnabled else { return false }
        guard AXIsProcessTrusted() else { return false }
        guard systemTitlebarDoubleClickAction() != .none else {
            pendingTitlebarTripleClick = nil
            return false
        }
        clearExpiredPendingTitlebarTripleClick()

        if let pending = pendingTitlebarTripleClick,
           pending.deadline >= Date(),
           pendingTitlebarTripleClickMatches(pending, point: point) {
            pendingTitlebarTripleClick = nil
            let restored = shaded[pending.id] != nil
                ? unshadeReturningElement(pending.id, playSound: false, pinAfterRestore: false)
                : pending.element
            if let win = restored {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                    self?.performSystemTitlebarDoubleClickAction(on: win,
                                                                 id: pending.id,
                                                                 originalClickPoint: pending.point,
                                                                 source: "pending")
                }
            }
            return true
        }

        // pending 分支之后才预过滤：三击补系统动作的 pending 匹配不依赖 AX。
        guard pointMayLieInTitlebarBand(point) else { return false }

        let sysWide = AXUIElementCreateSystemWide()
        var elRef: AXUIElement?
        if AXUIElementCopyElementAtPosition(sysWide, Float(point.x), Float(point.y), &elRef) == .success,
           let el = elRef,
           !stealsTitlebarDoubleClick(axRole(el)),
           let win = containingWindow(el),
           let (id, _) = titlebarContains(point: point, in: win) {
            performSystemTitlebarDoubleClickAction(on: win, id: id,
                                                   originalClickPoint: point,
                                                   source: "ax-hit")
            return true
        }

        if let win = frontmostWindowContaining(point: point),
           let (id, _) = titlebarContains(point: point, in: win) {
            performSystemTitlebarDoubleClickAction(on: win, id: id,
                                                   originalClickPoint: point,
                                                   source: "frontmost-geometry")
            return true
        }

        return false
    }
    func titlebarSystemDoubleClickPoint(for win: AXUIElement, id: CGWindowID,
                                                originalClickPoint: CGPoint) -> CGPoint? {
        guard let pos = axPosition(win), let size = axSize(win) else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let barH = titlebarHitHeight(of: win, id: id, winTop: pos.y, winSize: size, pid: pid)
        let safeLeft = pos.x + min(max(size.width * 0.18, 120), max(120, size.width - 40))
        let safeRight = pos.x + max(40, size.width - 40)
        let x: CGFloat
        if originalClickPoint.x >= safeLeft, originalClickPoint.x <= safeRight {
            x = originalClickPoint.x
        } else {
            x = min(max(pos.x + size.width * 0.5, safeLeft), safeRight)
        }
        return CGPoint(x: x, y: pos.y + max(8, min(barH * 0.5, barH - 4)))
    }
    func postSystemTitlebarDoubleClick(at axPoint: CGPoint, id: CGWindowID, source: String) {
        let eventPoint = movePointerVisibly(to: axPoint, reason: "titlebar-triple-double-click")
        let eventSource = CGEventSource(stateID: .hidSystemState)
        titlebarEventTapBypassUntil = Date().addingTimeInterval(0.35)
        let schedule: [(TimeInterval, CGEventType, Int64)] = [
            (0.000, .leftMouseDown, 1),
            (0.026, .leftMouseUp, 1),
            (0.078, .leftMouseDown, 2),
            (0.104, .leftMouseUp, 2),
        ]
        for (delay, type, clickState) in schedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let event = CGEvent(mouseEventSource: eventSource,
                                    mouseType: type,
                                    mouseCursorPosition: eventPoint,
                                    mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: clickState)
                event?.post(tap: .cghidEventTap)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            if self?.titlebarEventTapBypassUntil ?? .distantPast < Date() {
                self?.titlebarEventTapBypassUntil = nil
            }
        }
        wlog("titlebar-triple-click: posted system double-click source=\(source) id=\(id) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y)))")
    }
    func performAXZoomForTitlebarTripleClick(on win: AXUIElement,
                                                     id: CGWindowID,
                                                     source: String) -> Bool {
        switch realWindowManagementCapability(win) {
        case .zoom, .none:
            let ok = pressAXButton(win, kAXZoomButtonAttribute as String)
            wlog("titlebar-triple-click: AX zoom source=\(source) id=\(id) ok=\(ok)")
            return ok
        case .fullScreen:
            wlog("titlebar-triple-click: exact zoom fallback required source=\(source) id=\(id) reason=fullscreen-capability")
            return false
        }
    }
    func performSystemTitlebarDoubleClickAction(on win: AXUIElement, id: CGWindowID,
                                                        originalClickPoint: CGPoint,
                                                        source: String) {
        cancelRestorePin(for: id)
        var pid: pid_t = 0
        AXUIElementGetPid(win, &pid)
        let beforePos = axPosition(win)
        let beforeSize = axSize(win)
        switch systemTitlebarDoubleClickAction() {
        case .zoom:
            if performAXZoomForTitlebarTripleClick(on: win, id: id, source: source) {
                break
            }
            raiseAXWindow(win)
            focusAXWindow(win, pid: pid)
            if let target = titlebarSystemDoubleClickPoint(for: win, id: id,
                                                           originalClickPoint: originalClickPoint) {
                postSystemTitlebarDoubleClick(at: target, id: id, source: source)
            } else {
                let ok = pressAXButton(win, kAXZoomButtonAttribute as String)
                wlog("titlebar-triple-click: fallback AX zoom source=\(source) id=\(id) ok=\(ok)")
            }
        case .minimize:
            let err = setAXMinimizedReturningError(win, true)
            if err == .success {
                wlog("titlebar-triple-click: AX minimize source=\(source) id=\(id)")
                break
            }
            raiseAXWindow(win)
            focusAXWindow(win, pid: pid)
            if let target = titlebarSystemDoubleClickPoint(for: win, id: id,
                                                           originalClickPoint: originalClickPoint) {
                postSystemTitlebarDoubleClick(at: target, id: id, source: source)
            } else {
                wlog("titlebar-triple-click: fallback AX minimize failed source=\(source) id=\(id) err=\(err)")
            }
        case .none:
            wlog("titlebar-triple-click: system none source=\(source) id=\(id)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let afterPos = axPosition(win)
            let afterSize = axSize(win)
            let before = beforePos.flatMap { p in beforeSize.map { s in "(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))" } } ?? "<unavailable>"
            let after = afterPos.flatMap { p in afterSize.map { s in "(\(Int(p.x)),\(Int(p.y)) \(Int(s.width))x\(Int(s.height)))" } } ?? "<unavailable>"
            wlog("titlebar-triple-click: frame source=\(source) id=\(id) before=\(before) after=\(after)")
        }
    }
    func frontmostWindowContaining(point: CGPoint,
                                           requireCompatProfile: Bool = true) -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        // 常规路径只对已知需要几何回退的兼容 app 生效；AX 命中测试出错的
        // 降级路径（requireCompatProfile=false）对任何前台 app 生效。
        if requireCompatProfile {
            guard needsControlPaddedChrome(pid: app.processIdentifier) else { return nil }
        }
        func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x
            let dy = a.y - b.y
            return dx * dx + dy * dy
        }
        let candidates = appWindows(pid: app.processIdentifier).compactMap { win -> (AXUIElement, CGPoint, CGSize)? in
            guard let pos = axPosition(win), let size = axSize(win),
                  size.width > 1, size.height > 1 else { return nil }
            let rect = CGRect(origin: pos, size: size)
            guard rect.contains(point) else { return nil }
            return (win, pos, size)
        }
        return candidates.min {
            let a = distanceSquared($0.1, point)
            let b = distanceSquared($1.1, point)
            return a < b
        }?.0
    }
    func handleTitleBarDoubleClick(win: AXUIElement, point: CGPoint, source: String) -> Bool {
        guard let (id, pid) = titlebarContains(point: point, in: win) else {
            // 该分支仍在 event tap 回调中；失败诊断不能再额外读一次 AXTitle，
            // 否则忙 app 的一次“未命中”会平白多消耗一个同步 IPC timeout。
            wlog("titlebar-double-click: miss source=\(source) at=(\(Int(point.x)),\(Int(point.y)))")
            return false
        }

        // 这一层仍由 CGEventTap 同步调用。命中后必须先让 tap 返回，否则 shade()
        // 的窗口隐藏、overlay 安装与菜单更新会把全局鼠标输入一起卡住（实测 151ms）。
        // 事件已经确定要被吞掉；把实际状态变更放到下一轮 main queue，不改变双击
        // 的用户可见语义，却把 tap 临界区缩到 AX 命中/几何确认本身。
        DispatchQueue.main.async { [weak self] in
            self?.performTitleBarDoubleClickAction(win: win, id: id, pid: pid,
                                                    point: point, source: source)
        }
        return true
    }
    func performTitleBarDoubleClickAction(win: AXUIElement, id: CGWindowID, pid: pid_t,
                                                   point: CGPoint, source: String) {
        logIfSlow("titlebar-double-click action id=\(id)", threshold: 0.05) {
            performTitleBarDoubleClickActionSynchronously(win: win, id: id, pid: pid,
                                                           point: point, source: source)
        }
    }
    func performTitleBarDoubleClickActionSynchronously(win: AXUIElement, id: CGWindowID,
                                                                pid: pid_t, point: CGPoint,
                                                                source: String) {
        clearExpiredPendingTitlebarTripleClick()

        wlog("titlebar-double-click: source=\(source) app=\(appDisplayName(pid: pid)) id=\(id)")
        if shaded[id] != nil {
            pendingTitlebarTripleClick = nil
            unshade(id)
        } else {
            let options = focusRejoinEntries[id] != nil ? focusShadeOptions : nil
            shade(win, id, options: options)
            if systemTitlebarDoubleClickAction() != .none, shaded[id] != nil {
                pendingTitlebarTripleClick = PendingTitlebarTripleClick(id: id,
                                                                        element: win,
                                                                        point: point,
                                                                        deadline: Date().addingTimeInterval(0.65))
            }
        }
    }
}
