// 真实入口探针：对**正在运行的另一个 WindowShade 进程**（正常启动的应用，
// 不是本探针自己）走一遍真实入口：
//
//   状态栏菜单 → “选择窗口…” → 键盘面板 → 读面板里的真实窗口条目 → Esc 关闭 → 确认消失。
//
// 只做两次 AXPress（状态项、菜单项）和一次 Esc 按键，不点击任何卡片动作、不改设置、
// 不移动指针、不关闭或折叠任何用户窗口。用途是证明“新入口在真实运行的应用里可用”，
// 而不是只在本进程构造出的菜单对象里成立。

import Cocoa
import ApplicationServices

final class WindowBrowserLiveAppProbe {
    private let ownPID = getpid()
    private var targetPID: pid_t = 0
    private var frontmostBefore: pid_t = 0
    private var statusItem: AXUIElement?
    private var checks = 0
    private var failures: [String] = []
    private var savedPointer: NSPoint?

    func run() {
        guard hasAccessibilityPermission() else {
            print("live-app-probe: no accessibility permission; result=unverified")
            exit(2)
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { candidate in
            candidate.processIdentifier != ownPID
                && (candidate.bundleIdentifier == "com.windowshade.prototype"
                    || candidate.bundleURL?.lastPathComponent == "WindowShade.app")
        }) else {
            print("live-app-probe: no running WindowShade instance; result=unverified")
            exit(3)
        }
        targetPID = app.processIdentifier
        frontmostBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        print("live-app-probe: target pid=\(targetPID) "
              + "bundle=\(app.bundleIdentifier ?? "-") frontmostBefore=\(frontmostBefore)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            openStatusMenu(attempt: 0)
        }
    }

    // MARK: 状态栏菜单

    private func openStatusMenu(attempt: Int) {
        let appElement = AXUIElementCreateApplication(targetPID)
        let menuBar = axButtonElement(appElement, kAXExtrasMenuBarAttribute as String)
            ?? axButtonElement(appElement, kAXMenuBarAttribute as String)
        let item = menuBar.flatMap { axChildren($0).first }
        guard let item else {
            if attempt < 4 {
                retry(after: 0.3) { [self] in openStatusMenu(attempt: attempt + 1) }
                return
            }
            record("running app exposes a status item menu bar", false)
            finish()
            return
        }
        statusItem = item
        record("running app exposes a status item menu bar", true)
        print("live-app-probe: statusItem role=\(axRole(item) ?? "-") "
              + "title=\(axString(item, kAXTitleAttribute as String) ?? "-") "
              + "description=\(axString(item, kAXDescriptionAttribute as String) ?? "-") "
              + "actions=\(actionNames(item))")
        let pressResult = AXUIElementPerformAction(item, kAXPressAction as CFString)
        let pressed = pressStatusItem(item, axPressResult: pressResult)
        guard pressed else {
            record("status item answers AXPress", false)
            finish()
            return
        }
        record("status item answers AXPress", true)
        retry(after: 0.4) { [self] in readStatusMenu(attempt: 0) }
    }

    private func readStatusMenu(attempt: Int) {
        guard let statusItem else { finish(); return }
        let items = collectMenuItems(from: statusItem, depth: 0)
        if items.isEmpty, attempt < 8 {
            retry(after: 0.2) { [self] in readStatusMenu(attempt: attempt + 1) }
            return
        }
        let titles = items.map { $0.title }
        record("status menu has items", !items.isEmpty)
        print("live-app-probe: statusMenu items=\(items.count) titles=\(titles.joined(separator: " | "))")
        guard let browserItem = items.first(where: { $0.title == "选择窗口…" }) else {
            record("status menu contains 选择窗口…", false)
            dismissMenu()
            finish()
            return
        }
        record("status menu contains 选择窗口…", true)
        record("选择窗口… is enabled", browserItem.enabled)
        guard AXUIElementPerformAction(browserItem.element, kAXPressAction as CFString) == .success else {
            record("选择窗口… answers AXPress", false)
            dismissMenu()
            finish()
            return
        }
        record("选择窗口… answers AXPress", true)
        retry(after: 0.7) { [self] in inspectPanel(attempt: 0) }
    }

    // MARK: 面板

