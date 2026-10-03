# 实际路径与源码索引

仅定位，不证明平台编译或设备行为。SHA属于当前候选；更晚工作区先比较内容。完整符号在code-map.json。

## `AGENTS.md`

SHA256: `0793c499259866d9afac64dec032649fc4f8dad9341db0f4caec4477edc7ae70`，19行。


## `docs/agents-in-notch.md`

SHA256: `98664f72fa7279b8ecac4674574fa4063a4457f5a286b82cf4faf7ddf44b3b78`，95行。


## `docs/blueprint.md`

SHA256: `c9f10268752be9c75d6d269de73e58309c94d409a9b7f64233f595a40ff11de9`，88行。


## `docs/conductor-v2.md`

SHA256: `5c435d7e17bbdec2ba828718d5830721b77dd2e73d21e63c585f92d8a62d0494`，149行。


## `docs/copy-guide.md`

SHA256: `029858deb8ef6823440e3df738c1e96c0b47b55a8dd5150313c82db1af1ff2b6`，106行。


## `docs/design-system.md`

SHA256: `65b56799b1c169d2c1b6424ee00e22e5726acfa9253f353142e64bcbec491c62`，829行。


## `docs/device-battery.md`

SHA256: `655de0eacca269fdf91a946404ccafc493b2cc5fed5cffe925cd002491997358`，42行。


## `docs/direction.md`

SHA256: `513e4f42d4d9ace6226f112144b6c4bddfa8af9eb32764111ed852bda48c8d60`，200行。


## `docs/dynamic-lock.md`

SHA256: `1b355f08a3f3cb02b41f4667a64c259cd30e1ea33001a5dd1af6b24c3f70a85b`，117行。


## `docs/face-unlock.md`

SHA256: `9c191b9a39e43932e0bf8c587a8e0f8d849752bb6f6ef52fe4078322e8c4f59f`，64行。


## `docs/handoff/START-HERE-deepseek.md`

SHA256: `a0d8c8e82c23678451ad777b844816faaf2c43b5e4c9ebd6cd1d59de821ae5d7`，103行。


## `docs/handoff/deepseek-film.md`

SHA256: `f935b56ffbb3986db04f9d4489e8dcabe5c3c164e4aa8779d535a95ca34df965`，120行。


## `docs/handoff/deepseek-menu-agents.md`

SHA256: `f1d69f88f3c1dc6204389ceba794df9a3f1295cc86a6b6043153e599860c34bf`，56行。


## `docs/input-devices.md`

SHA256: `02bf83893ca3125232a8dcd80ebab1fd265ab6bfe1d96fa949174dee68fcd6ee`，217行。


## `docs/lock-unlock-plan.md`

SHA256: `59e782cecea525c98dda7033b07c4873bd9be678c244587059a7edcf9e82735d`，282行。


## `docs/menu-bar.md`

SHA256: `6ba87eb72d428ad59b853cf3e029acde5f3edfa2c4f06cdc056f1b226d778158`，72行。


## `docs/performance.md`

SHA256: `03a3bd2918a1f58e3bc4ce3dc7d79d74e88ecbbbc620cc2e91576dc3bd5833db`，461行。


## `docs/privacy-page.md`

SHA256: `f0d41966695d89e893ce3a315e177e1460f414548de16a1d2988a19b1ec78770`，66行。


## `docs/releases/v1.0.16-ledger.md`

SHA256: `c3b034007fd4b99da063998ee08ba15d1baab3c05e9a46109ef0c5cf9a879323`，70行。


## `prototype/App/AuthorizationService.swift`

SHA256: `b2787dc3bb4369d687fbcde86e444cedc752f30d0629a2c5468ae646328a2ba8`，37行。

- L7: `@MainActor final class AuthorizationService {`
- L28: `func consume(_ grant: AuthorizationGrant, purpose: AuthPurpose, currentTarget: AuthTarget) -> AuthFailure? {`
- L32: `private func observe(_ center: NotificationCenter, _ name: Notification.Name) {`

## `prototype/App/DeviceBatteryController.swift`

SHA256: `f91d842f704003420bc783ec477158f66c722c5a09213bd5c6bf7469dff629a3`，119行。

- L9: `@MainActor final class DeviceBatteryController {`
- L42: `func start() {`
- L48: `func stop() { source.stop() }`
- L52: `private func connect(_ identity: DeviceIdentity, initial: Bool) {`
- L57: `private func disconnect(_ id: String) {`
- L62: `private func record(_ reading: BatteryReading) {`
- L67: `private func handle(_ events: [DeviceBatteryEvent]) {`
- L92: `private func scheduleFlush() {`
- L100: `private func flushConnected() {`
- L114: `private func persist() {`

## `prototype/App/DeviceBatteryCopy.swift`

SHA256: `d8b91913cb5175d3730b1d4e2dd6673613330b68b44fcf9210feaccc78849f37`，42行。

- L6: `enum DeviceBatteryCopy {`
- L7: `struct Model {`
- L13: `static func model(productID: Int?) -> Model {`
- L22: `static func connected(_ name: String) -> String { "\(name)已连接" }`
- L23: `static func connected(count: Int) -> String { "\(count) 个设备已连接" }`
- L24: `static func percent(_ value: Int) -> String { "电量 \(value)%" }`
- L26: `static func low(_ name: String) -> String { "\(name)电量低" }`
- L27: `static func lowDetail(_ percent: Int, battery: BatteryKind) -> String {`
- L32: `static func symbol(percent: Int?) -> String {`

## `prototype/App/FaceObservationSource.swift`

SHA256: `fe1e1aa7bff0578030af1652c348b0396882037c2d267d439ae97172e9c24a2e`，259行。

- L6: `struct FaceCameraDescriptor: Sendable, Hashable { let id: String; let name: String }`
- L8: `struct FaceObservation: Sendable, Equatable {`
- L22: `enum FaceObservationSourceError: Error {`
- L28: `@MainActor final class FaceObservationSource {`
- L36: `static func devices() -> [FaceCameraDescriptor] {`
- L41: `static func startWatchingCameras() { CameraList.shared.start() }`
- L42: `func requestAuthorization() async -> Bool {`
- L45: `func start(deviceID: String, onObservation: @escaping @MainActor (FaceObservation) -> Void) async throws {`
- L73: `private func stopCapture() {`
- L78: `func stop() { stopCapture(); onFailure = nil }`

## `prototype/App/FocusSession.swift`

SHA256: `6a8feaa47356c9e6827eb41f3aa81cc972b0f884c518ef5c80716160f3cd8673`，562行。

