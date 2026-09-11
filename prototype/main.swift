import Cocoa

if CommandLine.arguments.contains(where:{$0.hasPrefix("--duo-")}) {
    let log=FileManager.default.currentDirectoryPath+"/.build/duo-tests/native-\(getpid()).log"
    try? FileManager.default.createDirectory(atPath:URL(fileURLWithPath:log).deletingLastPathComponent().path,withIntermediateDirectories:true)
    setenv("WINDOWSHADE_LOG_PATH",log,1)
}
let app = NSApplication.shared
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
if CommandLine.arguments.contains("--duo-render-test") {
    app.setActivationPolicy(.accessory)
    let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/duo-tests/render")
    let probe = EffectRenderProbe(output: output)
    probe.run()
    withExtendedLifetime(probe) { app.run() }
    exit(0)
}
let delegate = AppDelegate()
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
