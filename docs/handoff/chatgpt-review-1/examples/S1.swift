// WindowShade 2 审查包：原创边界骨架，非完整功能。
import AppKit
@MainActor
func settingsSymbol(_ name: String, label: String) -> NSImage? {
    let image = NSImage(systemSymbolName: name, accessibilityDescription: label)
        ?? NSImage(systemSymbolName: "gearshape", accessibilityDescription: label)
    return image?.withSymbolConfiguration(.init(hierarchicalColor: .labelColor))
}