- L7: `func focusSizedWorkSize(originalSize: CGSize, visible: NSRect,`
- L14: `func focusCenteredFrame(pos: CGPoint, size: CGSize,`
- L26: `func focusShelfReservedFrame(on screen: NSScreen) -> NSRect? {`
- L34: `func centerFocusedWindowForFocusMode(_ win: AXUIElement, pid: pid_t) {`
- L57: `func pulledOutFocusFrames(state: ShadeState, draggedFrame: NSRect) -> (overlay: NSRect, restore: NSRect) {`
- L87: `func focusRestoreFrame(fromOverlayFrame frame: NSRect, restoredSize: CGSize) -> NSRect {`
- L94: `func shouldReturnPulledOutOverlayToStack(id: CGWindowID, frame: NSRect) -> Bool {`
- L100: `func restorePulledOutOverlayToStack(id: CGWindowID) -> Bool {`
- L125: `func maybeStageFocusPullOut(id: CGWindowID, frame: NSRect) -> Bool {`
- L173: `func rejoinFocusStackAfterShadeIfNeeded(id: CGWindowID, overlay: NSWindow) {`

## `prototype/App/FocusTimerHost.swift`

SHA256: `7aa01c91cb3abf4503ff8eb92a8060efcdfca907b295caa3ab0fde88d264b666`，39行。

- L2: `@MainActor final class FocusTimerHost {`
- L16: `func handle(_ event: FocusTimer.Event) {`
- L21: `func configure(preset: FocusTimer.Preset, tuckChatEnabled: Bool) {`
- L26: `func stop() { wake?.cancel(); wake = nil; if revision < .max { revision += 1 } }`
- L27: `private func schedule() {`

## `prototype/App/FoldCompletion.swift`

SHA256: `18559db591375242d83406a083b9a18e4bf5dc69de7b8c32c8f3494c31054982`，65行。

- L11: `func registerFoldWaiter(id: CGWindowID, completion: @escaping (Bool) -> Void) -> UUID {`
- L21: `func bindFoldWaiters(id: CGWindowID, tokens: [UUID], transaction: UUID) {`
- L28: `func settleFoldWaiter(id: CGWindowID, token: UUID, success: Bool) {`
- L33: `func settleFoldWaiters(id: CGWindowID, transaction: UUID, success: Bool) {`
- L38: `func cancelFoldWaiters(id: CGWindowID, tokens: [UUID]) {`
- L42: `func settleFoldWaiters(id: CGWindowID, tokens: [UUID], success: Bool) {`

## `prototype/App/FoldTransaction.swift`

SHA256: `f353846ee708e80dc81e78636f24dd3976d5ec77f1c0f9db0e38f2f675519c3b`，1059行。

- L7: `func parkFocusForInactiveCapture() {`
- L22: `func releaseFocusParking(reactivate pid: pid_t?) {`
- L41: `func handOffFocusBeforeHiding(win: AXUIElement, pid: pid_t, id: CGWindowID) -> Bool {`
- L103: `func hideTookEffect(_ hide: HideMethod, win: AXUIElement, pid: pid_t,`
- L108: `func scheduleFoldVerification(id: CGWindowID) {`
- L147: `func revealOverlayAfterVerification(id: CGWindowID, state: ShadeState) {`
- L165: `func rollbackFoldTransaction(id: CGWindowID, expectedTransaction: UUID? = nil) {`
- L190: `func activateApp(pid: pid_t) {`
- L196: `func bringRestoredWindowToFront(_ win: AXUIElement, pid: pid_t, reason: String) {`
- L199: `func attempt(_ label: String) {`

## `prototype/App/InteractionCoordinator.swift`

SHA256: `5524bd61193c8e7ca5090b7c38c498f094bdc13a3e48971f3f084b2fb7a0c5b2`，142行。

- L5: `final class InteractionCoordinator {`
- L6: `struct Environment { var unlocked: Bool; var displays: Set<WS2.DisplayID> }`
- L7: `private struct Active { let handle: WS2.LeaseHandle; let layer: WS2.Layer; let deadline: WS2.Instant }`
- L8: `private struct Alert { let first: WS2.Instant; var last: WS2.Instant; let deadline: WS2.Instant }`
- L27: `private func permits(_ r: WS2.LeaseRequest) -> Bool {`
- L35: `private func withdraw(_ reason: WS2.LeaseRevocation) {`
- L40: `private func expire(_ now: WS2.Instant) {`
- L46: `func acquire(_ r: WS2.LeaseRequest, replacing expected: WS2.LeaseHandle? = nil) -> WS2.LeaseDecision {`
- L75: `func isCurrent(_ lease: WS2.LeaseHandle) -> Bool {`
- L81: `func release(_ lease: WS2.LeaseHandle, at now: WS2.Instant) {`

## `prototype/App/NotchFaceObservations.swift`

SHA256: `f7f541e11cd13467409c555cae89714bd2017f14033100d9012f5982692aafd2`，133行。

- L4: `@MainActor final class NotchFaceObservationController {`
- L29: `func start(cameraID: String) {`
- L71: `private func finish(title: String, detail: String = "可稍后重试", token: UInt64) {`
- L82: `func cancel(restoreFocus: Bool = true) {`
- L100: `@MainActor final class NotchFaceObservationView: NSView, NotchInteractiveContent {`
- L123: `override func layout() {`
- L130: `func update(title: String, detail: String) { self.title.stringValue = title; self.detail.stringValue = detail }`
- L131: `@objc private func cancelRequest() { onCancel?() }`
- L132: `override func cancelOperation(_ sender: Any?) { onCancel?() }`

## `prototype/App/PeripheralBatterySource.swift`

SHA256: `149935ed50964a0c77b69551a56551aa2d26ee84e9194e098f3cf61f4ece8d36`，159行。

- L14: `final class PeripheralBatterySource: @unchecked Sendable {`
- L15: `struct Peripheral: Sendable {`
- L35: `func start() {`
- L62: `func stop() {`
- L87: `private func drainMatched(_ iterator: io_iterator_t, initialSnapshot: Bool) {`
- L102: `private func drainTerminated(_ iterator: io_iterator_t) {`
- L115: `private func refreshAll() {`
- L119: `private func read(_ service: io_object_t, identity: DeviceIdentity) {`
- L133: `static func identity(of service: io_object_t) -> DeviceIdentity? {`
- L150: `static func intProperty(_ service: io_object_t, _ key: String) -> Int? {`

## `prototype/App/Reconcile.swift`

SHA256: `290d8fb4dcb1b14e79620279ff9e30b42e81fbaa86c68678808a5073bd333f04`，209行。

- L7: `func updateReconcileTimer() {`
- L25: `func shouldRetryJournalRescue(now: Date) -> Bool {`
- L30: `func sourceWindowLooksUserVisible(state: ShadeState, pos: CGPoint, size: CGSize,`
- L65: `func shouldLogReconcileInvalidCount(_ count: Int) -> Bool {`
- L68: `func sourceWindowMissingShouldCleanup(id: CGWindowID, state: ShadeState) -> Bool {`
- L91: `func reconcileShadedWindows(reason: String) {`
- L153: `func applyReconcileAXSnapshots(_ snapshots: [ReconcileAXSnapshot],`
- L203: `func finishReconcileShadedWindows() {`

## `prototype/App/ShadeController.swift`

SHA256: `ffe5d474a28aa43ac12baf5e4a85b1d795494be0df928980fe6b4e69d8bb813f`，891行。

