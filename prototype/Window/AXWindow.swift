// AX 辅助层：AXUIElement 读写、窗口几何/ID 解析、标题栏 chrome 探测、
// 按钮/指针交互。全部为文件级函数，可跨文件引用，不持有 AppDelegate 状态。

import Cocoa
import ApplicationServices
import Carbon.HIToolbox
import Darwin

func copyAXValue(_ element: AXUIElement, _ attr: String) -> AXValue? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success,
          let v = value else { return nil }
    // CF 类型在 Swift 里 `as?` 被编译器视为恒真，不能当运行时检查；
    // 先用类型 ID 校验外部返回值，再强转（此时类型已确认）。
    guard CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    return (v as! AXValue)
}

// AX 布尔属性可能是 CFBoolean，也可能是 toll-free 桥接的 NSNumber；都接受。
// CFBoolean 与 NSNumber 是 toll-free 桥接，统一走 NSNumber 读 boolValue，
// 不需要任何强转；第三方 app 返回其它类型时按 nil/false 处理。
func cfBooleanValue(_ value: CFTypeRef) -> Bool? {
    (value as? NSNumber)?.boolValue
}

func axPosition(_ e: AXUIElement) -> CGPoint? {
    guard let v = copyAXValue(e, kAXPositionAttribute) else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(v, .cgPoint, &p) ? p : nil
}

func axSize(_ e: AXUIElement) -> CGSize? {
    guard let v = copyAXValue(e, kAXSizeAttribute) else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(v, .cgSize, &s) ? s : nil
}

func setAXPosition(_ e: AXUIElement, _ p: CGPoint) {
    var p = p
    if let v = AXValueCreate(.cgPoint, &p) {
        AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, v)
    }
}

@discardableResult
func setAXSize(_ e: AXUIElement, _ s: CGSize) -> AXError {
    var s = s
    guard let v = AXValueCreate(.cgSize, &s) else { return .failure }
    return AXUIElementSetAttributeValue(e, kAXSizeAttribute as CFString, v)
}

@discardableResult
func setAXPositionReturningError(_ e: AXUIElement, _ p: CGPoint) -> AXError {
    var p = p
    guard let v = AXValueCreate(.cgPoint, &p) else { return .failure }
    return AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, v)
}

@discardableResult
func setAXMinimizedReturningError(_ e: AXUIElement, _ v: Bool) -> AXError {
    AXUIElementSetAttributeValue(e, kAXMinimizedAttribute as CFString,
                                 (v ? kCFBooleanTrue : kCFBooleanFalse))
}

func setAXMinimized(_ e: AXUIElement, _ v: Bool) {
    _ = setAXMinimizedReturningError(e, v)
}

@discardableResult
func setAXAppHidden(pid: pid_t, _ hidden: Bool) -> Bool {
    let app = AXUIElementCreateApplication(pid)
    let value: CFTypeRef = (hidden ? kCFBooleanTrue : kCFBooleanFalse)!
    return AXUIElementSetAttributeValue(app, kAXHiddenAttribute as CFString, value) == .success
}

func axBoolAttribute(_ e: AXUIElement, _ attr: String) -> Bool {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, attr as CFString, &ref) == .success,
          let value = ref else { return false }
    return cfBooleanValue(value) ?? false
}

func isAXSizeSettable(_ e: AXUIElement) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(e, kAXSizeAttribute as CFString, &settable) == .success else {
        return false
    }
    return settable.boolValue
}

func isAXAttributeSettable(_ e: AXUIElement, _ attr: String) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(e, attr as CFString, &settable) == .success else {
        return false
    }
    return settable.boolValue
}

func allowsProxyHorizontalResize(_ win: AXUIElement, pid: pid_t) -> Bool {
    guard windowPolicy(for: pid).allowsProxyHorizontalResize else { return false }
    return isAXSizeSettable(win)
}

func axButtonElement(_ win: AXUIElement, _ attr: String) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(win, attr as CFString, &ref) == .success,
          let button = ref else { return nil }
    guard CFGetTypeID(button) == AXUIElementGetTypeID() else { return nil }
    return (button as! AXUIElement)
}

