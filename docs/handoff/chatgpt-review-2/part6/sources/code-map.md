# 第六份候选源码地图

路径相对于统一包 `candidate-repo/`；行号和 SHA256 属于本轮候选。拟新增而未实现的 adapter 不会列为现有源码。

## `prototype/App/AuthorizationService.swift`

SHA256 `b2787dc3bb4369d687fbcde86e444cedc752f30d0629a2c5468ae646328a2ba8`；37 行。

- L16: `init(ledger: AuthorizationLedger? = nil, key: ProtectedKeySigning? = nil) {`
- L28: `func consume(_ grant: AuthorizationGrant, purpose: AuthPurpose, currentTarget: AuthTarget) -> AuthFailure? {`
- L32: `private func observe(_ center: NotificationCenter, _ name: Notification.Name) {`

## `prototype/App/FocusTimerHost.swift`

SHA256 `7aa01c91cb3abf4503ff8eb92a8060efcdfca907b295caa3ab0fde88d264b666`；39 行。

- L11: `init(model:FocusTimer,clock:any WS2Clock,`
- L16: `func handle(_ event: FocusTimer.Event) {`
- L21: `func configure(preset: FocusTimer.Preset, tuckChatEnabled: Bool) {`
- L26: `func stop() { wake?.cancel(); wake = nil; if revision < .max { revision += 1 } }`
- L27: `private func schedule() {`
- L38: `deinit { wake?.cancel() }`

## `prototype/App/FoldCompletion.swift`

SHA256 `1147a93b8ab37828e0dd4be225e879ea3a4636283aaa5d7202369b926ec850f5`；48 行。

- L8: `func registerFoldWaiter(id: CGWindowID,`
- L20: `func settleFoldWaiter(id: CGWindowID, token: UUID, success: Bool) {`
- L33: `func settleFoldWaiters(id: CGWindowID, success: Bool) {`
- L40: `func cancelFoldWaiters(id: CGWindowID, tokens: [UUID]) {`
- L44: `func settleFoldWaiters(id: CGWindowID, tokens: [UUID], success: Bool) {`

## `prototype/App/FoldTransaction.swift`

SHA256 `0cdb6083d236e72e193df9db07c672893c10f279be8f53b939be1a1f4cbd0733`；1053 行。

- L7: `func parkFocusForInactiveCapture() {`
- L22: `func releaseFocusParking(reactivate pid: pid_t?) {`
- L41: `func handOffFocusBeforeHiding(win: AXUIElement, pid: pid_t, id: CGWindowID) -> Bool {`
- L104: `func hideTookEffect(_ hide: HideMethod, win: AXUIElement, pid: pid_t,`
- L125: `func scheduleFoldVerification(id: CGWindowID) {`
- L174: `func revealOverlayAfterVerification(id: CGWindowID, state: ShadeState) {`
- L187: `func rollbackFoldTransaction(id: CGWindowID) {`
- L210: `func activateApp(pid: pid_t) {`
- L216: `func bringRestoredWindowToFront(_ win: AXUIElement, pid: pid_t, reason: String) {`
- L219: `func attempt(_ label: String) {`
- L243: `func prepareForwardedTrafficAction(_ win: AXUIElement, pid: pid_t, reason: String) {`
- L250: `func restoredWindowIsGeometryReady(_ win: AXUIElement) -> Bool {`
- L255: `func buttonIsReady(_ win: AXUIElement, _ attr: String) -> Bool {`
- L271: `func forwardedTrafficActionSucceeded(state: ShadeState, id: CGWindowID,`
- L294: `func performForwardedTrafficAction(state: ShadeState, pos: CGPoint,`
- L308: `func retryOrFallback(_ index: Int, note: String) {`
- L332: `func verifyAfterAXPress(_ win: AXUIElement, index: Int, attr: String) {`
- L344: `func verifyAfterPointerClick(_ win: AXUIElement, index: Int, attr: String) {`
- L361: `func attempt(_ index: Int) {`
- L392: `func schedule(_ index: Int, note: String) {`
- L407: `func showRealWindowManagementPopover(_ id: CGWindowID) {`
- L420: `func attempt(_ index: Int) {`
- L450: `func windowIsParkedOffscreen(id: CGWindowID, win: AXUIElement, size: CGSize) -> Bool {`
- L458: `func privateSLSOffscreenHide(_ win: AXUIElement, id: CGWindowID,`
- L494: `func privateSLSAlphaHide(id: CGWindowID, pid: pid_t, reason: String) -> HideMethod? {`
- L526: `func axOffscreenHide(_ win: AXUIElement,`
- L550: `func ownWindow(id: CGWindowID?) -> NSWindow? {`
- L557: `func orderOutOwnWindowIfNeeded(id: CGWindowID?, pid: pid_t, reason: String) -> HideMethod? {`
- L568: `func hideWindow(_ win: AXUIElement, pid: pid_t, originalPosition pos: CGPoint,`
- L629: `func fallbackHide(_ win: AXUIElement, pid: pid_t, id: CGWindowID?,`
- L659: `func safeRestorePosition(for state: ShadeState, desired pos: CGPoint) -> CGPoint {`
- L678: `func refreshedWindowElement(id: CGWindowID, fallback: AXUIElement,`
- L686: `func resolvedWindowElement(for state: ShadeState) -> AXUIElement {`
- L714: `func applyRestoredGeometry(_ state: ShadeState, to pos: CGPoint,`
- L747: `func restoreWindow(_ state: ShadeState, to pos: CGPoint) -> AXUIElement {`
- L787: `func cancelRestorePin(for id: CGWindowID) {`
- L791: `func pinRestoredWindow(_ state: ShadeState, to pos: CGPoint, reason: String) {`
- L799: `func attempt(_ label: String, focus: Bool, verify: Bool = true) {`
- L842: `func resizeShadedWindowFromProxy(_ id: CGWindowID, proxyFrame: NSRect) {`
- L881: `func makeRevealObserver(pid: pid_t, win: AXUIElement, id: CGWindowID) -> AXObserver? {`
- L893: `func removeObserver(_ state: ShadeState) {`
- L899: `func handleAXNotification(_ id: CGWindowID, _ notification: String) {`

