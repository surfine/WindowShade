# 第七份源码地图

行号只适用于这里的 SHA256。编译状态按 VALIDATION 另行判断；下表不是 SDK 通过证明。

## docs/handoff/round2-part7/privacy-signals.json

add · 85 行 · SHA256 `511294f40bd1dd8231178d9906ac9748889a74c2001b3e02cc8a3c3987298499`

L49: `"purpose": "Display actual current reply and protocol state",`  

## prototype/App/Updater.swift

modify · 942 行 · SHA256 `d2f0aa355acde29b729d0a05fdf41b33269599bf7d5405df64e8117a9c0f2c03`

L16: `struct UpdateOffer: Equatable {`  
L25: `enum UpdateOfferStage { case notDownloaded, downloaded, installing }`  
L26: `enum UpdateReply { case install, skip, dismiss }`  
L29: `@MainActor protocol UpdaterBackend: AnyObject {`  
L30: `func start() throws`  
L31: `func checkForUpdates()`  
L37: `@MainActor func makeSparkleBackend(controller: UpdaterController) -> UpdaterBackend? { nil }`  
L40: `enum UpdateSettingsKeys {`  
L56: `final class UpdaterController: NSObject, NSMenuItemValidation {`  
L68: `private enum Session {`  
L102: `func start() {`  
L118: `private func scheduleLaunchFollowUps() {`  
L143: `private func markHealthyIfSelfCheckPasses() {`  
L163: `private func showLaunchNotice(_ notice: UpdateLaunchNotice) {`  
L199: `func makeMenuItem() -> NSMenuItem {`  
L205: `func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {`  
L213: `@objc func checkForUpdatesAction(_ sender: Any?) {`  
L217: `func checkForUpdates() {`  
L274: `func setSettingsStatus(_ text: String?) {`  
L280: `func bindSettings(statusLabel: NSTextField, frequency: NSSegmentedControl) {`  
L285: `private func refreshSettings() {`  
L290: `func rollBackToPrevious() {`  
L309: `private func blocker(for offer: UpdateOffer, ignoreRefused: Bool) -> UpdateBlocker? {`  
L323: `func backendIsUserInitiatedCheck() -> Bool { manualCheckInFlight }`  
L325: `func backendIsRefused(_ build: String) -> Bool { store.isRefused(build: build) }`  
L327: `func backendShowChecking() {`  
L332: `func backendFound(_ offer: UpdateOffer, stage: UpdateOfferStage, userInitiated: Bool,`  
L347: `func backendNotFound() {`  
L358: `func backendError(_ description: String, isNetwork: Bool) {`  
L387: `func backendFeedLoaded() {`  
L391: `func backendDownloadStarted(cancel: @escaping () -> Void) {`  
L400: `func backendDownloadExpected(_ length: UInt64) {`  
L405: `func backendDownloadReceived(_ length: UInt64) {`  
L411: `func backendExtracting() {`  
L419: `func backendReadyToInstall(reply: @escaping (UpdateReply) -> Void) {`  
L429: `func backendInstalling(applicationTerminated: Bool, retry: @escaping () -> Void) {`  
L438: `func backendDismissed() {`  
L461: `func backendFocus() {`  
L468: `func backendCycleFinished() {`  
L486: `private func presentOffer(_ offer: UpdateOffer, stage: UpdateOfferStage, reply: @escaping (UpdateReply) -> Void) {`  
L514: `private func finishOffer(_ reply: (UpdateReply) -> Void, _ choice: UpdateReply) {`  
L520: `private func showBlocker(_ blocker: UpdateBlocker, offer: UpdateOffer?,`  
L563: `private func showMoveFailed() {`  
L575: `private func beginInstall(_ offer: UpdateOffer, stage: UpdateOfferStage, reply: @escaping (UpdateReply) -> Void,`  
L615: `private func didPrepare(_ offer: UpdateOffer, stage: UpdateOfferStage, result: Result<UpdateBackupInfo, Error>,`  
L655: `private func resumeInstallation(_ offer: UpdateOffer, reply: @escaping (UpdateReply) -> Void) {`  
L669: `private func runGate(_ offer: UpdateOffer, journal: UpdateJournal, reply: @escaping (UpdateReply) -> Void) {`  
L690: `private func finishGate(_ offer: UpdateOffer, verdict: UpdateGate.Verdict, reply: @escaping (UpdateReply) -> Void) {`  
L733: `private func veto(_ offer: UpdateOffer, phase: UpdatePhase, reason: UpdateRestoreReason?, message: String?,`  
L753: `private func windDown(_ offer: UpdateOffer, message: String?) {`  
L766: `private func stopBeforeGate(_ offer: UpdateOffer, message: String?) {`  
L777: `private func settleApproved(_ offer: UpdateOffer, waited: TimeInterval = 0) {`  
L791: `private func proceedVeto() {`  
L797: `private func confirmInstallerStopped(offer: UpdateOffer, message: String?, openDownloadPage: Bool) {`  
L841: `private func abandon(_ offer: UpdateOffer, phase: UpdatePhase, message: String?) {`  
L851: `private func cleanUpAfterStop(_ offer: UpdateOffer, phase: UpdatePhase?) {`  
L860: `private func markThisUpdate(_ offer: UpdateOffer, phase: UpdatePhase, reason: UpdateRestoreReason?) {`  
L876: `func applicationShouldTerminate() -> NSApplication.TerminateReply {`  
L909: `private func startTerminateSafetyTimer() {`  
L931: `private func releaseTerminateIfPending() {`  
L939: `func applicationWillTerminate() {`  

