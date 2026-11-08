# 实际源码定位

哈希匹配时行号才有效。当前参考是本包candidate，不是公开HEAD。

## `prototype/App/FocusTimerHost.swift`

SHA256 `7aa01c91cb3abf4503ff8eb92a8060efcdfca907b295caa3ab0fde88d264b666`

- L2: `@MainActor final class FocusTimerHost {`
- L16: `func handle(_ event: FocusTimer.Event) {`
- L21: `func configure(preset: FocusTimer.Preset, tuckChatEnabled: Bool) {`
- L26: `func stop() { wake?.cancel(); wake = nil; if revision < .max { revision += 1 } }`
- L27: `private func schedule() {`

## `prototype/App/FoldExit.swift`

SHA256 `e69cdab84f86400d15e9bbf85f3a1a2a5eb71c9586332576c13c301581d7af30`

- L7: `func unshadeReturningElement(_ id: CGWindowID, playSound: Bool = true,`
- L91: `func unshade(_ id: CGWindowID) -> Bool {`
- L103: `func forceCleanup(_ id: CGWindowID, preserveFocusEntry: Bool = false, preserveRecovery: Bool = false) {`
- L136: `func removeProxyForAction(_ id: CGWindowID, state: ShadeState,`
- L164: `func removeProxyForForwardedAction(_ id: CGWindowID, state: ShadeState) {`
- L167: `func quickLookProcessHint(pid: pid_t) -> Bool {`
- L179: `func windowLooksLikeQuickLookTarget(_ win: AXUIElement, pid: pid_t,`
- L199: `func quickLookWindowCandidates(preferredPID: pid_t, title: String) -> [(pid: pid_t, win: AXUIElement)] {`
- L249: `func reopenQuickLookForProxyFullScreen(state: ShadeState, id: CGWindowID) -> Bool {`
- L261: `func clickQuickLookVisualFullScreenButton(_ win: AXUIElement, pid: pid_t,`
- L283: `func triggerQuickLookFullScreen(_ win: AXUIElement, pid: pid_t,`
- L311: `func verifyQuickLookFullScreenOrSendShortcut(_ win: AXUIElement, pid: pid_t,`
- L343: `func openQuickLookFullScreenFromProxy(state: ShadeState, id: CGWindowID) {`
- L346: `func attempt(_ index: Int) {`
- L372: `func handleQuickLookTrafficLight(_ action: TrafficAction, id: CGWindowID, state: ShadeState) {`
- L386: `func handleTrafficLight(_ action: TrafficAction, _ id: CGWindowID) {`
- L413: `func handleClassicAction(_ action: ClassicAction, _ id: CGWindowID) {`

## `prototype/App/FoldTransaction.swift`

SHA256 `482e8b46ad1aec8d169653d75d0c3976379104191c2e53bbe3ecab05bb98e06c`

- L7: `func parkFocusForInactiveCapture() {`
- L22: `func releaseFocusParking(reactivate pid: pid_t?) {`
- L41: `func handOffFocusBeforeHiding(win: AXUIElement, pid: pid_t, id: CGWindowID) -> Bool {`
- L104: `func hideTookEffect(_ hide: HideMethod, win: AXUIElement, pid: pid_t,`
- L125: `func scheduleFoldVerification(id: CGWindowID) {`
- L174: `func revealOverlayAfterVerification(id: CGWindowID, state: ShadeState) {`
- L190: `func rollbackFoldTransaction(id: CGWindowID, expectedTransaction: UUID? = nil) {`
- L215: `func activateApp(pid: pid_t) {`
- L221: `func bringRestoredWindowToFront(_ win: AXUIElement, pid: pid_t, reason: String) {`
- L224: `func attempt(_ label: String) {`
- L248: `func prepareForwardedTrafficAction(_ win: AXUIElement, pid: pid_t, reason: String) {`
- L255: `func restoredWindowIsGeometryReady(_ win: AXUIElement) -> Bool {`
- L260: `func buttonIsReady(_ win: AXUIElement, _ attr: String) -> Bool {`
- L276: `func forwardedTrafficActionSucceeded(state: ShadeState, id: CGWindowID,`
- L299: `func performForwardedTrafficAction(state: ShadeState, pos: CGPoint,`
- L313: `func retryOrFallback(_ index: Int, note: String) {`
- L337: `func verifyAfterAXPress(_ win: AXUIElement, index: Int, attr: String) {`
- L349: `func verifyAfterPointerClick(_ win: AXUIElement, index: Int, attr: String) {`
- L366: `func attempt(_ index: Int) {`
- L397: `func schedule(_ index: Int, note: String) {`
- L412: `func showRealWindowManagementPopover(_ id: CGWindowID) {`
- L425: `func attempt(_ index: Int) {`
- L455: `func windowIsParkedOffscreen(id: CGWindowID, win: AXUIElement, size: CGSize) -> Bool {`
- L463: `func privateSLSOffscreenHide(_ win: AXUIElement, id: CGWindowID,`
- L499: `func privateSLSAlphaHide(id: CGWindowID, pid: pid_t, reason: String) -> HideMethod? {`
- L531: `func axOffscreenHide(_ win: AXUIElement,`
- L555: `func ownWindow(id: CGWindowID?) -> NSWindow? {`
- L562: `func orderOutOwnWindowIfNeeded(id: CGWindowID?, pid: pid_t, reason: String) -> HideMethod? {`
- L573: `func hideWindow(_ win: AXUIElement, pid: pid_t, originalPosition pos: CGPoint,`
- L634: `func fallbackHide(_ win: AXUIElement, pid: pid_t, id: CGWindowID?,`
- L664: `func safeRestorePosition(for state: ShadeState, desired pos: CGPoint) -> CGPoint {`
- L683: `func refreshedWindowElement(id: CGWindowID, fallback: AXUIElement,`
- L691: `func resolvedWindowElement(for state: ShadeState) -> AXUIElement {`
- L719: `func applyRestoredGeometry(_ state: ShadeState, to pos: CGPoint,`
- L752: `func restoreWindow(_ state: ShadeState, to pos: CGPoint) -> AXUIElement {`
- L792: `func cancelRestorePin(for id: CGWindowID) {`
- L796: `func pinRestoredWindow(_ state: ShadeState, to pos: CGPoint, reason: String) {`
- L804: `func attempt(_ label: String, focus: Bool, verify: Bool = true) {`
- L847: `func resizeShadedWindowFromProxy(_ id: CGWindowID, proxyFrame: NSRect) {`
- L886: `func makeRevealObserver(pid: pid_t, win: AXUIElement, id: CGWindowID) -> AXObserver? {`
- L898: `func removeObserver(_ state: ShadeState) {`
- L904: `func handleAXNotification(_ id: CGWindowID, _ notification: String) {`
- L943: `@objc func appTerminated(_ note: Notification) {`
- L953: `@objc func frontmostApplicationChanged(_ note: Notification) {`
- L983: `@objc func screenParametersChanged(_ note: Notification) {`
- L1028: `@objc func activeSpaceChanged(_ note: Notification) {`

