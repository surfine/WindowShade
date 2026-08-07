// 恢复日志（Recovery Journal）：折叠状态的持久化、匹配与生命周期标记。
// 数据层为 AppDelegate 扩展方法；离屏救援编排在 Recovery/Rescue.swift。
//
// crash consistency：任何可能让窗口长期不可见的操作之前，调用方必须先写一条
// stage=preparing 的 durable intent（recordShadeRecoveryIntent），隐藏动作成功
// 并验证后再更新为 stage=folded（recordShadeJournal）。这样进程在「已隐藏但
// journal 未记录」的窗口期被杀，重启后的 rescue 仍能根据 intent 找回窗口。

import Cocoa

extension AppDelegate {
    func shadeJournalEntries() -> [[String: Any]] {
        UserDefaults.standard.array(forKey: shadeJournalDefaultsKey) as? [[String: Any]] ?? []
    }

    func saveShadeJournalEntries(_ entries: [[String: Any]]) {
        if entries.isEmpty {
            UserDefaults.standard.removeObject(forKey: shadeJournalDefaultsKey)
        } else {
            UserDefaults.standard.set(entries, forKey: shadeJournalDefaultsKey)
        }
    }

    func journalNumber(_ entry: [String: Any], _ key: String) -> Double? {
        if let n = entry[key] as? NSNumber { return n.doubleValue }
        if let d = entry[key] as? Double { return d }
        if let i = entry[key] as? Int { return Double(i) }
        return nil
    }

    func journalString(_ entry: [String: Any], _ key: String) -> String {
        entry[key] as? String ?? ""
    }

    func journalID(_ entry: [String: Any]) -> CGWindowID? {
        guard let raw = journalNumber(entry, "id") else { return nil }
        return CGWindowID(max(0, Int(raw)))
    }

    func pruneShadeJournal(reason: String) {
        let now = Date().timeIntervalSince1970
        let entries = shadeJournalEntries()
        let filtered = entries.filter { entry in
            guard journalID(entry) != nil else { return false }
            let created = journalNumber(entry, "createdAt") ?? journalNumber(entry, "updatedAt") ?? now
            return now - created <= shadeJournalMaxAge
        }
        if filtered.count != entries.count {
            saveShadeJournalEntries(filtered)
            wlog("journal: pruned \(entries.count - filtered.count) stale entries reason=\(reason)")
        }
    }

    func recordShadeJournal(id: CGWindowID, win: AXUIElement, hide: HideMethod,
                                    pid: pid_t, bundleID: String, appName: String,
                                    title: String, originalPosition: CGPoint,
                                    originalSize: CGSize, mode: ShadeAppearanceMode,
                                    policy: ShadePolicy, planReason: String,
                                    stage: ShadeLifecycleStage,
                                    sourceDisplayID: CGDirectDisplayID?,
                                    sourceSpaceID: UInt64?) {
        guard hide == .offscreen || hide == .privateOffscreen || hide == .privateAlpha else {
            clearShadeJournal(id: id)
            return
        }

        // 折叠事务的正常落点：provisional intent（preparing）已被调用方在隐藏
        // 前写入；这里把同一条 entry 更新为真正的隐藏方式与停车位置，而不是
        // 新建，保留 createdAt 以维持 14 天过期语义。
        let parked = cgWindowInfo(id)
            .flatMap { cgWindowBounds($0) }
            .map { CGPoint(x: $0.minX, y: $0.minY) }
            ?? axPosition(win)
            ?? offscreen
        let now = Date().timeIntervalSince1970
        var entries = shadeJournalEntries().filter { journalID($0) != id }
        let existingCreatedAt = shadeJournalEntries().first { journalID($0) == id }
            .flatMap { journalNumber($0, "createdAt") }
        var entry: [String: Any] = [
            "schemaVersion": 3,
            "id": Int(id),
            "pid": Int(pid),
            "bundleID": bundleID,
            "appName": appName,
            "title": title,
            "hide": hide.rawValue,
            "mode": mode.rawValue,
            "policy": shadePolicyDescription(policy),
            "planReason": planReason,
            "stage": stage.rawValue,
            "state": stage.rawValue,
            "originalX": Double(originalPosition.x),
            "originalY": Double(originalPosition.y),
            "originalWidth": Double(originalSize.width),
            "originalHeight": Double(originalSize.height),
            "parkedX": Double(parked.x),
            "parkedY": Double(parked.y),
            "originalAlpha": Double(privateAlphaOriginalValues[id] ?? 1),
            "createdAt": existingCreatedAt ?? now,
            "updatedAt": now
        ]
        if let displayID = sourceDisplayID { entry["displayID"] = Double(displayID) }
        if let spaceID = sourceSpaceID { entry["spaceID"] = Double(spaceID) }
        entries.append(entry)
        saveShadeJournalEntries(entries)
        wlog("journal: record \(hide.rawValue) id=\(id) app=\(appName) parked=(\(Int(parked.x)),\(Int(parked.y)))")
    }

