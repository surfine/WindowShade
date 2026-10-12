import Cocoa

/// 计时器的三张卡（选分钟、大卡、时间到）：尺寸照稿，键盘就能选、开始、暂停、结束、再来一个，输入权被撤销后一律不响应。
@main enum CountdownTimerCardTests {
    @MainActor static func main() async {
        _ = NSApplication.shared
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition { print("ok   \(label)") } else { failures += 1; print("FAIL \(label)") }
        }
        func at(_ seconds: Double) -> WS2.Instant { WS2.Instant(seconds: seconds)! }
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                             characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }

        print("CASE TMR2-C01 | 尺寸照稿：岛的总高 = 刘海 33.5 + 内容")
        let picker = CountdownTimerCard(mode: .picker, minutes: 10)
        expect(picker.interactionSize == NSSize(width: 400, height: 84), "选分钟 400 × (117.5 − 33.5)")
        expect(CountdownTimerCard(mode: .running, minutes: 10).interactionSize == NSSize(width: 440, height: 142), "大卡 440 × (175.5 − 33.5)")
        expect(CountdownTimerCard(mode: .alert, minutes: 10).interactionSize == NSSize(width: 400, height: 52), "时间到 400 × (85.5 − 33.5)")

        // 经过实际宿主测形状，不能只验证卡片自报尺寸；夹具留在屏幕外。
        let panel = NotchPanel(notch: NSRect(x: -8000, y: 866.5, width: 185, height: 33.5), virtual: false)
        panel.isReleasedWhenClosed = false
        defer { panel.setInteraction(nil, animated: false); panel.close() }
        for (mode, width, height, radius) in [(CountdownTimerCard.Mode.picker, 400.0, 117.5, 24.0),
                                            (.running, 440.0, 175.5, 28.0), (.alert, 400.0, 85.5, 24.0)] {
            panel.setInteraction(CountdownTimerCard(mode: mode, minutes: 10), animated: false)
            let shape = panel.shapeForProbe
            expect(shape?.island.size == NSSize(width: width, height: height) && shape?.radius == CGFloat(radius),
                   "实际宿主 \(mode)：\(width) × \(height)，底角 \(radius)")
        }

        print("CASE TMR2-C02 | 选分钟：↑ ↓ 调，回车开始，Esc 取消")
        var started: [Int] = [], cancelled = 0
        picker.onStart = { started.append($0) }
        picker.onCancel = { cancelled += 1 }
        picker.inputIsCurrent = { true }
        expect(picker.selection == 10, "上次是 10 分钟")
        picker.keyDown(with: key(126)); picker.keyDown(with: key(126))
        expect(picker.selection == 12, "↑ 两下 = 12 分钟")
        picker.keyDown(with: key(125))
        expect(picker.selection == 11, "↓ 一下 = 11 分钟")
        picker.keyDown(with: key(36))
        expect(started == [11], "回车开始，用现在选的分钟")
        picker.keyDown(with: key(76))
        expect(started == [11, 11], "小键盘回车也开始")
        picker.keyDown(with: key(53))
        expect(cancelled == 1, "Esc 取消")
        picker.inputIsCurrent = { false }
        picker.keyDown(with: key(126)); picker.keyDown(with: key(36))
        expect(picker.selection == 11 && started == [11, 11], "输入权被撤销后不响应")

        print("CASE TMR2-C03 | 大卡和时间到：空格暂停 / 继续，删除结束，回车再来一个")
        let card = CountdownTimerCard(mode: .running, minutes: 10)
        var toggles = 0, ends = 0, agains = 0
        card.onTogglePause = { toggles += 1 }
        card.onEnd = { ends += 1 }
        card.onAgain = { agains += 1 }
        card.inputIsCurrent = { true }
        var model = CountdownTimer()
        _ = model.handle(.start(minutes: 10), at: at(0))
        card.render(model, at: at(60))
        expect(card.accessibilityLabel() == "计时器，还剩 9 分钟", "读屏念“计时器，还剩 9 分钟”")
        card.keyDown(with: key(49))
        expect(toggles == 1, "空格暂停")
        card.keyDown(with: key(36))
        expect(agains == 0, "没到点时回车不当“再来一个”")
        card.keyDown(with: key(51))
        expect(ends == 1, "删除结束")
        _ = model.handle(.pause, at: at(60))
        card.render(model, at: at(120))
        expect(card.accessibilityLabel() == "计时器，已暂停，还剩 9 分钟", "暂停后读屏念已暂停")
        _ = model.handle(.resume, at: at(120))
        _ = model.handle(.tick, at: at(720))
        card.render(model, at: at(720))
        card.keyDown(with: key(49))
        expect(toggles == 1, "时间到之后空格不再暂停")
        card.keyDown(with: key(36))
        expect(agains == 1, "时间到：回车 = 再来一个")
        expect(card.accessibilityLabel() == "计时器，时间到，已超时 1 分", "超时读屏")

        print("CASE TMR2-C04 | 时间到的提醒卡")
        let alert = CountdownTimerCard(mode: .alert, minutes: 10)
        var alertEnds = 0, alertAgains = 0
        alert.onEnd = { alertEnds += 1 }
        alert.onAgain = { alertAgains += 1 }
        alert.inputIsCurrent = { true }
        alert.render(model, at: at(720))
        expect(alert.accessibilityLabel() == "时间到，10 分钟计时器", "读屏念主句和次句")
        alert.keyDown(with: key(36))
        alert.keyDown(with: key(51))
        expect(alertAgains == 1 && alertEnds == 1, "回车再来一个，删除结束")

        print(failures == 0 ? "PASS CountdownTimerCardTests" : "FAIL CountdownTimerCardTests: \(failures) failure(s)")
        if failures > 0 { exit(1) }
    }
}
