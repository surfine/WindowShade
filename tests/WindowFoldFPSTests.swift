// PERF-13：窗口折叠会话采集帧率分档的纯逻辑（prototype/Effects/WindowFoldFPS.swift）。
// 钉住：跟手/动画中 60、盖板定住 15、阈值边界、负向手指差。

import Foundation

@main struct WindowFoldFPSTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    static func main() {
        expect(WindowFoldFPS.active == 60, "活动档 60")
        expect(WindowFoldFPS.idle == 15, "静止档 15（与桌面会话 resting 档一致）")
        // tracking：手指与显示值的差距。追平（含收敛吸附后的 0）→ 15；任何真实移动 → 60。
        expect(WindowFoldFPS.wanted(fingerDelta: 0) == WindowFoldFPS.idle, "完全追平 → 静止档")
        expect(WindowFoldFPS.wanted(fingerDelta: 0.0009) == WindowFoldFPS.idle, "低于阈值仍算停")
        expect(WindowFoldFPS.wanted(fingerDelta: 0.001) == WindowFoldFPS.active, "到阈值即回活动档")
        expect(WindowFoldFPS.wanted(fingerDelta: 0.5) == WindowFoldFPS.active, "大幅移动 → 活动档")
        expect(WindowFoldFPS.wanted(fingerDelta: -0.02) == WindowFoldFPS.active, "反向移动也算活动")
        // animate：transition.settled。
        expect(WindowFoldFPS.wanted(transitionSettled: true) == WindowFoldFPS.idle, "动画 settled → 静止档")
        expect(WindowFoldFPS.wanted(transitionSettled: false) == WindowFoldFPS.active, "动画进行中 → 活动档")
        print("PASS window-fold-fps-tier")
    }
}