## `prototype/App/InteractionCoordinator.swift`

SHA256 `5524bd61193c8e7ca5090b7c38c498f094bdc13a3e48971f3f084b2fb7a0c5b2`

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
- L86: `private func barrier(_ reason: WS2.LeaseRevocation) {`
- L90: `func invalidate(_ reason: WS2.LeaseRevocation, at now: WS2.Instant) {`
- L98: `func removeDisplay(_ id: WS2.DisplayID, at now: WS2.Instant) {`
- L105: `func publishOngoing(_ ids: [String], on display: WS2.DisplayID) {`
- L110: `func remind(on display: WS2.DisplayID, at now: WS2.Instant) {`
- L119: `func snapshots(at now: WS2.Instant) -> [WS2.VisibilitySnapshot] {`
- L137: `func confirmationIsFresh(lease: WS2.LeaseHandle, beganAt: WS2.Instant, sequence: UInt64,`

## `prototype/App/Notch.swift`

SHA256 `f99ffc0698fa98d63b07a4d3c4ba196e6ddba38f1148df635295a47572c6a1c7`

- L29: `final class NotchController {`
- L30: `private struct Tucked {`
- L49: `func refreshAppearance() {`
- L73: `func authenticationPanel() -> NotchPanel? {`
- L128: `static func notchScreen() -> NSScreen? {`
- L133: `static func notchRect(on screen: NSScreen) -> NSRect? {`
- L141: `static func slotRect(on screen: NSScreen) -> (rect: NSRect, virtual: Bool) {`
- L147: `private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {`
- L151: `private func panel(for screen: NSScreen) -> NotchPanel? {`
- L155: `private func panel(containing point: CGPoint) -> NotchPanel? {`
- L163: `func isTucked(_ id: CGWindowID) -> Bool { tucked.contains { $0.id == id } }`
- L173: `func install() {`
- L249: `private func applyShapes() {`
- L257: `func prepareForLaunchpad() {`
- L263: `func setEnabled(_ enabled: Bool) {`
- L278: `func setAlertsEnabled(_ enabled: Bool) {`
- L290: `func aims(from release: CGPoint, velocity: CGVector) -> Bool {`
- L301: `func dragMoved(to point: CGPoint) {`
- L316: `func cancelDrag() {`
- L322: `func dragEnded(at point: CGPoint) -> NotchPanel.DropChoice? {`
- L331: `func screen(containing point: CGPoint) -> NSScreen? {`
- L339: `func tuck(_ win: AXUIElement, id: CGWindowID, pid: pid_t, landed: CGRect, home: CGRect, velocity: CGVector,`
- L375: `private func finishTuck(_ win: AXUIElement, id: CGWindowID, pid: pid_t, landed: CGRect, home: CGRect,`
- L432: `private func coverUntilHidden(_ plate: BackgroundPlate, id: CGWindowID, attempts: Int) {`
- L444: `private func hideStripWhenReady(_ id: CGWindowID, attempts: Int, since: Int? = nil) {`
- L472: `func releaseLatest(reason: String, from origin: NSRect? = nil) {`
- L491: `func release(_ id: CGWindowID, reason: String, from origin: NSRect? = nil) {`
- L515: `private func restore(_ item: Tucked, landing: CGRect) {`
- L525: `private func slideHome(_ item: Tucked, attempts: Int) {`
- L551: `private func hoverChanged(_ inside: Bool, panel: NotchPanel) {`
- L578: `private func open(_ id: CGWindowID, from origin: NSRect? = nil) {`
- L613: `private func saveCoach() {`
- L619: `private func pointerPanel() -> NotchPanel? {`
- L626: `func announce(_ text: String, detail: String = "", tone: NotchPanel.Tone = .info, symbol: String? = nil,`
- L653: `private struct PendingAnnouncement {`
- L665: `func announceWhenFree(key: String, text: String, detail: String = "", tone: NotchPanel.Tone = .info,`
- L687: `private func isFreeToAnnounce() -> Bool {`
- L692: `private func drainPendingAnnouncements() {`
- L711: `func teach(_ tip: CoachTip, on target: NotchPanel? = nil) -> Bool {`
- L733: `func coachUsed(_ tip: CoachTip) {`
- L740: `func resetCoachForProbe() { coach = GestureCoach() }`
- L741: `func tapAnnouncementForProbe() { panels.values.first { $0.isAlerting }?.tapForProbe() }`
- L752: `func tuckFocused() -> Bool {`
- L772: `func tuckAll(on screen: NSScreen? = nil) -> Int {`
- L800: `func switchApp(back: Bool, panel: NotchPanel? = nil) {`
- L824: `static func recentWindows() -> [(id: CGWindowID, pid: pid_t)] {`
- L840: `private func homeKey(_ clicks: Int, from rect: NSRect) {`
- L867: `func activeSpaceChanged() {`
- L883: `func pressForProbe(_ clicks: Int) {`
- L889: `func refreshShelfForProbe() { shelf.invalidate(); refreshShelf() }`
- L890: `func openTileForProbe(_ id: CGWindowID) { open(id) }`
- L893: `private func refreshShelf() {`
- L898: `private func requestThumbnails() {`
- L906: `private func rowExclude() -> Set<CGWindowID> {`
- L926: `private func showPeek(_ id: CGWindowID, tile: NSRect? = nil) {`
- L987: `private func showStoredPeek(_ id: CGWindowID) {`
- L997: `enum TileGlance {`
- L1003: `private func startTileGlance(_ id: CGWindowID, tile: NSRect, glance: TileGlance, pid: pid_t, title: String) {`
- L1010: `private func showStill(_ item: NotchShelfItem, tile: NSRect) {`
- L1048: `private func endPeek() {`
- L1065: `private func hideStripAfterGlance(_ id: CGWindowID, attempts: Int) {`
- L1082: `func peekForProbe(_ id: CGWindowID, tile: NSRect) { showPeek(id, tile: tile) }`
- L1083: `func peekForProbe(_ id: CGWindowID) { showPeek(id) }`
- L1085: `func thumbnailForProbe(_ id: CGWindowID) -> CGImage? { thumbnails.image(id) }`
- L1087: `func requestThumbnailsForProbe() { requestThumbnails() }`
- L1088: `func endPeekForProbe() { endPeek() }`
- L1090: `private func refresh() {`
- L1099: `private func room(for panel: NotchPanel, display: CGDirectDisplayID) -> MenuBarRoom.Sides? {`
- L1108: `private func compactInfo() -> NotchPanel.Compact? {`
- L1117: `private func forgetGone() {`
- L1126: `private func tiles() -> [NotchTile] {`
- L1131: `func icon(_ pid: pid_t) -> NSImage? { NSRunningApplication(processIdentifier: pid)?.icon }`
- L1164: `private func syncWatchers() {`
- L1178: `private func titleSettled(_ id: CGWindowID, title: String) {`
- L1218: `func clearChange(_ id: CGWindowID) {`
- L1227: `func simulateTitleChange(_ id: CGWindowID, title: String) {`
- L1232: `func syncWatchersForProbe() { syncWatchers() }`
- L1233: `func isWatchingTitle(_ id: CGWindowID) -> Bool { watcher.isWatching(id) }`
- L1239: `private enum FlightStyle { case intoNotch, intoVirtualNotch, out }`
- L1241: `private func fly(_ image: CGImage, from: NSRect, to: NSRect, velocity: CGVector, style: FlightStyle,`
- L1260: `func elsewhereAnchorFrame(_ id: CGWindowID) -> NSRect? {`
- L1268: `func glanceTarget(forElsewhere id: CGWindowID) -> GlanceTarget? {`
- L1314: `func openElsewhereWindow(_ id: CGWindowID) { open(id) }`
- L1317: `struct NotchTile {`
- L1318: `enum Kind { case tucked, strip, slideOver, carried, minimized, hiddenApp, elsewhere }`
- L1337: `final class NotchPanel: NSPanel {`
- L1338: `enum DropState { case none, offered, armed, confirmed }`
- L1347: `func refreshAppearance() { apply(animated: false) }`
- L1351: `enum DropChoice: Int, CaseIterable {`
- L1373: `struct IslandStyle {`
- L1383: `struct Compact {`
- L1388: `func same(as other: Compact?) -> Bool {`
- L1395: `struct Alert {`
- L1408: `enum Tone { case info, done, problem, tip }`
- L1450: `func isShowingInteraction(_ view: NSView) -> Bool { authenticationView === view }`
- L1455: `func setAuthentication(_ view: NotchAuthenticationView?, animated: Bool = true) {`
- L1458: `func setInteraction(_ view: (NSView & NotchInteractiveContent)?, animated: Bool = true) {`
- L1467: `func setActivities(_ items: [NotchActivity], selected: String?) {`
- L1494: `func tapForProbe() { pressed(1) }`
- L1512: `func choice(at point: CGPoint) -> DropChoice {`
- L1563: `private func showActivityMenu(_ event: NSEvent) {`
- L1572: `@objc private func activityMenuAction(_ item: NSMenuItem) {`
- L1580: `override func orderOut(_ sender: Any?) {`
- L1589: `private func refitShoulders() {`
- L1606: `private func pressed(_ clicks: Int) {`
- L1651: `private func updateVisibility() {`
- L1660: `func setCompact(_ value: Compact?, room newRoom: MenuBarRoom.Sides?) {`
- L1703: `static func alertWidth(notch: NSRect, teaching: Bool) -> CGFloat {`
- L1708: `static func alertCoverSpans(notch: NSRect, virtual: Bool, screen: NSRect) -> MenuBarRoom.Spans {`
- L1715: `private enum CompactShape { case sides, pill, chin, pending }`
- L1723: `func alert(_ info: Alert, duration: TimeInterval = 2.6) {`
- L1739: `func expand(with tiles: [NotchTile]) {`
- L1753: `func updateTileSnapshot(id: CGWindowID, image: CGImage?) {`
- L1759: `func collapse() {`
- L1768: `func confirmDrop() {`
- L1783: `func setDropState(_ state: DropState, choice: DropChoice? = nil) {`
- L1796: `private func hover(_ inside: Bool) {`
- L1826: `private func pull(_ distance: CGFloat, touching: Bool, velocity: CGFloat) {`
- L1850: `static func rubberBand(_ x: CGFloat, limit d: CGFloat) -> CGFloat {`
- L1854: `static func rubberBandSlope(_ x: CGFloat, limit d: CGFloat) -> CGFloat {`
- L1859: `private struct Target {`
- L1873: `private func target() -> Target {`
- L1910: `private func baseTarget() -> (rect: NSRect, style: IslandStyle) {`
- L1988: `private func spring() -> NotchCanvasView.Spring {`
- L1998: `private func apply(animated: Bool, spring custom: NotchCanvasView.Spring? = nil, roomOnly: Bool = false) {`
- L2066: `private func shoulderMotion(to target: Target, from now: NSRect) -> (scale: (leading: CGFloat, trailing: CGFloat),`
- L2070: `func side(from edge: CGFloat, to goal: CGFloat, hardware: CGFloat, scale: CGFloat, was: CGFloat) -> (CGFloat, Bool) {`
- L2082: `func swallow() {`
- L2107: `private func compactSlots(in size: NSSize, shape: CompactShape, side: CGFloat) -> (leading: NSRect, trailing: NSRect) {`
- L2116: `private func hintText() -> String? {`
- L2136: `final class NotchCanvasView: NSView {`
- L2137: `struct Content {`
- L2161: `func same(as other: Content) -> Bool {`
- L2175: `struct Spring {`
- L2208: `func setAuthentication(_ view: (NSView & NotchInteractiveContent)?) {`
- L2214: `func placeAuthentication(in rect: NSRect) {`
- L2224: `func updateTileSnapshot(id: CGWindowID, image: CGImage?) {`
- L2261: `func setBare(_ bare: Bool) {`
- L2270: `func islandOnScreen(panelOrigin: NSPoint) -> NSRect? {`
- L2277: `func shift(by delta: CGVector) {`
- L2290: `func morph(to rect: NSRect, style: NotchPanel.IslandStyle, content: Content, spring: Spring?,`
- L2340: `private func add(_ spring: Spring, key: String, to layer: CALayer, position: CGVector, size: CGSize, radius: CGFloat) {`
- L2341: `func animate(_ keyPath: String, from: Any, zero: Any) {`
- L2361: `private func present(_ content: Content, in rect: NSRect, animated: Bool) {`
- L2399: `func settle() {`
- L2405: `func pullIconOnScreen() -> NSRect? {`
- L2411: `func pulse(width: CGFloat, height: CGFloat) {`
- L2413: `func bump(_ layer: CALayer) {`
- L2438: `override func updateTrackingAreas() {`
- L2445: `override func mouseEntered(with event: NSEvent) { onHover?(true) }`
- L2446: `override func mouseExited(with event: NSEvent) { holdTimer?.invalidate(); holdTimer = nil; if mouseDragAxis == nil { pressedAt = nil }; onHover?(false) }`
- L2447: `override func mouseMoved(with event: NSEvent) { onPointerMoved?() }`
- L2448: `override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }`
- L2455: `private func mouseScreenPoint(_ event: NSEvent) -> NSPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow }`
- L2456: `override func mouseDown(with event: NSEvent) {`
- L2472: `override func mouseUp(with event: NSEvent) {`
- L2502: `override func mouseDragged(with event: NSEvent) {`
- L2513: `func cancelHold() { holdTimer?.invalidate(); holdTimer = nil; pressedAt = nil; mouseDragAxis = nil }`
- L2514: `func resetInteractions() {`
- L2519: `override func cancelOperation(_ sender: Any?) {`
- L2525: `override func rightMouseDown(with event: NSEvent) { if authenticationView == nil { onAuxiliaryClick?(event) } }`
- L2526: `override func smartMagnify(with event: NSEvent) { if authenticationView == nil { onSmartExpand?() } }`
- L2527: `override func swipe(with event: NSEvent) {`
- L2541: `override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {`
- L2555: `override func draggingExited(_ sender: NSDraggingInfo?) {`
- L2559: `override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {`
- L2574: `override func scrollWheel(with event: NSEvent) {`
- L2627: `private func currentActivitySwipe(_ distance: CGFloat, touching: Bool, velocity: CGFloat, cancelled: Bool = false) -> Bool {`
- L2631: `override func magnify(with event: NSEvent) {`
- L2656: `final class NotchShoulders: NSPanel {`
- L2658: `struct Probe {`
- L2704: `func fit(screen: NSRect, top: CGFloat, radius: CGFloat) {`
- L2720: `func m(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * sign, y: p.y) }`
- L2741: `func place(leading a: NSPoint, trailing b: NSPoint, scale: (leading: CGFloat, trailing: CGFloat),`
- L2755: `func settle(_ scale: (leading: CGFloat, trailing: CGFloat)) {`
- L2765: `private func move(_ layer: CAShapeLayer, to point: NSPoint, from old: CGFloat, to new: CGFloat, snap: Bool,`
- L2813: `private func animate(_ layer: CALayer, _ keyPath: String, from: Any, zero: Any, spring: NotchCanvasView.Spring, key: String) {`
- L2825: `func setBare(_ bare: Bool) {`
- L2834: `func pulse(width: CGFloat, keyTimes: [NSNumber], duration: CFTimeInterval, timing: [CAMediaTimingFunction]) {`
- L2847: `func attached(leading a: NSPoint, trailing b: NSPoint) -> Bool {`
- L2849: `func at(_ layer: CALayer, _ p: NSPoint) -> Bool {`
- L2867: `final class NotchContentView: NSView {`
- L2932: `func updateSnapshot(id: CGWindowID, image: CGImage?) {`
- L2936: `override func hitTest(_ point: NSPoint) -> NSView? { inert ? nil : super.hitTest(point) }`
- L2939: `func place(in rect: NSRect, content: NotchCanvasView.Content) {`
- L3016: `final class NotchDotsView: NSView {`
- L3021: `func update(count: Int, changed: Bool, y: CGFloat) {`
- L3029: `override func hitTest(_ point: NSPoint) -> NSView? { nil }`
- L3031: `override func draw(_ dirtyRect: NSRect) {`
- L3045: `final class NotchCompactView: NSView {`
- L3049: `func update(_ compact: NotchPanel.Compact?, slots: (leading: NSRect, trailing: NSRect)?) {`
- L3060: `override func hitTest(_ point: NSPoint) -> NSView? { nil }`
- L3062: `override func draw(_ dirtyRect: NSRect) {`
- L3091: `final class NotchAlertView: NSView {`
- L3096: `func update(_ alert: NotchPanel.Alert?) {`
- L3111: `override func hitTest(_ point: NSPoint) -> NSView? { nil }`
- L3113: `override func layout() {`
- L3119: `override func draw(_ dirtyRect: NSRect) {`
- L3165: `final class NotchTileView: NSView {`
- L3175: `func setSnapshot(_ image: CGImage?) {`
- L3202: `static func verb(_ kind: NotchTile.Kind) -> String {`
- L3213: `static func kindName(_ kind: NotchTile.Kind) -> String {`
- L3225: `private static func badge(_ kind: NotchTile.Kind) -> NSImage? {`
- L3240: `override func updateTrackingAreas() {`
- L3248: `override func mouseEntered(with event: NSEvent) {`
- L3255: `override func mouseExited(with event: NSEvent) {`
- L3260: `override func mouseDown(with event: NSEvent) {`
- L3264: `override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }`
- L3277: `override func draw(_ dirtyRect: NSRect) {`
- L3331: `final class NotchPeek {`
- L3367: `func close() {`

