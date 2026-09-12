// 只读的 AX / SkyLight 延迟基准：判断折叠慢在「算」还是「等」。
// 不移动、不修改任何窗口，只测量往返耗时。用 --duo-ax-bench 运行。
import Cocoa

@MainActor
enum AXLatencyBench {
    private static func ms(_ block: () -> Void) -> Double {
        let t = CFAbsoluteTimeGetCurrent(); block(); return (CFAbsoluteTimeGetCurrent() - t) * 1000
    }

    static func run() {
        guard AXIsProcessTrusted() else {
            print("没有辅助功能权限，测不了 AX 延迟")
            exit(1)
        }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let owning = WindowListCache.shared.pidsWithWindows()
        var targets: [(name: String, pid: pid_t)] = []
        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid != selfPID, owning.contains(pid),
                  app.activationPolicy == .regular || app.activationPolicy == .accessory else { continue }
            targets.append((app.localizedName ?? "?", pid))
        }

        print("App                       窗口  枚举ms  位置ms  尺寸ms  标题ms  角色ms  单窗口合计ms")
        var totalPerWindow = 0.0
        var windowCount = 0
        for target in targets {
            var windows: [AXUIElement] = []
            let enumMs = ms { windows = appWindows(pid: target.pid) }
            guard let win = windows.first else { continue }
            // 每项测 3 次取中位，避免单次抖动
            func median(_ body: @escaping () -> Void) -> Double {
                let samples = (0..<3).map { _ in ms(body) }.sorted()
                return samples[1]
            }
            let posMs = median { _ = axPosition(win) }
            let sizeMs = median { _ = axSize(win) }
            let titleMs = median { _ = axTitle(win) }
            let roleMs = median { _ = axRole(win) }
            let per = posMs + sizeMs + titleMs + roleMs
            totalPerWindow += per
            windowCount += 1
            print(String(format: "%-24s %4d %7.1f %7.1f %7.1f %7.1f %7.1f %11.1f",
                         (target.name as NSString).utf8String!, windows.count,
                         enumMs, posMs, sizeMs, titleMs, roleMs, per))
        }

        // 对照：走 WindowServer 而不是目标 App 的 runloop
        let ids = WindowListCache.shared.allWindows().compactMap {
            ($0[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) }
        }
        if let id = ids.first {
            let slsMs = (0..<20).map { _ in ms { _ = PrivateSLSWindowMover.shared.windowAlpha(id: id) } }.sorted()[10]
            print(String(format: "\n对照 · SkyLight 查询（走 WindowServer，不经 App）：%.3fms", slsMs))
        }
        let cgMs = ms { _ = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) }
        print(String(format: "对照 · CGWindowList 全量枚举：%.1fms", cgMs))
        if windowCount > 0 {
            print(String(format: "\nAX 四项读取的平均单窗口成本：%.1fms（%d 个 App 取样）",
                         totalPerWindow / Double(windowCount), windowCount))
        }
        exit(0)
    }
}
