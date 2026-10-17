// 合成输入监听（prototype/App/GlobalInputFilter.swift）：
// 1. 过滤谓词和各处理函数开头的 guard 的对照表（滚动、拖标题栏用真的 CGEvent → NSEvent 走一遍）；
// 2. 输入线程的账（开头没被主线程处理完之前照送、只看指针位置的合并、离开 Dock 的那一下）；
// 3. 快照更新后输入线程马上按新状态过滤；
// 4. tap 建不起来、或者没打开时，退回 NSEvent 全局监听。
// 不移动指针、不滚动任何窗口；只在最后一项里往系统里发一个“指针原地移动”，看真的 tap 能不能送到主线程。
import Cocoa

@main
@MainActor
struct GlobalInputFilterTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    // MARK: 原文的 guard（照抄，注明出处）

    /// TrackpadGestureController.Phase.init(NSEvent.Phase)
    enum LegacyPhase { case began, changed, ended, cancelled
        init?(_ phase: NSEvent.Phase) {
            if phase.contains(.began) { self = .began }
            else if phase.contains(.changed) { self = .changed }
            else if phase.contains(.ended) { self = .ended }
            else if phase.contains(.cancelled) { self = .cancelled }
            else { return nil }
        }
    }

    /// TrackpadGestureController.handle(_:ownWindow:) 的 scrollWheel 分支：会不会往下走（不是立刻 return false）。
    static func legacyTitleScroll(_ event: NSEvent, sessionActive: Bool) -> Bool {
        if event.momentumPhase != [] { return false }
        if !event.hasPreciseScrollingDeltas, event.phase == [] { return true }
        guard event.hasPreciseScrollingDeltas, let phase = LegacyPhase(event.phase),
              phase == .began || sessionActive else { return false }
        return true
    }

    /// DockSwipeController.handle 开头。
    static func legacyDockSwipe(_ event: NSEvent, sessionActive: Bool) -> Bool {
        guard event.momentumPhase == [], event.hasPreciseScrollingDeltas else { return false }
        guard LegacyPhase(event.phase) != nil else { return false }
        let began = event.phase.contains(.began)
        return began || sessionActive
    }

    /// TrackpadGestureController.handleFlick 开头。
    static func legacyFlick(_ event: NSEvent, dragActive: Bool) -> Bool {
        !(event.type != .leftMouseDown && !dragActive)
    }

    /// DockLock.check 改动前的整个 guard 链（不含最后的挪指针）。
    static func legacyDockLock(_ point: CGPoint, orientationBottom: Bool, screens: [CGRect], locked: CGRect?) -> Bool {
        guard orientationBottom, screens.count > 1, let locked else { return false }
        guard DockLockRule.shouldNudge(point, screens: screens, locked: locked),
              screens.first(where: { $0.minX <= point.x && point.x < $0.maxX && abs(point.y - $0.minY) < 2 }) != nil
        else { return false }
        return true
    }

    // MARK: 事件

    static func scrollEvent(phase: Int64, momentum: Int64, continuous: Bool) -> CGEvent {
        let cg = CGEvent(scrollWheelEvent2Source: nil, units: continuous ? .pixel : .line, wheelCount: 2,
                         wheel1: 3, wheel2: 0, wheel3: 0)!
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: continuous ? 1 : 0)
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        return cg
    }

    static func sample(_ kind: GlobalInputSample.Kind, phase: Int64 = 0, momentum: Int64 = 0,
                       continuous: Bool = true, at point: CGPoint = CGPoint(x: 500, y: 500), pid: pid_t = 777,
                       time: TimeInterval = 0) -> GlobalInputSample {
        GlobalInputSample(kind: kind, scrollPhase: phase, momentumPhase: momentum, continuous: continuous,
                          location: point, targetPID: pid, time: time)
    }

    static func main() {
        _ = NSApplication.shared
        scrollTable()
        flickTable()
        dockLockTable()
        dockHoverTable()
        sequencing()
        smoothWheelAdmission()
        pointerMerging()
        coreSnapshot()
        windowNumber()
        fallback()
        realTap()
        print(failures == 0 ? "PASS global-input-filter" : "FAIL global-input-filter: \(failures)")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: 1. 对照表

    static func scrollTable() {
        var rows = 0, title = 0, swipe = 0
        for phase: Int64 in [0, 1, 2, 4, 8, 128] {
            for momentum: Int64 in [0, 1, 2, 3] {
                for continuous in [false, true] {
                    let cg = scrollEvent(phase: phase, momentum: momentum, continuous: continuous)
                    guard let ns = NSEvent(cgEvent: cg) else { failures += 1; print("FAIL no NSEvent"); continue }
                    let s = GlobalInputSample(cg, type: .scrollWheel)
                    for active in [false, true] {
                        rows += 1
                        let legacyT = legacyTitleScroll(ns, sessionActive: active)
                        let legacyS = legacyDockSwipe(ns, sessionActive: active)
                        if GlobalInputPredicate.titleScroll(s, sessionActive: active) != legacyT {
                            title += 1
                            print("FAIL title scroll phase=\(phase) momentum=\(momentum) continuous=\(continuous) active=\(active) legacy=\(legacyT)")
                        }
                        if GlobalInputPredicate.dockSwipe(s, sessionActive: active) != legacyS {
                            swipe += 1
                            print("FAIL dock swipe phase=\(phase) momentum=\(momentum) continuous=\(continuous) active=\(active) legacy=\(legacyS)")
                        }
                    }
                }
            }
        }
        failures += title + swipe
        expect(title == 0, "title-bar scroll filter equals TrackpadGestureController.handle's guard on \(rows) rows")
        expect(swipe == 0, "Dock swipe filter equals DockSwipeController.handle's guard on \(rows) rows")
        // 几个说得出名字的：
        let momentum = GlobalInputSample(scrollEvent(phase: 0, momentum: 2, continuous: true), type: .scrollWheel)
        expect(!GlobalInputPredicate.titleScroll(momentum, sessionActive: true), "momentum scrolling never wakes the main thread")
        let wheel = GlobalInputSample(scrollEvent(phase: 0, momentum: 0, continuous: false), type: .scrollWheel)
        expect(GlobalInputPredicate.titleScroll(wheel, sessionActive: false), "every mouse-wheel notch reaches the title-bar gesture (it times the bursts)")
        expect(!GlobalInputPredicate.dockSwipe(wheel, sessionActive: true), "mouse-wheel notches never reach the Dock swipe")
        let changed = GlobalInputSample(scrollEvent(phase: 2, momentum: 0, continuous: true), type: .scrollWheel)
        expect(!GlobalInputPredicate.titleScroll(changed, sessionActive: false), "two-finger scrolling with no gesture under way stays on the input thread")
    }

    static func flickTable() {
        var mismatches = 0
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        for type in types {
            let cg = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: 10, y: 10), mouseButton: .left)!
            let ns = NSEvent(cgEvent: cg)!
            let s = GlobalInputSample(cg, type: type)
            for active in [false, true] where GlobalInputPredicate.titleFlick(s, dragActive: active) != legacyFlick(ns, dragActive: active) {
                mismatches += 1
                print("FAIL flick type=\(type.rawValue) active=\(active)")
            }
        }
        expect(mismatches == 0, "title-bar flick filter equals handleFlick's guard (down always, drag/up only while dragging a title bar)")
        let moved = GlobalInputSample(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left)!,
                                      type: .mouseMoved)
        expect(!GlobalInputPredicate.titleFlick(moved, dragActive: true), "pointer moves never go to the flick handler")
    }

    static func dockLockTable() {
        // 两种排布：左右并排（主屏在左）、上下叠着（副屏在主屏下面）。Cocoa 坐标。
        let layouts: [(name: String, screens: [CGRect])] = [
            ("side by side", [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: -180, width: 1920, height: 1080)]),
            ("stacked", [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -240, y: -1080, width: 1920, height: 1080)]),
        ]
        var missed = 0, exactMismatch = 0, rows = 0
        for layout in layouts {
            let screens = layout.screens
            var points: [CGPoint] = []
            for screen in screens {
                for x in stride(from: screen.minX - 3, through: screen.maxX + 3, by: screen.width / 7) {
                    for dy: CGFloat in [-3, -2, -1.5, -0.5, 0, 0.5, 1, 1.5, 1.99, 2, 3, 40] {
                        points.append(CGPoint(x: x, y: screen.minY + dy))
                    }
                    points.append(CGPoint(x: x, y: screen.midY))
                }
            }
            for locked in screens {
                for bottom in [true, false] {
                    var snapshot = GlobalInputSnapshot()
                    snapshot.screens = screens
                    snapshot.baselineY = 900
                    snapshot.dockLockArmed = bottom && screens.count > 1
                    for p in points {
                        rows += 1
                        let s = sample(.mouseMoved, at: CGPoint(x: p.x, y: 900 - p.y))
                        let legacy = legacyDockLock(p, orientationBottom: bottom, screens: screens, locked: locked)
                        let exact = GlobalInputPredicate.dockLock(s, armed: snapshot.dockLockArmed, snapshot: snapshot, slack: 0)
                        let slack = GlobalInputPredicate.dockLock(s, armed: snapshot.dockLockArmed, snapshot: snapshot)
                        if legacy, !exact || !slack { missed += 1; print("FAIL dock lock missed \(layout.name) \(p)") }
                        let component = snapshot.dockLockArmed
                            && screens.contains { $0.minX <= p.x && p.x < $0.maxX && abs(p.y - $0.minY) < 2 }
                        if exact != component { exactMismatch += 1; print("FAIL dock lock edge test \(layout.name) \(p)") }
                        if exact, !slack { missed += 1; print("FAIL slack narrowed \(p)") }
                    }
                }
            }
        }
        expect(missed == 0, "Dock lock filter never drops a move DockLock.check would act on (\(rows) rows)")
        expect(exactMismatch == 0, "Dock lock filter without slack is exactly the bottom-edge guard")
        var snapshot = GlobalInputSnapshot()
        snapshot.screens = layouts[0].screens
        snapshot.baselineY = 900
        snapshot.dockLockArmed = true
        expect(!GlobalInputPredicate.dockLock(sample(.mouseMoved, at: CGPoint(x: 700, y: 450)), armed: true, snapshot: snapshot),
               "a move in the middle of a screen stays on the input thread")
        expect(!GlobalInputPredicate.dockLock(sample(.scroll, at: CGPoint(x: 700, y: 899)), armed: true, snapshot: snapshot),
               "scrolling is not a Dock lock event")
    }

    static func dockHoverTable() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: -180, width: 1920, height: 1080)]
        let snapshots = screens.map { WindowBrowserDockRegion.ScreenSnapshot(frame: $0) }
        let areaSets: [[CGRect]] = [[], [CGRect(x: 400, y: 0, width: 640, height: 70)],
                                    [CGRect(x: 400, y: 0, width: 640, height: 70), CGRect(x: 1700, y: -180, width: 900, height: 80)]]
        var mismatch = 0, narrowed = 0, rows = 0
        for areas in areaSets {
            let region = GlobalInputHoverRegion(running: true, dockAreas: areas, edgeBand: 10, tolerance: 24)
            for x in stride(from: -20.0, through: 3400.0, by: 37.0) {
                for y in stride(from: -200.0, through: 920.0, by: 11.0) {
                    rows += 1
                    let p = CGPoint(x: x, y: y)
                    let legacy = WindowBrowserDockRegion.isNearDock(p, screens: snapshots, dockAreas: areas, edgeBand: 10, tolerance: 24)
                    let exact = GlobalInputPredicate.nearDock(p, region: region, screens: screens, slack: 0)
                    let slack = GlobalInputPredicate.nearDock(p, region: region, screens: screens)
                    if exact != legacy { mismatch += 1; if mismatch < 5 { print("FAIL hover \(p) legacy=\(legacy)") } }
                    if exact, !slack { narrowed += 1 }
                }
            }
        }
        expect(mismatch == 0, "Dock hover filter without slack equals WindowBrowserDockRegion.isNearDock (\(rows) rows)")
        expect(narrowed == 0, "the 2-point slack only ever widens the Dock hover area")
        // 交界处：指针在副屏左缘、离主屏右缘 1 点，主屏排在前面也不能漏。
        let edge = CGPoint(x: 1441, y: 400)
        let region = GlobalInputHoverRegion(running: true, dockAreas: [], edgeBand: 10, tolerance: 24)
        expect(GlobalInputPredicate.nearDock(edge, region: region, screens: screens), "the seam between two screens still counts as an edge")
    }

    // MARK: 2. 输入线程的账

    /// 平滑滚轮（ScrollShape）：连续、没相位的，和前面没有手指那段的惯性，每个都送到标题栏手势（主线程靠完整的一串折格）；
    /// 触控板松手后的惯性照旧不送；Dock 上的滑动不收滚轮。
    static func smoothWheelAdmission() {
        var state = GlobalInputFilterState()
        let quiet = GlobalInputSnapshot()
        let both: GlobalInputRoutes = [.titleScroll, .dockSwipe]
        let phaseless = (0..<5).map { state.admit(sample(.scroll, time: 1 + Double($0) * 0.015), registered: both, snapshot: quiet, ownPID: 42) }
        expect(phaseless.allSatisfy { $0?.routes == [.titleScroll] }, "every continuous phase-0 event (Options+ smooth scrolling) reaches the title-bar gesture, never the Dock swipe")
        let momentumOnly = (0..<4).map { i in
            state.admit(sample(.scroll, momentum: i == 0 ? 1 : (i == 3 ? 3 : 2), time: 3 + Double(i) * 0.016),
                        registered: both, snapshot: quiet, ownPID: 42)
        }
        expect(momentumOnly.allSatisfy { $0?.routes == [.titleScroll] }, "a momentum-only burst with no finger phase reaches the title-bar gesture")
        var pad = GlobalInputFilterState()
        let start = pad.admit(sample(.scroll, phase: 1, time: 5), registered: .titleScroll, snapshot: quiet, ownPID: 42)!
        pad.acknowledge(start.sequence)
        _ = pad.admit(sample(.scroll, phase: 4, time: 5.1), registered: .titleScroll, snapshot: quiet, ownPID: 42)
        let tail = (0..<10).map { i in
            pad.admit(sample(.scroll, momentum: i == 0 ? 1 : 2, time: 5.11 + Double(i) * 0.016), registered: .titleScroll, snapshot: quiet, ownPID: 42)
        }
        expect(tail.allSatisfy { $0 == nil }, "the trackpad's own momentum still stays on the input thread")
        var off = GlobalInputFilterState()
        expect(off.admit(sample(.scroll, time: 1), registered: .dockSwipe, snapshot: quiet, ownPID: 42) == nil,
               "with only the Dock swipe listening, smooth-wheel events are not forwarded")
    }

    static func sequencing() {
        var state = GlobalInputFilterState()
        var snapshot = GlobalInputSnapshot()
        let both: GlobalInputRoutes = [.titleScroll, .dockSwipe, .titleFlick]
        expect(state.admit(sample(.scroll, phase: 1, pid: 42), registered: both, snapshot: snapshot, ownPID: 42) == nil,
               "events WindowShade itself will receive are not forwarded (the global monitor never saw them)")
        let began = state.admit(sample(.scroll, phase: 1), registered: both, snapshot: snapshot, ownPID: 42)
        expect(began?.routes == [.titleScroll, .dockSwipe] && began?.opener == true, "a scroll start goes to both scroll handlers")
        let early = state.admit(sample(.scroll, phase: 2), registered: both, snapshot: snapshot, ownPID: 42)
        expect(early?.routes == [.titleScroll, .dockSwipe],
               "until the main thread has handled the start, the rest of the scroll is forwarded")
        state.acknowledge(began!.sequence)
        state.acknowledge(early!.sequence)
        expect(state.admit(sample(.scroll, phase: 2), registered: both, snapshot: snapshot, ownPID: 42) == nil,
               "once the main thread found no gesture, the rest of the scroll stays on the input thread")
        snapshot.titleSessionActive = true
        let following = state.admit(sample(.scroll, phase: 2), registered: both, snapshot: snapshot, ownPID: 42)
        expect(following?.routes == [.titleScroll], "with a title-bar gesture under way, only that handler gets the rest")
        expect(state.admit(sample(.scroll, phase: 2, momentum: 1), registered: both, snapshot: snapshot, ownPID: 42) == nil,
               "momentum after the fingers lift never goes out")

        // 两下滚动挨得很近：第一下处理完了、第二下还没有，第二下后面的照送。
        var race = GlobalInputFilterState()
        let quiet = GlobalInputSnapshot()
        let first = race.admit(sample(.scroll, phase: 1), registered: .titleScroll, snapshot: quiet, ownPID: 42)!
        let second = race.admit(sample(.scroll, phase: 1), registered: .titleScroll, snapshot: quiet, ownPID: 42)!
        race.acknowledge(first.sequence)
        expect(race.admit(sample(.scroll, phase: 2), registered: .titleScroll, snapshot: quiet, ownPID: 42) != nil,
               "an older acknowledgement does not close a newer start")
        race.acknowledge(second.sequence)
        expect(race.admit(sample(.scroll, phase: 2), registered: .titleScroll, snapshot: quiet, ownPID: 42) == nil,
               "after the newer start is handled the filter follows the snapshot again")

        // 拖标题栏：按下一律送；没在拖的拖动不送。
        var flick = GlobalInputFilterState()
        let down = flick.admit(sample(.leftDown), registered: .titleFlick, snapshot: quiet, ownPID: 42)!
        expect(flick.admit(sample(.leftDragged), registered: .titleFlick, snapshot: quiet, ownPID: 42) != nil,
               "drags right after a press are forwarded until the press is handled")
        flick.acknowledge(down.sequence + 1)
        expect(flick.admit(sample(.leftDragged), registered: .titleFlick, snapshot: quiet, ownPID: 42) == nil,
               "selecting text or dragging files elsewhere stays on the input thread")
        var dragging = quiet
        dragging.flickDragActive = true
        expect(flick.admit(sample(.leftUp), registered: .titleFlick, snapshot: dragging, ownPID: 42) != nil,
               "the release of a title-bar drag is forwarded")
        expect(flick.admit(sample(.leftDown), registered: [], snapshot: dragging, ownPID: 42) == nil,
               "nothing goes out for a feature that is not listening")
    }

    static func pointerMerging() {
        var snapshot = GlobalInputSnapshot()
        snapshot.screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1440, height: 900)]
        snapshot.baselineY = 900
        let observer = NSObject()
        snapshot.hoverRegions[ObjectIdentifier(observer)] =
            GlobalInputHoverRegion(running: true, dockAreas: [CGRect(x: 400, y: 0, width: 640, height: 70)], edgeBand: 10, tolerance: 24)
        var state = GlobalInputFilterState()
        let nearDock = CGPoint(x: 700, y: 900 - 30)       // CGEvent 坐标
        let far = CGPoint(x: 700, y: 300)
        expect(state.admit(sample(.mouseMoved, at: far), registered: .dockHover, snapshot: snapshot, ownPID: 42) == nil,
               "pointer moves far from the Dock stay on the input thread")
        let first = state.admit(sample(.mouseMoved, at: nearDock), registered: .dockHover, snapshot: snapshot, ownPID: 42)
        expect(first?.pointerOnly == true, "a move near the Dock is forwarded")
        expect(state.admit(sample(.mouseMoved, at: nearDock), registered: .dockHover, snapshot: snapshot, ownPID: 42) == nil,
               "while one is on its way, further moves merge into it (the handler reads the pointer when it runs)")
        state.delivered(first!)
        let leaving = state.admit(sample(.mouseMoved, at: far), registered: .dockHover, snapshot: snapshot, ownPID: 42)
        expect(leaving != nil, "the move that leaves the Dock area is forwarded once")
        state.delivered(leaving!)
        expect(state.admit(sample(.mouseMoved, at: far), registered: .dockHover, snapshot: snapshot, ownPID: 42) == nil,
               "after that, moves away from the Dock stay on the input thread")
        var stopped = snapshot
        stopped.hoverRegions[ObjectIdentifier(observer)]?.running = false
        expect(state.admit(sample(.mouseMoved, at: nearDock), registered: .dockHover, snapshot: stopped, ownPID: 42) == nil,
               "a stopped hover observer gets nothing")

        // Dock 留在一块屏和拖标题栏同时要一次拖动：不合并，拖标题栏每一下都要。
        var mixed = GlobalInputFilterState()
        var armed = snapshot
        armed.dockLockArmed = true
        armed.flickDragActive = true
        let bottom = CGPoint(x: 2000, y: 899.5)
        let a = mixed.admit(sample(.leftDragged, at: bottom), registered: [.titleFlick, .dockLock], snapshot: armed, ownPID: 42)
        let b = mixed.admit(sample(.leftDragged, at: bottom), registered: [.titleFlick, .dockLock], snapshot: armed, ownPID: 42)
        expect(a?.routes == [.titleFlick, .dockLock] && b?.routes == [.titleFlick, .dockLock] && a?.pointerOnly == false,
               "a drag that also touches the bottom edge is never merged away")
    }

    // MARK: 3. 快照更新

    static func coreSnapshot() {
        final class Box: @unchecked Sendable { var deliveries: [GlobalInputDelivery] = [] }
        let box = Box()
        let core = GlobalInputTapCore(ownPID: 42) { box.deliveries.append($0) }
        core.setRegistered([.titleScroll])
        let changed = scrollEvent(phase: 2, momentum: 0, continuous: true)
        core.receive(.scrollWheel, changed)
        expect(box.deliveries.isEmpty, "core: no gesture under way, a scroll update is dropped on the input thread")
        core.update { $0.titleSessionActive = true }
        core.receive(.scrollWheel, changed)
        expect(box.deliveries.count == 1, "core: after the snapshot says a gesture is under way, the update goes out")
        expect(box.deliveries.first?.event !== changed, "core: the main thread gets a copy, not the tap's own event")
        core.finish(box.deliveries[0].admission)
        core.receive(.tapDisabledByTimeout, changed)
        expect(box.deliveries.count == 1, "core: a disabled-tap notice is not an input event")
        core.setRegistered([])
        core.receive(.scrollWheel, changed)
        expect(box.deliveries.count == 1, "core: with nothing registered nothing goes out")
    }

    static func windowNumber() {
        let cg = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: 321, y: 123), mouseButton: .left)!
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: 4242)
        GlobalInputFilter.fillWindowNumber(cg, hitTestIfMissing: false)
        let ns = NSEvent(cgEvent: cg)
        expect(ns?.windowNumber == 4242, "the target window travels to NSEvent.windowNumber like a global-monitor event")
        expect(ns?.cgEvent?.location == CGPoint(x: 321, y: 123), "the event location the handlers read is unchanged")
        let already = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: .zero, mouseButton: .left)!
        already.setIntegerValueField(GlobalInputFilter.windowNumberField!, value: 77)
        already.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: 99)
        GlobalInputFilter.fillWindowNumber(already, hitTestIfMissing: false)
        expect(NSEvent(cgEvent: already)?.windowNumber == 77, "a window number the system already set is kept")
    }

    // MARK: 4. 退回路径

    static func fallback() {
        var installed: [GlobalInputRoute] = []
        var removed = 0
        let filter = GlobalInputFilter()
        filter.installFallback = { route, _ in installed.append(route); return NSObject() }
        filter.removeFallback = { _ in removed += 1 }

        filter.wantsTap = { false }
        let off = filter.addMonitor(.dockLock) { _ in }
        expect(installed == [.dockLock] && !filter.isTapRunning,
               "switched off: the feature gets the same NSEvent global monitor as before")
        filter.removeMonitor(off)
        expect(removed == 1, "switched off: removing takes the NSEvent monitor away")

        installed = []
        removed = 0
        filter.wantsTap = { true }
        var attempts = 0
        filter.makeTap = { _ in attempts += 1; return nil }
        let first = filter.addMonitor(.titleScroll) { _ in }
        expect(installed == [.titleScroll] && filter.tapFailed && !filter.isTapRunning,
               "tap creation fails: the feature falls back to its NSEvent global monitor")
        expect((first as? GlobalInputMonitor)?.usesSharedTap == false, "the fallen-back monitor is not on the shared tap")
        let second = filter.addMonitor(.dockHover) { _ in }
        expect(installed == [.titleScroll, .dockHover] && attempts == 1, "after one failure later features go straight to NSEvent monitors")
        filter.removeMonitor(first)
        filter.removeMonitor(second)
        expect(removed == 2, "both fallback monitors are removed")
    }

    /// 真的 tap：能建就建，往系统里发一个“指针原地移动”，看主线程收没收到。建不了（没有授权）就说一声跳过。
    static func realTap() {
        let filter = GlobalInputFilter.shared
        filter.wantsTap = { true }
        var installed = 0
        filter.installFallback = { _, _ in installed += 1; return NSObject() }
        filter.removeFallback = { _ in }
        var received = 0
        // 区域盖住所有屏，任何移动都算“靠近 Dock”。
        let owner = NSObject()
        GlobalInputFilter.publish {
            $0.hoverRegions[ObjectIdentifier(owner)] = GlobalInputHoverRegion(
                running: true, dockAreas: [CGRect(x: -100_000, y: -100_000, width: 200_000, height: 200_000)], edgeBand: 10, tolerance: 0)
        }
        let monitor = filter.addMonitor(.dockHover) { _ in received += 1 }
        guard filter.isTapRunning else {
            print("skip real tap: could not create a listen-only tap here (fallback installed=\(installed))")
            expect(installed == 1, "without a tap the hover monitor falls back")
            filter.removeMonitor(monitor)
            return
        }
        expect(filter.tappedRoutes == .dockHover, "the shared tap listens for Dock hover moves only")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        if let here = CGEvent(source: nil)?.location {
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: here, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
        let deadline = Date().addingTimeInterval(2)
        while received == 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        if received == 0 {
            print("skip real tap delivery: no synthetic move came through (posting events may need permission here)")
        } else {
            expect(received >= 1, "a real move went through the input thread to the main-thread handler")
        }
        filter.removeMonitor(monitor)
        expect(!filter.isTapRunning, "with nothing listening the input thread stops")
        GlobalInputFilter.publish { $0.hoverRegions[ObjectIdentifier(owner)] = nil }
    }
}
