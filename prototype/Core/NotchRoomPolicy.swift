import CoreGraphics
import Foundation

/// 刘海先量空位（《实时活动晋级》稿“一 · 刘海先看有没有地方”，工作包 LA-1 / LA-2 / LA-3）。
///
/// 纯规则，不碰系统：量的人（App/NotchWatch.swift 的 MenuBarRoom）把读数交进来，这里决定
/// 问哪几个点、读到的帧折成多少空位、空位落在哪一档、耳朵多宽、画不画肩、挂几颗最小形，
/// 以及读数变了以后什么时候真的换：收立刻，长要等（+4 点、0.6 秒复核一样才长），
/// 指针在菜单栏上（不在刘海热区）只收不长。
enum NotchRoomPolicy {
    // MARK: 数字（照稿）

    /// 宽裕时每只耳朵多宽（两耳各 34：主体 26.6 + 肩 7.4）。
    static let fullSide: CGFloat = 34
    /// 最窄的耳朵：图标 18 点、两边各 4 点。再窄就退回下巴。
    static let narrowestSide: CGFloat = 26
    /// 活动紧凑以前按每边 54 画（LA-2）：只有量过、空位真有 54 才这么宽。
    static let legacyActivitySide: CGFloat = 54
    /// 读数比现在用的大这么多才算要长。
    static let growMargin: CGFloat = 4
    /// 每个事件后复核一次、要长时复核一次，都等这么久。
    static let recheckDelay: TimeInterval = 0.6
    /// 复核计时器的容差（不要求准点，系统可以合并唤醒）。
    static let recheckTolerance: TimeInterval = 0.1
    /// 来回拖的时候，两次长之间至少隔这么久（LA-3 验收：2 秒内最多长一次）。
    static let growSpacing: TimeInterval = 2
    /// 指针在菜单栏上、要长被按住时，最多再复核几次；之后等下一个事件。
    static let pointerRecheckLimit = 5
    /// 从刘海边往外第一个问的点、相邻两点的最小间距、每边最多问几个点。
    static let firstProbe: CGFloat = 3
    static let probeStep: CGFloat = 12
    static let probesPerSide = 10
    /// 一次量最多问几次：每边 10 个点 + 1 次读帧。
    static var queryBudget: Int { 2 * (probesPerSide + 1) }
    /// 刘海屏最小形：36 × 28，和岛、彼此之间隔 6；最多两颗。
    static let minimalWidth: CGFloat = 36
    static let minimalGap: CGFloat = 6
    static let maxMinimal = 2

    // MARK: 怎么量

    /// 一段要问的点（从刘海边往外的距离）：从 3 点起每 12 点一个，最后一个贴着这段的尽头；
    /// 这段太长、12 点一个放不下 10 个时把间距放宽，保证每边不超过 10 个。
    static func probeOffsets(reach: CGFloat) -> [CGFloat] {
        guard reach >= 2 else { return [] }
        let last = reach - 1
        let step = max(probeStep, ((last - firstProbe) / CGFloat(probesPerSide - 1)).rounded(.up))
        var offsets: [CGFloat] = []
        var offset = firstProbe
        while offset < last, offsets.count < probesPerSide - 1 {
            offsets.append(offset)
            offset += step
        }
        offsets.append(last)
        return offsets
    }

    /// 碰到的第一项读到了帧：空位就是刘海边到它近端的距离，向下取整到 1 点。
    /// - direction：-1 是左边（往左量），+1 是右边。
    /// - hitOffset：问到它的那个点离刘海边多远；clear：已经问过、确定空着的最远一点。
    /// 帧没读到，或者读到的帧和问到它的那一点对不上（帧里不含那一点），就只算到 clear：宁可窄一点。
    static func roomBefore(itemMinX: CGFloat?, itemMaxX: CGFloat?, edge: CGFloat, direction: CGFloat,
                           hitOffset: CGFloat, clear: CGFloat) -> CGFloat {
        guard let minX = itemMinX, let maxX = itemMaxX, maxX > minX else { return clear }
        let distance = direction < 0 ? edge - maxX : minX - edge
        guard distance <= hitOffset + 1 else { return clear }
        return max(0, floor(distance))
    }

    // MARK: 档位