## `prototype/App/ShadeController.swift`

SHA256 `f22cc7af4a270af54422820beea2807235198ba823b8bb42adf098b52f85a198`

- L8: `func retargetToActiveSpaceWindow(pid: pid_t) -> (AXUIElement, CGWindowID)? {`
- L35: `func toggle() {`
- L87: `func performNativeStickiesShade(_ win: AXUIElement) {`
- L104: `func makeShadePlan(win: AXUIElement, pos: CGPoint, size: CGSize,`
- L157: `func resolvedSourceSpaceID(windowID id: CGWindowID,`
- L169: `func shade(_ win: AXUIElement, _ id: CGWindowID,`
- L175: `func completeFold(success: Bool) {`
- L286: `func installOverlay(_ overlay: NSWindow, mode: ShadeAppearanceMode, previewImage: NSImage?) {`
- L463: `func installInteractiveNativeCollapse(barH: CGFloat) -> Bool {`
- L737: `func captureWindow(id: CGWindowID, axPos: CGPoint, size: CGSize,`
- L776: `func fastWindowCapture(_ id: CGWindowID) async -> CGImage? {`
- L783: `func captureWindowWithTimeout(id: CGWindowID, axPos: CGPoint, size: CGSize,`
- L834: `private func raceCaptureWithTimeout(id: CGWindowID, axPos: CGPoint, size: CGSize,`