## `prototype/App/InteractionCoordinator.swift`

SHA256 `5524bd61193c8e7ca5090b7c38c498f094bdc13a3e48971f3f084b2fb7a0c5b2`；142 行。

- L5: `final class InteractionCoordinator {`
- L6: `struct Environment { var unlocked: Bool; var displays: Set<WS2.DisplayID> }`
- L7: `private struct Active { let handle: WS2.LeaseHandle; let layer: WS2.Layer; let deadline: WS2.Instant }`
- L8: `private struct Alert { let first: WS2.Instant; var last: WS2.Instant; let deadline: WS2.Instant }`
- L21: `init(bootID: UUID, clock: any WS2Clock,`
- L27: `private func permits(_ r: WS2.LeaseRequest) -> Bool {`
- L35: `private func withdraw(_ reason: WS2.LeaseRevocation) {`
- L40: `private func expire(_ now: WS2.Instant) {`
- L46: `func acquire(_ r: WS2.LeaseRequest, replacing expected: WS2.LeaseHandle? = nil) -> WS2.LeaseDecision {`
- L75: `func isCurrent(_ lease: WS2.LeaseHandle) -> Bool {`
- L81: `func release(_ lease: WS2.LeaseHandle, at now: WS2.Instant) {`
- L86: `private func barrier(_ reason: WS2.LeaseRevocation) {`
- L90: `func invalidate(_ reason: WS2.LeaseRevocation, at now: WS2.Instant) {`
- L98: `func removeDisplay(_ id: WS2.DisplayID, at now: WS2.Instant) {`
- L105: `func publishOngoing(_ ids: [String], on display: WS2.DisplayID) {`
- L110: `func remind(on display: WS2.DisplayID, at now: WS2.Instant) {`
- L119: `func snapshots(at now: WS2.Instant) -> [WS2.VisibilitySnapshot] {`
- L137: `func confirmationIsFresh(lease: WS2.LeaseHandle, beganAt: WS2.Instant, sequence: UInt64,`

## `prototype/App/NotchAuthentication.swift`

SHA256 `e2db024c1161ab3157018670c80aa14da701ac5473668a5defa246375797d627`；258 行。

- L15: `final class NotchAuthenticationController {`
- L42: `init(owner: NotchController, service: AuthorizationService? = nil) {`
- L66: `func selfCheck() {`
- L77: `func authorize(_ target: AuthTarget, completion: @escaping (AuthorizationGrant?) -> Void) {`
- L117: `private func evaluateIfReady() {`
- L128: `private func evaluated(_ success: Bool, transaction: Int) {`
- L139: `private func signed(_ result: Result<Data, Error>, transaction: Int) {`
- L166: `private func isCurrent(_ transaction: Int) -> Bool {`
- L174: `private func fail(_ message: (AuthTarget) -> String) {`
- L180: `private func alert(_ title: String, on host: NotchPanel? = nil) {`
- L185: `func cancel(animated: Bool = true, restoreFocus: Bool = true) {`
- L203: `func reconcile(panels: [NotchPanel]) {`
- L209: `private struct SigningJob: @unchecked Sendable {`
- L217: `final class NotchAuthenticationView: NSView, NotchInteractiveContent {`
- L225: `init(context: LAContext, reason: String) {`
- L243: `override func layout() {`
- L250: `func confirm() {`
- L257: `override func cancelOperation(_ sender: Any?) { onCancel?() }`

## `prototype/App/WS2AgentSessionView.swift`

SHA256 `2eb4cc0b0ffd80413aeb0375a2b4973039174218273be6988b5fc1a8f730e53d`；47 行。

- L11: `override init(frame:NSRect) {`
- L20: `func render(_ sessions:[AgentSessions.Session]) {`
- L45: `override func cancelOperation(_ sender:Any?) { onCancel?() }`
- L46: `func revoke() { inputIsCurrent = { false }; render([]); bindings.removeAll() }`

## `prototype/App/WS2AppRuntime.swift`

SHA256 `4860048055a951fd637dba2f5f5a2456ced84b234f5034273e8432e3abb3f820`；139 行。

- L15: `init(owner: AppDelegate) {`
- L21: `func day(_ date: Date) -> String {`
- L73: `private func setLockReason(_ reason: String, locked: Bool) {`
- L84: `func open() {`
- L97: `func refreshFocusSettings() {`
- L102: `func toggleFocus() {`
- L120: `private func publish() {`
- L128: `func stop() {`

## `prototype/App/WS2CodexApprovalHost.swift`

SHA256 `e08fbdcab085bfda8db45e5a01797b9ef173cc87c52f47ae040353af2863b3bf`；235 行。

