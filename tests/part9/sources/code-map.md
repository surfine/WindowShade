# 源码索引

共 26 份实际文件。行号只对应此处 SHA256，不把更晚工作区相同行号当同一实现。

## prototype/App/FocusTimerHost.swift

SHA256：`7aa01c91cb3abf4503ff8eb92a8060efcdfca907b295caa3ab0fde88d264b666`；既有相关调用者，未改。

- L2：`@MainActor final class FocusTimerHost {`
- L16：`func handle(_ event: FocusTimer.Event) {`
- L21：`func configure(preset: FocusTimer.Preset, tuckChatEnabled: Bool) {`
- L26：`func stop() { wake?.cancel(); wake = nil; if revision < .max { revision += 1 } }`
- L27：`private func schedule() {`

## prototype/App/FoldCompletion.swift

SHA256：`18559db591375242d83406a083b9a18e4bf5dc69de7b8c32c8f3494c31054982`；本份修改/新增。

- L11：`func registerFoldWaiter(id: CGWindowID, completion: @escaping (Bool) -> Void) -> UUID {`
- L21：`func bindFoldWaiters(id: CGWindowID, tokens: [UUID], transaction: UUID) {`
- L28：`func settleFoldWaiter(id: CGWindowID, token: UUID, success: Bool) {`
- L33：`func settleFoldWaiters(id: CGWindowID, transaction: UUID, success: Bool) {`
- L38：`func cancelFoldWaiters(id: CGWindowID, tokens: [UUID]) {`
- L42：`func settleFoldWaiters(id: CGWindowID, tokens: [UUID], success: Bool) {`

## prototype/App/FoldTransaction.swift

SHA256：`f353846ee708e80dc81e78636f24dd3976d5ec77f1c0f9db0e38f2f675519c3b`；本份修改/新增。

