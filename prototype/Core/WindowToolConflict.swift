// R8：别的窗口管理工具在跑、而且我们的快捷键真的被占用时，提醒一次（纯逻辑，可单测）。
// 只提醒、不替人关任何东西；同一个工具永远只提醒一次（记在本机偏好里）。
// “冲突”只认一个信号：至少有一个全局快捷键注册失败、被其他应用占用。光是它在跑，不够。

import Foundation

enum WindowToolConflict {
    struct Tool: Equatable {
        let bundleID: String
        let name: String
    }

    /// 已经提醒过的工具（bundle id 数组）。
    static let defaultsKey = "WindowToolConflict.reminded"

    /// 已知的窗口管理工具。规格 R8 的 ChainYourMac 名单，加上 Wins、BetterTouchTool、Spectacle、AeroSpace。
    /// 不放 apple.WindowManager（系统自带的平铺）：它在 macOS 15 起一直在跑，会让每一次占用都变成误报。
    static let known: [Tool] = [
        Tool(bundleID: "com.knollsoft.Rectangle", name: "Rectangle"),
        Tool(bundleID: "com.knollsoft.Hookshot", name: "Rectangle Pro"),
        Tool(bundleID: "com.crowdcafe.windowmagnet", name: "Magnet"),
        Tool(bundleID: "com.manytricks.Moom", name: "Moom"),
        Tool(bundleID: "com.hegenberg.BetterTouchTool", name: "BetterTouchTool"),
        Tool(bundleID: "com.hegenberg.BetterSnapTool", name: "BetterSnapTool"),
        Tool(bundleID: "cools.wins.main", name: "Wins"),
        Tool(bundleID: "com.mizage.Divvy", name: "Divvy"),
        Tool(bundleID: "com.mizage.direct.Divvy", name: "Divvy"),
        Tool(bundleID: "com.divisiblebyzero.Spectacle", name: "Spectacle"),
        Tool(bundleID: "co.highlyopinionated.swish", name: "Swish"),
        Tool(bundleID: "com.MrKai77.Loop", name: "Loop"),
        Tool(bundleID: "bobko.aerospace", name: "AeroSpace"),
        Tool(bundleID: "com.amethyst.Amethyst", name: "Amethyst"),
        Tool(bundleID: "com.irradiatedsoftware.SizeUp", name: "SizeUp"),
        Tool(bundleID: "com.withmarko.OneMenu", name: "OneMenu"),
    ]

    /// 该提醒哪一个：占用的快捷键至少一个，正在跑的已知工具里，第一个没提醒过的（按上表的顺序）。
    /// 一次只提醒一个；剩下的下次再有占用时再说。
    static func toRemind(runningBundleIDs: [String], takenShortcutCount: Int,
                         alreadyReminded: Set<String>) -> Tool? {
        guard takenShortcutCount > 0 else { return nil }
        let running = Set(runningBundleIDs.map { $0.lowercased() })
        let reminded = Set(alreadyReminded.map { $0.lowercased() })
        return known.first { running.contains($0.bundleID.lowercased()) && !reminded.contains($0.bundleID.lowercased()) }
    }
}