- L24: `init(wire: CodexWire, connectionID: UUID, clock: any WS2Clock, island: WS2IslandCoordinator,`
- L36: `func beginProtocol() throws {`
- L40: `func startThread(cwd: String, model: String) throws {`
- L45: `func resumeThread(_ id: String) throws {`
- L49: `func startTurn(text: String, model: String, effort: String) throws {`
- L54: `func steer(text: String, expectedTurn: String) throws {`
- L59: `func interruptTurn() throws {`
- L63: `func receive(_ bytes: Data) {`
- L114: `private func confirm(beganAt: WS2.Instant, sequence: UInt64) {`
- L142: `private func target(_ review: WS2ApprovalReview) throws -> AuthTarget {`
- L145: `private func isCurrent(_ review: WS2ApprovalReview) -> Bool {`
- L150: `func tick() {`
- L160: `private func flush(deadline: WS2.Instant) {`
- L164: `private func abandonCurrent(decline: Bool) {`
- L173: `func invalidate() {`
- L184: `init(clock: any WS2Clock) {`
- L189: `private func begin() -> Bool {`
- L192: `override func mouseDown(with event:NSEvent) { guard begin() else { return }; defer { press = nil }; super.mouseDown(with:event) }`
- L193: `override func keyDown(with event:NSEvent) {`
- L197: `override func accessibilityPerformPress() -> Bool {`
- L210: `init(review:WS2ApprovalReview,clock:any WS2Clock) {`
- L231: `func enableConfirmation(){approval.isEnabled=inputIsCurrent()}`
- L232: `func revoke(){inputIsCurrent = { false };approval.isEnabled=false;text.string="";confirm=nil;decline=nil}`
- L234: `override func cancelOperation(_ sender:Any?){onCancel?()}`

## `prototype/App/WS2ConductorView.swift`

SHA256 `35e1bb2d5b14f59c381aba5969009add1be93e97eb3eeb2005fd1d9607e6e225`；78 行。

- L5: `enum Action { case sendDraft(String), discardDraft, confirmCost, stopTurn, leave, session(Int) }`
- L16: `override init(frame:NSRect) {`
- L63: `private func button(_ label:String,_ action:Action) {`
- L76: `override func cancelOperation(_ sender:Any?) { onCancel?() }`
- L77: `func revoke() { buttons.removeAll(); inputIsCurrent = { false }; editor.stringValue = ""; title.stringValue = ""; detail.stringValue = ""; path.path=nil }`

## `prototype/App/WS2DeviceActionHost.swift`

SHA256 `9bad067f8333d54084cb88f2bffa4dd50307d1bb3db4d34aef501b01daa50011`；100 行。

- L8: `func execute(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool`
- L9: `func move(_ effect: GamepadMapping.Effect, context: WS2SemanticInputRouter.Context) -> Bool`
- L22: `init(clock:any WS2Clock, sink:any WS2DeviceActionSink,`
- L41: `func start() { bridge.start() }`
- L52: `func disable(_ id: UUID) {`
- L57: `func environmentChanged() {`
- L61: `private func receive(_ input: WS2GameControllerBridge.Input) {`
- L90: `private static func intent(_ button:String) -> WS2SemanticInputRouter.Intent? {`
- L99: `func stop() { bridge.stop(); contexts.removeAll(); routers.removeAll(); held.removeAll() }`

## `prototype/App/WS2GameControllerBridge.swift`

SHA256 `e8ff240ac2a42ae32eda28fa656c41ecd4ba3e88ad6f763f97af1e1815690a23`；182 行。

- L6: `struct Environment {`
- L9: `init(unlocked: Bool, sinkReady: Bool, gameOrUnknownInFront: Bool,`
- L15: `struct Device { let attachment: UUID; let label: String; let enabled: Bool }`
- L16: `enum Input {`
- L28: `init(_ controller: GCController) { self.controller = controller; gate.connect(id) }`
- L39: `init(clock: any WS2Clock, environment: @escaping () -> Environment, emit: @escaping (Input) -> Void) {`
- L43: `func start() {`
- L77: `func environmentChanged() {`
- L90: `func suspendAll() { for e in entries.values { suspend(e) }; publish() }`
- L91: `private func reconcile() {`
- L112: `private func sample(_ e: Entry) {`
- L160: `private func clearFeedback(_ e:Entry) {`
- L164: `private func suspend(_ e:Entry) {`
- L169: `private func publish() {`
- L175: `func stop() {`

## `prototype/App/WS2IslandCoordinator.swift`

SHA256 `6499c0c6d5b798b909d6546e8ab5c8c081b234c61cff852a6670cc8ed216ba98`；96 行。

- L6: `func revoke()`
- L22: `init(owner: NotchController, clock: any WS2Clock) {`
- L32: `private static func displayID(_ screen: NSScreen) -> WS2.DisplayID? {`
- L60: `func handOffToAuthorization() { dismissed = nil; dismiss() }`
- L61: `func dismiss() { if let handle { leases.release(handle, at: clock.now()) } }`
- L62: `func dismiss(ifShowing content: NSView) { if view === content { dismiss() } }`
- L63: `func handOffToAuthorization(ifShowing content: NSView) -> Bool {`
- L66: `private func revoked(_ lease: WS2.LeaseHandle, reason: WS2.LeaseRevocation) {`
- L79: `private func beginAuthorization(on panel: NotchPanel) -> Bool {`
- L87: `private func endAuthorization() { if let authHandle { leases.release(authHandle,at:clock.now()) }; authHandle = nil }`
- L88: `func invalidate(_ reason: WS2.LeaseRevocation) { leases.invalidate(reason,at:clock.now()) }`
- L89: `private func reconcileDisplays() { _ = leases.snapshots(at:clock.now()) }`
- L90: `func stop() {`

## `prototype/App/WS2OwnedCodexSession.swift`

SHA256 `211a2a4a5024547723634142eb60825b43eb6dfbea3a7710d4ab54bb37653572`；70 行。

