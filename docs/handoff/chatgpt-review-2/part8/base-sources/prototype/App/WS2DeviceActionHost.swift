import Cocoa

@MainActor protocol WS2DeviceActionSink: AnyObject {
    var ready: Bool { get }
    var motionReady: Bool { get }
    // Implementations re-read the selected target synchronously and match ticket.context.targetRevision.
    // openSelection means opening a local UI selection, never granting a tool approval or unlocking.
    func execute(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool
    func move(_ effect: GamepadMapping.Effect, context: WS2SemanticInputRouter.Context) -> Bool
}

@MainActor final class WS2DeviceActionHost {
    private let clock: any WS2Clock
    private let liveContext: (UUID) -> WS2SemanticInputRouter.Context?
    private let frontIsGameOrUnknown: () -> Bool
    private let sink: any WS2DeviceActionSink
    private var bridge: WS2GameControllerBridge!
    private var routers: [UUID:WS2SemanticInputRouter] = [:]
    private var contexts: [UUID:WS2SemanticInputRouter.Context] = [:]
    private var held: [UUID:[UInt64:String]] = [:]
    var devicesChanged: (([WS2GameControllerBridge.Device]) -> Void)?
    init(clock:any WS2Clock, sink:any WS2DeviceActionSink,
         liveContext:@escaping (UUID)->WS2SemanticInputRouter.Context?, frontIsGameOrUnknown:@escaping ()->Bool) {
        self.clock = clock; self.sink = sink; self.liveContext = liveContext; self.frontIsGameOrUnknown = frontIsGameOrUnknown
        bridge = WS2GameControllerBridge(clock:clock, environment:{ [weak self] in
            guard let self else { return .init(unlocked:false,sinkReady:false,gameOrUnknownInFront:true,domain:.review) }
            let enabled = self.contexts.values.first
            return .init(unlocked:AuthorizationService.shared.lockState() == .unlocked,
                sinkReady:self.sink.ready && enabled != nil,gameOrUnknownInFront:self.frontIsGameOrUnknown(),
                domain:enabled?.domain ?? .review,motionReady:self.sink.motionReady)
        },emit:{ [weak self] in self?.receive($0) })
        bridge.devicesChanged = { [weak self] devices in
            guard let self else { return }
            let alive = Set(devices.filter(\.enabled).map(\.attachment))
            for id in Array(self.contexts.keys) where !alive.contains(id) {
                self.contexts[id] = nil; self.routers[id] = nil; self.held[id] = nil
            }
            self.devicesChanged?(devices)
        }
    }
    func start() { bridge.start() }
    var devices: [WS2GameControllerBridge.Device] { bridge.devices }
    @discardableResult func enable(_ id: UUID) -> Bool {
        // One active attachment/lease in V1; not an arbitration race between two controllers.
        bridge.suspendAll(); contexts.removeAll(); routers.removeAll(); held.removeAll()
        guard sink.ready, !frontIsGameOrUnknown(), AuthorizationService.shared.lockState() == .unlocked,
              let context = liveContext(id), context.domain != .review, context.attachment == id else { return false }
        contexts[id] = context; var router = WS2SemanticInputRouter(); _ = router.enable(context); routers[id] = router
        guard bridge.setEnabled(true,attachment:id) else { contexts[id] = nil; routers[id] = nil; return false }
        return true
    }
    func disable(_ id: UUID) {
        contexts[id] = nil; routers[id] = nil; held[id] = nil; _ = bridge.setEnabled(false,attachment:id)
    }
    // Call before publishing a changed selection lease, project, backend epoch, or lock state.
    // Conservative V1 requires local re-enable after a lease change. Do not secretly carry permission across it.
    func environmentChanged() {
        for (id,context) in Array(contexts) where liveContext(id) != context { disable(id) }
        bridge.environmentChanged()
    }
    private func receive(_ input: WS2GameControllerBridge.Input) {
        switch input {
        case .cancel(let id,let presses):
            for press in presses { held[id]?[press] = nil }
        case .button(let id,let name,let outcome):
            guard let context = contexts[id], liveContext(id) == context else { disable(id); return }
            switch outcome {
            case .began(let press):
                guard (held[id]?.count ?? 0) < 32 else { disable(id); return }
                held[id,default:[:]][press] = name
            case .ended(let press):
                guard held[id]?.removeValue(forKey:press) == name, let intent = Self.intent(name), var router = routers[id] else { return }
                do {
                    let unlocked = AuthorizationService.shared.lockState() == .unlocked
                    let ticket = try router.reserve(press:press,intent:intent,context:context,unlocked:unlocked,sinkReady:sink.ready)
                    guard let live = liveContext(id), router.consume(ticket,live:live,unlocked:unlocked,sinkReady:sink.ready) else { disable(id); return }
                    routers[id] = router
                    if !sink.execute(ticket) { disable(id) }
                } catch { disable(id) }
            case .cancelled(let press): held[id]?[press] = nil
            case .ignored: break
            }
        case .movement(let id,let effect):
            guard let context = contexts[id], liveContext(id) == context,
                  context.domain == .desktop, sink.ready, sink.motionReady,
                  AuthorizationService.shared.lockState() == .unlocked else { disable(id); return }
            if !sink.move(effect,context:context) { disable(id) }
        }
    }
    private static func intent(_ button:String) -> WS2SemanticInputRouter.Intent? {
        switch button {
        case "left","up": return .previous
        case "right","down": return .next
        case "a": return .openSelection
        case "b","menu": return .cancel
        default: return nil // No invented effort/approval/system mappings for X/Y/shoulders.
        }
    }
    func stop() { bridge.stop(); contexts.removeAll(); routers.removeAll(); held.removeAll() }
}