## prototype/App/WS2AppRuntime.swift

modify · 205 行 · SHA256 `ae496e5fafe758ced14f91fa8ca9d042699e0b8a68062b51fae88073d7b4fe83`

L3: `@MainActor final class WS2AppRuntime {`  
L29: `func day(_ date: Date) -> String {`  
L102: `private func setLockReason(_ reason: String, locked: Bool) {`  
L113: `func applicationShouldTerminate() -> NSApplication.TerminateReply {`  
L132: `private func finishQuit(updaterReply:Bool?=nil,childrenReady:Bool=false,failed:Bool=false) {`  
L138: `func openOwned() {`  
L147: `func open() {`  
L160: `func refreshFocusSettings() {`  
L165: `func toggleFocus() {`  
L172: `@discardableResult func showSessions(_ sessions:[AgentSessions.Session], open:@escaping(WS2.Context)->Void,`  
L177: `@discardableResult func showConductor(_ state:ConductorNotch, action:@escaping(WS2ConductorView.Action)->Void) -> Bool {`  
L183: `private func publish() {`  
L191: `func stop() {`  
L203: `@objc func ws2OpenOwned() { MainActor.assumeIsolated { ws2Runtime.openOwned() } }`  
L204: `@objc func ws2OpenFocus() { MainActor.assumeIsolated { ws2Runtime.open() } }`  

## prototype/App/WS2CodexApprovalHost.swift

modify · 250 行 · SHA256 `f400c3354906b3ddb97f7651388468520d91f5eb6796417d014d7753266bf03b`

