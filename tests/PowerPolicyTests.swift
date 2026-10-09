// R01：低电量模式与热状态的降级档。通知 → 档的映射，以及「交互中不降」。
import Foundation

private final class StateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var low = false
    private var thermal = ProcessInfo.ThermalState.nominal
    func set(low: Bool, thermal: ProcessInfo.ThermalState) { lock.withLock { self.low = low; self.thermal = thermal } }
    func read() -> (Bool, ProcessInfo.ThermalState) { lock.withLock { (low, thermal) } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    private var last = ""
    func hit(_ tier: String) { lock.withLock { n += 1; last = tier } }
    var snapshot: (Int, String) { lock.withLock { (n, last) } }
}

@main @MainActor
struct PowerPolicyTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static func main() {
        // 纯映射
        typealias R = PowerPolicyRules
        expect(R.tier(lowPowerMode: false, thermal: .nominal) == .normal, "平时是 normal")
        expect(R.tier(lowPowerMode: false, thermal: .fair) == .normal, "fair 不降")
        expect(R.tier(lowPowerMode: true, thermal: .nominal) == .lowPower, "低电量模式是 lowPower")
        expect(R.tier(lowPowerMode: true, thermal: .fair) == .lowPower, "低电量加 fair 仍是 lowPower")
        expect(R.tier(lowPowerMode: false, thermal: .serious) == .hot, "serious 是 hot")
        expect(R.tier(lowPowerMode: false, thermal: .critical) == .hot, "critical 是 hot")
        expect(R.tier(lowPowerMode: true, thermal: .serious) == .hot, "热状态优先于低电量")

        // 消费方参数
        expect(R.pinnedFPS(tier: .normal, interactive: false) == 15, "normal 置顶空闲 15")
        expect(R.pinnedFPS(tier: .lowPower, interactive: false) == 10, "lowPower 置顶空闲 10")
        expect(R.pinnedFPS(tier: .hot, interactive: false) == 10, "hot 置顶空闲 10")
        for tier in [PowerTier.normal, .lowPower, .hot] {
            expect(R.pinnedFPS(tier: tier, interactive: true) == 30, "交互中不降（\(tier.rawValue)）")
        }
        expect(R.lidDesktopFPS(tier: .normal, animating: true) == 60, "normal 合盖动画 60")
        expect(R.lidDesktopFPS(tier: .lowPower, animating: true) == 60, "lowPower 合盖动画仍 60")
        expect(R.lidDesktopFPS(tier: .hot, animating: true) == 30, "hot 合盖动画 30")
        for tier in [PowerTier.normal, .lowPower, .hot] {
            expect(R.lidDesktopFPS(tier: tier, animating: false) == 15, "合盖静止 15（\(tier.rawValue)）")
        }
        expect(!R.deferLaunchpadWarmUp(tier: .normal), "normal 照常预热")
        expect(R.deferLaunchpadWarmUp(tier: .lowPower) && R.deferLaunchpadWarmUp(tier: .hot), "非 normal 推迟预热")

        // 通知 → 档：用独立的通知中心，不碰系统状态
        let system = NotificationCenter()
        let events = NotificationCenter()
        let box = StateBox()
        let counter = Counter()
        let token = events.addObserver(forName: PowerPolicy.tierDidChange, object: nil, queue: nil) { note in
            counter.hit(note.userInfo?["tier"] as? String ?? "?")
        }
        let policy = PowerPolicy(center: events, systemCenter: system, readState: { box.read() })
        expect(policy.tier == .normal, "起始档来自当前状态")

        box.set(low: true, thermal: .nominal)
        system.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        expect(policy.tier == .lowPower, "电源状态通知 → lowPower")
        expect(counter.snapshot == (1, "lowPower"), "档变了发一次通知")

        system.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        expect(counter.snapshot.0 == 1, "档没变不重复通知")

        box.set(low: true, thermal: .serious)
        system.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        expect(policy.tier == .hot, "热状态通知 → hot")

        box.set(low: false, thermal: .nominal)
        system.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        expect(policy.tier == .normal, "恢复后回到 normal")
        expect(counter.snapshot == (3, "normal"), "三次变化三次通知")
        events.removeObserver(token)

        if failures > 0 { print("\(failures) 项失败"); exit(1) }
        print("全部通过")
    }
}
