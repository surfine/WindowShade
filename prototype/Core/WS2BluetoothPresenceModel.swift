import Foundation

// 离开就锁的蓝牙在场来源（纯模型）。来源语义：用户从已配对设备里选一台「随身设备」，
// 它连着就算在场。探针实测：经典蓝牙的 RSSI 只在已连接时可读（rawRSSI()），iPhone 的
// Continuity 连接会间歇断开——所以「断开」必须持续一段时间才算离开，否则会误锁。
// 时间由接入层以单调秒传入，纯函数可测；默认关，真机观察 iPhone 连接占空比前不放开。

/// 在场判定：把「现在连着吗」的读数序列换算成 PresenceLock 的事件序列。
struct WS2BluetoothPresenceModel: Equatable {
    /// 选中的随身设备（蓝牙地址，大写冒号分隔）。空 = 没选，来源不可用。
    var chosenAddress: String?
    /// 断开持续这么久才算离开（秒）。期间重连即取消，不发任何事件。
    var awayDebounce: TimeInterval
    /// 读数间隔（秒）。接入层按这个节奏喂 poll。
    var pollInterval: TimeInterval

    private var wasConnected: Bool?
    private var awaySince: TimeInterval?

    init(chosenAddress: String?, awayDebounce: TimeInterval = 60, pollInterval: TimeInterval = 5) {
        self.chosenAddress = chosenAddress
        self.awayDebounce = awayDebounce
        self.pollInterval = pollInterval
    }

    /// 地址归一化：大写、冒号分隔；不合格返回 nil。
    static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let hex = raw.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased()
        guard hex.count == 12, hex.allSatisfy({ $0.isHexDigit }) else { return nil }
        var out = ""
        for (index, character) in hex.enumerated() {
            if index > 0 && index % 2 == 0 { out += ":" }
            out.append(character)
        }
        return out
    }

    var isConfigured: Bool { chosenAddress != nil }

    enum Event: Equatable {
        case connect
        case disconnect
    }

    /// 喂一次「现在连着吗」（设备已不在配对列表时传 nil，时间单调秒）。状态没变就不发事件。
    mutating func poll(connected: Bool?, at now: TimeInterval) -> Event? {
        guard chosenAddress != nil else { return nil }
        guard let connected else {
            // 设备被解除配对：按离开处理一次，之后保持沉默直到它回来。
            let event: Event? = awaySince == nil && wasConnected == true ? .disconnect : nil
            wasConnected = nil
            awaySince = now
            return event
        }
        if connected {
            let firstSighting = wasConnected == nil
            let returning = awaySince != nil
            wasConnected = true
            awaySince = nil
            return (firstSighting || returning) ? .connect : nil
        }
        // 断开：先记起点；持续够久才认离开。
        if let since = awaySince {
            if now - since >= awayDebounce, wasConnected == true {
                wasConnected = false
                return .disconnect
            }
            return nil
        }
        if wasConnected == nil {
            wasConnected = false // 启动时就不在：不算「离开」，要等它先连上过。
            awaySince = now
            return nil
        }
        if wasConnected == true {
            awaySince = now
            return nil
        }
        return nil
    }
}
