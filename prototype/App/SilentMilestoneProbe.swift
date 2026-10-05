import Cocoa
@preconcurrency import AVFoundation

/// 同一宿主对一扇探针自己的临时窗口：提案、确认、读回真实外框。
/// 取消和换目标之后旧动作不执行。画中画零帧时窗口留在原地。
/// 不碰 Finder、浏览器、未保存的窗口，也不碰每天在用的那份 WindowShade。
/// 用法：tests/run-silent-milestone.sh
@MainActor
final class SilentMilestoneProbe {
    let owner = AppDelegate()
    private var fixture: NSRunningApplication?
    private var pipID: CGWindowID = 0
    private var failures: [String] = []

    func run() {
        Task { @MainActor in
            await exercise()
        }
    }

    private func exercise() async {
        let camera = FaceObservationSource.authorizationStatus
        print("INFO silent-milestone accessibility=\(AXIsProcessTrusted()) screenRecording=\(hasScreenRecordingPermission()) camera=\(Self.cameraLabel(camera))")
        if !AXIsProcessTrusted() {
            print("INFO silent-milestone: 这份隔离构建还没有辅助功能，打开系统设置后等待授权")
            _ = owner.ensureAccessibility()
            let trusted = await wait(120) { AXIsProcessTrusted() }
            guard trusted else {
                finish("辅助功能未授权，没有移动任何窗口")
                return
            }
            print("INFO silent-milestone accessibility=true")
        }
        guard let index = CommandLine.arguments.firstIndex(of: "--fixture"),
              CommandLine.arguments.count > index + 1 else {
            finish("需要 --fixture <path>")
            return
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        let appURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let running: NSRunningApplication
        do {
            running = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        } catch {
            finish(error.localizedDescription)
            return
        }
        fixture = running
        let pid = running.processIdentifier
        var target: AXUIElement?
        var other: AXUIElement?
        var targetID: CGWindowID = 0
        var otherID: CGWindowID = 0
        var lookup = ""
        let appeared = await wait(12) {
            let found = self.fixtureWindows(pid)
            let windows = found.windows
            target = windows.first { self.matches($0, width: 640) }
            other = windows.first { self.matches($0, width: 320) }
            if let target { targetID = self.resolveID(target, pid: pid, width: 640) ?? 0 }
            if let other { otherID = self.resolveID(other, pid: pid, width: 320) ?? 0 }
            lookup = "running=\(running.isTerminated == false) \(found.line) " + windows.map { window in
                self.describe(window)
            }.joined(separator: " | ")
            return target != nil && other != nil && targetID != 0 && otherID != 0
        }
        guard appeared, let target, let other else {
            print("INFO fixture: \(lookup)")
            finish("临时窗口没有出现")
            return
        }
        NotchController.probeSilence = true
        owner.ownsGlobalInput = false
        owner.notch.install()
        let runtime = owner.ws2Runtime
        let host = runtime.hostForSilentMilestone()
        guard await focus(target, pid: pid, id: targetID) else {
            print("INFO focus: \(describe(target)) resolved=\(targetID)")
            finish("临时窗口没有成为焦点，已停止")
            return
        }
        guard runtime.openSilent() else {
            finish("静音页没有打开 enabled=\(NotchController.isEnabled) unlocked=\(AuthorizationService.shared.lockState() == .unlocked)")
            return
        }
        guard await focus(target, pid: pid, id: targetID) else {
            host.invalidatePending()
            finish("打开静音页之后焦点不在临时窗口上，已停止")
            return
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) else {
            host.invalidatePending()
            finish("鼠标不在任何一块屏幕上")
            return
        }

        let before = liveFrame(target)
        let beforeCG = bounds(targetID)
        host.offer("window.left")
        guard host.frozenWindowIDForProbe == targetID, host.hasPendingForProbe else {
            host.invalidatePending()
            finish("冻结的不是这扇临时窗口 frozen=\(host.frozenWindowIDForProbe.map(String.init) ?? "nil")")
            return
        }
        host.confirm()
        let placed = await wait(2.5) {
            guard self.owner.gestures.observedFrameMatches(target, action: .leftHalf, screen: screen),
                  let before, let ax = self.liveFrame(target), let cg = self.bounds(targetID),
                  !Self.close(before, ax), Self.near(ax, cg) else { return false }
            return true
        }
        let after = liveFrame(target)
        let afterCG = bounds(targetID)
        let result = host.lastResult
        if placed, result?.isCompleted == true, let before, let after, let afterCG, !Self.close(before, after) {
            print("PASS place: \(Self.describe(result)) frame \(Self.rect(before)) -> \(Self.rect(after)) cg \(Self.rect(afterCG))")
        } else {
            failures.append("place result=\(Self.describe(result)) matched=\(placed) before=\(Self.rect(before)) after=\(Self.rect(after)) cg \(Self.rect(beforeCG)) -> \(Self.rect(afterCG))")
        }

        let parked = liveFrame(target)
        let parkedCG = bounds(targetID)
        host.offer("window.right")
        guard host.frozenWindowIDForProbe == targetID, host.hasPendingForProbe else {
            host.invalidatePending()
            failures.append("cancel: 提案没有冻在临时窗口上")
            report(host: host, runtime: runtime, target: target, targetID: targetID, pid: pid, screen: screen)
            return
        }
        host.offer("nav.cancel")
        host.confirm()
        try? await Task.sleep(nanoseconds: 400_000_000)
        let afterCancel = liveFrame(target)
        let afterCancelCG = bounds(targetID)
        if !host.hasPendingForProbe, let parked, let afterCancel, Self.close(parked, afterCancel),
           let parkedCG, let afterCancelCG, Self.near(parkedCG, afterCancelCG) {
            print("PASS cancel: 旧的右半屏没有执行 frame \(Self.rect(afterCancel))")
        } else {
            failures.append("cancel pending=\(host.hasPendingForProbe) frame \(Self.rect(parked)) -> \(Self.rect(afterCancel)) cg \(Self.rect(parkedCG)) -> \(Self.rect(afterCancelCG))")
        }

        let beforeSwitch = liveFrame(target)
        let beforeSwitchCG = bounds(targetID)
        let otherBefore = liveFrame(other)
        guard await focus(target, pid: pid, id: targetID) else {
            failures.append("target-change: 没法回到临时窗口")
            report(host: host, runtime: runtime, target: target, targetID: targetID, pid: pid, screen: screen)
            return
        }
        host.offer("window.right")
        guard host.frozenWindowIDForProbe == targetID, host.hasPendingForProbe else {
            host.invalidatePending()
            failures.append("target-change: 提案没有冻在临时窗口上")
            report(host: host, runtime: runtime, target: target, targetID: targetID, pid: pid, screen: screen)
            return
        }
        guard await focus(other, pid: pid, id: otherID) else {
            host.invalidatePending()
            failures.append("target-change: 第二扇临时窗口没有成为焦点")
            report(host: host, runtime: runtime, target: target, targetID: targetID, pid: pid, screen: screen)
            return
        }
        host.confirm()
        try? await Task.sleep(nanoseconds: 400_000_000)
        let afterSwitch = liveFrame(target)
        let afterSwitchCG = bounds(targetID)
        let otherAfter = liveFrame(other)
        if let beforeSwitch, let afterSwitch, Self.close(beforeSwitch, afterSwitch),
           let beforeSwitchCG, let afterSwitchCG, Self.near(beforeSwitchCG, afterSwitchCG),
           let otherBefore, let otherAfter, Self.close(otherBefore, otherAfter) {
            print("PASS target-change: 焦点换到另一扇临时窗口后，两扇都没动")
        } else {
            failures.append("target-change A \(Self.rect(beforeSwitch)) -> \(Self.rect(afterSwitch)) cg \(Self.rect(beforeSwitchCG)) -> \(Self.rect(afterSwitchCG)) B \(Self.rect(otherBefore)) -> \(Self.rect(otherAfter))")
        }

        guard await focus(target, pid: pid, id: targetID) else {
            failures.append("pip: 没法回到临时窗口")
            report(host: host, runtime: runtime, target: target, targetID: targetID, pid: pid, screen: screen)
            return
        }
        DistributedNotificationCenter.default().post(name: Notification.Name("com.windowshade.fixture.unshare"), object: nil)
        try? await Task.sleep(nanoseconds: 300_000_000)
        let home = liveFrame(target)
        let homeCG = bounds(targetID)
        pipID = targetID
        owner.pip.enter(target, id: targetID, pid: pid, on: screen)
        let started = owner.pip.isInPictureInPicture(targetID)
        var seenFrames: UInt64 = 0
        if started {
            _ = await wait(3) {
                seenFrames = max(seenFrames, owner.pip.framesForProbe(targetID))
                return seenFrames > 0 || owner.pip.isInPictureInPicture(targetID) == false
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            seenFrames = max(seenFrames, owner.pip.framesForProbe(targetID))
        }
        let afterPiP = liveFrame(target)
        let afterPiPCG = bounds(targetID)
        if !started {
            print("INFO pip-zero-frame: 未运行。这扇窗没有进入画中画")
        } else if seenFrames == 0 {
            if let home, let afterPiP, Self.close(home, afterPiP),
               let homeCG, let afterPiPCG, Self.near(homeCG, afterPiPCG) {
                print("PASS pip-zero-frame: frames=0 frame \(Self.rect(afterPiP)) cg \(Self.rect(afterPiPCG))")
            } else {
                failures.append("pip-zero-frame frames=0 frame \(Self.rect(home)) -> \(Self.rect(afterPiP)) cg \(Self.rect(homeCG)) -> \(Self.rect(afterPiPCG))")
            }
        } else {
            print("INFO pip-zero-frame: 未运行。捕获到 \(seenFrames) 帧，超时那条路径没有发生")
            owner.pip.exit(targetID, activate: false)
            _ = await wait(2) {
                guard let home, let now = liveFrame(target) else { return false }
                return Self.close(home, now)
            }
        }

        await head(host: host, runtime: runtime, target: target, targetID: targetID, pid: pid, screen: screen)
        print("INFO hardware: accessibility=\(AXIsProcessTrusted()) screenRecording=\(hasScreenRecordingPermission()) camera=\(Self.cameraLabel(camera))")
        print("INFO qualification: 未运行")
        finish(failures.isEmpty ? nil : failures.joined(separator: " | "))
    }

    private func head(host: WS2SilentHost, runtime: WS2AppRuntime, target: AXUIElement, targetID: CGWindowID, pid: pid_t, screen: NSScreen) async {
        let status = FaceObservationSource.authorizationStatus
        guard status == .authorized else {
            print("INFO head: 未运行。相机状态 \(Self.cameraLabel(status))，没有申请新权限")
            return
        }
        FaceObservationSource.startWatchingCameras()
        var device: FaceCameraDescriptor?
        _ = await wait(2) {
            device = FaceObservationSource.devices().first
            return device != nil
        }
        guard let device else {
            print("INFO head: 未运行。已授权但没有读到相机")
            return
        }
        guard await focus(target, pid: pid, id: targetID) else {
            print("INFO head: 未运行。临时窗口不在焦点上")
            return
        }
        let before = liveFrame(target)
        host.offer("window.right")
        guard host.frozenWindowIDForProbe == targetID, host.hasPendingForProbe else {
            host.invalidatePending()
            print("INFO head: 未运行。提案没有冻在临时窗口上")
            return
        }
        let media0 = CACurrentMediaTime()
        let clock0 = runtime.clock.now()
        let bag = HeadBag()
        let source = FaceObservationSource()
        do {
            try await source.start(deviceID: device.id) { observation in
                guard observation.faceCount == 1, let pitch = observation.pitch, let yaw = observation.yaw else { return }
                bag.faces += 1
                let pitchDown = -pitch * 180 / .pi
                let yawDeg = yaw * 180 / .pi
                bag.maxPitch = max(bag.maxPitch, pitchDown)
                bag.maxYaw = max(bag.maxYaw, abs(yawDeg))
                let delta = observation.observedAt - media0
                guard delta.isFinite, delta >= 0, delta < 30 else { return }
                let at = clock0.adding(UInt64(delta * 1_000_000_000))
                if let last = bag.samples.last, at.nanoseconds <= last.at.nanoseconds { return }
                bag.samples.append(WS2HeadSample(at: at, pitchDown: pitchDown, yaw: yawDeg))
            }
        } catch {
            host.invalidatePending()
            print("INFO head: 未运行。相机没有开始 \(error)")
            return
        }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        source.stop()
        let recognition = WS2HeadGesture.recognize(bag.samples)
        print("INFO head: samples=\(bag.samples.count) faces=\(bag.faces) maxPitchDown=\(String(format: "%.1f", bag.maxPitch)) maxAbsYaw=\(String(format: "%.1f", bag.maxYaw)) recognition=\(Self.recognition(recognition))")
        if recognition?.kind == .nod, let started = recognition?.startedAt {
            host.confirm(gestureBeganAt: started)
            let moved = await wait(2) {
                owner.gestures.observedFrameMatches(target, action: .rightHalf, screen: screen)
            }
            if moved, host.lastResult?.isCompleted == true {
                print("PASS head: 点头确认后右半屏 \(Self.describe(host.lastResult))")
            } else {
                failures.append("head nod did not finish result=\(Self.describe(host.lastResult)) matched=\(moved)")
            }
            return
        }
        host.invalidatePending()
        let after = liveFrame(target)
        if let before, let after, Self.close(before, after) {
            print("INFO head: 没有点头，提案已作废，窗口没动")
        } else {
            failures.append("head: 没有点头但窗口动了 \(Self.rect(before)) -> \(Self.rect(after))")
        }
    }

    private func report(host: WS2SilentHost, runtime: WS2AppRuntime, target: AXUIElement, targetID: CGWindowID, pid: pid_t, screen: NSScreen) {
        print("INFO hardware: accessibility=\(AXIsProcessTrusted()) screenRecording=\(hasScreenRecordingPermission()) camera=\(Self.cameraLabel(FaceObservationSource.authorizationStatus))")
        print("INFO qualification: 未运行")
        print("INFO head: 未运行")
        _ = (host, runtime, target, targetID, pid, screen)
        finish(failures.joined(separator: " | "))
    }

    private func focus(_ element: AXUIElement, pid: pid_t, id: CGWindowID) async -> Bool {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return await wait(4) {
            guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == pid,
                  let focused = focusedWindow(), self.identity(focused, pid: pid) == id else { return false }
            return true
        }
    }

    private func bounds(_ id: CGWindowID) -> CGRect? {
        cgWindowInfo(id).flatMap(cgWindowBounds)
    }

    private func liveFrame(_ element: AXUIElement) -> CGRect? {
        guard let pos = axPosition(element), let size = axSize(element) else { return nil }
        return CGRect(origin: pos, size: size)
    }

    private func wait(_ timeout: Double, condition: () -> Bool) async -> Bool {
        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 40_000_000)
        }
        return condition()
    }

