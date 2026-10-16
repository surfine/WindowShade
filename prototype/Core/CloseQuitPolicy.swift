import Foundation

// 规格 R21：关掉卷帘条（转发给真窗口的关闭）之后，要不要顺带退出这个 App。
// 纯逻辑，不依赖 AppKit。只认明确列出的 bundle ID，不做猜测；其余照旧只关窗口。
enum CloseQuitPolicy {
    enum Action: Equatable {
        case quitApp      // 单窗口工具：最后一扇窗关了就退出
        case keepRunning  // 聊天类：永远不退出
        case `default`    // 其余：只关窗口
    }

    // 只为一扇窗存在的工具类 App。
    static let singleWindowTools: Set<String> = [
        "com.apple.calculator",
        "com.apple.AppStore",
    ]

    // 聊天类 App：关掉最后一扇窗也要留在后台收消息。
    static let chatApps: Set<String> = [
        "com.tencent.xinWeChat",
        "com.tencent.qq",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "com.apple.MobileSMS",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "com.electron.lark",
        "com.bytedance.lark",
        "com.alibaba.DingTalkMac",
        "com.alibaba.dingtalk",
        "net.whatsapp.WhatsApp",
        "desktop.WhatsApp",
        "jp.naver.line.mac",
    ]

    static func action(bundleID: String) -> Action {
        if chatApps.contains(bundleID) { return .keepRunning }
        if singleWindowTools.contains(bundleID) { return .quitApp }
        return .default
    }

    // 只有「单窗口工具」且关窗之后一扇用户窗口都不剩，才退出。
    static func shouldQuit(bundleID: String, remainingUserWindows: Int) -> Bool {
        action(bundleID: bundleID) == .quitApp && remainingUserWindows <= 0
    }
}