- L16: `init(executable: URL, workingDirectory: URL, environment: [String:String], clock: any WS2Clock,`
- L44: `func start() throws {`
- L49: `func startThread(cwd: String, model: String) throws { try approval.startThread(cwd:cwd,model:model); scheduleExpiry() }`
- L50: `func resumeThread(_ id: String) throws { try approval.resumeThread(id); scheduleExpiry() }`
- L51: `func startTurn(text: String, model: String, effort: String) throws { try approval.startTurn(text:text,model:model,effort:effort); scheduleExpiry() }`
- L52: `func steer(text: String, expectedTurn: String) throws { try approval.steer(text:text,expectedTurn:expectedTurn); scheduleExpiry() }`
- L53: `func interrupt() throws { try approval.interruptTurn(); scheduleExpiry() }`
- L54: `private func scheduleExpiry() {`
- L65: `func stop() {`

## `prototype/App/WS2SupplementPane.swift`

SHA256 `223df7148a746cb7e6a7664c012b269dc0c7d515ae5d1fe698962e75aa5e517c`；32 行。

- L5: `init(owner: AppDelegate) {`

## `prototype/Core/AgentSessions.swift`

SHA256 `218b3910959c810d5662d608b8ab9560d5232cf5e69930c330b400c940c65d7c`；260 行。

- L4: `struct AgentSessions: Sendable {`
- L5: `enum Control: Sendable { case observed, owned }`
- L6: `enum Status: Equatable, Sendable { case idle, running, waiting, completed, failed, stale, disconnected }`
- L7: `struct Session: Sendable {`
- L17: `enum Event: Sendable {`
- L23: `enum Effect: Equatable, Sendable {`
- L28: `private struct Pending: Sendable {`
- L33: `enum TypedAction: Sendable {`
- L37: `static func risk(of action: TypedAction) -> WS2.Risk {`
- L64: `func request(for key: WS2.ApprovalKey) -> WS2.ApprovalRequest? { suspended ? nil : pending[key]?.request }`
- L65: `mutating func receive(_ envelope: WS2.Envelope<Event>) -> [Effect] {`
- L151: `mutating func choose(_ key: WS2.ApprovalKey, choice: WS2.ApprovalChoice,`
- L173: `mutating func authorizationFinished(_ outcome: WS2.AuthorizationOutcome, now: WS2.Instant) -> [Effect] {`
- L189: `mutating func tick(at now: WS2.Instant) -> [Effect] {`
- L200: `mutating func suspend(at now: WS2.Instant) -> [Effect] {`
- L210: `mutating func resume(at now: WS2.Instant) -> [Effect] {`
- L223: `private mutating func expire(at now: WS2.Instant) -> [Effect] {`
- L233: `private mutating func clearApprovals(for session: WS2.SessionKey) -> [Effect] {`
- L240: `private mutating func restoreStatus(for key: WS2.SessionKey, fallback: Status) {`
- L244: `private func orderedKeys() -> [WS2.SessionKey] {`
- L247: `private func approvalOrder(_ a: WS2.ApprovalKey, _ b: WS2.ApprovalKey) -> Bool {`
- L258: `private func valid(_ summary: String) -> Bool { !summary.isEmpty && summary.utf8.count <= 16_384 }`
- L259: `private func validID(_ id: String) -> Bool { !id.isEmpty && id.utf8.count <= 512 }`

## `prototype/Core/CodexWire.swift`

SHA256 `71e73c2b2bb2c5bda0aec0d94ad0d4f7dd6d3c218373de510da8007edc64c497`；235 行。

- L5: `init(from decoder: any Decoder) throws {`
- L15: `func encode(to encoder: any Encoder) throws {`
- L33: `struct CodexWire: Sendable {`
- L34: `enum Failure: Error { case oversized, closed, malformed, notReady, unsupported, stale, capacity }`
- L35: `enum State: Equatable, Sendable { case fresh, initializing, listingModels, ready, closed }`
- L36: `struct Pending: Sendable { let method: String; let deadline: WS2.Instant }`
- L37: `enum Event: Equatable, Sendable {`
- L59: `mutating func drain() -> [Data] { defer { outbound.removeAll(keepingCapacity:true) }; return outbound }`
- L60: `private mutating func send(_ value: WireJSON) throws {`
- L66: `private mutating func request(_ method: String, _ params: [String:WireJSON], now: WS2.Instant) throws -> WS2.RequestID {`
- L73: `mutating func initialize(now: WS2.Instant) throws {`
- L78: `mutating func startThread(cwd: String, model: String, now: WS2.Instant) throws {`
- L86: `mutating func resumeThread(id: String, now: WS2.Instant) throws {`
- L94: `mutating func startTurn(text: String, model: String, effort: String, now: WS2.Instant) throws {`
- L103: `mutating func steer(text: String, expectedTurnID: String, now: WS2.Instant) throws {`
- L109: `mutating func interrupt(now: WS2.Instant) throws {`
- L114: `mutating func ingest(_ chunk: Data, now: WS2.Instant) throws -> [Event] {`
- L134: `private mutating func receive(_ v: WireJSON, now: WS2.Instant) throws -> [Event] {`
- L201: `mutating func denyApproval(_ id: WS2.RequestID) throws {`
- L210: `enum ApprovalWireDecision { case acceptOnce, decline }`
- L211: `mutating func enqueueApprovalResponse(_ id: WS2.RequestID, expectedMethod: String,`
- L224: `mutating func tick(now: WS2.Instant) -> [Event] {`
- L230: `mutating func close() {`

## `prototype/Core/Contracts.swift`

SHA256 `12fffc2e5cf207aa0ca6b4c371f28b9eec8c2b374b5e1a06d8943878891b2420`；327 行。