- L7：`func parkFocusForInactiveCapture() {`
- L22：`func releaseFocusParking(reactivate pid: pid_t?) {`
- L41：`func handOffFocusBeforeHiding(win: AXUIElement, pid: pid_t, id: CGWindowID) -> Bool {`
- L103：`func hideTookEffect(_ hide: HideMethod, win: AXUIElement, pid: pid_t,`
- L108：`func scheduleFoldVerification(id: CGWindowID) {`
- L147：`func revealOverlayAfterVerification(id: CGWindowID, state: ShadeState) {`
- L165：`func rollbackFoldTransaction(id: CGWindowID, expectedTransaction: UUID? = nil) {`
- L190：`func activateApp(pid: pid_t) {`
- L196：`func bringRestoredWindowToFront(_ win: AXUIElement, pid: pid_t, reason: String) {`
- L199：`func attempt(_ label: String) {`
- L223：`func prepareForwardedTrafficAction(_ win: AXUIElement, pid: pid_t, reason: String) {`
- L230：`func restoredWindowIsGeometryReady(_ win: AXUIElement) -> Bool {`
- L235：`func buttonIsReady(_ win: AXUIElement, _ attr: String) -> Bool {`
- L251：`func forwardedTrafficActionSucceeded(state: ShadeState, id: CGWindowID,`
- L274：`func performForwardedTrafficAction(state: ShadeState, pos: CGPoint,`
- L288：`func retryOrFallback(_ index: Int, note: String) {`
- L312：`func verifyAfterAXPress(_ win: AXUIElement, index: Int, attr: String) {`
- L324：`func verifyAfterPointerClick(_ win: AXUIElement, index: Int, attr: String) {`
- L341：`func attempt(_ index: Int) {`
- L372：`func schedule(_ index: Int, note: String) {`
- L387：`func showRealWindowManagementPopover(_ id: CGWindowID) {`
- L400：`func attempt(_ index: Int) {`
- L430：`func windowIsParkedOffscreen(id: CGWindowID, win: AXUIElement, size: CGSize) -> Bool {`
- L438：`func privateSLSOffscreenHide(_ win: AXUIElement, id: CGWindowID,`
- L474：`func privateSLSAlphaHide(id: CGWindowID, pid: pid_t, reason: String) -> HideMethod? {`
- L506：`func axOffscreenHide(_ win: AXUIElement,`
- L530：`func ownWindow(id: CGWindowID?) -> NSWindow? {`
- L537：`func orderOutOwnWindowIfNeeded(id: CGWindowID?, pid: pid_t, reason: String) -> HideMethod? {`
- L548：`func hideWindow(_ win: AXUIElement, pid: pid_t, originalPosition pos: CGPoint,`
- L609：`func fallbackHide(_ win: AXUIElement, pid: pid_t, id: CGWindowID?,`
- L639：`func safeRestorePosition(for state: ShadeState, desired pos: CGPoint) -> CGPoint {`
- L658：`func refreshedWindowElement(id: CGWindowID, fallback: AXUIElement,`
- L666：`func resolvedWindowElement(for state: ShadeState) -> AXUIElement {`
- L694：`func applyRestoredGeometry(_ state: ShadeState, to pos: CGPoint,`
- L727：`func restoreWindow(_ state: ShadeState, to pos: CGPoint) -> AXUIElement {`
- L767：`func cancelRestorePin(for id: CGWindowID) {`
- L771：`func pinRestoredWindow(_ state: ShadeState, to pos: CGPoint, reason: String) {`
- L779：`func attempt(_ label: String, focus: Bool, verify: Bool = true) {`
- L822：`func resizeShadedWindowFromProxy(_ id: CGWindowID, proxyFrame: NSRect) {`
- L861：`func makeRevealObserver(pid: pid_t, win: AXUIElement, id: CGWindowID, transaction: UUID) -> AXObserver? {`
- L884：`func removeObserver(_ state: ShadeState) {`
- L894：`func handleAXNotification(_ id: CGWindowID, _ notification: String, expected: WS2FoldCallbackStamp) {`
- L942：`@objc func appTerminated(_ note: Notification) {`
- L952：`@objc func frontmostApplicationChanged(_ note: Notification) {`
- L982：`@objc func screenParametersChanged(_ note: Notification) {`
- L1028：`@objc func activeSpaceChanged(_ note: Notification) {`

## prototype/App/InteractionCoordinator.swift

SHA256：`5524bd61193c8e7ca5090b7c38c498f094bdc13a3e48971f3f084b2fb7a0c5b2`；既有相关调用者，未改。

- L5：`final class InteractionCoordinator {`
- L6：`struct Environment { var unlocked: Bool; var displays: Set<WS2.DisplayID> }`
- L7：`private struct Active { let handle: WS2.LeaseHandle; let layer: WS2.Layer; let deadline: WS2.Instant }`
- L8：`private struct Alert { let first: WS2.Instant; var last: WS2.Instant; let deadline: WS2.Instant }`
- L27：`private func permits(_ r: WS2.LeaseRequest) -> Bool {`
- L35：`private func withdraw(_ reason: WS2.LeaseRevocation) {`
- L40：`private func expire(_ now: WS2.Instant) {`
- L46：`func acquire(_ r: WS2.LeaseRequest, replacing expected: WS2.LeaseHandle? = nil) -> WS2.LeaseDecision {`
- L75：`func isCurrent(_ lease: WS2.LeaseHandle) -> Bool {`
- L81：`func release(_ lease: WS2.LeaseHandle, at now: WS2.Instant) {`
- L86：`private func barrier(_ reason: WS2.LeaseRevocation) {`
- L90：`func invalidate(_ reason: WS2.LeaseRevocation, at now: WS2.Instant) {`
- L98：`func removeDisplay(_ id: WS2.DisplayID, at now: WS2.Instant) {`
- L105：`func publishOngoing(_ ids: [String], on display: WS2.DisplayID) {`
- L110：`func remind(on display: WS2.DisplayID, at now: WS2.Instant) {`
- L119：`func snapshots(at now: WS2.Instant) -> [WS2.VisibilitySnapshot] {`
- L137：`func confirmationIsFresh(lease: WS2.LeaseHandle, beganAt: WS2.Instant, sequence: UInt64,`

