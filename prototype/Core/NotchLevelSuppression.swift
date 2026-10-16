// 要不要拦下音量、亮度、键盘灯键，把系统自己的提示藏起来（《音量与亮度》稿“藏起系统的提示：什么时候拦键”）。
//
// 一句话：拦键 = 能写 且 看得见 且 没有别的主人。三者缺一就不拦，按键原样交给系统。
// 拦下来的键由我们照系统的步长写回（NotchLevelStep），再画两耳；这里只做判定，不写任何数值、不碰 AppKit。
//
// 判定顺序（前面的先赢）：设置关 → 锁屏 → 放行 → 手势层 → 调度中心 → 全屏但面板看不见 →
// 别的 App 在管 → 改回用系统的提示 → 其它修饰键 → 设备不能调 → 亮度对着外接屏 → 监听被暂停 → 没允许辅助功能 →
// 版本没核对过 → 这一类键写回失败过 → 拦。

import Foundation

struct NotchLevelSuppression: Equatable, Sendable {
    /// 键盘监听现在的样子。
    enum Listener: Equatable, Sendable {
        /// 主动监听装好了，能拦。
        case active
        /// 只旁听（没允许辅助功能，或者没装上）：拦不了，系统的提示照出。
        case listenOnly
        /// 被系统暂停（回调超时、用户输入），收到 tapDisabledBy… 后会立刻重开；暂停期间不拦。
        case paused
    }

    /// 原生全屏桌面：面板在这张全屏桌面上真的可见（isOnActiveSpace 且未被遮挡）才算可见。查不到按“看不见”。
    enum FullScreen: Equatable, Sendable { case no, visible, notVisible }

    struct Input: Equatable, Sendable {
        /// 设置里“音量和亮度”开着。
        var settingEnabled = true
        /// 设置里“改回用系统的提示”开着（R12）：只旁听、不拦；系统的提示照出，刘海跟着画。
        var useSystemPopups = false
        var listener: Listener = .active
        /// 这个 macOS 版本核对过。
        var versionVerified = true
        /// Alcove、MediaMate、Atoll 等对方 App 在运行（foreignHUDIsRunning）。
        var foreignHUDRunning = false
        var locked = false
        var missionControl = false
        var fullScreen: FullScreen = .no
        /// 放行（刷脸解锁、等你批准）：不拦，系统的提示出来。
        var authorizationRelease = false
        /// 手势层里先来的手势（拖窗口到落点小岛、两指下拉刘海）：不拦。
        var gestureInFlight = false
        /// 这一类键要调的东西现在能调：音量是默认输出设备能不能调；亮度是有内建屏；键盘灯是读得到、写得进。
        var deviceAdjustable = true
        /// 亮度键要调的是外接屏（⌃ + 亮度键、合盖只用外接屏）。只对亮度键有意义。
        var brightnessTargetsExternal = false
        var modifiers: NotchLevelModifiers = .none

        init() {}
    }

    enum Action: Equatable, Sendable { case intercept, passThrough }
    enum Writer: Equatable, Sendable { case us, system, other }
    /// 这一下谁的提示看得见。
    enum Visible: Equatable, Sendable { case notchOnly, systemOnly, both, otherApp }

    enum Reason: Equatable, Sendable {
        case ready                   // 能写、看得见：拦
        case fullScreenVisible       // 原生全屏且面板可见：拦
        case settingOff
        case systemPopups            // 用户改回用系统的提示（R12）
        case locked                  // 锁屏、登录窗口、屏保
        case authorizationRelease
        case gestureInFlight
        case missionControl
        case fullScreenNotVisible    // 全屏但面板看不见：按调度中心处理
        case foreignHUD
        case otherModifiers          // 按着 ⌥、⇧、⌃、⌘ 但不是 ⌥⇧
        case outputNotAdjustable     // HDMI / DP、部分 USB 声卡、多输出设备
        case brightnessNotAdjustable
        case keyboardLightUnavailable
        case externalDisplay
        case listenerPaused
        case noAccessibility
        case versionNotVerified
        case writeFailedEarlier      // 这一类键本次开机写回失败过
        case processGone             // 崩溃或被强制退出：监听跟着进程没了
    }

    struct Decision: Equatable, Sendable {
        var action: Action
        var writer: Writer
        var visible: Visible
        var reason: Reason

        /// 刘海要不要画两耳。
        var notchDraws: Bool { visible == .notchOnly || visible == .both }
        var intercepts: Bool { action == .intercept }
    }

    /// WindowShade 崩溃或被强制退出：进程没了，谈不上判定；下一下就是系统的提示。
    static let processGone = Decision(action: .passThrough, writer: .system, visible: .systemOnly, reason: .processGone)

    /// 本次开机写回失败过的键类；失败过的不再拦（重启后清空，不落盘）。
    private(set) var failedKinds: Set<NotchLevelKind> = []

    init() {}

    func decide(_ kind: NotchLevelKind, _ input: Input) -> Decision {
        func system(_ reason: Reason) -> Decision {
            Decision(action: .passThrough, writer: .system, visible: .systemOnly, reason: reason)
        }
        func both(_ reason: Reason) -> Decision {
            Decision(action: .passThrough, writer: .system, visible: .both, reason: reason)
        }

        if !input.settingEnabled { return system(.settingOff) }
        if input.locked { return system(.locked) }
        if input.authorizationRelease { return system(.authorizationRelease) }
        if input.gestureInFlight { return system(.gestureInFlight) }
        if input.missionControl { return system(.missionControl) }
        if input.fullScreen == .notVisible { return system(.fullScreenNotVisible) }
        if input.foreignHUDRunning {
            return Decision(action: .passThrough, writer: .other, visible: .otherApp, reason: .foreignHUD)
        }
        // 放在锁屏、调度中心、别的 App 在管之后：那些情形刘海本来就不画，开关不该让它画出来。
        if input.useSystemPopups { return both(.systemPopups) }
        if input.modifiers == .other { return system(.otherModifiers) }
        if !input.deviceAdjustable {
            switch kind {
            case .volume: return system(.outputNotAdjustable)
            case .brightness: return system(.brightnessNotAdjustable)
            case .keyboardLight: return system(.keyboardLightUnavailable)
            }
        }
        if kind == .brightness, input.brightnessTargetsExternal { return system(.externalDisplay) }
        switch input.listener {
        case .paused: return both(.listenerPaused)
        case .listenOnly: return both(.noAccessibility)
        case .active: break
        }
        if !input.versionVerified { return both(.versionNotVerified) }
        if failedKinds.contains(kind) { return both(.writeFailedEarlier) }
        return Decision(action: .intercept, writer: .us, visible: .notchOnly,
                        reason: input.fullScreen == .visible ? .fullScreenVisible : .ready)
    }

    // MARK: 写回之后

    /// 写进去再读回来，对不对。
    enum Verification: Equatable, Sendable { case matched, mismatched }

    enum FollowUp: Equatable, Sendable {
        /// 写对了，两耳照常画。
        case done
        /// 写错了：这一下已经拦了，把原键标上记号补发给系统，监听认出记号放行；这一类键本次开机不再拦。
        case reissueToSystem
    }

    mutating func wrote(_ kind: NotchLevelKind, _ verification: Verification) -> FollowUp {
        switch verification {
        case .matched:
            return .done
        case .mismatched:
            failedKinds.insert(kind)
            return .reissueToSystem
        }
    }
}