- L6: `enum WS2 {`
- L8: `struct Instant: Hashable, Comparable, Sendable, Codable {`
- L10: `init(nanoseconds: UInt64) { self.nanoseconds = nanoseconds }`
- L18: `static func < (a: Self, b: Self) -> Bool { a.nanoseconds < b.nanoseconds }`
- L20: `func adding(_ duration: UInt64) -> Self {`
- L25: `func elapsed(since earlier: Self) -> UInt64 {`
- L32: `enum Duration {`
- L39: `struct TimeGate: Sendable {`
- L41: `mutating func accept(_ now: Instant) -> Bool {`
- L50: `struct EventGate: Sendable {`
- L53: `mutating func accept(sequence: UInt64, at now: Instant) -> Bool {`
- L62: `enum TokenDomain: String, Hashable, Sendable, Codable { case unspecified, focusTimer, presenceLock, conductor, interaction }`
- L66: `struct Token: Hashable, Sendable, Codable {`
- L70: `init(bootID: UUID, serial: UInt64, domain: TokenDomain = .unspecified) {`
- L76: `struct TokenSource: Sendable {`
- L80: `mutating func next() -> Token? {`
- L88: `enum Provider: String, Hashable, Sendable, Codable, CaseIterable {`
- L94: `struct SessionKey: Hashable, Sendable, Codable {`
- L101: `struct Context: Hashable, Sendable, Codable {`
- L114: `struct Envelope<Payload: Sendable>: Sendable {`
- L124: `struct Digest: Hashable, Sendable, Codable {`
- L130: `init(from decoder: Decoder) throws {`
- L138: `func encode(to encoder: Encoder) throws {`
- L145: `struct ModelID: Hashable, Sendable, Codable {`
- L151: `struct ExecutionConfig: Hashable, Sendable, Codable {`
- L159: `struct CostBinding: Hashable, Sendable, Codable {`
- L167: `enum Risk: String, Sendable, Codable { case normal, high, unknown }`
- L170: `enum RequestID: Hashable, Sendable, Codable {`
- L176: `struct ApprovalKey: Hashable, Sendable, Codable {`
- L183: `struct ApprovalRequest: Equatable, Sendable {`
- L200: `enum ApprovalChoice: Sendable { case confirm, deny, returnToHost }`
- L203: `struct AuthorizationIntent: Equatable, Sendable {`
- L211: `enum AuthorizationOutcome: Sendable {`
- L218: `enum ApprovalDisposition: String, Equatable, Sendable { case deny, deferToHost }`
- L221: `enum Button: String, Hashable, Sendable, CaseIterable {`
- L226: `enum ButtonPhase: String, Sendable { case down, up, cancel, heldHalfSecond, heldOneSecond, clickOnly }`
- L229: `struct ButtonEvent: Equatable, Sendable {`
- L238: `struct Point: Equatable, Sendable {`
- L245: `enum Action: String, Equatable, Sendable {`
- L254: `enum Layer: Int, Comparable, Sendable, CaseIterable {`
- L256: `static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }`
- L260: `struct DisplayID: Hashable, Comparable, Sendable, Codable {`
- L262: `static func < (a: Self, b: Self) -> Bool { a.value < b.value }`
- L266: `enum Fault: String, Equatable, Sendable {`
- L273: `protocol WS2Clock: Sendable {`
- L274: `func now() -> WS2.Instant`
- L278: `struct WS2ContinuousClock: WS2Clock, Sendable {`
- L280: `init() { origin = ContinuousClock.now }`
- L281: `func now() -> WS2.Instant {`
- L296: `struct LeaseRequest: Sendable {`
- L304: `struct LeaseHandle: Hashable, Sendable {`
- L310: `enum LeaseRevocation: Sendable {`
- L313: `enum LeaseDecision: Sendable {`
- L319: `struct VisibilitySnapshot: Sendable {`

## `prototype/Core/FocusTimer.swift`

SHA256 `f8d5760f92ad924c1727717938e84bc456f84967c931faec36d9554e243bf462`；180 行。

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
- L53: `func progress(at now: WS2.Instant) -> Double {`
- L58: `init(bootID: UUID, preset: Preset = .minutes25, tuckChatEnabled: Bool = true) {`
- L64: `func count(on today: String) -> Int { today == day ? completedToday : 0 }`
- L65: `func remaining(at now: WS2.Instant) -> UInt64 {`
- L70: `func compactText(at now: WS2.Instant) -> String {`
- L75: `func expandedText(at now: WS2.Instant) -> String {`
- L80: `func nextWake(at now: WS2.Instant, presentation: Presentation) -> WS2.Instant? {`
- L91: `mutating func handle(_ event: Event, at now: WS2.Instant, calendar: CalendarSample) -> [Effect] {`
- L132: `private func ceilingSeconds(_ ns: UInt64) -> UInt64 {`
- L135: `private mutating func setPause(_ reason: PauseReason, on: Bool, at now: WS2.Instant) {`
- L146: `private mutating func advance(at now: WS2.Instant, calendar: CalendarSample) -> [Effect] {`
- L160: `private mutating func beginRest(at start: WS2.Instant, now: WS2.Instant, audible: Bool) -> [Effect] {`
- L171: `private mutating func finish() -> [Effect] {`

## `prototype/Core/WS2BoundedOutbox.swift`

SHA256 `80fb7f58123a2f9df5c0d7b94c206277427e269273be595ac25e4d554c68e326`；72 行。

- L4: `struct WS2BoundedOutbox: Sendable {`
- L5: `enum Failure: Error, Equatable { case closed, stale, invalid, capacity, expired, mismatchedCompletion }`
- L6: `struct Slice: Sendable { let ticket: UInt64; let bytes: Data; let deadline: Double }`
- L7: `private struct Entry: Sendable { let ticket: UInt64; let bytes: Data; let deadline: Double; var offset: Int }`
- L18: `init(connection: UUID, maximumBytes: Int = 2_097_152, maximumEntries: Int = 32) {`
- L23: `private mutating func validate(_ epoch: UUID, _ now: Double) throws {`
- L31: `mutating func admit(_ records: [Data], connection: UUID, now: Double, deadline: Double) throws -> [UInt64] {`
- L51: `mutating func peek(connection: UUID, now: Double, limit: Int = 65_536) throws -> Slice? {`
- L71: `mutating func close() { closed = true; queue.removeAll(); retainedBytes = 0 }`