L5: `@MainActor final class WS2CodexApprovalHost: WS2OwnedProtocolHost {`  
L36: `func beginProtocol() throws {`  
L40: `func startThread(cwd: String, model: String) throws {`  
L45: `func resumeThread(_ id: String) throws {`  
L49: `func startTurn(text: String, model: String, effort: String) throws {`  
L54: `func steer(text: String, expectedTurn: String) throws {`  
L59: `func interruptTurn() throws {`  
L63: `func receive(_ bytes: Data) {`  
L87: `@discardableResult func present(_ id: WS2.RequestID) -> Bool {`  
L114: `private func confirm(beganAt: WS2.Instant, sequence: UInt64) {`  
L142: `private func target(_ review: WS2ApprovalReview) throws -> AuthTarget {`  
L145: `private func isCurrent(_ review: WS2ApprovalReview) -> Bool {`  
L150: `func tick() {`  
L160: `private func flush(deadline: WS2.Instant) {`  
L164: `private func abandonCurrent(decline: Bool) {`  
L173: `func invalidate() {`  
L179: `@MainActor private final class WS2ReviewButton: NSButton {`  
L189: `private func begin() -> Bool {`  
L192: `override func mouseDown(with event:NSEvent) { guard begin() else { return }; defer { press = nil }; super.mouseDown(with:event) }`  
L193: `override func keyDown(with event:NSEvent) {`  
L197: `override func accessibilityPerformPress() -> Bool {`  
L200: `@objc private func fire() { guard let press else { return }; freshAction?(press.0,press.1) }`  
L202: `@MainActor final class WS2CommandReviewView: NSView, WS2LeaseContent {`  
L231: `func enableConfirmation(){approval.isEnabled=inputIsCurrent()}`  
L232: `func revoke(){inputIsCurrent = { false };approval.isEnabled=false;text.string="";confirm=nil;decline=nil}`  
L233: `@objc private func refuse(){guard inputIsCurrent() else{return};decline?()}`  
L234: `override func cancelOperation(_ sender:Any?){onCancel?()}`  
L239: `func account(_ action:WS2AccountAction) throws -> WS2.RequestID {`  

## prototype/App/WS2OwnedCodexSession+Authorization.swift

add · 18 行 · SHA256 `cd619ed648b81d55565ecf519777681ab4419bd2374eecb1f793c7bf29538266`



## prototype/App/WS2OwnedCodexSession.swift

modify · 86 行 · SHA256 `b05f1a6d7aeafd72f5e8d5dea6cd8a460737d57cbf319b1c242b01a5f09d2ef8`

L3: `/// One engine for the real App and the process-backed protocol tests. It owns exactly one`  
L4: `/// child channel and one protocol host. The host factory cannot create a second transport.`  
L5: `@MainActor final class WS2OwnedCodexSession {`  
L57: `func start() throws {`  
L62: `func startThread(cwd:String,model:String) throws { try approval.startThread(cwd:cwd,model:model);scheduleExpiry() }`  
L63: `func resumeThread(_ id:String) throws { try approval.resumeThread(id);scheduleExpiry() }`  
L64: `func startTurn(text:String,model:String,effort:String) throws { try approval.startTurn(text:text,model:model,effort:effort);scheduleExpiry() }`  
L65: `func steer(text:String,expectedTurn:String) throws { try approval.steer(text:text,expectedTurn:expectedTurn);scheduleExpiry() }`  
L66: `func interrupt() throws { try approval.interruptTurn();scheduleExpiry() }`  
L67: `func account(_ action:WS2AccountAction) throws -> WS2.RequestID {`  
L70: `func clearDiagnostics() { channel.clearDiagnostics() }`  
L71: `private func scheduleExpiry() {`  
L80: `func stop() {`  

## prototype/App/WS2OwnedLaunchController.swift

add · 309 行 · SHA256 `631d6e462822fd75a3becc290c7b84492c7baacdc4b8adcbbd418dd125de3c07`

