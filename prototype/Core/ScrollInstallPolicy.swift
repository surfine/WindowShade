import Foundation

/// 规格点名过的产品号里没有普通滚轮。空表不是「这只鼠标没有滚轮」。
enum ConfirmedInputDevices: Sendable {
    static let wheelMice: [(vendor: UInt32, product: UInt32)] = []

    static func isConfirmedWheel(vendor: UInt32, product: UInt32) -> Bool {
        wheelMice.contains { $0.vendor == vendor && $0.product == product }
    }
}

/// 还没有核对过的做法，把一条滚动事件绑到某一台 HID 设备上。
enum PerEventAssociation: Sendable {
    static func available() -> Bool { false }
}

/// 让位只用规格写明的标识，外加仓库里已经写过的 BetterTouchTool 标识。
enum ScrollYield: Sendable {
    static func name(among bundleIDs: [String]) -> String? {
        if bundleIDs.contains("com.caldis.Mos") { return "Mos" }
        if bundleIDs.contains(where: { $0 == "com.nuebling.mac-mouse-fix" || $0.hasPrefix("com.nuebling.mac-mouse-fix.") }) {
            return "Mac Mouse Fix"
        }
        if bundleIDs.contains("com.hegenberg.BetterTouchTool") { return "BetterTouchTool" }
        return nil
    }
}

enum ScrollInstallPolicy: Sendable {
    enum Block: Equatable, Sendable {
        case off
        case yielded(String)
        case wheelUnknown
        case noConfirmedWheel
        case sourceUnverified
        case systemStopped
    }

    struct Input: Equatable, Sendable {
        var wantsScrollChange: Bool
        var yieldedTo: String?
        /// nil：没有枚举。true / false 只在调用方真的对照过确认表之后填写。
        var confirmedWheel: Bool?
        var perEventAssociationAvailable: Bool
        var systemStopped: Bool
    }

    enum Decision: Equatable, Sendable {
        case install
        case hold(Block)
    }

    static func decide(_ input: Input) -> Decision {
        if !input.wantsScrollChange { return .hold(.off) }
        if let name = input.yieldedTo { return .hold(.yielded(name)) }
        if input.systemStopped { return .hold(.systemStopped) }
        if input.confirmedWheel == nil { return .hold(.wheelUnknown) }
        if input.confirmedWheel == false { return .hold(.noConfirmedWheel) }
        if !input.perEventAssociationAvailable { return .hold(.sourceUnverified) }
        return .install
    }
}

enum InputStatusCopy: Sendable {
    static func scrollHold(_ block: ScrollInstallPolicy.Block) -> String {
        switch block {
        case .off: return "关着，不改滚动"
        case .yielded(let name): return "由 \(name) 接管"
        case .wheelUnknown, .noConfirmedWheel: return "还没确认是哪只鼠标"
        case .sourceUnverified: return "还没确认滚动来自哪只"
        case .systemStopped: return "系统停掉了，滚动保持原样"
        }
    }

    static func auxiliary(on: Bool, offPhrase: String, onPhrase: String, decision: ScrollInstallPolicy.Decision) -> String {
        guard on else { return offPhrase }
        switch decision {
        case .install: return onPhrase
        case .hold(.off): return "先打开平滑滚动或滚动方向"
        case .hold(let block): return scrollHold(block)
        }
    }
}
