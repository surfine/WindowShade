// AppDelegate 侧的窄适配层：把窗口浏览模块需要的“只读快照/明确目标折叠入口”
// 接到现有折叠、置顶与恢复系统上。不复制原有隐藏逻辑，也不修改恢复日志语义。

import Cocoa

extension AppDelegate {
    // MARK: 只读快照

    /// 已管理窗口快照：折叠会话 + 置顶会话，按原窗口身份合并。
    /// 只读，不暴露可修改的字典或句柄。
    func windowBrowserManagedSnapshots() -> [ManagedWindowDescriptor] {
        dispatchPrecondition(condition: .onQueue(.main))
        var byWindowID: [CGWindowID: ManagedWindowDescriptor] = [:]
        let pinnedSnapshots = pinnedPreviewController.sessionSnapshots()
        var pinnedByWindowID: [CGWindowID: PinnedPreviewSessionSnapshot] = [:]
        for snapshot in pinnedSnapshots { pinnedByWindowID[snapshot.windowID] = snapshot }

        for (id, state) in shaded {
            let operation = currentOperationState(id)
            let shadeState: WindowBrowserShadeState
            switch operation {
            case .folded: shadeState = .folded
            case .restoring: shadeState = .restoring
            case .normal, .capturing, .failed: shadeState = .folded
            }
            let pinned = pinnedByWindowID[id]
            let pinState: WindowBrowserPinState
            if let pinned {
                pinState = pinned.isSuspended ? .suspended : .running
            } else {
                pinState = .none
            }
            let logicalFrame: CGRect?
            if let overlay = state.overlay {
                logicalFrame = overlay.frame
            } else {
                logicalFrame = cocoaFrame(fromAXPosition: state.originalPosition,
                                          size: state.originalSize)
            }
            let visibility: WindowBrowserSystemVisibility
            switch state.hide {
            case .minimized: visibility = .minimized
            case .hidden: visibility = .applicationHidden
            default: visibility = .offScreen
            }
            var capabilities: WindowBrowserCapabilities = [.activate, .unfold, .close, .minimize]
            if pinned != nil {
                capabilities.formUnion([.pinPreview, .unpinPreview, .capture])
            } else if hasScreenRecordingPermission() {
                capabilities.formUnion(.pinPreview)
                if hasScreenRecordingPermission() { capabilities.formUnion(.capture) }
            }
            byWindowID[id] = ManagedWindowDescriptor(
                pid: state.pid,
                bundleIdentifier: state.bundleID,
                appName: state.appName,
                originalWindowID: id,
                title: state.title,
                logicalFrame: logicalFrame,
                systemVisibility: visibility,
                shadeState: shadeState,
                pinState: pinState,
                isMinimized: state.hide == .minimized,
                isOnScreen: false,
                placementSource: .managedFold,
                capabilities: capabilities,
                confidence: .confirmed)
        }

        for session in pinnedSnapshots where byWindowID[session.windowID] == nil {
            var capabilities: WindowBrowserCapabilities =
                [.activate, .fold, .close, .minimize, .pinPreview, .unpinPreview, .capture]
            if session.isSuspended {
                capabilities.remove(.pinPreview)
            }
            byWindowID[session.windowID] = ManagedWindowDescriptor(
                pid: session.pid,
                bundleIdentifier: session.bundleIdentifier,
                appName: session.appName,
                originalWindowID: session.windowID,
                title: session.title,
                logicalFrame: session.lastKnownFrame,
                systemVisibility: .onScreen,
                shadeState: .normal,
                pinState: session.isSuspended ? .suspended : .running,
                isMinimized: false,
                isOnScreen: true,
                placementSource: .managedPin,
                capabilities: capabilities,
                confidence: .confirmed)
        }
        return Array(byWindowID.values)
    }

    // MARK: 明确目标折叠

    /// 返回 token 表示折叠已经进入原有事务；返回 nil 表示窗口当前不处于可折叠的
    /// 稳定状态（忙/已折叠/恢复中），调用方应回 busy 或已完成。completion 只在
    /// 原折叠事务的真实终态（验证成功或回滚）到达时调用一次。
    func windowBrowserBeginFold(key: WindowKey, element: AXUIElement,
                                completion: @escaping (Bool) -> Void) -> UUID? {
        dispatchPrecondition(condition: .onQueue(.main))
        let id = key.originalWindowID
        if shaded[id] != nil { return nil }
        let state = currentOperationState(id)
        guard !shadeOperationIDs.contains(id),
              state != .capturing, state != .folded, state != .restoring else {
            return nil
        }
        var elementPID: pid_t = 0
        // 身份与窗口 ID 已由调用方在专用队列上核对（WindowBrowserTargetResolver.inspect
        // 会读 windowID(of:)）；这里只做廉价的 PID 复核，避免在主线程再做一次 AX 读取。
        guard AXUIElementGetPid(element, &elementPID) == .success,
              elementPID == key.application.pid else {
            return nil
        }
        let token = registerFoldWaiter(id: id, completion: completion)
        shade(element, id, trustElement: true)
        return token
    }

    // MARK: 目标解析

    /// 主线程只读取已经存在的会话句柄（廉价、无 IPC）；真正的 AX 核对/枚举由
    /// `WindowBrowserTargetResolver` 在专用串行队列执行。
    func windowBrowserTargetCandidate(key: WindowKey) -> AXUIElement? {
        dispatchPrecondition(condition: .onQueue(.main))
        let id = key.originalWindowID
        let pid = key.application.pid
        if let state = shaded[id], state.pid == pid { return state.element }
        return pinnedPreviewController.axElement(id: id, pid: pid)
    }

    func windowBrowserIsWindowStillPresent(key: WindowKey) -> Bool {
        let id = key.originalWindowID
        if let state = shaded[id] { return state.pid == key.application.pid }
        if pinnedPreviewController.isPreviewing(id: id) { return true }
        guard let info = cgWindowInfo(id),
              let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else {
            return false
        }
        return owner == key.application.pid
    }
}
