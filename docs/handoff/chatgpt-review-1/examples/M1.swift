// WindowShade 2 审查包：原创边界骨架，非完整功能。
import AppKit
@MainActor
func makeSettingsAlternates(target: AnyObject, settings: Selector,
                            about: Selector) -> [NSMenuItem] {
    let a = NSMenuItem(title: "设置…", action: settings, keyEquivalent: ",")
    a.target = target; a.keyEquivalentModifierMask = [.command]
    let b = NSMenuItem(title: "关于 WindowShade", action: about, keyEquivalent: ",")
    b.target = target; b.keyEquivalentModifierMask = [.command, .option]
    b.isAlternate = true
    return [a, b] // 必须相邻插入同一个 NSMenu。
}
