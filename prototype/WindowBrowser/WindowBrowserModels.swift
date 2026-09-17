// 窗口浏览功能的值类型与不依赖真实系统的纯逻辑。
//
// 这里不引用 NSRunningApplication、AXUIElement、NSWindow 或任何系统会话对象，
// 只表达“哪个窗口、来自哪个应用运行实例、状态是什么、要执行什么动作、结果如何”。
// 真实 AX/CG 引用由 WindowBrowserController 侧的受限映射持有。

import Foundation
import CoreGraphics

// MARK: - 身份

/// 应用运行实例身份。PID 会被系统复用，因此 PID 必须和本进程分配的实例代数
/// 一起使用；应用终止后重新出现即使 PID 相同也会得到新的代数。
struct ApplicationInstanceKey: Hashable, Comparable {
    let pid: pid_t
    let generation: UInt64

    static func < (lhs: ApplicationInstanceKey, rhs: ApplicationInstanceKey) -> Bool {
        if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
        return lhs.generation < rhs.generation
    }
}

/// 窗口身份。`CGWindowID` 只在本会话内稳定，窗口销毁后同一数字 ID 可能被复用，
/// 因此必须带上本会话分配的窗口代数。
struct WindowKey: Hashable, Comparable {
    let application: ApplicationInstanceKey
    let originalWindowID: CGWindowID
    let windowGeneration: UInt64

    static func < (lhs: WindowKey, rhs: WindowKey) -> Bool {
        if lhs.application != rhs.application { return lhs.application < rhs.application }
        if lhs.originalWindowID != rhs.originalWindowID {
            return lhs.originalWindowID < rhs.originalWindowID
        }
        return lhs.windowGeneration < rhs.windowGeneration
    }
}

/// 目录查询/动作请求代数。每次新面板会话、每次切换目标应用都递增。
struct WindowBrowserRequestID: Hashable, Comparable {
    let value: UInt64

    static func < (lhs: WindowBrowserRequestID, rhs: WindowBrowserRequestID) -> Bool {
        lhs.value < rhs.value
    }
}

/// 当前面板会话的所有者令牌：请求代数 + 目标应用实例 + 目标代数。
/// 异步结果回来时三者都要核对；仅核对 PID 不够，A→B→A 的旧结果必须被挡住。
struct WindowBrowserTargetToken: Hashable {
    let requestID: WindowBrowserRequestID
    let application: ApplicationInstanceKey?
    let targetGeneration: UInt64

    func accepts(application: ApplicationInstanceKey, targetGeneration: UInt64) -> Bool {
        guard let current = self.application else { return false }
        return current == application && self.targetGeneration == targetGeneration
    }
}

// MARK: - 状态与能力

enum WindowBrowserDiscoveryConfidence: Int, Comparable {
    case provisional = 0
    case inferred = 1
    case confirmed = 2

