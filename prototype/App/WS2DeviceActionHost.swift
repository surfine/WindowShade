import Foundation

/// One device owner per Runtime. The bridge is injectable so the production dispatcher is tested without fake AppKit.
@MainActor final class WS2DeviceActionHost {
    typealias Factory = (@escaping () -> WS2ControllerEnvironment, @escaping (WS2ControllerInput) -> Void) -> any WS2ControllerBridge
    private let liveContext: (UUID) -> WS2SemanticInputRouter.Context?
    private let frontIsGameOrUnknown: () -> Bool
    private let unlocked: () -> Bool
    private let sink: any WS2DeviceActionSink
    private var bridge: (any WS2ControllerBridge)!
    private var routers: [UUID: WS2SemanticInputRouter] = [:]
    private var contexts: [UUID: WS2SemanticInputRouter.Context] = [:]
    private var held: [UUID: [UInt64: WS2SemanticInputRouter.Ticket]] = [:]
    var devicesChanged: (([WS2ControllerDevice]) -> Void)?
    init(sink: any WS2DeviceActionSink,
         liveContext: @escaping (UUID) -> WS2SemanticInputRouter.Context?,
         frontIsGameOrUnknown: @escaping () -> Bool, unlocked: @escaping () -> Bool,
         makeBridge: Factory) {
        self.sink = sink; self.liveContext = liveContext
        self.frontIsGameOrUnknown = frontIsGameOrUnknown; self.unlocked = unlocked
        bridge = makeBridge({ [weak self] in
            guard let self else { return .init(unlocked: false, sinkReady: false, gameOrUnknownInFront: true, domain: .review) }
            let active = self.contexts.values.first
            return .init(unlocked: self.unlocked(), sinkReady: self.sink.ready && active != nil,
                         gameOrUnknownInFront: self.frontIsGameOrUnknown(), domain: active?.domain ?? .review,
                         motionReady: self.sink.motionReady)
        }, { [weak self] in self?.receive($0) })
        bridge.devicesChanged = { [weak self] devices in
            guard let self else { return }
            let alive = Set(devices.filter(\.enabled).map(\.attachment))
            for id in Array(self.contexts.keys) where !alive.contains(id) { self.clear(id) }
            self.devicesChanged?(devices)
        }
    }
    func start() { bridge.start() }
    var devices: [WS2ControllerDevice] { bridge.devices }
    private func clear(_ id: UUID) {
        if let context = contexts[id] { sink.cancelPrepared(context: context, presses: Array(held[id]?.keys ?? Dictionary<UInt64, WS2SemanticInputRouter.Ticket>().keys)) }
        contexts[id] = nil; routers[id] = nil; held[id] = nil
    }
    @discardableResult func enable(_ id: UUID) -> Bool {
        for old in Array(contexts.keys) { clear(old) }
        bridge.suspendAll()
        guard sink.ready, !frontIsGameOrUnknown(), unlocked(),
              let context = liveContext(id), context.domain != .review, context.attachment == id else { return false }
        contexts[id] = context
        var router = WS2SemanticInputRouter(); _ = router.enable(context); routers[id] = router
        guard bridge.setEnabled(true, attachment: id) else { clear(id); return false }
        return contexts[id] == context
    }
    func disable(_ id: UUID) { clear(id); _ = bridge.setEnabled(false, attachment: id) }
    func environmentChanged() {
        for (id, context) in Array(contexts) where liveContext(id) != context || !unlocked() || !sink.ready || frontIsGameOrUnknown() { disable(id) }
        bridge.environmentChanged()
    }
    private func receive(_ input: WS2ControllerInput) {
        switch input {
        case .cancel(let id, let presses):
            if let context = contexts[id] { sink.cancelPrepared(context: context, presses: presses) }
            for press in presses { held[id]?[press] = nil }
        case .button(let id, let name, let outcome):
            guard let context = contexts[id], liveContext(id) == context, unlocked(), sink.ready,
                  !frontIsGameOrUnknown() else { disable(id); return }
            switch outcome {
            case .began(let press):
                guard let intent = Self.intent(name) else { return }
                guard press > 0, held[id]?[press] == nil, (held[id]?.count ?? 0) < 32 else { disable(id); return }
                let ticket = WS2SemanticInputRouter.Ticket(context: context, press: press, intent: intent)
                guard sink.prepare(ticket) else { disable(id); return }
                guard contexts[id] == context, liveContext(id) == context, unlocked(), sink.ready, !frontIsGameOrUnknown() else {
                    sink.cancelPrepared(context: context, presses: [press]); return
                }
                held[id, default: [:]][press] = ticket
            case .ended(let press):
                guard let down = held[id]?.removeValue(forKey: press) else { return }
                guard down.intent == Self.intent(name), var router = routers[id] else {
                    sink.cancelPrepared(context: context, presses: [press]); disable(id); return
                }
                do {
                    let ticket = try router.reserve(press: press, intent: down.intent, context: context, unlocked: unlocked(), sinkReady: sink.ready)
                    guard let live = liveContext(id), !frontIsGameOrUnknown(),
                          router.consume(ticket, live: live, unlocked: unlocked(), sinkReady: sink.ready) else { disable(id); return }
                    routers[id] = router
                    if !sink.execute(ticket) { disable(id) }
                } catch { disable(id) }
            case .cancelled(let press):
                sink.cancelPrepared(context: context, presses: [press]); held[id]?[press] = nil
            case .ignored: break
            }
        case .movement(let id, let effect):
            guard let context = contexts[id], liveContext(id) == context, context.domain == .desktop,
                  sink.ready, sink.motionReady, unlocked(), !frontIsGameOrUnknown() else { disable(id); return }
            if !sink.move(effect, context: context) { disable(id) }
        }
    }
    private static func intent(_ name: String) -> WS2SemanticInputRouter.Intent? {
        switch name {
        case "left", "up": return .previous
        case "right", "down": return .next
        case "a": return .openSelection
        case "b", "menu": return .cancel
        default: return nil
        }
    }
    func stop() { for id in Array(contexts.keys) { clear(id) }; bridge.stop() }
}
