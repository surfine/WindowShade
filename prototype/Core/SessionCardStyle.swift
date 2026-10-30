// 刘海里编程会话的卡面：审批卡的尺寸、行的摆法、从琥珀点长出来的缩放，以及各时刻用哪个弹簧令牌。
// 纯逻辑（只用 Foundation 和 CoreGraphics），界面在 App/WS2SessionCardChrome.swift。
// 依据：设计稿《刘海里的编程会话》§3 审批卡与 §4.6.1；尺寸照 10-30 岛的范式（展开宽至多 408、高至多 160）。

import Foundation
import CoreGraphics

enum SessionCardStyle {
    /// 展开的岛至多这么宽、这么高（含刘海那一截）。
    static let islandMaxWidth: CGFloat = 408
    static let islandMaxHeight: CGFloat = 160
    /// 紧凑耳朵的高（36.67）：刘海那一截的参照，卡的内容高度 = 岛的上限 - 它，取整。
    static let notchReferenceHeight: CGFloat = 36.67
    static let cardSize = CGSize(width: islandMaxWidth, height: (islandMaxHeight - notchReferenceHeight).rounded(.down))

    static let inset: CGFloat = 16
    static let earSide: CGFloat = 18
    static let rowGap: CGFloat = 3
    static let buttonHeight: CGFloat = 28
    static let buttonBottom: CGFloat = 12
    static let buttonGap: CGFloat = 8
    static let dotDiameter: CGFloat = 8
    /// 卡出现后这么久内的点按不算（防正在点别处的手）；Codex 那条路已有同样的新鲜度判断，这里只记数。
    static let freshPressSeconds: Double = 0.5

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