- L8: `func retargetToActiveSpaceWindow(pid: pid_t) -> (AXUIElement, CGWindowID)? {`
- L35: `func toggle() {`
- L87: `func performNativeStickiesShade(_ win: AXUIElement) {`
- L104: `func makeShadePlan(win: AXUIElement, pos: CGPoint, size: CGSize,`
- L157: `func resolvedSourceSpaceID(windowID id: CGWindowID,`
- L169: `func shade(_ win: AXUIElement, _ id: CGWindowID,`
- L178: `func admissionCurrent() -> Bool {`
- L184: `func completeFold(success: Bool, transaction: UUID? = nil) {`
- L303: `func installOverlay(_ overlay: NSWindow, mode: ShadeAppearanceMode, previewImage: NSImage?) {`
- L482: `func installInteractiveNativeCollapse(barH: CGFloat) -> Bool {`

## `prototype/App/WS2AgentSessionView.swift`

SHA256: `2eb4cc0b0ffd80413aeb0375a2b4973039174218273be6988b5fc1a8f730e53d`，47行。

- L3: `@MainActor final class WS2AgentSessionView: NSView, WS2LeaseContent {`
- L20: `func render(_ sessions:[AgentSessions.Session]) {`
- L41: `@objc private func pressed(_ sender:NSButton) {`
- L45: `override func cancelOperation(_ sender:Any?) { onCancel?() }`
- L46: `func revoke() { inputIsCurrent = { false }; render([]); bindings.removeAll() }`

## `prototype/App/WS2AppRuntime.swift`

SHA256: `99205e90fd9d99278da55fbfe88924e2100c4ada4223c6d35136da67cf5b6db2`，251行。

- L3: `@MainActor final class WS2AppRuntime {`
- L31: `func day(_ date: Date) -> String {`
- L108: `private func setLockReason(_ reason: String, locked: Bool) {`
- L119: `func applicationShouldTerminate() -> NSApplication.TerminateReply {`
- L138: `private func finishQuit(updaterReply:Bool?=nil,childrenReady:Bool=false,failed:Bool=false) {`
- L144: `func openOwned() {`
- L153: `private func openModelPicker() {`
- L192: `func open() {`
- L205: `func refreshFocusSettings() {`
- L210: `func toggleFocus() {`

## `prototype/App/WS2CodexApprovalHost.swift`

SHA256: `f400c3354906b3ddb97f7651388468520d91f5eb6796417d014d7753266bf03b`，250行。

- L5: `@MainActor final class WS2CodexApprovalHost: WS2OwnedProtocolHost {`
- L36: `func beginProtocol() throws {`
- L40: `func startThread(cwd: String, model: String) throws {`
- L45: `func resumeThread(_ id: String) throws {`
- L49: `func startTurn(text: String, model: String, effort: String) throws {`
- L54: `func steer(text: String, expectedTurn: String) throws {`
- L59: `func interruptTurn() throws {`
- L63: `func receive(_ bytes: Data) {`
- L87: `@discardableResult func present(_ id: WS2.RequestID) -> Bool {`
- L114: `private func confirm(beganAt: WS2.Instant, sequence: UInt64) {`

## `prototype/App/WS2ConductorView.swift`

SHA256: `35e1bb2d5b14f59c381aba5969009add1be93e97eb3eeb2005fd1d9607e6e225`，78行。

- L3: `@MainActor final class WS2ConductorView: NSView, WS2LeaseContent {`
- L5: `enum Action { case sendDraft(String), discardDraft, confirmCost, stopTurn, leave, session(Int) }`
- L32: `@discardableResult func render(_ state: ConductorNotch) -> Bool {`
- L63: `private func button(_ label:String,_ action:Action) {`
- L67: `@objc private func pressed(_ sender:NSButton) {`
- L76: `override func cancelOperation(_ sender:Any?) { onCancel?() }`
- L77: `func revoke() { buttons.removeAll(); inputIsCurrent = { false }; editor.stringValue = ""; title.stringValue = ""; detail.stringValue = ""; path.path=nil }`

## `prototype/App/WS2DeviceActionHost.swift`

SHA256: `e969db6f1d29d4dc2af25afb99a58e90281b395480a704193de53e3b5cf2e5a7`，106行。

- L4: `@MainActor final class WS2DeviceActionHost {`
- L35: `func start() { bridge.start() }`
- L37: `private func clear(_ id: UUID) {`
- L41: `@discardableResult func enable(_ id: UUID) -> Bool {`
- L51: `func disable(_ id: UUID) { clear(id); _ = bridge.setEnabled(false, attachment: id) }`
- L52: `func environmentChanged() {`
- L56: `private func receive(_ input: WS2ControllerInput) {`
- L96: `private static func intent(_ name: String) -> WS2SemanticInputRouter.Intent? {`
- L105: `func stop() { for id in Array(contexts.keys) { clear(id) }; bridge.stop() }`

## `prototype/App/WS2FoldCallbackGuard.swift`

SHA256: `9f8d8cc688955c493ac17ebde396f59f70892e32c0b78250c78589c007fc63db`，100行。

- L5: `func foldCallbackStamp(id: CGWindowID, state: ShadeState) -> WS2FoldCallbackStamp {`
- L13: `func foldWaiterDeliveryStamp(id: CGWindowID, transaction: UUID) -> WS2FoldCallbackStamp? {`
- L21: `func foldCallbackIsCurrent(_ expected: WS2FoldCallbackStamp,`
- L30: `func observeFoldHide(_ hide: HideMethod, win: AXUIElement, pid: pid_t,`
- L68: `func retainUnconfirmedFold(id: CGWindowID, state: ShadeState) {`
- L84: `func receiveFoldAXNotification(routeID: UInt, notification: String) {`
- L96: `func axObservedBoolAttribute(_ win: AXUIElement, _ attribute: String) -> Bool? {`

## `prototype/App/WS2GameControllerBridge.swift`

SHA256: `cf257e4e8233d7030b96e5b317d02043024d25f2d03dc27824dd9976394881ee`，186行。

- L5: `@MainActor final class WS2GameControllerBridge: WS2ControllerBridge {`
- L9: `@MainActor private final class Entry {`
- L32: `func start() {`
- L52: `@discardableResult func setEnabled(_ enabled: Bool, attachment: UUID) -> Bool {`
- L67: `func environmentChanged() {`
- L80: `func suspendAll() { for e in entries.values { suspend(e) }; publish() }`
- L81: `private func reconcile() {`
- L97: `private func installHandler(_ e: Entry) -> Bool {`
- L108: `private func releaseHandler(_ e: Entry) {`
- L117: `private func sample(_ e: Entry) {`

## `prototype/App/WS2IslandCoordinator.swift`

SHA256: `315bf8f9b76ead7600c8829b69c4609bf89d919f3421631b3154aedd13acd91f`，101行。

