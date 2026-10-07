// 实时活动 store 的行为测试：只通过公开 API 观察，不镜像内部实现。
// 纯 swiftc @main 入口，无权限、无 UI、无网络。

import Foundation

@main struct NotchActivityTests {
    static func expect(_ condition: Bool, _ message: String) {
        precondition(condition, "断言失败: \(message)")
    }

    // 造一条活动，默认 startedAt=now，updatedAt 省略即 startedAt。
    static func make(
        _ id: String,
        _ kind: NotchActivityKind = .music,
        generation: UInt64 = 1,
        startedAt: Double = 0,
        updatedAt: Double? = nil,
        expiresAt: Double? = nil,
        progress: Double? = nil,
        title: String = "t"
    ) -> NotchActivity {
        NotchActivity(
            id: id,
            generation: generation,
            kind: kind,
            title: title,
            startedAt: startedAt,
            updatedAt: updatedAt,
            expiresAt: expiresAt,
            progress: progress
        )
    }

    static func main() {
        testPriorityOrderingAndCap()
        testSelectionStickyAndContentUpdate()
        testFourthActivityPreservesSelection()
        testSelectionAfterEnd()
        testMoveSelectionCycles()
        testStaleGenerationAndUpdatedAt()
        testTombstoneNoRevival()
        testTombstoneBound()
        testExpiryBoundariesAndPrune()
        testProgressOptional()
        testRejectsNaNAndBadTimestamps()
        testMonotonicWatermark()
        testCapacityBounded()
        testLargeStepsNoOverflow()
        testPollingTiers()

        var future = NotchActivityStore()
        expect(!future.upsert(make("future", startedAt: 11), now: 10), "未来时间不能污染排序")
        expect(!future.upsert(make("future-update", startedAt: 1, updatedAt: 11), now: 10), "未来更新时间不能推进状态")
        expect(future.upsert(make("valid", startedAt: 1), now: 10), "拒绝未来输入后仍接受正常输入")
        print("PASS notch activity store")
    }

    // 1) 三个上限与优先级排序。
    static func testPriorityOrderingAndCap() {
        var store = NotchActivityStore()
        expect(store.activities.isEmpty, "初始为空")
        expect(store.selected == nil, "初始无选中")

        // 按 startedAt 故意乱序插入，观察排序不依赖插入顺序。
        _ = store.upsert(make("m1", .music, startedAt: 10), now: 10)
        _ = store.upsert(make("r1", .recording, startedAt: 5), now: 10)
        _ = store.upsert(make("a1", .airPods, startedAt: 1), now: 10)
        _ = store.upsert(make("d1", .airDrop, startedAt: 3), now: 10)
        _ = store.upsert(make("o1", .route, startedAt: 2), now: 10)

        let ids = store.activities.map(\.id)
        expect(ids == ["r1", "d1", "o1", "m1", "a1"], "按优先级降序，实际 \(ids)")

        let visible = store.visible
        expect(visible.count == 3, "最多 3 条可见")
        expect(visible.map(\.id) == ["r1", "d1", "o1"], "可见就是前三")

        // 同优先级按 startedAt 升序，再按 id 稳定 tie-break。
        var tie = NotchActivityStore()
        _ = tie.upsert(make("b", .music, startedAt: 2), now: 2)
        _ = tie.upsert(make("a", .music, startedAt: 2), now: 2)
        _ = tie.upsert(make("c", .music, startedAt: 1), now: 2)
        expect(tie.activities.map(\.id) == ["c", "a", "b"], "startedAt 升序 + id tie-break")

        // 排序不看 updatedAt：把 u1 的 updatedAt 抬到最大，顺序也不该变。
        var noReorder = NotchActivityStore()
        _ = noReorder.upsert(make("x", .music, startedAt: 1), now: 1)
        _ = noReorder.upsert(make("y", .music, startedAt: 2), now: 2)
        _ = noReorder.upsert(make("x", .music, startedAt: 1, updatedAt: 99), now: 99)
        expect(noReorder.activities.map(\.id) == ["x", "y"], "updatedAt 不影响排序")
    }

