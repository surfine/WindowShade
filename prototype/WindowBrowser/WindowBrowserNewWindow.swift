// 新建窗口（DockMate 的 “open a new window”）：让 App 按它自己的方式新开一扇窗。
//
// 读这个 App 的菜单栏，按下标题说的就是“新建窗口”的那一项（“新建窗口”“新建访达窗口”
// “打开新的窗口”，也看“新建窗口 ▸”子菜单里的 ⌘N）；没有这种项时，文稿类 App 的“新建”（⌘N）也算。
// 只看快捷键不看标题不行：日历、提醒事项、备忘录、通讯录的 ⌘N 是新建日程、提醒、备忘录、名片。
// 挑不到、或菜单读不到，就不按、也不发按键。
//
// 分两步：先读菜单定下按哪一项（resolve），调用方确认要按了才把 App 带到前面，再按（press）。
// 这样没东西可按时不会把用户让开或隐藏的 App 翻出来。
//
// 线程：同步 AX 读取，调用方放在后台队列（控制器的 axResolverQueue）。

import Cocoa
import ApplicationServices

enum WindowBrowserNewWindow {
    enum Resolution {
        /// 要按的那一项。
        case ready(AXUIElement)
        case disabled
        case noCommand
        case unreadable

        var label: String {
            switch self {
            case .ready: return "ready"
            case .disabled: return "disabled"
            case .noCommand: return "no-command"
            case .unreadable: return "unreadable"
            }
        }
    }

    /// 每个菜单最多看这么多项：菜单很长的 App（书签、历史）不在这里耗时间。
    private static let itemsPerMenu = 60
    /// “新建窗口 ▸”子菜单最多看这么多项（终端的描述文件、Safari 的个人资料）。
    private static let itemsPerSubmenu = 20

    private typealias Command = WindowBrowserNewWindowCommand

    static func resolve(pid: pid_t) -> Resolution {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        var barRef: CFTypeRef?
        let readable: Bool
        var candidates: [Command.Candidate] = []
        var elements: [Command.ItemPath: AXUIElement] = [:]
        if AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &barRef) == .success,
           let barRef, CFGetTypeID(barRef) == AXUIElementGetTypeID() {
            let bar = barRef as! AXUIElement
            let barItems = axChildren(bar)
            readable = !barItems.isEmpty
            // 先看“文件”（下标 2）；已经找到只带 ⌘N 的“新建窗口”就不再往下读别的菜单。
            var order = Array(barItems.indices.dropFirst())
            if let file = order.firstIndex(of: 2) { order.insert(order.remove(at: file), at: 0) }
            for menuIndex in order {
                scan(menuItem: barItems[menuIndex], menuIndex: menuIndex,
                     into: &candidates, elements: &elements)
                if Command.isSettled(candidates) { break }
            }
        } else {
            readable = false
        }
        switch Command.plan(menuReadable: readable, candidates: candidates) {
        case .press(let path):
            guard let element = elements[path] else { return .unreadable }
            return .ready(element)
        case .disabled:
            return .disabled
        case .noCommand:
            return .noCommand
        case .unreadable:
            return .unreadable
        }
    }

    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private static var itemAttributes: CFArray {
        [kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
         kAXEnabledAttribute, kAXTitleAttribute, kAXChildrenAttribute] as CFArray
    }

    /// 读一项的属性。读不到的属性会以 AXValue 错误占位：只接受真正的字符串 / 数字 / 数组。
    private static func read(_ item: AXUIElement)
        -> (character: String?, modifiers: Int?, enabled: Bool, title: String, children: [AXUIElement])? {
        var valuesRef: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(item, itemAttributes, AXCopyMultipleAttributeOptions(),
                                                     &valuesRef) == .success,
              let values = valuesRef as? [Any], values.count == 5 else { return nil }
        let character = (values[0] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let modifiers = (values[1] as? NSNumber)?.intValue
        let enabled = (values[2] as? NSNumber)?.boolValue ?? false
        let title = values[3] as? String ?? ""
        let children = values[4] as? [AXUIElement] ?? []
        return (character, modifiers, enabled, title, children)
    }

    /// 读一个顶层菜单里的各项，记下 plan 用得上的那些；标题像“新建窗口”的子菜单再往下读一层。
    private static func scan(menuItem: AXUIElement, menuIndex: Int,
                             into candidates: inout [Command.Candidate],
                             elements: inout [Command.ItemPath: AXUIElement]) {
        for menu in axChildren(menuItem) {
            for (itemIndex, item) in axChildren(menu).prefix(itemsPerMenu).enumerated() {
                guard let values = read(item) else { continue }
                let candidate = Command.Candidate(
                    menuIndex: menuIndex, itemIndex: itemIndex, title: values.title,
                    commandCharacter: values.character, commandModifiers: values.modifiers,
                    enabled: values.enabled, hasSubmenu: !values.children.isEmpty)
                guard Command.isWorthKeeping(candidate) else { continue }
                candidates.append(candidate)
                elements[candidate.path] = item
                guard candidate.hasSubmenu,
                      Command.titleKind(values.title) == .newWindow else { continue }
                for submenu in values.children {
                    for (subIndex, sub) in axChildren(submenu).prefix(itemsPerSubmenu).enumerated() {
                        guard let subValues = read(sub), subValues.children.isEmpty else { continue }
                        let child = Command.Candidate(
                            menuIndex: menuIndex, itemIndex: itemIndex, subItemIndex: subIndex,
                            title: subValues.title, parentTitle: values.title,
                            commandCharacter: subValues.character, commandModifiers: subValues.modifiers,
                            enabled: subValues.enabled)
                        candidates.append(child)
                        elements[child.path] = sub
                    }
                }
            }
        }
    }

    /// 这个进程现在在 WindowServer 里的普通层窗口号（判断新窗口出没出来）。
    static func layerZeroWindowIDs(pid: pid_t) -> Set<CGWindowID> {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var ids = Set<CGWindowID>()
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
            ids.insert(CGWindowID(number.uint32Value))
        }
        return ids
    }
}