- L3: `@MainActor protocol WS2LeaseContent: NotchInteractiveContent {`
- L6: `func revoke()`
- L8: `@MainActor final class WS2IslandCoordinator {`
- L32: `private static func displayID(_ screen: NSScreen) -> WS2.DisplayID? {`
- L35: `@discardableResult func show(_ content: NSView & WS2LeaseContent, ownerID: String, layer: WS2.Layer = .opened,`
- L60: `func inputHandle(for content: NSView) -> WS2.LeaseHandle? {`
- L65: `func handOffToAuthorization() { dismissed = nil; dismiss() }`
- L66: `func dismiss() { if let handle { leases.release(handle, at: clock.now()) } }`
- L67: `func dismiss(ifShowing content: NSView) { if view === content { dismiss() } }`
- L68: `func handOffToAuthorization(ifShowing content: NSView) -> Bool {`

## `prototype/App/WS2ModelPickerView.swift`

SHA256: `1da4c59ec557195a5b03760eb038b2d8fe1ecabb2f733f2c29ab554d8790f73c`，179行。

- L4: `@MainActor final class WS2ModelPickerView: NSView, WS2LeaseContent, NSTableViewDataSource, NSTableViewDelegate {`
- L79: `override func viewDidMoveToWindow() {`
- L96: `func sync() {`
- L112: `func renderDevices(_ devices: [WS2ControllerDevice]) {`
- L128: `private func renderHint() {`
- L132: `private func showSelection() {`
- L137: `func numberOfRows(in tableView: NSTableView) -> Int { rows.count }`
- L138: `func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {`
- L145: `func tableViewSelectionDidChange(_ notification: Notification) {`
- L149: `@objc private func toggleDevice() {`

## `prototype/App/WS2OwnedCodexSession+Authorization.swift`

SHA256: `cd619ed648b81d55565ecf519777681ab4419bd2374eecb1f793c7bf29538266`，18行。


## `prototype/App/WS2OwnedLaunchController.swift`

SHA256: `302f4b8ad841610a8a471caf79af657a5c8bc5d10e9c0e0a8d954363160a4ed2`，311行。

- L4: `/// AgentSessions remain the authorities for protocol state and backend sessions respectively.`
- L5: `@MainActor final class WS2OwnedLaunchController {`
- L6: `enum Phase: Equatable { case idle, checkingVersion, connecting, checkingConfig, signedOut, ready, creatingThread, sending, running, interrupting, completed, failed, stopping, stopped }`
- L7: `private enum Query { case config, account, login, cancelLogin, logout }`
- L8: `private struct Submission { let text:String;let model:String;let effort:String }`
- L9: `private struct Association { let project:WS2OwnedScope.Project;let thread:String }`
- L60: `@discardableResult func editDraft(_ value:String) -> Bool {`
- L63: `@discardableResult func selectProject(_ url:URL) -> Bool {`
- L74: `@discardableResult func selectExecutable(_ url:URL) -> Bool {`
- L78: `@discardableResult func launch(consent:Bool,diagnostics:Bool=false) -> Bool {`

## `prototype/App/WS2OwnedSessionView.swift`

SHA256: `d3360e975925f28b112b32d4c51b9a75d195a507629793e5e5b3d3eed006434f`，154行。

- L4: `@MainActor final class WS2OwnedSessionView: NSView, WS2LeaseContent, NSTextViewDelegate {`
- L45: `func row(_ views:[NSView]) -> NSStackView { let r=NSStackView(views:views);r.orientation = .horizontal;r.spacing=8;return r }`
- L75: `private func configure(_ text:NSTextView,editable:Bool) {`
- L82: `func scheduleRender() {`
- L89: `func render() {`
- L117: `func textDidChange(_ notification:Notification) {`
- L121: `private func choose(directory:Bool) {`
- L132: `@objc private func pickProject() { choose(directory:true) }`
- L133: `@objc private func pickExecutable() { choose(directory:false) }`
- L134: `@objc private func consentChanged() { render() }`

## `prototype/Core/AgentSessions.swift`

SHA256: `218b3910959c810d5662d608b8ab9560d5232cf5e69930c330b400c940c65d7c`，260行。

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

## `prototype/Core/AuthorizationLedger.swift`

SHA256: `495d1ce534fe560c8c0fe43ee6fd2bb5e9e24b7f82b172978ffdd62143985676`，157行。

- L16: `enum AuthFailure: Error, Equatable, Sendable {`
- L21: `protocol AuthRandomSource {`
- L22: `func bytes(_ count: Int) -> [UInt8]?`
- L25: `struct SystemAuthRandom: AuthRandomSource {`
- L26: `func bytes(_ count: Int) -> [UInt8]? {`
- L33: `@MainActor final class AuthorizationGrant {`
- L34: `enum State: Equatable { case live, consumed, revoked(AuthFailure) }`
- L53: `@MainActor final class AuthorizationLedger {`
- L55: `nonisolated static func monotonicNow() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }`
- L83: `func begin(target: AuthTarget, ttl: UInt64) -> Result<AuthRequest, AuthFailure> {`

## `prototype/Core/CodexWire.swift`

SHA256: `ed2e3e209bb3ff42c6ba8273b323f2b6f70bdf48daa4cc21f91060d9bfebecf3`，271行。

- L3: `indirect enum WireJSON: Codable, Equatable, Sendable {`
- L15: `func encode(to encoder: any Encoder) throws {`
- L33: `struct CodexWire: Sendable {`
- L34: `enum Failure: Error { case oversized, closed, malformed, notReady, unsupported, stale, capacity }`
- L35: `enum State: Equatable, Sendable { case fresh, initializing, listingModels, ready, closed }`
- L36: `struct Pending: Sendable { let method: String; let deadline: WS2.Instant }`
- L37: `enum Event: Equatable, Sendable {`
- L42: `static let maximumFrame = 1_048_576 // Recommendation: bounded metadata stream; not a measured protocol maximum.`
- L59: `mutating func drain() -> [Data] { defer { outbound.removeAll(keepingCapacity:true) }; return outbound }`
- L60: `private mutating func send(_ value: WireJSON) throws {`

## `prototype/Core/ConductorCapabilities.swift`

SHA256: `4494697451f96b08ea1c1bf92fbb83ec9539055ac06937edef392558c20c9af0`，101行。

- L5: `struct ConductorCapabilities: Equatable, Sendable {`
- L17: `enum Resolution: Equatable, Sendable {`
- L21: `func resolve(_ requested: ConductorEffort, keeping current: String) -> Resolution {`
- L37: `func accepts(_ config: WS2.ExecutionConfig) -> Bool {`
- L49: `struct ConductorModelSlots: Sendable {`
- L55: `enum Selection: Equatable, Sendable {`
- L59: `func select(_ number: Int, in completeSnapshot: [ConductorCapabilities]) -> Selection {`
- L69: `struct ConductorCostCandidate: Equatable, Sendable {`
- L76: `struct ConductorCostVault: Sendable {`
- L77: `struct Ticket: Equatable, Sendable {`

## `prototype/Core/ConductorSession.swift`