L4: `/// AgentSessions remain the authorities for protocol state and backend sessions respectively.`  
L5: `@MainActor final class WS2OwnedLaunchController {`  
L6: `enum Phase: Equatable { case idle, checkingVersion, connecting, checkingConfig, signedOut, ready, creatingThread, sending, running, interrupting, completed, failed, stopping, stopped }`  
L7: `private enum Query { case config, account, login, cancelLogin, logout }`  
L8: `private struct Submission { let text:String;let model:String;let effort:String }`  
L9: `private struct Association { let project:WS2OwnedScope.Project;let thread:String }`  
L58: `@discardableResult func editDraft(_ value:String) -> Bool {`  
L61: `@discardableResult func selectProject(_ url:URL) -> Bool {`  
L72: `@discardableResult func selectExecutable(_ url:URL) -> Bool {`  
L76: `@discardableResult func launch(consent:Bool,diagnostics:Bool=false) -> Bool {`  
L92: `private func begin(_ prepared:WS2LocalLaunchProfile,diagnostics:Bool) {`  
L118: `private func currentIsValid() -> Bool {`  
L123: `private func revalidate() -> Bool {`  
L127: `@discardableResult func chooseModel(_ value:String) -> Bool {`  
L131: `@discardableResult func chooseEffort(_ value:String) -> Bool {`  
L135: `@discardableResult func send(_ draft:String,hasMarkedText:Bool) -> Bool {`  
L147: `private func deliverSubmission() throws {`  
L153: `@discardableResult func resumeLast() -> Bool {`  
L159: `@discardableResult func interrupt() -> Bool {`  
L164: `@discardableResult func login() -> Bool {`  
L169: `@discardableResult func logout() -> Bool {`  
L174: `func cancelLogin() {`  
L181: `static func browserLoginURL(_ text:String) -> URL? {`  
L187: `private func receive(_ event:CodexWire.Event,connection:UUID) {`  
L254: `private func readAccount() throws {`  
L258: `private func synchronizeThreadAndTurn() throws {`  
L273: `private func emit(_ event:AgentSessions.Event,turn:String?=nil) {`  
L277: `private func ended(connection:UUID) {`  
L283: `func stop(reason:String="已断开连接",clearPrivate:Bool=false) {`  
L301: `func environmentChanged() {`  
L305: `private func fail(_ message:String) {`  
L308: `private func changed() { onChange?();if !isBusy { onQuiescent?() } }`  

## prototype/App/WS2OwnedSessionView.swift

add · 143 行 · SHA256 `ca1e124b84fd3f2138ee243eb2f3a0c175a03b9087f7eb1adc882fb727fe4ce8`

L4: `@MainActor final class WS2OwnedSessionView: NSView, WS2LeaseContent, NSTextViewDelegate {`  
L43: `func row(_ views:[NSView]) -> NSStackView { let r=NSStackView(views:views);r.orientation = .horizontal;r.spacing=8;return r }`  
L70: `private func configure(_ text:NSTextView,editable:Bool) {`  
L77: `func scheduleRender() {`  
L84: `func render() {`  
L111: `func textDidChange(_ notification:Notification) {`  
L115: `private func choose(directory:Bool) {`  
L126: `@objc private func pickProject() { choose(directory:true) }`  
L127: `@objc private func pickExecutable() { choose(directory:false) }`  
L128: `@objc private func consentChanged() { render() }`  
L129: `@objc private func start() { guard inputIsCurrent() else { return };_=controller.launch(consent:consent.state == .on,diagnostics:diagnostic.state == .on);render() }`  
L130: `@objc private func logIn() { guard inputIsCurrent() else { return };_=controller.login() }`  
L131: `@objc private func cancelLogIn() { guard inputIsCurrent() else { return };controller.cancelLogin() }`  
L132: `@objc private func logOut() { guard inputIsCurrent() else { return };_=controller.logout() }`  
L133: `@objc private func resumeSession() { guard inputIsCurrent() else { return };_=controller.resumeLast() }`  
L134: `@objc private func selectModel() { guard inputIsCurrent(),model.indexOfSelectedItem>0 else { return };_=controller.chooseModel(modelIDs[model.indexOfSelectedItem-1]) }`  
L135: `@objc private func selectEffort() { guard inputIsCurrent(),effort.indexOfSelectedItem>0 else { return };_=controller.chooseEffort(effortIDs[effort.indexOfSelectedItem-1]) }`  
L136: `@objc private func sendDraft() { guard inputIsCurrent() else { return };_=controller.send(draft.string,hasMarkedText:draft.hasMarkedText()) }`  
L137: `@objc private func interruptTurn() { guard inputIsCurrent() else { return };_=controller.interrupt() }`  
L138: `@objc private func stopSession() { guard inputIsCurrent() else { return };controller.stop() }`  
L139: `@objc private func toggleDiagnostics() { guard inputIsCurrent() else { return };displayingDiagnostics.toggle();diagnostics.title=displayingDiagnostics ? "返回回复":"查看诊断";render() }`  
L140: `func revoke() { renderTask?.cancel();renderTask=nil;inputIsCurrent={false};draft.inputContext?.discardMarkedText();draft.string="";output.string="";onCancel?() }`  
L143: `@MainActor private final class WS2OwnedDocumentView:NSView { override var isFlipped:Bool { true } }`  

