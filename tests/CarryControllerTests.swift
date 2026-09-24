// Appended to Carry.swift by the test runner. Only fixture panels are created;
// source status is injected, and no original app/window receives an AX write.
@main struct CarryControllerTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let ids = (1...20).map { CGWindowID($0) }
        for width: CGFloat in [200, 320, 640, 800, 1440, 2560] {
            for origin: CGFloat in [-2560, 0, 700] {
                for count in [0, 1, 2, 5, 20] {
                    let bounds = CGRect(x: origin, y: -300, width: width, height: 700)
                    let input = Array(ids.prefix(count))
                    let plan = CarryShelfLayout.compute(ids: input, visibleFrame: bounds,
                                                        promotedID: input.last)
                    let frames = plan.strips.map(\.frame) + [plan.moreFrame].compactMap { $0 }
                    precondition(Set(plan.strips.map(\.id) + plan.overflow) == Set(input), "Every window remains reachable")
                    precondition(plan.strips.count + plan.overflow.count == input.count, "No duplicated slots")
                    precondition(plan.overflow.isEmpty || plan.moreFrame != nil, "Overflow always has an entrance")
                    for (index, frame) in frames.enumerated() {
                        precondition(bounds.contains(frame), "All controls stay inside visible screen")
                        precondition(frame.width >= 40 && frame.height == 30)
                        for other in frames.dropFirst(index + 1) {
                            precondition(!frame.intersects(other), "Controls never overlap")
                        }
                    }
                    if let selected = input.last {
                        precondition(plan.strips.first?.id == selected, "Selected window gets a visible strip")
                    }
                }
            }
        }
        let wide = CarryShelfLayout.compute(ids: [1, 2], visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 700))
        precondition(wide.moreFrame == nil && wide.strips[0].frame == CGRect(x: 730, y: 662, width: 260, height: 30))
        CarryController.verifyOverflow()
        print("CarryControllerTests passed")
    }
}

extension CarryController {
    @MainActor static func verifyOverflow() {
        let owner = AppDelegate()
        let controller = CarryController(owner: owner)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let oldOverride = GlanceController.probeOverride
        GlanceController.probeOverride = false // selection test cannot start screen capture
        defer { GlanceController.probeOverride = oldOverride }
        var width: CGFloat = 900
        var visible: Set<CGWindowID> = []
        var gone: Set<CGWindowID> = []
        controller.shelfVisibleFrame = { CGRect(x: 0, y: 0, width: width, height: 700) }
        controller.sourceExists = { id, _ in !gone.contains(id) }
        controller.sourceIsOnScreen = { visible.contains($0) }
        let ids: [CGWindowID] = [4_100_001, 4_100_002, 4_100_003, 4_100_004, 4_100_005]
        for (index, id) in ids.enumerated() {
            let panel = CarryStripPanel(frame: .zero)
            let view = CarryStripView(frame: NSRect(origin: .zero, size: stripSize), appIcon: nil,
                                      title: "Test window \(index + 1)")
            panel.contentView = view
            let item = Carried(id: id, pid: 123_456, bundleID: "test", appName: "Test",
                               title: "Test window \(index + 1)", axWindow: AXUIElementCreateApplication(getpid()),
                               windowSize: CGSize(width: 600, height: 400), panel: panel, view: view)
            controller.carried[id] = item
            controller.order.append(id)
        }
        defer {
            for id in controller.order { owner.glance.detach(id: id); controller.carried[id]?.panel.orderOut(nil) }
            controller.morePanel?.orderOut(nil)
        }
        controller.layout()
        if CommandLine.arguments.contains("--showcase")
            || Bundle.main.bundleIdentifier == "local.windowshade.carry-shelf-preview" {
            NSApp.setActivationPolicy(.accessory)
            NSApp.finishLaunching()
            print("Carry shelf fixture ready (90 seconds)"); fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) { NSApp.terminate(nil) }
            NSApp.run()
            return
        }
        func visibleIDs() -> Set<CGWindowID> {
            Set(controller.order.filter { controller.carried[$0]?.panel.isVisible == true })
        }
        precondition(visibleIDs() == Set(ids.prefix(2)))
        precondition(controller.overflowIDs == Array(ids.dropFirst(2)))
        precondition(controller.morePanel?.isVisible == true)
        let selection = CarryMenuSelection()
        let menu = controller.makeOverflowMenu(selection: selection)
        precondition(menu.items.map(\.title) == ["Test window 3", "Test window 4", "Test window 5"])
        selection.selectWindow(menu.items[2])
        precondition(selection.id == ids[4])
        precondition(controller.previewOverflowItem(ids[4]))
        precondition(visibleIDs().contains(ids[4]) && !controller.overflowIDs.contains(ids[4]))
        controller.refreshVisibility(reason: "test")
        precondition(visibleIDs().count == 2 && visibleIDs().contains(ids[4]), "Refresh must not expose overflow")
        visible.insert(ids[4])
        controller.refreshVisibility(reason: "test-visible")
        precondition(controller.promotedID == nil && !visibleIDs().contains(ids[4]))
        precondition(!controller.previewOverflowItem(ids[4]), "Late selection of an ineligible window does nothing")
        gone.insert(ids[3])
        precondition(!controller.previewOverflowItem(ids[3]), "Late selection of a closed source does nothing")
        precondition(!controller.previewOverflowItem(999), "Unknown window cannot be resurrected")
        let old = controller.carried[ids[0]]!
        let replacement = Carried(id: old.id, pid: old.pid, bundleID: old.bundleID, appName: old.appName,
                                  title: "Replacement", axWindow: old.axWindow, windowSize: old.windowSize,
                                  panel: old.panel, view: old.view)
        controller.carried[old.id] = replacement
        precondition(!controller.previewOverflowItem(old.id, expected: old), "Reused ID cannot redirect an old menu action")
        controller.carried[old.id] = old
        GlanceController.probeOverride = true
        precondition(controller.previewOverflowItem(ids[2]))
        precondition(owner.glance.intent.activeID == ids[2] && owner.glance.intent.isOpen,
                     "Menu selection reaches the actual glance controller")
        owner.glance.detach(id: ids[2]) // immediate cleanup, before any asynchronous capture can start
        GlanceController.probeOverride = false

        width = 200
        controller.layout()
        precondition(visibleIDs().count == 1 && controller.morePanel?.isVisible == true)
        let narrow = controller.shelfVisibleFrame()!
        for id in visibleIDs() { precondition(narrow.contains(controller.carried[id]!.panel.frame)) }
        precondition(narrow.contains(controller.morePanel!.frame))
        width = 2560
        controller.layout()
        precondition(controller.morePanel == nil && controller.overflowIDs.isEmpty)
        visible.formUnion(ids)
        controller.layout()
        precondition(visibleIDs().isEmpty && controller.morePanel == nil, "No shelf on source desktop")
        precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == front, "Fixture shelf must not steal focus")
        precondition(controller.carried.values.allSatisfy { !$0.panel.canBecomeKey && !$0.panel.canBecomeMain })
    }
}