    // 2) 选中粘滞：普通内容更新不跳选、不重排。
    static func testSelectionStickyAndContentUpdate() {
        var store = NotchActivityStore()
        _ = store.upsert(make("r", .recording, startedAt: 0), now: 0)
        _ = store.upsert(make("m", .music, startedAt: 1), now: 1)
        expect(store.select(id: "m"), "可见项可被选中")
        expect(store.selectedID == "m", "选中生效")

        // 更新别的条目内容，不改变选中。
        _ = store.upsert(make("r", .recording, startedAt: 0, updatedAt: 5, title: "变了"), now: 5)
        expect(store.selectedID == "m", "别的条目更新不跳选")

        // 更新选中项自身的内容，仍保持选中。
        _ = store.upsert(make("m", .music, startedAt: 1, updatedAt: 6, title: "新标题"), now: 6)
        expect(store.selectedID == "m", "自身内容更新不丢选")
        expect(store.selected?.title == "新标题", "内容已更新")

        // 不可见项不能被选中。
        var small = NotchActivityStore()
        _ = small.upsert(make("r1", .recording, startedAt: 0), now: 0)
        _ = small.upsert(make("r2", .recording, startedAt: 0, title: "2"), now: 0)
        _ = small.upsert(make("r3", .recording, startedAt: 0, title: "3"), now: 0)
        _ = small.upsert(make("r4", .recording, startedAt: 0, title: "4"), now: 0)
        expect(!small.select(id: "r4"), "第四名不可选")
        expect(small.select(id: "r1"), "前三可选")
    }

    static func testFourthActivityPreservesSelection() {
        var store = NotchActivityStore()
        _ = store.upsert(make("music", .music), now: 0)
        _ = store.upsert(make("route", .route), now: 0)
        _ = store.upsert(make("drop", .airDrop), now: 0)
        expect(store.select(id: "music"), "选中正在看的音乐")
        _ = store.upsert(make("recording", .recording, startedAt: 1), now: 1)
        expect(store.selectedID == "music", "第四项不赶走当前选择")
        expect(store.visible.map(\.id) == ["recording", "drop", "music"], "保留选中且最多三项")
        _ = store.upsert(make("music", .music, updatedAt: 2, progress: 0.5), now: 2)
        expect(store.selectedID == "music", "进度更新仍保持选择")
        _ = store.end(id: "music", generation: 1, now: 3)
        expect(store.selectedID == nil && store.visible.map(\.id) == ["recording", "drop", "route"], "结束才释放位置")
    }

    // 3) 选中项结束后清空。
    static func testSelectionAfterEnd() {
        var store = NotchActivityStore()
        _ = store.upsert(make("a", .recording, startedAt: 0), now: 0)
        _ = store.upsert(make("b", .music, startedAt: 1), now: 1)
        expect(store.select(id: "a"), "选中 a")
        expect(store.end(id: "a", generation: 1, now: 2), "a 结束")
        expect(store.selectedID == nil, "选中随结束清空")
        expect(store.activities.map(\.id) == ["b"], "只留 b")
    }

    // 4) 可见 3 个之间循环切换。
    static func testMoveSelectionCycles() {
        var store = NotchActivityStore()
        _ = store.upsert(make("a", .recording, startedAt: 0), now: 0)
        _ = store.upsert(make("b", .recording, startedAt: 1), now: 1)
        _ = store.upsert(make("c", .recording, startedAt: 2), now: 2)

        store.moveSelection(by: 1)
        expect(store.selectedID == "a", "无选中时选第一个")
        store.moveSelection(by: 1)
        expect(store.selectedID == "b", "向后一格")
        store.moveSelection(by: 1)
        expect(store.selectedID == "c", "向后一格")
        store.moveSelection(by: 1)
        expect(store.selectedID == "a", "三个循环回第一个")

        store.moveSelection(by: -1)
        expect(store.selectedID == "c", "反向循环到最后一个")
        store.moveSelection(by: 0)
        expect(store.selectedID == "c", "by 0 不动")
    }