    static func < (lhs: WindowBrowserDiscoveryConfidence, rhs: WindowBrowserDiscoveryConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum WindowBrowserSystemVisibility: String {
    case onScreen
    case offScreen
    case minimized
    case applicationHidden
    case unknown
}

enum WindowBrowserShadeState: String {
    case normal
    case folded
    case restoring
    case unknown
}

enum WindowBrowserPinState: String {
    case none
    case running
    case suspended
    case unknown
}

enum WindowBrowserPlacementSource: String {
    case managedFold
    case managedPin
    case liveDiscovery
    case recoveryJournal
    case unavailable
}

struct WindowBrowserCapabilities: OptionSet, Hashable {
    let rawValue: Int

    static let activate = WindowBrowserCapabilities(rawValue: 1 << 0)
    static let fold = WindowBrowserCapabilities(rawValue: 1 << 1)
    static let unfold = WindowBrowserCapabilities(rawValue: 1 << 2)
    static let pinPreview = WindowBrowserCapabilities(rawValue: 1 << 3)
    static let unpinPreview = WindowBrowserCapabilities(rawValue: 1 << 4)
    static let close = WindowBrowserCapabilities(rawValue: 1 << 5)
    static let minimize = WindowBrowserCapabilities(rawValue: 1 << 6)
    static let capture = WindowBrowserCapabilities(rawValue: 1 << 7)

    static let managedWindow: WindowBrowserCapabilities = [
        .activate, .fold, .unfold, .pinPreview, .unpinPreview, .close, .minimize
    ]
    static let discoveredWindow: WindowBrowserCapabilities = [
        .activate, .fold, .pinPreview, .close, .minimize, .capture
    ]
}

// MARK: - 记录

/// 目录里的只读投影。它的状态不代表所有权：真实折叠状态仍在原控制器，
/// 真实置顶状态仍在 PinnedPreviewController。
struct WindowRecord: Equatable {
    let key: WindowKey
    var bundleIdentifier: String
    var appName: String
    var title: String
    /// 统一 Cocoa 全局 point 坐标。
    var logicalFrame: CGRect?
    var placementSource: WindowBrowserPlacementSource
    var systemVisibility: WindowBrowserSystemVisibility
    var shadeState: WindowBrowserShadeState
    var pinState: WindowBrowserPinState
    var capabilities: WindowBrowserCapabilities
    var confidence: WindowBrowserDiscoveryConfidence
    var metadataRevision: UInt64
    var isMinimized: Bool
    var isOnScreen: Bool
    /// 折叠窗口在屏外停车，但逻辑位置来自标题条恢复位置，筛选显示器要用它。
    var isFoldedOffscreen: Bool
    /// 该记录是否来自本次会话的普通窗口枚举；已管理窗口即使暂时枚举不到也要保留。
    var isManaged: Bool

    var displayTitle: String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? appName : clean
    }

    var sortAppName: String { WindowBrowserSearch.normalize(appName) }
    var sortTitle: String { WindowBrowserSearch.normalize(displayTitle) }
}

/// 折叠会话/置顶会话提供的只读快照。只描述原窗口，不携带可修改句柄。
struct ManagedWindowDescriptor {
    let pid: pid_t
    let bundleIdentifier: String
    let appName: String
    let originalWindowID: CGWindowID
    let title: String
    let logicalFrame: CGRect?
    let systemVisibility: WindowBrowserSystemVisibility
    let shadeState: WindowBrowserShadeState
    let pinState: WindowBrowserPinState
    let isMinimized: Bool
    let isOnScreen: Bool
    let placementSource: WindowBrowserPlacementSource
    let capabilities: WindowBrowserCapabilities
    let confidence: WindowBrowserDiscoveryConfidence
}

/// 普通窗口发现结果。标题/几何/可见性可能来自 AX 或 CG，两者信息不完整时
/// 允许字段为空，由目录按优先级合并。
struct DiscoveredWindowDescriptor {
    let pid: pid_t
    let bundleIdentifier: String?
    let appName: String?
    let originalWindowID: CGWindowID
    let title: String?
    let frame: CGRect?
    let isOnScreen: Bool
    let isMinimized: Bool
    let capabilities: WindowBrowserCapabilities
    let confidence: WindowBrowserDiscoveryConfidence
}

/// 一次枚举的四种终态。失败不能被当成空数组发布。
enum WindowBrowserFetchResult<Value> {
    case success(Value)
    case empty
    case partial(Value, failures: [pid_t])
    case failure(reason: String)
    case timedOut(previous: Value)
}

// MARK: - 动作

enum WindowBrowserAction: String, CaseIterable {
    case activate
    case fold
    case unfold
    case pinPreview
    case unpinPreview
    case close
    case minimize
}

enum WindowBrowserActionOutcome: Equatable {
    case completed
    case awaitingUser(reason: String)
    case unsupported(reason: String)
    case permissionRequired(kind: WindowBrowserPermissionKind)
    case targetGone
    case busy
    case failed(reason: String)
    case uncertain(reason: String)

}

enum WindowBrowserPermissionKind: String, Equatable {
    case accessibility
    case screenRecording
}

enum WindowBrowserPanelMode: String {
    case dock
    case keyboard
}

// MARK: - 面板状态机

enum WindowBrowserTemporaryPanelState: Equatable {
    case hidden(WindowBrowserRequestID?)
    case pendingShow(WindowBrowserRequestID)
    case visible(WindowBrowserRequestID)
    case pendingHide(WindowBrowserRequestID)
    case interacting(WindowBrowserRequestID)

