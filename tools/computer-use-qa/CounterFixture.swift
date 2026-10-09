// Standalone QA fixture. No WindowShade internals, credentials, or user documents.
import Cocoa

@MainActor final class Fixture: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var timer: Timer?
    var tick = 0
    func applicationDidFinishLaunching(_ note: Notification) {
        let title = CommandLine.arguments.dropFirst().first ?? "WindowShade QA Counter"
        window = NSWindow(contentRect: NSRect(x: 160, y: 220, width: 640, height: 400),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        let text = NSTextField(labelWithString: "Counter 0")
        text.font = .monospacedDigitSystemFont(ofSize: 60, weight: .medium)
        text.frame = NSRect(x: 30, y: 160, width: 570, height: 80)
        window.contentView?.addSubview(text)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tick += 1
                text.stringValue = "Counter \(self.tick)"
            }
        }
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit QA Counter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        menu.addItem(fileItem)
        NSApp.mainMenu = menu
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let fixture = Fixture()
app.delegate = fixture
app.setActivationPolicy(.regular)
app.run()
