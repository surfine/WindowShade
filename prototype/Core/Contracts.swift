// WindowShade 2 · 第二轮共享合同草案 v1。原创实现。
// 只传递事实、输入和执行意图；不签发 AuthorizationGrant，也不执行系统动作。
import Foundation

/// 跨工作包共享的命名空间。不要另造同名的会话、按键或审批结构。
enum WS2 {
    /// 本进程连续时钟的纳秒。起点只在本进程有效，不能和远端时间、Date 或授权账绝对时钟混算。
    struct Instant: Hashable, Comparable, Sendable, Codable {
        let nanoseconds: UInt64
        init(nanoseconds: UInt64) { self.nanoseconds = nanoseconds }
        /// 仅作单位转换；拒绝负数、NaN、无穷和会溢出的输入。
        init?(seconds: Double) {
            guard seconds.isFinite, seconds >= 0,
                  seconds < Double(UInt64.max) / 1_000_000_000 else { return nil }
            nanoseconds = UInt64((seconds * 1_000_000_000).rounded(.down))
        }
        static let zero = Instant(nanoseconds: 0)
        static func < (a: Self, b: Self) -> Bool { a.nanoseconds < b.nanoseconds }
        /// 溢出时饱和到最大值，不把期限绕回过去。
        func adding(_ duration: UInt64) -> Self {
            let (value, overflow) = nanoseconds.addingReportingOverflow(duration)
            return Self(nanoseconds: overflow ? .max : value)
        }
        /// 非负经过时间。调用者必须先用 TimeGate 拒绝倒流。
        func elapsed(since earlier: Self) -> UInt64 {
            nanoseconds >= earlier.nanoseconds ? nanoseconds - earlier.nanoseconds : 0
        }
        var seconds: Double { Double(nanoseconds) / 1_000_000_000 }
    }

    /// 固定时长，单位为纳秒。值来自本轮决定表，不代表硬件实测。
    enum Duration {
        static let millisecond: UInt64 = 1_000_000
        static let second: UInt64 = 1_000_000_000
        static let minute: UInt64 = 60 * second
    }

    /// 所有纯 reducer 共用的时间检查器。相同时刻可以有多个有序事件。
    struct TimeGate: Sendable {
        private(set) var last: Instant?
        mutating func accept(_ now: Instant) -> Bool {
            guard last.map({ now >= $0 }) ?? true else { return false }
            last = now
            return true
        }
    }

    /// 同一宿主串行事件总线上的接收序号。UI、设备和后端共用编号域，允许未订阅事件造成空洞。
    /// 编号在本机入口分配，不能拿各设备自己的序号相互比较，也不能相信网络载荷自报。
    struct EventGate: Sendable {
        private(set) var lastSequence: UInt64 = 0
        private(set) var lastTime: Instant?
        mutating func accept(sequence: UInt64, at now: Instant) -> Bool {
            guard sequence > lastSequence, lastTime.map({ now >= $0 }) ?? true else { return false }
            lastSequence = sequence
            lastTime = now
            return true
        }
    }

    /// 每种独占 reducer 有不同编号域，防止番茄钟的1号与自动锁的1号撞号。
    enum TokenDomain: String, Hashable, Sendable, Codable { case unspecified, focusTimer, presenceLock, conductor, interaction }

    /// 不可复用的本地动作编号。bootID 在宿主启动时注入；serial 禁止回绕。
    /// 同一boot的每个domain只能有一个编号源；禁用/重开不能重建编号源。
    struct Token: Hashable, Sendable, Codable {
        let bootID: UUID
        let serial: UInt64
        let domain: TokenDomain
        init(bootID: UUID, serial: UInt64, domain: TokenDomain = .unspecified) {
            self.bootID = bootID; self.serial = serial; self.domain = domain
        }
    }

    /// 无随机副作用的编号源；只允许一个串行所有者使用。耗尽时必须停止发动作。
    struct TokenSource: Sendable {
        let bootID: UUID
        var domain: TokenDomain = .unspecified
        private(set) var serial: UInt64 = 0
        mutating func next() -> Token? {
            guard serial < UInt64.max else { return nil }
            serial += 1
            return Token(bootID: bootID, serial: serial, domain: domain)
        }
    }

    /// 助手身份。显示名称不参与会话匹配。
    enum Provider: String, Hashable, Sendable, Codable, CaseIterable {
        case claudeCode, codex
        var displayName: String { self == .codex ? "Codex" : "Claude" }
    }

    /// 助手与会话 ID 的组合键；同一目录里的两次会话不得合并。
    struct SessionKey: Hashable, Sendable, Codable {
        let provider: Provider
        let id: String
        var isValid: Bool { !id.isEmpty && id.utf8.count <= 512 }
    }

