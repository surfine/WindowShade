import CoreGraphics
import Foundation

// 刘海先量空位（《实时活动晋级》稿“一 · 刘海先看有没有地方”，LA-1 / LA-2 / LA-3）的纯规则测试。
@main
struct NotchRoomPolicyTests {
    typealias Policy = NotchRoomPolicy
    typealias Reading = NotchRoomPolicy.Hysteresis.Reading

    static func main() {
        var t = TestSuite("NotchRoomPolicy")

        t.section("LA3-01", "四档：宽裕 ≥ 34 两耳 34 带肩；偏挤 26–33 收窄不画肩；挤 < 26 下巴；让开不画")
        let e: CGFloat = 7.4
        let roomy = Policy.layout(leading: 80, trailing: 120, overflow: false, yielding: false, shoulderExtent: e, wantedMinimal: 2)
        t.expect(roomy == .init(tier: .roomy, earWidth: 34, shoulders: true, minimalCount: 2), "宽裕：耳 34、带肩、右边 120 挂两颗")
        let exact = Policy.layout(leading: 34, trailing: 34.9, overflow: false, yielding: false, shoulderExtent: e, wantedMinimal: 0)
        t.expect(exact.tier == .roomy && exact.earWidth == 34 && exact.shoulders, "刚好 34 仍是宽裕，主体 26.6 + 肩 7.4")
        let tight = Policy.layout(leading: 30.7, trailing: 60, overflow: false, yielding: false, shoulderExtent: e, wantedMinimal: 2)
        t.expect(tight == .init(tier: .tight, earWidth: 30, shoulders: false, minimalCount: 0), "偏挤：耳收到 30（向下取整），不画肩")
        t.expect(Policy.layout(leading: 33.9, trailing: 40, overflow: false, yielding: false, shoulderExtent: e, wantedMinimal: 0).tier == .tight,
                 "33.9 取整 33 是偏挤")
        t.expect(Policy.layout(leading: 26, trailing: 26, overflow: false, yielding: false, shoulderExtent: nil, wantedMinimal: 0).earWidth == 26,
                 "26 还是耳朵")
        let chin = Policy.layout(leading: 25.9, trailing: 90, overflow: false, yielding: false, shoulderExtent: e, wantedMinimal: 2)
        t.expect(chin == .init(tier: .chin, earWidth: 0, shoulders: false, minimalCount: 0), "挤：不到 26 退回下巴，不挂最小形")
        let unknown = Policy.layout(leading: nil, trailing: 34, overflow: false, yielding: false, shoulderExtent: e, wantedMinimal: 1)
        t.expect(unknown.tier == .chin, "一边没量到：当挤")
        let yield = Policy.layout(leading: 80, trailing: 80, overflow: false, yielding: true, shoulderExtent: e, wantedMinimal: 2)
        t.expect(yield == .init(tier: .yield, earWidth: 0, shoulders: false, minimalCount: 0), "让开：全屏、调度中心、锁屏时不画")
        t.expect(!Policy.layout(leading: 40, trailing: 40, overflow: false, yielding: false, shoulderExtent: nil, wantedMinimal: 0).shoulders,
                 "不知道硬件形状：宽裕也不画肩")

        t.section("LA3-02", "最小形：耳宽 34 时一颗要 76、两颗要 118；放不下就少挂")
        t.expect(Policy.minimalRoomNeeded(count: 1, earWidth: 34) == 76 && Policy.minimalRoomNeeded(count: 2, earWidth: 34) == 118,
                 "一颗 76、两颗 118")
        func count(_ trailing: CGFloat, wanted: Int = 2) -> Int {
            Policy.layout(leading: 40, trailing: trailing, overflow: false, yielding: false, shoulderExtent: e, wantedMinimal: wanted).minimalCount
        }
        t.expect(count(75) == 0 && count(76) == 1 && count(117) == 1 && count(118) == 2 && count(500, wanted: 5) == 2,
                 "75 → 0、76 → 1、117 → 1、118 → 2、最多 2")
        t.expect(count(118, wanted: 1) == 1 && count(118, wanted: 0) == 0, "只想挂一颗就挂一颗")
        t.expect(Policy.layout(leading: 30, trailing: 72, overflow: false, yielding: false, shoulderExtent: e, wantedMinimal: 1).minimalCount == 1,
                 "偏挤时按收窄后的耳宽算：30 + 42 = 72 放得下一颗")

        t.section("LA3-03", "系统的 » 当挤：在就落到下巴；» 自己占着时右边只剩约 6 点，也是下巴")
        t.expect(Policy.tier(room: 80, overflow: true, yielding: false) == .chin, "» 在：空位再大也是下巴")
        t.expect(Policy.layout(leading: 80, trailing: 6, overflow: false, yielding: false, shoulderExtent: e, wantedMinimal: 1).tier == .chin,
                 "» 挨着刘海、右边只剩 6 点：下巴")
        t.expect(Policy.tier(room: 80, overflow: true, yielding: true) == .yield, "让开优先于 »")

        t.section("LA2-01", "耳宽按画出来的验：30 点处有图标时耳朵 ≤ 30，从不画 54")
        for room in stride(from: CGFloat(0), through: 80, by: 0.5) {
            let ear = Policy.earWidth(leading: room, trailing: room)
            let side = Policy.activitySide(earWidth: ear, leading: room, trailing: room)
            if side > room { t.expect(false, "空位 \(room) 却画了 \(side)") }
        }
        t.expect(Policy.activitySide(earWidth: Policy.earWidth(leading: 30, trailing: 80), leading: 30, trailing: 80) == 30,
                 "左边 30 点处有图标：活动耳朵 30")
        t.expect(Policy.activitySide(earWidth: 34, leading: 34, trailing: 34) == 34, "只量到 34（最小形关着）：画 34，不画 54")
        t.expect(Policy.activitySide(earWidth: 34, leading: 53.9, trailing: 200) == 34, "差一点不到 54：仍画 34")
        t.expect(Policy.activitySide(earWidth: 34, leading: 54, trailing: 138) == 54, "两边真量到 54：照旧画 54")
        t.expect(Policy.activitySide(earWidth: 34, leading: nil, trailing: 138) == 34, "一边没量到：不画 54")

        t.section("LA3-04", "耳宽和以前 Notch.swift 自己算的一样（宽裕时与今天一致）")
        var same = true
        for l in stride(from: CGFloat(-2), through: 60, by: 0.25) {
            for r in stride(from: CGFloat(-2), through: 60, by: 1.75) where Policy.earWidth(leading: l, trailing: r) != min(34, floor(min(l, r))) {
                same = false
            }
        }
        t.expect(same, "min(34, floor(min(左, 右)))")
        t.expect(Policy.earWidth(leading: nil, trailing: 34) == 0 && Policy.earWidth(leading: 40, trailing: nil) == 0, "没量到的一边算 0")

        t.section("LA1-01", "每 12 点问一次，最后一点贴着尽头；每边至多 10 个，一次至多 22 次询问")
        t.expect(Policy.probeOffsets(reach: 34) == [3, 15, 27, 33], "34 点：3、15、27、33")
        t.expect(Policy.probeOffsets(reach: 40) == [3, 15, 27, 39], "隐形刘海那颗胶囊的一半 40 点：3、15、27、39")
        let long = Policy.probeOffsets(reach: 138)
        t.expect(long.count <= 10 && long.first == 3 && long.last == 137, "最小形开着量 138 点：不超过 10 个点，首 3 尾 137（\(long)）")
        var gaps = true
        for reach in stride(from: CGFloat(2), through: 400, by: 1) {
            let offsets = Policy.probeOffsets(reach: reach)
            if offsets.count > Policy.probesPerSide || offsets.isEmpty || offsets.last != reach - 1 { gaps = false }
            if zip(offsets, offsets.dropFirst()).contains(where: { $1 <= $0 }) { gaps = false }
        }
        t.expect(gaps, "任何长度：1–10 个点、递增、最后一个在尽头")
        t.expect(Policy.probeOffsets(reach: 1).isEmpty && Policy.probeOffsets(reach: 0).isEmpty, "没有那一段就不问")
        t.expect(Policy.queryBudget == 22, "每边 10 个点 + 1 次读帧，共 22")

        t.section("LA1-02", "碰到第一项读帧，空位精确到 1 点；帧对不上就只算到确定空着的那一点")
        // 刘海右沿 x = 1000，往右量；15 点处问到一个图标，它从 1011.6 开始。
        t.expect(Policy.roomBefore(itemMinX: 1011.6, itemMaxX: 1033, edge: 1000, direction: 1, hitOffset: 15, clear: 3) == 11,
                 "右边：图标左沿离刘海 11.6 → 11")
        // 刘海左沿 x = 800，往左量；27 点处问到，它的右沿在 774.2。
        t.expect(Policy.roomBefore(itemMinX: 750, itemMaxX: 774.2, edge: 800, direction: -1, hitOffset: 27, clear: 15) == 25,
                 "左边：图标右沿离刘海 25.8 → 25")
        t.expect(Policy.roomBefore(itemMinX: nil, itemMaxX: nil, edge: 1000, direction: 1, hitOffset: 27, clear: 15) == 15,
                 "帧没读到：只算到上一个空着的点")
        t.expect(Policy.roomBefore(itemMinX: 1040, itemMaxX: 1060, edge: 1000, direction: 1, hitOffset: 27, clear: 15) == 15,
                 "帧不含问到的那一点（读到别的东西）：只算到上一个空着的点")
        t.expect(Policy.roomBefore(itemMinX: 990, itemMaxX: 1020, edge: 1000, direction: 1, hitOffset: 3, clear: 0) == 0,
                 "图标压着刘海边：0")

        t.section("LA3-05", "收立刻，长要等：+4 点以上且 0.6 秒复核一样才长")
        var h = NotchRoomPolicy.Hysteresis()
        t.expect(h.observe(r(34, 34), at: 0, pointerOnMenuBar: false) == .init(changed: true, recheckIn: nil) && h.inUse == r(34, 34),
                 "第一次量到的直接用（和以前一样，不多等）")
        t.expect(h.observe(r(20, 34), at: 1, pointerOnMenuBar: false) == .init(changed: true, recheckIn: nil) && h.inUse == r(20, 34),
                 "左边读数变小：马上收到 20")
        t.expect(h.observe(r(23, 34), at: 2, pointerOnMenuBar: false) == .init(changed: false, recheckIn: nil) && h.inUse == r(20, 34),
                 "只大 3 点：不长，也不排复核")
        let wait = h.observe(r(34, 34), at: 3, pointerOnMenuBar: false)
        t.expect(!wait.changed && wait.recheckIn.map { abs($0 - 0.6) < 1e-9 } == true && h.inUse == r(20, 34), "大 14 点：先等 0.6 秒复核")
        t.expect(h.observe(r(34, 34), at: 3.3, pointerOnMenuBar: false).recheckIn.map { abs($0 - 0.3) < 1e-9 } == true && h.inUse == r(20, 34),
                 "0.3 秒时又量到一样的：还不长，等满 0.6 秒")
        t.expect(h.observe(r(34.5, 34), at: 3.6, pointerOnMenuBar: false) == .init(changed: true, recheckIn: nil) && h.inUse == r(34, 34),
                 "0.6 秒复核还一样（差不过 1 点）：长，取两次里小的")
        var h2 = NotchRoomPolicy.Hysteresis()
        _ = h2.observe(r(10, 34), at: 0, pointerOnMenuBar: false)
        _ = h2.observe(r(34, 34), at: 5, pointerOnMenuBar: false)
        let differs = h2.observe(r(28, 34), at: 5.6, pointerOnMenuBar: false)
        t.expect(!differs.changed && differs.recheckIn != nil && h2.inUse == r(10, 34), "复核不一样（34 → 28）：不长，从新读数重新等")
        _ = h2.observe(r(28, 34), at: 6.2, pointerOnMenuBar: false)
        t.expect(h2.inUse == r(28, 34), "新读数 0.6 秒后复核一样：长到 28")
        var h3 = NotchRoomPolicy.Hysteresis()
        _ = h3.observe(r(10, 34), at: 0, pointerOnMenuBar: false)
        _ = h3.observe(r(34, 34), at: 5, pointerOnMenuBar: false)
        _ = h3.observe(r(5, 34), at: 5.2, pointerOnMenuBar: false)
        t.expect(h3.inUse == r(5, 34) && h3.candidate == nil, "等复核时又变窄：马上收，等着的长作废")
        _ = h3.observe(r(34, 34), at: 5.6, pointerOnMenuBar: false)
        t.expect(h3.inUse == r(5, 34), "作废后再看到宽的：重新等 0.6 秒，不直接长")
        var h4 = NotchRoomPolicy.Hysteresis()
        _ = h4.observe(r(34, 34), at: 0, pointerOnMenuBar: false)
        let both = h4.observe(r(20, 60), at: 1, pointerOnMenuBar: false)
        t.expect(h4.inUse == r(20, 34) && both.recheckIn != nil, "一边收一边要长：收的那边马上收，长的那边等复核")

        t.section("LA3-06", "指针在菜单栏上（不在刘海热区）：只收不长，离开后再复核")
        var p = NotchRoomPolicy.Hysteresis()
        _ = p.observe(r(10, 34), at: 0, pointerOnMenuBar: false)
        let held = p.observe(r(34, 34), at: 1, pointerOnMenuBar: true)
        t.expect(!held.changed && held.recheckIn != nil && p.inUse == r(10, 34) && p.candidate == nil, "要长被按住，排一次复核")
        _ = p.observe(r(34, 34), at: 1.6, pointerOnMenuBar: true)
        t.expect(p.inUse == r(10, 34), "指针还在菜单栏上：仍不长")
        _ = p.observe(r(34, 2), at: 2.2, pointerOnMenuBar: true)
        t.expect(p.inUse == r(10, 2), "指针在菜单栏上照样收")
        var holds = 0
        var q = NotchRoomPolicy.Hysteresis()
        _ = q.observe(r(10, 34), at: 0, pointerOnMenuBar: false)
        var clock = 1.0
        while let delay = q.observe(r(34, 34), at: clock, pointerOnMenuBar: true).recheckIn, holds < 100 {
            holds += 1
            clock += delay
        }
        t.expect(holds == Policy.pointerRecheckLimit, "指针一直不走：最多复核 \(Policy.pointerRecheckLimit) 次就停，等下一个事件")
        let left = q.observe(r(34, 34), at: clock + 5, pointerOnMenuBar: false)
        t.expect(left.recheckIn != nil && q.inUse == r(10, 34), "指针离开后的那次读数：先等复核")
        _ = q.observe(r(34, 34), at: clock + 5.6, pointerOnMenuBar: false)
        t.expect(q.inUse == r(34, 34), "0.6 秒后复核一样：长")
        let strip = Policy.menuBarStrip(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), midY: 982 - 16.5)
        t.expect(strip == CGRect(x: 0, y: 949, width: 1512, height: 33), "菜单栏那一条：顶上 33 点")
        let zone = Policy.hotZone(leadingEdge: 663.5, trailingEdge: 848.5, leading: 34, trailing: 34, strip: strip)
        t.expect(Policy.pointerBlocksGrowth(pointer: CGPoint(x: 1300, y: 970), strip: strip, hotZone: zone), "指针在右边的菜单栏图标上：按住")
        t.expect(!Policy.pointerBlocksGrowth(pointer: CGPoint(x: 700, y: 970), strip: strip, hotZone: zone), "指针在刘海热区里：不按住")
        t.expect(!Policy.pointerBlocksGrowth(pointer: CGPoint(x: 1300, y: 500), strip: strip, hotZone: zone), "指针在菜单栏下面：不按住")
        t.expect(!Policy.pointerBlocksGrowth(pointer: CGPoint(x: 625, y: 970), strip: strip, hotZone: zone), "悬停多出的 5 点也算热区")

