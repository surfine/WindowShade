# 第四份文件地图与实际符号

行号针对本份完整 overlay 文件；工作区更晚时以符号和 SHA 为准。依赖 Core/Contracts.swift 等共享文件只保留一份。

|路径|操作|旧 SHA256 前12位|新 SHA256 前12位|
|---|---|---|---|
|`prototype/App/EventTap.swift`|modified|d73b793e9350|3c8cb6ff1897|
|`prototype/App/FocusTimerCard.swift`|modified|c50a49ca830c|f6dfab112513|
|`prototype/App/FocusTimerHost.swift`|modified|71347ef9d5c9|7aa01c91cb3a|
|`prototype/App/GlobalShortcuts.swift`|modified|f90893187c5f|f73921fa76ca|
|`prototype/App/InteractionCoordinator.swift`|modified|dc81452cb377|30c08c2813e0|
|`prototype/App/LaunchpadToday.swift`|modified|756b29e69bb7|b049a50d0d3d|
|`prototype/App/Notch.swift`|modified|e2974711f96a|354a6045d722|
|`prototype/App/NotchActivityController.swift`|modified|36a1872d5a3e|4ee8833f2e4d|
|`prototype/App/NotchActivityView.swift`|modified|697e921dc385|2b622c8cfa4c|
|`prototype/App/NotchAuthentication.swift`|modified|047b22b0273a|e2db024c1161|
|`prototype/App/Preferences.swift`|modified|42211e65c3d3|7e7f3c3623de|
|`prototype/App/WS2AgentSessionView.swift`|modified|253d8ba017b1|2eb4cc0b0ffd|
|`prototype/App/WS2AppRuntime.swift`|modified|62450895b64d|4860048055a9|
|`prototype/App/WS2CodexApprovalHost.swift`|new|new|751cfd0b416c|
|`prototype/App/WS2ConductorView.swift`|modified|9fbbe60aeb03|35e1bb2d5b14|
|`prototype/App/WS2FocusSettings.swift`|new|new|5c2dd1877bea|
|`prototype/App/WS2GameControllerBridge.swift`|new|new|dfdb66e861c4|
|`prototype/App/WS2IslandCoordinator.swift`|new|new|596a69bc2161|
|`prototype/App/WS2SupplementPane.swift`|modified|bc7f64128637|223df7148a74|
|`prototype/Core/CodexWire.swift`|modified|7c507cbbc301|25faf949ec1f|
|`prototype/Core/FocusTimer.swift`|modified|10a6c89164ce|f8d5760f92ad|
|`prototype/Core/NotchActivities.swift`|modified|343c66181295|e5c6c6fc339b|
|`prototype/Core/WS2ApprovalReview.swift`|new|new|382ba5ed1470|
|`prototype/Core/WS2CompanionFrame.swift`|new|new|2ecb698bdf16|
|`prototype/Core/WS2DeviceInputGate.swift`|new|new|60c5be947869|
|`prototype/Core/WS2FocusWindowOwnership.swift`|new|new|69a0b9a82fd6|
|`prototype/Support/WS2CompanionCrypto.swift`|new|new|d50a35fcb45b|
|`prototype/build.sh`|modified|1e7f8d73e24a|5de4c8d199ef|

## prototype/App/EventTap.swift

请查看 patch 中的精确上下文。

## prototype/App/FocusTimerCard.swift

- L3: `@MainActor final class FocusTimerCard: NSView, WS2LeaseContent {`
- L6: `var interactionSize: NSSize { NSSize(width: 320, height: 210) }`
- L29: `private func configure(_ b:NSButton,_ symbol:String,_ label:String,_ action:Selector) {`

## prototype/App/FocusTimerHost.swift

- L2: `@MainActor final class FocusTimerHost {`
- L21: `func configure(preset: FocusTimer.Preset, tuckChatEnabled: Bool) {`
- L26: `func stop() { wake?.cancel(); wake = nil; if revision < .max { revision += 1 } }`

## prototype/App/GlobalShortcuts.swift

