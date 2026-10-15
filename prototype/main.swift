import Cocoa

// 应用内更新：试跑新版（--self-check）要在建 App 之前返回；再读更新日志，记一条启动。见 App/UpdaterLaunch.swift。
if let code = UpdateLaunch.handleEarlyArguments() { exit(code) }
UpdateLaunch.recordLaunch()

// 界面语言（第27批）：跟随系统或用户在设置里的选择；只在启动时读这一次，切换由设置里的语言行即时生效。
InterfaceLanguagePreference.applyAtLaunch()

if CommandLine.arguments.contains(where:{$0.hasPrefix("--duo-") || $0.hasPrefix("--glance-") || $0 == "--silent-milestone" || $0 == "--silent-cover-probe" || $0 == "--sls-offscreen-check"}) {
    // 外面已经指定了日志路径（例如在虚拟机里经 open 启动，工作目录是只读的 /）就照用。
    if getenv("WINDOWSHADE_LOG_PATH") == nil {
        let log=FileManager.default.currentDirectoryPath+"/.build/duo-tests/native-\(getpid()).log"
        try? FileManager.default.createDirectory(atPath:URL(fileURLWithPath:log).deletingLastPathComponent().path,withIntermediateDirectories:true)
        setenv("WINDOWSHADE_LOG_PATH",log,1)
    }
}
let app = NSApplication.shared
if CommandLine.arguments.contains("--window-browser-dock-probe") {
    app.setActivationPolicy(.accessory)
    let probe = DockHoverProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-catalog-probe") {
    app.setActivationPolicy(.accessory)
    let probe = WindowCatalogProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-capture-probe") {
    app.setActivationPolicy(.accessory)
    let probe = WindowBrowserCaptureProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-hover-probe") {
    app.setActivationPolicy(.accessory)
    let probe = DockHoverPathProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-thumbnail-probe") {
    app.setActivationPolicy(.accessory)
    let probe = WindowThumbnailPathProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-stream-probe") {
    app.setActivationPolicy(.accessory)
    let probe = WindowStreamPathProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-panel-probe") {
    app.setActivationPolicy(.accessory)
    let probe = WindowBrowserPanelProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-ui-probe") {
    app.setActivationPolicy(.accessory)
    let probe = WindowBrowserUIRouteProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-idle-probe") {
    app.setActivationPolicy(.accessory)
    let probe = WindowBrowserIdleProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-hover-live-probe") {
    app.setActivationPolicy(.accessory)
    let probe = DockHoverLiveProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-identity-probe") {
    app.setActivationPolicy(.accessory)
    let probe = WindowBrowserIdentityProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-live-app-probe") {
    app.setActivationPolicy(.accessory)
    let probe = WindowBrowserLiveAppProbe()
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if let shotIndex = CommandLine.arguments.firstIndex(of: "--window-browser-shots") {
    app.setActivationPolicy(.accessory)
    let directory = CommandLine.arguments.count > shotIndex + 1
        ? URL(fileURLWithPath: CommandLine.arguments[shotIndex + 1])
        : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/window-browser-shots")
    let probe = WindowBrowserShotProbe(outputDirectory: directory)
    DispatchQueue.main.async {
        probe.run()
        NSApp.terminate(nil)
    }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--window-browser-fixture") {
    app.setActivationPolicy(.regular)
    let fixture = WindowBrowserFixture()
    DispatchQueue.main.async { fixture.show() }
    withExtendedLifetime(fixture) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--duo-window-fixture") {
    app.setActivationPolicy(.regular)
    EffectWindowProbe.runFixture()
    exit(0)
}
if CommandLine.arguments.contains("--duo-inspector") {
    app.setActivationPolicy(.accessory)
    let inspector=EffectInspector();inspector.run()
    withExtendedLifetime(inspector) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--glance-probe") {
    app.setActivationPolicy(.accessory)
    let probe = MainActor.assumeIsolated { GlanceProbe() }
    DispatchQueue.main.async { MainActor.assumeIsolated { probe.run() } }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
for flag in ["--export-settings", "--import-settings"] where CommandLine.arguments.contains(flag) {
    // 规格 R5：导出／合并导入设置（后面跟文件路径）。只动设置，不动状态与隐私键。
    let index = CommandLine.arguments.firstIndex(of: flag)!
    guard CommandLine.arguments.count > index + 1 else { print("settings: \(flag) needs a file path"); exit(2) }
    let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    do {
        if flag == "--export-settings" {
            print("settings: exported \(try SettingsArchiveIO.export(to: url)) key(s) to \(url.path)")
        } else {
            let result = try SettingsArchiveIO.importSettings(from: url)
            print("settings: imported \(result.written) key(s), skipped \(result.skipped)")
        }
        exit(0)
    } catch {
        print("settings: failed \(error.localizedDescription)")
        exit(1)
    }
}
if CommandLine.arguments.contains("--launchpad-census") {
    // 规格 R48：启动台扫到的每个 App 的路径，一行一个，给外面拿 Spotlight 的 App 清单对照有没有漏。
    for app in AppCatalog.scan() { print("launchpad: \(app.path)") }
    exit(0)
}
if CommandLine.arguments.contains("--window-census") {
    // 规格 R20：只读普查本机每个 App 的辅助功能窗口，看窗口浏览的过滤收进了哪些「不像真窗口」的东西。
    // 每扇窗一行：App、角色／子角色、有没有标题（不打标题本身）、层、尺寸、关闭与全屏按钮、过滤结论。
    for app in NSWorkspace.shared.runningApplications where app.processIdentifier != getpid() {
        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement], !windows.isEmpty else { continue }
        let bundle = app.bundleIdentifier ?? "-"
        for window in windows {
            let role = axRole(window)
            let id = windowID(of: window) ?? 0
            let layer = id == 0 ? -1 : (cgWindowLayer(id) ?? -1)
            let size = axSize(window)
            let included = isWindowLikeRole(role, pid: pid) && id != 0 && WindowBrowserDiscoveryFilter.shouldInclude(
                WindowBrowserDiscoveryFilter.Input(
                    pid: pid, ownPID: getpid(), bundleIdentifier: bundle, excludedBundleIDs: [],
                    overlayWindowIDs: [], windowID: id, layer: layer, role: role,
                    isDesktopWidget: isDesktopWidgetWindow(id: id), allowsLayoutAreaRole: isAdobeApp(pid: pid)))
            print(String(format: "census: %@ policy=%ld role=%@ subrole=%@ titled=%@ layer=%d size=%@ close=%@ fullscreen=%@ minimized=%@ included=%@",
                bundle, app.activationPolicy.rawValue, role ?? "-", axSubrole(window) ?? "-",
                axTitle(window).isEmpty ? "no" : "yes", layer,
                size.map { String(format: "%.0fx%.0f", $0.width, $0.height) } ?? "-",
                axButtonFrame(window, kAXCloseButtonAttribute as String) != nil ? "yes" : "no",
                axButtonFrame(window, kAXFullScreenButtonAttribute as String) != nil ? "yes" : "no",
                axBoolAttribute(window, kAXMinimizedAttribute as String) ? "yes" : "no",
                included ? "yes" : "no"))
        }
    }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--chrome-report") {
    // 规格 R11：只读量一量某个 App 每扇窗的工具栏底边与收起时保留的高度（不收起、不写任何东西、不打标题）。
    // 用法：--chrome-report <bundle id>，例如 com.apple.finder。
    guard CommandLine.arguments.count > index + 1 else { print("chrome-report: needs a bundle id"); exit(2) }
    let bundle = CommandLine.arguments[index + 1]
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
    guard !apps.isEmpty else { print("chrome-report: \(bundle) is not running"); exit(1) }
    for app in apps {
        let windows = appWindows(pid: app.processIdentifier)
        if windows.isEmpty {
            print("chrome-report: \(bundle) pid=\(app.processIdentifier) no windows (accessibility trusted=\(AXIsProcessTrusted()))")
        }
        for window in windows {
            guard let position = axPosition(window), let size = axSize(window) else { continue }
            let toolbarBottom = firstToolbar(window).flatMap { toolbar -> CGFloat? in
                guard let p = axPosition(toolbar), let s = axSize(toolbar) else { return nil }
                return p.y + s.height - position.y
            }
            let kept = chromeHeight(of: window, winTop: position.y, winSize: size, pid: app.processIdentifier)
            print(String(format: "chrome-report: %@ window=%u size=%.0fx%.0f toolbarBottom=%@ kept=%.1f",
                         bundle, windowID(of: window) ?? 0, size.width, size.height,
                         toolbarBottom.map { String(format: "%.1f", $0) } ?? "none", kept))
        }
    }
    exit(0)
}
if CommandLine.arguments.contains("--export-diagnostics") {
    // 规格 R35／R13：导出本地诊断包并打印路径（不在访达里显示）。可选：后面跟一个目录。
    app.setActivationPolicy(.accessory)
    let index = CommandLine.arguments.firstIndex(of: "--export-diagnostics")!
    let parent = CommandLine.arguments.count > index + 1 && !CommandLine.arguments[index + 1].hasPrefix("-")
        ? URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true) : nil
    do {
        let folder = try MainActor.assumeIsolated { try DiagnosticsExport.export(to: parent) }
        print("diagnostics: \(folder.path)")
        exit(0)
    } catch {
        print("diagnostics: failed \(error.localizedDescription)")
        exit(1)
    }
}
if CommandLine.arguments.contains("--entitlement-probe") {
    // 规格 C3：hardened runtime 下 Apple Events 与摄像头还能不能用（只查授权、已授权才取 1 秒帧）。
    app.setActivationPolicy(.accessory)
    let probe = MainActor.assumeIsolated { EntitlementProbe() }
    DispatchQueue.main.async { MainActor.assumeIsolated { probe.run() } }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--silent-milestone") {
    app.setActivationPolicy(.accessory)
    let probe = MainActor.assumeIsolated { SilentMilestoneProbe() }
    DispatchQueue.main.async { MainActor.assumeIsolated { probe.run() } }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--silent-cover-probe") {
    app.setActivationPolicy(.accessory)
    let probe = MainActor.assumeIsolated { SilentCoverProbe() }
    DispatchQueue.main.async { MainActor.assumeIsolated { probe.run() } }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--sls-offscreen-check") {
    app.setActivationPolicy(.accessory)
    let probe = MainActor.assumeIsolated { SLSOffscreenCheckProbe() }
    DispatchQueue.main.async { MainActor.assumeIsolated { probe.run() } }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--duo-window-test") {
    app.setActivationPolicy(.accessory)
    let probe=EffectWindowProbe();probe.run()
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--duo-soak-test") {
    app.setActivationPolicy(.accessory)
    let duration = CommandLine.arguments.count>index+1 ? Double(CommandLine.arguments[index+1]) ?? 1800 : 1800
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/duo-tests/soak-\(Int(duration)).json")
    let probe = EffectSoakProbe(duration: max(5,duration), output: output)
    probe.run()
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--duo-ax-bench") {
    app.setActivationPolicy(.accessory)
    DispatchQueue.main.async { MainActor.assumeIsolated { AXLatencyBench.run() } }
    app.run()
    exit(0)
}
if CommandLine.arguments.contains("--duo-render-test") {
    app.setActivationPolicy(.accessory)
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/duo-tests/render")
    let probe = EffectRenderProbe(output: output)
    probe.run()
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
let delegate = AppDelegate()
// Isolated visual QA: builds real settings views without sensors, event taps,
// window recovery, or changes to the user's saved effect preferences.
if CommandLine.arguments.contains("--standard-menu-probe") {
    app.setActivationPolicy(.accessory)
    DispatchQueue.main.async {
        let probe = WindowBrowserShotProbe(
            outputDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/design-review"))
        probe.runStandardMenuProbe()
        NSApp.terminate(nil)
    }
    app.run()
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--capture-indicator-probe") {
    app.setActivationPolicy(.accessory)
    let directory = CommandLine.arguments.count > index + 1
        ? URL(fileURLWithPath: CommandLine.arguments[index + 1])
        : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/capture-indicator-probe")
    let probe = CaptureIndicatorProbe(output: directory)
    DispatchQueue.main.async { probe.run() }
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--settings-shots") {
    // 隔离设置窗口截图：不启动传感器、全局事件监听或恢复扫描，也不写入用户偏好。
    app.setActivationPolicy(.accessory)
    delegate.duoController.persistsSettings = false
    delegate.duoController.owner = delegate
    delegate.duoController.isDesignPreview = true
    let index = CommandLine.arguments.firstIndex(of: "--settings-shots")!
    let directory = CommandLine.arguments.count > index + 1
        ? URL(fileURLWithPath: CommandLine.arguments[index + 1])
        : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/settings-shots")
    DispatchQueue.main.async {
        SettingsShotProbe(owner: delegate, outputDirectory: directory).run {
            NSApp.terminate(nil)
        }
    }
    withExtendedLifetime(delegate) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--duo-design-preview") {
    app.setActivationPolicy(.regular)
    delegate.duoController.persistsSettings = false
    delegate.duoController.owner = delegate
    delegate.duoController.isDesignPreview = true
    let preview = SettingsDesignPreview(owner: delegate)
    DispatchQueue.main.async { preview.show() }
    withExtendedLifetime((delegate, preview)) { app.run() }
    exit(0)
}
if CommandLine.arguments.contains("--duo-trial") {
    delegate.duoController.persistsSettings = false
    delegate.duoController.settings.windowsEnabled = true
    delegate.duoController.settings.desktopEnabled = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { delegate.showDuoSettings() }
}
if CommandLine.arguments.contains("--duo-desktop-demo") {
    app.setActivationPolicy(.accessory)
    delegate.duoController.persistsSettings = false
    delegate.duoController.settings.desktopEnabled = true
    delegate.duoController.settings.windowsEnabled = false
    delegate.duoController.start(owner: delegate)
    delegate.showDuoSettings()
    DispatchQueue.main.asyncAfter(deadline: .now()+180) {
        delegate.duoController.stop()
        NSApp.terminate(nil)
    }
    withExtendedLifetime(delegate) { app.run() }
    exit(0)
}
appDelegate = delegate
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