## `prototype/App/WS2AppRuntime.swift`

SHA256 `99205e90fd9d99278da55fbfe88924e2100c4ada4223c6d35136da67cf5b6db2`

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
- L217: `@discardableResult func showSessions(_ sessions:[AgentSessions.Session], open:@escaping(WS2.Context)->Void,`
- L222: `@discardableResult func showConductor(_ state:ConductorNotch, action:@escaping(WS2ConductorView.Action)->Void) -> Bool {`
- L228: `private func publish() {`
- L236: `func stop() {`
- L249: `@objc func ws2OpenOwned() { MainActor.assumeIsolated { ws2Runtime.openOwned() } }`
- L250: `@objc func ws2OpenFocus() { MainActor.assumeIsolated { ws2Runtime.open() } }`

## `prototype/App/WS2DeviceActionHost.swift`

SHA256 `e969db6f1d29d4dc2af25afb99a58e90281b395480a704193de53e3b5cf2e5a7`

- L4: `@MainActor final class WS2DeviceActionHost {`
- L35: `func start() { bridge.start() }`
- L37: `private func clear(_ id: UUID) {`
- L41: `@discardableResult func enable(_ id: UUID) -> Bool {`
- L51: `func disable(_ id: UUID) { clear(id); _ = bridge.setEnabled(false, attachment: id) }`
- L52: `func environmentChanged() {`
- L56: `private func receive(_ input: WS2ControllerInput) {`
- L96: `private static func intent(_ name: String) -> WS2SemanticInputRouter.Intent? {`
- L105: `func stop() { for id in Array(contexts.keys) { clear(id) }; bridge.stop() }`