- L9: `enum GlobalShortcut: String, CaseIterable {`
- L55: `case focusTimer`
- L173: `enum GlobalShortcutSettings {`
- L288: `enum InstallHistory: Int, Sendable {`

## prototype/App/InteractionCoordinator.swift

- L5: `final class InteractionCoordinator {`
- L6: `struct Environment { var unlocked: Bool; var displays: Set<WS2.DisplayID> }`
- L7: `private struct Active { let handle: WS2.LeaseHandle; let layer: WS2.Layer; let deadline: WS2.Instant }`
- L8: `private struct Alert { let first: WS2.Instant; var last: WS2.Instant; let deadline: WS2.Instant }`
- L82: `func invalidate(_ reason: WS2.LeaseRevocation, at now: WS2.Instant) {`

## prototype/App/LaunchpadToday.swift

- L6: `final class LaunchpadTodayPage {`
- L7: `enum Action: Equatable { case spotlight, calendar, app(String), activity(String, NotchActivityAction), activityTool(NotchActivityAction) }`
- L8: `struct Item { let frame: CGRect; let title: String; let action: Action }`

## prototype/App/Notch.swift

- L29: `final class NotchController {`
- L30: `private struct Tucked {`
- L261: `func setEnabled(_ enabled: Bool) {`
- L555: `private func open(_ id: CGWindowID, from origin: NSRect? = nil) {`
- L630: `private struct PendingAnnouncement {`
- L974: `enum TileGlance {`
- L1216: `private enum FlightStyle { case intoNotch, intoVirtualNotch, out }`
- L1294: `struct NotchTile {`
- L1295: `enum Kind { case tucked, strip, slideOver, carried, minimized, hiddenApp, elsewhere }`
- L1314: `final class NotchPanel: NSPanel {`
- L1315: `enum DropState { case none, offered, armed, confirmed }`
- L1328: `enum DropChoice: Int, CaseIterable {`
- L1350: `struct IslandStyle {`
- L1360: `struct Compact {`
- L1372: `struct Alert {`
- L1385: `enum Tone { case info, done, problem, tip }`
- L1428: `private var interactionSize: NSSize {`
- L1435: `func setInteraction(_ view: (NSView & NotchInteractiveContent)?, animated: Bool = true) {`
- L1692: `private enum CompactShape { case sides, pill, chin, pending }`
- L1836: `private struct Target {`
- L1887: `private func baseTarget() -> (rect: NSRect, style: IslandStyle) {`
- L2113: `final class NotchCanvasView: NSView {`
- L2114: `struct Content {`
- L2152: `struct Spring {`
- L2191: `func placeAuthentication(in rect: NSRect) {`
- L2338: `private func present(_ content: Content, in rect: NSRect, animated: Bool) {`
- L2633: `final class NotchShoulders: NSPanel {`
- L2635: `struct Probe {`
- L2844: `final class NotchContentView: NSView {`
- L2993: `final class NotchDotsView: NSView {`
- L3022: `final class NotchCompactView: NSView {`
- L3068: `final class NotchAlertView: NSView {`
- L3142: `final class NotchTileView: NSView {`
- L3308: `final class NotchPeek {`

## prototype/App/NotchActivityController.swift

- L6: `final class NotchActivityController: NSObject, NSSharingServiceDelegate {`
- L62: `func configure() {`
- L75: `private func stop() {`
- L135: `case .focusOpen: ws2FocusAction?(.focusOpen)`

## prototype/App/NotchActivityView.swift

- L6: `final class NotchActivityView: NSView {`
- L169: `private final class ActivityCard: NSView {`

## prototype/App/NotchAuthentication.swift

- L6: `@MainActor protocol NotchInteractiveContent: AnyObject { var onCancel: (() -> Void)? { get set } }`
- L15: `final class NotchAuthenticationController {`
- L209: `private struct SigningJob: @unchecked Sendable {`
- L217: `final class NotchAuthenticationView: NSView, NotchInteractiveContent {`

## prototype/App/Preferences.swift

- L834: `recorderRow(.focusTimer, subtitle: "开始、暂停或继续同一个番茄钟；默认不占用任何快捷键"),`
- L1218: `final class SwitcherOriginControl: NSSegmentedControl {`
- L1246: `final class HotKeyRecorderView: NSControl {`
- L1282: `func configure(current: HotKey?) {`

