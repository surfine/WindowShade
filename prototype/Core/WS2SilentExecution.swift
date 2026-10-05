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
    /// `overlayCreated` / `allScreensCovered` 必须来自遮罩适配器的观察，不能是内存布尔。
    /// 有遮罩但缺屏时用 displayed 表示 partial，不算 completed。
    static func cover(
        overlayCreated: Bool,
        commandID: String,
        allScreensCovered: Bool = false,
        missingScreens: Bool = false
    ) -> SilentExecutionResult {
        if overlayCreated, allScreensCovered, !missingScreens {
            return .completed(WS2EffectReceipt(commandID: commandID, targetID: "", observed: true))
        }
        if overlayCreated, missingScreens {
            return .displayed("还有屏没遮住")
        }
        return .unavailable("尚未遮住")
    }

    static func glance(invoked: Bool, previewVisible: Bool) -> SilentExecutionResult {
        if invoked, previewVisible {
            return .completed(WS2EffectReceipt(commandID: "window.glance", targetID: "", observed: true))
        }
        if invoked {
            return .waiting(1)
        }
        return .unavailable("没预览")
    }

    static func focusStart(wasIdle: Bool, runningAfter: Bool) -> SilentExecutionResult {
        if wasIdle && runningAfter {
            return .completed(WS2EffectReceipt(commandID: "focus.start", targetID: "focus", observed: true))
        }
        if !wasIdle && runningAfter { return .alreadySatisfied("已在专注") }
        return .failed("这一笔没有做成")
    }

    static func pin(alreadyPreviewing: Bool) -> (result: SilentExecutionResult, start: Bool) {
        if alreadyPreviewing { return (.alreadySatisfied("已在置顶"), false) }
        return (.waiting(0), true)
    }

    static func usageRefresh(protocolParsed: Bool) -> SilentExecutionResult {
        guard protocolParsed else { return .displayed("未提供") }
        return .completed(WS2EffectReceipt(commandID: "usage.refresh", targetID: "", observed: true))
    }

    static func placement(frameMatched: Bool, commandID: String, targetID: String) -> SilentExecutionResult {
        guard frameMatched else { return .unknown(0) }
        return .completed(WS2EffectReceipt(commandID: commandID, targetID: targetID, observed: true))
    }

    /// 看一眼：visible 表示首帧已挂上（isLive）。已派发未观察到首帧时 waiting，不报完成。
    static func glance(windowID: UInt64, invoked: Bool, visible: Bool) -> SilentExecutionResult {
        if invoked, visible {
            return .completed(WS2EffectReceipt(
                commandID: "window.glance", targetID: String(windowID), observed: true))
        }
        if invoked {
            return .waiting(1)
        }
        return .unavailable("没预览")
    }

    static func pin(alreadyPreviewing: Bool, started: Bool) -> SilentExecutionResult {
        if alreadyPreviewing { return .alreadySatisfied("已在置顶") }
        return started ? .waiting(1) : .failed("这一笔没有做成")
    }

    static func asyncWindow(already: Bool, started: Bool, satisfied: String) -> SilentExecutionResult {
        if already { return .alreadySatisfied(satisfied) }
        return started ? .waiting(1) : .failed("这一笔没有做成")
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

struct WS2SilentLabLog: Equatable, Sendable {
    var windowCalls = 0
    var backendCalls = 0
    var credentialCalls = 0

    mutating func ingestSimulatedNod() {}
}

/// 一笔操作的回执。晚到的旧操作不能改新页面。
struct WS2SilentOperationLedger: Equatable, Sendable {
    struct Record: Equatable, Sendable {
        var id: UUID
        var commandID: String
        var targetID: String
        var page: UUID
        var line: String
    }

    private(set) var page = UUID()
    private(set) var records: [UUID: Record] = [:]
    private(set) var visible: String = ""

    mutating func begin(commandID: String, targetID: String) -> UUID {
        let id = UUID()
        records[id] = Record(id: id, commandID: commandID, targetID: targetID, page: page, line: "还在等")
        visible = "还在等"
        return id
    }

    mutating func turnPage() {
        page = UUID()
        visible = ""
    }

    /// 页面已经换走时只留下这笔自己的记录，不覆盖新页面。
    @discardableResult
    mutating func finish(id: UUID, line: String) -> Bool {
        guard var record = records[id] else { return false }
        record.line = line
        records[id] = record
        guard record.page == page else { return false }
        visible = line
        return true
    }
}

struct WS2BoundWindow: Equatable, Sendable {
    var displayID: UInt32
    var windowID: String
    var generation: UInt64

    func affected(pointerDisplay: UInt32, focusedWindow: String) -> String {
        _ = pointerDisplay
        _ = focusedWindow
        return windowID
    }
}

struct WS2PinLaunch: Equatable, Sendable {
    struct Key: Hashable, Sendable {
        var pid: Int32
        var window: String
    }

    var inflight: [Key: UInt64] = [:]
    var sessions: Set<Key> = []

    mutating func start(pid: Int32, window: String, generation: UInt64) -> String {
        let key = Key(pid: pid, window: window)
        if sessions.contains(key) { return "already" }
        if inflight[key] != nil { return "join" }
        inflight[key] = generation
        return "new"
    }

    mutating func finish(pid: Int32, window: String, generation: UInt64) -> Bool {
        let key = Key(pid: pid, window: window)
        guard inflight[key] == generation else { return false }
        inflight[key] = nil
        sessions.insert(key)
        return true
    }
}

struct WS2LockedShelf: Equatable, Sendable {
    var scroll: Double
    var selectedID: String?
    var privateLine: String

    func locked() -> WS2LockedShelf {
        WS2LockedShelf(scroll: scroll, selectedID: nil, privateLine: "")
    }
}

struct WS2PageRestore: Equatable, Sendable {
    var scroll: Double
    var selectedID: String?

    func apply(ids: [String], oldLease: UInt64, newLease: UInt64) -> (scroll: Double, selected: String?, missing: Bool, leaseChanged: Bool) {
        let selected = selectedID.flatMap { ids.contains($0) ? $0 : nil }
        let missing = selectedID != nil && selected == nil
        return (scroll, selected, missing, oldLease != newLease)
    }
}