    /// 宽裕：两耳各 34 带肩；偏挤：收窄到量到的宽度、不画肩；下巴：不长耳朵；让开：全屏、调度中心、锁屏时不画。
    enum Tier: Equatable, Sendable {
        case roomy, tight, chin, yield
    }

    /// 空位（取窄的那边）→ 档位。系统的 » 在，就当挤。
    static func tier(room: CGFloat?, overflow: Bool, yielding: Bool) -> Tier {
        if yielding { return .yield }
        guard !overflow, let room else { return .chin }
        let side = floor(room)
        if side >= fullSide { return .roomy }
        return side >= narrowestSide ? .tight : .chin
    }

    /// 耳朵每边多宽：最宽 34，否则就是量到的那么宽（窄的那边，向下取整）；不到 26 由档位退回下巴。
    /// 和 App/Notch.swift 以前自己算的完全一样，只是搬到这里。
    static func earWidth(leading: CGFloat?, trailing: CGFloat?) -> CGFloat {
        min(fullSide, floor(min(leading ?? 0, trailing ?? 0)))
    }

    /// LA-2：活动紧凑画多宽，就要量到多宽。以前按 max(耳宽, 54) 画，却只要求空位 ≥ 26，
    /// 菜单栏项落在 26 到 54 点之间时会被盖住。现在只有两边量到的空位都 ≥ 54 才画 54，否则就按耳宽画。
    static func activitySide(earWidth: CGFloat, leading: CGFloat?, trailing: CGFloat?) -> CGFloat {
        let room = floor(min(leading ?? 0, trailing ?? 0))
        return room >= legacyActivitySide ? legacyActivitySide : earWidth
    }

    /// 从刘海边往外放下 `count` 颗最小形要空多宽：耳宽 + 6 + 每颗 36（颗间 6）。耳宽 34 时一颗 76、两颗 118。
    static func minimalRoomNeeded(count: Int, earWidth: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return earWidth + minimalGap + CGFloat(count) * minimalWidth + CGFloat(count - 1) * minimalGap
    }

    /// 一个档位最后长什么样：耳宽、画不画肩、挂几颗最小形。
    struct Layout: Equatable, Sendable {
        var tier: Tier
        var earWidth: CGFloat
        var shoulders: Bool
        var minimalCount: Int
    }

    /// 空位 → 档位 → 耳宽、肩、最小形个数。
    /// - shoulderExtent：硬件刘海肩的外伸（不知道硬件形状就是 nil，不画肩）。
    /// - wantedMinimal：想挂几颗最小形（右边那段放得下才挂）。
    static func layout(leading: CGFloat?, trailing: CGFloat?, overflow: Bool, yielding: Bool,
                       shoulderExtent: CGFloat?, wantedMinimal: Int) -> Layout {
        let room = min(leading ?? 0, trailing ?? 0)
        let tier = tier(room: (leading == nil || trailing == nil) ? nil : room, overflow: overflow, yielding: yielding)
        switch tier {
        case .chin, .yield:
            return Layout(tier: tier, earWidth: 0, shoulders: false, minimalCount: 0)
        case .roomy, .tight:
            let ear = earWidth(leading: leading, trailing: trailing)
            // 肩从耳宽里扣，扣完还要有 26（NotchIsland.compactSide 的约定）；偏挤一律不画。
            let shoulders = tier == .roomy && shoulderExtent.map { ear - $0 >= narrowestSide } == true
            var count = min(max(0, wantedMinimal), maxMinimal)
            while count > 0, minimalRoomNeeded(count: count, earWidth: ear) > floor(trailing ?? 0) { count -= 1 }
            return Layout(tier: tier, earWidth: ear, shoulders: shoulders, minimalCount: count)
        }
    }

    // MARK: 指针

    /// 菜单栏那一条（Cocoa 坐标）：屏幕顶到菜单栏正中再往下同样高。
    static func menuBarStrip(screen: CGRect, midY: CGFloat) -> CGRect {
        let bottom = max(screen.minY, 2 * midY - screen.maxY)
        return CGRect(x: screen.minX, y: bottom, width: screen.width, height: screen.maxY - bottom)
    }