## prototype/App/Reconcile.swift

SHA256：`290d8fb4dcb1b14e79620279ff9e30b42e81fbaa86c68678808a5073bd333f04`；本份修改/新增。

- L7：`func updateReconcileTimer() {`
- L25：`func shouldRetryJournalRescue(now: Date) -> Bool {`
- L30：`func sourceWindowLooksUserVisible(state: ShadeState, pos: CGPoint, size: CGSize,`
- L65：`func shouldLogReconcileInvalidCount(_ count: Int) -> Bool {`
- L68：`func sourceWindowMissingShouldCleanup(id: CGWindowID, state: ShadeState) -> Bool {`
- L91：`func reconcileShadedWindows(reason: String) {`
- L153：`func applyReconcileAXSnapshots(_ snapshots: [ReconcileAXSnapshot],`
- L203：`func finishReconcileShadedWindows() {`

## prototype/App/ShadeController.swift

SHA256：`ffe5d474a28aa43ac12baf5e4a85b1d795494be0df928980fe6b4e69d8bb813f`；本份修改/新增。

- L8：`func retargetToActiveSpaceWindow(pid: pid_t) -> (AXUIElement, CGWindowID)? {`
- L35：`func toggle() {`
- L87：`func performNativeStickiesShade(_ win: AXUIElement) {`
- L104：`func makeShadePlan(win: AXUIElement, pos: CGPoint, size: CGSize,`
- L157：`func resolvedSourceSpaceID(windowID id: CGWindowID,`
- L169：`func shade(_ win: AXUIElement, _ id: CGWindowID,`
- L178：`func admissionCurrent() -> Bool {`
- L184：`func completeFold(success: Bool, transaction: UUID? = nil) {`
- L303：`func installOverlay(_ overlay: NSWindow, mode: ShadeAppearanceMode, previewImage: NSImage?) {`
- L482：`func installInteractiveNativeCollapse(barH: CGFloat) -> Bool {`
- L761：`func captureWindow(id: CGWindowID, axPos: CGPoint, size: CGSize,`
- L800：`func fastWindowCapture(_ id: CGWindowID) async -> CGImage? {`
- L807：`func captureWindowWithTimeout(id: CGWindowID, axPos: CGPoint, size: CGSize,`
- L858：`private func raceCaptureWithTimeout(id: CGWindowID, axPos: CGPoint, size: CGSize,`

## prototype/App/WS2AppRuntime.swift

SHA256：`99205e90fd9d99278da55fbfe88924e2100c4ada4223c6d35136da67cf5b6db2`；既有相关调用者，未改。

- L3：`@MainActor final class WS2AppRuntime {`
- L31：`func day(_ date: Date) -> String {`
- L108：`private func setLockReason(_ reason: String, locked: Bool) {`
- L119：`func applicationShouldTerminate() -> NSApplication.TerminateReply {`
- L138：`private func finishQuit(updaterReply:Bool?=nil,childrenReady:Bool=false,failed:Bool=false) {`
- L144：`func openOwned() {`
- L153：`private func openModelPicker() {`
- L192：`func open() {`
- L205：`func refreshFocusSettings() {`
- L210：`func toggleFocus() {`
- L217：`@discardableResult func showSessions(_ sessions:[AgentSessions.Session], open:@escaping(WS2.Context)->Void,`
- L222：`@discardableResult func showConductor(_ state:ConductorNotch, action:@escaping(WS2ConductorView.Action)->Void) -> Bool {`
- L228：`private func publish() {`
- L236：`func stop() {`
- L249：`@objc func ws2OpenOwned() { MainActor.assumeIsolated { ws2Runtime.openOwned() } }`
- L250：`@objc func ws2OpenFocus() { MainActor.assumeIsolated { ws2Runtime.open() } }`