func isAXButtonEnabled(_ win: AXUIElement, _ attr: String) -> Bool {
    guard let button = axButtonElement(win, attr),
          let p = axPosition(button),
          let s = axSize(button),
          s.width > 0, s.height > 0,
          p.x.isFinite, p.y.isFinite else { return false }

    var ref: CFTypeRef?
    if AXUIElementCopyAttributeValue(button, kAXEnabledAttribute as CFString, &ref) == .success,
       let value = ref {
        return cfBooleanValue(value) ?? false
    }
    return true
}

func axButtonFrame(_ win: AXUIElement, _ attr: String) -> CGRect? {
    guard let btn = axButtonElement(win, attr) else { return nil }
    guard let p = axPosition(btn), let s = axSize(btn) else { return nil }
    return CGRect(origin: p, size: s)
}

@discardableResult
func pressAXButton(_ win: AXUIElement, _ attr: String) -> Bool {
    guard let button = axButtonElement(win, attr) else { return false }
    return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
}

func pressAXFullScreenOrZoom(_ win: AXUIElement) {
    if pressAXButton(win, kAXFullScreenButtonAttribute as String) { return }
    pressAXButton(win, kAXZoomButtonAttribute as String)
}

func pressFullScreenShortcut() {
    let source = CGEventSource(stateID: .hidSystemState)
    let flags: CGEventFlags = [.maskCommand, .maskControl]
    let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_F), keyDown: true)
    down?.flags = flags
    let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_F), keyDown: false)
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

@discardableResult
func legacyPostMouseEvent(_ p: CGPoint, down: Bool) -> CGError? {
    typealias CGPostMouseEventFn = @convention(c) (CGPoint, boolean_t, CGButtonCount, boolean_t) -> CGError
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGPostMouseEvent") else {
        return nil
    }
    let fn = unsafeBitCast(symbol, to: CGPostMouseEventFn.self)
    return fn(p, boolean_t(0), 1, down ? boolean_t(1) : boolean_t(0))
}

func cocoaMousePoint(fromAXPoint p: CGPoint) -> CGPoint {
    CGPoint(x: p.x, y: coordinateBaselineY() - p.y)
}

func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

@discardableResult
func movePointerRaw(to p: CGPoint, includeDisplayMove: Bool) -> (CGError, CGError?) {
    CGDisplayShowCursor(CGMainDisplayID())
    CGAssociateMouseAndMouseCursorPosition(boolean_t(0))
    let warpErr = CGWarpMouseCursorPosition(p)
    var displayErr: CGError?
    if includeDisplayMove {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }),
           let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            let displayID = CGDirectDisplayID(number.uint32Value)
            let bounds = CGDisplayBounds(displayID)
            let local = CGPoint(x: p.x - bounds.minX, y: p.y - bounds.minY)
            displayErr = CGDisplayMoveCursorToPoint(displayID, local)
        } else {
            displayErr = CGDisplayMoveCursorToPoint(CGMainDisplayID(), p)
        }
    }
    CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
    return (warpErr, displayErr)
}

