// 1.0.16 默认值总账（Aaron 第六轮，2026-10-09：“1.0.16 里只有真机验过的才默认开，没验过的带上但默认关”）。
//
// 这里是唯一的开关表：每个“设计上默认开”的新功能一行。`deviceVerified` 是 false，1.0.16 里它就默认关
// （设置里照样能打开）；Aaron 在真机上验过，只把那一行改成 true，再对一下 docs/releases/v1.0.16-defaults.md。
// 1.0.15 已有的键不在这张表里，行为一律不变。
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
        /// 真机验过了吗。验过才按设计值发；没验过一律关。
        let deviceVerified: Bool

        /// 1.0.16 里这个键没设过时的值。
        var release: Bool { designed && deviceVerified }
    }

    // 一行一个键。真机验过后只改那一行的 deviceVerified。
    static let ledger: [Entry] = [
        // 刘海：整个功能和它的子项（刘海 20、home 3、habits 7 等探针在 10/2–3 改动后要重跑，才算数）
        Entry(key: "Notch.enabled", designed: true, deviceVerified: false),
        Entry(key: "Notch.changeAlerts", designed: true, deviceVerified: false),
        Entry(key: "Notch.teach", designed: true, deviceVerified: false),
        Entry(key: "Notch.activitiesEnabled", designed: true, deviceVerified: false),
        Entry(key: "Notch.activities.musicEnabled", designed: true, deviceVerified: false),
        Entry(key: "Notch.activities.nowPlayingStream", designed: true, deviceVerified: false),
        Entry(key: "Notch.mergedRow", designed: true, deviceVerified: false),
        Entry(key: "Notch.minimalPresentation", designed: true, deviceVerified: false),
        Entry(key: "Notch.deviceBattery.enabled", designed: true, deviceVerified: false),
        Entry(key: "Notch.levelKeys.enabled", designed: true, deviceVerified: false),
        // 文件架与 Dock
        Entry(key: "FileShelf.enabled", designed: true, deviceVerified: false),
        Entry(key: "Dock.clickToHide", designed: true, deviceVerified: false),
        // 启动台卸载（右键菜单「卸载 App…」，进废纸篓可找回；真机 fixture 流过了才翻 deviceVerified）
        Entry(key: "Launchpad.uninstall.enabled", designed: true, deviceVerified: false),
        // 账本写明签名构建上探针跑过（build 16，9/30–10/1），之后没再改过：按设计值发
        Entry(key: "SplitView.divider", designed: true, deviceVerified: true),
        Entry(key: "MissionControl.keys", designed: true, deviceVerified: true),
        Entry(key: "Switcher.trigger", designed: true, deviceVerified: true),
    ]

    /// 这个键 1.0.16 没设过时的值。不在表里的键一律 false（新键默认关）。
    static func value(_ key: String) -> Bool {
        ledger.first { $0.key == key }?.release ?? false
    }
}
