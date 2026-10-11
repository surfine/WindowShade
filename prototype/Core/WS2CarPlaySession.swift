import Foundation

// 接收端会话的生命周期。纯状态契约：不开传输、不带凭据、不持有窗口状态，也不自己起计时器。
// 时间由接入层以单调秒数传入，事件驱动，空闲时不轮询（能耗不高于 1.0.15）。
// 工程做法参考 PlayPort / DiPlay / LIVI（GPL，只取思路，代码自写）。

/// 配件身份的来源。只有 Apple 签发的身份会被直连接受；提取出来的与用户自备的一律不进直连
/// （用户自备身份目前只允许出现在隔离探针与外部接收器路径里，App 不校验身份内容）。
enum WS2CarPlayIdentityProvenance: Equatable {
    case appleIssued
    case extracted
    /// 用户自己提供的身份文件。来源可信度未知，App 不基于它做直连授权。
    case userSupplied
    case unknown
}

/// 可插拔的配件身份接口。会话只看来源，不读也不存身份内容；真正的校验由接入层完成。
protocol WS2CarPlayAccessoryIdentity {
    var provenance: WS2CarPlayIdentityProvenance { get }
}

struct WS2CarPlayResolution: Equatable {
    var width: Int
    var height: Int
    var isValid: Bool { width > 0 && height > 0 }
}

/// 一次会话开始时固定下来的设置。串流中改动只记为待生效，下次重连才用。
struct WS2CarPlaySettings: Equatable {
    var resolution: WS2CarPlayResolution
    /// 刘海高度，单位与分辨率一致（串流像素），由接入层按缩放换算。
    var notchHeight: Double

    static let standard = WS2CarPlaySettings(
        resolution: WS2CarPlayResolution(width: 1280, height: 720), notchHeight: 0)
}

struct WS2CarPlayInsets: Equatable {
    var top: Double
    var left: Double
    var bottom: Double
    var right: Double
}

/// 两套边距：可视区是手机铺画面的范围；安全区在可视区之内，让交互内容避开刘海。
struct WS2CarPlayLayout: Equatable {
    var viewArea: WS2CarPlayInsets
    var safeArea: WS2CarPlayInsets

    init(notchHeight: Double) {
        let notch = notchHeight.isFinite ? max(0, notchHeight) : 0
        viewArea = WS2CarPlayInsets(top: 0, left: 0, bottom: 0, right: 0)
        safeArea = WS2CarPlayInsets(top: notch, left: 0, bottom: 0, right: 0)
    }
}

struct WS2CarPlayFrameCounters: Equatable {
    /// 解码端收到的帧数。
    var received = 0
    /// 画面显示出来时实际画出的帧数；验收拿它和 received 对比。
    var drawn = 0
}

struct WS2CarPlaySession {
    enum State: Equatable { case disconnected, missingIdentity, connecting, ready, waitingToReconnect, gaveUp }
    /// 没有 Apple 签发的身份时只能跑合成模式。
    enum Mode: Equatable { case synthetic, live }
    /// live 模式的认证放在哪：本机持 Apple 签发身份直连，或交给外部接收器（本机不读取、不保存身份）。
    enum LiveAuth: Equatable { case local, delegated }
    enum ReconnectPlan: Equatable {
        case none
        case retry(attempt: Int, after: TimeInterval)
        case gaveUp
    }
    struct Ticket: Equatable { fileprivate let id = UUID() }

    static let backoffBase: TimeInterval = 2
    static let backoffCap: TimeInterval = 30
    static let maxReconnectAttempts = 5
    static let stableDuration: TimeInterval = 60

    /// 第 n 次重连前的等待：2 s × 2^n，封顶 30 s。
    static func backoff(attempt n: Int) -> TimeInterval {
        min(backoffBase * pow(2, Double(min(max(n, 0), 10))), backoffCap)
    }

    private(set) var state: State = .disconnected
    private(set) var ticket: Ticket?
    private(set) var mode: Mode?
    /// 本次连接的认证位置；合成模式为 nil。断开后清空。
    private(set) var liveAuth: LiveAuth?
    private(set) var isFullscreen = false
    /// 本次连接开始时固定的设置；串流中不变。
    private(set) var activeSettings: WS2CarPlaySettings?
    /// 下次连接才会用的设置。
    private(set) var pendingSettings: WS2CarPlaySettings
    private(set) var reconnectAttempts = 0
    /// 下一次重连的最早时刻；接入层据此只起一个带容差的单次计时器。
    private(set) var reconnectDueAt: TimeInterval?
    private(set) var keyframeRequests = 0
    private(set) var frames = WS2CarPlayFrameCounters()
    private var wantsLive = false
    private var stableSince: TimeInterval?

    init(settings: WS2CarPlaySettings = .standard) { pendingSettings = settings }

    var layout: WS2CarPlayLayout? { activeSettings.map { WS2CarPlayLayout(notchHeight: $0.notchHeight) } }

