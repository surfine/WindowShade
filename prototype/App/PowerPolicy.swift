import Foundation
import Synchronization

/// 低电量模式与热状态的降级档（R01）。只给「看不出来的参数」让路，交互期间不降。
///
/// 三档：
/// - `normal`：什么都不变，和没有这个文件时完全一样。
/// - `lowPower`：系统开了低电量模式。置顶非交互帧率 15→10；启动台预热推迟到第一次打开。
/// - `hot`：系统热状态 serious / critical。同上，另外合盖桌面流 60→30。
/// 热状态优先于低电量。倒数、放行、交互中的 30fps 都不受这个档影响。
enum PowerTier: String, Sendable, Equatable {
    case normal, lowPower, hot
}

/// 纯映射：测试直接喂参数，不碰系统状态。
enum PowerPolicyRules {
    static func tier(lowPowerMode: Bool, thermal: ProcessInfo.ThermalState) -> PowerTier {
        switch thermal {
        case .serious, .critical: return .hot
        default: return lowPowerMode ? .lowPower : .normal
        }
    }

    /// 置顶预览的目标帧率。交互中（拖动、动画进行中）永远 30，不降。
    static func pinnedFPS(tier: PowerTier, interactive: Bool) -> Int {
        if interactive { return 30 }
        return tier == .normal ? 15 : 10
    }

    /// 合盖桌面流：有动画时 60，热了降到 30；静止时仍是 15。
    static func lidDesktopFPS(tier: PowerTier, animating: Bool) -> Int {
        guard animating else { return 15 }
        return tier == .hot ? 30 : 60
    }

    /// 启动台后台预热：非 normal 档推迟到第一次打开。
    static func deferLaunchpadWarmUp(tier: PowerTier) -> Bool { tier != .normal }
}

/// 监听系统通知，对外给当前档。只听通知，不轮询；档变了才发 `tierDidChange`。
final class PowerPolicy: @unchecked Sendable {
    static let shared = PowerPolicy()
    static let tierDidChange = Notification.Name("WindowShade.PowerPolicy.tierDidChange")

    // 规格 M3：档位进 Mutex；observers 仍是可变属性，@unchecked Sendable 保留。
    private let currentTier: Mutex<PowerTier>
    private var observers: [NSObjectProtocol] = []
    private let center: NotificationCenter
    private let readState: @Sendable () -> (Bool, ProcessInfo.ThermalState)

    init(center: NotificationCenter = .default,
         systemCenter: NotificationCenter = .default,
         readState: @escaping @Sendable () -> (Bool, ProcessInfo.ThermalState) = {
             (ProcessInfo.processInfo.isLowPowerModeEnabled, ProcessInfo.processInfo.thermalState)
         }) {
        self.center = center
        self.systemCenter = systemCenter
        self.readState = readState
        let (low, thermal) = readState()
        currentTier = Mutex(PowerPolicyRules.tier(lowPowerMode: low, thermal: thermal))
        let names: [Notification.Name] = [.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification]
        observers = names.map { name in
            systemCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.refresh() }
        }
    }

    private let systemCenter: NotificationCenter

    deinit { observers.forEach { systemCenter.removeObserver($0) } }

    var tier: PowerTier { currentTier.withLock { $0 } }

    /// 重读系统状态；档变了才发通知。通知回调和测试都走这里。
    func refresh() {
        let (low, thermal) = readState()
        let next = PowerPolicyRules.tier(lowPowerMode: low, thermal: thermal)
        let changed = currentTier.withLock { current -> Bool in
            guard next != current else { return false }
            current = next
            return true
        }
        if changed { center.post(name: Self.tierDidChange, object: self, userInfo: ["tier": next.rawValue]) }
    }
}
