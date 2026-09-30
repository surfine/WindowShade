import Cocoa
import LocalAuthentication

@main enum NotchActivityViewTests {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let items = [
            NotchActivity(id: "music", kind: .music, title: "September", subtitle: "Earth, Wind & Fire", symbol: "music.note", startedAt: 1, progress: 0.4),
            NotchActivity(id: "drop", kind: .airDrop, title: "隔空投送", subtitle: "2 个文件", symbol: "airdrop", startedAt: 1),
            NotchActivity(id: "route", kind: .route, title: "台北车站", subtitle: "预计 12 分钟 · 3.2 公里", symbol: "car.fill", startedAt: 1)
        ]
        let view = NotchActivityView(frame: NSRect(x: 0, y: 0, width: 420, height: 142))
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        view.update(items, selected: "music", expanded: true)
        view.layoutSubtreeIfNeeded()
        let viewport = view.subviews[0]
        let strip = viewport.subviews[0]
        precondition(viewport.layer?.masksToBounds == true, "Stationary viewport clips adjacent cards at rest and during a swipe")
        precondition(strip.subviews[0].frame.maxX == viewport.bounds.width && strip.subviews[1].frame.minX == viewport.bounds.width)
        view.update(items, selected: "drop", expanded: true)
        view.update(items, selected: "route", expanded: true)
        precondition((strip.layer?.animationKeys()?.count ?? 0) <= 1, "Repeated selections replace the captured spring rather than add residual motion")
        view.update(items, selected: "music", expanded: true)
        var selected = "music", selections: [String] = []
        view.onSelect = { id in
            selected = id; selections.append(id)
            view.update(items, selected: id, expanded: true)
        }
        precondition(view.visibleActivityIDs == items.map(\.id))
        _ = view.swipe(-250, touching: true, velocity: 0)
        precondition(view.isDraggingActivity && selections.isEmpty, "Tracking must not commit before lift")
        _ = view.swipe(-250, touching: false, velocity: 0, cancelled: true)
        precondition(selected == "music" && !view.isDraggingActivity, "Cancelled swipe can't select")
        _ = view.swipe(-260, touching: true, velocity: 0)
        _ = view.swipe(-260, touching: false, velocity: 0)
        precondition(selected == "drop" && selections == ["drop"], "Release selects exactly once")
        _ = view.swipe(0, touching: true, velocity: 0)
        view.update(Array(items.prefix(1)), selected: "music", expanded: true)
        _ = view.swipe(-300, touching: false, velocity: 1400)
        precondition(selections == ["drop"] && !view.isDraggingActivity, "End/removal invalidates captured gesture")
        view.update(items + items, selected: "music", expanded: false)
        precondition(view.visibleActivityIDs.count == 3, "View also enforces the three-activity limit")
        view.update([items[0]], selected: "music", expanded: false)
        precondition(!view.swipe(-200, touching: true, velocity: 0), "One activity leaves App navigation untouched")

