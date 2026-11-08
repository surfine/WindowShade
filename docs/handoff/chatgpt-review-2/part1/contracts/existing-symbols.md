# 既有符号定位

以下是上传快照的原始声明行；只用于准确对照，完整实现以输入仓库为准。

## prototype/Core/NotchActivities.swift

SHA256: `38392fccf4d517c420f768938ff923c821a8c2a5d0e4a7f3a454182dc99644f7`

```swift
// L86
struct NotchActivityStore {
// L135
mutating func upsert(_ activity: NotchActivity, now: Double) -> Bool {
// L168
mutating func end(id: String, generation: UInt64, now: Double) -> Bool {
// L180
mutating func prune(now: Double) {
// L194
mutating func select(id: String) -> Bool {
// L201
mutating func moveSelection(by delta: Int) {
```

## prototype/App/NotchActivityController.swift

SHA256: `ff97464d04d2dd340b4e67374bbfc70612b96e1d00be310b8b343b2108770e4e`

```swift
// L51
func configure() {
// L62
private func suspend(_ reason: String) { suspensions.insert(reason); stop() }
// L63
private func resume(_ reason: String) { suspensions.remove(reason); configure() }
// L64
private func stop() {
// L74
func select(_ id: String) { if store.select(id: id) { publish() } }
// L103
private func publish() {
// L117
func perform(_ action: NotchActivityAction) {
```

## prototype/App/Notch.swift

SHA256: `f63095255d7996020cad759674a62368bb549354e0038fb5f0bcb4b9ca1195a9`

```swift
// L29
final class NotchController {
// L145
private static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
// L149
private func panel(for screen: NSScreen) -> NotchPanel? {
// L153
private func panel(containing point: CGPoint) -> NotchPanel? {
// L749
func tuckAll(on screen: NSScreen? = nil) -> Int {
// L1314
final class NotchPanel: NSPanel {
// L1428
func setAuthentication(_ view: NotchAuthenticationView?, animated: Bool = true) {
// L1440
func setActivities(_ items: [NotchActivity], selected: String?) {
// L2176
func setAuthentication(_ view: (NSView & NotchInteractiveContent)?) {
```

## prototype/App/AuthorizationService.swift

SHA256: `b2787dc3bb4369d687fbcde86e444cedc752f30d0629a2c5468ae646328a2ba8`

```swift
// L7
@MainActor final class AuthorizationService {
// L28
func consume(_ grant: AuthorizationGrant, purpose: AuthPurpose, currentTarget: AuthTarget) -> AuthFailure? {
```

## prototype/Core/AuthorizationLedger.swift

SHA256: `495d1ce534fe560c8c0fe43ee6fd2bb5e9e24b7f82b172978ffdd62143985676`

```swift
// L53
@MainActor final class AuthorizationLedger {
// L83
func begin(target: AuthTarget, ttl: UInt64) -> Result<AuthRequest, AuthFailure> {
// L99
func complete(_ request: AuthRequest, signature: Data, publicKey: P256.Signing.PublicKey,
lock: SessionLockState) -> Result<AuthorizationGrant, AuthFailure>
// L124
func consume(_ grant: AuthorizationGrant, expectedPurpose: AuthPurpose, currentTarget: AuthTarget,
lock: SessionLockState) -> AuthFailure?
// L151
func advanceSessionEpoch() {
```

## prototype/Core/ConductorGesture.swift

SHA256: `98802f88fa95985e05a46e75582016e60692725c75c84af0e74cb2248b867393`

```swift
// L47
static func recognize(_ stroke: [ConductorPoint]) -> Result<ConductorGesture, ConductorRejection> {
// L73
static func beatPreview(_ stroke: [ConductorPoint]) -> Int {
```
