// 默认值总账。纪律：验过的，或 Aaron 拍板的（2026-10-17），才默认开；其余带上但默认关。
// （1.0.16 起的第六轮，2026-10-09，原本是“只有真机验过的才默认开”；1.0.18 起 Aaron 拍板开了刘海、实时活动、
// 文件架、再点 Dock 让开和 Dock 悬停查看窗口，见 docs/releases/v1.0.18-defaults.md。）
//
// 这里是唯一的开关表：每个“设计上默认开”的新功能一行。`deviceVerified` 照实记真机验过没有；
// `ownerDecided` 记 Aaron 拍板开的，账上看得出是拍板开的、不是验过开的。两样都没有，它就默认关
// （设置里照样能打开）。改一行之后对一下 docs/releases/ 里最新那份 defaults 表。
// 不分新装和升级：键里没有值的，新老一律按这张表。
// 1.0.15 已有的键不在这张表里，行为一律不变；例外是 WindowBrowserDockEnabled（1.0.18 拍板改成默认开）。
//
// 纯逻辑，不读写本机设置；各处读设置时，“键里没有值”这一支用 ReleaseDefaults.value(_:)。
// 用户已经显式开过或关过的值，原样使用，不看这张表。

import Foundation

enum ReleaseDefaults {
    struct Entry: Equatable, Sendable {
        /// 本机设置里的键。
        let key: String
        /// 设计稿或 Aaron 裁定的默认值（true = 设计上默认开）。
        let designed: Bool
        /// 真机验过了吗。
        let deviceVerified: Bool
        /// Aaron 拍板默认开（没验过也开；验收照样要跑）。
        var ownerDecided: Bool = false

        /// 这个键没设过时的值：设计上开，并且验过或拍板过。
        var release: Bool { designed && (deviceVerified || ownerDecided) }
    }

    // 一行一个键。真机验过后改那一行的 deviceVerified；deviceVerified 照实写，拍板开的另记 ownerDecided。
    static let ledger: [Entry] = [
        // 刘海：整个功能和它的子项。Aaron 拍板 2026-10-17 默认开；刘海 20、home 3、habits 7 等探针照样要在真机上跑
        Entry(key: "Notch.enabled", designed: true, deviceVerified: false, ownerDecided: true),
        Entry(key: "Notch.changeAlerts", designed: true, deviceVerified: false, ownerDecided: true),
        Entry(key: "Notch.teach", designed: true, deviceVerified: false, ownerDecided: true),
        Entry(key: "Notch.activitiesEnabled", designed: true, deviceVerified: false, ownerDecided: true),
        Entry(key: "Notch.activities.musicEnabled", designed: true, deviceVerified: false, ownerDecided: true),
        Entry(key: "Notch.activities.nowPlayingStream", designed: true, deviceVerified: false, ownerDecided: true),
        Entry(key: "Notch.mergedRow", designed: true, deviceVerified: false, ownerDecided: true),
        Entry(key: "Notch.minimalPresentation", designed: true, deviceVerified: false, ownerDecided: true),
        Entry(key: "Notch.deviceBattery.enabled", designed: true, deviceVerified: false, ownerDecided: true),
        Entry(key: "Notch.levelKeys.enabled", designed: true, deviceVerified: false, ownerDecided: true),
        // 文件架与 Dock（Aaron 拍板 2026-10-17 默认开）
        Entry(key: "FileShelf.enabled", designed: true, deviceVerified: false, ownerDecided: true),
        Entry(key: "Dock.clickToHide", designed: true, deviceVerified: false, ownerDecided: true),
        // Dock 悬停查看窗口：1.0.15 起就有的键，那时没设过是关；Aaron 拍板 2026-10-17 起默认开
        Entry(key: "WindowBrowserDockEnabled", designed: true, deviceVerified: false, ownerDecided: true),
        // 启动台卸载（右键菜单「卸载 App…」，进废纸篓可找回；真机 fixture 流过了才翻 deviceVerified）
        Entry(key: "Launchpad.uninstall.enabled", designed: true, deviceVerified: false),
        // 账本写明签名构建上探针跑过（build 16，9/30–10/1），之后没再改过：按设计值发
        Entry(key: "SplitView.divider", designed: true, deviceVerified: true),
        Entry(key: "MissionControl.keys", designed: true, deviceVerified: true),
        Entry(key: "Switcher.trigger", designed: true, deviceVerified: true),
    ]

    /// 这个键没设过时的值。不在表里的键一律 false（新键默认关）。
    static func value(_ key: String) -> Bool {
        ledger.first { $0.key == key }?.release ?? false
    }
}