    private func inspectPanel(attempt: Int) {
        if attempt == 0 { restorePointer() }
        let onScreen = panelOnScreen()
        let windows = appWindows(pid: targetPID)
        let titled = windows.map { (element: $0, title: axString($0, kAXTitleAttribute as String) ?? "") }
        guard let panel = titled.first(where: { $0.title == "窗口选择" })?.element else {
            if attempt < 12 {
                retry(after: 0.2) { [self] in inspectPanel(attempt: attempt + 1) }
                return
            }
            // 窗口对象即使 orderOut 也留在 AX 列表里、也可能反过来被其它窗口干扰，
            // 所以“面板是否打开”以 WindowServer 在屏窗口为准。
            record("真实菜单项打开键盘面板窗口", onScreen)
            record("面板窗口可被 AX 读取", false)
            print("live-app-probe: appWindows=\(windows.count) "
                  + "onScreen=\(onScreen) "
                  + "titles=[\(titled.map(\.title).joined(separator: " | "))]")
            closePanel()
            return
        }
        record("真实菜单项打开键盘面板窗口", onScreen)
        record("面板窗口可被 AX 读取", true)
        record("面板窗口带可访问性名称“窗口选择”",
               axString(panel, kAXTitleAttribute as String) == "窗口选择")
        print("live-app-probe: panel window title=窗口选择 onScreen=\(onScreen) "
              + "appWindows=\(windows.count)")
        let descendants = collectLabels(from: panel, depth: 0)
        let cardLabels = descendants.filter { $0.contains("，") }
        record("面板里有真实窗口条目", !cardLabels.isEmpty)
        print("live-app-probe: panelLabels=\(descendants.count) cards=\(cardLabels.count) "
              + "sample=[\(cardLabels.prefix(3).joined(separator: " / "))]")
        let realTitles = otherAppWindowTitles()
        let matched = realTitles.first { title in
            descendants.contains { $0.contains(title) }
        }
        record("面板条目与真实窗口标题对应", matched != nil)
        print("live-app-probe: crossCheck matchedTitle=\(matched ?? "-") "
              + "candidates=\(realTitles.count)")
        closePanel()
    }

    // MARK: 关闭与确认

    private func closePanel() {
        postEscape()
        retry(after: 0.6) { [self] in verifyClosed(attempt: 0, toggled: false) }
    }

    private func verifyClosed(attempt: Int, toggled: Bool) {
        if !panelOnScreen() {
            record("Esc 关闭面板", true)
            let frontmostAfter = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            if frontmostBefore != 0, frontmostBefore != targetPID {
                record("关闭后前台应用归还给打开前的应用", frontmostAfter == frontmostBefore)
                print("live-app-probe: frontmostAfter=\(frontmostAfter) "
                      + "frontmostBefore=\(frontmostBefore)")
            } else {
                print("live-app-probe: frontmostAfter=\(frontmostAfter) "
                      + "(打开前前台就是目标应用，不做归还断言)")
            }
            finish()
            return
        }
        if attempt < 8 {
            retry(after: 0.25) { [self] in verifyClosed(attempt: attempt + 1, toggled: toggled) }
            return
        }
        guard !toggled else {
            record("Esc 关闭面板", false)
            finish()
            return
        }
        // Esc 没关掉就再走一遍真实菜单项把它切回关闭，避免把面板留在用户屏幕上。
        print("live-app-probe: escape did not close the panel; retrying through the menu")
        openStatusMenuAgainToToggle { [self] success in
            guard success else {
                record("Esc 关闭面板", false)
                finish()
                return
            }
            retry(after: 0.5) { [self] in verifyClosed(attempt: 0, toggled: true) }
        }
    }

    private func openStatusMenuAgainToToggle(_ completion: @escaping (Bool) -> Void) {
        let appElement = AXUIElementCreateApplication(targetPID)
        let menuBar = axButtonElement(appElement, kAXExtrasMenuBarAttribute as String)
            ?? axButtonElement(appElement, kAXMenuBarAttribute as String)
        guard let item = menuBar.flatMap({ axChildren($0).first }) else {
            completion(false)
            return
        }
        guard pressStatusItem(item, axPressResult: AXUIElementPerformAction(
                item, kAXPressAction as CFString)) else {
            completion(false)
            return
        }
        retry(after: 0.4) { [self] in
            let items = collectMenuItems(from: item, depth: 0)
            guard let browserItem = items.first(where: { $0.title == "选择窗口…" }) else {
                postEscape()
                completion(false)
                return
            }
            completion(AXUIElementPerformAction(browserItem.element,
                                                kAXPressAction as CFString) == .success)
        }
    }

    private func dismissMenu() {
        postEscape()
    }