## prototype/App/WS2FoldCallbackGuard.swift

SHA256：`9f8d8cc688955c493ac17ebde396f59f70892e32c0b78250c78589c007fc63db`；本份修改/新增。

- L5：`func foldCallbackStamp(id: CGWindowID, state: ShadeState) -> WS2FoldCallbackStamp {`
- L13：`func foldWaiterDeliveryStamp(id: CGWindowID, transaction: UUID) -> WS2FoldCallbackStamp? {`
- L21：`func foldCallbackIsCurrent(_ expected: WS2FoldCallbackStamp,`
- L30：`func observeFoldHide(_ hide: HideMethod, win: AXUIElement, pid: pid_t,`
- L68：`func retainUnconfirmedFold(id: CGWindowID, state: ShadeState) {`
- L84：`func receiveFoldAXNotification(routeID: UInt, notification: String) {`
- L96：`func axObservedBoolAttribute(_ win: AXUIElement, _ attribute: String) -> Bool? {`

## prototype/App/WS2FoldEvidenceAdapter.swift

SHA256：`56606957ca290794e0450d6199aa4e3d85fc954e4c472a9e6158bb06cdb7013d`；本份修改/新增。

- L7：`func shadeWithEvidence(_ win:AXUIElement,id:CGWindowID,pid:pid_t,recordedPosition:CGPoint?,`
- L27：`func deliverFoldEvidence(_ event:WS2FoldEvidence.Event?){`
- L33：`func mayCommitObservedFold(_ ticket:WS2FoldEvidence.Ticket)->Bool {`
- L37：`func finishFoldEvidence(_ ticket:WS2FoldEvidence.Ticket?,success:Bool){`
- L44：`func publishFoldObservation(id:CGWindowID,state:ShadeState){`
- L61：`func strictFoldObservation(id: CGWindowID, state: ShadeState) -> WS2FoldEvidence.Observation {`
- L70：`func cancelFoldEvidence(id:CGWindowID,transaction:UUID){`

## prototype/Core/FoldVerifier.swift

SHA256：`8391bca46e6af68e0ae1942edd2e9bd106f5ea83e237ffa9ba0b58e5b878c597`；本份修改/新增。

- L4：`final class FoldVerifier {`
- L5：`enum Observation: Equatable, Sendable { case hidden, visible, unknown }`
- L44：`func start() {`
- L50：`private func pollQuickly(until deadline: TimeInterval, elapsed: TimeInterval) {`
- L62：`private func check(attempt: Int) {`
- L83：`private func finish(_ value: Observation) {`

## prototype/Core/WS2FocusEffectPlan.swift

SHA256：`60ccb717e3641f20e1fc499dc1e432ba37493e3c4abe8e28c73b2ebc19419829`；既有相关调用者，未改。

- L4：`struct WS2FocusEffectPlan: Sendable {`
- L7：`struct Window: Equatable, Sendable { let identity: Identity; let revision: UInt64 }`
- L8：`enum Kind: Equatable, Sendable { case tuck(Window, WS2.Token, UInt64), restore(Receipt) }`
- L9：`struct Operation: Equatable, Sendable { let id: UUID; let kind: Kind }`
- L10：`enum Outcome: Sendable { case completed(revision: UInt64), unchanged, userChanged, unknown }`
- L11：`enum Failure: Error { case invalid, capacity, overflow, unexpectedCompletion }`
- L24：`mutating func transition(run: WS2.Token?, windows: [Window]) throws {`
- L31：`mutating func setSuspended(_ value: Bool) { suspended = value }`
- L32：`mutating func manualChange(_ identity: Identity) {`
- L38：`private static func identity(_ kind: Kind) -> Identity {`
- L41：`mutating func next() -> Operation? {`
- L51：`func mayCommit(_ operation: Operation) -> Bool {`
- L60：`mutating func complete(_ operation: Operation, _ outcome: Outcome) throws {`