## prototype/App/WS2AgentSessionView.swift

- L3: `@MainActor final class WS2AgentSessionView: NSView, WS2LeaseContent {`
- L4: `var interactionSize: NSSize { NSSize(width:520,height:320) }`
- L6: `var open: ((WS2.Context) -> Void)?`
- L7: `var stop: ((WS2.Context) -> Void)?`

## prototype/App/WS2AppRuntime.swift

- L3: `@MainActor final class WS2AppRuntime {`
- L37: `case .focusOpen, .open: self.open()`
- L84: `func open() {`
- L97: `func refreshFocusSettings() {`
- L102: `func toggleFocus() {`
- L109: `@discardableResult func showSessions(_ sessions:[AgentSessions.Session], open:@escaping(WS2.Context)->Void,`
- L114: `@discardableResult func showConductor(_ state:ConductorNotch, action:@escaping(WS2ConductorView.Action)->Void) -> Bool {`
- L128: `func stop() {`

## prototype/App/WS2CodexApprovalHost.swift

- L5: `@MainActor final class WS2CodexApprovalHost {`
- L56: `@discardableResult func present(_ id: WS2.RequestID) -> Bool {`
- L142: `func invalidate() {`
- L148: `@MainActor private final class WS2ReviewButton: NSButton {`
- L171: `@MainActor final class WS2CommandReviewView: NSView, WS2LeaseContent {`
- L174: `var interactionSize: NSSize { NSSize(width:600,height:360) }`

## prototype/App/WS2ConductorView.swift

- L3: `@MainActor final class WS2ConductorView: NSView, WS2LeaseContent {`
- L4: `var interactionSize: NSSize { NSSize(width:420,height:280) }`
- L5: `enum Action { case sendDraft(String), discardDraft, confirmCost, stopTurn, leave, session(Int) }`

## prototype/App/WS2FocusSettings.swift

- L2: `@MainActor enum WS2FocusSettings {`
- L14: `@MainActor final class WS2FocusSettingsRows: NSStackView {`

## prototype/App/WS2GameControllerBridge.swift

- L5: `@MainActor final class WS2GameControllerBridge {`
- L6: `struct Environment { let unlocked: Bool; let sinkReady: Bool; let gameOrUnknownInFront: Bool; let domain: WS2DeviceInputGate.Domain }`
- L7: `struct Device { let attachment: UUID; let label: String; let enabled: Bool }`
- L8: `enum Input {`
- L13: `@MainActor private final class Entry {`
- L55: `@discardableResult func setEnabled(_ enabled: Bool, attachment: UUID) -> Bool {`
- L167: `func stop() {`

## prototype/App/WS2IslandCoordinator.swift

- L3: `@MainActor protocol WS2LeaseContent: NotchInteractiveContent {`
- L5: `var interactionSize: NSSize { get }`
- L8: `@MainActor final class WS2IslandCoordinator {`
- L59: `func handOffToAuthorization() { dismissed = nil; dismiss() }`
- L60: `func dismiss() { if let handle { leases.release(handle, at: clock.now()) } }`
- L61: `func dismiss(ifShowing content: NSView) { if view === content { dismiss() } }`
- L62: `func handOffToAuthorization(ifShowing content: NSView) -> Bool {`
- L86: `func invalidate(_ reason: WS2.LeaseRevocation) { leases.invalidate(reason,at:clock.now()) }`
- L88: `func stop() {`

## prototype/App/WS2SupplementPane.swift

- L3: `@MainActor final class WS2SupplementPane: NSStackView {`

## prototype/Core/CodexWire.swift

- L3: `indirect enum WireJSON: Codable, Equatable, Sendable {`
- L33: `struct CodexWire: Sendable {`
- L34: `enum Failure: Error { case oversized, closed, malformed, notReady, unsupported, stale, capacity }`
- L35: `enum State: Equatable, Sendable { case fresh, initializing, listingModels, ready, closed }`
- L36: `struct Pending: Sendable { let method: String; let deadline: WS2.Instant }`
- L37: `enum Event: Equatable, Sendable {`
- L42: `static let maximumFrame = 1_048_576 // Recommendation: bounded metadata stream; not a measured protocol maximum.`
- L204: `enum ApprovalWireDecision { case acceptOnce, decline }`
- L205: `mutating func enqueueApprovalResponse(_ id: WS2.RequestID, expectedMethod: String,`