## `prototype/App/WS2FoldEvidenceAdapter.swift`

SHA256 `cb7f57c8020aeda4aca842a4a48a58b5e4a70acacc02cff63a2682d426a0c264`

- L7: `func shadeWithEvidence(_ win:AXUIElement,id:CGWindowID,pid:pid_t,recordedPosition:CGPoint?,`
- L27: `func deliverFoldEvidence(_ event:WS2FoldEvidence.Event?){`
- L33: `func mayCommitObservedFold(_ ticket:WS2FoldEvidence.Ticket)->Bool {`
- L37: `func finishFoldEvidence(_ ticket:WS2FoldEvidence.Ticket?,success:Bool){`
- L44: `func publishFoldObservation(id:CGWindowID,state:ShadeState){`
- L61: `func strictFoldObservation(id:CGWindowID,state:ShadeState)->WS2FoldEvidence.Observation{`
- L84: `func cancelFoldEvidence(id:CGWindowID,transaction:UUID){`

## `prototype/App/WS2GameControllerBridge.swift`

SHA256 `cf257e4e8233d7030b96e5b317d02043024d25f2d03dc27824dd9976394881ee`

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
- L157: `@discardableResult func feedback(attachment:UUID,start:Float,strength:Float) -> Bool {`
- L167: `private func clearFeedback(_ e:Entry) {`
- L171: `private func suspend(_ e:Entry) {`
- L177: `private func publish() {`
- L180: `func stop() {`

## `prototype/App/WS2IslandCoordinator.swift`

SHA256 `315bf8f9b76ead7600c8829b69c4609bf89d919f3421631b3154aedd13acd91f`

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
- L71: `private func revoked(_ lease: WS2.LeaseHandle, reason: WS2.LeaseRevocation) {`
- L84: `private func beginAuthorization(on panel: NotchPanel) -> Bool {`
- L92: `private func endAuthorization() { if let authHandle { leases.release(authHandle,at:clock.now()) }; authHandle = nil }`
- L93: `func invalidate(_ reason: WS2.LeaseRevocation) { leases.invalidate(reason,at:clock.now()) }`
- L94: `private func reconcileDisplays() { _ = leases.snapshots(at:clock.now()) }`
- L95: `func stop() {`

## `prototype/App/WS2ModelPickerView.swift`

SHA256 `1da4c59ec557195a5b03760eb038b2d8fe1ecabb2f733f2c29ab554d8790f73c`

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
- L159: `@objc private func useSelection() {`
- L164: `@objc private func goBack() { if inputIsCurrent() { navigateBack?() } }`
- L165: `func revoke() {`
- L175: `func prepare(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool { input.ready = isInputReady; return input.prepare(ticket) }`
- L176: `func cancelPrepared(context: WS2SemanticInputRouter.Context, presses: [UInt64]) { input.cancel(context: context, presses: presses) }`
- L177: `func execute(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool { input.ready = isInputReady; return input.execute(ticket) }`
- L178: `func move(_ effect: GamepadMapping.Effect, context: WS2SemanticInputRouter.Context) -> Bool { false }`

## `prototype/App/WS2OwnedCodexSession.swift`

SHA256 `b05f1a6d7aeafd72f5e8d5dea6cd8a460737d57cbf319b1c242b01a5f09d2ef8`

- L3: `/// One engine for the real App and the process-backed protocol tests. It owns exactly one`
- L4: `/// child channel and one protocol host. The host factory cannot create a second transport.`
- L5: `@MainActor final class WS2OwnedCodexSession {`
- L57: `func start() throws {`
- L62: `func startThread(cwd:String,model:String) throws { try approval.startThread(cwd:cwd,model:model);scheduleExpiry() }`
- L63: `func resumeThread(_ id:String) throws { try approval.resumeThread(id);scheduleExpiry() }`
- L64: `func startTurn(text:String,model:String,effort:String) throws { try approval.startTurn(text:text,model:model,effort:effort);scheduleExpiry() }`
- L65: `func steer(text:String,expectedTurn:String) throws { try approval.steer(text:text,expectedTurn:expectedTurn);scheduleExpiry() }`
- L66: `func interrupt() throws { try approval.interruptTurn();scheduleExpiry() }`
- L67: `func account(_ action:WS2AccountAction) throws -> WS2.RequestID {`
- L70: `func clearDiagnostics() { channel.clearDiagnostics() }`
- L71: `private func scheduleExpiry() {`
- L80: `func stop() {`

## `prototype/App/WS2OwnedLaunchController.swift`

SHA256 `302f4b8ad841610a8a471caf79af657a5c8bc5d10e9c0e0a8d954363160a4ed2`

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
- L94: `private func begin(_ prepared:WS2LocalLaunchProfile,diagnostics:Bool) {`
- L120: `private func currentIsValid() -> Bool {`
- L125: `private func revalidate() -> Bool {`
- L129: `@discardableResult func chooseModel(_ value:String) -> Bool {`
- L133: `@discardableResult func chooseEffort(_ value:String) -> Bool {`
- L137: `@discardableResult func send(_ draft:String,hasMarkedText:Bool) -> Bool {`
- L149: `private func deliverSubmission() throws {`
- L155: `@discardableResult func resumeLast() -> Bool {`
- L161: `@discardableResult func interrupt() -> Bool {`
- L166: `@discardableResult func login() -> Bool {`
- L171: `@discardableResult func logout() -> Bool {`
- L176: `func cancelLogin() {`
- L183: `static func browserLoginURL(_ text:String) -> URL? {`
- L189: `private func receive(_ event:CodexWire.Event,connection:UUID) {`
- L256: `private func readAccount() throws {`
- L260: `private func synchronizeThreadAndTurn() throws {`
- L275: `private func emit(_ event:AgentSessions.Event,turn:String?=nil) {`
- L279: `private func ended(connection:UUID) {`
- L285: `func stop(reason:String="已断开连接",clearPrivate:Bool=false) {`
- L303: `func environmentChanged() {`
- L307: `private func fail(_ message:String) {`
- L310: `private func changed() { onChange?();if !isBusy { onQuiescent?() } }`