SHA256: `e426c0b1a19fd8bea29528f707371decf0ac65459e3c85dbd6d6e2f94e7f2e7d`，646行。

- L5: `enum ConductorNotch: Equatable, Sendable {`
- L50: `struct ConductorSession: Sendable {`
- L51: `struct SessionChoice: Equatable, Sendable { let context: WS2.Context; let label: String; let running: Bool }`
- L52: `enum TouchPhase: Sendable { case begin, move, end, cancel }`
- L53: `enum Reconciliation: Sendable {`
- L56: `enum Event: Sendable {`
- L80: `enum Effect: Equatable, Sendable {`
- L93: `struct Draft: Equatable, Sendable { let text: String; let digest: WS2.Digest; let revision: UInt64; let owner: WS2.Context }`
- L94: `private struct Press: Sendable { let id: UInt64; let beganAt: WS2.Instant; let sequence: UInt64; var consumed = false }`
- L95: `private struct Stroke: Sendable { let beganAt: WS2.Instant; let sequence: UInt64; var points: [ConductorPoint] }`

## `prototype/Core/Contracts.swift`

SHA256: `12fffc2e5cf207aa0ca6b4c371f28b9eec8c2b374b5e1a06d8943878891b2420`，327行。

- L6: `enum WS2 {`
- L8: `struct Instant: Hashable, Comparable, Sendable, Codable {`
- L20: `func adding(_ duration: UInt64) -> Self {`
- L25: `func elapsed(since earlier: Self) -> UInt64 {`
- L32: `enum Duration {`
- L39: `struct TimeGate: Sendable {`
- L41: `mutating func accept(_ now: Instant) -> Bool {`
- L50: `struct EventGate: Sendable {`
- L53: `mutating func accept(sequence: UInt64, at now: Instant) -> Bool {`
- L62: `enum TokenDomain: String, Hashable, Sendable, Codable { case unspecified, focusTimer, presenceLock, conductor, interaction }`

## `prototype/Core/DeviceBattery.swift`

SHA256: `7777539671486437ff4e26398663d7187b31401405d866362efde3caadc473e3`，177行。

- L16: `enum DeviceKind: String, Codable, Sendable {`
- L20: `enum BatteryComponent: String, Codable, Sendable {`
- L25: `enum ChargingState: String, Codable, Sendable {`
- L29: `enum BatteryKind: String, Codable, Sendable {`
- L33: `struct DeviceIdentity: Equatable, Sendable {`
- L41: `struct BatteryReading: Equatable, Sendable {`
- L56: `static func validPercent(_ raw: Int?) -> Int? {`
- L62: `enum BatteryFreshness: Equatable, Sendable { case currentEnough, aged, unknown }`
- L64: `enum DeviceBatteryEvent: Equatable, Sendable {`
- L74: `struct DeviceBatteryBook: Sendable {`

## `prototype/Core/HIDMappingTransaction.swift`

SHA256: `48edb2bb043ddd6cf18285f422ae90e4f75b258ee75efd9c6976fd7ef973a3d6`，30行。

- L3: `struct HIDMappingTransaction: Sendable {`
- L4: `enum Failure: Error { case nonUniqueDevice, stale, notOwned, malformed }`
- L5: `struct Device: Equatable, Sendable { let registryID: UInt64; let vendor: Int; let product: Int }`
- L6: `struct Write: Equatable, Sendable { let device: Device; let expected: Data; let replacement: Data }`
- L8: `mutating func prepare(device: Device, matches: [Device], current: Data, replacement: Data) throws -> Write {`
- L16: `mutating func commit(_ write: Write, readback: Data) throws {`
- L20: `func restore(device: Device, current: Data) throws -> Write {`
- L25: `mutating func restored(_ write: Write, readback: Data) throws {`

## `prototype/Core/NotchActivities.swift`

SHA256: `e5c6c6fc339b58175672abea1322b5aeaa0c526ab850a4a0b0d7c48280f5c10b`，266行。

- L13: `enum NotchActivityAction: String {`
- L18: `enum NotchActivityKind: String, Codable, Sendable, CaseIterable {`
- L40: `struct NotchActivity: Equatable, Sendable {`
- L88: `struct NotchActivityStore {`
- L137: `mutating func upsert(_ activity: NotchActivity, now: Double) -> Bool {`
- L170: `mutating func end(id: String, generation: UInt64, now: Double) -> Bool {`
- L182: `mutating func prune(now: Double) {`
- L196: `mutating func select(id: String) -> Bool {`
- L203: `mutating func moveSelection(by delta: Int) {`
- L218: `private static func validNow(_ now: Double) -> Bool {`

## `prototype/Core/PairingAttemptWindow.swift`

SHA256: `262dc840763d31105c16f5edda749a2e11ea15064158884c825109fbcd3450e3`，39行。

- L3: `struct PairingAttemptWindow: Sendable {`
- L4: `enum Failure: Error { case badTime, coolingDown, alreadyOpen, invalidPIN, unavailable }`
- L17: `mutating func open(at now: Double, makePIN: () -> String) throws -> String {`
- L26: `func mayAttempt(at now: Double) -> Bool {`
- L29: `mutating func failed(at now: Double) throws {`
- L34: `mutating func finish(at now: Double) throws {`
- L37: `mutating func cancel() { deadline = nil; pin = nil } // 取消不能抹去冷却。`
- L38: `static func randomPIN() -> String { String(format:"%04d",Int.random(in:0...9999)) }`

## `prototype/Core/PairingTLV.swift`

SHA256: `32495002c85cc927a8c31cd5699ff517f070107120c111919e9b35c1df2f3845`，39行。

- L3: `enum PairingTLV {`
- L4: `enum Failure: Error { case oversized, truncated, duplicate, invalidFragment, invalidType }`
- L6: `static func decode(_ data: Data, allowed: Set<UInt8>) throws -> [UInt8:Data] {`
- L24: `static func encode(_ entries: [(UInt8,Data)]) throws -> Data {`

## `prototype/Core/PresenceLock.swift`

SHA256: `7099b9f42bc09683ac35dd345020a58429bd2e9e19db4823082df19ad7540188`，295行。

- L4: `struct PresenceLock: Sendable {`
- L5: `enum Device: String, Hashable, Sendable { case phone, watch }`
- L6: `enum Status: Equatable, Sendable { case unknown, connecting, present, away }`
- L7: `enum LockState: Sendable { case unknown, unlocked, locked }`
- L8: `enum Reason: Equatable, Sendable { case devices, camera }`
- L9: `enum Phase: Equatable, Sendable {`
- L13: `struct Configuration: Sendable {`
- L20: `enum Event: Sendable {`
- L36: `enum Effect: Equatable, Sendable {`
- L43: `private struct Probe: Sendable { let id: UInt64; let deadline: WS2.Instant }`

## `prototype/Core/RemoteMode.swift`

SHA256: `559d83d94615574613c9ec13a92ddf9395a55157c21f3eaff0e60b61bb48b3d7`，89行。