    /// 刘海热区：刘海加上此刻长出来的耳朵（悬停时每边再多 5 点）。
    static func hotZone(leadingEdge: CGFloat, trailingEdge: CGFloat, leading: CGFloat, trailing: CGFloat,
                        strip: CGRect) -> CGRect {
        let minX = leadingEdge - max(0, leading) - 5
        let maxX = trailingEdge + max(0, trailing) + 5
        return CGRect(x: minX, y: strip.minY, width: max(0, maxX - minX), height: strip.height)
    }

    /// 指针在菜单栏上、又不在刘海热区里：你多半正要去点哪个图标，这时只收不长。
    static func pointerBlocksGrowth(pointer: CGPoint, strip: CGRect, hotZone: CGRect) -> Bool {
        strip.contains(pointer) && !hotZone.contains(pointer)
    }

    // MARK: 收立刻，长要等

    /// 一块屏上“现在用的空位”。读数比现在小：马上收到读数；比现在大 4 点以上，而且 0.6 秒后复核还一样（差不过 1 点）才长；
    /// 两次长之间至少隔 2 秒；指针在菜单栏上只收不长。第一次量到的直接用（和以前一样，不让刘海多等）。
    struct Hysteresis: Equatable, Sendable {
        struct Reading: Equatable, Sendable {
            var leading: CGFloat
            var trailing: CGFloat
        }

        /// changed：现在用的空位变了；recheckIn：要在多少秒后再量一次（nil：不用，等下一个事件）。
        struct Outcome: Equatable, Sendable {
            var changed: Bool
            var recheckIn: TimeInterval?
        }

        private(set) var inUse: Reading?
        private(set) var candidate: Reading?
        private(set) var candidateAt: TimeInterval = 0
        private(set) var lastGrowAt: TimeInterval?
        private(set) var pointerHolds = 0

        init() {}

        mutating func observe(_ reading: Reading, at now: TimeInterval, pointerOnMenuBar: Bool) -> Outcome {
            guard let current = inUse else {
                inUse = reading
                candidate = nil
                pointerHolds = 0
                return Outcome(changed: true, recheckIn: nil)
            }
            // 收立刻。
            var next = Reading(leading: min(current.leading, reading.leading), trailing: min(current.trailing, reading.trailing))
            let growLeading = reading.leading >= current.leading + growMargin
            let growTrailing = reading.trailing >= current.trailing + growMargin
            var recheck: TimeInterval?
            if !growLeading && !growTrailing {
                candidate = nil
                pointerHolds = 0
            } else if pointerOnMenuBar {
                // 只收不长；等指针离开菜单栏再复核（有上限，之后等下一个事件）。
                candidate = nil
                pointerHolds += 1
                recheck = pointerHolds <= pointerRecheckLimit ? recheckDelay : nil
            } else {
                pointerHolds = 0
                let earliestGrow = (lastGrowAt ?? -.infinity) + growSpacing
                if let held = candidate, Self.agrees(held, reading, current: current) {
                    let ready = max(candidateAt + recheckDelay, earliestGrow)
                    if now + 0.001 >= ready {
                        if growLeading { next.leading = min(held.leading, reading.leading) }
                        if growTrailing { next.trailing = min(held.trailing, reading.trailing) }
                        lastGrowAt = now
                        candidate = nil
                    } else {
                        recheck = ready - now
                    }
                } else {
                    candidate = reading
                    candidateAt = now
                    recheck = max(now + recheckDelay, earliestGrow) - now
                }
            }
            let changed = next != current
            inUse = next
            return Outcome(changed: changed, recheckIn: recheck)
        }

        /// 复核“还一样”：要长的是同一边（或同两边），每一边差不过 1 点。
        private static func agrees(_ held: Reading, _ reading: Reading, current: Reading) -> Bool {
            let heldLeading = held.leading >= current.leading + growMargin
            let heldTrailing = held.trailing >= current.trailing + growMargin
            let nowLeading = reading.leading >= current.leading + growMargin
            let nowTrailing = reading.trailing >= current.trailing + growMargin
            guard heldLeading == nowLeading, heldTrailing == nowTrailing else { return false }
            if nowLeading, abs(held.leading - reading.leading) > 1 { return false }
            if nowTrailing, abs(held.trailing - reading.trailing) > 1 { return false }
            return true
        }
    }
}
