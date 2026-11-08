// 岛的六态模型（C02）：27.3 #islandSizing 的 tag 0–5、形状 adapter、状态→弹簧。
// 纯计算，不碰窗口（不访问 NSWorkspace）。
import Foundation

@main
struct IslandMotionStateTests {
    static func state(
        auth: Bool = false, authCard: Bool = false, expanded: Bool = false,
        alert: Bool = false, meter: Bool = false, dragging: Bool = false,
        compact: IslandCompactKind? = nil, activity: IslandMotionState? = nil
    ) -> IslandMotionState {
        IslandMotionState.resolve(
            isAuthenticating: auth, authenticationIsExpandedCard: authCard,
            isExpanded: expanded, hasAlert: alert, hasMeter: meter,
            isDragging: dragging, compactKind: compact, compactActivity: activity
        )
    }

    static func main() {
        var t = TestSuite("C02")

        t.section("C02-01", "27.3 六态 tag：0 listening、1 thinking、2 response、3 transient、4 hidden、5 prompt")
        t.expect(IslandMotionState.listening.systemTag == 0, "listening = 0")
        t.expect(IslandMotionState.thinking.systemTag == 1, "thinking = 1")
        t.expect(IslandMotionState.response.systemTag == 2, "response = 2")
        t.expect(IslandMotionState.transient.systemTag == 3, "transient = 3")
        t.expect(IslandMotionState.hidden.systemTag == 4, "hidden = 4")
        t.expect(IslandMotionState.prompt.systemTag == 5, "prompt = 5")
        let tags = IslandMotionState.allCases.map(\.systemTag)
        t.expect(tags.count == 6 && Set(tags).count == 6 && tags.sorted() == Array(0...5), "六个 tag 不重不漏")

        t.section("C02-02", "形状 → 状态：与 NotchController.motionShape() 的优先序一致")
        let table: [(Motion.NotchShape, IslandMotionState, Motion.Spring, String)] = [
            (.minimum, .hidden, .islandHidden, "hidden"),
            (.compact, .thinking, .islandSizing, "thinking"),
            (.chin, .thinking, .islandSizing, "thinking"),
            (.capsuleCompact, .thinking, .islandSizing, "thinking"),
            (.alert, .transient, .islandSizing, "transient"),
            (.expanded, .response, .islandSizing, "response"),
            (.interaction, .prompt, .islandPrompt, "prompt"),
            (.meter, .transient, .islandSizing, "transient"),
            (.drop, .transient, .islandSizing, "transient"),
        ]
        t.expect(table.count == Motion.NotchShape.allCases.count, "映射表覆盖每一种形状")
        for (shape, state, token, name) in table {
            t.expect(IslandMotionState(shape: shape) == state, "\(shape) → \(name)")
            t.expect(Motion.notchSpring(for: state, reduced: false) == token, "\(name) 用 \(name) 令牌")
        }

        t.section("C02-03", "状态 → 弹簧：listening／prompt 用 islandPrompt，其余内容态用 islandSizing")
        t.expect(Motion.notchSpring(for: .listening, reduced: false) == .islandPrompt, "listening → islandPrompt")
        t.expect(Motion.notchSpring(for: .prompt, reduced: false) == .islandPrompt, "prompt → islandPrompt")
        for state in [IslandMotionState.thinking, .response, .transient] {
            t.expect(Motion.notchSpring(for: state, reduced: false) == .islandSizing, "\(state) → islandSizing")
        }
        t.expect(Motion.notchSpring(for: .hidden, reduced: false) == .islandHidden,
                 "hidden → islandHidden（WindowSizingAnimation.default 0.3/bounce 0.2）")
        t.expect(Motion.notchSpring(for: .thinking, transition: .collapse, reduced: false) == .islandSizing,
                 "collapse 目前不改令牌")

        t.section("C02-04", "减少动态效果：六态一律 reducedNotch")
        for state in IslandMotionState.allCases {
            t.expect(Motion.notchSpring(for: state, reduced: true) == .reducedNotch, "\(state) → reducedNotch")
        }

        t.section("C02-05", "resolve：认证卡／拖放／提醒／音量／展开／紧凑／静止")
        t.expect(state(auth: true, authCard: true) == .response, "认证大卡 → response")
        t.expect(state(auth: true) == .prompt, "认证交互 → prompt")
        t.expect(state(dragging: true) == .transient, "拖放 → transient")
        t.expect(state(alert: true) == .transient, "提醒 → transient")
        t.expect(state(meter: true) == .transient, "音量亮度 → transient")
        t.expect(state(expanded: true) == .response, "展开 → response")
        for kind in IslandCompactKind.allCases {
            t.expect(state(compact: kind) == .thinking, "紧凑 \(kind) → thinking")
        }
        t.expect(state() == .hidden, "什么都没有 → hidden")
        // 优先序：认证 > 拖放 > 提醒 > 音量 > 展开 > 紧凑 > 静止
        t.expect(state(auth: true, expanded: true, alert: true, meter: true, dragging: true, compact: .sides) == .prompt,
                 "认证压过其他")
        t.expect(state(expanded: true, alert: true, meter: true, dragging: true) == .transient, "拖放压过提醒/音量/展开")
        t.expect(state(expanded: true, alert: true, meter: true) == .transient, "提醒压过音量/展开")
        t.expect(state(expanded: true, meter: true) == .transient, "音量压过展开")
        t.expect(state(expanded: true, compact: .sides) == .response, "展开压过紧凑")

        t.section("C02-06", "紧凑两耳由活动撑起时，用活动自己的状态；其他优先级仍压过它")
        t.expect(state(compact: .sides, activity: .prompt) == .prompt, "录音／等你的会话 → prompt")
        t.expect(state(compact: .sides, activity: .response) == .response, "音乐等 → response")
        t.expect(state(compact: .sides, activity: nil) == .thinking, "没有活动 → thinking")
        t.expect(state(auth: true, compact: .sides, activity: .prompt) == .prompt, "认证仍是 prompt")
        t.expect(state(expanded: true, compact: .sides, activity: .prompt) == .response, "展开压过活动")
        t.expect(state(alert: true, compact: .sides, activity: .prompt) == .transient, "提醒压过活动")

        t.finish()
    }
}