        t.section("LA3-07", "来回拖 20 次：2 秒内最多长一次；停下以后还是会长回来")
        var random = DeterministicRandom()
        var worstGrowsIn2s = 0
        var settledAll = true
        for trial in 0..<20 {
            let result = dragSimulation(seed: &random)
            worstGrowsIn2s = max(worstGrowsIn2s, result.maxGrowsIn2s)
            if !result.settledWide { settledAll = false; print("trial \(trial) did not settle") }
        }
        t.expect(worstGrowsIn2s <= 1, "任何 2 秒窗口里最多长一次（最坏 \(worstGrowsIn2s)）")
        t.expect(settledAll, "拖完停在宽的位置：最后都长回宽裕（差不到 4 点的不算要长）")

        t.section("LA1-03", "每个事件一次 0.6 秒复核，空闲 0 次")
        // 一次事件、读数没变：量一次 + 复核一次，之后不再排。
        var idle = NotchRoomPolicy.Hysteresis()
        _ = idle.observe(r(34, 34), at: 0, pointerOnMenuBar: false)
        t.expect(idle.observe(r(34, 34), at: 10, pointerOnMenuBar: false).recheckIn == nil, "读数没变：规则不要复核（只剩事件那一次）")
        t.expect(idle.observe(r(34, 34), at: 10.6, pointerOnMenuBar: false).recheckIn == nil, "复核也没变：不再排，空闲时一次也不量")

