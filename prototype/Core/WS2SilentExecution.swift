// WindowShade 2.1 · 静音结果。内存里的计划不能生成效果回执。
import Foundation

struct WS2EffectReceipt: Equatable, Sendable {
    var commandID: String
    var targetID: String
    /// 调用返回之后读到的状态。写入本身不算。
    var observed: Bool
}

enum SilentExecutionResult: Equatable, Sendable {
    case displayed(String)
    case completed(WS2EffectReceipt)
    case alreadySatisfied(String)
    case waiting(UInt64)
    case unavailable(String)
    case cancelled(String)
    case failed(String)
    case unknown(UInt64)

    var isCompleted: Bool {
        if case .completed(let receipt) = self { return receipt.observed }
        return false
    }

    var notchLine: String {
        switch self {
        case .displayed(let line), .alreadySatisfied(let line), .unavailable(let line), .cancelled(let line), .failed(let line):
            return line
        case .waiting:
            return "还在等"
        case .completed:
            return "已完成"
        case .unknown:
            return "结果未确认"
        }
    }
}

enum WS2SilentEffectJudge {
    static func cover(overlayCreated: Bool, commandID: String) -> SilentExecutionResult {
        guard overlayCreated else { return .unavailable("没遮住") }
        return .completed(WS2EffectReceipt(commandID: commandID, targetID: "", observed: true))
    }

    static func glance(previewVisible: Bool) -> SilentExecutionResult {
        guard previewVisible else { return .unavailable("没预览") }
        return .completed(WS2EffectReceipt(commandID: "window.glance", targetID: "", observed: true))
    }

    static func usageRefresh(protocolParsed: Bool) -> SilentExecutionResult {
        guard protocolParsed else { return .displayed("未提供") }
        return .completed(WS2EffectReceipt(commandID: "usage.refresh", targetID: "", observed: true))
    }

    static func placement(frameMatched: Bool, commandID: String, targetID: String) -> SilentExecutionResult {
        guard frameMatched else { return .unknown(0) }
        return .completed(WS2EffectReceipt(commandID: commandID, targetID: targetID, observed: true))
    }

    static func launchpad(panelVisible: Bool, onFrozenScreen: Bool, commandID: String) -> SilentExecutionResult {
        guard panelVisible, onFrozenScreen else { return .unavailable("没打开") }
        return .completed(WS2EffectReceipt(commandID: commandID, targetID: "", observed: true))
    }
}

/// 开发实验室只记样本。它没有真实效果端口。
enum WS2SilentLab {
    static var realEffectCount: Int { 0 }
}
