import Foundation

// CarPlay 全屏的纯映射：会话状态 -> 画什么、写什么。不碰窗口、不起计时器、不读系统。
// 全屏里只画抽象形状，不画 CarPlay 的界面、标志或商标；合成模式的“已连接”一律写明是示意画面。
// 文案按 docs/copy-guide.md：说用户遇到的事；没连上 iPhone 时写“连接 iPhone”，不放假画面。

/// 全屏当前该画的样子。
struct WS2CarPlaySurfaceDisplay: Equatable {
    enum Phase: Equatable {
        case waiting
        case connecting
        case connectedSynthetic
        /// 外部接收器连着：全屏画接收器送来的真画面，状态文字只在还没出画面时垫底。
        case connectedLive(phoneName: String?)
        case disconnected
        case reconnecting(attempt: Int, of: Int, afterSeconds: Int)
        case gaveUp
        case needsIdentity
    }

    var phase: Phase
    /// SF Symbol 名。
    var symbol: String
    var title: String
    var detail: String?
    /// 只有合成模式已连接时画抽象方块。
    var showsTiles: Bool
    /// live 画面已经在收帧：垫底的标题说明可以整体让开。
    var showsLiveVideo: Bool
    /// 断了或放弃后，留在全屏等用户决定：给一个“重新连接”。
    var offersReconnect: Bool
    /// 读屏念的整句。
    var accessibilityLabel: String {
        [title, detail].compactMap { $0 }.joined(separator: "，")
    }
}

enum WS2CarPlaySurfaceModel {
    /// 退出提示，所有状态下都在底部。
    static let exitHint = "再长按刘海或按 Esc 回到桌面"

    /// - Parameters:
    ///   - hasStarted: 这次进入全屏之后是否已经开始过一次连接。区分“还没连”和“连接断了”。
    ///   - now: 单调秒数，只用来算“几秒后再试”。
    static func display(for session: WS2CarPlaySession, hasStarted: Bool, now: TimeInterval,
                        liveVideoStarted: Bool = false, phoneName: String? = nil) -> WS2CarPlaySurfaceDisplay {
        switch session.state {
        case .disconnected:
            if !hasStarted {
                return WS2CarPlaySurfaceDisplay(
                    phase: .waiting, symbol: "iphone", title: "连接 iPhone", detail: nil,
                    showsTiles: false, showsLiveVideo: false, offersReconnect: false)
            }
            return WS2CarPlaySurfaceDisplay(
                phase: .disconnected, symbol: "iphone.slash", title: "连接断了", detail: "回到桌面或重新连接",
                showsTiles: false, showsLiveVideo: false, offersReconnect: true)
        case .missingIdentity:
            return WS2CarPlaySurfaceDisplay(
                phase: .needsIdentity, symbol: "iphone.slash", title: "还不能连接 iPhone", detail: nil,
                showsTiles: false, showsLiveVideo: false, offersReconnect: false)
        case .connecting:
            return WS2CarPlaySurfaceDisplay(
                phase: .connecting, symbol: "iphone.radiowaves.left.and.right", title: "正在连接 iPhone", detail: nil,
                showsTiles: false, showsLiveVideo: false, offersReconnect: false)
        case .ready:
            if session.isReceiverLive {
                // 真画面从接收器来；收到第一帧前先说明在等画面，收到后整块让开。
                let started = liveVideoStarted
                return WS2CarPlaySurfaceDisplay(
                    phase: .connectedLive(phoneName: phoneName),
                    symbol: "car", title: started ? (phoneName ?? "已连接 iPhone") : "等待 iPhone 的画面",
                    detail: started ? nil : "iPhone 已连上接收器",
                    showsTiles: false, showsLiveVideo: started, offersReconnect: false)
            }
            // 合成模式没有真的 iPhone 画面：写明是示意，不冒充。
            return WS2CarPlaySurfaceDisplay(
                phase: .connectedSynthetic, symbol: "car", title: "示意画面", detail: "不是 iPhone 的画面",
                showsTiles: true, showsLiveVideo: false, offersReconnect: false)
        case .waitingToReconnect:
            let attempt = session.reconnectAttempts
            let total = WS2CarPlaySession.maxReconnectAttempts
            let seconds = reconnectSeconds(due: session.reconnectDueAt, now: now)
            return WS2CarPlaySurfaceDisplay(
                phase: .reconnecting(attempt: attempt, of: total, afterSeconds: seconds),
                symbol: "arrow.triangle.2.circlepath", title: "正在重新连接",
                detail: "第 \(attempt) 次，共 \(total) 次，\(seconds) 秒后再试",
                showsTiles: false, showsLiveVideo: false, offersReconnect: false)
        case .gaveUp:
            return WS2CarPlaySurfaceDisplay(
                phase: .gaveUp, symbol: "iphone.slash", title: "没有连上",
                detail: "试了 \(WS2CarPlaySession.maxReconnectAttempts) 次，都没连上",
                showsTiles: false, showsLiveVideo: false, offersReconnect: true)
        }
    }