    // 5) 老 generation / 旧 updatedAt 不能覆盖新内容。
    static func testStaleGenerationAndUpdatedAt() {
        var store = NotchActivityStore()
        _ = store.upsert(make("a", .music, generation: 2, startedAt: 0, updatedAt: 10), now: 10)
        // 老代覆盖应失败。
        expect(!store.upsert(make("a", .music, generation: 1, startedAt: 0, updatedAt: 99), now: 11),
               "老 generation 不能覆盖")
        // 同代旧 updatedAt 不能覆盖。
        expect(!store.upsert(make("a", .music, generation: 2, startedAt: 0, updatedAt: 5), now: 12),
               "旧 updatedAt 不能覆盖")
        // 同代更新的 updatedAt 可以。
        expect(store.upsert(make("a", .music, generation: 2, startedAt: 0, updatedAt: 11, title: "n"), now: 13),
               "新 updatedAt 可覆盖")
        expect(store.activities.first?.title == "n", "内容已替换")

        // 老 generation 不能结束新代。
        _ = store.upsert(make("b", .route, generation: 5, startedAt: 1), now: 14)
        expect(!store.end(id: "b", generation: 4, now: 15), "老代结束不了新代")
        expect(store.activities.contains(where: { $0.id == "b" }), "b 仍在")
    }

    // 6) end 后同代不得复活，新代可显式重开。
    static func testTombstoneNoRevival() {
        var store = NotchActivityStore()
        _ = store.upsert(make("a", .music, generation: 3, startedAt: 0), now: 0)
        expect(store.end(id: "a", generation: 3, now: 1), "结束 a")
        // 同一代晚到的回调不得复活。
        expect(!store.upsert(make("a", .music, generation: 3, startedAt: 0, updatedAt: 9), now: 2),
               "同代不复活")
        // 较老代更不行。
        expect(!store.upsert(make("a", .music, generation: 2, startedAt: 0, updatedAt: 9), now: 3),
               "老代不复活")
        // 新代显式可重开。
        expect(store.upsert(make("a", .music, generation: 4, startedAt: 0, updatedAt: 3), now: 4),
               "新代可重开")
    }

    // 7) 墓碑有界：大量结束不应无限增长，但同代不复活/新代可重开仍成立。
    static func testTombstoneBound() {
        var store = NotchActivityStore()
        // 结束 1 条并确认墓碑生效。
        _ = store.upsert(make("a", .music, generation: 1, startedAt: 0), now: 0)
        expect(store.end(id: "a", generation: 1, now: 1), "结束 a")
        expect(!store.upsert(make("a", .music, generation: 1, startedAt: 0, updatedAt: 2), now: 2),
               "墓碑拦同代")
        expect(store.upsert(make("a", .music, generation: 2, startedAt: 0, updatedAt: 2), now: 3),
               "新代可重开")

        // 结束远多于 64 条：行为仍自洽（有界），不崩溃。
        // 墓碑上限是硬约束，因此这里只验证语义正确性，不假设任意旧 id 都还能拦。
        for i in 0..<100 {
            let id = "gone\(i)"
            _ = store.upsert(make(id, .music, generation: 1, startedAt: 0), now: Double(10 + i))
            expect(store.end(id: id, generation: 1, now: Double(10 + i)), "结束 \(id)")
        }
        // 最近结束的 id 的同代应被拦（尚未被淘汰）。
        expect(!store.upsert(make("gone99", .music, generation: 1, startedAt: 0, updatedAt: 200), now: 200),
               "最近墓碑拦同代")
        // 新代可重开。
        expect(store.upsert(make("gone99", .music, generation: 2, startedAt: 0, updatedAt: 201), now: 201),
               "新代可重开")
        // 记录总数始终有界。
        expect(store.activities.count <= NotchActivityStore.capacity, "存储有界")
    }

