// WindowShade 2.1 · 意图新鲜度与绑定。折入静音会话，不取代 AuthorizationLedger。
// 检查通过只表示确认输入够新、绑定没漂；不是生物识别，也不是授权签发。
import Foundation

enum WS2SilentIntentOrigin: Equatable, Sendable {
    case nativeClick
    case liveCameraGesture
    case diagnosticFixture
}

enum WS2SilentIntent {
    static let maxLifetime = WS2.Duration.second * 8
    static let maxDeliveryAge = WS2.Duration.millisecond * 250

    /// `nil` 表示意图检查通过；随后仍走命令策略与既有授权账。
    static func admit(
        origin: WS2SilentIntentOrigin,
        expectedBoot: UUID,
        observedBoot: UUID,
        expectedEpoch: UInt64,
        observedEpoch: UInt64,
        expectedProposal: UInt64,
        observedProposal: UInt64,
        expectedLease: UUID,
        observedLease: UUID,
        expectedTarget: String,
        observedTarget: String,
        expectedRevision: UInt64,
        observedRevision: UInt64,
        presented: WS2.Instant,
        expires: WS2.Instant,
        gestureStarted: WS2.Instant,
        gestureEnded: WS2.Instant,
        received: WS2.Instant
    ) -> WS2SilentSession.Reason? {
        if origin == .diagnosticFixture { return .diagnosticInput }
        // 相机挑战点头不能批准普通命令；本轮只认原生点击确认。
        if origin != .nativeClick { return .nodCannotAuthorize }
        guard !expectedTarget.isEmpty, !observedTarget.isEmpty else { return .missingTarget }
        guard expectedBoot == observedBoot,
              expectedEpoch == observedEpoch,
              expectedProposal == observedProposal,
              expectedLease == observedLease,
              expectedTarget == observedTarget,
              expectedRevision == observedRevision else {
            return .bindingChanged
        }
        guard expires > presented,
              expires.elapsed(since: presented) <= maxLifetime else {
            return .invalidLifetime
        }
        guard gestureStarted >= presented else { return .confirmationTooEarly }
        guard gestureStarted <= gestureEnded, gestureEnded <= received else {
            return .confirmationInFuture
        }
        guard received < expires else { return .expired }
        guard received.elapsed(since: gestureEnded) <= maxDeliveryAge else {
            return .staleInput
        }
        return nil
    }
}