- L4: `struct RemoteMode: Sendable {`
- L5: `enum Mode: String, Equatable, Sendable { case remote, conductor }`
- L6: `enum Effect: Equatable, Sendable {`
- L13: `private struct Press: Sendable { let id: UInt64; var consumed = false }`
- L20: `mutating func setEnabled(_ value: Bool) -> [Effect] {`
- L26: `mutating func handle(_ event: WS2.ButtonEvent) -> [Effect] {`
- L72: `private func short(_ button: WS2.Button) -> [Effect] {`

## `prototype/Core/SessionLockState.swift`

SHA256: `1f92f697f9a7c1b5add7c4842496b86d4e65b93f2985e10f08ba3662a82ebe75`，16行。

- L5: `enum SessionLockState: Equatable {`
- L8: `static func resolve(locked: Bool?, onConsole: Bool?, loginDone: Bool?, dictionaryPresent: Bool) -> Self {`

## `prototype/Core/WS2CompanionFrame.swift`

SHA256: `2ecb698bdf16965242836f132a7bc801d0ac7db7b488abc0d5a1b878a4c0fabd`，59行。

- L3: `struct WS2CompanionFrame: Equatable, Sendable {`
- L4: `enum Failure: Error { case closed, oversized, unsupportedType, invalidLength, exhausted }`
- L5: `static let maximumPayload = 65_536 // local cap, NOT the 24-bit protocol maximum`
- L9: `static func header(type: UInt8, count: Int) throws -> Data {`
- L14: `func encoded() throws -> Data { try Self.header(type: type, count: payload.count) + payload }`
- L15: `struct Decoder: Sendable {`
- L18: `mutating func close() { closed = true; bytes.removeAll(keepingCapacity: false) }`
- L20: `mutating func feed(_ input: Data) throws -> [WS2CompanionFrame] {`
- L48: `struct WS2CompanionCounter: Sendable {`
- L52: `mutating func take() throws -> Data {`

## `prototype/Core/WS2ConnectionBudget.swift`

SHA256: `f225317ecabd3143c7c40603ed7a1c2bb93f19f083c59722a6bddfc409be9cd2`，74行。

- L4: `struct WS2ConnectionBudget: Sendable {`
- L5: `struct Handle: Hashable, Sendable { let generation: UUID; let serial: UInt64 }`
- L6: `enum Handshake: Sendable { case pairSetup, pairVerify }`
- L7: `struct Peer: Hashable, Sendable { let id: String; let revision: UInt64 }`
- L8: `private struct Entry: Sendable { let deadline: WS2.Instant; var peer: Peer?; var queued: Int = 0 }`
- L23: `mutating func expire(at now: WS2.Instant) -> [Handle] {`
- L31: `mutating func admit(_ mode: Handshake, at now: WS2.Instant, locallyOpenedPairing: Bool) -> Handle? {`
- L43: `@discardableResult mutating func promote(_ handle: Handle, peer: Peer, at now: WS2.Instant) -> Bool {`
- L49: `func isCurrent(_ handle: Handle, peer: Peer?, at now: WS2.Instant) -> Bool {`
- L53: `@discardableResult mutating func reserve(_ bytes: Int, for handle: Handle, at now: WS2.Instant) -> Bool {`

## `prototype/Core/WS2FocusEffectPlan.swift`

SHA256: `60ccb717e3641f20e1fc499dc1e432ba37493e3c4abe8e28c73b2ebc19419829`，85行。

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

## `prototype/Core/WS2FocusWindowOwnership.swift`

SHA256: `69a0b9a82fd67c318d92b4bcedebd6f980b094f24b37197758fe1cf85f5ab3c7`，27行。

- L3: `struct WS2FocusWindowOwnership: Sendable {`
- L4: `struct Identity: Hashable, Sendable { let pid: Int32; let processStart: UInt64; let windowID: UInt32; let windowGeneration: UInt64 }`
- L5: `struct Receipt: Equatable, Sendable {`
- L13: `mutating func record(_ receipt: Receipt, didComplete: Bool) -> Bool {`
- L18: `mutating func takeForRestore(_ id: Identity, run: WS2.Token, effectGeneration: UInt64, liveRevision: UInt64) -> Receipt? {`
- L24: `mutating func manualChange(_ id: Identity) { owned[id] = nil }`
- L25: `mutating func clear() { owned.removeAll() }`

## `prototype/Core/WS2FoldCallbackStamp.swift`

SHA256: `50e53418e04733bbe0421c49533bd7e87943f25707f7404bedf188a4ed4543de`，39行。

- L5: `struct WS2FoldCallbackStamp: Equatable, Sendable {`
- L15: `func accepts(current: Self, now: TimeInterval, unlocked: Bool,`
- L29: `struct WS2FoldObserverRoute: Equatable, Sendable {`
- L36: `func ws2ObservedBoolean(_ raw: CFTypeRef?) -> Bool? {`

## `prototype/Core/WS2SelectionModel.swift`

SHA256: `c8fb3c0ac6564970d2daedee4d4708799ef0014a94a7bb22b99f18a85d86cf4c`，50行。

- L4: `struct WS2SelectionModel: Sendable {`
- L5: `struct Item: Equatable, Sendable { let id: String; let enabled: Bool }`
- L6: `struct Activation: Equatable, Sendable { let revision: UInt64; let serial: UInt64; let itemID: String }`
- L7: `enum Failure: Error { case invalidSnapshot, exhausted }`
- L14: `mutating func replace(_ next: [Item]) throws {`
- L25: `@discardableResult mutating func move(_ direction: Int, expectedRevision: UInt64) -> Bool {`
- L34: `@discardableResult mutating func select(id: String, expectedRevision: UInt64) -> Bool {`
- L38: `mutating func reserveActivation(expectedRevision: UInt64) -> Activation? {`
- L44: `mutating func consume(_ value: Activation) -> String? {`
- L49: `mutating func revoke() { pending = nil; items = []; selectedID = nil; if revision < .max { revision += 1 } else { exhausted = true } }`

## `prototype/Core/WS2StrictJSON.swift`

SHA256: `3c1edb48065c85d7b0fbed12ac8299df4d1931abecfe53019f9ea9cabdc9bb0d`，99行。

- L5: `struct WS2StrictJSON {`
- L6: `enum Failure: Error, Equatable { case syntax, duplicateKey, depth, nodes, size }`
- L7: `static func validate(_ data: Data, maximumBytes: Int = 1_048_576,`
- L15: `private struct Parser {`
- L19: `mutating func whitespace() { while let c=current, [9,10,13,32].contains(c) { index += 1 } }`
- L20: `mutating func expect(_ c:UInt8) throws { guard current == c else { throw Failure.syntax }; index += 1 }`
- L21: `mutating func node() throws { guard remaining > 0 else { throw Failure.nodes }; remaining -= 1 }`
- L22: `mutating func value(_ depth:Int) throws {`
- L53: `mutating func literal(_ text:[UInt8]) throws { for byte in text { try expect(byte) } }`
- L54: `func digit(_ c:UInt8?) -> Bool { c.map { (48...57).contains($0) } ?? false }`