    // 8) 过期与精确边界；prune 清理。
    static func testExpiryBoundariesAndPrune() {
        var store = NotchActivityStore()
        // now == expiresAt 视为已过期，忽略。
        expect(!store.upsert(make("e", .music, startedAt: 0, expiresAt: 5), now: 5),
               "now == expiresAt 已过期")
        // now 略早一点则可进。
        expect(store.upsert(make("e", .music, startedAt: 0, expiresAt: 5), now: 4.999),
               "过期前可进入")
        // 到点 prune 精确边界删除。
        store.prune(now: 4.999)
        expect(store.activities.contains(where: { $0.id == "e" }), "正好到期前仍在")
        store.prune(now: 5)
        expect(!store.activities.contains(where: { $0.id == "e" }), "正好到点被 prune")
    }

    // 9) 缺失进度不补假数；合法进度原样保留。
    static func testProgressOptional() {
        var store = NotchActivityStore()
        _ = store.upsert(make("n", .recording, startedAt: 0), now: 0)
        expect(store.selected == nil, "没选中就没有 selected")
        expect(store.activities.first?.progress == nil, "缺失进度就是 nil")
        _ = store.upsert(make("n", .recording, startedAt: 0, updatedAt: 1, progress: 0.5), now: 1)
        expect(store.activities.first?.progress == 0.5, "0.5 保留")
        _ = store.upsert(make("n", .recording, startedAt: 0, updatedAt: 2, progress: 0), now: 2)
        expect(store.activities.first?.progress == 0, "0 是合法值不是缺失")
        _ = store.upsert(make("n", .recording, startedAt: 0, updatedAt: 3, progress: 1), now: 3)
        expect(store.activities.first?.progress == 1, "1 合法")
    }

    // 10) NaN、负值、未来/倒退时间戳被拒。
    static func testRejectsNaNAndBadTimestamps() {
        var store = NotchActivityStore()
        // 非法 now。
        expect(!store.upsert(make("a", .music, startedAt: 0), now: -1), "负 now 拒绝")
        expect(!store.upsert(make("a", .music, startedAt: 0), now: .nan), "NaN now 拒绝")
        expect(!store.upsert(make("a", .music, startedAt: 0), now: .infinity), "inf now 拒绝")

        // 负 startedAt。
        expect(!store.upsert(make("b", .music, startedAt: -1), now: 0), "负 startedAt 拒绝")
        // updatedAt < startedAt。
        expect(!store.upsert(make("c", .music, startedAt: 10, updatedAt: 9), now: 10),
               "updatedAt < startedAt 拒绝")
        // 非有限 startedAt。
        expect(!store.upsert(make("d", .music, startedAt: .nan), now: 0), "NaN startedAt 拒绝")
        // 非有限 expiresAt。
        expect(!store.upsert(make("f", .music, startedAt: 0, expiresAt: .nan), now: 0),
               "NaN expiresAt 拒绝")
        // progress 越界与 NaN。
        expect(!store.upsert(make("g", .music, startedAt: 0, progress: -0.1), now: 0),
               "progress < 0 拒绝")
        expect(!store.upsert(make("h", .music, startedAt: 0, progress: 1.1), now: 0),
               "progress > 1 拒绝")
        expect(!store.upsert(make("i", .music, startedAt: 0, progress: .nan), now: 0),
               "NaN progress 拒绝")
        // 上面全部被拒后存储应为空。
        expect(store.activities.isEmpty, "非法输入不留痕")
    }

    // 11) 全局单调水位拒绝倒退的 now，同一 now 合法；prune 不重置水位。
    static func testMonotonicWatermark() {
        var store = NotchActivityStore()
        expect(store.upsert(make("a", .music, startedAt: 0), now: 10), "先前进到 10")
        // 倒退 now 被拒。
        expect(!store.upsert(make("b", .music, startedAt: 0), now: 9), "倒退 now 拒绝")
        // 同一 now 合法。
        expect(store.upsert(make("b", .music, startedAt: 0), now: 10), "同一 now 合法")
        // prune 到更晚后，旧 now 仍被拒（水位不因 prune 重置）。
        store.prune(now: 20)
        expect(!store.upsert(make("c", .music, startedAt: 0), now: 15), "prune 后旧 now 仍拒绝")
        expect(store.upsert(make("c", .music, startedAt: 0), now: 21), "新 now 通过")
    }