## prototype/App/WS2SupplementPane.swift

modify · 36 行 · SHA256 `eb49bb23eda0c267d0c169dc4ef4040dd462ae3ed71f75aa341e2bfd96c39fcd`

L3: `@MainActor final class WS2SupplementPane: NSStackView {`  

## prototype/Core/CodexWire.swift

modify · 271 行 · SHA256 `ed2e3e209bb3ff42c6ba8273b323f2b6f70bdf48daa4cc21f91060d9bfebecf3`

L3: `indirect enum WireJSON: Codable, Equatable, Sendable {`  
L15: `func encode(to encoder: any Encoder) throws {`  
L33: `struct CodexWire: Sendable {`  
L34: `enum Failure: Error { case oversized, closed, malformed, notReady, unsupported, stale, capacity }`  
L35: `enum State: Equatable, Sendable { case fresh, initializing, listingModels, ready, closed }`  
L36: `struct Pending: Sendable { let method: String; let deadline: WS2.Instant }`  
L37: `enum Event: Equatable, Sendable {`  
L42: `static let maximumFrame = 1_048_576 // Recommendation: bounded metadata stream; not a measured protocol maximum.`  
L59: `mutating func drain() -> [Data] { defer { outbound.removeAll(keepingCapacity:true) }; return outbound }`  
L60: `private mutating func send(_ value: WireJSON) throws {`  
L66: `private mutating func request(_ method: String, _ params: [String:WireJSON]?, now: WS2.Instant) throws -> WS2.RequestID {`  
L74: `mutating func initialize(now: WS2.Instant) throws {`  
L79: `mutating func startThread(cwd: String, model: String, now: WS2.Instant) throws {`  
L87: `mutating func resumeThread(id: String, now: WS2.Instant) throws {`  
L95: `mutating func startTurn(text: String, model: String, effort: String, now: WS2.Instant) throws {`  
L104: `mutating func steer(text: String, expectedTurnID: String, now: WS2.Instant) throws {`  
L110: `mutating func interrupt(now: WS2.Instant) throws {`  
L115: `mutating func readConfig(cwd:String,now:WS2.Instant) throws -> WS2.RequestID {`  
L119: `mutating func readAccount(now: WS2.Instant) throws -> WS2.RequestID {`  
L123: `mutating func beginBrowserLogin(now: WS2.Instant) throws -> WS2.RequestID {`  
L127: `mutating func cancelLogin(id: String, now: WS2.Instant) throws -> WS2.RequestID {`  
L131: `mutating func logout(now: WS2.Instant) throws -> WS2.RequestID {`  
L135: `mutating func ingest(_ chunk: Data, now: WS2.Instant) throws -> [Event] {`  
L156: `private mutating func receive(_ v: WireJSON, now: WS2.Instant) throws -> [Event] {`  
L237: `mutating func denyApproval(_ id: WS2.RequestID) throws {`  
L246: `enum ApprovalWireDecision { case acceptOnce, decline }`  
L247: `mutating func enqueueApprovalResponse(_ id: WS2.RequestID, expectedMethod: String,`  
L260: `mutating func tick(now: WS2.Instant) -> [Event] {`  
L266: `mutating func close() {`  

## prototype/Core/WS2OwnedProtocolHost.swift

add · 85 行 · SHA256 `11defe55b4723986cdcd10cea154dfcc10f205dbb8d45eb1265c9dc84fe5b765`