## `prototype/Core/WS2VisibleListInput.swift`

SHA256: `919b37b1add050fa65660fa70127a8dc131e659675ebedf791b86277d5acf425`，70行。

- L4: `@MainActor final class WS2VisibleListInput {`
- L14: `func replace(_ items: [WS2SelectionModel.Item], selectedID: String?) throws {`
- L20: `func bind(_ context: WS2SemanticInputRouter.Context?) {`
- L24: `@discardableResult func select(_ id: String) -> Bool {`
- L30: `@discardableResult func prepare(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool {`
- L39: `func cancel(context: WS2SemanticInputRouter.Context, presses: [UInt64]) {`
- L43: `func cancelAll() {`
- L48: `@discardableResult func execute(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool {`
- L69: `func revoke() { ready = false; context = nil; prepared = nil; selection.revoke(); onArmed?(nil) }`

## `prototype/Effects/EffectFrameAwaiter.swift`

SHA256: `9c7a967621855e6add53c5ee4cd405249142d018eea497e5301ebae72e0e42c8`，32行。

- L3: `enum EffectFrameAwaiter<Value> {`
- L6: `static func first(`

## `prototype/Native/WS2Child.c`

SHA256: `134368aa12dfbbb9ec5a6f60a121c44b52b46bb303d55d73b18d78326d875f47`，167行。

- L16: `struct WS2Child {`
- L23: `struct timespec value;`

## `prototype/Native/module.modulemap`

SHA256: `9cac42ba9402e4324e393d07c155c9375e20846e3bca84117460fdd0e6a0db8e`，4行。


## `prototype/Private/LockSpaceBridge.swift`

SHA256: `d16128cca2e5b893900e5d5165353724a780e76beddc5ffa79f4ac4a2bf8978f`，75行。

- L6: `final class LockSpaceBridge {`
- L41: `func attach(_ panel: NSWindow) -> Bool {`
- L67: `func detach(_ panel: NSWindow) {`

## `prototype/Recovery/DurableShadeJournal.swift`

SHA256: `5dbcd013cc44573bfef4b028dae0ca44c75c963d7df131cf20b946a737c366c8`，34行。

- L4: `struct DurableShadeJournal {`
- L11: `func load() throws -> [[String: Any]]? {`
- L22: `func save(_ entries: [[String: Any]]) throws {`

## `prototype/Recovery/Journal.swift`

SHA256: `5ffdb659b88cba3b72a346192fef9ba0c6a0eb22fad68aebd0681c09eb5b85aa`，235行。

- L12: `func shadeJournalEntries() -> [[String: Any]] {`
- L20: `func saveShadeJournalEntries(_ entries: [[String: Any]]) -> Bool {`
- L32: `func journalNumber(_ entry: [String: Any], _ key: String) -> Double? {`
- L39: `func journalString(_ entry: [String: Any], _ key: String) -> String {`
- L43: `func journalID(_ entry: [String: Any]) -> CGWindowID? {`
- L52: `func pruneShadeJournal(reason: String) {`
- L66: `func recordShadeJournal(id: CGWindowID, win: AXUIElement, hide: HideMethod,`
- L124: `func recordShadeRecoveryIntent(id: CGWindowID, pid: pid_t, bundleID: String,`
- L157: `func updateShadeJournal(id: CGWindowID, reason: String,`
- L169: `func markShadeJournalStage(id: CGWindowID, _ stage: ShadeLifecycleStage,`

## `prototype/Recovery/Rescue.swift`

SHA256: `26cc2ce87db65aa2b49a134cbac248a1c69740bb0aadd042ad45631ff1ce2428`，277行。

- L10: `struct OffscreenRescueAction {`
- L20: `struct JournalAlphaRestore {`
- L25: `struct JournalRescueResult {`
- L39: `func isAtWindowShadeParkingSpot(_ pos: CGPoint) -> Bool {`
- L40: `func onParkingBand(_ v: CGFloat) -> Bool {`
- L43: `func looksLikeWindowAxis(_ v: CGFloat) -> Bool {`
- L53: `func collectJournalRescueActions(targetTopLeft: CGPoint,`
- L124: `func rescueActionVerified(_ action: OffscreenRescueAction) -> Bool {`
- L137: `func alphaRestoreVerified(_ restore: JournalAlphaRestore) -> Bool {`
- L142: `func pruneRescuedJournalEntries(rescuedIDs: Set<CGWindowID>) {`

## `prototype/Support/WS2CompanionCrypto.swift`

SHA256: `d50a35fcb45ba1905fb26a6c3c4f14a7dd450bb8413b13bfcf8429b0a7eed8e8`，120行。

- L2: `// See decisions/01-配对与加密.md for the observed protocol and the missing enrollment gate.`
- L6: `@MainActor final class WS2CompanionCrypto {`
- L7: `enum Failure: Error { case state, expired, malformed, unknownPeer, signature, revoked, closed }`
- L8: `struct Peer: Equatable {`
- L14: `struct Identity {`
- L19: `@MainActor final class VerifiedSession {`
- L31: `func close() { transmit = nil; receive = nil; tx.close(); rx.close() }`
- L32: `func seal(_ plaintext: Data) throws -> Data {`
- L42: `func open(_ frame: WS2CompanionFrame) throws -> Data {`
- L52: `private enum State { case fresh, proving, finished, closed }`

## `prototype/Support/WS2CompanionTCPTransport.swift`

SHA256: `78bccef841039bf2d4fb5058ae21e01633da6f2e00435eb1a17b9ca2cd273266`，109行。

- L7: `@MainActor final class WS2CompanionTCPTransport {`
- L24: `func start() {`
- L41: `@discardableResult func enqueue(_ bytes: Data, deadline: Double) -> Bool {`
- L47: `private func receive() {`
- L65: `private func sendNext() {`
- L85: `func setProtocolDeadline(_ deadline: Double) {`
- L90: `private func scheduleTimeout() {`
- L102: `func close() {`

## `prototype/Support/WS2DuplexProcess.swift`

SHA256: `1efe08a7d6987fdac80d87f345f1d2ce212e6a5dddac3a71e086e247d8ab579a`，248行。

- L11: `@MainActor final class WS2DuplexProcess {`
- L12: `enum Failure: Error { case invalid, io(Int32), notRunning }`
- L13: `enum End: Equatable { case localStop, eof, processExit, io(Int32), framing, timeout, revoked }`
- L14: `struct Termination: Equatable, Sendable { let status: Int32; let wasSignalled: Bool }`
- L57: `func start() throws {`
- L96: `private func pollChild() {`
- L120: `@discardableResult func admit(_ lines: [Data], connection: UUID, deadline: Double,`
- L131: `@discardableResult func admitWireFrames(_ frames: [Data], connection: UUID, deadline: Double,`
- L143: `private func armWrite() { if !writeArmed, !stopped { writeArmed = true; writer?.resume() } }`
- L144: `private func disarmWrite() { if writeArmed { writeArmed = false; writer?.suspend() } }`

