// 只读的 AX / SkyLight 延迟基准：判断折叠慢在「算」还是「等」。
// 不移动、不修改任何窗口，只测量往返耗时。用 --duo-ax-bench 运行。
import Cocoa

@MainActor
enum AXLatencyBench {
    private static func ms(_ block: () -> Void) -> Double {
        let t = ProcessInfo.processInfo.systemUptime
        block()
        return (ProcessInfo.processInfo.systemUptime - t) * 1000
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

        let rawFirst = CommandLine.arguments.contains("--ax-raw-first")
        func readWindows(_ application: AXUIElement) {
            var value: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        }
        print("顺序：\(rawFirst ? "先读原始 AX 列表，再调用生产枚举" : "先调用生产枚举，再拆分测量")")
        print("App\t窗口\t原始列表预读\t完整枚举(首次)\t完整枚举(重复)\tAX列表(新句柄)\tAX列表(复用句柄)\t窗口ID\t小组件过滤\t位置\t尺寸\t标题\t角色")
        print("单位 ms；首次各一次，其余各三次中位数；按列顺序采样，不作冷启动或 p95/p99 结论。")
        var totalPerWindow = 0.0
        var windowCount = 0
        for target in targets {
            let rawFirstMs: Double? = rawFirst
                ? ms { readWindows(AXUIElementCreateApplication(target.pid)) } : nil
            var windows: [AXUIElement] = []
            let enumMs = ms { windows = appWindows(pid: target.pid) }
            guard let win = windows.first else { continue }
            // 每项测 3 次取中位，避免单次抖动
            func median(_ body: @escaping () -> Void) -> Double {
                let samples = (0..<3).map { _ in ms(body) }.sorted()
                return samples[1]
            }
            let repeatedEnumMs = median { _ = appWindows(pid: target.pid) }
            let newHandleMs = median { readWindows(AXUIElementCreateApplication(target.pid)) }
            let application = AXUIElementCreateApplication(target.pid)
            // Warm the connection separately so reuse is not confounded with its first message.
            readWindows(application)
            let reusedHandleMs = median { readWindows(application) }
            let idMs = median { _ = windowID(of: win) }
            let widgetMs = windowID(of: win).map { id in
                median { _ = isDesktopWidgetWindow(id: id) }
            }
            let posMs = median { _ = axPosition(win) }
            let sizeMs = median { _ = axSize(win) }
            let titleMs = median { _ = axTitle(win) }
            let roleMs = median { _ = axRole(win) }
            let per = posMs + sizeMs + titleMs + roleMs
            totalPerWindow += per
            windowCount += 1
            let measurements = [rawFirstMs ?? .nan, enumMs, repeatedEnumMs, newHandleMs, reusedHandleMs,
                                idMs, widgetMs ?? .nan, posMs, sizeMs, titleMs, roleMs]
                .map { String(format: "%.3f", $0) }.joined(separator: "\t")
            print("\(target.name)\t\(windows.count)\t\(measurements)")
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