L3: `enum WS2AccountAction { case read, login, cancel(String), logout, config(String) }`  
L6: `@MainActor protocol WS2OwnedProtocolHost: AnyObject {`  
L11: `func beginProtocol() throws`  
L12: `func startThread(cwd:String,model:String) throws`  
L13: `func resumeThread(_ id:String) throws`  
L14: `func startTurn(text:String,model:String,effort:String) throws`  
L15: `func steer(text:String,expectedTurn:String) throws`  
L16: `func interruptTurn() throws`  
L17: `func account(_ action:WS2AccountAction) throws -> WS2.RequestID`  
L18: `func receive(_ data:Data)`  
L19: `func tick()`  
L20: `func invalidate()`  
L25: `@MainActor final class WS2ReadOnlyProtocolHost: WS2OwnedProtocolHost {`  
L39: `private func check() throws { guard !closed else { throw CodexWire.Failure.closed } }`  
L40: `private func flush() {`  
L44: `func beginProtocol() throws { try check();try wire.initialize(now:clock.now());flush() }`  
L45: `func startThread(cwd:String,model:String) throws { try check();try wire.startThread(cwd:cwd,model:model,now:clock.now());flush() }`  
L46: `func resumeThread(_ id:String) throws { try check();try wire.resumeThread(id:id,now:clock.now());flush() }`  
L47: `func startTurn(text:String,model:String,effort:String) throws { try check();try wire.startTurn(text:text,model:model,effort:effort,now:clock.now());flush() }`  
L48: `func steer(text:String,expectedTurn:String) throws { try check();try wire.steer(text:text,expectedTurnID:expectedTurn,now:clock.now());flush() }`  
L49: `func interruptTurn() throws { try check();try wire.interrupt(now:clock.now());flush() }`  
L50: `func account(_ action:WS2AccountAction) throws -> WS2.RequestID {`  
L61: `func receive(_ data:Data) {`  
L79: `func tick() {`  
L84: `func invalidate() { guard !closed else { return };closed=true;wire.close();closeTransport() }`  

## prototype/Core/WS2QuitBarrier.swift

add · 20 行 · SHA256 `2a80a0409cee77c4a117844ac1192084ab922a1073b405d26909a6fd8a39754e`

L5: `struct WS2QuitBarrier: Sendable {`  
L6: `struct Token:Hashable,Sendable { let value:UUID }`  
L9: `mutating func begin(updaterReady:Bool,childrenReady:Bool) -> Token? {`  
L13: `mutating func update(_ expected:Token,updaterReply:Bool?=nil,childrenReady:Bool=false,failed:Bool=false) -> Bool? {`  

## prototype/Core/WS2StrictJSON.swift

add · 99 行 · SHA256 `3c1edb48065c85d7b0fbed12ac8299df4d1931abecfe53019f9ea9cabdc9bb0d`

L5: `struct WS2StrictJSON {`  
L6: `enum Failure: Error, Equatable { case syntax, duplicateKey, depth, nodes, size }`  
L7: `static func validate(_ data: Data, maximumBytes: Int = 1_048_576,`  
L15: `private struct Parser {`  
L19: `mutating func whitespace() { while let c=current, [9,10,13,32].contains(c) { index += 1 } }`  
L20: `mutating func expect(_ c:UInt8) throws { guard current == c else { throw Failure.syntax }; index += 1 }`  
L21: `mutating func node() throws { guard remaining > 0 else { throw Failure.nodes }; remaining -= 1 }`  
L22: `mutating func value(_ depth:Int) throws {`  
L53: `mutating func literal(_ text:[UInt8]) throws { for byte in text { try expect(byte) } }`  
L54: `func digit(_ c:UInt8?) -> Bool { c.map { (48...57).contains($0) } ?? false }`  
L55: `mutating func number() throws {`  
L65: `mutating func hex() throws -> UInt16 {`  
L74: `mutating func string() throws -> String {`  

## prototype/Native/WS2Child.c