## prototype/Core/WS2FoldCallbackStamp.swift

SHA256：`50e53418e04733bbe0421c49533bd7e87943f25707f7404bedf188a4ed4543de`；本份修改/新增。

- L5：`struct WS2FoldCallbackStamp: Equatable, Sendable {`
- L15：`func accepts(current: Self, now: TimeInterval, unlocked: Bool,`
- L29：`struct WS2FoldObserverRoute: Equatable, Sendable {`
- L36：`func ws2ObservedBoolean(_ raw: CFTypeRef?) -> Bool? {`

## prototype/Core/WS2FoldEvidence.swift

SHA256：`3d1dd3583a1e6f93a4d721e6b4587a0cd700c993722fee2f7a03428919f420dd`；既有相关调用者，未改。

- L5：`struct WS2FoldEvidence: Sendable {`
- L6：`struct Ticket: Equatable, Sendable { let request:UUID;let window:UInt32;let pid:Int32 }`
- L7：`enum Observation:String,Sendable,Codable { case verifiedHidden, stillVisible, unknown, notStarted }`
- L8：`struct Event:Equatable,Sendable { let ticket:Ticket;let transaction:UUID?;let observation:Observation;let late:Bool }`
- L9：`private struct Entry:Sendable { let ticket:Ticket;let issuedAt:Double;let deadline:Double;var attempted=false;var transaction:UUID?;var last:Observation? }`
- L12：`func contains(_ ticket:Ticket)->Bool{entries[ticket.request]?.ticket == ticket}`
- L13：`mutating func begin(request:UUID,window:UInt32,pid:Int32,at now:Double,timeout:Double=30)->Ticket?{`
- L19：`func mayStart(_ t:Ticket,at now:Double)->Bool {`
- L23：`mutating func markMutation(_ t:Ticket,at now:Double)->Bool{`
- L26：`mutating func bind(_ t:Ticket,transaction:UUID)->Bool{`
- L30：`func ticket(window:UInt32,transaction:UUID)->Ticket?{`
- L33：`mutating func observe(_ t:Ticket,transaction:UUID,observation:Observation)->Event?{`
- L38：`mutating func failed(_ t:Ticket)->Event?{`
- L42：`mutating func expire(_ t:Ticket,at now:Double)->Event?{`
- L48：`mutating func forget(_ t:Ticket){if contains(t){entries[t.request]=nil}}`
- L49：`private mutating func emit(_ t:Ticket,observation:Observation)->Event?{`

## prototype/Effects/EffectFrameAwaiter.swift

SHA256：`9c7a967621855e6add53c5ee4cd405249142d018eea497e5301ebae72e0e42c8`；本份修改/新增。

- L3：`enum EffectFrameAwaiter<Value> {`
- L6：`static func first(`

## prototype/Effects/EffectFrameSource.swift

SHA256：`c63cc6885d42278bf8ce30ae05cfc63e3f209d9490524fbd73ddbfb5087990ab`；既有相关调用者，未改。

- L7：`enum EffectColorSpace: String {`
- L11：`static func display(_ screen: NSScreen?) -> EffectColorSpace {`
- L15：`struct EffectFrame {`
- L30：`func stillImage() -> CGImage? {`
- L46：`final class EffectFrameSource: NSObject, SCStreamOutput, SCStreamDelegate {`
- L62：`func frame() -> EffectFrame? { lock.withLock { slot.value } }`
- L71：`private static func configuration(size: CGSize, fps: Int, color: EffectColorSpace)`
- L88：`func start(filter: SCContentFilter, size: CGSize, fps: Int = 60, color: EffectColorSpace = .sRGB)`
- L126：`@discardableResult func stop() -> UInt64 {`
- L129：`private func stopLocked() -> UInt64 {`
- L158：`func stopAndWait() async throws {`
- L162：`private func waitForStop() async throws {`
- L167：`func updateFPS(_ fps: Int) {`
- L191：`func waitForFrame(timeout: TimeInterval = 0.6) async -> EffectFrame? {`
- L199：`static func contentUV(_ raw: Any?, scaleFactor: CGFloat, buffer: CVPixelBuffer) -> CGRect {`
- L224：`func stream(`
- L273：`private func fail(_ candidate: SCStream, error: Error) {`
- L285：`func stream(_ stream: SCStream, didStopWithError error: Error) { fail(stream, error: error) }`

