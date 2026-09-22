import Cocoa

@main
enum ClassicStripTests {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let screenshotStrip = TitleStripView(frame: .zero)
        screenshotStrip.configureAccessibility(appName: "Finder", windowTitle: "项目资料")
        let screenshotAction = screenshotStrip.accessibilityCustomActions()!.first!
        precondition(screenshotAction.handler?() == false)
        var screenshotExpansions = 0
        screenshotStrip.onDoubleClick = { screenshotExpansions += 1 }
        precondition(screenshotAction.handler?() == true && screenshotExpansions == 1)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 28),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let strip = ClassicTitleStripView(frame: NSRect(x: 0, y: 0, width: 320, height: 28),
                                         appName: "Finder", windowTitle: "项目资料", pid: getpid())
        window.contentView = strip
        let actions = strip.accessibilityCustomActions() ?? []
        precondition(actions.map(\.name) == ["展开窗口", "缩放窗口", "关闭窗口"])
        for action in actions {
            precondition(action.handler?() == false, "Unwired actions must not report success")
        }
        var expanded = 0
        var submitted: [ClassicAction] = []
        strip.onDoubleClick = { expanded += 1 }
        strip.onAction = { submitted.append($0) }
        for action in actions { precondition(action.handler?() == true) }
        precondition(expanded == 1 && submitted == [.zoom, .close],
                     "Accessible actions must dispatch each intended operation exactly once")
        let children = strip.accessibilityChildren() ?? []
        precondition(children.count == 3, "Classic controls must expose independent accessibility children")
        precondition(children.compactMap { ($0 as? NSAccessibilityButton)?.accessibilityLabel() } == ["关闭窗口", "缩放窗口", "展开窗口"])
        submitted.removeAll()
        expanded = 0
        let buttons = children.compactMap { $0 as? NSAccessibilityButton }
        let buttonResults = buttons.map { $0.accessibilityPerformPress() }
        precondition(buttons.count == 3 && buttonResults.allSatisfy { $0 })
        precondition(expanded == 0 && submitted == [.close, .zoom, .expand],
                     "Keyboard-style button activation must dispatch each control")

        func click(x: CGFloat, upX: CGFloat? = nil) {
            func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 14),
                    modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            strip.mouseDown(with: event(.leftMouseDown, x))
            strip.mouseUp(with: event(.leftMouseUp, upX ?? x))
        }
        for width: CGFloat in [150, 320, 640] {
            strip.setFrameSize(NSSize(width: width, height: 28))
            submitted.removeAll()
            // Both ends of each independent 28pt target activate the same action.
            for x in [width - 61, width - 35] { click(x: x) }
            for x in [width - 29, width - 3] { click(x: x) }
            precondition(submitted == [.zoom, .zoom, .expand, .expand])
            submitted.removeAll()
            click(x: width - 32) // Four-point gap between targets.
            click(x: width - 48, upX: width - 16) // Release over a different action.
            precondition(submitted.isEmpty, "Gap and drag-across release must not activate")
            click(x: 16)
            precondition(submitted == [.close])
        }

        let output = URL(fileURLWithPath: ".build/appkit-tests/strip-shots", isDirectory: true)
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            strip.appearance = NSAppearance(named: appearance)
            strip.refreshPalette()
            strip.setFrameSize(NSSize(width: 320, height: 28))
            guard let bitmap = strip.bitmapImageRepForCachingDisplay(in: strip.bounds) else {
                preconditionFailure("Cannot render strip")
            }
            strip.cacheDisplay(in: strip.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])!
                .write(to: output.appendingPathComponent("classic-\(name).png"))
        }
        window.close()
        print("PASS: classic strip accessible actions, independent hit targets, release cancellation, light/dark renders")
    }
}
