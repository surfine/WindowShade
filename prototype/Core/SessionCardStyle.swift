// 刘海里编程会话的卡面：审批卡的尺寸、行的摆法、从琥珀点长出来的缩放，以及各时刻用哪个弹簧令牌。
// 纯逻辑（只用 Foundation 和 CoreGraphics），界面在 App/WS2SessionCardChrome.swift。
// 依据：设计稿《刘海里的编程会话》§3 审批卡与 §4.6.1；尺寸照 10-30 岛的范式（展开宽至多 408、高至多 160）。

import Foundation
import CoreGraphics

enum SessionCardStyle {
    /// 展开的岛至多这么宽、这么高（含刘海那一截）：都取自 `IslandMetrics`。
    static let islandMaxWidth: CGFloat = IslandMetrics.expandedWidth
    static let islandMaxHeight: CGFloat = IslandMetrics.expandedMaximumHeight
    /// 紧凑耳朵的高：刘海那一截的参照，卡的内容高度 = 岛的上限 - 它，取整。
    static let notchReferenceHeight: CGFloat = IslandMetrics.compactHeight
    static let cardSize = CGSize(width: islandMaxWidth, height: (islandMaxHeight - notchReferenceHeight).rounded(.down))

    static let inset: CGFloat = 16
    static let earSide: CGFloat = 18
    static let rowGap: CGFloat = 3
    static let buttonHeight: CGFloat = 28
    static let buttonBottom: CGFloat = 12
    static let buttonGap: CGFloat = 8
    static let dotDiameter: CGFloat = IslandMetrics.sessionDotDiameter
    /// 卡出现后这么久内开始的按下不算（防正在点别处的手）；数值在 MotionHold，Claude hook 卡和 Codex 卡共用。
    static let freshPressSeconds: Double = MotionHold.freshPressSeconds

    /// 卡面上从上到下的行（原点在左下，AppKit 坐标）。
    struct Layout: Equatable {
        var ear: CGRect
        var dot: CGRect
        var waiting: CGRect
        var headline: CGRect
        var byline: CGRect
        var risk: CGRect?
        var details: CGRect?
        var buttonsTop: CGFloat
    }

    /// `showsRisk`：高风险和说不清的才有风险一行；`showsDetails`：Codex 的“去看看”把详情放在副句和风险那两行的位置。
    static func layout(in size: CGSize = cardSize, showsRisk: Bool, showsDetails: Bool) -> Layout {
        let w = size.width, h = size.height
        let top: CGFloat = 14
        let headlineH: CGFloat = 18, lineH: CGFloat = 15
        let ear = CGRect(x: inset, y: h - top - earSide, width: earSide, height: earSide)
        let waitingW: CGFloat = 52
        let waiting = CGRect(x: w - inset - waitingW, y: h - top - lineH - 1, width: waitingW, height: lineH)
        let dot = CGRect(x: waiting.minX - dotDiameter - 5, y: waiting.midY - dotDiameter / 2,
                         width: dotDiameter, height: dotDiameter)
        let textX = inset + earSide + 8
        let headline = CGRect(x: textX, y: h - top - headlineH, width: max(0, dot.minX - 8 - textX), height: headlineH)
        let byline = CGRect(x: textX, y: headline.minY - rowGap - lineH, width: max(0, w - inset - textX), height: lineH)
        let risk = showsRisk ? CGRect(x: textX, y: byline.minY - rowGap - lineH, width: max(0, w - inset - textX), height: lineH) : nil
        let buttonsTop = buttonBottom + buttonHeight
        let detailsTop = headline.minY - 6
        let details = showsDetails
            ? CGRect(x: inset, y: buttonsTop + 6, width: max(0, w - 2 * inset), height: max(0, detailsTop - buttonsTop - 6))
            : nil
        return Layout(ear: ear, dot: dot, waiting: waiting, headline: headline, byline: byline,
                      risk: risk, details: details, buttonsTop: buttonsTop)
    }

    // MARK: 从琥珀点长出来

    /// 把内容以 `anchor` 为不动点缩放：anchor 在变换前后不动。
    static func scale(_ factor: CGFloat, about anchor: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: anchor.x, y: anchor.y).scaledBy(x: factor, y: factor)
            .translatedBy(x: -anchor.x, y: -anchor.y)
    }

    /// 内容层（锚点在中心 `center`）要套的变换，使整层以 `anchor` 为不动点缩放 `factor`：
    /// 层上任一点 x 落在 `center + t(x - center)`，取 t = 缩放 factor 再平移 (1 - factor)(anchor - center)。
    static func layerTransform(scale factor: CGFloat, about anchor: CGPoint, center: CGPoint) -> CGAffineTransform {
        CGAffineTransform(a: factor, b: 0, c: 0, d: factor,
                          tx: (1 - factor) * (anchor.x - center.x), ty: (1 - factor) * (anchor.y - center.y))
    }

    /// 卡内容的缩放原点：默认就是右耳那颗琥珀点的中心（调用方可以传真实位置）。
    static func bloomOrigin(layout: Layout, override: CGPoint? = nil) -> CGPoint {
        override ?? CGPoint(x: layout.dot.midX, y: layout.dot.midY)
    }

    enum Moment: Equatable, Sendable {
        /// 等你：从琥珀点长成卡。
        case enter
        /// 放行或超时：缩回那个点。
        case retreat
        /// 被更高层挂起后回来：只淡回，不重播放大。
        case resume
    }

    /// 弹簧令牌的名字（稿 §4.6.1）。只写令牌名，数值在 `MotionSpring`。
    enum Token: String, Equatable, Sendable { case calm, settle, bloom, reducedNotch }

    struct Plan: Equatable, Sendable {
        var token: Token
        /// 起点（enter）或终点（retreat）的缩放；1 = 不缩放，只淡。
        var scale: CGFloat
    }

    /// 进：bloom，从点长出来；出：settle，终点是口子不回弹；回来：calm，只淡。
    /// 减少动态效果：全部 reducedNotch，原处淡入淡出，不缩放。
    static func plan(_ moment: Moment, reduced: Bool) -> Plan {
        if reduced { return Plan(token: .reducedNotch, scale: 1) }
        switch moment {
        case .enter: return Plan(token: .bloom, scale: enterScale)
        case .retreat: return Plan(token: .settle, scale: enterScale)
        case .resume: return Plan(token: .calm, scale: 1)
        }
    }
    /// 卡刚从点里出来时的大小比例。
    static let enterScale: CGFloat = 0.4
}