    var requestID: WindowBrowserRequestID? {
        switch self {
        case .hidden(let token): return token
        case .pendingShow(let token), .visible(let token),
             .pendingHide(let token), .interacting(let token):
            return token
        }
    }

}

/// 临时面板的显式状态机。每个状态都携带当前请求 token，旧会话的异步回调必须被拒绝。
/// 纯逻辑，便于用可推进时钟与替身直接测试。
struct WindowBrowserPanelStateMachine {
    private(set) var state: WindowBrowserTemporaryPanelState = .hidden(nil)

    /// 收到新的显示请求（Dock 目标或键盘面板打开）。
    mutating func beginShow(request: WindowBrowserRequestID) -> Bool {
        switch state {
        case .hidden, .pendingHide:
            state = .pendingShow(request)
            return true
        case .pendingShow, .visible, .interacting:
            // 同一 token 重复请求忽略；换了 token 就替换（Dock 图标切换）。
            guard currentRequest != request else { return false }
            state = .pendingShow(request)
            return true
        }
    }

    /// 面板真正出现在屏幕上。
    mutating func confirmShow(request: WindowBrowserRequestID) -> Bool {
        guard currentRequest == request else { return false }
        switch state {
        case .pendingShow, .pendingHide:
            // pendingHide 说明一次隐藏检查已经排过但当时鼠标仍在内；此时面板确实
            // 出现在屏幕上，回到 visible 更准确，后续隐藏仍由排程的工作项决定。
            state = .visible(request)
            return true
        case .visible, .interacting:
            return false
        case .hidden:
            return false
        }
    }

    /// 开始离开延迟（鼠标离开图标/面板，或 Dock 清除目标）。
    mutating func beginHide(request: WindowBrowserRequestID) -> Bool {
        guard currentRequest == request else { return false }
        switch state {
        case .visible, .pendingShow, .pendingHide:
            // pendingHide 允许重复排程（幂等）：否则一次“鼠标仍在内”的检查会让
            // 状态卡在 pendingHide，之后再也排不出隐藏。
            state = .pendingHide(request)
            return true
        case .interacting:
            // 交互中不启动隐藏：由 endInteraction 之后再判断。
            return false
        case .hidden:
            return false
        }
    }

    /// 鼠标重新进入图标/面板：取消待隐藏。
    mutating func cancelHide(request: WindowBrowserRequestID) -> Bool {
        guard currentRequest == request else { return false }
        guard case .pendingHide = state else { return false }
        state = .visible(request)
        return true
    }

    /// 鼠标进入面板内部。
    mutating func beginInteraction(request: WindowBrowserRequestID) -> Bool {
        guard currentRequest == request else { return false }
        switch state {
        case .visible, .pendingHide:
            state = .interacting(request)
            return true
        case .pendingShow, .interacting, .hidden:
            return false
        }
    }

    /// 鼠标离开面板内部。
    mutating func endInteraction(request: WindowBrowserRequestID) -> Bool {
        guard currentRequest == request, case .interacting = state else { return false }
        state = .visible(request)
        return true
    }

    /// 面板已关闭 / 会话结束。
    mutating func reset() {
        state = .hidden(nil)
    }

    /// 关闭回调、延迟工作项等异步结果是否仍属于当前会话。
    func accepts(_ request: WindowBrowserRequestID) -> Bool {
        currentRequest == request
    }

    var currentRequest: WindowBrowserRequestID? { state.requestID }
}

// MARK: - 搜索

enum WindowBrowserSearch {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matches(query: String, record: WindowRecord) -> Bool {
        let needle = normalize(query)
        guard !needle.isEmpty else { return true }
        return normalize(record.appName).contains(needle)
            || normalize(record.displayTitle).contains(needle)
    }

