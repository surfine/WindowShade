// 离开期间摘要（Core/AwaySummary.swift）：空进空出、去重、上限、顺序、区间边界、账本收账。
import Foundation

@main
struct AwaySummaryTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static let span = AwaySummary.Interval(start: 100, end: 200)
    typealias S = AwaySummary

    static func reality(tucked: Int = 0, windows: Bool = true, devices: Bool = true) -> AwayLog.Reality {
        AwayLog.Reality(tuckedCount: tucked, windowIsCurrent: { _ in windows }, deviceIsCurrent: { _, _ in devices })
    }

    static func main() {
        // 空进空出
        expect(S.build(tuckedCount: 5, interval: span) == nil, "nothing recorded gives no summary even with tucked windows")
        expect(S.build(intrusions: [.init(text: "x", at: 50)], devices: [.init(deviceID: "a", name: "鼠标", part: nil, percent: 8, at: 250)],
                       tuckedCount: 0, interval: span) == nil, "everything outside the interval gives nothing")
        expect(S.build(windows: [.init(id: 1, app: "终端", at: 150)], tuckedCount: 0,
                       interval: .init(start: 200, end: 100)) == nil, "an inverted interval gives nothing")
        expect(S.build(intrusions: [.init(text: "", at: 150)], tuckedCount: 0, interval: span) == nil, "an empty sentence is not an item")

        // 区间边界：两端都算
        let edge = S.build(downloads: [.init(name: "a.zip", at: 100)], tuckedCount: 0, interval: span)
        expect(edge?.items.count == 1, "an event exactly at the start counts")
        let edgeEnd = S.build(downloads: [.init(name: "a.zip", at: 200)], tuckedCount: 0, interval: span)
        expect(edgeEnd?.items.count == 1, "an event exactly at the end counts")
        expect(S.build(downloads: [.init(name: "a.zip", at: 99.999)], tuckedCount: 0, interval: span) == nil, "just before the start is out")
        expect(S.build(downloads: [.init(name: "a.zip", at: 200.001)], tuckedCount: 0, interval: span) == nil, "just after the end is out")
        expect(S.build(downloads: [.init(name: "a.zip", at: .nan)], tuckedCount: 0, interval: span) == nil, "a NaN time is never in range")

        // 去重
        let dupIntrusion = S.build(intrusions: [.init(text: "被解锁了一次", at: 120), .init(text: "被解锁了一次", at: 160)],
                                   tuckedCount: 0, interval: span)
        expect(dupIntrusion?.items.count == 1, "the same intrusion sentence is listed once")
        let dupDevice = S.build(devices: [
            .init(deviceID: "m", name: "妙控鼠标", part: nil, percent: 18, at: 110),
            .init(deviceID: "m", name: "妙控鼠标", part: nil, percent: 8, at: 150),
            .init(deviceID: "m", name: "妙控鼠标", part: nil, percent: 18, at: 170)], tuckedCount: 0, interval: span)
        expect(dupDevice?.items.map(\.text) == ["妙控鼠标 8%"], "one device part keeps its lowest reading")
        let parts = S.build(devices: [
            .init(deviceID: "p", name: "AirPods", part: "左耳", percent: 8, at: 110),
            .init(deviceID: "p", name: "AirPods", part: "右耳", percent: 9, at: 111)], tuckedCount: 0, interval: span)
        expect(parts?.items.map(\.text) == ["AirPods 左耳 8%", "AirPods 右耳 9%"], "earbud sides stay separate")
        let dupWindows = S.build(windows: [
            .init(id: 7, app: "终端", at: 110), .init(id: 7, app: "终端", at: 150), .init(id: 9, app: "终端", at: 130)],
            tuckedCount: 0, interval: span)
        expect(dupWindows?.items.map(\.text) == ["终端 2 扇有变化"], "windows of one app merge, a repeated window counts once")
        expect(dupWindows?.items.first?.windowID == 7, "the merged item points at the most recently changed window")
        let oneWindow = S.build(windows: [.init(id: 3, app: "终端", at: 150)], tuckedCount: 0, interval: span)
        expect(oneWindow?.items.map(\.text) == ["终端有变化"], "a single window reads 终端有变化")
        let dupDownloads = S.build(downloads: [.init(name: "a.zip", at: 110), .init(name: "a.zip", at: 120)], tuckedCount: 0, interval: span)
        expect(dupDownloads?.items.map(\.text) == ["下载好了 · a.zip"], "the same finished file is listed once")
        let manyDownloads = S.build(downloads: [.init(name: "a.zip", at: 110), .init(name: "b.zip", at: 120)], tuckedCount: 0, interval: span)
        expect(manyDownloads?.items.map(\.text) == ["下载好了 · 2 个文件"], "several finished files collapse into a count")
        let longName = S.build(downloads: [.init(name: String(repeating: "长", count: 30), at: 110)], tuckedCount: 0, interval: span)
        expect((longName?.items.first?.text.count ?? 99) < 25, "a long file name is clipped")

        // 顺序：有人动过 → 设备 → 窗口 → 下载
        let all = S.build(
            intrusions: [.init(text: "被解锁了一次", at: 150)],
            devices: [.init(deviceID: "m", name: "妙控鼠标", part: nil, percent: 18, at: 150)],
            windows: [.init(id: 1, app: "终端", at: 150)],
            downloads: [.init(name: "a.zip", at: 150)], tuckedCount: 3, interval: span)
        expect(all?.items.map(\.kind) == [.intrusion, .device, .window, .download], "kinds come out intrusion, device, window, download")
        expect(all?.lines == ["收着 3 扇窗口", "被解锁了一次", "妙控鼠标 18%", "终端有变化", "下载好了 · a.zip"], "lines lead with the tucked count")
        expect(all?.firstWindowID == 1, "the first reachable window is found past non-window items")
        expect(all?.compactDetail == "被解锁了一次，还有 3 件", "the compact line is the first item plus how many more")
        expect(all?.spoken == "收着 3 扇窗口；被解锁了一次；妙控鼠标 18%；终端有变化；下载好了 · a.zip", "the spoken form joins every line")
        let lowFirst = S.build(devices: [
            .init(deviceID: "a", name: "妙控键盘", part: nil, percent: 18, at: 150),
            .init(deviceID: "b", name: "妙控鼠标", part: nil, percent: 5, at: 150)], tuckedCount: 0, interval: span)
        expect(lowFirst?.items.map(\.text) == ["妙控鼠标 5%", "妙控键盘 18%"], "the emptiest device comes first")
        let newestWindow = S.build(windows: [.init(id: 1, app: "邮件", at: 120), .init(id: 2, app: "终端", at: 180)], tuckedCount: 0, interval: span)
        expect(newestWindow?.items.map(\.text) == ["终端有变化", "邮件有变化"], "the most recently changed app comes first")

        // 上限
        var many: [S.WindowEntry] = []
        for i in 0..<10 { many.append(.init(id: UInt32(i), app: "App\(i)", at: 110 + Double(i))) }
        let capped = S.build(devices: [.init(deviceID: "m", name: "妙控鼠标", part: nil, percent: 8, at: 150)],
                             windows: many, tuckedCount: 0, interval: span)
        expect(capped?.items.count == S.maxItems && capped?.omitted == 10 + 1 - S.maxItems, "items are capped and the rest are counted")
        expect(capped?.items.first?.kind == .device, "the cap drops from the end, never the first kind")
        expect(capped?.lines.last == "还有 \(11 - S.maxItems) 件", "the omitted count is the last line")
        expect(capped?.count == 11, "count covers shown and omitted")

        // 账本
        var log = AwayLog()
        log.noteWindowChange(id: 1, app: "终端", at: 10)
        log.noteIntrusion("x", at: 10)
        expect(log.isEmpty && !log.isAway, "nothing is recorded before the away starts")
        expect(log.finish(unlocked: true, at: 50, reality: reality()) == .nothing, "finishing without an away gives nothing")
        log.begin(at: 100)
        log.begin(at: 150)
        expect(log.start == 100, "a second begin keeps the earliest start")
        log.noteWindowChange(id: 1, app: "终端", at: 120)
        log.noteLowBattery(deviceID: "m", name: "妙控鼠标", part: nil, percent: 8, at: 130)
        log.noteDownloads(["a.zip"], at: 140)
        log.noteIntrusion("被解锁了一次", at: 145)
        expect(log.finish(unlocked: false, at: 160, reality: reality()) == .stillAway, "still locked keeps the log and says so")
        expect(log.isAway && !log.isEmpty, "a still-locked finish does not clear anything")
        if case .summary(let summary) = log.finish(unlocked: true, at: 170, reality: reality(tucked: 2)) {
            expect(summary.items.map(\.kind) == [.intrusion, .device, .window, .download] && summary.tuckedCount == 2,
                   "an unlocked finish returns the full summary")
        } else { expect(false, "an unlocked finish returns the full summary") }
        expect(log.isEmpty && !log.isAway, "the log is cleared once the summary is handed out")
        expect(log.finish(unlocked: true, at: 180, reality: reality()) == .nothing, "a second finish never replays")

        // 只列现在仍成立的事
        log.begin(at: 100)
        log.noteWindowChange(id: 1, app: "终端", at: 120)
        log.noteLowBattery(deviceID: "m", name: "妙控鼠标", part: nil, percent: 8, at: 130)
        expect(log.finish(unlocked: true, at: 170, reality: reality(windows: false, devices: false)) == .nothing,
               "a window that was put back and a device that recovered are not listed")
        expect(log.isEmpty && !log.isAway, "an empty finish still clears the log")

        // 上限：账本不会越记越长
        log.begin(at: 0)
        for i in 0..<100 { log.noteWindowChange(id: UInt32(i), app: "A\(i)", at: Double(i)) }
        for i in 0..<100 { log.noteDownloads(["f\(i)"], at: Double(i)) }
        if case .summary(let summary) = log.finish(unlocked: true, at: 200, reality: reality()) {
            expect(summary.count <= AwayLog.capacity + 1, "a flood of events stays bounded")
        } else { expect(false, "a flood of events still gives a summary") }

        // 区间终点早于起点（时钟回拨）不崩，按起点算
        log.begin(at: 500)
        log.noteDownloads(["a.zip"], at: 500)
        if case .summary = log.finish(unlocked: true, at: 400, reality: reality()) { expect(true, "a clock step back still reports the start instant") }
        else { expect(false, "a clock step back still reports the start instant") }

        print(failures == 0 ? "all passed" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
