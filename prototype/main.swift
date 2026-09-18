import Cocoa

if CommandLine.arguments.contains(where:{$0.hasPrefix("--duo-")}) {
    let log=FileManager.default.currentDirectoryPath+"/.build/duo-tests/native-\(getpid()).log"
    try? FileManager.default.createDirectory(atPath:URL(fileURLWithPath:log).deletingLastPathComponent().path,withIntermediateDirectories:true)
    setenv("WINDOWSHADE_LOG_PATH",log,1)
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