        t.finish()
    }

    static func r(_ leading: CGFloat, _ trailing: CGFloat) -> Reading { Reading(leading: leading, trailing: trailing) }

    /// 模拟 MenuBarRoom：每次拖动是一个事件（马上量一次，量完补 0.6 秒复核），规则要复核就排一个（一块屏至多一个）。
    static func dragSimulation(seed: inout DeterministicRandom) -> (maxGrowsIn2s: Int, settledWide: Bool) {
        var world: CGFloat = 34
        var changes: [(at: Double, value: CGFloat)] = []
        var clock = 0.5
        for _ in 0..<20 {
            clock += 0.05 + seed.unit() * 0.9
            changes.append((clock, 10 + CGFloat(seed.unit() * 10)))
            clock += 0.05 + seed.unit() * 0.9
            changes.append((clock, 30 + CGFloat(seed.unit() * 30)))
        }
        let end = clock
        changes.append((end + 0.01, 60))
        var rule = NotchRoomPolicy.Hysteresis()
        _ = rule.observe(r(world, world), at: 0, pointerOnMenuBar: false)
        var recheckAt: Double?
        var grows: [Double] = []
        var queue = changes
        var now = 0.0
        func measure(at time: Double, afterEvent: Bool) {
            let before = rule.inUse
            let outcome = rule.observe(r(world, world), at: time, pointerOnMenuBar: false)
            if let before, let after = rule.inUse, after.leading > before.leading { grows.append(time) }
            if let delay = outcome.recheckIn {
                if recheckAt == nil { recheckAt = time + delay }
            } else if afterEvent, recheckAt == nil {
                recheckAt = time + NotchRoomPolicy.recheckDelay
            }
        }
        while now < end + 20 {
            let nextEvent = queue.first?.at ?? .infinity
            let nextRecheck = recheckAt ?? .infinity
            guard min(nextEvent, nextRecheck) < .infinity else { break }
            if nextEvent <= nextRecheck {
                now = nextEvent
                world = queue.removeFirst().value
                measure(at: now, afterEvent: true)
            } else {
                now = nextRecheck
                recheckAt = nil
                measure(at: now, afterEvent: false)
            }
        }
        var worst = 0
        for (index, start) in grows.enumerated() {
            worst = max(worst, grows[index...].prefix { $0 < start + 2 }.count)
        }
        // 停在 60：现在用的离 60 不到 4 点（再小的差不值得长），也不超过 60。
        let settled = rule.inUse.map { $0.leading > 60 - NotchRoomPolicy.growMargin && $0.leading <= 60 } ?? false
        return (worst, settled)
    }
}