        // Long press + moved/escaped holds are exercised on the actual production canvas.
        let canvas = NotchCanvasView(frame: NSRect(x: 0, y: 0, width: 260, height: 64))
        let holdWindow = NSWindow(contentRect: canvas.frame, styleMask: .borderless, backing: .buffered, defer: false)
        holdWindow.isReleasedWhenClosed = false; holdWindow.contentView = canvas
        var holds = 0, clicks = 0
        canvas.onLongPress = { holds += 1 }; canvas.onPress = { _ in clicks += 1 }
        func event(_ type: NSEvent.EventType, _ x: CGFloat = 30, _ count: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 20), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: holdWindow.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
        }
        func advance(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        canvas.mouseDown(with: event(.leftMouseDown))
        await advance(0.56)
        canvas.mouseUp(with: event(.leftMouseUp))
        precondition(holds == 1 && clicks == 0, "A consumed hold must not also become a click")
        canvas.mouseDown(with: event(.leftMouseDown))
        canvas.mouseDragged(with: event(.leftMouseDragged, 70))
        await advance(0.56)
        canvas.mouseUp(with: event(.leftMouseUp, 70))
        precondition(holds == 1 && clicks == 0, "Drag doesn't open hold or trigger home")
        canvas.mouseDown(with: event(.leftMouseDown))
        canvas.cancelOperation(nil)
        await advance(0.56)
        canvas.mouseUp(with: event(.leftMouseUp))
        precondition(holds == 1 && clicks == 0, "Escape cancels pending hold")
        canvas.mouseDown(with: event(.leftMouseDown, 30, 2))
        await advance(0.56)
        canvas.mouseUp(with: event(.leftMouseUp, 30, 2))
        precondition(holds == 1 && clicks == 1, "Double click remains its own interaction")

        let today = LaunchpadTodayPage()
        today.updateActivities(items)
        today.layout(size: CGSize(width: 1440, height: 900), top: 160, bottom: 860, running: [])
        let hits = today.activities.hits
        precondition(hits.count == 4 && hits.filter { $0.action == .playPause }.count == 1)
        precondition(hits.allSatisfy { CGRect(x: 0, y: 0, width: 1440, height: 900).contains($0.frame) }, "Today cards fit page")
        today.updateActivities([])
        precondition(today.activities.hits.isEmpty && !today.items.contains { if case .activity = $0.action { return true }; return false }, "Ended cards can't leave clickable targets")

        view.update(items, selected: "music", expanded: true)
        var costs: [Double] = []
        for _ in 0..<150 {
            for x in stride(from: CGFloat(0), through: -200, by: -10) {
                let start = ProcessInfo.processInfo.systemUptime
                _ = view.swipe(x, touching: true, velocity: -400)
                costs.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
            }
            _ = view.swipe(-200, touching: false, velocity: 0, cancelled: true)
        }
        costs.sort()
        let p95 = costs[Int(Double(costs.count - 1) * 0.95)]
        print(String(format: "PASS activity UI: cancellation, selection, expiry targets, hold arbitration; %d drag events p95 %.3f ms max %.3f ms (CPU handler, not GPU frame time)", costs.count, p95, costs.last!))

        // Use the production island, not the separate preview window. No evaluatePolicy is called here.
        let screen = NSScreen.main!
        let slot = NSRect(x: screen.frame.midX - 95, y: screen.frame.maxY - 32, width: 190, height: 32)
        for virtual in [false, true] {
            let panel = NotchPanel(notch: slot, virtual: virtual)
            let context = LAContext()
            let native = NotchAuthenticationView(context: context, reason: "确认你正在使用 WindowShade。")
            panel.setActivities(items, selected: "drop")
            panel.setAuthentication(native, animated: false)
            native.layoutSubtreeIfNeeded()
            precondition(panel.isAuthenticating && panel.canBecomeKey && native.window === panel)
            let shape = panel.shapeForProbe!.island
            if virtual {
                precondition(abs(shape.maxY - (slot.minY - 8)) < 0.01 && shape.height == 68,
                             "Displays without a notch use a separate capsule below the menu bar")
            } else {
                precondition(shape.maxY == slot.maxY && shape.height == slot.height + 68,
                             "Actual notch preserves the camera band and puts controls below it")
            }
            let before = panel.shapeForProbe!.island
            panel.expand(with: []); panel.setDropState(.offered)
            precondition(panel.shapeForProbe!.island == before, "Hover and drag targets must not replace authentication")
            let authCanvas = panel.contentView as! NotchCanvasView
            authCanvas.settle()
            precondition(native.window === panel, "Animation settling must keep the native authentication view mounted")
            var cancelled = false
            native.onCancel = { cancelled = true }
            authCanvas.cancelOperation(nil)
            precondition(cancelled, "Escape routes to the authentication cancellation")
            native.confirm(); precondition(native.isConfirmed)
            panel.setAuthentication(nil, animated: false)
            precondition(!panel.isAuthenticating && !panel.canBecomeKey && native.window == nil)
            let restored = authCanvas.subviews.first?.subviews.compactMap { $0 as? NotchContentView }.last
            precondition(restored?.activityView.selectedActivityID == "drop"
                         && restored?.activityView.visibleActivityIDs == items.map(\.id), "Authentication preserves activity selection and cards")
            panel.orderOut(nil); context.invalidate()
        }
        print("PASS actual/virtual notch authentication geometry, camera clearance, exclusive interaction, native view lifetime and cancellation; no authentication requested")

        for virtual in [false, true] {
            let panel = NotchPanel(notch: slot, virtual: virtual)
            let faceView = NotchFaceObservationView()
            panel.setActivities(items, selected: "route")
            panel.setInteraction(faceView, animated: false)
            faceView.layoutSubtreeIfNeeded()
            let canvas = panel.contentView as! NotchCanvasView
            canvas.settle()
            precondition(panel.isAuthenticating && faceView.window === panel)
            let contentHeight = faceView.bounds.height
            precondition(contentHeight == 68, "Face exercise uses the same camera-safe content region")
            precondition(faceView.subviews.allSatisfy { faceView.bounds.contains($0.frame) }, "Every label and cancel control fits")
            var cancelled = false
            faceView.onCancel = { cancelled = true }
            canvas.cancelOperation(nil)
            precondition(cancelled)
            panel.setInteraction(nil, animated: false)
            precondition(faceView.window == nil && !panel.isAuthenticating)
            panel.orderOut(nil)
        }
        print("PASS face-action content in real/virtual island, clipping and Escape; no camera access requested")

        for size in [CGSize(width: 1024, height: 768), CGSize(width: 2560, height: 1440), CGSize(width: 1440, height: 2560)] {
            let bounds = CGRect(origin: .zero, size: size)
            let clearance = LockOverlaySession.authenticationClearance(in: bounds)
            precondition(clearance.minY == 0 && clearance.maxY == bounds.maxY)
            precondition(clearance.contains(CGPoint(x: bounds.midX, y: 1)) && clearance.contains(CGPoint(x: bounds.midX, y: bounds.maxY - 1)))
        }
        let overlay = try! LockOverlaySession(screen: screen, bridge: nil, progress: 0.4, velocity: -0.5, preset: .shade)
        precondition(overlay.panel.ignoresMouseEvents && !overlay.panel.canBecomeKey && !overlay.panel.canBecomeMain)
        precondition(!overlay.panel.isVisible, "Constructing a layer does not show it")
        let mask = overlay.renderer.view.layer?.mask as! CAShapeLayer
        let bounds = overlay.renderer.view.bounds
        precondition(mask.fillRule == .evenOdd && mask.path!.contains(CGPoint(x: 1, y: bounds.midY), using: .evenOdd))
        precondition(!mask.path!.contains(CGPoint(x: bounds.midX, y: bounds.midY), using: .evenOdd), "Authentication remains completely transparent")
        let revision = overlay.renderer.revision
        overlay.stop(); overlay.stop()
        precondition(overlay.stopped && !overlay.panel.isVisible && overlay.renderer.revision > revision)
        print("PASS lock layer is inert, non-key, peripheral-only and clears texture revision; no system lock requested")

        // A static review artifact rendered from production view code.
        let output = URL(fileURLWithPath: ".build/appkit-tests/activity-shots", isDirectory: true)
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        view.update(items, selected: "music", expanded: true); view.layoutSubtreeIfNeeded()
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) { try! png.write(to: output.appendingPathComponent("notch-expanded.png")) }
        }
        let host = ActivityTodayShotView(frame: NSRect(x: 0, y: 0, width: 1440, height: 900)); host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.19, blue: 0.26, alpha: 1).cgColor
        today.updateActivities(items); today.layout(size: host.bounds.size, top: 130, bottom: 865, running: [])
        host.layer?.addSublayer(today.root)
        let shotWindow = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        shotWindow.isReleasedWhenClosed = false; shotWindow.contentView = host
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) { try! png.write(to: output.appendingPathComponent("today.png")) }
        }
    }
}

private final class ActivityTodayShotView: NSView { override var isFlipped: Bool { true } }