    /// 向上取整到秒；没到点显示至少 1 秒，过了点显示 0。
    static func reconnectSeconds(due: TimeInterval?, now: TimeInterval) -> Int {
        guard let due, due.isFinite, now.isFinite else { return 0 }
        let remaining = due - now
        guard remaining > 0 else { return 0 }
        return Int(remaining.rounded(.up))
    }

    /// 内容离屏幕上沿的距离：让开刘海（会话的安全区）再留一点呼吸。
    static func contentTopInset(layout: WS2CarPlayLayout?, margin: Double = 24) -> Double {
        let notch = layout?.safeArea.top ?? 0
        return (notch.isFinite ? max(0, notch) : 0) + max(0, margin)
    }

    /// 示意方块：抽象的一行行圆角块，按内容区宽高排。返回的是 0...1 的相对矩形（左上为原点）。
    /// 固定的几块，不随会话数据变；只是“这里会有画面”的形状，不模仿任何真实界面。
    static func tileRects(columns: Int = 4, rows: Int = 2, gap: Double = 0.03) -> [WS2CarPlayTileRect] {
        guard columns > 0, rows > 0 else { return [] }
        let g = max(0, min(gap, 0.2))
        let w = (1 - g * Double(columns - 1)) / Double(columns)
        let h = (1 - g * Double(rows - 1)) / Double(rows)
        var out: [WS2CarPlayTileRect] = []
        for r in 0..<rows {
            for c in 0..<columns {
                out.append(WS2CarPlayTileRect(x: Double(c) * (w + g), y: Double(r) * (h + g), width: w, height: h))
            }
        }
        return out
    }
}

struct WS2CarPlayTileRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

/// 合成模式下，每次连接尝试会发生什么。没有传输，所以由这份脚本决定；默认直接连上。
/// 开发者用环境变量 WINDOWSHADE_CARPLAY_SYNTHETIC 选：connect（默认）、idle、fail、flaky。
enum WS2CarPlaySyntheticScript: String, Equatable {
    /// 第一次就连上。
    case connect
    /// 一直停在“连接 iPhone”，什么都不发生。
    case idle
    /// 每次都失败：走完 5 次重连后放弃。
    case fail
    /// 前两次失败，第三次连上。
    case flaky

    enum Outcome: Equatable { case becomesReady, fails, nothing }

    init(environmentValue: String?) {
        self = environmentValue.flatMap { WS2CarPlaySyntheticScript(rawValue: $0.lowercased()) } ?? .connect
    }

    /// attempt 从 0 起：0 是用户进入全屏的那次，之后是每次重连。
    func outcome(attempt: Int) -> Outcome {
        switch self {
        case .connect: return .becomesReady
        case .idle: return .nothing
        case .fail: return .fails
        case .flaky: return attempt >= 2 ? .becomesReady : .fails
        }
    }
}