    /// 已经规范化过的查询串复用版本：面板在每次刷新过滤几十条记录时只折叠一次查询。
    static func matches(normalizedQuery needle: String, record: WindowRecord) -> Bool {
        guard !needle.isEmpty else { return true }
        return normalize(record.appName).contains(needle)
            || normalize(record.displayTitle).contains(needle)
    }
}

/// 自有实时流异步启动成功后的保留判断：任何一项不成立都必须立即停掉刚建好的流，
/// 不能留下无人引用的孤儿捕获。
enum WindowBrowserLivePreviewPolicy {
    static func shouldKeepStartedStream(leaseIsCurrent: Bool,
                                        cancelled: Bool,
                                        sessionActive: Bool,
                                        targetStillKnown: Bool) -> Bool {
        leaseIsCurrent && !cancelled && sessionActive && targetStillKnown
    }
}

/// 实时预览租约的所有权与重试纪律。
/// 一个异步任务只能清理自己的资源：旧租约的失败、超时、找不到来源分支
/// 都不能释放当前已经换成的新租约。
enum WindowBrowserLiveLeasePolicy {
    /// 只有当前持有的租约才能执行“清空画面”的全局清理。
    static func ownsGlobalRelease(currentLeaseID: UUID?, releasingLeaseID: UUID) -> Bool {
        guard let currentLeaseID else { return false }
        return currentLeaseID == releasingLeaseID
    }

    /// 自动重试预算：不超过上限，且没有明确不可重试的原因。
    static func retryPermitted(failureCount: Int, blocked: Bool, maxRetries: Int) -> Bool {
        guard !blocked else { return false }
        return failureCount <= maxRetries
    }

    /// 权限拒绝、源消失或能力明确不支持时直接停止自动重试。
    static func failureBlocksRetry(reason: String) -> Bool {
        let lower = reason.lowercased()
        return lower.contains("permission") || lower.contains("denied")
            || lower.contains("not authorized") || lower.contains("no-sc-window")
            || lower.contains("unsupported")
    }
}

/// 明确目标的身份判定：只由“元素所属 PID + 元素对应的原窗口 ID”决定。
/// 函数不接受也不读取当前焦点窗口，因此焦点切到别的窗口/应用时不会改变判定结果，
/// 也不会把动作指向焦点窗口。
enum WindowBrowserTargetIdentity {
    static func matches(elementPID: pid_t, elementWindowID: CGWindowID?,
                        expectedPID: pid_t, expectedWindowID: CGWindowID) -> Bool {
        guard expectedPID > 0, expectedWindowID != 0 else { return false }
        return elementPID == expectedPID && elementWindowID == expectedWindowID
    }
}

/// 异步元数据/图片结果的接收条件：功能仍开启、面板会话仍是同一个请求代数、
/// 目标应用实例没有被终止后复用。任何一项不成立都必须丢弃结果，不能发布。
enum WindowBrowserRequestValidity {
    static func accepts(running: Bool,
                        featureEnabled: Bool,
                        sessionRequestID: WindowBrowserRequestID?,
                        resultRequestID: WindowBrowserRequestID,
                        expectedAppInstance: ApplicationInstanceKey?,
                        currentAppInstance: ApplicationInstanceKey?) -> Bool {
        guard running, featureEnabled, sessionRequestID == resultRequestID else { return false }
        if let expectedAppInstance {
            // 键盘面板（expectedAppInstance == nil）面向所有应用；Dock 面板必须仍是
            // 同一个应用运行实例，PID 复用后的旧结果一律丢弃。
            return expectedAppInstance == currentAppInstance
        }
        return true
    }
}

/// 关闭键盘面板时是否把焦点归还给打开前的应用。
/// 只有“面板确实暂时取得焦点”且“用户没有点击其他应用（我们仍是前台）”时才归还，
/// 避免无条件下重新激活打开前的应用。
enum WindowBrowserFocusReturnPolicy {
    static func shouldReturnFocus(previousAppPID: pid_t?,
                                  ownPID: pid_t,
                                  currentFrontmostPID: pid_t?,
                                  mode: WindowBrowserPanelMode,
                                  panelWasKeyWindow: Bool) -> Bool {
        guard mode == .keyboard, panelWasKeyWindow else { return false }
        guard let previousAppPID, previousAppPID != ownPID else { return false }
        return currentFrontmostPID == ownPID
    }
}

/// 收到“打开键盘面板”请求时该怎么处理已存在的面板。
enum WindowBrowserOpenAction: Equatable {
    case create
    case focusExisting
    case replaceExisting
}

/// Dock 悬停目标到达时的会话决策：把“应用身份变化”和“同一应用的图标几何变化”
/// 明确分开，控制器不再用一个 `changed` 布尔值同时表示两件事。
enum WindowBrowserDockSessionDecision: Equatable {
    /// 换应用（或从键盘面板切回来）：建立新的数据会话。
    case startNewSession
    /// 同一应用实例：只更新锚点与过渡区域，不清空选择、不重新发现窗口。
    case updateAnchorOnly
    /// 键盘面板正在使用：Dock 悬停不抢占。
    case ignore
}

/// 上下文菜单跟踪期间的面板状态：菜单仍然以面板为锚点，不能中途释放它。
/// 跟踪期间收到的关闭请求被延后，菜单结束后补执行一次。
struct WindowBrowserMenuTrackingState {
    private(set) var isTracking = false
    private(set) var deferredCloseReason: String?

