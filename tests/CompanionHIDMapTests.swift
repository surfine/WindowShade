import Foundation

/// 1-4：iPhone 遥控器的键码、松开才算、触控门槛、会话时限。
@main struct CompanionHIDMapTests {
    static func main() {
        keyTable()
        releaseCounts()
        touches()
        sessions()
        print("PASS: companion HID map — release-only presses, 60/160 tap and vertical thresholds, 200 horizontal step, 1/2.5/3 s idle limits")
    }

    static func keyTable() {
        let expected: [UInt64: WS2.Button] = [1: .up, 2: .down, 3: .left, 4: .right, 5: .back, 6: .select, 7: .tv,
                                              8: .volumeUp, 9: .volumeDown, 14: .playPause, 18: .mute, 19: .power]
        for (code, button) in expected { precondition(CompanionHID.button(code: code) == button, "code \(code)") }
        for code: UInt64 in [0, 10, 11, 12, 13, 15, 16, 17, 20, 999] {
            precondition(CompanionHID.button(code: code) == nil, "认不出的键码 \(code) 不当成别的键")
        }
    }

    static func releaseCounts() {
        var buttons = CompanionHID.Buttons()
        precondition(buttons.feed(code: 6, state: 1) == nil, "按下不算")
        precondition(buttons.feed(code: 6, state: 1) == nil, "重复按下也不算")
        precondition(buttons.feed(code: 6, state: 2) == .select, "松开才算")
        precondition(buttons.feed(code: 6, state: 2) == nil, "没按下的松开不算")
        precondition(buttons.feed(code: 14, state: 2) == nil)
        precondition(buttons.feed(code: 5, state: 1) == nil)
        buttons.cancelAll()
        precondition(buttons.feed(code: 5, state: 2) == nil, "断线后按着的键作废")
        precondition(buttons.feed(code: 6, state: 3) == nil, "认不出的状态丢掉")
        precondition(buttons.feed(code: 99, state: 1) == nil && buttons.feed(code: 99, state: 2) == nil)
    }

    static func touches() {
        var touch = CompanionHID.Touch()
        precondition(touch.feed(phase: 1, x: 500, y: 500).isEmpty)
        precondition(touch.feed(phase: 2, x: 520, y: 510).isEmpty)
        precondition(touch.feed(phase: 4, x: 530, y: 520) == [.tap], "不到 60 算点")
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 4, x: 600, y: 500).isEmpty, "横着不满一步（200）不算")
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 4, x: 700, y: 520) == [.swipe(.right)], "满 200 发一步")
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 4, x: 300, y: 480) == [.swipe(.left)])
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 4, x: 480, y: 300) == [.swipe(.up)], "触控区 y 向下，往上滑是 up")
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 4, x: 500, y: 700) == [.swipe(.down)])
        // 竖滑阈值 16%（160）：159 不算，160 算；60 到 160 之间两样都不算。
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 4, x: 500, y: 341).isEmpty, "159 不够竖滑")
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 4, x: 500, y: 340) == [.swipe(.up)], "160 刚好算")
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 4, x: 500, y: 580).isEmpty, "60 到 160 之间两样都不算")
        // 边划边步进：0.65 宽的一次长划发 3 步，抬手不再补点按或多余的步。
        _ = touch.feed(phase: 1, x: 100, y: 500)
        var steps: [CompanionHID.Gesture] = []
        for x in stride(from: 150.0, through: 750.0, by: 50) { steps += touch.feed(phase: 2, x: x, y: 505) }
        precondition(steps == Array(repeating: .swipe(.right), count: 3), "650 宽发 3 步：\(steps)")
        precondition(touch.feed(phase: 4, x: 750, y: 505).isEmpty, "步进过的触摸抬手不再发点按")
        // 步进是在移动中发的，不用等抬手；起点每步重置，所以来回划各算各的。
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 2, x: 690, y: 500).isEmpty, "190 还没满一步")
        precondition(touch.feed(phase: 2, x: 700, y: 500) == [.swipe(.right)], "满 200 立刻发")
        precondition(touch.feed(phase: 2, x: 500, y: 500) == [.swipe(.left)], "起点已重置，回划 200 发反向一步")
        precondition(touch.feed(phase: 4, x: 500, y: 500).isEmpty)
        // 一次采样跳很远也不丢步。
        _ = touch.feed(phase: 1, x: 50, y: 500)
        precondition(touch.feed(phase: 4, x: 700, y: 500) == Array(repeating: .swipe(.right), count: 3), "650 的一跳也是 3 步")
        // 没开始就结束、坐标越界、NaN、未知阶段：放弃这次触摸。
        precondition(touch.feed(phase: 4, x: 900, y: 500).isEmpty)
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 2, x: 1200, y: 500).isEmpty)
        precondition(touch.feed(phase: 4, x: 900, y: 500).isEmpty, "越界后这一次作废")
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 4, x: .nan, y: 500).isEmpty)
        _ = touch.feed(phase: 1, x: 500, y: 500)
        precondition(touch.feed(phase: 3, x: 500, y: 500).isEmpty)
        precondition(touch.feed(phase: 4, x: 900, y: 500).isEmpty)
    }

    static func sessions() {
        precondition(CompanionHID.idleLimit(backgroundProbe: true, verifiedWithoutSession: true) == 1)
        precondition(CompanionHID.idleLimit(backgroundProbe: false, verifiedWithoutSession: true) == 3)
        precondition(CompanionHID.idleLimit(backgroundProbe: false, verifiedWithoutSession: false) == 2.5)
        precondition(CompanionHID.volumeControlFlag == 0x0100)
    }
}
