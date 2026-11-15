import AppKit
import Foundation

/// 标题栏目标的通用规则：非一般 App 的非第 0 层或非标准窗口不是目标。
/// 纯判定，不开窗口、不读辅助功能。
@main struct TitlebarTargetPolicyTests {
    static func main() {
        let standard = kAXStandardWindowSubrole as String
        let dialog = kAXDialogSubrole as String
        var failures = 0
        func expect(_ condition: Bool, _ name: String) {
            if condition {
                print("ok   \(name)")
            } else {
                failures += 1
                print("FAIL \(name)")
            }
        }

        // 1. 非一般 App 的浮动窗口（桌宠预设 .floating、放大的 CarPlay 影片窗）：不是目标。
        expect(!TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .accessory, layer: 3, subrole: standard),
               "accessory + layer 3 + standard → not a target")
        expect(!TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .prohibited, layer: 3, subrole: standard),
               "prohibited + layer 3 + standard → not a target")

        // 2. 非一般 App 的第 0 层非标准窗口（关掉置顶的桌宠、无边框面板）：不是目标。
        expect(!TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .accessory, layer: 0, subrole: "AXUnknown"),
               "accessory + layer 0 + AXUnknown → not a target")
        expect(!TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .accessory, layer: 0, subrole: "AXFloatingWindow"),
               "accessory + layer 0 + AXFloatingWindow → not a target")

        // 3. 一般 App 的第 0 层标准窗口（Finder/Safari 的普通窗口）：照旧是目标。
        expect(TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .regular, layer: 0, subrole: standard),
               "regular + layer 0 + standard → target")
        expect(TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .regular, layer: 0, subrole: dialog),
               "regular + layer 0 + dialog → target")

        // 4. 一般 App 的浮动窗口：维持现状（规则只管非一般 App，不扩大影响面）。
        expect(TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .regular, layer: 3, subrole: standard),
               "regular + layer 3 + standard → target (existing behaviour)")
        expect(TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .regular, layer: 3, subrole: "AXUnknown"),
               "regular + layer 3 + unknown subrole → target (existing behaviour)")

        // 5. 非一般 App 的第 0 层标准窗口（HomePlay 的设置/对话框这类）：仍可当目标。
        expect(TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .accessory, layer: 0, subrole: standard),
               "accessory + layer 0 + standard → target")
        expect(TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .accessory, layer: 0, subrole: dialog),
               "accessory + layer 0 + dialog → target")

        // 6. 预筛只有 WindowServer 快照、还没有 AX 子角色：第 0 层先放行，交给后面的 AX 判定。
        expect(TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .accessory, layer: 0, subrole: nil),
               "accessory + layer 0 + unknown subrole → conservative pass for the prefilter")
        expect(!TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .accessory, layer: 3, subrole: nil),
               "accessory + layer 3 + unknown subrole → not a target without AX")

        // 7. 层级优先：非一般 App 的浮动窗口即使是标准窗口也不是目标。
        expect(!TitlebarTargetPolicy.isTitlebarTarget(activationPolicy: .accessory, layer: 3, subrole: dialog),
               "accessory + layer 3 + dialog → not a target")

        if failures == 0 {
            print("PASS titlebar-target-policy")
        } else {
            print("FAIL titlebar-target-policy \(failures)")
        }
        exit(failures == 0 ? 0 : 1)
    }
}
