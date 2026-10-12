import Foundation
import Synchronization

// M11：窗口和会话合成一排。纯逻辑：分段与坐标、焦点跨过竖线、读屏句子、主人合并以后的租约行为。
// 画面（NotchTileView、竖线、转圈）在 AppKit 那一层，由整模块检查和真机验收看。

final class RowClock: WS2Clock {
    private let instant = Mutex<WS2.Instant>(.init(nanoseconds: 100))
    func now() -> WS2.Instant { instant.withLock { $0 } }
}

@main
struct NotchRowMergeTests {
    @MainActor static func main() {
        var t = TestSuite("M11")
        typealias Cell = NotchFocusController.Cell
        let cell = NotchRow.cellWidth, gap = NotchRow.cellGap, pitch = NotchRow.pitch

        // MARK: 分段与坐标

        t.section("M11-01", "只有窗口：没有竖线，坐标和原来一样")
        let windowsOnly = NotchRow.layout(windows: 3, ongoing: 0)
        t.expect(!windowsOnly.hasDivider && windowsOnly.dividerX == nil, "没有正在进行的事就没有竖线")
        t.expect(windowsOnly.contentWidth == 3 * pitch - gap, "三格：3×132−8")
        t.expect(windowsOnly.x(ofCell: 0) == 0 && windowsOnly.x(ofCell: 2) == 2 * pitch, "格子之间还是 132")
        t.expect(windowsOnly.islandWidth(minimum: 0) == 3 * pitch + 20, "岛宽是 n×132+20，两边边距 14")
        t.expect(NotchRow.layout(windows: 0, ongoing: 0).islandWidth(minimum: 232) == 232, "一格都没有：用最小宽度")
        t.expect(windowsOnly.dividerFrame(inRowWidth: 400, cellsMinY: 14, cellsHeight: 100) == nil, "没有竖线就没有外框")

        t.section("M11-02", "窗口在左、竖线、正在进行的在右")
        let both = NotchRow.layout(windows: 2, ongoing: 2)
        t.expect(both.hasDivider && both.count == 4, "两段都有格子才有竖线")
        t.expect(both.dividerX == 2 * pitch, "竖线在最后一个窗口格右边的间隙里：窗口右边缘 + 8")
        t.expect(both.x(ofCell: 1) == pitch, "左段格子位置不变")
        t.expect(both.x(ofCell: 2) == 2 * pitch + 1 + gap, "右段第一格：竖线 1pt 之后再空 8")
        t.expect(both.x(ofCell: 3) == 3 * pitch + 1 + gap, "右段第二格接着排")
        t.expect(both.contentWidth == 4 * pitch - gap + (1 + gap), "内容宽度比没有竖线多 1+8")
        t.expect(both.islandWidth(minimum: 0) == both.contentWidth + 28, "岛宽 = 内容 + 两边各 14")
        let line = both.dividerFrame(inRowWidth: 600, cellsMinY: 14, cellsHeight: 100)
        t.expect(line?.width == 1 && line?.y == 24 && line?.height == 80, "竖线 1pt 宽，上下各留 10pt")
        t.expect(line?.x == (600 - both.contentWidth) / 2 + 2 * pitch, "竖线跟着整排居中")
        t.expect(abs((line?.x ?? 0) - (both.leading(inRowWidth: 600) + both.x(ofCell: 1) + cell + gap)) < 0.001,
                 "竖线正好在左段最后一格右边 8pt")
        t.expect(NotchRow.dividerWhite == 0.2 && NotchRow.dividerInset == 10, "白 0.2、上下各留 10")
        t.expect(NotchRow.outerRadius - NotchRow.edgeMargin == NotchRow.cellRadius, "外框 28 − 边距 14 = 格子 14：同心不变")

        t.section("M11-03", "只有右段：没有竖线")
        let rightOnly = NotchRow.layout(windows: 0, ongoing: 2)
        t.expect(!rightOnly.hasDivider && rightOnly.x(ofCell: 1) == pitch, "没有窗口时右段从头排，不留竖线的位置")

        t.section("M11-04", "放不下就裁：窗口最多 8、正在进行的最多 3，右段至多一半")
        let room = 1000.0
        t.expect(NotchRow.capacity(room: room, divider: false) == 7 && NotchRow.capacity(room: room, divider: true) == 7,
                 "1000 宽放 7 格（竖线多占的 9 点这里没有挤掉一格）")
        t.expect(NotchRow.capacity(room: 1056, divider: false) == 8 && NotchRow.capacity(room: 1056, divider: true) == 7,
                 "有竖线时要扣掉它多占的 9 点")
        t.expect(NotchRow.capacity(room: 10, divider: false) == 1, "再窄也至少一格（原来的 max(1, …)）")
        t.expect(NotchRow.fit(windows: 20, ongoing: 0, room: 2000) == NotchRow.Layout(windows: 8, ongoing: 0), "只有窗口：最多 8 格")
        t.expect(NotchRow.fit(windows: 5, ongoing: 0, room: 400) == NotchRow.Layout(windows: 3, ongoing: 0), "窄屏：按屏宽少放几格，沿用原来的算法")
        t.expect(NotchRow.fit(windows: 0, ongoing: 9, room: 2000) == NotchRow.Layout(windows: 0, ongoing: 3), "只有右段：最多 3 格")
        t.expect(NotchRow.fit(windows: 3, ongoing: 2, room: 2000) == NotchRow.Layout(windows: 3, ongoing: 2), "放得下就都放")
        t.expect(NotchRow.fit(windows: 8, ongoing: 3, room: 2000) == NotchRow.Layout(windows: 8, ongoing: 3), "8+3 都放（宽屏）")
        t.expect(NotchRow.fit(windows: 8, ongoing: 3, room: 1000) == NotchRow.Layout(windows: 4, ongoing: 3), "1000 宽：右段 3 格，窗口让出剩下的 4 格")
        t.expect(NotchRow.fit(windows: 8, ongoing: 3, room: 600) == NotchRow.Layout(windows: 2, ongoing: 2), "600 宽：共 4 格，右段至多一半")
        t.expect(NotchRow.fit(windows: 8, ongoing: 3, room: 300) == NotchRow.Layout(windows: 1, ongoing: 1), "两格：各一格")
        t.expect(NotchRow.fit(windows: 8, ongoing: 3, room: 140) == NotchRow.Layout(windows: 1, ongoing: 0), "连两格都放不下：只留窗口，没有竖线")
        t.expect(NotchRow.fit(windows: 1, ongoing: 1, room: 300) == NotchRow.Layout(windows: 1, ongoing: 1), "1+1")
        t.expect(NotchRow.fit(windows: 0, ongoing: 0, room: 300) == NotchRow.Layout(windows: 0, ongoing: 0), "空的一排")
        for w in 0...9 {
            for o in 0...4 {
                for room in stride(from: 100.0, through: 1500.0, by: 100.0) {
                    let fit = NotchRow.fit(windows: w, ongoing: o, room: room)
                    // 原来的算法：n×132 ≤ 屏宽−44 就放得下（岛宽 n×132+20 超出的 20 点是两边的边距，岛本身再按屏宽夹住）；至少一格。
                    let fits = fit.count <= 1 || fit.islandWidth(minimum: 0) <= room + 20
                    t.expect(fit.windows <= w && fit.ongoing <= o && fit.count <= max(1, NotchRow.capacity(room: room, divider: fit.hasDivider)) && fits,
                             "组合 \(w)+\(o) 宽 \(Int(room))：不超数量、不超宽度")
                }
            }
        }

        // MARK: 格子编号

        t.section("M11-05", "格子编号：同一个活动一直是同一个号，和窗口号不撞")
        var ids = NotchRow.IDMap()
        let a = ids.id(for: "ws2.session"), b = ids.id(for: "source.music")
        t.expect(a != nil && b != nil && a != b, "不同活动不同号")
        t.expect(ids.id(for: "ws2.session") == a, "同一个活动再问还是同一个号")
        t.expect(a.map(NotchRow.isOngoingID) == true && !NotchRow.isOngoingID(4_000_000), "号在高位，窗口号都不是")
        t.expect(a.flatMap { ids.activityID(for: $0) } == "ws2.session" && ids.activityID(for: 7) == nil, "能反查回活动 id")
        for n in 0..<80 { _ = ids.id(for: "x\(n)") }
        t.expect(ids.id(for: "overflow") == nil && ids.id(for: "ws2.session") == a, "登记有上限；已登记的不受影响")

        // MARK: 右段放什么

        t.section("M11-06", "右段：正在播放的、编程会话，耳朵上的符号不进来")
        func activity(_ id: String, _ kind: NotchActivityKind, title: String = "T", subtitle: String = "", phase: NotchSessionPhase? = nil,
                      paused: Bool = false, trailing: String? = nil) -> NotchActivity {
            NotchActivity(id: id, kind: kind, title: title, subtitle: subtitle, symbol: kind == .session ? "terminal" : "music.note",
                          startedAt: 1, isPaused: paused, trailing: trailing, sessionPhase: phase)
        }
        let visible = [
            activity("ws2.session", .session, title: "WindowShade", subtitle: "Claude Code在跑", phase: .running),
            activity("ws2.remote", .remote), activity("source.airPods", .airPods),
            activity("source.music", .music, title: "September", subtitle: "Earth, Wind & Fire"),
            activity("ws2.focus", .focus, title: "专注", subtitle: "今天第 2 个", trailing: "18 分"),
            activity("source.download", .download, title: "正在下载", subtitle: "1 个文件"),
        ]
        let cells = NotchRow.ongoingCells(from: visible)
        t.expect(cells.map(\.activityID) == ["ws2.session", "source.music", "ws2.focus"], "遥控器、耳机不进右段；按原来的顺序，最多 3 格")
        t.expect(cells[2].title == "专注 · 18 分", "番茄钟的格子主句把剩余时间合进去")
        t.expect(cells[1].action == .nowPlayingOpen && cells[1].closesRow, "音乐：点格子长成正在播放大卡（NP-4），这一排收起")
        t.expect(cells[1].accessory == .playPause && cells[0].accessory == nil && cells[2].accessory == nil,
                 "只有音乐格右下角留播放 / 暂停键；点它不收这一排")
        t.expect(NotchRow.OngoingCell.accessorySide == 24, "那个小键 24 点")
        t.expect(cells[0].action == .open && cells[0].closesRow && cells[2].action == .open, "会话和其它：点一下“过去 / 打开”，这一排收起")
        t.expect(NotchRow.ongoingCells(from: []).isEmpty, "没有正在进行的事：右段是空的，也就没有竖线")
        t.expect(NotchRow.ongoingCells(from: [activity("ws2.remote", .remote)]).isEmpty, "只有遥控器连着：右段也是空的")
        t.expect(NotchRow.ongoingCells(from: [activity("m", .music, subtitle: "A", paused: true)])[0].subtitle == "已暂停", "音乐暂停时副句写“已暂停”")

        t.section("M11-07", "读屏：竖线不念；会话格念“项目，在等你”")
        func session(_ title: String, _ phase: NotchSessionPhase?, subtitle: String = "") -> NotchRow.OngoingCell {
            NotchRow.OngoingCell(activityID: "s", kind: .session, title: title, subtitle: subtitle, symbol: "terminal", phase: phase, isPaused: false)
        }
        t.expect(session("WindowShade", .waiting).spoken == "WindowShade，在等你", "在等你")
        t.expect(session("WindowShade", .running).spoken == "WindowShade，在跑", "在跑")
        var quota = session("WindowShade", .quota)
        t.expect(quota.spoken == "WindowShade，在跑", "没有右耳字：只念在跑")
        quota.earText = "剩 42%"
        t.expect(quota.spoken == "WindowShade，在跑，剩 42%", "有额度：念出剩多少")
        t.expect(quota.quantityText == "剩 42%" && quota.quantity.drawing == .none, "展开额度写剩余数字，不混成下载进度环")
        var lowQuota = session("WindowShade", .quotaLow); lowQuota.earText = "剩 5%"
        t.expect(lowQuota.quantityText == "剩 5%", "低额也把真实数字交给绘制与读屏")
        let projectedLow = NotchRow.ongoingCells(from: [NotchActivity(id:"q",kind:.session,title:"WindowShade",symbol:"terminal",startedAt:0,trailing:"剩 5%",sessionPhase:.quotaLow)])[0]
        t.expect(projectedLow.quantityText == "剩 5%", "实际Activity→Core投影也保低额耳字，不能只测手写cell")
        lowQuota.earText = "剩 4%"
        t.expect(lowQuota.quantityText == "剩 4%", "相同低额相位数字仍更新")
        var waitingQuota = session("WindowShade", .waiting); waitingQuota.earText = "剩 4%"
        t.expect(waitingQuota.quantityText == nil, "等你时额度数字退让")
        t.expect(session("完成", .done, subtitle: "改了 3 个文件").spoken == "完成，改了 3 个文件", "做完了")
        t.expect(session("WindowShade", nil).spoken == "WindowShade", "不知道状态：只念名字")
        let long = String(repeating: "很长的项目名", count: 8)
        let longSpoken = session(long, .waiting).spoken
        t.expect(longSpoken.hasSuffix("，在等你") && longSpoken.contains("…"), "项目名太长只截项目名，状态一直念全")
        t.expect(session("", .waiting).spoken == "在等你", "没有项目名也不念出空逗号")
        let music = NotchRow.OngoingCell(activityID: "m", kind: .music, title: "September", subtitle: "", symbol: "music.note", phase: nil, isPaused: false)
        t.expect(music.spoken == "September，正在播放", "音乐：正在播放")
        t.expect(NotchRow.OngoingCell(activityID: "m", kind: .music, title: "September", subtitle: "已暂停", symbol: "", phase: nil, isPaused: true).spoken
                 == "September，已暂停", "音乐：已暂停")
        let download = NotchRow.OngoingCell(activityID: "d", kind: .download, title: "正在下载", subtitle: "1 个文件", symbol: "", phase: nil, isPaused: false)
        t.expect(download.spoken == "正在下载，1 个文件", "其它：标题加副句")

        // MARK: 焦点跨过竖线

        func window(_ id: UInt32, _ title: String = "窗口", tucked: Bool = false) -> Cell { Cell(id: id, title: title, tucked: tucked) }
        func sessionCell(_ id: UInt32, _ spoken: String, waiting: Bool = false) -> Cell {
            Cell(id: id, title: "WindowShade", waiting: waiting, ongoing: true, session: true, spoken: spoken)
        }
        func playing(_ id: UInt32) -> Cell { Cell(id: id, title: "September", ongoing: true, spoken: "September，正在播放") }
        let r0 = NotchRow.ongoingIDBase, r1 = NotchRow.ongoingIDBase + 1
        func started(_ cells: [Cell], pointerInside: Bool = false) -> NotchFocusController {
            var c = NotchFocusController()
            c.setCells(cells)
            if pointerInside { c.pointerEntered() }
            _ = c.handle(.notchShelf)
            return c
        }

        t.section("M11-08", "同一页、同一套索引：焦点向右跨过竖线，再向左回来")
        var c = started([window(1, "访达", tucked: true), window(2, "备忘录", tucked: true), sessionCell(r0, "WindowShade，在跑"), playing(r1)])
        t.expect(c.focusedID == 1 && !c.focusIsOnSession, "没有人在等：落在最近收进去的窗口")
        t.expect(c.handle(.focusRight) == .moved(id: 2, announcement: "备忘录，第 2 个，共 4 个"), "窗口之间照常挪")
        t.expect(c.handle(.focusRight) == .moved(id: r0, announcement: "WindowShade，在跑，第 3 个，共 4 个"), "越过竖线到会话格，念整句")
        t.expect(c.focusIsOnSession && c.focusedCell?.session == true, "焦点在会话格上")
        t.expect(c.handle(.focusRight) == .moved(id: r1, announcement: "September，正在播放，第 4 个，共 4 个"), "右段里继续往右")
        t.expect(!c.focusIsOnSession, "挪到播放格：不再是会话格")
        if case .bump(let direction, _) = c.handle(.focusRight) { t.expect(direction == .right && c.focusedID == r1, "最右一格到头：顶一下，不绕回") }
        else { t.expect(false, "最右一格往右应该是 bump") }
        t.expect(c.handle(.focusLeft) == .moved(id: r0, announcement: "WindowShade，在跑，第 3 个，共 4 个"), "往左回到会话格")
        t.expect(c.handle(.focusLeft) == .moved(id: 2, announcement: "备忘录，第 2 个，共 4 个"), "再往左越过竖线回到窗口")
        t.expect(c.handle(.activateFocused) == .activate(id: 2), "Return 打开亮着的那一格（窗口）")

        t.section("M11-09", "默认落点：有会话在等你，焦点先落在它上面")
        var waiting = started([window(1, tucked: true), window(2, tucked: true), sessionCell(r0, "WindowShade，在等你", waiting: true), playing(r1)])
        t.expect(waiting.focusedID == r0 && waiting.focusIsOnSession, "等你的会话格就是默认焦点")
        t.expect(waiting.handle(.activateFocused) == .activate(id: r0), "Return 激活会话格（“过去”）")
        let noWindows = started([sessionCell(r0, "WindowShade，在等你", waiting: true)])
        t.expect(noWindows.focusedID == r0, "一扇窗口都没有、只有会话格：照样能开始")
        let hidden = started([window(1), sessionCell(r0, "WindowShade，在等你", waiting: true)], pointerInside: true)
        t.expect(hidden.visibleFocusID == nil && hidden.focusIsOnSession, "指针在刘海里：焦点藏起来，但它还在会话格上（遥控器要知道）")
        var openAnnounce = NotchFocusController()
        openAnnounce.setCells([window(1), sessionCell(r0, "WindowShade，在等你", waiting: true)])
        t.expect(openAnnounce.handle(.notchShelf) == .begin(announcement: "刘海那一排，2 项"), "开始时念“刘海那一排，n 项”（窗口加会话一起数）")

        t.section("M11-10", "那一排重排：会话格没了，焦点重选；会话格还在，焦点留着")
        var re = started([window(1), sessionCell(r0, "WindowShade，在等你", waiting: true)])
        t.expect(re.focusIsOnSession, "起点在会话格")
        re.setCells([window(1), sessionCell(r0, "WindowShade，在跑")])
        t.expect(re.focusedID == r0 && re.focusIsOnSession, "会话格还在：焦点留着")
        re.setCells([window(1)])
        t.expect(re.focusedID == 1 && !re.focusIsOnSession, "会话格没了：回到窗口")
        re.shelfClosed()
        t.expect(!re.focusIsOnSession, "那一排收起：不再算在会话格上")

        t.section("M11-11", "格子在一页里的坐标：右段比左段多空出竖线那一格（只影响方向判断）")
        t.expect(NotchRow.dividerExtra == 9, "竖线多占 1+8")

        // MARK: 主人合并

        let display = WS2.DisplayID(value: 1)
        func request(_ owner: String, _ layer: WS2.Layer = .opened) -> WS2.LeaseRequest {
            .init(ownerID: owner, display: display, layer: layer, requestedAt: .init(nanoseconds: 100),
                  deadline: .init(nanoseconds: 1_000_000), containsPrivateContent: true)
        }
        func lease(_ decision: WS2.LeaseDecision) -> WS2.LeaseHandle? { if case .acquired(let h) = decision { return h }; return nil }
        func isBusy(_ decision: WS2.LeaseDecision) -> Bool { if case .busy = decision { return true }; return false }
        func isUnavailable(_ decision: WS2.LeaseDecision) -> Bool { if case .unavailable = decision { return true }; return false }
        func makeCoordinator(_ onCancel: @escaping (WS2.LeaseHandle, WS2.LeaseRevocation) -> Void = { _, _ in }) -> InteractionCoordinator {
            InteractionCoordinator(bootID: UUID(), clock: RowClock(), environment: { .init(unlocked: true, displays: [display]) }, cancel: onCancel)
        }

        t.section("M11-12", "agentSessions 不再是主人：会话的详情页用 notchShelf 露面")
        t.expect(isUnavailable(makeCoordinator().acquire(request("agentSessions"))), "表里没有 agentSessions 这个主人了")
        t.expect(lease(makeCoordinator().acquire(request("notchShelf"))) != nil, "那一排和会话详情页共用的主人拿得到")

        t.section("M11-13", "同一个主人：一块屏上只有一份展示权，详情页要显式换页")
        var cancelled: [(WS2.LeaseHandle, WS2.LeaseRevocation)] = []
        let c1 = makeCoordinator { cancelled.append(($0, $1)) }
        let shelf = lease(c1.acquire(request("notchShelf")))
        t.expect(shelf != nil && isBusy(c1.acquire(request("notchShelf"))), "没有显式换页：详情页不能顶掉那一排")
        let detail = shelf.flatMap { lease(c1.acquire(request("notchShelf"), replacing: $0)) }
        t.expect(detail != nil && shelf.map { !c1.isCurrent($0) } == true && detail.map(c1.isCurrent) == true, "显式换页：详情页接手，旧的一份作废")
        t.expect(cancelled.count == 1 && cancelled[0].1 == .preempted, "旧的一份只被撤销一次，原因是被换页")
        if let detail { c1.release(detail, at: .init(nanoseconds: 200)) }
        t.expect(c1.snapshots(at: .init(nanoseconds: 300)).first?.layer == .idle, "详情页关掉以后这块屏回到空闲")

        t.section("M11-14", "放行仍然比这一排高：详情页被挂起，让出后另拿一份")
        var reasons: [WS2.LeaseRevocation] = []
        let c2 = makeCoordinator { _, reason in reasons.append(reason) }
        let page = lease(c2.acquire(request("notchShelf")))
        let review = lease(c2.acquire(request("agentReview", .authorization)))
        t.expect(review != nil && page.map { !c2.isCurrent($0) } == true && reasons == [.suspended], "放行进来：那一排（或详情页）被挂起")
        if let review { c2.release(review, at: .init(nanoseconds: 100)) }
        let again = lease(c2.acquire(request("notchShelf")))
        t.expect(again != nil && again != page, "让出后另拿一份，旧租约不复活")

        t.section("M11-15", "别的主人仍然不能顶掉这一排，也不能被它顶掉")
        let c3 = makeCoordinator()
        _ = lease(c3.acquire(request("notchShelf")))
        t.expect(isBusy(c3.acquire(request("launchpad"))) && isBusy(c3.acquire(request("pomodoro"))), "同层的别的主人拿不到")
        t.expect(isBusy(c3.acquire(request("conductor", .opened))), "指挥模式的页面同样排队等")

        t.section("M11-16", "合成一排开关：默认开；键为 nil、显式开、显式关三种读值；两个方向的重排判定")
        t.expect(!NotchMergedRowPreference.defaultEnabled && NotchMergedRowPreference.defaultsKey == "Notch.mergedRow", "1.0.16 真机验过前默认关（设计上默认开），键名固定")
        for (stored, expected, label) in [(nil, false, "键为 nil"), (true, true, "显式开"), (false, false, "显式关")] as [(Bool?, Bool, String)] {
            let suite = "NotchRowMergeTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            if let stored { defaults.set(stored, forKey: NotchMergedRowPreference.defaultsKey) }
            t.expect(NotchMergedRowPreference.isEnabled(in: defaults) == expected, "读值：\(label) → \(expected)")
            defaults.removePersistentDomain(forName: suite)
        }
        t.expect(NotchMergedRowPreference.needsReflow(isExpanded: true, currentlyMerged: false, enabled: true), "展开着、关→开：重排")
        t.expect(NotchMergedRowPreference.needsReflow(isExpanded: true, currentlyMerged: true, enabled: false), "展开着、开→关：重排")
        t.expect(!NotchMergedRowPreference.needsReflow(isExpanded: true, currentlyMerged: true, enabled: true), "样子已经对了：不动")
        t.expect(!NotchMergedRowPreference.needsReflow(isExpanded: false, currentlyMerged: false, enabled: true), "收着的：下次展开自然生效")

        t.finish()
    }
}