    /// 经宿主确认的执行上下文。peerID 是已配对公钥的本地索引，不是设备名称或 BLE 地址。
    struct Context: Hashable, Sendable, Codable {
        let peerID: String
        let projectID: String
        let session: SessionKey
        /// 本机接收器生成的连接代次；重连、撤销、锁屏后不能重用。
        let epoch: UInt64
        var isValid: Bool {
            !peerID.isEmpty && peerID.utf8.count <= 512 && !projectID.isEmpty &&
                projectID.utf8.count <= 4096 && session.isValid
        }
    }

    /// 任意异步事件的外壳。时间和序号由本机接收器填写，关联号按事件用途填写。
    struct Envelope<Payload: Sendable>: Sendable {
        let context: Context
        let sequence: UInt64
        let receivedAt: Instant
        let commandID: Token?
        let turnID: String?
        let payload: Payload
    }

    /// 安全摘要，恰好 32 字节。计算由受信适配器使用 CryptoKit 完成；这里不自制哈希。
    struct Digest: Hashable, Sendable, Codable {
        let bytes: Data
        init?(_ bytes: Data) {
            guard bytes.count == 32 else { return nil }
            self.bytes = bytes
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let data = try container.decode(Data.self)
            guard let value = Self(data) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "摘要必须为 32 字节")
            }
            self = value
        }
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(bytes)
        }
    }

    /// 模型的稳定身份。modelID 是协议里的实际请求值，不是 displayName 或列表位置。
    struct ModelID: Hashable, Sendable, Codable {
        let provider: Provider
        let modelID: String
    }

    /// 允许执行的实际配置。workflowID 只有在适配器明确实现并声明后才能非空。
    struct ExecutionConfig: Hashable, Sendable, Codable {
        let model: ModelID
        let effort: String
        let workflowID: String?
        let capabilityRevision: UInt64
    }

    /// 高开销确认绑定。草稿、最终配置、候选、连接和会话任一变化都让原票失效。
    struct CostBinding: Hashable, Sendable, Codable {
        let context: Context
        let candidateID: Token
        let config: ExecutionConfig
        let draftDigest: Digest
    }

    /// 风险不是授权。unknown 必须交回宿主或请求高风险确认，不能当 normal。
    enum Risk: String, Sendable, Codable { case normal, high, unknown }

    /// 保留 JSON-RPC request id 的类型和值，不能把整数 7 与字符串 "7" 合并。
    enum RequestID: Hashable, Sendable, Codable {
        case integer(Int64)
        case string(String)
    }

    /// 一次待审批请求的唯一键。会话、连接代次、请求号必须同时匹配。
    struct ApprovalKey: Hashable, Sendable, Codable {
        let session: SessionKey
        let epoch: UInt64
        let requestID: RequestID
    }

    /// 宿主给 UI 的审批事实。摘要由实际动作规范字节计算，summary 只供展示，不能做授权目标。
    struct ApprovalRequest: Equatable, Sendable {
        let key: ApprovalKey
        let context: Context
        let targetDigest: Digest
        let summary: String
        let risk: Risk
        let createdAt: Instant
        let deadline: Instant
        /// 审批可见时的接收序号。确认动作必须在这之后开始，不能只在这之后抬起。
        let shownAfterSequence: UInt64
        var isValid: Bool {
            context.isValid && key.session == context.session && key.epoch == context.epoch &&
                deadline > createdAt && !summary.isEmpty && summary.utf8.count <= 16_384
        }
    }

    /// 用户的意图；此类型故意没有 allow。confirm 只能转换成 AuthorizationIntent。
    enum ApprovalChoice: Sendable { case confirm, deny, returnToHost }

    /// 唯一授权服务要处理的请求。普通审批也不能绕过服务；voice 信息只能作附加证据。
    struct AuthorizationIntent: Equatable, Sendable {
        let request: ApprovalRequest
        let confirmationBeganAt: Instant
        let confirmationSequence: UInt64
        let auxiliaryVoicePassed: Bool
    }

    /// 已有授权服务发回的展示结果。dispatched 表示服务已经消费 grant 并送出应答；不是可执行的凭据。
    enum AuthorizationOutcome: Sendable {
        case dispatched(key: ApprovalKey, targetDigest: Digest)
        case denied(key: ApprovalKey)
        case cancelled(key: ApprovalKey)
    }

    /// 外部请求的非允许结局。deferToHost 是无决定，不是默认批准。
    enum ApprovalDisposition: String, Equatable, Sendable { case deny, deferToHost }

    /// 所有输入设备共用的按键，不省略独立的中心确认键。
    enum Button: String, Hashable, Sendable, CaseIterable {
        case up, down, left, right, select, back, tv, playPause, mute, power, side, volumeUp, volumeDown
    }

    /// 长按阈值事件只发一次。clickOnly 代表源协议确实没有阶段，不能伪造 down/up。
    enum ButtonPhase: String, Sendable { case down, up, cancel, heldHalfSecond, heldOneSecond, clickOnly }

    /// 一次按压的生命周期。pressID、beganAt 在按下后不变；长按后的 up 仍保留同一编号。
    struct ButtonEvent: Equatable, Sendable {
        let button: Button
        let phase: ButtonPhase
        let pressID: UInt64
        let beganAt: Instant
        let at: Instant
    }

    /// 统一坐标：x 向右、y 向上；normalized、毫米和屏幕点分别用不同结构传递。
    struct Point: Equatable, Sendable {
        let x: Double
        let y: Double
        var isFinite: Bool { x.isFinite && y.isFinite }
    }

    /// 跨输入设备的离散动作。动作执行和辅助功能查询留在 App 层，纯逻辑不得调用 CGEvent。
    enum Action: String, Equatable, Sendable {
        case focusUp, focusDown, focusLeft, focusRight, activateFocused, back
        case launchpad, notchShelf, missionControl, appWindows, windowBrowser, appSwitcher
        case spaceLeft, spaceRight, mediaPlayPause, mediaMute, volumeUp, volumeDown
        case displaySleepRequest, enterConductor, leaveConductor, tuckWindow, revealWindow
        case titlebarUp, titlebarDown, titlebarLeft, titlebarRight
    }

    /// 可见展示的六层仲裁。数字小的先占；授权不能塞进容量受限的普通活动表。
    enum Layer: Int, Comparable, Sendable, CaseIterable {
        case authorization = 1, interaction = 2, opened = 3, alert = 4, ongoing = 5, idle = 6
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// 显示器标识由宿主转换后注入，不拿显示器名称作键。
    struct DisplayID: Hashable, Comparable, Sendable, Codable {
        let value: UInt32
        static func < (a: Self, b: Self) -> Bool { a.value < b.value }
    }

    /// 运行错误必须可报告，但不夹带草稿、路径、窗口标题或设备密钥。
    enum Fault: String, Equatable, Sendable {
        case timeReversed, sequenceReplayed, staleContext, malformedInput, capacityExceeded
        case missingDependency, unsupportedCapability, generationExhausted
    }
}