add · 167 行 · SHA256 `134368aa12dfbbb9ec5a6f60a121c44b52b46bb303d55d73b18d78326d875f47`

L16: `struct WS2Child {`  
L23: `struct timespec value;`  
L46: `int ws2_child_spawn(const char *executable, char *const argv[], char *const envp[],`  
L140: `int ws2_child_poll(WS2Child *c, WS2ChildState *state) {`  
L156: `int ws2_child_stop(WS2Child *c) {`  
L161: `int ws2_child_destroy(WS2Child *c) {`  
L167: `pid_t ws2_child_pid(const WS2Child *c) { return c ? c->pid : -1; }`  

## prototype/Native/WS2Child.h

add · 27 行 · SHA256 `95380850f4cbd24d868fc785978cda939307f3962640b091200068a17ea1a9da`

L7: `typedef struct WS2Child WS2Child;`  
L17: `int ws2_child_spawn(const char *executable, char *const argv[], char *const envp[],`  
L21: `int ws2_child_poll(WS2Child *child, WS2ChildState *state);`  
L22: `int ws2_child_stop(WS2Child *child);`  
L25: `int ws2_child_destroy(WS2Child *child);`  
L26: `pid_t ws2_child_pid(const WS2Child *child);`  

## prototype/Native/module.modulemap

add · 4 行 · SHA256 `9cac42ba9402e4324e393d07c155c9375e20846e3bca84117460fdd0e6a0db8e`



## prototype/Support/WS2DuplexProcess.swift

modify · 248 行 · SHA256 `1efe08a7d6987fdac80d87f345f1d2ce212e6a5dddac3a71e086e247d8ab579a`

L11: `@MainActor final class WS2DuplexProcess {`  
L12: `enum Failure: Error { case invalid, io(Int32), notRunning }`  
L13: `enum End: Equatable { case localStop, eof, processExit, io(Int32), framing, timeout, revoked }`  
L14: `struct Termination: Equatable, Sendable { let status: Int32; let wasSignalled: Bool }`  
L57: `func start() throws {`  
L96: `private func pollChild() {`  
L120: `@discardableResult func admit(_ lines: [Data], connection: UUID, deadline: Double,`  
L131: `@discardableResult func admitWireFrames(_ frames: [Data], connection: UUID, deadline: Double,`  
L143: `private func armWrite() { if !writeArmed, !stopped { writeArmed = true; writer?.resume() } }`  
L144: `private func disarmWrite() { if writeArmed { writeArmed = false; writer?.suspend() } }`  
L145: `private func scheduleDeadline() {`  
L157: `private func writeReady() {`  
L183: `private func readReady(checkChild: Bool = true) {`  
L205: `private func readDiagnosticReady() {`  
L220: `func clearDiagnostics() { diagnostics?.clear() }`  
L221: `private static func writeWithoutSIGPIPE(_ fd: Int32, _ bytes: Data) -> Int {`  
L236: `func stop(_ reason: End = .localStop) {`  
L246: `// The reaper timer survives protocol closure. A stopped pipe is not reaping evidence.`  

## prototype/Support/WS2LocalLaunchProfile.swift

add · 131 行 · SHA256 `34a52b15e0a183c0e0f8d45d999ab15e0f8d1b1998b7fa467fe15a4b1c843a27`

L10: `struct WS2LocalLaunchProfile: Sendable {`  
L11: `enum Failure: Error { case unsafePath, configurationChanged, externalConfiguration, executableChanged }`  
L12: `struct FileIdentity: Equatable, Sendable {`  
L38: `static func prepare(projectURL:URL,projectID:UUID,executableURL:URL,root:URL) throws -> Self {`  
L73: `func revalidate() throws {`  
L84: `private static func identify(_ url:URL) throws -> FileIdentity {`  
L91: `private static func privateDirectory(_ url:URL) throws {`  
L102: `private static func rejectExternalConfiguration(_ project:WS2OwnedScope.Directory) throws {`  
L118: `static func admitsEffectiveConfig(_ response:WireJSON) -> Bool {`  