## `prototype/App/WS2OwnedSessionView.swift`

SHA256 `d3360e975925f28b112b32d4c51b9a75d195a507629793e5e5b3d3eed006434f`

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
- L135: `@objc private func start() { guard inputIsCurrent() else { return };_=controller.launch(consent:consent.state == .on,diagnostics:diagnostic.state == .on);render() }`
- L136: `@objc private func logIn() { guard inputIsCurrent() else { return };_=controller.login() }`
- L137: `@objc private func cancelLogIn() { guard inputIsCurrent() else { return };controller.cancelLogin() }`
- L138: `@objc private func logOut() { guard inputIsCurrent() else { return };_=controller.logout() }`
- L139: `@objc private func resumeSession() { guard inputIsCurrent() else { return };_=controller.resumeLast() }`
- L140: `@objc private func showModelPicker() {`
- L145: `@objc private func selectModel() { guard inputIsCurrent(),model.indexOfSelectedItem>0 else { return };_=controller.chooseModel(modelIDs[model.indexOfSelectedItem-1]) }`
- L146: `@objc private func selectEffort() { guard inputIsCurrent(),effort.indexOfSelectedItem>0 else { return };_=controller.chooseEffort(effortIDs[effort.indexOfSelectedItem-1]) }`
- L147: `@objc private func sendDraft() { guard inputIsCurrent() else { return };_=controller.send(draft.string,hasMarkedText:draft.hasMarkedText()) }`
- L148: `@objc private func interruptTurn() { guard inputIsCurrent() else { return };_=controller.interrupt() }`
- L149: `@objc private func stopSession() { guard inputIsCurrent() else { return };controller.stop() }`
- L150: `@objc private func toggleDiagnostics() { guard inputIsCurrent() else { return };displayingDiagnostics.toggle();diagnostics.title=displayingDiagnostics ? "返回回复":"查看诊断";render() }`
- L151: `func revoke() { renderTask?.cancel();renderTask=nil;inputIsCurrent={false};draft.inputContext?.discardMarkedText();draft.string="";output.string="";onCancel?() }`
- L154: `@MainActor private final class WS2OwnedDocumentView:NSView { override var isFlipped:Bool { true } }`

## `prototype/Core/AgentSessions.swift`

SHA256 `218b3910959c810d5662d608b8ab9560d5232cf5e69930c330b400c940c65d7c`

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

SHA256 `ed2e3e209bb3ff42c6ba8273b323f2b6f70bdf48daa4cc21f91060d9bfebecf3`

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
- L66: `private mutating func request(_ method: String, _ params: [String:WireJSON]?, now: WS2.Instant) throws -> WS2.RequestID {`
- L74: `mutating func initialize(now: WS2.Instant) throws {`
- L79: `mutating func startThread(cwd: String, model: String, now: WS2.Instant) throws {`
- L87: `mutating func resumeThread(id: String, now: WS2.Instant) throws {`
- L95: `mutating func startTurn(text: String, model: String, effort: String, now: WS2.Instant) throws {`
- L104: `mutating func steer(text: String, expectedTurnID: String, now: WS2.Instant) throws {`
- L110: `mutating func interrupt(now: WS2.Instant) throws {`
- L115: `mutating func readConfig(cwd:String,now:WS2.Instant) throws -> WS2.RequestID {`
- L119: `mutating func readAccount(now: WS2.Instant) throws -> WS2.RequestID {`
- L123: `mutating func beginBrowserLogin(now: WS2.Instant) throws -> WS2.RequestID {`
- L127: `mutating func cancelLogin(id: String, now: WS2.Instant) throws -> WS2.RequestID {`
- L131: `mutating func logout(now: WS2.Instant) throws -> WS2.RequestID {`
- L135: `mutating func ingest(_ chunk: Data, now: WS2.Instant) throws -> [Event] {`
- L156: `private mutating func receive(_ v: WireJSON, now: WS2.Instant) throws -> [Event] {`
- L237: `mutating func denyApproval(_ id: WS2.RequestID) throws {`
- L246: `enum ApprovalWireDecision { case acceptOnce, decline }`
- L247: `mutating func enqueueApprovalResponse(_ id: WS2.RequestID, expectedMethod: String,`
- L260: `mutating func tick(now: WS2.Instant) -> [Event] {`
- L266: `mutating func close() {`

## `prototype/Core/Contracts.swift`

SHA256 `12fffc2e5cf207aa0ca6b4c371f28b9eec8c2b374b5e1a06d8943878891b2420`

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
- L66: `struct Token: Hashable, Sendable, Codable {`
- L76: `struct TokenSource: Sendable {`
- L80: `mutating func next() -> Token? {`
- L88: `enum Provider: String, Hashable, Sendable, Codable, CaseIterable {`
- L94: `struct SessionKey: Hashable, Sendable, Codable {`
- L101: `struct Context: Hashable, Sendable, Codable {`
- L114: `struct Envelope<Payload: Sendable>: Sendable {`
- L124: `struct Digest: Hashable, Sendable, Codable {`
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
- L260: `struct DisplayID: Hashable, Comparable, Sendable, Codable {`
- L266: `enum Fault: String, Equatable, Sendable {`
- L273: `protocol WS2Clock: Sendable {`
- L274: `func now() -> WS2.Instant`
- L278: `struct WS2ContinuousClock: WS2Clock, Sendable {`
- L281: `func now() -> WS2.Instant {`
- L296: `struct LeaseRequest: Sendable {`
- L304: `struct LeaseHandle: Hashable, Sendable {`
- L310: `enum LeaseRevocation: Sendable {`
- L313: `enum LeaseDecision: Sendable {`
- L319: `struct VisibilitySnapshot: Sendable {`

## `prototype/Core/GamepadMapping.swift`

SHA256 `672cf04922a50acca6eecd2727b135f07a05acae74ab285e9fb92a23ea39a855`

- L3: `struct GamepadMapping: Sendable {`
- L4: `struct Vector: Equatable, Sendable { var x: Double; var y: Double; static let zero = Vector(x: 0, y: 0) }`
- L5: `enum Effect: Equatable, Sendable { case pointer(Vector), scroll(Vector), desktop(Int), releaseTriggers }`
- L15: `mutating func configure(enabled: Bool, gameInFront: Bool) -> [Effect] {`
- L21: `static func axis(_ v: Vector) -> Vector {`
- L29: `mutating func sample(left: Vector, right: Vector, at now: Double) -> [Effect] {`
- L41: `mutating func trigger(left: Bool, value: Double, desktopEnabled: Bool) -> [Effect] {`
- L51: `mutating func disconnect() -> [Effect] { configure(enabled:false,gameInFront:false) }`