// MARK: 缩回琥珀点：进度、弹簧的位置与速度

extension SessionCardStyle {
    /// 卡的“收回程度” p：0 = 完整的卡，1 = 缩进点里。缩放与透明度都由它推出，打断时位置和速度一起接着走。
    static func pose(progress p: Double, plan: Plan) -> (scale: CGFloat, opacity: Float) {
        let clamped = min(1, max(0, p))
        return (1 - CGFloat(clamped) * (1 - plan.scale), Float(1 - clamped))
    }

    /// 一次弹簧（质量 1，Apple 的 response / dampingRatio 口径：ω = 2π / response）的解析解，
    /// 用来在中途改道时读出当下的位置和速度。位置单位同 `from` / `to`，速度是每秒。
    struct SpringRun: Equatable, Sendable {
        var response: Double
        var dampingRatio: Double
        var from: Double
        var to: Double
        var initialVelocity: Double = 0

        func position(at t: Double) -> Double { to + displacement(at: max(0, t)).e }
        func velocity(at t: Double) -> Double { displacement(at: max(0, t)).v }

        private func displacement(at t: Double) -> (e: Double, v: Double) {
            let w = 2 * Double.pi / max(0.001, response)
            let z = max(0.01, dampingRatio)
            let e0 = from - to, v0 = initialVelocity
            if z >= 1 {
                // 临界阻尼（过阻尼按临界算，令牌里没有）。
                let b = v0 + w * e0
                let decay = exp(-w * t)
                return ((e0 + b * t) * decay, (b - w * (e0 + b * t)) * decay)
            }
            let wd = w * (1 - z * z).squareRoot()
            let decay = exp(-z * w * t)
            let c = e0, d = (v0 + z * w * e0) / wd
            let cosT = cos(wd * t), sinT = sin(wd * t)
            let e = decay * (c * cosT + d * sinT)
            let v = decay * (v0 * cosT - ((z * w * v0 + w * w * e0) / wd) * sinT)
            return (e, v)
        }
    }

    /// 缩回途中某一刻的状态，交给接上来的新卡：从这个位置、这个速度接着走。
    struct RetreatSnapshot: Equatable, Sendable {
        var progress: Double
        /// p 每秒变多少（缩回时为正）。
        var velocity: Double
    }

    /// 编程会话审批卡“没人管”这条规则（拍板 10-29 第 36 条）：2 分钟没人动，卡缩回琥珀点，请求仍挂着。
    /// 规则本身只会说“缩回去”，不带任何“回答”或“改期限”：Claude Code（无期限）和 Codex（30 秒）各自的期限它不碰。
    struct IdleRule: Equatable, Sendable {
        static let idleSeconds: Double = 120
        /// 本规则不拥有的期限，原样记着，只为说明它不被改动。
        let requestDeadline: Double?
        private(set) var shownAt: Double
        private(set) var parked = false
        private(set) var cancelled = false

        enum Effect: Equatable, Sendable { case none, retreatToDot }

        init(shownAt: Double, requestDeadline: Double? = nil) {
            self.shownAt = shownAt; self.requestDeadline = requestDeadline
        }

        func isDue(now: Double) -> Bool { !parked && !cancelled && now - shownAt >= Self.idleSeconds }

        mutating func fire(now: Double) -> Effect {
            guard isDue(now: now) else { return .none }
            parked = true
            return .retreatToDot
        }

        /// 点点或耳朵把卡请回来：重新计 2 分钟。已放行、已回答（cancel）的不再回来。
        mutating func restore(now: Double) -> Bool {
            guard parked, !cancelled else { return false }
            parked = false; shownAt = now
            return true
        }

        /// 有人回答了、交给 Touch ID、请求没了：不再触发。
        mutating func cancel() { cancelled = true }
    }
}

extension AgentApprovalCard {
    /// 风险一行：高风险和说不清的才写，用符号加一句原因，不只靠颜色；普通的什么都不写。
    struct RiskNote: Equatable, Sendable { var symbol: String; var text: String }

    static func riskNote(_ risk: WS2.Risk) -> RiskNote? {
        switch risk {
        case .normal: return nil
        case .high:
            return RiskNote(symbol: "exclamationmark.triangle.fill", text: WSL10n.text("agent.risk.high", zh: "风险较高"))
        case .unknown:
            return RiskNote(symbol: "exclamationmark.triangle.fill", text: WSL10n.text("agent.risk.unknown", zh: "可能改动文件或联网"))
        }
    }
}