/// 时钟注入接口。pure reducer 接收采样值，不自行调用此接口。
protocol WS2Clock: Sendable {
    func now() -> WS2.Instant
}

/// 本进程的 ContinuousClock 适配。睡眠期间继续推进；不持久化它的原点。
struct WS2ContinuousClock: WS2Clock, Sendable {
    private let origin: ContinuousClock.Instant
    init() { origin = ContinuousClock.now }
    func now() -> WS2.Instant {
        let components = origin.duration(to: ContinuousClock.now).components
        guard components.seconds >= 0 else { return .zero }
        let seconds = UInt64(components.seconds)
        let (whole, overflow) = seconds.multipliedReportingOverflow(by: WS2.Duration.second)
        guard !overflow else { return .init(nanoseconds: .max) }
        // Duration components 同号；纳秒以下的精度向下取整。
        let fraction = UInt64(max(0, components.attoseconds) / 1_000_000_000)
        return WS2.Instant(nanoseconds: whole).adding(fraction)
    }
}

/// 展示租约是输入路由证明，不是 AuthorizationGrant，不能批准助手或解锁系统。
extension WS2 {
    /// ownerID 为编译期注册的子系统标识；nonce 来自宿主统一 TokenSource。
    struct LeaseRequest: Sendable {
        let ownerID: String
        let display: DisplayID
        let layer: Layer
        let requestedAt: Instant
        let deadline: Instant
        let containsPrivateContent: Bool
    }
    struct LeaseHandle: Hashable, Sendable {
        let token: Token
        let ownerID: String
        let display: DisplayID
        let environmentEpoch: UInt64
    }
    enum LeaseRevocation: Sendable {
        case preempted, suspended, released, expired, locked, sleeping, sessionChanged, disabled, displayRemoved
    }
    enum LeaseDecision: Sendable {
        case acquired(LeaseHandle)
        case busy
        case unavailable
    }
    /// 非持久纯快照。private 内容不进入此结构；实际内容单独按当前租约读。
    struct VisibilitySnapshot: Sendable {
        let display: DisplayID
        let environmentEpoch: UInt64
        let layer: Layer
        let lease: LeaseHandle?
        let ongoingIDs: [String]
        let hasSecondaryDot: Bool
    }
}