    /// 连着外部接收器的 live 会话：真画面来自接收器，不在全屏里画示意方块。
    var isReceiverLive: Bool { mode == .live && liveAuth == .delegated }

    /// 串流中提交了不同的设置，要到下次重连才生效。
    var settingsChangePending: Bool {
        (state == .connecting || state == .ready) && activeSettings != pendingSettings
    }

    /// 只记下新设置，不动正在跑的会话。无效分辨率被拒绝。
    @discardableResult
    mutating func requestSettings(_ settings: WS2CarPlaySettings) -> Bool {
        guard settings.resolution.isValid else { return false }
        pendingSettings = settings
        return true
    }

    /// 用户发起的连接。wantsLive 为真时必须有 Apple 签发的身份，否则停在缺身份，不连。
    mutating func connect(identity: (any WS2CarPlayAccessoryIdentity)?, wantsLive: Bool = false) -> Ticket? {
        self.wantsLive = wantsLive
        liveAuth = wantsLive ? .local : nil
        reconnectAttempts = 0
        reconnectDueAt = nil
        return start(identity: identity)
    }

    /// 经外部接收器连真机：认证在接收器侧完成，本机不读取、不保存任何身份。
    mutating func connectViaReceiver() -> Ticket? {
        wantsLive = true
        liveAuth = .delegated
        reconnectAttempts = 0
        reconnectDueAt = nil
        return start(identity: nil)
    }

    mutating func becameReady(_ event: Ticket, at now: TimeInterval) {
        guard event == ticket, state == .connecting else { return }
        state = .ready
        stableSince = now
    }

    /// 稳定连接满 60 s 后清零重连计数。任何带时间的事件都会顺带结算，不需要定时轮询。
    mutating func observe(at now: TimeInterval) {
        guard state == .ready, let since = stableSince, now - since >= Self.stableDuration else { return }
        reconnectAttempts = 0
    }

    /// 连接结束。失败时按退避排下一次重连，用满 5 次就放弃；正常结束不重连。
    @discardableResult
    mutating func ended(_ event: Ticket, failed: Bool = false, at now: TimeInterval) -> ReconnectPlan {
        guard event == ticket else { return .none }
        observe(at: now)
        ticket = nil
        isFullscreen = false
        stableSince = nil
        guard failed else { state = .disconnected; return .none }
        guard reconnectAttempts < Self.maxReconnectAttempts else {
            state = .gaveUp
            reconnectDueAt = nil
            return .gaveUp
        }
        let delay = Self.backoff(attempt: reconnectAttempts)
        reconnectAttempts += 1
        reconnectDueAt = now + delay
        state = .waitingToReconnect
        return .retry(attempt: reconnectAttempts, after: delay)
    }

    /// 到点后由接入层调用；没到点或不在等待重连时什么也不做。重连用当时的待生效设置。
    mutating func reconnectIfDue(identity: (any WS2CarPlayAccessoryIdentity)?, at now: TimeInterval) -> Ticket? {
        guard state == .waitingToReconnect, let due = reconnectDueAt, now >= due else { return nil }
        reconnectDueAt = nil
        return start(identity: identity)
    }

    /// 显示 CarPlay 画面（长按刘海）。返回是否要向手机请求一个关键帧：每次显示只请求一次。
    @discardableResult
    mutating func enterFullscreen() -> Bool {
        guard state == .ready, !isFullscreen else { return false }
        isFullscreen = true
        keyframeRequests += 1
        return true
    }

    /// 回到桌面不断开手机。会话不记窗口，窗口都留在原处。
    mutating func exitFullscreen() { isFullscreen = false }

    mutating func frameReceived(_ event: Ticket) {
        guard event == ticket, state == .ready else { return }
        frames.received += 1
    }

    /// 只有画面显示着才算画出。
    mutating func frameDrawn(_ event: Ticket) {
        guard event == ticket, state == .ready, isFullscreen else { return }
        frames.drawn += 1
    }

    /// 用户主动断开：取消重连并清零计数。接入层还要自己停传输和媒体；作废票据会挡掉在途回调。
    mutating func disconnect() {
        ticket = nil
        state = .disconnected
        mode = nil
        liveAuth = nil
        isFullscreen = false
        reconnectAttempts = 0
        reconnectDueAt = nil
        stableSince = nil
    }

    private mutating func start(identity: (any WS2CarPlayAccessoryIdentity)?) -> Ticket? {
        ticket = nil
        isFullscreen = false
        stableSince = nil
        frames = WS2CarPlayFrameCounters()
        let delegated = liveAuth == .delegated
        if wantsLive, !delegated, identity?.provenance != .appleIssued {
            state = .missingIdentity
            mode = nil
            liveAuth = nil
            return nil
        }
        activeSettings = pendingSettings
        mode = wantsLive ? .live : .synthetic
        let next = Ticket()
        ticket = next
        state = .connecting
        return next
    }
}