@discardableResult
func movePointerVisibly(to axPoint: CGPoint, reason: String) -> CGPoint {
    let expectedVisiblePoint = cocoaMousePoint(fromAXPoint: axPoint)
    let before = NSEvent.mouseLocation
    let beforeCG = CGEvent(source: nil)?.location ?? .zero

    let first = movePointerRaw(to: axPoint, includeDisplayMove: true)
    let afterAX = NSEvent.mouseLocation
    if distance(afterAX, expectedVisiblePoint) <= 3 {
        wlog("mouse: move reason=\(reason) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) event=(\(Int(axPoint.x)),\(Int(axPoint.y))) before=(\(Int(before.x)),\(Int(before.y))) beforeCG=(\(Int(beforeCG.x)),\(Int(beforeCG.y))) after=(\(Int(afterAX.x)),\(Int(afterAX.y))) warp=\(first.0.rawValue) display=\(first.1?.rawValue ?? -999) mode=ax")
        return axPoint
    }

    let flipped = expectedVisiblePoint
    let second = movePointerRaw(to: flipped, includeDisplayMove: false)
    let afterFlipped = NSEvent.mouseLocation
    let useFlipped = distance(afterFlipped, expectedVisiblePoint) < distance(afterAX, expectedVisiblePoint)
    let eventPoint = useFlipped ? flipped : axPoint
    wlog("mouse: move reason=\(reason) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) expected=(\(Int(expectedVisiblePoint.x)),\(Int(expectedVisiblePoint.y))) before=(\(Int(before.x)),\(Int(before.y))) beforeCG=(\(Int(beforeCG.x)),\(Int(beforeCG.y))) afterAX=(\(Int(afterAX.x)),\(Int(afterAX.y))) afterFlip=(\(Int(afterFlipped.x)),\(Int(afterFlipped.y))) first=(warp:\(first.0.rawValue),display:\(first.1?.rawValue ?? -999)) second=(warp:\(second.0.rawValue)) mode=\(useFlipped ? "flipped" : "ax")")
    return eventPoint
}

@discardableResult
func clickAXButton(_ win: AXUIElement, _ attr: String) -> Bool {
    guard let frame = axButtonFrame(win, attr) else { return false }
    let axPoint = CGPoint(x: frame.midX, y: frame.midY)
    return clickAXPoint(axPoint, reason: "click-\(attr)", logLabel: "attr=\(attr)")
}

@discardableResult
func clickAXPoint(_ axPoint: CGPoint, reason: String, logLabel: String) -> Bool {
    let eventPoint = movePointerVisibly(to: axPoint, reason: reason)
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
            mouseCursorPosition: eventPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) {
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        let legacyErr = legacyPostMouseEvent(eventPoint, down: true)
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                           mouseCursorPosition: eventPoint, mouseButton: .left)
        down?.setIntegerValueField(.mouseEventClickState, value: 1)
        down?.post(tap: .cghidEventTap)
        wlog("mouse: down legacy=\(legacyErr?.rawValue ?? -999) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) visible=(\(Int(NSEvent.mouseLocation.x)),\(Int(NSEvent.mouseLocation.y)))")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.034) {
        let legacyErr = legacyPostMouseEvent(eventPoint, down: false)
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                         mouseCursorPosition: eventPoint, mouseButton: .left)
        up?.setIntegerValueField(.mouseEventClickState, value: 1)
        up?.post(tap: .cghidEventTap)
        wlog("mouse: up legacy=\(legacyErr?.rawValue ?? -999) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) visible=(\(Int(NSEvent.mouseLocation.x)),\(Int(NSEvent.mouseLocation.y)))")
    }
    wlog("mouse: scheduled click \(logLabel) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y)))")
    return true
}

@discardableResult
func humanClickAXPoint(_ axPoint: CGPoint, reason: String, logLabel: String,
                       hoverDelay: TimeInterval = 0.18,
                       pressDuration: TimeInterval = 0.09) -> Bool {
    let eventPoint = movePointerVisibly(to: axPoint, reason: reason)
    let source = CGEventSource(stateID: .hidSystemState)

    for i in 0..<3 {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
            CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                    mouseCursorPosition: eventPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay) {
        CGAssociateMouseAndMouseCursorPosition(boolean_t(1))
        let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                           mouseCursorPosition: eventPoint, mouseButton: .left)
        down?.setIntegerValueField(.mouseEventClickState, value: 1)
        down?.post(tap: .cghidEventTap)
        wlog("mouse: human down \(logLabel) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) visible=(\(Int(NSEvent.mouseLocation.x)),\(Int(NSEvent.mouseLocation.y)))")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + hoverDelay + pressDuration) {
        let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                         mouseCursorPosition: eventPoint, mouseButton: .left)
        up?.setIntegerValueField(.mouseEventClickState, value: 1)
        up?.post(tap: .cghidEventTap)
        wlog("mouse: human up \(logLabel) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) visible=(\(Int(NSEvent.mouseLocation.x)),\(Int(NSEvent.mouseLocation.y)))")
    }
    wlog("mouse: scheduled human click \(logLabel) ax=(\(Int(axPoint.x)),\(Int(axPoint.y))) event=(\(Int(eventPoint.x)),\(Int(eventPoint.y))) hoverDelay=\(String(format: "%.2f", hoverDelay))")
    return true
}

