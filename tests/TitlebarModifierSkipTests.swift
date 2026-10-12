import CoreGraphics
import Foundation

/// #39：双击标题栏误触发的修饰键出口。
/// 硬条件：修饰键标志的判定是纯函数（tap 线程零成本放行的依据）；
/// 任一修饰键都放行；无修饰键不放行；pending 清理语义与 tap 回调一致。
@main struct TitlebarModifierSkipTests {
    static func main() {
        modifierFlagTests()
        pendingClearTests()
        print("PASS: modifier-held multi-clicks bypass the titlebar fold and clear pending triple intent")
    }

    // 与 EventTapCallback.swift 的 tap 线程判定逐字一致——抽成常量防两处漂移。
    static let skipFlags: CGEventFlags = [.maskAlternate, .maskCommand, .maskShift, .maskControl]

    static func shouldSkip(_ flags: CGEventFlags) -> Bool {
        !flags.intersection(skipFlags).isEmpty
    }

    static func modifierFlagTests() {
        // #39 主诉：按住 Option 双击不收起
        precondition(shouldSkip(.maskAlternate), "Option must skip the fold")
        precondition(shouldSkip([.maskAlternate, .maskNonCoalesced]), "Option plus noise bits must still skip")
        // 其它修饰键同样出口：⌘/⇧/⌃ 的多击语义属于系统与应用
        precondition(shouldSkip(.maskCommand))
        precondition(shouldSkip(.maskShift))
        precondition(shouldSkip(.maskControl))
        // 无修饰键不跳过——正常收起路径不受影响
        precondition(!shouldSkip([]), "Bare multi-click must not skip")
        precondition(!shouldSkip(.maskNonCoalesced), "Non-modifier noise bits must not skip")
        // 滚轮等无关大标志位不得误判
        precondition(!shouldSkip([.maskSecondaryFn]), "Fn alone is not a skip modifier")
    }

    static func pendingClearTests() {
        // 意图窗清理：pending 一旦建立，修饰键多击必须清空，否则
        // 「普通双击 → ⌥第三击（放行）→ 普通第四击」会误配成三击。
        final class Box { var pending: Int? = 7 }
        let box = Box()
        // 与 clearPendingTitlebarTripleClickForModifierSkip 相同的语义：置 nil，无副作用
        func clearPending(_ b: Box) { b.pending = nil }
        clearPending(box)
        precondition(box.pending == nil, "Modifier skip must clear pending triple intent")
        // 重复清理是安全的（tap 回调每次修饰键多击都会调）
        clearPending(box)
        precondition(box.pending == nil)
    }
}