    mutating func beginTracking() {
        isTracking = true
    }

    /// 跟踪期间收到关闭请求时返回 true（关闭被延后到菜单结束）。
    mutating func requestClose(reason: String) -> Bool {
        guard isTracking else { return false }
        deferredCloseReason = reason
        return true
    }

    /// 菜单结束：返回需要补执行的关闭原因。
    mutating func endTracking() -> String? {
        isTracking = false
        let reason = deferredCloseReason
        deferredCloseReason = nil
        return reason
    }
}

enum WindowBrowserDockSessionPolicy {
    static func decision(sessionMode: WindowBrowserPanelMode?,
                         sessionApplication: ApplicationInstanceKey?,
                         keyboardPanelVisible: Bool,
                         targetApplication: ApplicationInstanceKey)
        -> WindowBrowserDockSessionDecision {
        if sessionMode == .keyboard, keyboardPanelVisible { return .ignore }
        if sessionMode == .dock, sessionApplication == targetApplication {
            return .updateAnchorOnly
        }
        return .startNewSession
    }
}

enum WindowBrowserOpenPolicy {
    static func action(existingMode: WindowBrowserPanelMode?,
                       panelIsVisible: Bool) -> WindowBrowserOpenAction {
        guard let existingMode, panelIsVisible else { return .create }
        return existingMode == .keyboard ? .focusExisting : .replaceExisting
    }
}

// MARK: - 稳定列表与选择

/// 单个面板会话内的稳定顺序与选择。已有项目不因截图完成、标题变化或后台刷新
/// 而重排；新增项目按确定规则追加；删除按身份移除；选择保存 WindowKey 而不是下标。
struct WindowBrowserListState {
    private(set) var orderedKeys: [WindowKey] = []
    private(set) var selection: WindowKey?

    mutating func reconcile(records: [WindowRecord]) -> [WindowRecord] {
        let byKey = Dictionary(records.map { ($0.key, $0) }, uniquingKeysWith: { _, new in new })
        var next = orderedKeys.filter { byKey[$0] != nil }
        let existing = Set(next)
        // 新增项排序同样只算一次规范化字符串，不让比较器反复折叠。
        let additions = records
            .filter { !existing.contains($0.key) }
            .map { (key: $0.key, app: $0.sortAppName, title: $0.sortTitle) }
            .sorted { lhs, rhs in
                if lhs.app != rhs.app { return lhs.app < rhs.app }
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.key < rhs.key
            }
            .map(\.key)
        next.append(contentsOf: additions)

        if let selection, byKey[selection] == nil {
            self.selection = nearestReplacement(forRemoved: selection,
                                                previousOrder: orderedKeys,
                                                in: next)
        }
        orderedKeys = next
        if let selection, byKey[selection] == nil {
            self.selection = next.first
        }
        return next.compactMap { byKey[$0] }
    }

    /// 结果被搜索过滤后调用：选择项若不再可见，选择第一个有效结果。
    mutating func applyVisible(_ visibleKeys: [WindowKey]) {
        guard let selection else {
            self.selection = visibleKeys.first
            return
        }
        if !visibleKeys.contains(selection) {
            self.selection = visibleKeys.first
        }
    }

    mutating func select(_ key: WindowKey?) {
        guard let key else {
            selection = nil
            return
        }
        if orderedKeys.contains(key) { selection = key }
    }

    mutating func removeAll() {
        orderedKeys = []
        selection = nil
    }