@discardableResult
func clickAXFullScreenOrZoom(_ win: AXUIElement) -> Bool {
    if clickAXButton(win, kAXFullScreenButtonAttribute as String) { return true }
    if clickAXButton(win, kAXZoomButtonAttribute as String) { return true }
    return false
}

@discardableResult
func movePointerToAXButton(_ win: AXUIElement, _ attr: String) -> Bool {
    guard let frame = axButtonFrame(win, attr) else { return false }
    let axPoint = CGPoint(x: frame.midX, y: frame.midY)
    let eventPoint = movePointerVisibly(to: axPoint, reason: "move-\(attr)")
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
            mouseCursorPosition: eventPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
    return true
}

@discardableResult
func hoverAXButtonForWindowManagement(_ win: AXUIElement, _ attr: String) -> Bool {
    guard let frame = axButtonFrame(win, attr) else { return false }
    let axPoint = CGPoint(x: frame.midX, y: frame.midY)
    let eventPoint = movePointerVisibly(to: axPoint, reason: "hover-\(attr)")

    // The system Window Management popover is hover-driven. A single synthetic
    // move is easy to lose while the real app is activating, so keep the cursor
    // warm over the real green button for one native hover interval.
    for i in 0...10 {
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.08) {
            let source = CGEventSource(stateID: .hidSystemState)
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                    mouseCursorPosition: eventPoint, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }
    return true
}

func raiseAXWindow(_ win: AXUIElement) {
    AXUIElementPerformAction(win, kAXRaiseAction as CFString)
}

func focusAXWindow(_ win: AXUIElement, pid: pid_t) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, win)
    AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(win, kAXFocusedAttribute as CFString, kCFBooleanTrue)
}

// 三个交通灯在折叠条（view 坐标，左下原点，高 barH）里的命中区
func windowIsVisible(pos: CGPoint, size: CGSize) -> Bool {
    let winRect = cocoaFrame(fromAXPosition: pos, size: size)
    return NSScreen.screens.contains { $0.frame.intersects(winRect) }
}

func cgWindowIsVisible(id: CGWindowID, fallbackSize: CGSize) -> Bool? {
    guard let info = cgWindowInfo(id), let bounds = cgWindowBounds(info) else { return nil }
    let size = bounds.size.width > 0 && bounds.size.height > 0 ? bounds.size : fallbackSize
    let axPos = CGPoint(x: bounds.minX, y: bounds.minY)
    return windowIsVisible(pos: axPos, size: size)
}

func currentOnScreenWindowIDs() -> Set<CGWindowID> {
    WindowListCache.shared.onScreenIDs()
}

func cgWindowIsCurrentlyOnScreen(_ id: CGWindowID) -> Bool {
    WindowListCache.shared.isOnScreen(id)
}

func focusedWindow() -> AXUIElement? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let appEl = AXUIElementCreateApplication(app.processIdentifier)
    var win: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &win) == .success,
          let w = win else { return nil }
    guard CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
    return (w as! AXUIElement)
}

func cgWindowBounds(_ info: [String: Any]) -> CGRect? {
    guard let raw = info[kCGWindowBounds as String] else { return nil }
    var rect = CGRect.zero
    // CFDictionary 与 NSDictionary toll-free 桥接，as? 是真实运行时检查。
    guard let dict = raw as? NSDictionary else { return nil }
    return CGRectMakeWithDictionaryRepresentation(dict, &rect) ? rect : nil
}

func cocoaFrame(fromWindowServerBounds bounds: CGRect) -> NSRect {
    cocoaFrame(fromAXPosition: CGPoint(x: bounds.minX, y: bounds.minY), size: bounds.size)
}

func cgWindowName(_ info: [String: Any]) -> String {
    (info[kCGWindowName as String] as? String) ?? ""
}

func frameDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
    abs(a.minX - b.minX) + abs(a.minY - b.minY) +
    abs(a.width - b.width) + abs(a.height - b.height)
}

func publicWindowID(of e: AXUIElement) -> CGWindowID? {
    guard let pos = axPosition(e), let size = axSize(e) else { return nil }
    var pid: pid_t = 0
    guard AXUIElementGetPid(e, &pid) == .success, pid > 0 else { return nil }

    let axFrame = CGRect(origin: pos, size: size)
    let axTitle = cleanDisplayTitle(axTitle(e))
    // 在屏快速通道：列表远小于全量，聚焦/可见窗口（绝大多数调用）都能在这里解析。
    // 必须要求标题精确一致（strictTitle）：若目标窗口其实在另一个 Space（不在在屏
    // 列表里），同 app 在当前 Space 的同几何兄弟窗口会无竞争地被错误匹配——
    // 曾造成"折叠当前窗口折到了另一个 Space 的窗口"。标题对不上就回退全量列表，
    // 让所有候选同场竞争，结果与旧的全量逻辑一致。
    if let id = bestPublicWindowIDMatch(pid: pid, axFrame: axFrame, axTitle: axTitle,
                                        options: [.optionOnScreenOnly, .excludeDesktopElements],
                                        strictTitle: true) {
        return id
    }
    return bestPublicWindowIDMatch(pid: pid, axFrame: axFrame, axTitle: axTitle,
                                   options: [.optionAll, .excludeDesktopElements],
                                   strictTitle: false)
}

func bestPublicWindowIDMatch(pid: pid_t, axFrame: CGRect, axTitle: String,
                             options: CGWindowListOption, strictTitle: Bool = false) -> CGWindowID? {
    // 用缓存按 pid 预筛，只遍历目标 app 自己的窗口：一次折叠事务里同一份全量
    // 列表会被反复枚举（appWindows 对每个 AX 窗口都会做一次 ID 匹配），
    // 预筛后每次匹配从 O(全量窗口) 降到 O(本 app 窗口)。
    let windows = options.contains(.optionOnScreenOnly)
        ? WindowListCache.shared.onScreenWindows(ofPID: pid)
        : WindowListCache.shared.allWindows(ofPID: pid)
    var best: (id: CGWindowID, score: CGFloat)?

    for info in windows {
        guard let number = info[kCGWindowNumber as String] as? NSNumber,
              let bounds = cgWindowBounds(info) else { continue }

        let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        guard alpha > 0 else { continue }

        let delta = frameDistance(bounds, axFrame)
        guard delta <= 96 else { continue }

        var score = delta
        let name = cleanDisplayTitle(cgWindowName(info))
        // 严格模式（在屏快速通道）：标题必须精确一致，否则交给全量回退去竞争。
        if strictTitle, axTitle.isEmpty || name != axTitle { continue }
        if !axTitle.isEmpty && !name.isEmpty {
            if name == axTitle {
                score -= 24
            } else if name.localizedCaseInsensitiveContains(axTitle) ||
                        axTitle.localizedCaseInsensitiveContains(name) {
                score -= 8
            } else {
                score += 18
            }
        }

        let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        if layer != 0 { score += CGFloat(abs(layer)) * 2 }

        let candidate = (CGWindowID(number.uint32Value), score)
        if best == nil || candidate.1 < best!.score {
            best = candidate
        }
    }

    return best?.id
}

func windowID(of e: AXUIElement) -> CGWindowID? {
    if let id = publicWindowID(of: e) { return id }
    var id: CGWindowID = 0
    return _AXUIElementGetWindow(e, &id) == .success ? id : nil
}

func axRole(_ e: AXUIElement) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &v) == .success else { return nil }
    return v as? String
}

func axSubrole(_ e: AXUIElement) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXSubroleAttribute as CFString, &v) == .success else { return nil }
    return v as? String
}

