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

        t.section("S11B2-01", "尺寸只从 IslandMetrics 来")
        t.expect(S.cardSize.width == IslandMetrics.expandedWidth && S.notchReferenceHeight == IslandMetrics.compactHeight, "卡宽、耳高取自 IslandMetrics")

        t.section("S11B2-02", "缩回：弹簧解析解的位置与速度")
        for z in [1.0, 0.84] {
            let run = S.SpringRun(response: 0.38, dampingRatio: z, from: 0, to: 1)
            t.expect(abs(run.position(at: 0)) < 1e-12 && abs(run.velocity(at: 0)) < 1e-12, "z=\(z)：起点在 from、初速 0")
            t.expect(abs(run.position(at: 3) - 1) < 1e-6, "z=\(z)：最后落在 to")
            for time in [0.05, 0.15, 0.3] {
                let h = 1e-5
                let numeric = (run.position(at: time + h) - run.position(at: time - h)) / (2 * h)
                t.expect(abs(numeric - run.velocity(at: time)) < 1e-4, "z=\(z)：t=\(time) 速度与位置的导数一致")
            }
        }
        let critical = S.SpringRun(response: 0.38, dampingRatio: 1, from: 0, to: 1)
        t.expect((0...300).allSatisfy { critical.position(at: Double($0) / 100) <= 1 + 1e-9 }, "settle 不回弹：从不越过口子")
        let mid = S.SpringRun(response: 0.38, dampingRatio: 1, from: 0.4, to: 1, initialVelocity: 2)
        t.expect(abs(mid.velocity(at: 0) - 2) < 1e-12 && abs(mid.position(at: 0) - 0.4) < 1e-12, "接着走：起点和初速都是给的")

        t.section("S11B2-03", "缩回的姿态：缩放和透明度由同一个进度推出")
        let retreat = S.plan(.retreat, reduced: false)
        t.expect(S.pose(progress: 0, plan: retreat) == (1, 1) && S.pose(progress: 1, plan: retreat) == (S.enterScale, 0), "0 是整卡，1 是缩进点里并淡没")
        let reducedPose = S.pose(progress: 1, plan: S.plan(.retreat, reduced: true))
        t.expect(reducedPose.scale == 1 && reducedPose.opacity == 0, "减少动态效果：原处淡出，不缩放")
        t.expect(S.pose(progress: -1, plan: retreat).scale == 1 && S.pose(progress: 9, plan: retreat).opacity == 0, "进度越界取边")

        t.section("S11B2-04", "2 分钟没人管：缩回琥珀点，不回答、不改期限")
        var rule = S.IdleRule(shownAt: 100, requestDeadline: 130)
        t.expect(S.IdleRule.idleSeconds == 120, "2 分钟")
        t.expect(rule.fire(now: 219.9) == .none && !rule.parked, "没到点不动")
        t.expect(rule.fire(now: 220) == .retreatToDot && rule.parked, "到点：缩回琥珀点")
        t.expect(rule.requestDeadline == 130, "请求的期限原样没动（Codex 的 30 秒、Claude Code 的无期限都不碰）")
        t.expect(rule.fire(now: 500) == .none, "只缩回一次")
        t.expect(rule.restore(now: 600) && !rule.parked && rule.shownAt == 600, "点耳朵把卡请回来，重新计 2 分钟")
        t.expect(rule.fire(now: 719) == .none && rule.fire(now: 720) == .retreatToDot, "请回来后又是 2 分钟")
        var answered = S.IdleRule(shownAt: 0)
        answered.cancel()
        t.expect(answered.fire(now: 999) == .none && !answered.restore(now: 1000), "已回答或交给 Touch ID 的不再触发、不再回来")
        var never = S.IdleRule(shownAt: 0, requestDeadline: nil)
        t.expect(!never.restore(now: 1), "没缩回去就谈不上请回来")

        t.finish()
    }
}