    private func nearestReplacement(forRemoved removed: WindowKey,
                                    previousOrder: [WindowKey],
                                    in keys: [WindowKey]) -> WindowKey? {
        guard !keys.isEmpty else { return nil }
        guard let oldIndex = previousOrder.firstIndex(of: removed) else { return keys.first }
        if let later = keys.first(where: {
            (previousOrder.firstIndex(of: $0) ?? Int.max) > oldIndex
        }) {
            return later
        }
        return keys.last
    }
}

// MARK: - 身份分配器

/// 本进程内部的身份代数。纯逻辑，便于 fake 测试；不访问任何系统对象。
final class WindowIdentityAllocator {
    private let lock = NSLock()
    private var applicationInstances: [pid_t: (bundleIdentifier: String, key: ApplicationInstanceKey)] = [:]
    private var nextApplicationGeneration: UInt64 = 1
    private var windowGenerations: [ApplicationInstanceKey: [CGWindowID: UInt64]] = [:]
    private var nextWindowGeneration: UInt64 = 1

    func applicationInstance(pid: pid_t, bundleIdentifier: String) -> ApplicationInstanceKey {
        lock.lock()
        defer { lock.unlock() }
        if let existing = applicationInstances[pid] {
            // 元数据缺失（bundle ID 为空）时不要为同一个 PID 造出第二个应用实例；
            // 后到的可靠 bundle ID 只把现有实例补齐。
            if existing.bundleIdentifier == bundleIdentifier
                || bundleIdentifier.isEmpty
                || existing.bundleIdentifier.isEmpty {
                if existing.bundleIdentifier.isEmpty, !bundleIdentifier.isEmpty {
                    applicationInstances[pid] = (bundleIdentifier, existing.key)
                }
                return existing.key
            }
        }
        let key = ApplicationInstanceKey(pid: pid, generation: nextApplicationGeneration)
        nextApplicationGeneration &+= 1
        applicationInstances[pid] = (bundleIdentifier, key)
        return key
    }

    /// 应用终止：同一 PID 再次出现时分配新的应用实例。
    func noteApplicationTerminated(pid: pid_t) {
        lock.lock()
        if let existing = applicationInstances.removeValue(forKey: pid) {
            windowGenerations.removeValue(forKey: existing.key)
        }
        lock.unlock()
    }

    func windowKey(pid: pid_t, bundleIdentifier: String,
                   originalWindowID: CGWindowID) -> WindowKey {
        let application = applicationInstance(pid: pid, bundleIdentifier: bundleIdentifier)
        lock.lock()
        defer { lock.unlock() }
        if let existing = windowGenerations[application]?[originalWindowID] {
            return WindowKey(application: application,
                             originalWindowID: originalWindowID,
                             windowGeneration: existing)
        }
        let generation = nextWindowGeneration
        nextWindowGeneration &+= 1
        windowGenerations[application, default: [:]][originalWindowID] = generation
        return WindowKey(application: application,
                         originalWindowID: originalWindowID,
                         windowGeneration: generation)
    }

    /// 确证窗口销毁后才调用。同一数字 ID 再次出现会得到新的窗口代数，
    /// 旧图像与旧 AX 引用都不能被新窗口复用。
    func confirmWindowDestroyed(_ key: WindowKey) {
        lock.lock()
        windowGenerations[key.application]?.removeValue(forKey: key.originalWindowID)
        lock.unlock()
    }

    func confirmWindowDestroyed(pid: pid_t, bundleIdentifier: String,
                                originalWindowID: CGWindowID) {
        lock.lock()
        let application = applicationInstances[pid]?.key
        lock.unlock()
        guard let application else { return }
        let key = WindowKey(application: application,
                            originalWindowID: originalWindowID,
                            windowGeneration: 0)
        confirmWindowDestroyed(key)
    }

    func isCurrent(_ key: WindowKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return windowGenerations[key.application]?[key.originalWindowID] == key.windowGeneration
    }

    /// 仅用于测试与目录清理统计。
    func knownApplicationInstance(pid: pid_t) -> ApplicationInstanceKey? {
        lock.lock()
        defer { lock.unlock() }
        return applicationInstances[pid]?.key
    }
}