// 从「点中的元素」往上找它所属的窗口
func containingWindow(_ el: AXUIElement) -> AXUIElement? {
    if axRole(el) == (kAXWindowRole as String) { return el }
    var winRef: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, kAXWindowAttribute as CFString, &winRef) == .success,
       let w = winRef {
        guard CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return (w as! AXUIElement)
    }
    return nil
}

func axChildren(_ el: AXUIElement) -> [AXUIElement] {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &ref) == .success,
          let arr = ref as? [AXUIElement] else { return [] }
    return arr
}

// 在窗口里找工具栏（含浅层递归），用于量出真实的标题栏+工具栏高度
func firstToolbar(_ el: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if depth > 2 { return nil }
    // 工具栏几乎总在子列表最前，前缀截断只为挡住极端 AX 树（数千子节点的窗口）。
    let kids = axChildren(el).prefix(axTraversalMaxChildrenPerNode)
    for c in kids where axRole(c) == (kAXToolbarRole as String) { return c }
    for c in kids { if let t = firstToolbar(c, depth: depth + 1) { return t } }
    return nil
}

func isChromeControlRole(_ role: String?) -> Bool {
    switch role ?? "" {
    case "AXButton", "AXPopUpButton", "AXMenuButton", "AXTextField", "AXSearchField",
         "AXComboBox", "AXCheckBox", "AXRadioButton", "AXSlider", "AXSegmentedControl",
         "AXTabGroup", "AXRadioGroup", "AXDisclosureTriangle", "AXImage", "AXLink":
        return true
    default:
        return false
    }
}

// 双击/三击标题栏时"不抢"的控件：只保护有真实双击语义的（地址栏/输入框选词、
// 按钮、滑块等）。标签例外——Safari 等浏览器对标签及标签条的双击没有任何行为
// （实测确认，2026-07），而标签条在空间语义上就是标题栏，放行给折叠。
// 误伤防线：命中点仍需通过 titlebarContains 的标题栏带校验，
// 对话框内容区里的真单选按钮不会走到折叠。
func stealsTitlebarDoubleClick(_ role: String?) -> Bool {
    switch role ?? "" {
    case "AXRadioButton", "AXTabGroup", "AXRadioGroup":
        return false
    default:
        return isChromeControlRole(role)
    }
}

struct TopChromeControlSample {
    let minTop: CGFloat
    let maxBottom: CGFloat
}

func collectTopChromeControlSamples(_ el: AXUIElement, winTop: CGFloat, winSize: CGSize,
                                    ignoredFrames: [CGRect] = [],
                                    depth: Int = 0, scanLimit: CGFloat = 120,
                                    nodeBudget: inout Int,
                                    into samples: inout [TopChromeControlSample]) {
    if depth > 6 || nodeBudget <= 0 { return }
    nodeBudget -= 1
    if isChromeControlRole(axRole(el)), let p = axPosition(el), let s = axSize(el) {
        let relTop = p.y - winTop
        let relBottom = relTop + s.height
        let frame = CGRect(origin: p, size: s)
        let ignored = ignoredFrames.contains { $0.insetBy(dx: -3, dy: -3).contains(CGPoint(x: frame.midX, y: frame.midY)) }
        let sane = s.width >= 4 && s.width <= winSize.width + 8 && s.height >= 4 && s.height <= 80 &&
                   relTop >= -4 && relTop <= scanLimit && relBottom <= scanLimit + 40
        if sane && !ignored {
            samples.append(TopChromeControlSample(minTop: max(0, relTop), maxBottom: relBottom))
        }
    }

    // 每节点最多展开前 40 个子节点：顶部 chrome 控件（交通灯、搜索框、工具栏
    // 按钮）几乎总在子列表最前，越界展开只会把预算浪费在内容区深层节点上。
    for c in axChildren(el).prefix(axTraversalMaxChildrenPerNode) {
        collectTopChromeControlSamples(c, winTop: winTop, winSize: winSize,
                                       ignoredFrames: ignoredFrames,
                                       depth: depth + 1, scanLimit: scanLimit,
                                       nodeBudget: &nodeBudget,
                                       into: &samples)
    }
}