## `prototype/Core/WS2ConnectionBudget.swift`

SHA256 `f225317ecabd3143c7c40603ed7a1c2bb93f19f083c59722a6bddfc409be9cd2`；74 行。

- L4: `struct WS2ConnectionBudget: Sendable {`
- L5: `struct Handle: Hashable, Sendable { let generation: UUID; let serial: UInt64 }`
- L6: `enum Handshake: Sendable { case pairSetup, pairVerify }`
- L7: `struct Peer: Hashable, Sendable { let id: String; let revision: UInt64 }`
- L8: `private struct Entry: Sendable { let deadline: WS2.Instant; var peer: Peer?; var queued: Int = 0 }`
- L18: `init(generation: UUID) { self.generation = generation }`
- L23: `mutating func expire(at now: WS2.Instant) -> [Handle] {`
- L31: `mutating func admit(_ mode: Handshake, at now: WS2.Instant, locallyOpenedPairing: Bool) -> Handle? {`
- L49: `func isCurrent(_ handle: Handle, peer: Peer?, at now: WS2.Instant) -> Bool {`
- L65: `mutating func close(_ handle: Handle) { entries[handle] = nil }`
- L66: `mutating func revoke(peerID: String) -> [Handle] {`

## `prototype/Core/WS2DiagnosticTail.swift`

SHA256 `fef7ffb8b3191d594e2c9e5e8521fba1ff8271975ddd653c9ae2185281c12fc5`；32 行。

- L5: `struct WS2DiagnosticTail: Sendable {`
- L9: `init(capacity: Int) { self.capacity = min(65_536, max(0, capacity)) }`
- L11: `mutating func append(_ input: Data) {`
- L20: `mutating func clear() { bytes.removeAll(keepingCapacity: false); observedBytes = 0 }`
- L22: `func visibleText() -> String {`

## `prototype/Core/WS2FocusEffectPlan.swift`

SHA256 `60ccb717e3641f20e1fc499dc1e432ba37493e3c4abe8e28c73b2ebc19419829`；85 行。

- L4: `struct WS2FocusEffectPlan: Sendable {`
- L7: `struct Window: Equatable, Sendable { let identity: Identity; let revision: UInt64 }`
- L8: `enum Kind: Equatable, Sendable { case tuck(Window, WS2.Token, UInt64), restore(Receipt) }`
- L9: `struct Operation: Equatable, Sendable { let id: UUID; let kind: Kind }`
- L10: `enum Outcome: Sendable { case completed(revision: UInt64), unchanged, userChanged, unknown }`
- L11: `enum Failure: Error { case invalid, capacity, overflow, unexpectedCompletion }`
- L24: `mutating func transition(run: WS2.Token?, windows: [Window]) throws {`
- L31: `mutating func setSuspended(_ value: Bool) { suspended = value }`
- L32: `mutating func manualChange(_ identity: Identity) {`
- L38: `private static func identity(_ kind: Kind) -> Identity {`
- L41: `mutating func next() -> Operation? {`
- L51: `func mayCommit(_ operation: Operation) -> Bool {`
- L60: `mutating func complete(_ operation: Operation, _ outcome: Outcome) throws {`

## `prototype/Core/WS2FocusWindowOwnership.swift`

SHA256 `69a0b9a82fd67c318d92b4bcedebd6f980b094f24b37197758fe1cf85f5ab3c7`；27 行。

- L3: `struct WS2FocusWindowOwnership: Sendable {`
- L4: `struct Identity: Hashable, Sendable { let pid: Int32; let processStart: UInt64; let windowID: UInt32; let windowGeneration: UInt64 }`
- L5: `struct Receipt: Equatable, Sendable {`
- L13: `mutating func record(_ receipt: Receipt, didComplete: Bool) -> Bool {`
- L18: `mutating func takeForRestore(_ id: Identity, run: WS2.Token, effectGeneration: UInt64, liveRevision: UInt64) -> Receipt? {`
- L24: `mutating func manualChange(_ id: Identity) { owned[id] = nil }`
- L25: `mutating func clear() { owned.removeAll() }`

## `prototype/Core/WS2OwnedScope.swift`

SHA256 `20102a3fbab321958f7dde9a24d69453f3a7d45d2f537fd5957a9a4df4a9d6f2`；60 行。

- L5: `struct WS2OwnedScope: Sendable {`
- L6: `struct Directory: Hashable, Sendable {`
- L12: `struct Project: Hashable, Sendable {`
- L16: `struct Ticket: Hashable, Sendable {`
- L29: `init(boot: UUID) { self.boot = boot }`
- L31: `private mutating func advance() -> Bool {`
- L40: `mutating func environment(unlocked: Bool, enabled: Bool) {`
- L44: `mutating func invalidate() { _ = advance() }`
- L45: `mutating func clearProject() { _ = advance(); project = nil }`
- L46: `mutating func begin(connection: UUID, liveRoot: Directory) -> Ticket? {`
- L51: `func accepts(_ ticket: Ticket, liveRoot: Directory) -> Bool {`
- L56: `func context(_ ticket: Ticket, session: WS2.SessionKey, liveRoot: Directory) -> WS2.Context? {`

## `prototype/Core/WS2SelectionModel.swift`

