// 无头性能基准：跑真实视图的扫描 / 布局 / 内容准备，只计时，不截图、不写用户设置。
// 锁屏也能跑（所以不依赖「有人在用这台电脑」）。输出 `perf: launchpad …` 行。
import Cocoa

func wlog(_ message: String) { print(message) }
enum LegacyQuickCapture { static func reportUnavailableOnce() {} }

@main struct LaunchpadPerfFixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            guard let screen = NSScreen.main else { exit(1) }
            func report(_ label: String, _ started: CFAbsoluteTime, _ extra: String = "") {
                let milliseconds = (CFAbsoluteTimeGetCurrent() - started) * 1000
                print(String(format: "perf: %@ %.1fms%@", label, milliseconds, extra.isEmpty ? "" : " " + extra))
            }

            var started = CFAbsoluteTimeGetCurrent()
            let found = AppCatalog.scan()
            report("launchpad catalog scan", started, "apps=\(found.count)")

            started = CFAbsoluteTimeGetCurrent()
            let layout = LaunchpadLayout.initial(apps: found, otherName: "其他")
            report("launchpad initial layout", started, "items=\(layout.items.count)")

            let panel = LaunchpadPanel(screen: screen)
            let view = panel.view
            let labelWidth = view.grid.cell.width - 12

            started = CFAbsoluteTimeGetCurrent()
            var images: [String: (CGImage?, CGImage?)] = [:]
            for entry in found {
                images[entry.path] = (AppCatalog.icon(for: entry.path, pixels: 192),
                                      AppCatalog.label(entry.name, width: labelWidth, scale: screen.backingScaleFactor))
            }
            report("launchpad artwork for every app", started, "apps=\(found.count)")
            view.art = { images[$0.path] ?? (nil, nil) }

            started = CFAbsoluteTimeGetCurrent()
            view.setContent(apps: found, layout: layout)
            report("launchpad home setContent", started)

            started = CFAbsoluteTimeGetCurrent()
            view.settle(to: view.homePages)
            report("launchpad library layout", started, "categories=\(view.library.categories.count)")

            if let category = view.library.categories.first {
                started = CFAbsoluteTimeGetCurrent()
                view.openCategoryForProbe(category.id)
                report("launchpad category open", started, "id=\(category.id) apps=\(category.apps.count)")
                view.closeFolder(animated: false)
            }

            view.settle(to: 0)
            if let folder = layout.items.compactMap(\.folderID).first {
                started = CFAbsoluteTimeGetCurrent()
                view.openFolder(folder)
                report("launchpad folder open", started, "id=\(folder)")
                view.closeFolder(animated: false)
            }

            started = CFAbsoluteTimeGetCurrent()
            view.settle(to: -1)
            report("launchpad today layout", started)

            panel.orderOut(nil)
            exit(0)
        }
        app.run()
    }
}
