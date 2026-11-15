// 标题栏目标的通用规则（2026-11-13 HomePlay 相容研究第 4 条）：
// 非一般 App（activationPolicy != .regular）的非第 0 层或非标准窗口，不当成标题栏目标。
// 双击预筛、双击/三击判定、触控板标题栏手势与收起捷径都走这一个纯判定，
// 不替任何具体 App 写死 bundle ID。

import Cocoa

enum TitlebarTargetPolicy {
    /// 算得上「标准窗口」的 AX 子角色。对话框放行；浮动面板、AXUnknown 等都不算。
    static let standardWindowSubroles: Set<String> = [
        kAXStandardWindowSubrole as String,
        kAXDialogSubrole as String,
    ]

    /// 纯判定：这扇窗口能不能被当成标题栏目标。
    ///
    /// - 一般 App：一律放行，层级与子角色都不参与（一般 App 的浮窗照旧可以收起）。
    /// - 非一般 App：第 0 层且是标准窗口才放行；其余（辅助层、浮动面板、无边框面板）都排除。
    /// - `subrole == nil` 表示还没读到 AX 子角色（双击预筛在 tap 线程上只有 WindowServer 快照）。
    ///   这时只套层级规则：非一般 App 的第 0 层窗口留给后面的 AX 判定，
    ///   宁可多一次 AX 往返，也不在预筛里错杀。
    static func isTitlebarTarget(activationPolicy: NSApplication.ActivationPolicy,
                                 layer: Int32,
                                 subrole: String?) -> Bool {
        guard activationPolicy != .regular else { return true }
        guard layer == 0 else { return false }
        guard let subrole else { return true }
        return standardWindowSubroles.contains(subrole)
    }
}