func firstTopChromeControlCluster(of win: AXUIElement, winTop: CGFloat, winSize: CGSize,
                                  ignoredFrames: [CGRect] = [],
                                  scanLimit: CGFloat = 120) -> TopChromeControlSample? {
    var samples: [TopChromeControlSample] = []
    var nodeBudget = axTraversalNodeBudget
    collectTopChromeControlSamples(win, winTop: winTop, winSize: winSize,
                                   ignoredFrames: ignoredFrames,
                                   scanLimit: scanLimit,
                                   nodeBudget: &nodeBudget,
                                   into: &samples)
    guard !samples.isEmpty else { return nil }

    samples.sort {
        if abs($0.minTop - $1.minTop) > 0.5 { return $0.minTop < $1.minTop }
        return $0.maxBottom < $1.maxBottom
    }

    let gap: CGFloat = 8
    var clusters: [TopChromeControlSample] = []
    var current = samples[0]
    for sample in samples.dropFirst() {
        if sample.minTop <= current.maxBottom + gap {
            current = TopChromeControlSample(minTop: min(current.minTop, sample.minTop),
                                             maxBottom: max(current.maxBottom, sample.maxBottom))
        } else {
            clusters.append(current)
            current = sample
        }
    }
    clusters.append(current)

    return clusters.first
}

// 自绘/toolbar-less 窗口常把搜索框、标题、按钮藏在 AXSplitGroup/AXGroup 内部。
// 若顶部确实有控件，保留到控件底边，并补上与顶部相同的下 margin，避免截断控件。
func topChromeControlsHeight(of win: AXUIElement, winTop: CGFloat, winSize: CGSize,
                             titleBarBottom: CGFloat?,
                             allowBelowTitleBar: Bool = false) -> CGFloat? {
    let ignored = standardTrafficButtonFrames(of: win)
    guard let e = firstTopChromeControlCluster(of: win, winTop: winTop, winSize: winSize,
                                               ignoredFrames: ignored) else { return nil }
    if let titleBarBottom = titleBarBottom, !allowBelowTitleBar, e.minTop >= titleBarBottom - 2 {
        return nil
    }
    if allowBelowTitleBar, let titleBarBottom = titleBarBottom {
        let maxChromeStart = max(titleBarBottom + 44, CGFloat(76))
        if e.minTop > maxChromeStart { return nil }
    }
    return paddedChromeHeight(for: e, containerTop: 0)
}

func paddedChromeHeight(for e: TopChromeControlSample, containerTop: CGFloat) -> CGFloat {
    let topPadding = max(0, e.minTop - containerTop)
    let bottomPadding = max(4, min(topPadding, 28))
    return e.maxBottom + bottomPadding
}

func standardTrafficButtonFrames(of win: AXUIElement) -> [CGRect] {
    [
        kAXCloseButtonAttribute as String,
        kAXMinimizeButtonAttribute as String,
        kAXZoomButtonAttribute as String,
    ].compactMap { axButtonFrame(win, $0) }
}

func hasContentControlsBelowTitleBar(_ win: AXUIElement, winTop: CGFloat, winSize: CGSize,
                                     titleBarBottom: CGFloat?) -> Bool {
    guard let titleBarBottom = titleBarBottom else { return false }
    let ignored = standardTrafficButtonFrames(of: win)
    guard let e = firstTopChromeControlCluster(of: win, winTop: winTop, winSize: winSize,
                                               ignoredFrames: ignored) else { return false }
    return e.minTop >= titleBarBottom - 2
}

// 用原生交通灯按钮推算标题栏高度：交通灯在标题栏里垂直居中，
// 所以 高度 ≈ 2 ×（按钮中心到窗口顶的距离）。Electron 等自绘标题栏也适用，
// 因为交通灯始终是 macOS 原生绘制、AX 可读。
func trafficLightHeight(of win: AXUIElement, winTop: CGFloat) -> CGFloat? {
    guard let btn = axButtonElement(win, kAXCloseButtonAttribute as String) else { return nil }
    guard let bp = axPosition(btn), let bs = axSize(btn) else { return nil }
    let centerY = bp.y + bs.height / 2
    return (centerY - winTop) * 2
}