## `prototype/Core/WS2DeviceActionContracts.swift`

SHA256 `bb69fd284e1fe4921c90e68f770915e724ce6198f12156662f81b04161a809a0`

- L4: `struct WS2ControllerDevice: Equatable, Sendable {`
- L9: `enum WS2ControllerInput: Sendable {`
- L14: `struct WS2ControllerEnvironment: Sendable {`
- L21: `@MainActor protocol WS2ControllerBridge: AnyObject {`
- L24: `func start()`
- L25: `func stop()`
- L26: `func suspendAll()`
- L27: `func environmentChanged()`
- L28: `@discardableResult func setEnabled(_ enabled: Bool, attachment: UUID) -> Bool`
- L30: `@MainActor protocol WS2DeviceActionSink: AnyObject {`
- L34: `func prepare(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool`
- L35: `func cancelPrepared(context: WS2SemanticInputRouter.Context, presses: [UInt64])`
- L37: `func execute(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool`
- L38: `func move(_ effect: GamepadMapping.Effect, context: WS2SemanticInputRouter.Context) -> Bool`

## `prototype/Core/WS2DeviceInputGate.swift`

SHA256 `60c5be94786910c4719bcc4b56ff7ff217708e3981591922f33bbe9b384ae662`

- L3: `struct WS2DeviceInputGate: Sendable {`
- L4: `enum Domain: Sendable { case desktop, conductor, review }`
- L5: `enum Outcome: Equatable, Sendable { case ignored, began(UInt64), ended(UInt64), cancelled(UInt64) }`
- L14: `mutating func connect(_ id: UUID) { attachment = id; enabled = false; neutralSeen.removeAll(); down.removeAll(); sequence = nil; time = .init(); currentDomain = nil }`
- L15: `mutating func enable(_ id: UUID) -> Bool {`
- L19: `mutating func suspend() -> [UInt64] {`
- L22: `mutating func disconnect() -> [UInt64] { let ids = suspend(); attachment = nil; currentDomain = nil; return ids }`
- L24: `mutating func changeDomain(to domain: Domain) -> [UInt64] {`
- L30: `mutating func button(attachment id: UUID, name: String, pressed: Bool, sequence: UInt64,`
- L49: `struct WS2HIDButtonMap: Sendable {`
- L50: `struct Identity: Equatable, Sendable { let registryID: UInt64; let vendor: Int; let product: Int }`
- L52: `func button(from actual: Identity, page: Int, usage: Int, value: Int) -> (WS2.Button, Bool)? {`

## `prototype/Core/WS2FocusEffectPlan.swift`

SHA256 `60ccb717e3641f20e1fc499dc1e432ba37493e3c4abe8e28c73b2ebc19419829`

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

SHA256 `69a0b9a82fd67c318d92b4bcedebd6f980b094f24b37197758fe1cf85f5ab3c7`

- L3: `struct WS2FocusWindowOwnership: Sendable {`
- L4: `struct Identity: Hashable, Sendable { let pid: Int32; let processStart: UInt64; let windowID: UInt32; let windowGeneration: UInt64 }`
- L5: `struct Receipt: Equatable, Sendable {`
- L13: `mutating func record(_ receipt: Receipt, didComplete: Bool) -> Bool {`
- L18: `mutating func takeForRestore(_ id: Identity, run: WS2.Token, effectGeneration: UInt64, liveRevision: UInt64) -> Receipt? {`
- L24: `mutating func manualChange(_ id: Identity) { owned[id] = nil }`
- L25: `mutating func clear() { owned.removeAll() }`

## `prototype/Core/WS2FoldEvidence.swift`

SHA256 `3d1dd3583a1e6f93a4d721e6b4587a0cd700c993722fee2f7a03428919f420dd`

- L5: `struct WS2FoldEvidence: Sendable {`
- L6: `struct Ticket: Equatable, Sendable { let request:UUID;let window:UInt32;let pid:Int32 }`
- L7: `enum Observation:String,Sendable,Codable { case verifiedHidden, stillVisible, unknown, notStarted }`
- L8: `struct Event:Equatable,Sendable { let ticket:Ticket;let transaction:UUID?;let observation:Observation;let late:Bool }`
- L9: `private struct Entry:Sendable { let ticket:Ticket;let issuedAt:Double;let deadline:Double;var attempted=false;var transaction:UUID?;var last:Observation? }`
- L12: `func contains(_ ticket:Ticket)->Bool{entries[ticket.request]?.ticket == ticket}`
- L13: `mutating func begin(request:UUID,window:UInt32,pid:Int32,at now:Double,timeout:Double=30)->Ticket?{`
- L19: `func mayStart(_ t:Ticket,at now:Double)->Bool {`
- L23: `mutating func markMutation(_ t:Ticket,at now:Double)->Bool{`
- L26: `mutating func bind(_ t:Ticket,transaction:UUID)->Bool{`
- L30: `func ticket(window:UInt32,transaction:UUID)->Ticket?{`
- L33: `mutating func observe(_ t:Ticket,transaction:UUID,observation:Observation)->Event?{`
- L38: `mutating func failed(_ t:Ticket)->Event?{`
- L42: `mutating func expire(_ t:Ticket,at now:Double)->Event?{`
- L48: `mutating func forget(_ t:Ticket){if contains(t){entries[t.request]=nil}}`
- L49: `private mutating func emit(_ t:Ticket,observation:Observation)->Event?{`

## `prototype/Core/WS2SelectionModel.swift`

SHA256 `c8fb3c0ac6564970d2daedee4d4708799ef0014a94a7bb22b99f18a85d86cf4c`

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

## `prototype/Core/WS2SemanticInputRouter.swift`

SHA256 `7055bb6994681ac67dd6b166374ab00923a8e1d76b9133021d922925ef2ac3c6`

- L4: `struct WS2SemanticInputRouter: Sendable {`
- L5: `enum Intent: Equatable, Sendable { case previous, next, cancel, openSelection, interruptTurn }`
- L6: `struct Context: Equatable, Sendable {`
- L10: `struct Ticket: Equatable, Sendable { let context: Context; let press: UInt64; let intent: Intent }`
- L11: `enum Failure: Error { case invalid, replay, unavailable, stale, forbidden, capacity }`
- L16: `@discardableResult mutating func enable(_ context: Context) -> Bool {`
- L20: `mutating func revoke() { active = nil; seen.removeAll(); reserved.removeAll(); enabled = false }`
- L23: `mutating func reserve(press: UInt64, intent: Intent, context: Context, unlocked: Bool, sinkReady: Bool) throws -> Ticket {`
- L36: `func isCurrent(_ ticket: Ticket, live: Context, unlocked: Bool, sinkReady: Bool) -> Bool {`
- L39: `@discardableResult mutating func consume(_ ticket: Ticket, live: Context, unlocked: Bool, sinkReady: Bool) -> Bool {`