## prototype/Core/FocusTimer.swift

- L5: `struct FocusTimer: Sendable {`
- L6: `enum Phase: String, Sendable { case idle, focus, rest }`
- L7: `enum PauseReason: String, Hashable, Sendable { case manual, locked, sleeping }`
- L8: `enum Preset: Sendable {`
- L13: `enum Presentation: Sendable { case hidden, compact, expanded }`
- L14: `enum Sound: Sendable { case restStarted, restFinished }`
- L15: `enum Event: Sendable {`
- L19: `enum Effect: Equatable, Sendable {`
- L26: `struct CalendarSample: Sendable {`
- L47: `mutating func configure(preset: Preset, tuckChatEnabled: Bool) {`

## prototype/Core/NotchActivities.swift

- L13: `enum NotchActivityAction: String {`
- L18: `enum NotchActivityKind: String, Codable, Sendable, CaseIterable {`
- L40: `struct NotchActivity: Equatable, Sendable {`
- L88: `struct NotchActivityStore {`

## prototype/Core/WS2ApprovalReview.swift

- L3: `struct WS2ApprovalReview: Equatable, Sendable {`
- L4: `enum Failure: Error { case unsupported, malformed, ambiguous, stale, notShown, oldInput, duplicate, full }`
- L45: `func targetBytes() throws -> Data {`
- L72: `struct WS2ApprovalReviewGate: Sendable {`

## prototype/Core/WS2CompanionFrame.swift

- L3: `struct WS2CompanionFrame: Equatable, Sendable {`
- L4: `enum Failure: Error { case closed, oversized, unsupportedType, invalidLength, exhausted }`
- L5: `static let maximumPayload = 65_536 // local cap, NOT the 24-bit protocol maximum`
- L15: `struct Decoder: Sendable {`
- L48: `struct WS2CompanionCounter: Sendable {`

## prototype/Core/WS2DeviceInputGate.swift

- L3: `struct WS2DeviceInputGate: Sendable {`
- L4: `enum Domain: Sendable { case desktop, conductor, review }`
- L5: `enum Outcome: Equatable, Sendable { case ignored, began(UInt64), ended(UInt64), cancelled(UInt64) }`
- L49: `struct WS2HIDButtonMap: Sendable {`
- L50: `struct Identity: Equatable, Sendable { let registryID: UInt64; let vendor: Int; let product: Int }`

## prototype/Core/WS2FocusWindowOwnership.swift

- L3: `struct WS2FocusWindowOwnership: Sendable {`
- L4: `struct Identity: Hashable, Sendable { let pid: Int32; let processStart: UInt64; let windowID: UInt32; let windowGeneration: UInt64 }`
- L5: `struct Receipt: Equatable, Sendable {`

## prototype/Support/WS2CompanionCrypto.swift

- L2: `// See decisions/01-配对与加密.md for the observed protocol and the missing enrollment gate.`
- L6: `@MainActor final class WS2CompanionCrypto {`
- L7: `enum Failure: Error { case state, expired, malformed, unknownPeer, signature, revoked, closed }`
- L8: `struct Peer: Equatable {`
- L14: `struct Identity {`
- L18: `// Only a successful M3 verification inside this file can construct this object.`
- L19: `@MainActor final class VerifiedSession {`
- L32: `func seal(_ plaintext: Data) throws -> Data {`
- L42: `func open(_ frame: WS2CompanionFrame) throws -> Data {`
- L52: `private enum State { case fresh, proving, finished, closed }`
- L78: `func answerM1(_ tlv: Data) throws -> Data {`
- L97: `func answerM3(_ tlv: Data) throws -> (m4: Data, session: VerifiedSession) {`

## prototype/build.sh

- L64: `-framework GameController`