func trafficLightPaddedHeight(of win: AXUIElement, winTop: CGFloat) -> CGFloat? {
    let frames = standardTrafficButtonFrames(of: win)
    guard !frames.isEmpty else { return nil }
    let top = max(0, frames.map { $0.minY - winTop }.min() ?? 0)
    let bottom = max(0, frames.map { $0.maxY - winTop }.max() ?? 0)
    return bottom + min(top, 28)
}

// 折叠后要保留的 AX 下限：取「写死默认 / 交通灯推算 / 工具栏底边 / 顶部 AX 控件」最大值，
// 宁可略多保留一点内容，也不要把标题栏切断。
func chromeHeight(of win: AXUIElement, winTop: CGFloat, winSize: CGSize? = nil, pid: pid_t? = nil) -> CGFloat {
    let trafficH = trafficLightPaddedHeight(of: win, winTop: winTop) ??
                   trafficLightHeight(of: win, winTop: winTop)
    if let pid = pid, let fixed = fixedNonstandardChromeHeight(pid: pid) {
        return min(max(titleBarHeight, fixed), winSize?.height ?? fixed)
    }
    if let pid = pid, isAdobeApp(pid: pid) {
        let profile = adobeChromeProfile(for: win, pid: pid, size: winSize)
        let adobeH = max(profile.preservedChromeHeight, trafficH ?? titleBarHeight)
        return min(adobeH, min(winSize?.height ?? adobeH, 300))
    }
    if let pid = pid, let winSize = winSize,
       usesStandardTitleBarOnly(pid: pid) ||
        windowLooksToolbarlessStandardTitleBar(win,
                                               winTop: winTop,
                                               winSize: winSize,
                                               pid: pid,
                                               trafficLightHeight: trafficH) {
        return standardTitleBarCropHeight(of: win, winTop: winTop, winSize: winSize)
    }
    if pid.map({ usesStandardTitleBarOnly(pid: $0) }) ?? false {
        return min(trafficH ?? titleBarHeight, 300)
    }

    var h = titleBarHeight
    if let bh = trafficH { h = max(h, bh) }
    if let winSize = winSize, let pid = pid, needsControlPaddedChrome(pid: pid),
       let controlsH = topChromeControlsHeight(of: win, winTop: winTop, winSize: winSize,
                                               titleBarBottom: trafficH,
                                               allowBelowTitleBar: true) {
        return min(max(h, controlsH), min(winSize.height, 300))
    }

    let toolbar = firstToolbar(win)
    if let tb = toolbar, let tp = axPosition(tb), let ts = axSize(tb) {
        h = max(h, (tp.y + ts.height) - winTop)
    }
    if toolbar == nil, let winSize = winSize,
       let controlsH = topChromeControlsHeight(of: win, winTop: winTop, winSize: winSize,
                                               titleBarBottom: trafficH,
                                               allowBelowTitleBar: pid.map { isElpass(pid: $0) } ?? false) {
        h = max(h, controlsH)
    }
    return min(h, 300)
}

func titlebarHitHeight(of win: AXUIElement, id: CGWindowID,
                       winTop: CGFloat, winSize: CGSize, pid: pid_t) -> CGFloat {
    // 双击判定的第一下已解析过完整 profile 的话，第二下直接取缓存，不再重跑
    // 整棵 AX 子树的 chrome 计算（cache 按元素身份 + 窗口尺寸校验新鲜度）。
    if let cached = ChromeProfileCache.shared.cachedHitBarHeight(id: id, win: win, size: winSize) {
        return cached
    }
    let visualHeight = chromeHeight(of: win, winTop: winTop, winSize: winSize, pid: pid)
    if isAdobeApp(pid: pid) {
        let profile = adobeChromeProfile(for: win, pid: pid, size: winSize)
        return min(max(visualHeight, profile.hitChromeHeight), min(winSize.height, 300))
    }
    guard extendsTitlebarHitToApplicationFrame(pid: pid) else { return visualHeight }
    return visualHeight
}

// MARK: - 诊断日志（写到 /tmp/windowshade.log）
