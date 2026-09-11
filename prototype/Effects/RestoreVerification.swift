import Cocoa

/// No input/focus changes here: observation and journal acknowledgement only.
extension AppDelegate {
  func observeRestoredWindow(_ state: ShadeState, to pos: CGPoint) -> RestoreObservation {
    guard let app = NSRunningApplication(processIdentifier: state.pid), !app.isTerminated else {
      return .closed
    }
    let element = resolvedWindowElement(for: state)
    guard let info = cgWindowInfo(state.sourceWindowID),
      (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == state.pid
    else {
      var role: CFTypeRef?
      let error = AXUIElementCopyAttributeValue(state.element, kAXRoleAttribute as CFString, &role)
      return error == .invalidUIElement ? .closed : .pending
    }
    guard windowID(of: element) == state.sourceWindowID,
      !app.isHidden, !axBoolAttribute(element, kAXMinimizedAttribute as String),
      (info[kCGWindowIsOnscreen as String] as? Bool) == true,
      ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
      let bounds = cgWindowBounds(info), let size = axSize(element),
      let actual = axPosition(element)
    else { return .pending }
    let safe = safeRestorePosition(for: state, desired: pos)
    let expected = CGRect(origin: safe, size: state.originalSize)
    let ax = CGRect(origin: actual, size: size)
    let tolerates: (CGRect) -> Bool = { frame in
      abs(frame.minX - expected.minX) <= 2 && abs(frame.minY - expected.minY) <= 2
        && abs(frame.width - expected.width) <= 2 && abs(frame.height - expected.height) <= 2
    }
    return tolerates(ax) && tolerates(bounds) ? .visible : .pending
  }

  func verifyRestoredWindow(
    _ state: ShadeState, to position: CGPoint, completion: ((Bool) -> Void)?
  ) {
    let id = state.sourceWindowID
    let token = UUID()
    duoRestoreVerificationTokens[id] = token
    markShadeJournalStage(id: id, .restoring, reason: "awaiting-restore-verification")
    // Keep the last durable position current even when the strip was dragged.
    updateShadeJournal(id: id, reason: "restore-target") { entry in
      let safe = safeRestorePosition(for: state, desired: position)
      entry["originalX"] = Double(safe.x)
      entry["originalY"] = Double(safe.y)
    }
    RestoreVerifier(
      now: CACurrentMediaTime,
      schedule: { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
      }, isCurrent: { [weak self] in self?.duoRestoreVerificationTokens[id] == token },
      observe: { [weak self] in self?.observeRestoredWindow(state, to: position) ?? .pending },
      acknowledge: { [weak self] in self?.clearShadeJournal(id: id) },
      completion: { [weak self] success in
        self?.duoRestoreVerificationTokens.removeValue(forKey: id)
        completion?(success)
        if !success {
          wlog(
            "duo: restoration not visible; recovery record retained unless closure confirmed id=\(id)"
          )
        }
      }
    ).start()
  }
}