SHA256 `c8fb3c0ac6564970d2daedee4d4708799ef0014a94a7bb22b99f18a85d86cf4c`；50 行。

- L4: `struct WS2SelectionModel: Sendable {`
- L5: `struct Item: Equatable, Sendable { let id: String; let enabled: Bool }`
- L6: `struct Activation: Equatable, Sendable { let revision: UInt64; let serial: UInt64; let itemID: String }`
- L7: `enum Failure: Error { case invalidSnapshot, exhausted }`
- L14: `mutating func replace(_ next: [Item]) throws {`
- L38: `mutating func reserveActivation(expectedRevision: UInt64) -> Activation? {`
- L44: `mutating func consume(_ value: Activation) -> String? {`
- L49: `mutating func revoke() { pending = nil; items = []; selectedID = nil; if revision < .max { revision += 1 } else { exhausted = true } }`

## `prototype/Core/WS2SemanticInputRouter.swift`

SHA256 `7055bb6994681ac67dd6b166374ab00923a8e1d76b9133021d922925ef2ac3c6`；43 行。

- L4: `struct WS2SemanticInputRouter: Sendable {`
- L5: `enum Intent: Equatable, Sendable { case previous, next, cancel, openSelection, interruptTurn }`
- L6: `struct Context: Equatable, Sendable {`
- L10: `struct Ticket: Equatable, Sendable { let context: Context; let press: UInt64; let intent: Intent }`
- L11: `enum Failure: Error { case invalid, replay, unavailable, stale, forbidden, capacity }`
- L20: `mutating func revoke() { active = nil; seen.removeAll(); reserved.removeAll(); enabled = false }`
- L23: `mutating func reserve(press: UInt64, intent: Intent, context: Context, unlocked: Bool, sinkReady: Bool) throws -> Ticket {`
- L36: `func isCurrent(_ ticket: Ticket, live: Context, unlocked: Bool, sinkReady: Bool) -> Bool {`

## `prototype/Support/WS2CompanionCrypto.swift`

SHA256 `d50a35fcb45ba1905fb26a6c3c4f14a7dd450bb8413b13bfcf8429b0a7eed8e8`；120 行。

- L7: `enum Failure: Error { case state, expired, malformed, unknownPeer, signature, revoked, closed }`
- L8: `struct Peer: Equatable {`
- L14: `struct Identity {`
- L26: `fileprivate init(peer: Peer, transmit: SymmetricKey, receive: SymmetricKey,`
- L31: `func close() { transmit = nil; receive = nil; tx.close(); rx.close() }`
- L32: `func seal(_ plaintext: Data) throws -> Data {`
- L42: `func open(_ frame: WS2CompanionFrame) throws -> Data {`
- L52: `private enum State { case fresh, proving, finished, closed }`
- L63: `init(identity: Identity, clock: any WS2Clock, lookup: @escaping (Data) -> Peer?, isCurrent: @escaping (Peer) -> Bool) throws {`
- L68: `func close() { state = .closed; ephemeral = nil; shared = nil; proofKey = nil; clientEphemeral = nil }`
- L69: `private func checkTime() throws { guard clock.now() < deadline else { close(); throw Failure.expired } }`
- L70: `private static func derive(_ shared: SharedSecret, salt: String, info: String) -> SymmetricKey {`
- L73: `private static func proofNonce(_ value: String) throws -> ChaChaPoly.Nonce {`
- L78: `func answerM1(_ tlv: Data) throws -> Data {`
- L97: `func answerM3(_ tlv: Data) throws -> (m4: Data, session: VerifiedSession) {`

## `prototype/Support/WS2CompanionTCPTransport.swift`

SHA256 `78bccef841039bf2d4fb5058ae21e01633da6f2e00435eb1a17b9ca2cd273266`；109 行。

- L20: `init(connection: NWConnection, clock: @escaping () -> Double, isCurrent: @escaping () -> Bool) {`
- L24: `func start() {`
- L47: `private func receive() {`
- L65: `private func sendNext() {`
- L85: `func setProtocolDeadline(_ deadline: Double) {`
- L90: `private func scheduleTimeout() {`
- L102: `func close() {`

## `prototype/Support/WS2DuplexProcess.swift`

SHA256 `e85ba57a74110f0f4163eac840c65eed8bc9bd6fa08ce4f802098e5a159deaff`；246 行。

- L12: `enum Failure: Error { case invalid, io(Int32), notRunning }`
- L13: `enum End: Equatable { case localStop, eof, processExit, io(Int32), framing, timeout, revoked }`
- L14: `struct Termination: Equatable, Sendable { let status: Int32; let wasSignalled: Bool }`
- L41: `init(connection: UUID = UUID(), executable: URL, arguments: [String], workingDirectory: URL,`
- L60: `func start() throws {`
- L119: `private func armWrite() { if !writeArmed, !stopped { writeArmed = true; writer?.resume() } }`
- L120: `private func disarmWrite() { if writeArmed { writeArmed = false; writer?.suspend() } }`
- L121: `private func scheduleDeadline() {`
- L133: `private func writeReady() {`
- L158: `private func readReady() {`
- L179: `private func childExited(_ result: Termination) {`
- L192: `private func readDiagnosticReady() {`
- L207: `func clearDiagnostics() { diagnostics?.clear() }`
- L208: `private static func writeWithoutSIGPIPE(_ fd: Int32, _ bytes: Data) -> Int {`
- L223: `func stop(_ reason: End = .localStop) {`

## `prototype/Support/WS2FocusEffectExecutor.swift`

SHA256 `674a8760579e1eccf401f6c949d6fcf69b74257943fe795b043f255b7c3887bf`；35 行。