## prototype/Effects/RestoreVerifier.swift

SHA256：`a0ed730ff532106fdde2eaa64fd8905d5aeddaf9a1ec1e28c293b26ff7dc7052`；既有相关调用者，未改。

- L3：`enum RestoreObservation { case pending, visible, closed }`
- L7：`final class RestoreVerifier {`
- L31：`func start() {`
- L35：`private func check() {`

## prototype/Native/WS2Child.c

SHA256：`134368aa12dfbbb9ec5a6f60a121c44b52b46bb303d55d73b18d78326d875f47`；既有相关调用者，未改。

- L16：`struct WS2Child {`
- L23：`struct timespec value;`

## prototype/Recovery/DurableShadeJournal.swift

SHA256：`5dbcd013cc44573bfef4b028dae0ca44c75c963d7df131cf20b946a737c366c8`；既有相关调用者，未改。

- L4：`struct DurableShadeJournal {`
- L11：`func load() throws -> [[String: Any]]? {`
- L22：`func save(_ entries: [[String: Any]]) throws {`

## prototype/Support/WS2DuplexProcess.swift

SHA256：`1efe08a7d6987fdac80d87f345f1d2ce212e6a5dddac3a71e086e247d8ab579a`；既有相关调用者，未改。

- L11：`@MainActor final class WS2DuplexProcess {`
- L12：`enum Failure: Error { case invalid, io(Int32), notRunning }`
- L13：`enum End: Equatable { case localStop, eof, processExit, io(Int32), framing, timeout, revoked }`
- L14：`struct Termination: Equatable, Sendable { let status: Int32; let wasSignalled: Bool }`
- L57：`func start() throws {`
- L96：`private func pollChild() {`
- L120：`@discardableResult func admit(_ lines: [Data], connection: UUID, deadline: Double,`
- L131：`@discardableResult func admitWireFrames(_ frames: [Data], connection: UUID, deadline: Double,`
- L143：`private func armWrite() { if !writeArmed, !stopped { writeArmed = true; writer?.resume() } }`
- L144：`private func disarmWrite() { if writeArmed { writeArmed = false; writer?.suspend() } }`
- L145：`private func scheduleDeadline() {`
- L157：`private func writeReady() {`
- L183：`private func readReady(checkChild: Bool = true) {`
- L205：`private func readDiagnosticReady() {`
- L220：`func clearDiagnostics() { diagnostics?.clear() }`
- L221：`private static func writeWithoutSIGPIPE(_ fd: Int32, _ bytes: Data) -> Int {`
- L236：`func stop(_ reason: End = .localStop) {`

## prototype/Support/WS2FocusEffectExecutor.swift

SHA256：`674a8760579e1eccf401f6c949d6fcf69b74257943fe795b043f255b7c3887bf`；既有相关调用者，未改。

- L3：`@MainActor protocol WS2FocusMutationPort: AnyObject {`
- L6：`func perform(_ operation: WS2FocusEffectPlan.Operation,`
- L10：`@MainActor final class WS2FocusEffectExecutor {`
- L16：`func transition(run: WS2.Token?, windows: [WS2FocusEffectPlan.Window]) throws {`
- L19：`func suspend() { plan.setSuspended(true) }`
- L20：`func resumeAfterVerifiedUnlock() { plan.setSuspended(false); pump() }`
- L21：`func manualChange(_ identity: WS2FocusEffectPlan.Identity) { plan.manualChange(identity); pump() }`
- L23：`func end() throws { try transition(run: nil, windows: []) }`
- L24：`private func pump() {`

