import Foundation
import CoreGraphics

// 编程会话审批卡的尺寸、摆法、琥珀点缩放与弹簧令牌选择（设计稿《刘海里的编程会话》§3、§4.6.1）。纯逻辑。
@main
struct SessionCardStyleTests {
    static func main() {
        var t = TestSuite("session-card-style")
        typealias S = SessionCardStyle

        t.section("S11B-01", "尺寸压进岛的上限：宽至多 408，连刘海那一截高至多 160")
        t.expect(S.cardSize.width <= 408, "卡宽不超过 408")
        t.expect(S.cardSize.height + S.notchReferenceHeight <= 160, "卡高加紧凑耳朵的高不超过 160")
        t.expect(S.cardSize.height > 100, "卡高没有被压得放不下四件事和按钮")

        t.section("S11B-02", "各行都在卡内，从上到下不叠、不压按钮")
        for risk in [false, true] {
            let l = S.layout(showsRisk: risk, showsDetails: false)
            let bounds = CGRect(origin: .zero, size: S.cardSize)
            let rects = [l.ear, l.dot, l.waiting, l.headline, l.byline] + (l.risk.map { [$0] } ?? [])
            t.expect(rects.allSatisfy { bounds.contains($0) }, "风险行\(risk ? "有" : "无")：每一行都在卡内")
            t.expect(l.headline.minY >= l.byline.maxY, "主句在副句上面")
            t.expect((l.risk?.maxY ?? l.byline.minY) <= l.byline.minY && (l.risk?.minY ?? l.buttonsTop) >= l.buttonsTop,
                     "风险行在副句下面、按钮上面")
            t.expect(l.headline.maxX <= l.dot.minX, "主句不压到右耳的点")
            t.expect(l.dot.maxX < l.waiting.minX + 6 && l.waiting.maxX <= S.cardSize.width - S.inset, "点在“等你”左边")
            t.expect((l.risk != nil) == risk, "风险行只在要求时出现")
        }
        let details = S.layout(showsRisk: true, showsDetails: true)
        t.expect(details.details.map { $0.height >= 36 && $0.minY >= details.buttonsTop && $0.maxY <= details.headline.minY } == true,
                 "去看看的详情放得进主句和按钮之间，至少三行")

        t.section("S11B-03", "缩放以琥珀点为不动点")
        let layout = S.layout(showsRisk: false, showsDetails: false)
        let origin = S.bloomOrigin(layout: layout)
        t.expect(origin == CGPoint(x: layout.dot.midX, y: layout.dot.midY), "默认原点是右耳点的中心")
        t.expect(S.bloomOrigin(layout: layout, override: CGPoint(x: 5, y: 6)) == CGPoint(x: 5, y: 6), "调用方可以传真实位置")
        let center = CGPoint(x: S.cardSize.width / 2, y: S.cardSize.height / 2)
        for scale in [S.enterScale, 0.7, 1] as [CGFloat] {
            let transform = S.layerTransform(scale: scale, about: origin, center: center)
            // 层上的点 x 落在 center + t(x - center)；原点自己不动。
            let local = CGPoint(x: origin.x - center.x, y: origin.y - center.y).applying(transform)
            let landed = CGPoint(x: center.x + local.x, y: center.y + local.y)
            t.expect(abs(landed.x - origin.x) < 1e-9 && abs(landed.y - origin.y) < 1e-9, "缩放 \(scale)：琥珀点留在原处")
        }
        let identity = S.layerTransform(scale: 1, about: origin, center: center)
        t.expect(identity == .identity, "缩放 1 是恒等")
        let t0 = S.layerTransform(scale: S.enterScale, about: origin, center: center)
        let fromCorner = CGPoint(x: -center.x, y: -center.y).applying(t0)
        let landedCorner = CGPoint(x: center.x + fromCorner.x, y: center.y + fromCorner.y)
        t.expect(hypot(landedCorner.x - origin.x, landedCorner.y - origin.y) < hypot(origin.x, origin.y), "缩小后的卡角比原来更靠近琥珀点")

        t.section("S11B-04", "弹簧令牌：进 bloom、出 settle、回来 calm；减少动态效果全是 reducedNotch 且不缩放")
        t.expect(S.plan(.enter, reduced: false) == .init(token: .bloom, scale: S.enterScale), "进：bloom，从点里长出来")
        t.expect(S.plan(.retreat, reduced: false) == .init(token: .settle, scale: S.enterScale), "放行或超时：settle，缩回点")
        t.expect(S.plan(.resume, reduced: false) == .init(token: .calm, scale: 1), "挂起后回来：calm，只淡不重播放大")
        for moment in [S.Moment.enter, .retreat, .resume] {
            t.expect(S.plan(moment, reduced: true) == .init(token: .reducedNotch, scale: 1), "\(moment) 减少动态效果：原处淡入淡出")
        }

        t.section("S11B-05", "风险一行：普通不写；高风险和说不清用警示符号加一句原因")
        t.expect(AgentApprovalCard.riskNote(.normal) == nil, "普通没有风险行")
        for risk in [WS2.Risk.high, .unknown] {
            let note = AgentApprovalCard.riskNote(risk)
            t.expect(note?.symbol == "exclamationmark.triangle.fill" && note?.text.isEmpty == false, "\(risk)：符号加原因")
        }
        t.expect(AgentApprovalCard.riskNote(.high)?.text != AgentApprovalCard.riskNote(.unknown)?.text, "两种风险说的不是同一句")
        t.expect(AgentApprovalCard.needsTouchID(.unknown) == (AgentApprovalCard.riskNote(.unknown) != nil)
                 && AgentApprovalCard.needsTouchID(.normal) == (AgentApprovalCard.riskNote(.normal) != nil),
                 "有风险行的正是要 Touch ID 的")

        t.finish()
    }
}
