// LA56：实时活动统一的样子与生命周期（《实时活动晋级》三、工作包 LA-5 / LA-6）。
// 排序键、1.5 秒门槛、过期沉底、结束留 4 秒与那一排留到看过、两件同时在的耳朵分配、文件架不占位。
// 纯 Foundation，只通过公开 API 观察；时间全由测试给。

import Foundation

@main @MainActor
struct NotchActivityLifecycleTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if !condition { failures += 1; print("FAIL \(message)") }
    }

    static func item(_ id: String, _ kind: NotchActivityKind, at start: Double = 0, updated: Double? = nil,
                     relevance: Int = 0, staleAt: Double? = nil, appearAfter: Double = 0,
                     closing: NotchActivity.Closing = .standard, finalLook: NotchActivity.FinalLook? = nil,
                     generation: UInt64 = 1, progress: NotchActivity.Quantity = .unknown, title: String? = nil) -> NotchActivity {
        NotchActivity(id: id, generation: generation, kind: kind, title: title ?? id, startedAt: start, updatedAt: updated,
                      progress: progress, relevance: relevance, staleAt: staleAt, appearAfter: appearAfter,
                      closing: closing, finalLook: finalLook)
    }

    static func main() {
        sortKey()
        appearGate()
        staleSinks()
        endLingersFourSeconds()
        closingKinds()
        earAllocation()
        shelfDoesNotTakeASlot()
        lifecycleTable()
        sessionStaleness()
        if failures > 0 { print("\(failures) 处失败"); exit(1) }
        print("PASS notch activity lifecycle (LA56)")
    }

    // 排序键：新鲜 > 权重 > 同类相关度 > 最近更新。
    static func sortKey() {
        var store = NotchActivityStore()
        _ = store.upsert(item("s1", .session, at: 1), now: 1)
        _ = store.upsert(item("s2", .session, at: 2, relevance: 4), now: 2)
        _ = store.upsert(item("m", .music, at: 3, relevance: 4), now: 3)
        _ = store.upsert(item("d", .download, at: 4), now: 4)
        expect(store.activities.map(\.id) == ["s2", "s1", "d", "m"], "相关度只在同类里分先后，音乐跨不过下载：\(store.activities.map(\.id))")
        expect(NotchActivity(id: "x", kind: .music, title: "t", startedAt: 0, relevance: 9).relevance == 4, "相关度夹在 0–4")
        expect(NotchActivity(id: "x", kind: .music, title: "t", startedAt: 0, relevance: -2).relevance == 0, "相关度夹在 0–4")
        // 同类同相关度：最近更新的在前。
        _ = store.upsert(item("s1", .session, at: 1, updated: 6, relevance: 4), now: 6)
        expect(store.activities.prefix(2).map(\.id) == ["s1", "s2"], "同类同相关度，最近更新的在前")
    }

    // 开始后 1.5 秒内就结束的不出现。
    static func appearGate() {
        var store = NotchActivityStore()
        let gate = NotchActivityKind.copy.appearAfter
        expect(gate == 1.5 && NotchActivityKind.download.appearAfter == 1.5, "下载、拷贝 1.5 秒门槛")
        _ = store.upsert(item("quick", .copy, at: 10, appearAfter: gate), now: 10)
        expect(store.visible.isEmpty && store.activities.count == 1, "门槛里不露面，但 store 里有")
        expect(!store.select(id: "quick"), "门槛里不能选中")
        expect(store.nextTransition == 11.5, "到 11.5 醒一次：\(String(describing: store.nextTransition))")
        expect(store.end(id: "quick", generation: 1, now: 11), "1 秒的拷贝结束")
        expect(store.activities.isEmpty && store.visible.isEmpty, "1 秒的拷贝从不出现，也不留最后的样子")
        store.prune(now: 20)
        expect(store.rowActivities.isEmpty, "那一排里也没有")

        _ = store.upsert(item("slow", .copy, at: 20, appearAfter: gate), now: 20)
        store.prune(now: 21.4)
        expect(store.visible.isEmpty, "1.4 秒还不露面")
        store.prune(now: 21.5)
        expect(store.visible.map(\.id) == ["slow"], "1.5 秒后出现")
        expect(NotchActivity(id: "x", kind: .copy, title: "t", startedAt: 0, appearAfter: .infinity).appearAfter == 0, "非有限门槛当 0")
    }

    // 过期：内容降级、右耳“—”、读屏“可能已停”，并沉到所有新鲜的后面。
    static func staleSinks() {
        var store = NotchActivityStore()
        _ = store.upsert(item("s", .session, at: 0, staleAt: 120), now: 0)
        _ = store.upsert(item("m", .music, at: 1), now: 1)
        store.followFirst()
        expect(store.activities.map(\.id) == ["s", "m"] && store.selectedID == "s", "新鲜时会话在前，耳朵给会话")
        expect(store.nextTransition == 120, "到过期那一刻醒一次")
        store.prune(now: 119.9)
        expect(!(store.activities.first?.isStale ?? true), "没到点不过期")
        store.prune(now: 120)
        let ordered = store.activities
        expect(ordered.map(\.id) == ["m", "s"], "过期的会话排在新鲜的音乐后面：\(ordered.map(\.id))")
        expect(ordered.last?.isStale == true, "store 按自己的时钟填过期")
        store.followFirst()
        expect(store.selectedID == "m", "过期的让出耳朵")
        expect(store.nextTransition == nil, "过期了不再排醒来的时刻")
        guard let stale = ordered.last else { return }
        expect(NotchEarText.trailing(stale) == "—", "右耳写“—”")
        var withTrailing = stale; withTrailing.trailing = "剩 40%"
        expect(NotchEarText.trailing(withTrailing) == "—", "来源给的字也不写，不补数")
        expect(NotchMinimalPresentation.label(for: stale) == "正在进行：s，可能已停", "最小形读屏")
        expect(NotchActivity.staleAlpha == 0.5, "内容 0.5 透明")
        let cells = NotchRow.ongoingCells(from: ordered)
        expect(cells.last?.isStale == true && cells.last?.spoken.hasSuffix("可能已停") == true, "那一格读屏加“可能已停”：\(cells.last?.spoken ?? "")")
        // 来了新消息就回到新鲜。
        _ = store.upsert(item("s", .session, at: 0, updated: 130, staleAt: 250), now: 130)
        expect(store.activities.first?.id == "s" && store.activities.first?.isStale == false, "新消息回到新鲜，排回前面")
    }

    // 结束：最后的样子留 4 秒；那一排里留到看过，或 15 分钟。
    static func endLingersFourSeconds() {
        var store = NotchActivityStore()
        let look = NotchActivity.FinalLook(title: "下载好了", symbol: "checkmark.circle.fill")
        _ = store.upsert(item("d", .download, at: 0, staleAt: 30, finalLook: look, progress: .fraction(0.9)), now: 0)
        store.followFirst()
        expect(store.end(id: "d", generation: 1, now: 10), "结束")
        guard let last = store.visible.first else { return expect(false, "结束后还在耳朵上") }
        expect(last.isEnded && last.title == "下载好了" && last.symbol == "checkmark.circle.fill", "换上最后的样子")
        expect(last.progress == .unknown && !last.isStale, "最后的样子不画量、不变暗")
        expect(store.selectedID == "d" && store.live(id: "d") == nil, "还在耳朵上；但不算还在跑")
        expect(!store.end(id: "d", generation: 1, now: 11), "不能结束两次")
        expect(!store.upsert(item("d", .download, at: 0, updated: 11), now: 11), "同一代不复活")
        expect(store.nextTransition == 14, "4 秒后醒一次：\(String(describing: store.nextTransition))")
        store.prune(now: 13.9)
        expect(store.visible.map(\.id) == ["d"], "3.9 秒时还在")
        store.prune(now: 14)
        expect(store.visible.isEmpty && store.selectedID == nil, "4 秒后离开耳朵")
        expect(store.rowActivities.map(\.id) == ["d"], "那一排里还留着")
        expect(store.nextTransition == 10 + NotchActivityStore.rowKeepLimit, "那一排留到 15 分钟")
        store.rowSeen()
        expect(store.rowActivities.isEmpty, "看过一次就走")

        // 没人看：15 分钟后自己走。
        _ = store.upsert(item("c", .copy, at: 20), now: 20)
        _ = store.end(id: "c", generation: 1, now: 30)
        store.prune(now: 34)
        store.prune(now: 30 + 899)
        expect(store.rowActivities.map(\.id) == ["c"], "15 分钟内还在那一排")
        store.prune(now: 30 + 900)
        expect(store.rowActivities.isEmpty && store.nextTransition == nil, "15 分钟后走，不再排醒来")

        // 在耳朵上那 4 秒里看过那一排：离开耳朵后不再留。
        _ = store.upsert(item("e", .copy, at: 1000), now: 1000)
        _ = store.end(id: "e", generation: 1, now: 1001)
        store.rowSeen()
        store.prune(now: 1005)
        expect(store.rowActivities.isEmpty, "留在耳朵上时已经看过：之后不再留")

        // 新一代重新开始：换掉最后的样子，那一排也不再留旧的。
        _ = store.upsert(item("f", .copy, at: 2000), now: 2000)
        _ = store.end(id: "f", generation: 1, now: 2001)
        expect(store.upsert(item("f", .copy, at: 2002, generation: 2), now: 2002), "新一代可以重开")
        expect(store.live(id: "f")?.generation == 2 && store.visible.first?.isEnded == false, "新一代是活的")
    }

    // 收场方式：立即 / 留几秒 / 到点（最长 300 秒）。
    static func closingKinds() {
        expect(NotchActivity.Closing.standard == .linger(4) && NotchActivity.Closing.standard.holdSeconds == 4, "默认留 4 秒")
        expect(NotchActivity.Closing.immediate.holdSeconds == 0, "立即")
        expect(NotchActivity.Closing.deadline(120).holdSeconds == 120 && NotchActivity.Closing.deadline(900).holdSeconds == 300, "到点最长 300 秒")
        expect(NotchActivity.Closing.linger(.nan).holdSeconds == 4 && NotchActivity.Closing.deadline(-5).holdSeconds == 0, "坏数字有界")
        var store = NotchActivityStore()
        _ = store.upsert(item("m", .music, closing: .immediate), now: 0)
        _ = store.end(id: "m", generation: 1, now: 1)
        expect(store.activities.isEmpty && store.rowActivities.isEmpty, "立即：马上收，不进那一排")
        _ = store.upsert(item("cal", .calendar, at: 2, closing: .deadline(300)), now: 2)
        _ = store.end(id: "cal", generation: 1, now: 3)
        store.prune(now: 302.9)
        expect(store.visible.map(\.id) == ["cal"], "有会议链接：再留 5 分钟")
        store.prune(now: 303)
        expect(store.visible.isEmpty, "5 分钟到点收")
    }

    // 两件同时在：两耳给第一件，第二件挂最小形；人挑的留在耳朵上直到它结束。
    static func earAllocation() {
        var store = NotchActivityStore()
        _ = store.upsert(item("m", .music, at: 0, closing: .immediate), now: 0)
        store.followFirst()
        expect(store.selectedID == "m" && !store.isSelectionPinned, "只有一件：耳朵给它")
        _ = store.upsert(item("s", .session, at: 1), now: 1)
        store.followFirst()
        expect(store.selectedID == "s", "更要紧的来了，耳朵给第一件")
        let layout = NotchMinimalPresentation.layout(items: store.visible, selected: store.selectedID, enabled: true)
        expect(layout.compact?.id == "s" && layout.minimum.map(\.id) == ["m"], "第二件挂最小形")

        // 同一档里更新的先后不让耳朵来回跳。
        var tie = NotchActivityStore()
        _ = tie.upsert(item("d", .download, at: 0), now: 0)
        _ = tie.upsert(item("c", .copy, at: 0), now: 0)
        tie.followFirst()
        let ear = tie.selectedID
        _ = tie.upsert(item(ear == "d" ? "c" : "d", ear == "d" ? .copy : .download, at: 0, updated: 5), now: 5)
        tie.followFirst()
        expect(tie.selectedID == ear, "同档只是更新得更近，耳朵不换")

        // 人两指横扫选中音乐：留在耳朵上，直到它结束。
        expect(store.select(id: "m") && store.isSelectionPinned, "人挑了音乐")
        _ = store.upsert(item("r", .recording, at: 2), now: 2)
        store.followFirst()
        expect(store.selectedID == "m", "更要紧的来了也不抢人挑的")
        _ = store.end(id: "m", generation: 1, now: 3)
        store.followFirst()
        expect(store.selectedID == "s" && !store.isSelectionPinned, "人挑的结束了，耳朵回到第一件")

        // 耳朵上的那件结束：最后的样子留够 4 秒才让位。
        _ = store.end(id: "s", generation: 1, now: 4)
        store.followFirst()
        expect(store.selectedID == "s", "结束了的最后样子还在耳朵上")
        store.prune(now: 8)
        store.followFirst()
        expect(store.selectedID == "r", "4 秒后让给下一件")
    }

    // 文件架：最低（10），不当最小形，不算右段的 3 件。
    static func shelfDoesNotTakeASlot() {
        expect(NotchActivityKind.shelf.priority == 10 && NotchActivityKind.allCases.allSatisfy { $0 == .shelf || $0.priority > 10 }, "文件架权重最低")
        var store = NotchActivityStore()
        _ = store.upsert(item("shelf", .shelf), now: 0)
        store.followFirst()
        expect(store.selectedID == "shelf", "空闲时露文件架个数")
        for (n, kind) in [NotchActivityKind.session, .download, .music].enumerated() {
            _ = store.upsert(item("k\(n)", kind, at: Double(n)), now: Double(n))
        }
        _ = store.upsert(item("k3", .airPods, at: 3), now: 3)
        store.followFirst()
        expect(store.visible.map(\.id) == ["k0", "k1", "k2", "shelf"], "三件之外另挂文件架：\(store.visible.map(\.id))")
        expect(store.selectedID == "k0", "有别的事时耳朵不给文件架")
        let layout = NotchMinimalPresentation.layout(items: store.visible, selected: store.selectedID, enabled: true)
        expect(!layout.minimum.contains { $0.kind == .shelf }, "文件架不当最小形")
        expect(NotchRow.ongoingCells(from: store.visible).map(\.activityID) == ["k0", "k1", "k2"], "文件架不算右段的 3 格")
        expect(NotchActivity(id: "x", kind: .shelf, title: "t", startedAt: 0).symbol == "tray.full", "托盘符号")
    }

    // 各来源按表填过期与收场方式。
    static func lifecycleTable() {
        expect(NotchActivityKind.session.staleAfter == 120, "会话在跑 120 秒没消息过期")
        for kind in [NotchActivityKind.download, .copy, .airDrop] { expect(kind.staleAfter == 30, "\(kind) 30 秒没进展过期") }
        for kind in [NotchActivityKind.calendar, .timer, .focus, .shelf] { expect(kind.staleAfter == nil, "\(kind) 不过期") }
        for kind in [NotchActivityKind.music, .airPods, .shelf, .timer, .calendar] { expect(kind.closing == .immediate, "\(kind) 结束立即") }
        for kind in [NotchActivityKind.session, .download, .copy, .airDrop, .focus] { expect(kind.closing == .standard, "\(kind) ✓ 留 4 秒") }
        // 右耳与一格按表核对：右耳个数写短写法，那一格写全。
        let copy = item("c", .copy, progress: .count(3, 7))
        expect(NotchEarText.trailing(copy) == "3/7", "右耳“3/7”")
        expect(NotchRow.ongoingCells(from: [copy]).first?.quantityText == "第 3 / 7", "那一格“第 3 / 7”")
        expect(NotchEarText.trailing(item("d", .download, progress: .fraction(0.42))) == "42%", "右耳“42%”")
        // 结束了的那一格没有动作可按以外，读屏照常。
        var ended = item("e", .session, closing: .standard, finalLook: .init(title: "完成", sessionPhase: .done))
        ended = ended.applyingFinalLook(); ended.endedAt = 1
        let cell = NotchRow.ongoingCells(from: [ended]).first
        expect(cell?.isEnded == true && cell?.phase == .done, "结束了的那一格是最后的样子")
    }

    // 编程会话：在跑时最近一次消息 + 120 秒过期；等你不过期；做完 ✓ 留 4 秒。
    static func sessionStaleness() {
        var model = CodingSessionActivities()
        func change(_ status: CodingSessionActivities.Status) -> CodingSessionActivities.Change {
            .init(id: "s1", project: "WindowShade", cwd: "/tmp/ws", assistant: "Claude Code", status: status)
        }
        _ = model.apply(change(.running), now: 10)
        expect(model.liveSpec?.staleAt == 130, "在跑：10 + 120")
        _ = model.apply(change(.running), now: 50)
        expect(model.liveSpec?.staleAt == 170, "又有消息：重新算")
        _ = model.apply(change(.waiting), now: 60)
        expect(model.liveSpec?.staleAt == nil, "等你不过期")
        _ = model.apply(change(.completed), now: 70)
        expect(CodingSessionActivities.completionLifetime == 4 && model.doneSpec(at: 73.9) != nil && model.doneSpec(at: 74) == nil, "✓ 留 4 秒")
    }
}