- L6: `func perform(_ operation: WS2FocusEffectPlan.Operation,`
- L15: `init(port: any WS2FocusMutationPort) { self.port = port }`
- L16: `func transition(run: WS2.Token?, windows: [WS2FocusEffectPlan.Window]) throws {`
- L19: `func suspend() { plan.setSuspended(true) }`
- L20: `func resumeAfterVerifiedUnlock() { plan.setSuspended(false); pump() }`
- L21: `func manualChange(_ identity: WS2FocusEffectPlan.Identity) { plan.manualChange(identity); pump() }`
- L23: `func end() throws { try transition(run: nil, windows: []) }`
- L24: `private func pump() {`

## `prototype/Support/WS2PairSetupCrypto.swift`

SHA256 `6345ec9ff7339c0845f4140beac96577ee1310968d71dab941a0266d315e6fda`；71 行。

- L4: `func begin(pin: String) throws -> (salt: Data, publicKey: Data)`
- L6: `func verify(publicKey: Data, proof: Data) throws -> (serverProof: Data, key: Data)`
- L7: `func clear()`
- L15: `enum Failure: Error { case state, malformed, signature }`
- L16: `private enum Phase { case fresh, started, proven, finished }`
- L22: `init(srp: any WS2SRPPrimitive, identifier: Data, signingSeed: Data) throws {`
- L27: `func begin(pin: String) throws -> (salt: Data, publicKey: Data) {`
- L31: `func verify(clientPublicKey: Data, proof: Data) throws -> Data {`
- L38: `private func derive(_ suffix: String) throws -> SymmetricKey {`
- L43: `private func nonce(_ name: String) throws -> ChaChaPoly.Nonce {`
- L47: `func finish(encryptedM5: Data) throws -> (identifier: Data, publicKey: Data, encryptedM6: Data) {`
- L69: `func clear() { srp.clear(); sessionKey = nil; phase = .finished }`

## `prototype/Support/WS2PairSetupServer.swift`

SHA256 `56ba109e6d1f63c8771cb0788c6c3af4796eed38cea5fe9880f744651c6516b1`；117 行。

- L6: `func begin(pin: String) throws -> (salt: Data, publicKey: Data)`
- L7: `func verify(clientPublicKey: Data, proof: Data) throws -> Data`
- L10: `func finish(encryptedM5: Data) throws -> (identifier: Data, publicKey: Data, encryptedM6: Data)`
- L11: `func clear()`
- L15: `enum Failure: Error { case unavailable, busy, expired }`
- L21: `init(repository: WS2PeerRepository, clock: @escaping () -> Double) {`
- L27: `func openByLocalUser(makePIN: () -> String = PairingAttemptWindow.randomPIN) throws -> String {`
- L38: `func claim(_ connection: UUID) throws -> String {`
- L43: `func isCurrent(_ connection: UUID) -> Bool {`
- L46: `func failed(_ connection: UUID) {`
- L53: `func succeeded(_ connection: UUID) throws {`
- L56: `func cancel() { window.cancel(); displayedPIN = nil; owner = nil /* persistent incomplete marker intentionally survives */ }`
- L60: `enum Failure: Error { case sequence, malformed, expired, closed }`
- L61: `enum State { case fresh, awaitingM3, awaitingM5, finished, closed }`
- L68: `init(connection: UUID, admission: WS2PairingAdmission, repository: WS2PeerRepository,`
- L72: `func receive(_ tlv: Data) throws -> Data {`
- L113: `func cancel() {`

## `prototype/Support/WS2PeerRepository.swift`

SHA256 `1ee4290d4151defac9a50b741c1128dbd8d6bcb7514cd4535ce39ac84f740b42`；127 行。

- L5: `func read() throws -> Data?`
- L6: `func replace(_ bytes: Data, creating: Bool) throws`
- L10: `enum Failure: Error { case unavailable, malformed, conflict, capacity, overflow, denied }`
- L11: `struct Peer: Codable, Equatable, Sendable {`
- L18: `struct Snapshot: Codable, Equatable, Sendable {`
- L33: `init(storage: any WS2PeerStorage) { self.storage = storage }`
- L34: `func load() throws {`
- L44: `func provision(identifier: Data, signingSeed: Data) throws {`
- L55: `private static func validate(_ value: Snapshot) throws {`
- L65: `private func encode(_ value: Snapshot) throws -> Data {`
- L70: `private func mutate(_ body: (inout Snapshot, UInt64) throws -> Void) throws {`
- L83: `func beginPairing() throws {`
- L86: `func recordFailedAttempt() throws {`
- L90: `func clearAttemptsAfterCooldown() throws {`
- L93: `func enroll(identifier: Data, publicKey: Data) throws -> Peer {`
- L106: `func markVerified(identifier: Data, revision: UInt64) throws {`
- L113: `func revoke(identifier: Data) throws {`
- L122: `func current(identifier: Data, publicKey: Data, revision: UInt64) -> Bool {`
- L126: `func suspend() { blocked = true; onInvalidateAll?() }`

## `prototype/Support/WS2ProjectDirectory.swift`

SHA256 `7a9c30764d3199652eccc46265c4d7afae6c05cf65e1ee2a5be65c73bbd628a2`；26 行。

- L4: `enum WS2ProjectDirectory {`
- L5: `enum Failure: Error { case notAbsoluteFileURL, notDirectory, missingIdentity }`
- L6: `static func read(_ url: URL) throws -> WS2OwnedScope.Directory {`
- L18: `static func contains(canonicalRoot root: String, canonicalCandidate candidate: String) -> Bool {`

## `prototype/build.sh`

SHA256 `e9f87cc96478257d129e8d16c85d0697e97f25ace0ffa8bbe08573cb4fc72f01`；351 行。


