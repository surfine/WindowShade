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

        // 每个格子各点各的（稿对照账 1、3、4、5）
        let url1 = URL(fileURLWithPath: "/tmp/Downloads/a.zip")
        let url2 = URL(fileURLWithPath: "/tmp/Downloads/b.zip")
        let mixed = S.build(
            intrusions: [.init(text: "被解锁了一次", at: 150)],
            devices: [.init(deviceID: "m", name: "妙控鼠标", part: nil, percent: 18, at: 150)],
            windows: [.init(id: 7, app: "终端", at: 150)],
            downloads: [.init(name: "a.zip", at: 150, url: url1)], tuckedCount: 0, interval: span)!
        func probe(_ w: @escaping (UInt32) -> S.Whereabouts = { _ in .inRow }, files: Set<URL> = [url1, url2]) -> S.Probe {
            S.Probe(whereabouts: w, fileExists: { files.contains($0) })
        }
        let states = mixed.items.map { $0.state(probe()) }
        expect(states == [.informational, .actionable(.openBluetoothSettings), .actionable(.backToPlace(7)), .actionable(.revealFile(url1))],
               "each item carries its own action: nothing, Bluetooth, back to place, reveal in Finder")
        expect(mixed.items[2].state(probe({ _ in .otherDesktop })) == .actionable(.goThere(7)), "a window on another desktop is 'go there'")
        expect(mixed.items[2].state(probe({ _ in .gone })) == .gone, "a window that is gone is gray")
        expect(mixed.items[3].state(probe(files: [])) == .gone, "a download whose file is gone is gray")
        let two = S.build(downloads: [.init(name: "a.zip", at: 150, url: url1), .init(name: "b.zip", at: 140, url: url2)], tuckedCount: 0, interval: span)!
        expect(two.items[0].state(probe()) == .actionable(.openDownloadsFolder), "several files open the Downloads folder")
        expect(two.items[0].state(probe(files: [url2])) == .actionable(.openDownloadsFolder), "several files with one left still open the folder")
        let noURL = S.build(downloads: [.init(name: "a.zip", at: 150)], tuckedCount: 0, interval: span)!
        expect(noURL.items[0].state(probe(files: [])) == .actionable(.openDownloadsFolder), "an unknown location falls back to the folder")
        if case .device(_, let name, _, let percent) = mixed.items[1].content { expect(name == "妙控鼠标" && percent == 18, "device content is structured") }
        else { expect(false, "device content is structured") }
        expect(S.TapAction.backToPlace(1).leavesRow == false && S.TapAction.goThere(1).leavesRow
               && S.TapAction.openBluetoothSettings.leavesRow && S.TapAction.openDownloadsFolder.leavesRow, "only back-to-place stays")

        // 列表寿命、还有 N 件、去重、再问一次现状
        var list = AwayList(mixed)!
        expect(list.cells.count == 4 && list.windowIDs == [7] && !list.showsOmittedCell, "list is fixed from the summary; windows exposed for dedupe")
        let big = S.build(intrusions: [.init(text: "x", at: 150)],
                          devices: (0..<3).map { .init(deviceID: "d\($0)", name: "d\($0)", part: nil, percent: 5 + $0, at: 150) },
                          windows: [.init(id: 7, app: "终端", at: 150), .init(id: 8, app: "备忘录", at: 150)],
                          downloads: [.init(name: "a", at: 150)], tuckedCount: 0, interval: span)!
        let bigList = AwayList(big)!
        expect(big.omitted == 3 && bigList.omitted == 3 && bigList.showsOmittedCell && bigList.totalCount == 7, "the narrow cell counts only the omitted items")
        expect(AwayList.isAwayID(AwayList.omittedID) && !AwayList.isAwayID(0xF000_0001) && !AwayList.isAwayID(77), "away ids do not collide")
        var expiring = AwayList(mixed)!
        expect(expiring.alertEnded() && expiring.isEmpty, "the alert ending before it was opened clears the list")
        var opened = AwayList(mixed)!
        opened.rowOpened()
        expect(!opened.alertEnded() && !opened.isEmpty, "opening the row stops the timer")
        opened.rowClosed()
        expect(opened.isEmpty, "closing the row clears the list")
        let backID = list.cells[2].id
        expect(list.tap(backID, probe: probe()) == .perform(.backToPlace(7)) && list.cells.count == 3 && list.windowIDs.isEmpty,
               "back to place removes only that cell")
        expect(list.tap(backID, probe: probe()) == .refused, "a removed cell cannot be tapped again")
        expect(list.tap(list.cells[0].id, probe: probe()) == .refused && list.cells.count == 3, "an informational cell does nothing")
        var again = AwayList(mixed)!
        let before = again.states(probe())[again.cells[2].id]
        expect(before == .actionable(.backToPlace(7)), "the row asks when it opens")
        expect(again.tap(again.cells[2].id, probe: probe({ _ in .gone })) == .refused && again.cells.count == 4,
               "the second asking wins: a window gone by the tap does nothing")
        expect(again.states(probe({ _ in .gone }))[again.cells[2].id] == .gone, "and the cell shows gray")
        expect(again.tap(again.cells[1].id, probe: probe()) == .perform(.openBluetoothSettings) && again.isEmpty,
               "a leaving action clears the whole list")
        var last = AwayList(S.build(windows: [.init(id: 7, app: "终端", at: 150)], tuckedCount: 0, interval: span)!)!
        _ = last.tap(last.cells[0].id, probe: probe())
        expect(last.isEmpty && !last.showsOmittedCell, "the last cell leaving empties the list")
        expect(AwayList(S.Summary(items: [], omitted: 0, tuckedCount: 2)) == nil, "no items, no list")

        print(failures == 0 ? "all passed" : "\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