## `prototype/Core/WS2VisibleListInput.swift`

SHA256 `919b37b1add050fa65660fa70127a8dc131e659675ebedf791b86277d5acf425`

- L4: `@MainActor final class WS2VisibleListInput {`
- L14: `func replace(_ items: [WS2SelectionModel.Item], selectedID: String?) throws {`
- L20: `func bind(_ context: WS2SemanticInputRouter.Context?) {`
- L24: `@discardableResult func select(_ id: String) -> Bool {`
- L30: `@discardableResult func prepare(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool {`
- L39: `func cancel(context: WS2SemanticInputRouter.Context, presses: [UInt64]) {`
- L43: `func cancelAll() {`
- L48: `@discardableResult func execute(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool {`
- L69: `func revoke() { ready = false; context = nil; prepared = nil; selection.revoke(); onArmed?(nil) }`

## `prototype/Support/WS2DuplexProcess.swift`

SHA256 `1efe08a7d6987fdac80d87f345f1d2ce212e6a5dddac3a71e086e247d8ab579a`

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
- L145: `private func scheduleDeadline() {`
- L157: `private func writeReady() {`
- L183: `private func readReady(checkChild: Bool = true) {`
- L205: `private func readDiagnosticReady() {`
- L220: `func clearDiagnostics() { diagnostics?.clear() }`
- L221: `private static func writeWithoutSIGPIPE(_ fd: Int32, _ bytes: Data) -> Int {`
- L236: `func stop(_ reason: End = .localStop) {`
- L246: `// The reaper timer survives protocol closure. A stopped pipe is not reaping evidence.`

## `prototype/Support/WS2FocusEffectExecutor.swift`

SHA256 `674a8760579e1eccf401f6c949d6fcf69b74257943fe795b043f255b7c3887bf`

- L3: `@MainActor protocol WS2FocusMutationPort: AnyObject {`
- L6: `func perform(_ operation: WS2FocusEffectPlan.Operation,`
- L10: `@MainActor final class WS2FocusEffectExecutor {`
- L16: `func transition(run: WS2.Token?, windows: [WS2FocusEffectPlan.Window]) throws {`
- L19: `func suspend() { plan.setSuspended(true) }`
- L20: `func resumeAfterVerifiedUnlock() { plan.setSuspended(false); pump() }`
- L21: `func manualChange(_ identity: WS2FocusEffectPlan.Identity) { plan.manualChange(identity); pump() }`
- L23: `func end() throws { try transition(run: nil, windows: []) }`
- L24: `private func pump() {`

## `prototype/Support/WS2ProjectDirectory.swift`

SHA256 `7a9c30764d3199652eccc46265c4d7afae6c05cf65e1ee2a5be65c73bbd628a2`

- L4: `enum WS2ProjectDirectory {`
- L5: `enum Failure: Error { case notAbsoluteFileURL, notDirectory, missingIdentity }`
- L6: `static func read(_ url: URL) throws -> WS2OwnedScope.Directory {`
- L18: `static func contains(canonicalRoot root: String, canonicalCandidate candidate: String) -> Bool {`

## `prototype/WindowShade.swift`

SHA256 `0c489c4b721315ef147f7b3898aa388377eac8b766ada421fda395716f16828a`

- L79: `func framesAlmostEqual(_ a: NSRect, _ b: NSRect, tolerance: CGFloat = 0.5) -> Bool {`
- L86: `func cgWindowID(for window: NSWindow) -> CGWindowID? {`
- L94: `final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {`
- L96: `final class PendingTitlebarTripleClick {`
- L110: `struct PendingSpaceReturn {`
- L118: `struct ReconcileAXTarget {`
- L125: `struct ReconcileAXSnapshot {`
- L304: `func applicationDidFinishLaunching(_ note: Notification) {`
- L418: `func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {`
- L423: `@objc func systemAppearanceOptionsChanged(_ note: Notification) {`
- L454: `func installStandardMainMenu() {`
- L464: `private func migrateDistractingDefaultSounds() {`
- L493: `func refreshPinnedPreviewTarget(reason: String) {`
- L500: `private func setupPinnedPreviewFocusTracking() {`
- L513: `private func scheduleTitlebarPrefetch() {`
- L534: `private func schedulePinnedPreviewTargetRefresh() {`
- L554: `func focusSizedFrame(pos: CGPoint, size: CGSize,`
- L593: `func configureShadedAccessibility(for overlay: NSWindow, id: CGWindowID,`
- L619: `func currentShadedOverlayID() -> CGWindowID? {`
- L637: `@objc func finishOnboarding() {`
- L641: `@objc func dismissOnboarding() {`
- L652: `private func runTool(_ path: String, _ args: [String]) -> Int32? {`
- L669: `private func readTool(_ path: String, _ args: [String]) -> String? {`
- L685: `private func runDefaults(_ args: [String]) { runTool("/usr/bin/defaults", args) }`
- L686: `private func readDefaults(_ args: [String]) -> String? { readTool("/usr/bin/defaults", args) }`
- L687: `private func killDock() { runTool("/usr/bin/killall", ["Dock"]) }   // 让 Dock 重读 mineffect`
- L689: `private func writeDockMinimizeEffect(_ value: String, reason: String) -> Bool {`
- L702: `private func persistDockMinimizeEffectSession(original: String?) {`
- L713: `private func clearDockMinimizeEffectSession() {`
- L720: `private func restoreDockMinimizeEffect(original: String?) {`
- L728: `private func recoverStaleDockMinimizeEffectSessionIfNeeded() {`
- L739: `private func enableScaleMinimizeEffectForSession() {`
- L767: `private func restoreDockMinimizeEffect() {`
- L784: `func currentOperationState(_ id: CGWindowID) -> WindowShadeState {`
- L790: `func transitionOperationState(id: CGWindowID, to next: WindowShadeState,`
- L803: `func applicationWillTerminate(_ note: Notification) {`
- L830: `func ensureAccessibility() -> Bool {`
- L837: `@objc func toggleAction() { toggle() }`
- L848: `@objc func focusCurrentAppAction() {`
- L862: `@objc func unshadeFromMenu(_ sender: NSMenuItem) {`
- L867: `@objc func quit() {`
- L880: `func setupEventTapWhenTrusted() {`
- L896: `func setupEventTap() -> Bool {`
