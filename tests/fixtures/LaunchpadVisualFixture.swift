// Render the actual AppKit view with a disposable in-memory layout; no user defaults writes.
import Cocoa
func wlog(_ message: String) { print(message) }
enum LegacyQuickCapture { static func reportUnavailableOnce() {} }
@main struct LaunchpadVisualFixture {
    @MainActor static func pause() async { CATransaction.flush(); try? await Task.sleep(nanoseconds: 800_000_000) }
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        Task { @MainActor in
            guard let screen = NSScreen.main else { exit(1) }
            let panel = LaunchpadPanel(screen: screen)
            let view = panel.view
            let found = AppCatalog.scan()
            let layout = LaunchpadLayout.initial(apps: found, otherName: "其他")
            var images: [String: (CGImage?, CGImage?)] = [:]
            for entry in found {
                images[entry.path] = (AppCatalog.icon(for: entry.path, pixels: 192), AppCatalog.label(entry.name, width: view.grid.cell.width - 12, scale: screen.backingScaleFactor))
            }
            view.art = { images[$0.path] ?? (nil, nil) }
            view.setContent(apps: found, layout: layout)
            if let url = NSWorkspace.shared.desktopImageURL(for: screen), let image = AppCatalog.wallpaper(url: url, pixels: screen.frame.width * screen.backingScaleFactor) { view.setWallpaper(image) }
            panel.orderFrontRegardless()
            view.animateIn()
            @MainActor func save(_ name: String) {
                guard let image = FastCapture.window(CGWindowID(panel.windowNumber)),
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { print("capture failed: \(name)"); exit(1) }
                try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png"))
                print("saved \(name)")
            }
            await pause(); save("home")
            view.settle(to: view.homePages); await pause(); save("library")
            view.settle(to: 0)
            if let folder = layout.items.compactMap(\.folderID).first { view.openFolder(folder); await pause(); save("folder"); view.closeFolder(animated: false) }
            view.settle(to: -1); await pause(); save("today")
            panel.orderOut(nil); exit(0)
        }
        app.run()
    }
}