## prototype/Window/AXHelpers.swift

SHA256：`b679b85d9e4e31f1a2f4594a048fba885c89b46bd25395e3fab768c880ab71b6`；本份修改/新增。

- L9：`enum TrafficAction { case close, minimize, zoom, fullScreen }`
- L11：`enum ProxyTrafficLightStyle {`
- L16：`struct ProxyTrafficLightConfiguration {`
- L40：`func proxyTrafficLightConfiguration(of win: AXUIElement, pid: pid_t) -> ProxyTrafficLightConfiguration {`
- L73：`func urlFromAXAttribute(_ win: AXUIElement, _ attr: String) -> URL? {`
- L90：`func quickLookReopenURL(for win: AXUIElement) -> URL? {`
- L102：`func reopenQuickLookPreview(url: URL) -> Bool {`
- L116：`func postSpacebarKey() {`
- L125：`func reopenQuickLookFromFinderSelection(pid: pid_t) -> Bool {`
- L149：`enum SystemTitlebarDoubleClickAction: Equatable {`
- L155：`func systemTitlebarDoubleClickAction() -> SystemTitlebarDoubleClickAction {`
- L163：`func systemTitlebarTripleClickDescription() -> String? {`
- L174：`enum WindowManagementCapability {`
- L182：`func realWindowManagementCapability(_ win: AXUIElement) -> WindowManagementCapability {`
- L203：`func trafficLightRects(_ win: AXUIElement, winTopLeft pos: CGPoint, barH: CGFloat) -> [(CGRect, TrafficAction)] {`
- L216：`func trafficLightRects(_ rects: [(CGRect, TrafficAction)],`
- L238：`func axTitle(_ e: AXUIElement) -> String {`
- L245：`func dumpWindow(_ win: AXUIElement) {`

## prototype/WindowBrowser/WindowBrowserAppDelegate.swift

SHA256：`47a44ee7dd3717a71545ca192da753f650a75ca9a538a8ceeb0fd895583937c8`；本份修改/新增。

- L11：`func windowBrowserManagedSnapshots() -> [ManagedWindowDescriptor] {`
- L101：`func windowBrowserBeginFold(key: WindowKey, element: AXUIElement,`
- L127：`func windowBrowserTargetCandidate(key: WindowKey) -> AXUIElement? {`
- L135：`func windowBrowserIsWindowStillPresent(key: WindowKey) -> Bool {`

## prototype/WindowShade.swift

SHA256：`2c95d5d27a9f4649461e330e590da4bf0afdacee1fb0a2bfdb4897b32f570aed`；本份修改/新增。

