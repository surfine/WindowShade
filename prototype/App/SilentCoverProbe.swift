import Cocoa

/// R02 真机：可识别屏逐屏对账、重复请求复用面板、别的 App 在前台时 Esc 也能撤、退出后无残留。
/// 这是「方便遮一下」，不是系统锁屏，也不宣称 loginwindow 隔离强度。
/// 用法：tests/run-silent-cover-probe.sh
@MainActor
final class SilentCoverProbe {
    private let owner = AppDelegate()
    private var fixture: NSRunningApplication?
    private var failures: [String] = []

    func run() {
        Task { @MainActor in
            await exercise()
        }
    }

    private func exercise() async {
        guard let index = CommandLine.arguments.firstIndex(of: "--fixture"),
              CommandLine.arguments.count > index + 1 else {
            finish("需要 --fixture <path>")
            return
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        let appURL = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

        NotchController.probeSilence = true
        owner.ownsGlobalInput = false
        owner.duoController.persistsSettings = false
        owner.setupStatusItem()
        owner.statusItem.isVisible = false
        print("INFO cover: screens=\(NSScreen.screens.count) accessibility=\(AXIsProcessTrusted())")
        guard AXIsProcessTrusted() else {
            finish("这份隔离构建还没有辅助功能")
            return
        }

        let cover = owner.silentPrivacyCover
        let first = cover.coverAllScreens()
        if first.overlayCreated, first.allScreensCovered, first.unknownDisplayCount == 0 {
            print("PASS cover-all: epoch=\(first.epoch) expected=\(first.expected.count) covered=\(first.coveredIDs.count)")
        } else {
            failures.append("cover-all overlay=\(first.overlayCreated) expected=\(first.expected.count) covered=\(first.coveredIDs.count) unknown=\(first.unknownDisplayCount)")
        }

        // 重复请求：复用现有面板，不先全撤再铺。基线取在第一次铺好之后。
        let createdBefore = cover.probePanelsCreated
        let second = cover.coverAllScreens()
        if second.allScreensCovered, cover.probePanelsCreated == createdBefore {
            print("PASS cover-reuse: 面板创建次数仍是 \(createdBefore)")
        } else {
            failures.append("cover-reuse created \(createdBefore) -> \(cover.probePanelsCreated) covered=\(second.coveredIDs.count)")
        }

        // 别的 App 在前台时 Esc：靠遮挡期间临时装的全局监听，不用长期驻留。
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            let running = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            fixture = running
            let frontmost = await wait(5) {
                NSWorkspace.shared.frontmostApplication?.processIdentifier == running.processIdentifier
            }
            if frontmost, cover.probeHasGlobalEscapeMonitor {
                postEscape()
                let cleared = await wait(3) { !cover.isCovering }
                if cleared {
                    print("PASS cover-esc-outside: 别的 App 在前台，Esc 也撤掉了")
                } else {
                    failures.append("cover-esc-outside 前台是别的 App，Esc 之后仍 covering=\(cover.isCovering)")
                }
            } else {
                failures.append("cover-esc-outside frontmost=\(frontmost) globalMonitor=\(cover.probeHasGlobalEscapeMonitor)")
            }
        } catch {
            failures.append("cover-esc-outside: \(error.localizedDescription)")
        }

        // 退出后没有残留面板和临时监听。
        if cover.probePanelCount == 0, !cover.probeHasGlobalEscapeMonitor, !cover.isCovering {
            print("PASS cover-teardown: 面板和临时监听都拆掉了")
        } else {
            failures.append("cover-teardown panels=\(cover.probePanelCount) globalMonitor=\(cover.probeHasGlobalEscapeMonitor) covering=\(cover.isCovering)")
        }

        // 热插拔：要人手动插/拔一块屏；没等到就如实记未运行，不当成通过。
        let before = NSScreen.screens.count
        _ = cover.coverAllScreens()
        let changed = await wait(25) { NSScreen.screens.count != before }
        if changed {
            let after = cover.coverAllScreens()
            if after.allScreensCovered {
                print("PASS cover-hotplug: screens \(before) -> \(NSScreen.screens.count) covered=\(after.coveredIDs.count)")
            } else {
                failures.append("cover-hotplug screens \(before) -> \(NSScreen.screens.count) covered=\(after.coveredIDs.count) unknown=\(after.unknownDisplayCount)")
            }
        } else {
            print("INFO cover-hotplug: 未运行（25 秒内没有检测到显示器变化）")
        }
        cover.clear()

        finish(failures.isEmpty ? nil : failures.joined(separator: " | "))
    }

    private func postEscape() {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap)
        }
    }

    private func wait(_ timeout: Double, condition: () -> Bool) async -> Bool {
        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        return condition()
    }

    private func finish(_ error: String?) {
        fixture?.terminate()
        fixture = nil
        owner.silentPrivacyCover.clear()
        if let error, !error.isEmpty {
            print("FAIL silent-cover: \(error)")
        } else {
            print("PASS silent-cover")
        }
        WindowShadeLogger.shared.flushAndClose()
        fflush(stdout)
        exit(error == nil || error?.isEmpty == true ? 0 : 1)
    }
}
