// Original adapter. Public GameController only; it emits typed intentions, never synthetic keys.
import Cocoa
@preconcurrency import GameController

@MainActor final class WS2GameControllerBridge {
    struct Environment { let unlocked: Bool; let sinkReady: Bool; let gameOrUnknownInFront: Bool; let domain: WS2DeviceInputGate.Domain }
    struct Device { let attachment: UUID; let label: String; let enabled: Bool }
    enum Input {
        case button(attachment: UUID, name: String, outcome: WS2DeviceInputGate.Outcome)
        case cancel(attachment: UUID, presses: [UInt64])
        case movement(attachment: UUID, effect: GamepadMapping.Effect)
    }
    @MainActor private final class Entry {
        let controller: GCController; let id = UUID()
        var gate = WS2DeviceInputGate(), mapping = GamepadMapping(), sequence: UInt64 = 0
        var buttons: [(String, GCControllerButtonInput)] = []
        var last: [String:Bool] = [:], domain: WS2DeviceInputGate.Domain?
        var neutralSticks = false, ownsFeedback = false
        var movement: Task<Void,Never>?
        init(_ controller: GCController) { self.controller = controller; gate.connect(id) }
    }
    private let clock: any WS2Clock
    private let environment: () -> Environment
    private let emit: (Input) -> Void
    private var entries: [ObjectIdentifier:Entry] = [:]
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var priorBackground: Bool?
    private var running = false
    var devicesChanged: (([Device]) -> Void)?
    init(clock: any WS2Clock, environment: @escaping () -> Environment, emit: @escaping (Input) -> Void) {
        self.clock = clock; self.environment = environment; self.emit = emit
    }
    // Call only when opening the device feature, not automatically at application launch.
    func start() {
        guard !running else { return }; running = true
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcile() }
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspendAll() }
            })
        }
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,
            object:nil,queue:.main) { [weak self] _ in MainActor.assumeIsolated { self?.environmentChanged() } })
        reconcile()
    }
    var devices: [Device] {
        entries.values.map { Device(attachment:$0.id,label:$0.controller.vendorName ?? "游戏手柄",enabled:$0.gate.enabled) }
            .sorted { $0.attachment.uuidString < $1.attachment.uuidString }
    }
    @discardableResult func setEnabled(_ enabled: Bool, attachment: UUID) -> Bool {
        guard let e = entries.values.first(where:{$0.id == attachment}) else { return false }
        if !enabled { suspend(e); publish(); return true }
        let env = environment()
        guard running, env.unlocked, env.sinkReady, !env.gameOrUnknownInFront, env.domain != .review,
              e.controller.extendedGamepad != nil else { return false }
        guard !e.gate.enabled else { return true }
        _ = e.gate.enable(e.id); e.last.removeAll(); e.neutralSticks = false; e.domain = env.domain
        _ = e.gate.changeDomain(to:env.domain)
        if priorBackground == nil { priorBackground = GCController.shouldMonitorBackgroundEvents }
        GCController.shouldMonitorBackgroundEvents = true
        sample(e); publish(); return true
    }
    // The application lock observer MUST call this too; workspace notifications alone do not prove lock state.
    func environmentChanged() {
        let env = environment()
        for e in entries.values where e.gate.enabled {
            guard env.unlocked, env.sinkReady, !env.gameOrUnknownInFront else { suspend(e); continue }
            if e.domain != env.domain {
                emit(.cancel(attachment:e.id,presses:e.gate.changeDomain(to:env.domain)))
                e.domain = env.domain; e.last.removeAll(); e.neutralSticks = false
                e.movement?.cancel(); e.movement = nil; clearFeedback(e)
            }
            sample(e)
        }
        publish()
    }
    func suspendAll() { for e in entries.values { suspend(e) }; publish() }
    private func reconcile() {
        let current = GCController.controllers(), present = Set(current.map(ObjectIdentifier.init))
        for key in Array(entries.keys) where !present.contains(key) {
            if let e = entries.removeValue(forKey:key) {
                suspend(e); e.controller.extendedGamepad?.valueChangedHandler = nil; _ = e.gate.disconnect()
            }
        }
        for c in current where entries[ObjectIdentifier(c)] == nil {
            guard let pad = c.extendedGamepad else { continue }
            let e = Entry(c); entries[ObjectIdentifier(c)] = e
            e.buttons = [("a",pad.buttonA),("b",pad.buttonB),("x",pad.buttonX),("y",pad.buttonY),
                ("menu",pad.buttonMenu),("up",pad.dpad.up),("down",pad.dpad.down),("left",pad.dpad.left),("right",pad.dpad.right),
                ("leftShoulder",pad.leftShoulder),("rightShoulder",pad.rightShoulder)]
            // This bridge is the process's sole owner of this handler; do not install a second bridge.
            c.handlerQueue = .main
            pad.valueChangedHandler = { [weak self, weak e] _,_ in MainActor.assumeIsolated {
                guard let self,let e else { return }; self.sample(e)
            } }
        }
        publish()
    }
    private func sample(_ e: Entry) {
        guard e.gate.enabled, let pad=e.controller.extendedGamepad else { return }
        let env=environment()
        guard env.unlocked,env.sinkReady,!env.gameOrUnknownInFront else { suspend(e);publish();return }
        guard env.domain == e.domain else { environmentChanged();return }
        let now=clock.now()
        for (name,button) in e.buttons {
            let pressed=button.isPressed
            guard e.last[name] != pressed else { continue };e.last[name]=pressed
            guard e.sequence < .max else { suspend(e);return };e.sequence += 1
            let outcome=e.gate.button(attachment:e.id,name:name,pressed:pressed,sequence:e.sequence,at:now,
                                      unlocked:env.unlocked,domain:env.domain)
            if outcome != .ignored { emit(.button(attachment:e.id,name:name,outcome:outcome)) }
        }
        let left=GamepadMapping.Vector(x:Double(pad.leftThumbstick.xAxis.value),y:Double(pad.leftThumbstick.yAxis.value))
        let right=GamepadMapping.Vector(x:Double(pad.rightThumbstick.xAxis.value),y:Double(pad.rightThumbstick.yAxis.value))
        let neutral=GamepadMapping.axis(left) == .zero && GamepadMapping.axis(right) == .zero
        if neutral { e.neutralSticks=true }
        _ = e.mapping.configure(enabled:env.domain == .desktop && e.neutralSticks,gameInFront:false)
        guard env.domain == .desktop, e.neutralSticks, !neutral else {
            e.movement?.cancel();e.movement=nil;_ = e.mapping.disconnect();return
        }
        if e.movement == nil { e.movement=Task { [weak self,weak e] in
            while !Task.isCancelled {
                guard let self,let e,e.gate.enabled,let pad=e.controller.extendedGamepad else{return}
                let current=self.environment()
                guard current.unlocked,current.sinkReady,!current.gameOrUnknownInFront,current.domain == .desktop else {
                    self.suspend(e);self.publish();return
                }
                let l=GamepadMapping.Vector(x:Double(pad.leftThumbstick.xAxis.value),y:Double(pad.leftThumbstick.yAxis.value))
                let r=GamepadMapping.Vector(x:Double(pad.rightThumbstick.xAxis.value),y:Double(pad.rightThumbstick.yAxis.value))
                if GamepadMapping.axis(l) == .zero && GamepadMapping.axis(r) == .zero { e.movement=nil;_ = e.mapping.disconnect();return }
                for effect in e.mapping.sample(left:l,right:r,at:self.clock.now().seconds) { self.emit(.movement(attachment:e.id,effect:effect)) }
                do { try await Task.sleep(nanoseconds:16_666_667) } catch { return }
            }
        } }
    }
    // Optional physical feedback, never a proxy for identity. No caller enables it in this patch.
    @discardableResult func feedback(attachment:UUID,start:Float,strength:Float) -> Bool {
        let env=environment()
        guard start.isFinite,strength.isFinite,(0...1).contains(start),(0...0.25).contains(strength),
              env.unlocked,env.sinkReady,!env.gameOrUnknownInFront,env.domain == .conductor,
              let e=entries.values.first(where:{$0.id == attachment}),e.gate.enabled,
              let pad=e.controller.extendedGamepad as? GCDualSenseGamepad else{return false}
        if strength == 0 { clearFeedback(e);return true }
        // SDK 27 里这个方法没有 NS_SWIFT_NAME，Swift 侧名字是 setModeFeedbackWithStartPosition(_:resistiveStrength:)。
        pad.leftTrigger.setModeFeedbackWithStartPosition(start, resistiveStrength: strength)
        pad.rightTrigger.setModeFeedbackWithStartPosition(start, resistiveStrength: strength);e.ownsFeedback=true;return true
    }
    private func clearFeedback(_ e:Entry) {
        guard e.ownsFeedback else{return};e.ownsFeedback=false
        if let pad=e.controller.extendedGamepad as? GCDualSenseGamepad { pad.leftTrigger.setModeOff();pad.rightTrigger.setModeOff() }
    }
    private func suspend(_ e:Entry) {
        let active=e.gate.suspend();e.movement?.cancel();e.movement=nil;_ = e.mapping.disconnect();clearFeedback(e)
        e.last.removeAll();e.neutralSticks=false
        if !active.isEmpty { emit(.cancel(attachment:e.id,presses:active)) }
    }
    private func publish() {
        if !entries.values.contains(where:{$0.gate.enabled}), let priorBackground {
            GCController.shouldMonitorBackgroundEvents=priorBackground;self.priorBackground=nil
        }
        devicesChanged?(devices)
    }
    func stop() {
        guard running else{return};suspendAll();running=false
        for token in observers { NotificationCenter.default.removeObserver(token) };observers.removeAll()
        for token in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(token) };workspaceObservers.removeAll()
        for e in entries.values { e.controller.extendedGamepad?.valueChangedHandler=nil }
        entries.removeAll();publish()
    }
}
