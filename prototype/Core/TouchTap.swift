import Foundation

/// 一台设备的完整接触组识别。bridge 必须提供毫米和平方毫米；单位不明时不要调用。
struct TouchTap: Sendable {
    enum Device: Sendable { case trackpad, magicMouse }
    enum Phase: Sendable { case began, moved, stationary, ended, cancelled }
    struct Contact: Sendable {
        let id: Int64
        let pointMM: WS2.Point
        let areaMM2: Double
        let phase: Phase
    }
    enum Tap: Equatable, Sendable { case threeFingers, fourFingers }
    struct Output: Equatable, Sendable {
        let tap: Tap?
        let twoFingersDown: Bool
        let cancelled: Bool
        let fault: WS2.Fault?
    }
    private struct Slot: Sendable {
        var id: Int64 = 0
        var used = false
        var active = false
        var origin = WS2.Point(x: 0, y: 0)
    }
    static let maxContacts = 16
    static let simultaneous: UInt64 = 150 * WS2.Duration.millisecond
    static let maximumDuration: UInt64 = 250 * WS2.Duration.millisecond
    static let maximumTravelMM = 1.5
    /// 推荐探针起点，未实测。只有 bridge 证实面积单位是 mm² 后才可启用。
    static let palmAreaMM2 = 140.0
    private var slots = Array(repeating: Slot(), count: maxContacts)
    private var startedAt: WS2.Instant?
    private var poisoned = false
    private var gate = WS2.EventGate()
    let device: Device
    init(device: Device) { self.device = device }

    /// 数组便捷入口供测试使用。实时桥应使用下方借用缓冲区入口，避免逐帧构造数组。
    mutating func frame(_ contacts: [Contact], sequence: UInt64, at now: WS2.Instant) -> Output {
        contacts.withUnsafeBufferPointer { frame($0, sequence: sequence, at: now) }
    }
    /// 本调用不保留指针。上限固定 16，预分配存储由单个串行线程独占，不复制状态给渲染线程。
    mutating func frame(_ contacts: UnsafeBufferPointer<Contact>, sequence: UInt64, at now: WS2.Instant) -> Output {
        guard gate.accept(sequence: sequence, at: now) else {
            return Output(tap: nil, twoFingersDown: false, cancelled: true, fault: .sequenceReplayed)
        }
        guard contacts.count <= Self.maxContacts else { poisoned = true; return bad(.capacityExceeded) }
        if contacts.isEmpty {
            let wasIncomplete = slots.contains(where: { $0.active }) || poisoned
            reset()
            return Output(tap: nil, twoFingersDown: false, cancelled: wasIncomplete, fault: nil)
        }
        for i in contacts.indices {
            let c = contacts[i]
            guard c.pointMM.isFinite, c.areaMM2.isFinite, c.areaMM2 > 0,
                  c.areaMM2 < Self.palmAreaMM2, c.phase != .cancelled else { poisoned = true; return bad(nil) }
            for j in contacts.indices where j < i {
                if contacts[j].id == c.id { poisoned = true; return bad(.malformedInput) }
            }
        }
        if device == .magicMouse {
            var active = 0
            for c in contacts where c.phase != .ended { active += 1 }
            // 两指按下是持续弦键，不受轻点 250ms 的时限约束。
            return Output(tap: nil, twoFingersDown: !poisoned && active == 2, cancelled: poisoned, fault: nil)
        }
        if poisoned { return bad(nil) }
        // 快照必须包含上帧仍活动的所有触点（含本帧 ended）；静默丢点不当成抬手。
        for slot in slots where slot.active {
            if !contacts.contains(where: { $0.id == slot.id }) { poisoned = true; return bad(nil) }
        }
        for c in contacts {
            let index: Int
            if let existing = slots.firstIndex(where: { $0.used && $0.id == c.id }) {
                index = existing
                guard slots[index].active, c.phase != .began else { poisoned = true; return bad(nil) }
            } else {
                guard c.phase == .began, let free = slots.firstIndex(where: { !$0.used }) else {
                    poisoned = true; return bad(nil)
                }
                if let start = startedAt, now.elapsed(since: start) > Self.simultaneous {
                    poisoned = true; return bad(nil)
                }
                if startedAt == nil { startedAt = now }
                index = free
                slots[index] = Slot(id: c.id, used: true, active: true, origin: c.pointMM)
            }
            let dx = c.pointMM.x - slots[index].origin.x, dy = c.pointMM.y - slots[index].origin.y
            guard hypot(dx, dy) < Self.maximumTravelMM else { poisoned = true; return bad(nil) }
            if c.phase == .ended { slots[index].active = false }
        }
        guard let start = startedAt, now.elapsed(since: start) <= Self.maximumDuration else {
            poisoned = true; return bad(nil)
        }
        if slots.contains(where: { $0.active }) { return Output(tap: nil, twoFingersDown: false, cancelled: false, fault: nil) }
        let count = slots.reduce(0) { $0 + ($1.used ? 1 : 0) }
        let tap: Tap? = count == 3 ? .threeFingers : count == 4 ? .fourFingers : nil
        reset()
        return Output(tap: tap, twoFingersDown: false, cancelled: tap == nil, fault: nil)
    }
    mutating func cancel() { poisoned = true }
    private mutating func reset() {
        for i in slots.indices { slots[i] = Slot() }
        startedAt = nil; poisoned = false
    }
    private func bad(_ fault: WS2.Fault?) -> Output {
        Output(tap: nil, twoFingersDown: false, cancelled: true, fault: fault)
    }
}