    // 12) 容量上限 32：满了不再驱逐既有，旧更新也不会反弹。
    static func testCapacityBounded() {
        var store = NotchActivityStore()
        for i in 0..<40 {
            _ = store.upsert(make("id\(i)", .airPods, startedAt: 0, title: "\(i)"), now: Double(i))
        }
        expect(store.activities.count == NotchActivityStore.capacity, "封顶在 32，实际 \(store.activities.count)")
        // 先进来的 32 条都还在。
        for i in 0..<32 {
            expect(store.activities.contains(where: { $0.id == "id\(i)" }), "id\(i) 应保留")
        }
        // 超限的没进来。
        expect(!store.activities.contains(where: { $0.id == "id39" }), "id39 被有界丢弃")
        // 已存在条目仍可正常更新（不会因为当初没被驱逐而反弹旧数据）。
        expect(store.upsert(make("id0", .airPods, startedAt: 0, updatedAt: 50, title: "upd"), now: 50),
               "既有条目可更新")
        // 旧 updatedAt 依然拒绝。
        expect(!store.upsert(make("id0", .airPods, startedAt: 0, updatedAt: 40, title: "old"), now: 51),
               "旧更新不反弹")
    }

    // 13) 大 step 与负 now：无整数溢出、无崩溃。
    static func testLargeStepsNoOverflow() {
        var store = NotchActivityStore()
        _ = store.upsert(make("a", .recording, startedAt: 0), now: 0)
        _ = store.upsert(make("b", .recording, startedAt: 1), now: 1)
        _ = store.upsert(make("c", .recording, startedAt: 2), now: 2)
        _ = store.select(id: "a")

        store.moveSelection(by: Int.max)
        expect(store.selectedID != nil, "大 step 后有合法选中")
        store.moveSelection(by: Int.min)
        expect(store.selectedID != nil, "大负 step 后仍有合法选中")
        store.moveSelection(by: 0)
        expect(store.selectedID != nil, "0 step 不改变")
        // 极端 now 不会崩，且行为可预期（inf 被拒）。
        expect(!store.upsert(make("z", .music, startedAt: 0), now: .infinity), "inf now 拒绝")
        expect(!store.end(id: "a", generation: 1, now: -5), "负 now 结束拒绝")
    }

    // 14) PERF-08：轮询档位只由「有没有东西要看」决定，和机器状态无关。
    static func testPollingTiers() {
        let p = NotchActivityPollPolicy.self
        expect(p.tier(hasPlayer: true, hasRecordingSource: false, hasVisibleCard: false) == .progress,
               "有播放器在放：进度档")
        expect(p.tier(hasPlayer: false, hasRecordingSource: true, hasVisibleCard: false) == .source,
               "语音备忘录开着：来源档")
        expect(p.tier(hasPlayer: false, hasRecordingSource: false, hasVisibleCard: true) == .source,
               "画面上有卡片：来源档")
        expect(p.tier(hasPlayer: false, hasRecordingSource: false, hasVisibleCard: false) == .idle,
               "什么都没有：空闲档")
        expect(p.interval(for: .progress) == 2, "进度档 2 秒")
        expect(p.interval(for: .source) > p.interval(for: .progress), "来源档比进度档慢")
        expect(p.interval(for: .idle) > p.interval(for: .source), "空闲档最慢")
        expect(p.tolerance(for: p.interval(for: .idle)) <= 1, "容忍度有上限，空闲唤醒不会被拖长")
        expect(p.tolerance(for: p.interval(for: .progress)) > 0, "进度档也允许系统合并唤醒")
    }
}
