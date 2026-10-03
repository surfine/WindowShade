import Foundation

/// Facts exposed by a controller adapter. A label is presentation, never a persistent identity.
struct WS2ControllerDevice: Equatable, Sendable {
    let attachment: UUID
    let label: String
    let enabled: Bool
}
enum WS2ControllerInput: Sendable {
    case button(attachment: UUID, name: String, outcome: WS2DeviceInputGate.Outcome)
    case movement(attachment: UUID, effect: GamepadMapping.Effect)
    case cancel(attachment: UUID, presses: [UInt64])
}
struct WS2ControllerEnvironment: Sendable {
    let unlocked: Bool
    let sinkReady: Bool
    let gameOrUnknownInFront: Bool
    let domain: WS2DeviceInputGate.Domain
    var motionReady = false
}
@MainActor protocol WS2ControllerBridge: AnyObject {
    var devices: [WS2ControllerDevice] { get }
    var devicesChanged: (([WS2ControllerDevice]) -> Void)? { get set }
    func start()
    func stop()
    func suspendAll()
    func environmentChanged()
    @discardableResult func setEnabled(_ enabled: Bool, attachment: UUID) -> Bool
}
@MainActor protocol WS2DeviceActionSink: AnyObject {
    var ready: Bool { get }
    var motionReady: Bool { get }
    /// Capture the visible selection on DOWN. This is not an authorization grant.
    func prepare(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool
    func cancelPrepared(context: WS2SemanticInputRouter.Context, presses: [UInt64])
    /// Called once on a matching fresh UP, after the router consumes its ticket.
    func execute(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool
    func move(_ effect: GamepadMapping.Effect, context: WS2SemanticInputRouter.Context) -> Bool
}
