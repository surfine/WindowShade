// 行为实验室 · 时序特征聚合
//
// 这里只做一件事：把短时间内的按键与指针事件，压成不含输入内容的
// 数值特征（按住的时长、两次按下之间的间隔、指针速度与转向角度）。
//
// 硬性约定：
//   * 输出结构里**只**允许出现时长、速度、转向角度这类数值；绝不出现 keyCode
//     或任何坐标。
//   * pressed 字典是临时的，只在内存里存 code/时间，容量上限 256。
//   * 每个输出数组最多 128 个值，超过后用蓄水池抽样，避免只学到开头一小段。
//   * 没有"风险分""认证""锁屏""压力"之类的假设——这只是特征采集。
//
// 本文件是纯 Foundation，不监听系统、不读任何外部状态。

import Foundation

// 一扇时间窗聚合出来的特征。全是数值，没有按键码、没有坐标。
struct TimingFeatureWindow: Codable, Equatable {
    var context: String
    var startedAt: Double
    var endedAt: Double
    // 每次按下的按住时长（秒），只保留 (0, 2]。
    var holds: [Double]
    // 相邻两次按下之间的间隔（秒），只保留 (0, 2]（空闲不算）。
    var downGaps: [Double]
    // 指针一次移动的瞬时速度（点/秒）。
    var pointerSpeeds: [Double]
    // 相邻两段移动方向之间的夹角（弧度，0...π）。
    var pointerTurns: [Double]
}

final class TimingFeatureAccumulator {
    // 每个输出数组的上限；达到后停止增长。
    static let maxSamples = 128
    // pressed 临时表的容量上限。
    static let maxPressed = 256
    // 允许参与计算的最大间隔；比这更长视为空闲，不做假特征。
    static let maxInterval = 2.0
    // 单次指针采样允许的最大 dt；比这更长就重置方向基准。
    static let maxPointerDt = 0.25

    private(set) var context: String
    private(set) var startedAt: Double

    // 临时的按键按下表：code -> 按下时刻。仅内存，重置/快照后清空。
    private var pressed: [UInt16: Double] = [:]
    // 上一个按键按下的时刻，用来算 downGap。
    private var lastDownAt: Double?
    private var lastEventAt: Double?

    // 上一次指针事件的时间与方向向量（未归一化的 dx/dy）。
    private var lastPointerAt: Double?
    private var lastPointerVector: (dx: Double, dy: Double)?

    private var holds: [Double] = []
    private var downGaps: [Double] = []
    private var pointerSpeeds: [Double] = []
    private var pointerTurns: [Double] = []
    private var holdSeen = 0, gapSeen = 0, speedSeen = 0, turnSeen = 0

    init(context: String, startedAt: Double) {
        self.context = context
        self.startedAt = startedAt.isFinite ? startedAt : 0
    }

    // MARK: - 按键

    func keyDown(code: UInt16, at: Double, isRepeat: Bool = false) {
        guard acceptTime(at) else { return }
        // 自动重复：不覆盖按下时间，也不产生新的 downGap。
        if isRepeat { return }
        // 同一按键重复按下：忽略，保留最初按下时间。
        if pressed[code] != nil { return }

        if let previous = lastDownAt {
            let gap = at - previous
            // 空闲间隔不算；只保留合理的 (0, 2]。
            if gap > 0 && gap <= TimingFeatureAccumulator.maxInterval {
                append(gap, to: &downGaps, seen: &gapSeen)
            }
        }
        lastDownAt = at

        // 临时表有上限：满了就先清掉最旧的一条，绝不无限增长。
        if pressed.count >= TimingFeatureAccumulator.maxPressed {
            if let oldest = pressed.min(by: { $0.value < $1.value })?.key {
                pressed.removeValue(forKey: oldest)
            }
        }
        pressed[code] = at
    }

