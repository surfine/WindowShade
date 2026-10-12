import Foundation

/// 第27批：打包资源路径实测。把 xcstringstool 编出的 en.lproj 当成包里
/// Contents/Resources/Localization/en.lproj（WSL10n.englishBundle 的真实取用方式）加载，
/// 确认新键命中、占位符按语义替换、缺键回退中文、中文一路不读 bundle。
/// 用法：check-english-bundle-path <strings 目录>；目录下须有 en.lproj/Localizable.strings。
@main enum CheckEnglishBundlePath {
    static func main() {
        let stringsDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let enDir = stringsDir.appendingPathComponent("en.lproj", isDirectory: true)
        guard let bundle = Bundle(url: enDir) else {
            print("FAIL cannot open en.lproj at \(enDir.path)")
            exit(1)
        }
        guard let table = NSDictionary(contentsOf: enDir.appendingPathComponent("Localizable.strings"))
            as? [String: String] else {
            print("FAIL cannot read compiled Localizable.strings")
            exit(1)
        }
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            if condition {
                print("ok   \(label)")
            } else {
                failures += 1
                print("FAIL \(label)")
            }
        }

        // 中文一路：不设 bundle 时原样返回源句；设了 bundle 也一样（zh 不看译文）。
        WSL10n.language = .zh
        check(WSL10n.text("settings.shade.glance.name", zh: "看一眼") == "看一眼",
              "zh returns the source sentence verbatim")
        check(WSL10n.text("settings.info.label", zh: "%@的说明", "看一眼") == "看一眼的说明",
              "zh template still formats its arguments")

        // 英文经真实 Bundle 路径：batch-27 新键命中编好的译文。
        WSL10n.englishBundle = bundle
        WSL10n.language = .en
        check(WSL10n.text("settings.shade.glance.name", zh: "看一眼") == "Glance",
              "en bundle resolves settings.shade.glance.name")
        check(WSL10n.text("settings.shade.tuckNotch.name", zh: "收进刘海") == "Tuck into the notch",
              "en bundle resolves settings.shade.tuckNotch.name")
        check(WSL10n.text("settings.window.title", zh: "WindowShade 设置") == "WindowShade Settings",
              "en bundle resolves the window title")
        check(WSL10n.text("settings.shade.sub",
                          zh: "设置怎么收起窗口、收起后什么样、要不要提示音。")
              == "How windows roll up, how a rolled-up window looks, and whether to play a sound.",
              "en bundle resolves the long shade subtitle")
        check(WSL10n.text("settings.info.label", zh: "%@的说明", "Glance") == "Notes on Glance",
              "en template formats its arguments")
        let missing = WSL10n.text("batch27.key.not.in.catalog", zh: "缺失键回退")
        check(missing == "缺失键回退", "missing key falls back to the zh source sentence")
        let tableValue = table["settings.shade.tuckNotch.name"]
        check(tableValue == "Tuck into the notch",
              "compiled artifact carries the batch-27 key (strings table agree)")
        check(table.count >= 371, "compiled artifact has the full catalog (\(table.count) keys)")

        // 切回中文：语言改写后同一键回到源句，说明 bundle 只在 en 时参与。
        WSL10n.language = .zh
        check(WSL10n.text("settings.shade.tuckNotch.name", zh: "收进刘海") == "收进刘海",
              "switching back to zh ignores the bundle")

        WSL10n.englishBundle = nil
        WSL10n.language = .en
        check(WSL10n.text("settings.shade.tuckNotch.name", zh: "收进刘海") == "收进刘海",
              "en without a bundle degrades to the zh sentence")

        if failures == 0 {
            print("PASS: english bundle path — new keys resolve through the packaged en.lproj, zh untouched")
        } else {
            print("FAILED \(failures)")
            exit(1)
        }
    }
}
