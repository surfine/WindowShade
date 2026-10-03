import Cocoa
import ApplicationServices

extension AppDelegate {
    func foldCallbackStamp(id: CGWindowID, state: ShadeState) -> WS2FoldCallbackStamp {
        let ledger = AuthorizationService.shared.ledger
        return WS2FoldCallbackStamp(window: id, pid: state.pid,
            transaction: state.foldTransactionID, hide: state.hide.rawValue,
            boot: ledger.bootID, sessionEpoch: ledger.sessionEpoch,
            presentation: foldPresentationID, capturedAt: ProcessInfo.processInfo.systemUptime)
    }

    func foldWaiterDeliveryStamp(id: CGWindowID, transaction: UUID) -> WS2FoldCallbackStamp? {
        guard let state = shaded[id], state.foldTransactionID == transaction,
              state.lifecycleStage == .folded else { return nil }
        return foldCallbackStamp(id: id, state: state)
    }

    /// Revalidate after each asynchronous/read boundary. This is a stale-result fence,
    /// not a process-birth identity or proof that an external window mutation is atomic.
    func foldCallbackIsCurrent(_ expected: WS2FoldCallbackStamp,
                               maximumAge: TimeInterval = 2) -> Bool {
        guard let state = shaded[expected.window], state.sourceWindowID == expected.window,
              state.lifecycleStage == .folded else { return false }
        let current = foldCallbackStamp(id: expected.window, state: state)
        return expected.accepts(current: current, now: ProcessInfo.processInfo.systemUptime,
            unlocked: AuthorizationService.shared.lockState() == .unlocked, maximumAge: maximumAge)
    }

    func observeFoldHide(_ hide: HideMethod, win: AXUIElement, pid: pid_t,
                         id: CGWindowID) -> FoldVerifier.Observation {
        guard AuthorizationService.shared.lockState() == .unlocked else { return .unknown }
        if hide == .ownWindowOrderedOut {
            guard pid == getpid(), let local = ownWindow(id: id) else { return .unknown }
            return local.isVisible ? .visible : .hidden
        }
        // Intentional close has a separate positive enumeration check. Merely being
        // absent from the on-screen list is never proof of closure or minimization.
        if hide == .quickLookClosed {
            guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
            else { return .unknown }
            return list.isEmpty ? .hidden : .unknown
        }
        guard hide != .none, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              windowID(of: win) == id else { return .unknown }
        var actualPID: pid_t = 0
        guard AXUIElementGetPid(win, &actualPID) == .success, actualPID == pid else { return .unknown }
        switch hide {
        case .offscreen, .privateOffscreen:
            guard let pos = axPosition(win), let size = axSize(win),
                  pos.x.isFinite, pos.y.isFinite, size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else { return .unknown }
            return windowIsVisible(pos: pos, size: size) ? .visible : .hidden
        case .hidden: return app.isHidden ? .hidden : .visible
        case .minimized:
            guard let value = axObservedBoolAttribute(win, kAXMinimizedAttribute as String) else { return .unknown }
            return value ? .hidden : .visible
        case .privateAlpha:
            guard let alpha = PrivateSLSWindowMover.shared.windowAlpha(id: id),
                  alpha.isFinite, (0...1).contains(alpha) else { return .unknown }
            return alpha <= 0.05 ? .hidden : .visible
        case .none, .ownWindowOrderedOut, .quickLookClosed: return .unknown
        }
    }

    /// Preserve the existing recovery entry. Unknown is neither success nor permission
    /// to run a second strategy. The proxy is a manual recovery affordance, not proof.
    func retainUnconfirmedFold(id: CGWindowID, state: ShadeState) {
        guard shaded[id]?.foldTransactionID == state.foldTransactionID else { return }
        settleFoldWaiters(id: id, transaction: state.foldTransactionID, success: false)
        publishFoldObservation(id: id, state: state)
        guard shaded[id]?.foldTransactionID == state.foldTransactionID,
              AuthorizationService.shared.lockState() == .unlocked else { return }
        if let overlay = state.overlay,
           enforceOverlaySpaceInvariant(id: id, state: state, reason: "hide-unconfirmed") {
            overlay.contentView?.toolTip = "收起状态未确认，点击可尝试恢复窗口"
            revealPreparedOverlay(overlay)
        }
        quietNotice("收起状态未确认，已保留恢复入口", log: "shade: observation unknown id=\(id); recovery retained")
    }

    /// AX observers are installed on CFRunLoopGetMain. The C callback verifies that
    /// assumption; only Sendable route/stamp/string values cross the queued boundary.
    func receiveFoldAXNotification(routeID: UInt, notification: String) {
        guard let route = foldObserverRoutes[routeID], let state = shaded[route.window],
              state.foldTransactionID == route.transaction, state.pid == route.pid else { return }
        let stamp = foldCallbackStamp(id: route.window, state: state)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.foldObserverRoutes[routeID] == route,
                  self.foldCallbackIsCurrent(stamp) else { return }
            self.handleAXNotification(route.window, notification, expected: stamp)
        }
    }
}

func axObservedBoolAttribute(_ win: AXUIElement, _ attribute: String) -> Bool? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(win, attribute as CFString, &raw) == .success else { return nil }
    return ws2ObservedBoolean(raw)
}