- L79：`func framesAlmostEqual(_ a: NSRect, _ b: NSRect, tolerance: CGFloat = 0.5) -> Bool {`
- L86：`func cgWindowID(for window: NSWindow) -> CGWindowID? {`
- L94：`final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {`
- L96：`final class PendingTitlebarTripleClick {`
- L110：`struct PendingSpaceReturn {`
- L118：`struct ReconcileAXTarget {`
- L126：`struct ReconcileAXSnapshot: Sendable {`
- L311：`func applicationDidFinishLaunching(_ note: Notification) {`
- L425：`func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {`
- L430：`@objc func systemAppearanceOptionsChanged(_ note: Notification) {`
- L461：`func installStandardMainMenu() {`
- L471：`private func migrateDistractingDefaultSounds() {`
- L500：`func refreshPinnedPreviewTarget(reason: String) {`
- L507：`private func setupPinnedPreviewFocusTracking() {`
- L520：`private func scheduleTitlebarPrefetch() {`
- L541：`private func schedulePinnedPreviewTargetRefresh() {`
- L561：`func focusSizedFrame(pos: CGPoint, size: CGSize,`
- L600：`func configureShadedAccessibility(for overlay: NSWindow, id: CGWindowID,`
- L626：`func currentShadedOverlayID() -> CGWindowID? {`
- L644：`@objc func finishOnboarding() {`
- L648：`@objc func dismissOnboarding() {`
- L659：`private func runTool(_ path: String, _ args: [String]) -> Int32? {`
- L676：`private func readTool(_ path: String, _ args: [String]) -> String? {`
- L692：`private func runDefaults(_ args: [String]) { runTool("/usr/bin/defaults", args) }`
- L693：`private func readDefaults(_ args: [String]) -> String? { readTool("/usr/bin/defaults", args) }`
- L694：`private func killDock() { runTool("/usr/bin/killall", ["Dock"]) }   // 让 Dock 重读 mineffect`
- L696：`private func writeDockMinimizeEffect(_ value: String, reason: String) -> Bool {`
- L709：`private func persistDockMinimizeEffectSession(original: String?) {`
- L720：`private func clearDockMinimizeEffectSession() {`
- L727：`private func restoreDockMinimizeEffect(original: String?) {`
- L735：`private func recoverStaleDockMinimizeEffectSessionIfNeeded() {`
- L746：`private func enableScaleMinimizeEffectForSession() {`
- L774：`private func restoreDockMinimizeEffect() {`
- L791：`func currentOperationState(_ id: CGWindowID) -> WindowShadeState {`
- L797：`func transitionOperationState(id: CGWindowID, to next: WindowShadeState,`
- L810：`func applicationWillTerminate(_ note: Notification) {`
- L837：`func ensureAccessibility() -> Bool {`
- L844：`@objc func toggleAction() { toggle() }`
- L855：`@objc func focusCurrentAppAction() {`
- L869：`@objc func unshadeFromMenu(_ sender: NSMenuItem) {`
- L874：`@objc func quit() {`
- L887：`func setupEventTapWhenTrusted() {`
- L903：`func setupEventTap() -> Bool {`

## prototype/build.sh

SHA256：`e6db6c9f3499fcdcb4f28c065199f4f87aa64aeb0c5a46b098164dc761ad588c`；既有相关调用者，未改。


## tests/DuoCoreTests.swift

SHA256：`580fbdfa753b6fba4941f67abc0ce7fe58d182d37cb3409880647a5ea6d748f5`；既有相关调用者，未改。

- L3：`@main struct DuoCoreTests {`
- L4：`final class Clock {`
- L7：`func schedule(_ delay: Double, _ action: @escaping () -> Void) {`
- L10：`func advance(_ delta: Double) {`
- L22：`static func main() async throws {`
- L110：`static func titlebarIntentTests() {`
- L134：`static func foldVerificationTests() {`
- L135：`final class Scenario {`
- L222：`static func deferredRestoreCompletionTests() {`
- L253：`static func restorationTests() throws {`
- L266：`func verifier() -> RestoreVerifier {`
- L307：`struct LegacyMotion {`
- L312：`mutating func receive(_ acceleration: SIMD3<Double>, time: Double) {`
- L334：`static func motionTiltTests() throws {`

## tests/duo-integration-check.py

SHA256：`77baca7e632b420b099a9af21b6462d826b6f9f2eb97c9c5d90f5906e002bb6d`；本份修改/新增。

- L5：`transaction = shade.split('func installOverlay(', 1)[1].split('func installInteractiveNativeCollapse', 1)[0]`
- L11：`native = shade.split('func installInteractiveNativeCollapse', 1)[1].split('if mode == .interactiveNative', 1)[0]`
- L15：`sync = exit_code.split('func unshadeReturningElement(', 1)[1].split('@discardableResult', 1)[0]`
- L20：`suspend = controller.split('private func suspend()', 1)[1].split('private func resume()', 1)[0]`
- L25：`assert 'struct MenuState' in menu`
