import Foundation

// 系统设置「隐私与安全性」里辅助功能那一栏，macOS 27 改名了（规格 R28）。本机 macOS 27.0.1 的
// SecurityPrivacyExtension.appex 里 ACCESSIBILITY 这个键：en「Device Control and Data Access」、
// zh_CN「设备控制和数据访问」、zh_TW「裝置控制和資料取用」。新旧两个名字都在本地化目录里
// （system.privacyPane.legacy／.renamed），按当前界面语言取。
// 我们教人去那里开权限的句子要跟着系统叫。26 及以前原样不动；只套在「指这一栏」的句子上——
// 「减少动态效果」所在的那个真正的「辅助功能」设置没有改名，那几句不套。
enum PrivacyPaneName {
    static var isRenamed: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }
    static var legacyName: String { WSL10n.text("system.privacyPane.legacy", zh: "辅助功能") }
    static var renamedName: String { WSL10n.text("system.privacyPane.renamed", zh: "设备控制和数据访问") }

    static func adjust(_ text: String, renamed: Bool = isRenamed) -> String {
        adjust(text, renamed: renamed, from: legacyName, to: renamedName)
    }

    static func adjust(_ text: String, renamed: Bool, from old: String, to new: String) -> String {
        guard renamed, !old.isEmpty else { return text }
        return text.replacingOccurrences(of: old, with: new)
    }
}