## prototype/Support/WS2VersionProbe.swift

add · 48 行 · SHA256 `8b77c9a8ce4ec1d66f5106736783ad5581572e45d761ebb7ec92c68756d7bd8f`

L4: `@MainActor final class WS2VersionProbe {`  
L35: `func start() throws {`  
L43: `func cancel() { invalid=true;channel.stop();finish(false) }`  
L44: `private func finish(_ ok:Bool) {`  

## prototype/WindowShade.swift

modify · 914 行 · SHA256 `4cbf3342bc01d1df701c23151617ad5df76bfe9a2b27c14f5149828c1242e228`

L79: `func framesAlmostEqual(_ a: NSRect, _ b: NSRect, tolerance: CGFloat = 0.5) -> Bool {`  
L86: `func cgWindowID(for window: NSWindow) -> CGWindowID? {`  
L94: `final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {`  
L96: `final class PendingTitlebarTripleClick {`  
L110: `struct PendingSpaceReturn {`  
L118: `struct ReconcileAXTarget {`  
L125: `struct ReconcileAXSnapshot {`  
L301: `func applicationDidFinishLaunching(_ note: Notification) {`  
L415: `func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {`  
L420: `@objc func systemAppearanceOptionsChanged(_ note: Notification) {`  
L451: `func installStandardMainMenu() {`  
L461: `private func migrateDistractingDefaultSounds() {`  
L490: `func refreshPinnedPreviewTarget(reason: String) {`  
L497: `private func setupPinnedPreviewFocusTracking() {`  
L510: `private func scheduleTitlebarPrefetch() {`  
L531: `private func schedulePinnedPreviewTargetRefresh() {`  
L551: `func focusSizedFrame(pos: CGPoint, size: CGSize,`  
L590: `func configureShadedAccessibility(for overlay: NSWindow, id: CGWindowID,`  
L616: `func currentShadedOverlayID() -> CGWindowID? {`  
L634: `@objc func finishOnboarding() {`  
L638: `@objc func dismissOnboarding() {`  
L649: `private func runTool(_ path: String, _ args: [String]) -> Int32? {`  
L666: `private func readTool(_ path: String, _ args: [String]) -> String? {`  
L682: `private func runDefaults(_ args: [String]) { runTool("/usr/bin/defaults", args) }`  
L683: `private func readDefaults(_ args: [String]) -> String? { readTool("/usr/bin/defaults", args) }`  
L684: `private func killDock() { runTool("/usr/bin/killall", ["Dock"]) }   // 让 Dock 重读 mineffect`  
L686: `private func writeDockMinimizeEffect(_ value: String, reason: String) -> Bool {`  
L699: `private func persistDockMinimizeEffectSession(original: String?) {`  
L710: `private func clearDockMinimizeEffectSession() {`  
L717: `private func restoreDockMinimizeEffect(original: String?) {`  
L725: `private func recoverStaleDockMinimizeEffectSessionIfNeeded() {`  
L736: `private func enableScaleMinimizeEffectForSession() {`  
L764: `private func restoreDockMinimizeEffect() {`  
L781: `func currentOperationState(_ id: CGWindowID) -> WindowShadeState {`  
L787: `func transitionOperationState(id: CGWindowID, to next: WindowShadeState,`  
L800: `func applicationWillTerminate(_ note: Notification) {`  
L827: `func ensureAccessibility() -> Bool {`  
L834: `@objc func toggleAction() { toggle() }`  
L845: `@objc func focusCurrentAppAction() {`  
L859: `@objc func unshadeFromMenu(_ sender: NSMenuItem) {`  
L864: `@objc func quit() {`  
L877: `func setupEventTapWhenTrusted() {`  
L893: `func setupEventTap() -> Bool {`  

## prototype/build.sh

modify · 358 行 · SHA256 `e6db6c9f3499fcdcb4f28c065199f4f87aa64aeb0c5a46b098164dc761ad588c`
