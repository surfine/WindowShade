// 可截屏内容列表预热的门控真值表与预过滤计数（纯逻辑，无系统依赖）。

import Foundation

enum TitlebarPrefetchGate {
    /// 没有画像时的标题栏带高。
    static let defaultBandHeight: CGFloat = 52

    /// 预热只服务收起动画（要截图）与退回 ScreenCaptureKit 的对照模式；只在第一下点击时做。
    static func shouldPrefetch(clickState: Int, animationEnabled: Bool, fastCaptureDisabled: Bool) -> Bool {
        clickState == 1 && (animationEnabled || fastCaptureDisabled)
    }

    /// 该窗口的标题栏带高：有画像用画像，没有用 52pt。
    static func bandHeight(profileHeight: CGFloat?) -> CGFloat {
        if let h = profileHeight, h > 0 { return h }
        return defaultBandHeight
    }
}

/// tap 线程上预过滤结果计数。hit=确定不在标题栏带（放行）、miss=可能在（交主线程）、nil=资格不清。
final class PrefilterStats: @unchecked Sendable {
    enum Outcome { case hit, miss, unknown }
    struct Counts: Equatable { var hit = 0, miss = 0, unknown = 0 }

    static let shared = PrefilterStats()
    private let lock = NSLock()
    private var counts = Counts()

    func note(_ outcome: Outcome) -> Counts {
        lock.lock(); defer { lock.unlock() }
        switch outcome {
        case .hit: counts.hit += 1
        case .miss: counts.miss += 1
        case .unknown: counts.unknown += 1
        }
        return counts
    }
}