## `prototype/Support/WS2FocusEffectExecutor.swift`

SHA256: `674a8760579e1eccf401f6c949d6fcf69b74257943fe795b043f255b7c3887bf`，35行。

- L3: `@MainActor protocol WS2FocusMutationPort: AnyObject {`
- L6: `func perform(_ operation: WS2FocusEffectPlan.Operation,`
- L10: `@MainActor final class WS2FocusEffectExecutor {`
- L16: `func transition(run: WS2.Token?, windows: [WS2FocusEffectPlan.Window]) throws {`
- L19: `func suspend() { plan.setSuspended(true) }`
- L20: `func resumeAfterVerifiedUnlock() { plan.setSuspended(false); pump() }`
- L21: `func manualChange(_ identity: WS2FocusEffectPlan.Identity) { plan.manualChange(identity); pump() }`
- L23: `func end() throws { try transition(run: nil, windows: []) }`
- L24: `private func pump() {`

## `prototype/Support/WS2KeychainPeerStorage.swift`

SHA256: `ffe7ecc5a1bbd58497156c645a074506371039f49ceb92bfc2d9b2c6f36a395f`，46行。

- L7: `@MainActor final class WS2KeychainPeerStorage: WS2PeerStorage {`
- L8: `struct Failure: Error { let status: OSStatus }`
- L20: `func read() throws -> Data? {`
- L31: `func replace(_ bytes: Data, creating: Bool) throws {`

## `prototype/Support/WS2LocalLaunchProfile.swift`

SHA256: `34a52b15e0a183c0e0f8d45d999ab15e0f8d1b1998b7fa467fe15a4b1c843a27`，131行。

- L10: `struct WS2LocalLaunchProfile: Sendable {`
- L11: `enum Failure: Error { case unsafePath, configurationChanged, externalConfiguration, executableChanged }`
- L12: `struct FileIdentity: Equatable, Sendable {`
- L38: `static func prepare(projectURL:URL,projectID:UUID,executableURL:URL,root:URL) throws -> Self {`
- L73: `func revalidate() throws {`
- L84: `private static func identify(_ url:URL) throws -> FileIdentity {`
- L91: `private static func privateDirectory(_ url:URL) throws {`
- L102: `private static func rejectExternalConfiguration(_ project:WS2OwnedScope.Directory) throws {`
- L118: `static func admitsEffectiveConfig(_ response:WireJSON) -> Bool {`

## `prototype/Support/WS2PairSetupCrypto.swift`

SHA256: `6345ec9ff7339c0845f4140beac96577ee1310968d71dab941a0266d315e6fda`，71行。

- L3: `@MainActor protocol WS2SRPPrimitive: AnyObject {`
- L4: `func begin(pin: String) throws -> (salt: Data, publicKey: Data)`
- L6: `func verify(publicKey: Data, proof: Data) throws -> (serverProof: Data, key: Data)`
- L7: `func clear()`
- L14: `@MainActor final class WS2PairSetupCrypto: WS2PairSetupEngine {`
- L15: `enum Failure: Error { case state, malformed, signature }`
- L16: `private enum Phase { case fresh, started, proven, finished }`
- L27: `func begin(pin: String) throws -> (salt: Data, publicKey: Data) {`
- L31: `func verify(clientPublicKey: Data, proof: Data) throws -> Data {`
- L38: `private func derive(_ suffix: String) throws -> SymmetricKey {`

## `prototype/Support/WS2PairSetupServer.swift`

SHA256: `56ba109e6d1f63c8771cb0788c6c3af4796eed38cea5fe9880f744651c6516b1`，117行。

- L5: `@MainActor protocol WS2PairSetupEngine: AnyObject {`
- L6: `func begin(pin: String) throws -> (salt: Data, publicKey: Data)`
- L7: `func verify(clientPublicKey: Data, proof: Data) throws -> Data`
- L10: `func finish(encryptedM5: Data) throws -> (identifier: Data, publicKey: Data, encryptedM6: Data)`
- L11: `func clear()`
- L14: `@MainActor final class WS2PairingAdmission {`
- L15: `enum Failure: Error { case unavailable, busy, expired }`
- L27: `func openByLocalUser(makePIN: () -> String = PairingAttemptWindow.randomPIN) throws -> String {`
- L38: `func claim(_ connection: UUID) throws -> String {`
- L43: `func isCurrent(_ connection: UUID) -> Bool {`

## `prototype/Support/WS2PeerRepository.swift`

SHA256: `1ee4290d4151defac9a50b741c1128dbd8d6bcb7514cd4535ce39ac84f740b42`，127行。

- L4: `@MainActor protocol WS2PeerStorage: AnyObject {`
- L5: `func read() throws -> Data?`
- L6: `func replace(_ bytes: Data, creating: Bool) throws`
- L9: `@MainActor final class WS2PeerRepository {`
- L10: `enum Failure: Error { case unavailable, malformed, conflict, capacity, overflow, denied }`
- L11: `struct Peer: Codable, Equatable, Sendable {`
- L18: `struct Snapshot: Codable, Equatable, Sendable {`
- L34: `func load() throws {`
- L44: `func provision(identifier: Data, signingSeed: Data) throws {`
- L55: `private static func validate(_ value: Snapshot) throws {`

## `prototype/Support/WS2ProjectDirectory.swift`

SHA256: `7a9c30764d3199652eccc46265c4d7afae6c05cf65e1ee2a5be65c73bbd628a2`，26行。

- L4: `enum WS2ProjectDirectory {`
- L5: `enum Failure: Error { case notAbsoluteFileURL, notDirectory, missingIdentity }`
- L6: `static func read(_ url: URL) throws -> WS2OwnedScope.Directory {`
- L18: `static func contains(canonicalRoot root: String, canonicalCandidate candidate: String) -> Bool {`

## `prototype/Window/AXHelpers.swift`

SHA256: `b679b85d9e4e31f1a2f4594a048fba885c89b46bd25395e3fab768c880ab71b6`，255行。

- L9: `enum TrafficAction { case close, minimize, zoom, fullScreen }`
- L11: `enum ProxyTrafficLightStyle {`
- L16: `struct ProxyTrafficLightConfiguration {`
- L40: `func proxyTrafficLightConfiguration(of win: AXUIElement, pid: pid_t) -> ProxyTrafficLightConfiguration {`
- L73: `func urlFromAXAttribute(_ win: AXUIElement, _ attr: String) -> URL? {`
- L90: `func quickLookReopenURL(for win: AXUIElement) -> URL? {`
- L102: `func reopenQuickLookPreview(url: URL) -> Bool {`
- L116: `func postSpacebarKey() {`
- L125: `func reopenQuickLookFromFinderSelection(pid: pid_t) -> Bool {`
- L149: `enum SystemTitlebarDoubleClickAction: Equatable {`

## `prototype/build.sh`

SHA256: `7059bc9f7cf023359899cb35bcb92b3fa934e06f30bfb2f2737bed28a55c493d`，360行。

- L73: `collect_sources() {`