    /// 面板是否真的还在屏幕上。不能用 AX 窗口列表判断：面板关闭只是 orderOut，
    /// 窗口仍留在应用的 AXWindows 里（窗口对象 isReleasedWhenClosed = false）。
    /// 也不能只看“目标应用有没有大窗口”，否则用户自己的设置窗口会造成假阳性；
    /// 这里用 WindowServer 的在屏窗口名精确匹配。
    private func panelOnScreen() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == targetPID else {
                return false
            }
            return (info[kCGWindowName as String] as? String) == "窗口选择"
        }
    }

    private func postEscape() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// 状态项位置上的真实点击（保存指针位置，面板出现前原样放回）。
    private func pressStatusItem(_ item: AXUIElement, axPressResult: AXError) -> Bool {
        if axPressResult == .success { return true }
        // 部分状态项不响应 AXPress；像真人一样在它的位置点一下，稍后原样放回指针。
        print("live-app-probe: statusItem axPress=err=\(axPressResult.rawValue); "
              + "falling back to a real click")
        return clickStatusItem(item)
    }

    private func clickStatusItem(_ item: AXUIElement) -> Bool {
        guard let position = axPosition(item), let size = axSize(item),
              size.width > 1, size.height > 1,
              let source = CGEventSource(stateID: .hidSystemState) else { return false }
        savedPointer = NSEvent.mouseLocation
        let target = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                mouseCursorPosition: target, mouseButton: .left)?.post(tap: .cghidEventTap)
        print("live-app-probe: statusItem clicked at=(\(Int(target.x)),\(Int(target.y)))")
        return true
    }

    private func restorePointer() {
        guard let saved = savedPointer,
              let source = CGEventSource(stateID: .hidSystemState) else { return }
        savedPointer = nil
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: CGPoint(x: saved.x, y: coordinateBaselineY() - saved.y),
                mouseButton: .left)?.post(tap: .cghidEventTap)
        print("live-app-probe: pointerRestored=true")
    }

    private func actionNames(_ element: AXUIElement) -> String {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let list = names as? [String] else { return "-" }
        return list.joined(separator: ",")
    }

    // MARK: 读取真实窗口标题（只读，用于交叉核对面板内容）

    private func otherAppWindowTitles() -> [String] {
        var titles: [String] = []
        for app in NSWorkspace.shared.runningApplications
        where app.processIdentifier != targetPID && app.activationPolicy == .regular {
            for element in appWindows(pid: app.processIdentifier) {
                guard axRole(element) == "AXWindow",
                      let title = axString(element, kAXTitleAttribute as String) else { continue }
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 4 { titles.append(trimmed) }
            }
        }
        return titles
    }

    // MARK: 工具

    private struct MenuItem {
        let title: String
        let enabled: Bool
        let element: AXUIElement
    }

    private func collectMenuItems(from element: AXUIElement, depth: Int) -> [MenuItem] {
        guard depth < 3 else { return [] }
        var result: [MenuItem] = []
        for child in axChildren(element) {
            let role = axRole(child)
            if role == (kAXMenuItemRole as String) {
                let title = axString(child, kAXTitleAttribute as String) ?? ""
                var ref: CFTypeRef?
                var enabled = true
                if AXUIElementCopyAttributeValue(child, kAXEnabledAttribute as CFString, &ref) == .success,
                   let value = ref {
                    enabled = cfBooleanValue(value) ?? true
                }
                if !title.isEmpty {
                    result.append(MenuItem(title: title, enabled: enabled, element: child))
                }
            }
            result.append(contentsOf: collectMenuItems(from: child, depth: depth + 1))
        }
        return result
    }

    /// 收集面板里的可访问性标签（标题/描述），用于核对真实窗口条目。
    private func collectLabels(from element: AXUIElement, depth: Int) -> [String] {
        guard depth < 6 else { return [] }
        var labels: [String] = []
        for attribute in [kAXTitleAttribute as String,
                          kAXDescriptionAttribute as String,
                          kAXValueAttribute as String] {
            if let value = axString(element, attribute), !value.isEmpty {
                labels.append(value)
            }
        }
        for child in axChildren(element) {
            labels.append(contentsOf: collectLabels(from: child, depth: depth + 1))
        }
        return labels
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref else { return nil }
        return value as? String
    }

    private func retry(after delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func record(_ description: String, _ condition: Bool) {
        checks += 1
        if !condition {
            failures.append(description)
            print("live-app-probe: FAIL \(description)")
        }
    }

    private func finish() {
        print("live-app-probe: checks=\(checks) failures=\(failures.count) "
              + "result=\(failures.isEmpty ? "pass" : "fail")")
        exit(failures.isEmpty ? 0 : 1)
    }
}
