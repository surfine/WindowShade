// 离屏窗口救援：折叠异常退出后的 journal 恢复与广域停车点扫描。
// 扫描在后台队列、写回在主线程；作为 AppDelegate 扩展实现。

import Cocoa

extension AppDelegate {
    struct OffscreenRescueAction {
        let win: AXUIElement
        let target: CGPoint
        let size: CGSize
    }
    func collectJournalRescueActions(targetTopLeft: CGPoint,
                                             into actions: inout [OffscreenRescueAction])
        -> (count: Int, rescuedIDs: Set<CGWindowID>) {
        let entries = shadeJournalEntries()
        guard !entries.isEmpty else { return (0, []) }

        var rescuedIDs = Set<CGWindowID>()
        var rescued = 0

        for app in NSWorkspace.shared.runningApplications {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
                  let windows = ref as? [AXUIElement] else { continue }

            for win in windows {
                guard let entry = entries.first(where: { entry in
                    guard let id = journalID(entry), !rescuedIDs.contains(id) else { return false }
                    return journalMatches(entry, app: app, win: win)
                }), let id = journalID(entry) else { continue }

                if journalString(entry, "hide") == HideMethod.privateAlpha.rawValue {
                    let alpha = Float(journalNumber(entry, "originalAlpha") ?? 1)
                    if PrivateSLSWindowMover.shared.setAlpha(id: id, alpha: max(0.05, min(alpha, 1.0))) {
                        rescuedIDs.insert(id)
                        rescued += 1
                        wlog("journal: rescued alpha id=\(id) app=\(journalString(entry, "appName"))")
                    }
                    continue
                }

                guard let pos = axPosition(win), let size = axSize(win),
                      !windowIsVisible(pos: pos, size: size) else { continue }

                let target = CGPoint(
                    x: CGFloat(journalNumber(entry, "originalX") ?? Double(targetTopLeft.x + CGFloat(rescued * 24))),
                    y: CGFloat(journalNumber(entry, "originalY") ?? Double(targetTopLeft.y + CGFloat(rescued * 24)))
                )
                let originalSize = CGSize(
                    width: CGFloat(journalNumber(entry, "originalWidth") ?? Double(size.width)),
                    height: CGFloat(journalNumber(entry, "originalHeight") ?? Double(size.height))
                )
                let safeTarget: CGPoint
                if windowIsVisible(pos: target, size: originalSize) {
                    safeTarget = target
                } else {
                    let frame = cocoaFrame(fromAXPosition: target, size: originalSize)
                    // 优先恢复到折叠时所在显示器，避免多显示器布局变化后救错屏。
                    let displayID = journalNumber(entry, "displayID").map { CGDirectDisplayID($0) }
                    safeTarget = axPosition(fromCocoaFrame: clampedFrame(frame, margin: 16,
                                                                          preferredDisplayID: displayID))
                }
                actions.append(OffscreenRescueAction(win: win, target: safeTarget, size: originalSize))
                rescuedIDs.insert(id)
                rescued += 1
                wlog("journal: rescued id=\(id) app=\(journalString(entry, "appName")) target=(\(Int(safeTarget.x)),\(Int(safeTarget.y)))")
            }
        }

        return (rescued, rescuedIDs)
    }
    func pruneRescuedJournalEntries(rescuedIDs: Set<CGWindowID>) {
        guard !rescuedIDs.isEmpty else { return }
        let entries = shadeJournalEntries()
        let filtered = entries.filter { entry in
            guard let id = journalID(entry) else { return false }
            return !rescuedIDs.contains(id)
        }
        if filtered.count != entries.count {
            saveShadeJournalEntries(filtered)
            wlog("journal: pruned \(entries.count - filtered.count) rescued entries")
        }
    }
    func collectParkedWindowRescueActions(targetTopLeft: CGPoint,
                                                  into actions: inout [OffscreenRescueAction]) -> Int {
        let parkedAxisThreshold: CGFloat = -11000
        let allWindows = WindowListCache.shared.allWindows()
        var parkedPIDs: Set<pid_t> = []
        for info in allWindows {
            guard let bounds = cgWindowBounds(info),
                  bounds.minX < parkedAxisThreshold || bounds.minY < parkedAxisThreshold,
                  let owner = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            parkedPIDs.insert(owner.int32Value)
        }

        var rescued = 0
        for pid in parkedPIDs {
            let appEl = AXUIElementCreateApplication(pid)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref) == .success,
                  let windows = ref as? [AXUIElement] else { continue }

            for win in windows {
                guard let pos = axPosition(win), let size = axSize(win) else { continue }
                // 只救我们自己的停车点附近、且确实不在任何屏幕可见区的窗口。
                guard pos.x < parkedAxisThreshold || pos.y < parkedAxisThreshold else { continue }
                guard !windowIsVisible(pos: pos, size: size) else { continue }
                actions.append(OffscreenRescueAction(
                    win: win,
                    target: CGPoint(x: targetTopLeft.x + CGFloat(rescued * 24),
                                    y: targetTopLeft.y + CGFloat(rescued * 24)),
                    size: size))
                rescued += 1
            }
        }
        return rescued
    }
    func rescueOffscreenWindows(silent: Bool) {
        guard !isRescuingOffscreenWindows else {
            isRescueQueued = true
            return
        }
        isRescuingOffscreenWindows = true
        // 屏幕几何在主线程取好（NSScreen 只在主线程访问）；AX 扫描在后台。
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            isRescuingOffscreenWindows = false
            if !silent { quietNotice("没有可用屏幕", log: "rescue: no screen") }
            return
        }
        let targetTopLeft = CGPoint(x: screen.visibleFrame.minX + 80,
                                    y: coordinateBaselineY() - (screen.visibleFrame.maxY - 80))
        let finish: (String?) -> Void = { [weak self] notice in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRescuingOffscreenWindows = false
                if let notice {
                    self.quietNotice(notice, log: "rescue: \(notice)")
                }
                if self.isRescueQueued {
                    self.isRescueQueued = false
                    self.rescueOffscreenWindows(silent: true)
                }
            }
        }
        rescueWorkQueue.async { [weak self] in
            guard let self else { return }
            guard AXIsProcessTrusted() else {
                DispatchQueue.main.async { self.showPermissionOnboardingIfNeeded(force: true) }
                finish(silent ? nil : "需要权限")
                return
            }
            var actions: [OffscreenRescueAction] = []
            let journalResult = self.collectJournalRescueActions(targetTopLeft: targetTopLeft, into: &actions)
            var rescued = journalResult.count
            if rescued == 0 {
                rescued += self.collectParkedWindowRescueActions(targetTopLeft: targetTopLeft, into: &actions)
            } else {
                wlog("rescueOffscreenWindows: journal rescued=\(rescued)")
            }
            let rescuedIDs = journalResult.rescuedIDs
            // 写回统一在主线程：若扫描期间用户折了窗口（shaded 非空），放弃这批
            // 写回，避免把刚停车的窗口又挪回可见区；journal 清理也回主线程写，
            // 避免与 shade 的 journal 写入竞争。
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !self.shaded.isEmpty {
                    wlog("rescue: shaded windows appeared during scan; skip applying \(actions.count) actions")
                    finish(nil)
                    return
                }
                self.pruneShadeJournal(reason: "rescue")
                self.pruneRescuedJournalEntries(rescuedIDs: rescuedIDs)
                for action in actions {
                    setAXSize(action.win, action.size)
                    setAXPosition(action.win, action.target)
                    raiseAXWindow(action.win)
                }
                wlog("rescueOffscreenWindows: rescued=\(rescued)")
                finish(rescued == 0 && !silent ? "没有需要救援的窗口" : nil)
            }
        }
    }
}