    func keyUp(code: UInt16, at: Double) {
        guard acceptTime(at) else { return }
        // 没按下过就松手：不配对的 up，忽略。
        guard let downAt = pressed.removeValue(forKey: code) else { return }
        let hold = at - downAt
        // 只保留 (0, 2] 的按住时长。
        if hold > 0 && hold <= TimingFeatureAccumulator.maxInterval {
            append(hold, to: &holds, seen: &holdSeen)
        }
    }

    // MARK: - 指针

    func pointerMoved(dx: Double, dy: Double, at: Double) {
        // 非有限时间或非有限位移直接丢。
        guard dx.isFinite, dy.isFinite else { clearTransientClocks(); return }
        guard acceptTime(at) else { return }

        guard let previousAt = lastPointerAt else {
            // 第一个指针事件只用来播种时钟，不算速度、不算转向。
            lastPointerAt = at
            lastPointerVector = (dx, dy)
            return
        }

        let dt = at - previousAt
        // dt 不合理（<=0、>0.25、或逆时针）：重置方向基准，绝不产生假速度。
        if !(dt > 0 && dt <= TimingFeatureAccumulator.maxPointerDt) {
            lastPointerAt = at
            lastPointerVector = (dx, dy)
            return
        }

        let distance = hypot(dx, dy)
        guard distance.isFinite, (distance / dt).isFinite else { clearTransientClocks(); return }
        if distance > 0 {
            append(distance / dt, to: &pointerSpeeds, seen: &speedSeen)
        }

        // 只有两段都非零才谈转向角度。
        if let previous = lastPointerVector {
            let previousLength = hypot(previous.dx, previous.dy)
            let currentLength = distance
            if previousLength > 0 && currentLength > 0 {
                let dot = (previous.dx / previousLength) * (dx / currentLength) +
                          (previous.dy / previousLength) * (dy / currentLength)
                let clamped = min(1.0, max(-1.0, dot))
                append(acos(clamped), to: &pointerTurns, seen: &turnSeen)
            }
        }

        lastPointerAt = at
        lastPointerVector = (dx, dy)
    }

    // MARK: - 快照与重置

    func snapshot(endedAt: Double) -> TimingFeatureWindow {
        let end = endedAt.isFinite ? max(endedAt, lastEventAt ?? startedAt, startedAt) : (lastEventAt ?? startedAt)
        let window = TimingFeatureWindow(
            context: context,
            startedAt: startedAt,
            endedAt: end,
            holds: holds,
            downGaps: downGaps,
            pointerSpeeds: pointerSpeeds,
            pointerTurns: pointerTurns
        )
        // 快照后清空 pressed 与瞬时时钟，防止跨窗口的按住被误算。
        reset(context: context, at: end)
        return window
    }

    func reset(context: String, at: Double) {
        // 换窗口：清空一切时钟与数组，连 context 一起重置。
        pressed.removeAll()
        clearTransientClocks()
        holds.removeAll()
        downGaps.removeAll()
        pointerSpeeds.removeAll()
        pointerTurns.removeAll()
        holdSeen = 0; gapSeen = 0; speedSeen = 0; turnSeen = 0
        self.context = context
        startedAt = at.isFinite ? at : 0
        lastEventAt = nil
    }

    // MARK: - 内部

    // 重置瞬时连续性：pressed 表、时钟与方向基准。逆时针时间戳会调用它，
    // 从而丢掉半截的按下状态而不是让它们污染后续窗口。
    private func clearTransientClocks() {
        pressed.removeAll()
        lastDownAt = nil
        lastPointerAt = nil
        lastPointerVector = nil
    }

    private func acceptTime(_ time: Double) -> Bool {
        guard time.isFinite, time >= startedAt, lastEventAt.map({ time >= $0 }) ?? true else {
            clearTransientClocks()
            return false
        }
        lastEventAt = time
        return true
    }

    private func append(_ value: Double, to array: inout [Double], seen: inout Int) {
        guard value.isFinite, seen < Int.max else { return }
        seen += 1
        if array.count < TimingFeatureAccumulator.maxSamples { array.append(value); return }
        let index = Int.random(in: 0..<seen)
        if index < array.count { array[index] = value }
    }
}