    // 折叠动作前的 durable intent：在窗口可能被移到屏幕外/设透明之前落盘，
    // 供崩溃后 rescue 恢复。隐藏成功后会由 recordShadeJournal 更新为 folded；
    // 若最终采用了不需要离屏救援的隐藏方式（minimize/hidden 等），
    // recordShadeJournal 会清掉这条 intent。
    func recordShadeRecoveryIntent(id: CGWindowID, pid: pid_t, bundleID: String,
                                   appName: String, title: String,
                                   originalPosition: CGPoint, originalSize: CGSize,
                                   sourceDisplayID: CGDirectDisplayID?,
                                   sourceSpaceID: UInt64?) {
        let now = Date().timeIntervalSince1970
        var entries = shadeJournalEntries().filter { journalID($0) != id }
        var entry: [String: Any] = [
            "schemaVersion": 3,
            "id": Int(id),
            "pid": Int(pid),
            "bundleID": bundleID,
            "appName": appName,
            "title": title,
            "hide": HideMethod.none.rawValue,
            "stage": ShadeLifecycleStage.preparing.rawValue,
            "state": ShadeLifecycleStage.preparing.rawValue,
            "originalX": Double(originalPosition.x),
            "originalY": Double(originalPosition.y),
            "originalWidth": Double(originalSize.width),
            "originalHeight": Double(originalSize.height),
            "createdAt": now,
            "updatedAt": now
        ]
        if let displayID = sourceDisplayID { entry["displayID"] = Double(displayID) }
        if let spaceID = sourceSpaceID { entry["spaceID"] = Double(spaceID) }
        entries.append(entry)
        saveShadeJournalEntries(entries)
        wlog("journal: intent id=\(id) app=\(appName) preparing")
    }

    func updateShadeJournal(id: CGWindowID, reason: String,
                                    _ mutate: (inout [String: Any]) -> Void) {
        var entries = shadeJournalEntries()
        guard let index = entries.firstIndex(where: { journalID($0) == id }) else { return }
        var entry = entries[index]
        mutate(&entry)
        entry["updatedAt"] = Date().timeIntervalSince1970
        entry["lastReason"] = reason
        entries[index] = entry
        saveShadeJournalEntries(entries)
    }

    func markShadeJournalStage(id: CGWindowID, _ stage: ShadeLifecycleStage,
                                       reason: String) {
        updateShadeJournal(id: id, reason: reason) { entry in
            entry["stage"] = stage.rawValue
            entry["state"] = stage.rawValue
        }
    }

    func markShadeLifecycle(id: CGWindowID, _ stage: ShadeLifecycleStage,
                                    reason: String) {
        if var state = shaded[id] {
            if state.lifecycleStage == stage {
                markShadeJournalStage(id: id, stage, reason: reason)
                return
            }
            let oldStage = state.lifecycleStage
            state.lifecycleStage = stage
            shaded[id] = state
            wlog("lifecycle: id=\(id) \(oldStage.rawValue) -> \(stage.rawValue) reason=\(reason)")
        } else {
            wlog("lifecycle: id=\(id) -> \(stage.rawValue) reason=\(reason)")
        }
        markShadeJournalStage(id: id, stage, reason: reason)
    }
    func clearShadeJournal(id: CGWindowID) {
        let entries = shadeJournalEntries()
        let filtered = entries.filter { journalID($0) != id }
        if filtered.count != entries.count {
            saveShadeJournalEntries(filtered)
            wlog("journal: clear id=\(id)")
        }
    }

    func syncRestoreJournal(id: CGWindowID, fromOverlayFrame frame: NSRect,
                                    restoredSize: CGSize? = nil) {
        var entries = shadeJournalEntries()
        guard let index = entries.firstIndex(where: { journalID($0) == id }) else { return }

        let pos = axPosition(fromCocoaFrame: frame)
        var entry = entries[index]
        entry["originalX"] = Double(pos.x)
        entry["originalY"] = Double(pos.y)
        if let restoredSize {
            entry["originalWidth"] = Double(restoredSize.width)
            entry["originalHeight"] = Double(restoredSize.height)
        }
        entry["updatedAt"] = Date().timeIntervalSince1970
        entries[index] = entry
        saveShadeJournalEntries(entries)
        wlog("journal: sync id=\(id) restore=(\(Int(pos.x)),\(Int(pos.y)))")
    }

    func journalMatches(_ entry: [String: Any], app: NSRunningApplication,
                                win: AXUIElement) -> Bool {
        guard Int(app.processIdentifier) == Int(journalNumber(entry, "pid") ?? -1) else { return false }
        let expectedBundle = journalString(entry, "bundleID")
        if !expectedBundle.isEmpty, app.bundleIdentifier != expectedBundle { return false }

        // 匹配优先级：pid -> bundleID -> title -> windowID。
        // 窗口 ID 在 app 重启后可能被复用，先按稳定属性（标题）匹配，
        // 窗口 ID 只作最后兜底；标题为空时必须有 ID 精确匹配才视为同一窗口，
        // 避免把同 app 的其他窗口误救。
        let expectedTitle = cleanDisplayTitle(journalString(entry, "title"))
        if !expectedTitle.isEmpty, cleanDisplayTitle(axTitle(win)) == expectedTitle {
            return true
        }
        if let expectedID = journalID(entry), let currentID = windowID(of: win), expectedID == currentID {
            return true
        }
        return false
    }
}
