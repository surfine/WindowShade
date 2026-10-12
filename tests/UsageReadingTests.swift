// 用量（实验）：解析 rate limits 事件；10% 以内只提醒一次；没有数据回到会话状态；“等你”不被压过。纯逻辑。

import Foundation

@main struct UsageReadingTests {
    nonisolated(unsafe) static var assertions = 0
    static func expect(_ condition: Bool, _ message: String) {
        assertions += 1
        precondition(condition, "断言失败: \(message)")
    }

    static func json(_ text: String) -> WireJSON { try! JSONDecoder().decode(WireJSON.self, from: Data(text.utf8)) }
    static func reading(_ used: Int, reset: Int = 1_800_003_600) -> UsageReading {
        UsageReading.parse(json(#"{"rateLimits":{"primary":{"usedPercent":\#(used),"windowDurationMins":300,"resetsAt":\#(reset)},"secondary":null}}"#))!
    }
    static let now = 1_800_000_000.0
    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    static func usage(_ used: Int, reset: Int = 1_800_003_600) -> CodingSessionUsage {
        reading(used, reset: reset).sessionUsage(now: now, model: "gpt-5", effort: "高", calendar: calendar)!
    }
    static func running() -> CodingSessionActivities {
        var m = CodingSessionActivities()
        m.apply(.init(id: "s1", project: "WindowShade", cwd: "/a", assistant: "Claude Code", status: .running), now: 1)
        return m
    }

    static func main() {
        testParse()
        testNoDataIsNil()
        testRecoveryText()
        testRecoveryNeedsConfirmation()
        testCompactAndAmber()
        testAlertOncePerWindow()
        testNoDataFallsBack()
        testWaitingNotOutranked()
        print("UsageReadingTests: \(assertions) assertions passed")
    }

    static func testParse() {
        let r = reading(76)
        expect(r.windows.count == 1 && r.windows[0].leftPercent == 24, "剩余 = 100 - 已用")
        expect(r.windows[0].windowMinutes == 300 && r.windows[0].resetsAt == 1_800_003_600, "窗口时长与恢复时刻照服务端")
        let both = UsageReading.parse(json(#"{"rateLimits":{"primary":{"usedPercent":40.4,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":93,"windowDurationMins":10080,"resetsAt":1800400000}}}"#))!
        expect(both.windows.count == 2 && both.tightest?.windowMinutes == 10080, "取剩得最少的窗口")
        expect(both.windows[0].leftPercent == 60, "小数四舍五入")
        let pooled = UsageReading.parse(json(#"{"rateLimits":{"primary":{"usedPercent":1}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":55}}}}"#))!
        expect(pooled.windows[0].leftPercent == 45, "按额度池发时认 codex 那一池")
        let partial = UsageReading.parse(json(#"{"rateLimits":{"primary":{"usedPercent":10}}}"#))!
        expect(partial.windows[0].resetsAt == nil && partial.sessionUsage(now: now)?.recovery == nil, "没给恢复时刻就不编")
        let malformed = UsageReading.parse(json(#"{"rateLimits":{"primary":{"usedPercent":95,"resetsAt":1e300}}}"#))!
        expect(malformed.windows[0].resetsAt == nil && malformed.sessionUsage(now: now)?.leftPercent == 5, "超出可表示恢复时间时保真实额度，拒绝坏时间，不在窗口身份转Int崩溃")
    }

    static func testNoDataIsNil() {
        for text in [#"{}"#, #"{"rateLimits":null}"#, #"{"rateLimits":{"primary":null,"secondary":null}}"#,
                     #"{"rateLimits":{"primary":{"usedPercent":"x"}}}"#, #"{"rateLimits":{"primary":{"usedPercent":150}}}"#,
                     #"{"rateLimits":{"primary":{"usedPercent":-5}}}"#, #"{"rateLimits":{"primary":{}}}"#, #"[]"#] {
            expect(UsageReading.parse(json(text)) == nil, "没有可信窗口就是没有数据: \(text)")
        }
    }

    static func testRecoveryText() {
        expect(UsageReading.recoveryText(resetsAt: now + 18 * 60, now: now, calendar: calendar) == "18 分钟后", "一小时内写分钟")
        expect(UsageReading.recoveryText(resetsAt: now + 2 * 3600, now: now, calendar: calendar) == "2 小时后", "一天内写小时")
        expect(UsageReading.recoveryText(resetsAt: now - 5, now: now, calendar: calendar) == "等待用量更新", "过了只等待真实更新")
        let far = UsageReading.recoveryText(resetsAt: 1_800_400_000, now: now, calendar: calendar)
        expect(far == "周二 23:06", "更远写周几和时刻: \(far)")
    }

    static func testRecoveryNeedsConfirmation() {
        for reset in [Int(now) - 5, Int(now)] {
            let past = usage(95, reset: reset)
            expect(past.leftPercent == 5 && past.compactText == "剩 5%", "到恢复时刻不重写真实剩余")
            expect(past.recovery == nil && past.detailText.contains("等待用量更新"), "旧读数到期只预计，不许写马上恢复")
            var sessions = running()
            _ = sessions.applyUsage(past)
            expect(sessions.liveSpec?.subtitle.contains("等待用量更新") == true, "等待确认交到实际会话内容")
            expect(sessions.liveSpec?.subtitle.contains("gpt-5") == true, "等待确认仍保会话模型")
            _ = sessions.applyUsage(usage(5, reset: Int(now) + 3600))
            expect(sessions.liveSpec?.trailing == "剩 95%" && sessions.liveSpec?.subtitle.contains("等待更新") == false, "新来源读数才退出等待，量仍照来源")
        }
    }

    static func testCompactAndAmber() {
        expect(usage(76).compactText == "剩 24%" && !usage(76).isLow, "有数据写剩 p%")
        expect(usage(90).isLow && usage(90).leftPercent == 10, "10% 含在内变琥珀")
        expect(!usage(89).isLow, "11% 不变")
        var m = running()
        _ = m.applyUsage(usage(76))
        var spec = m.liveSpec!
        expect(spec.trailing == "剩 24%" && spec.phase == .quota, "没人等你：右耳是剩 24%")
        expect(spec.symbol == "gauge.with.dots.needle.33percent", "展开格的符号")
        expect(spec.subtitle.contains("1 小时后恢复") && spec.subtitle.contains("gpt-5") && spec.subtitle.contains("高"), "展开格写恢复时间、模型、强度")
        _ = m.applyUsage(usage(95))
        spec = m.liveSpec!
        expect(spec.trailing == "剩 5%" && spec.phase == .quotaLow, "≤10% 压过在跑，琥珀")
    }

    static func testAlertOncePerWindow() {
        var m = running()
        expect(m.applyUsage(usage(80)) == nil, "还多着不提醒")
        let bloom = m.applyUsage(usage(92))
        expect(bloom?.headline == "额度快用完了" && bloom?.detail == "1 小时后恢复", "第一次掉到 10% 以内：主句副句")
        expect(m.applyUsage(usage(95)) == nil, "同一窗口不再提醒")
        expect(m.applyUsage(usage(99)) == nil, "同一窗口继续用也不再提醒")
        expect(m.applyUsage(usage(92, reset: 1_800_090_000)) != nil, "下一个窗口再提醒一次")
        expect(m.applyUsage(usage(10, reset: 1_800_090_000)) == nil, "额度回来不提醒")
        let weekly = UsageReading.parse(json(#"{"rateLimits":{"primary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":1800090000},"secondary":{"usedPercent":97,"windowDurationMins":10080,"resetsAt":1800400000}}}"#))!
        expect(m.applyUsage(weekly.sessionUsage(now: now, calendar: calendar)) != nil, "周窗口单独提醒")
    }

    static func testNoDataFallsBack() {
        var m = running()
        let plain = m.liveSpec!
        expect(plain.phase == .running && plain.trailing == "" && plain.symbol == "terminal", "没有数据：在跑")
        _ = m.applyUsage(usage(50))
        expect(m.applyUsage(nil) == nil, "没有数据不开口")
        expect(m.liveSpec == plain, "没有数据：回到会话状态，不画成无限")
        _ = m.applyUsage(usage(50)); m.reset()
        expect(m.usage == nil, "会话关掉就忘掉")
    }

    static func testWaitingNotOutranked() {
        var m = running()
        _ = m.applyUsage(usage(97))
        m.apply(.init(id: "s1", project: "WindowShade", cwd: "/a", assistant: "Claude Code", status: .waiting, summary: "Bash"), now: 5)
        let spec = m.liveSpec!
        expect(spec.phase == .waiting && spec.trailing == "等你", "额度再低也不压过等你")
        var two = running()
        two.apply(.init(id: "s2", project: "B", cwd: "/b", assistant: "Claude Code", status: .running), now: 2)
        _ = two.applyUsage(usage(50))
        expect(two.liveSpec?.trailing == "剩 50%" && two.liveSpec?.title == "2 个会话", "多个会话在跑也写剩 p%")
    }
}