    private func finish(_ error: String?) {
        hostCleanup()
        fixture?.terminate()
        fixture = nil
        if let error, !error.isEmpty {
            print("FAIL silent-milestone: \(error)")
        } else {
            print("PASS silent-milestone")
        }
        WindowShadeLogger.shared.flushAndClose()
        fflush(stdout)
        exit(error == nil || error?.isEmpty == true ? 0 : 1)
    }

    private func hostCleanup() {
        if pipID != 0 { owner.pip.exit(pipID, activate: false) }
        owner.notch.leases.invalidate(.disabled)
    }

    private func fixtureWindows(_ pid: pid_t) -> (windows: [AXUIElement], line: String) {
        // 不要打開 AXManualAccessibility。那會讓 AppKit 停止公布窗口。
        let app = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref)
        let windows = err == .success ? (ref as? [AXUIElement] ?? []) : []
        return (windows, "axErr=\(err.rawValue) ax=\(windows.count) \(windows.map { describe($0) }.joined(separator: " | "))")
    }

    private func matches(_ element: AXUIElement, width: CGFloat) -> Bool {
        if let id = windowID(of: element), let frame = bounds(id), abs(frame.width - width) < 2 { return true }
        if let size = axSize(element), abs(size.width - width) < 2 { return true }
        return false
    }

    private func identity(_ element: AXUIElement, pid: pid_t) -> CGWindowID? {
        if let id = windowID(of: element), id != 0 { return id }
        guard let size = axSize(element) else { return nil }
        return resolveID(element, pid: pid, width: size.width)
    }

    private func resolveID(_ element: AXUIElement, pid: pid_t, width: CGFloat) -> CGWindowID? {
        if let id = windowID(of: element), id != 0 { return id }
        let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let hits = info.filter { row in
            let owner = row[kCGWindowOwnerPID as String]
            let same = (owner as? Int32) == pid || (owner as? Int) == Int(pid) || (owner as? NSNumber)?.int32Value == pid
            guard same, let frame = cgWindowBounds(row), abs(frame.width - width) < 2 else { return false }
            return true
        }
        guard hits.count == 1, let number = hits[0][kCGWindowNumber as String] as? NSNumber else { return nil }
        return CGWindowID(number.uint32Value)
    }

    private func describe(_ element: AXUIElement) -> String {
        var id: CGWindowID = 0
        let error = _AXUIElementGetWindow(element, &id)
        let size = axSize(element)
        return "\(axTitle(element)) role=\(axRole(element) ?? "?") get=\(error.rawValue)#\(id) ax=\(size.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-")"
    }

    private static func close(_ a: CGRect, _ b: CGRect) -> Bool {
        near(a, b, slack: 2)
    }

    private static func near(_ a: CGRect, _ b: CGRect, slack: CGFloat = 8) -> Bool {
        abs(a.minX - b.minX) < slack && abs(a.minY - b.minY) < slack
            && abs(a.width - b.width) < slack && abs(a.height - b.height) < slack
    }

    private static func rect(_ value: CGRect?) -> String {
        guard let value else { return "nil" }
        return String(format: "(%.0f,%.0f %.0fx%.0f)", value.minX, value.minY, value.width, value.height)
    }

    private static func describe(_ result: SilentExecutionResult?) -> String {
        guard let result else { return "nil" }
        if case .completed(let receipt) = result {
            return "completed \(receipt.commandID) observed=\(receipt.observed)"
        }
        return "\(result) \(result.notchLine)"
    }

    private static func recognition(_ value: WS2HeadRecognition?) -> String {
        switch value?.kind {
        case .nod: return "nod"
        case .shake: return "shake"
        case nil: return "nil"
        }
    }

    private static func cameraLabel(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }
}

@MainActor
private final class HeadBag {
    var samples: [WS2HeadSample] = []
    var faces = 0
    var maxPitch = 0.0
    var maxYaw = 0.0
}
