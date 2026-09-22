// 只读的 Dock AX 结构探针：开发/验证用，不写 Dock 设置、不点击、不移动鼠标、
// 不截图。输出角色、子节点数量、是否有选中子项、选中项的 bundle ID 与矩形，
// 以及系统命中测试结果，用于核对 Dock 内部结构在当前系统上的实际表现。

import Cocoa
import ApplicationServices
import ScreenCaptureKit

final class DockHoverProbe {
    private var observer: AXObserver?
    private var retained: Unmanaged<DockHoverProbe>?
    private var notificationCount = 0
    private var firstAppItemFrameAX: CGRect?

    func run() {
        guard AXIsProcessTrusted() else {
            print("dock-probe: no accessibility permission; result=unverified")
            exit(2)
        }
        guard let dockApp = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            print("dock-probe: Dock not running; result=unverified")
            exit(3)
        }
        let pid = dockApp.processIdentifier
        let root = AXUIElementCreateApplication(pid)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let screens = NSScreen.screens.map {
            "\(Int($0.frame.width))x\(Int($0.frame.height))@\(String(format: "%.1f", $0.backingScaleFactor))"
        }.joined(separator: ",")
        print("dock-probe: pid=\(pid) macOS=\(version.majorVersion).\(version.minorVersion)."
              + "\(version.patchVersion) screens=\(NSScreen.screens.count) [\(screens)]")
        var budget = 120
        dump(root: root, depth: 0, budget: &budget)
        hitTest()
        if let iconFrame = firstAppItemFrameAX {
            // 不移动系统指针：直接对已知 Dock 图标矩形内的坐标做只读命中测试，
            // 验证鼠标回退路径能解析出应用项。
            hitTestInsideDockItem(iconFrame)
        }
        verifyMultiDisplayGeometry()
        registerObserver(pid: pid, root: root)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            print("dock-probe: selected-children notifications in 2s = \(self.notificationCount)")
            self.teardown()
            print("dock-probe: observer teardown complete")
            exit(0)
        }
    }

    private func dump(root: AXUIElement, depth: Int, budget: inout Int) {
        guard depth <= 5, budget > 0 else { return }
        budget -= 1
        let role = axRole(root) ?? "?"
        let children = axChildren(root)
        let selected = selectedChildren(of: root)
        var line = String(repeating: "  ", count: depth)
        line += "role=\(role) children=\(children.count)"
        if !selected.isEmpty { line += " selected=\(selected.count)" }
        if role == "AXList" {
            let appItems = children.filter { isAppItem($0) }.count
            line += " appItems=\(appItems)"
            var selectedReadable = false
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(root, kAXSelectedChildrenAttribute as CFString,
                                             &value) == .success {
                selectedReadable = true
            }
            line += " selectedAttrReadable=\(selectedReadable)"
        }
        if let frame = axFrame(of: root) {
            line += " frame=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))"
        }
        if firstAppItemFrameAX == nil,
           let item = children.first(where: { isAppItem($0) }),
           let itemFrame = axFrame(of: item) {
            firstAppItemFrameAX = itemFrame
            line += " firstAppItemFrame=(\(Int(itemFrame.minX)),\(Int(itemFrame.minY)) "
                + "\(Int(itemFrame.width))x\(Int(itemFrame.height)))"
        }
        if let selectedItem = selected.first, let bundle = bundleIdentifier(of: selectedItem) {
            line += " selectedBundle=\(bundle)"
        }
        print(line)
        for child in children where children.count <= 64 {
            dump(root: child, depth: depth + 1, budget: &budget)
        }
    }

    private func hitTest() {
        let mouse = NSEvent.mouseLocation
        let axPoint = CGPoint(x: mouse.x, y: coordinateBaselineY() - mouse.y)
        var hit: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(system, Float(axPoint.x), Float(axPoint.y),
                                               &hit) == .success, let hit else {
            print("dock-probe: hit-test=miss")
            return
        }
        var node: AXUIElement? = hit
        var depth = 0
        while let current = node, depth < 5 {
            if let bundle = bundleIdentifier(of: current) {
                print("dock-probe: hit-test=appItem bundle=\(bundle) depth=\(depth)")
                return
            }
            node = parent(of: current)
            depth += 1
        }
        print("dock-probe: hit-test=no-app-item role=\(axRole(hit) ?? "?")")
    }

    /// 对给定 AX 坐标做系统命中测试（不移动指针），用于验证 Dock 图标命中解析。
    private func hitTestInsideDockItem(_ frame: CGRect) {
        let point = CGPoint(x: frame.midX, y: frame.midY)
        var hit: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y),
                                               &hit) == .success, let hit else {
            print("dock-probe: synthetic-hit=miss point=(\(Int(point.x)),\(Int(point.y)))")
            return
        }
        var node: AXUIElement? = hit
        var depth = 0
        while let current = node, depth < 5 {
            if let bundle = bundleIdentifier(of: current) {
                print("dock-probe: synthetic-hit=appItem bundle=\(bundle) depth=\(depth) "
                      + "point=(\(Int(point.x)),\(Int(point.y)))")
                return
            }
            node = parent(of: current)
            depth += 1
        }
        print("dock-probe: synthetic-hit=no-app-item role=\(axRole(hit) ?? "?") "
              + "point=(\(Int(point.x)),\(Int(point.y)))")
    }

    /// 用本机真实的 NSScreen frame/visibleFrame 复核三个 Dock 方向的面板归属与范围。
    private func verifyMultiDisplayGeometry() {
        for (index, screen) in NSScreen.screens.enumerated() {
            let iconSize = CGSize(width: 52, height: 52)
            let icons: [(String, NSRect, WindowBrowserDockEdge)] = [
                ("bottom", NSRect(x: screen.frame.midX - iconSize.width / 2,
                                  y: screen.frame.minY + 4,
                                  width: iconSize.width, height: iconSize.height), .bottom),
                ("left", NSRect(x: screen.frame.minX + 4,
                                y: screen.frame.midY - iconSize.height / 2,
                                width: iconSize.width, height: iconSize.height), .left),
                ("right", NSRect(x: screen.frame.maxX - 4 - iconSize.width,
                                 y: screen.frame.midY - iconSize.height / 2,
                                 width: iconSize.width, height: iconSize.height), .right)
            ]
            for (edgeName, icon, edge) in icons {
                let geometry = WindowBrowserGeometry.panelGeometry(
                    iconFrame: icon, edge: edge, screenFrame: screen.frame,
                    visibleFrame: screen.visibleFrame,
                    desiredSize: CGSize(width: 520, height: 460),
                    windowCount: 6)
                let contained = screen.visibleFrame.contains(geometry.panelFrame)
                let correctSide: Bool
                switch edge {
                case .bottom: correctSide = geometry.panelFrame.minY >= icon.maxY
                case .left: correctSide = geometry.panelFrame.minX >= icon.maxX
                case .right: correctSide = geometry.panelFrame.maxX <= icon.minX
                }
                let gapPoint: CGPoint
                switch edge {
                case .bottom:
                    gapPoint = CGPoint(x: icon.midX,
                                       y: (icon.maxY + geometry.panelFrame.minY) / 2)
                case .left:
                    gapPoint = CGPoint(x: (icon.maxX + geometry.panelFrame.minX) / 2,
                                       y: icon.midY)
                case .right:
                    gapPoint = CGPoint(x: (icon.minX + geometry.panelFrame.maxX) / 2,
                                       y: icon.midY)
                }
                print("dock-probe: screen[\(index)] \(edgeName) "
                      + "frame=(\(Int(screen.frame.width))x\(Int(screen.frame.height)) "
                      + "@\(String(format: "%.1f", screen.backingScaleFactor))) "
                      + "panel=(\(Int(geometry.panelFrame.minX)),\(Int(geometry.panelFrame.minY)) "
                      + "\(Int(geometry.panelFrame.width))x\(Int(geometry.panelFrame.height))) "
                      + "contained=\(contained) side=\(correctSide) "
                      + "transition=\(geometry.transitionRegion.contains(gapPoint)) "
                      + "columns=\(geometry.columns)")
            }
        }
    }

    private func registerObserver(pid: pid_t, root: AXUIElement) {
        guard AXObserverCreate(pid, { _, _, notification, refcon in
            guard let refcon else { return }
            let probe = Unmanaged<DockHoverProbe>.fromOpaque(refcon).takeUnretainedValue()
            if notification as String == kAXSelectedChildrenChangedNotification as String {
                probe.notificationCount += 1
            }
        }, &observer) == .success, let observer else {
            print("dock-probe: observer creation failed")
            return
        }
        retained = Unmanaged.passRetained(self)
        let refcon = retained?.toOpaque()
        let lists = collectLists(in: root)
        for list in lists {
            let result = AXObserverAddNotification(observer, list,
                                                   kAXSelectedChildrenChangedNotification as CFString,
                                                   refcon)
            print("dock-probe: register selected-children list=\(axRole(list) ?? "?") result=\(result.rawValue)")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        print("dock-probe: observer registered lists=\(lists.count)")
    }

    private func teardown() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer),
                                  .commonModes)
            self.observer = nil
        }
        retained?.release()
        retained = nil
    }

    private func collectLists(in root: AXUIElement) -> [AXUIElement] {
        var lists: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 120 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let children = axChildren(element)
            if axRole(element) == "AXList", children.contains(where: { isAppItem($0) }) {
                lists.append(element)
                continue
            }
            guard depth < 5 else { continue }
            for child in children where children.count <= 64 {
                queue.append((child, depth + 1))
            }
        }
        return lists
    }

    private func isAppItem(_ element: AXUIElement) -> Bool {
        bundleIdentifier(of: element) != nil
    }

    private func bundleIdentifier(of element: AXUIElement) -> String? {
        guard let url = urlFromAXAttribute(element, kAXURLAttribute as String) else { return nil }
        guard url.path.hasSuffix(".app") else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    private func selectedChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedChildrenAttribute as CFString,
                                            &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString,
                                            &value) == .success,
              let parent = value, CFGetTypeID(parent) == AXUIElementGetTypeID() else {
            return nil
        }
        return (parent as! AXUIElement)
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        guard let position = axPosition(element), let size = axSize(element),
              size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: position, size: size)
    }
}

/// 只读的普通窗口发现探针：对当前运行中的 regular 应用调用生产发现函数，
/// 只输出 bundle ID 与窗口数量/可见性统计，不输出窗口标题或文档内容。
final class WindowCatalogProbe {
    func run() {
        guard AXIsProcessTrusted() else {
            print("catalog-probe: no accessibility permission; result=unverified")
            exit(2)
        }
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .filter { $0.processIdentifier != getpid() }
        // 主线程心跳：目录发现（同步 AX 读取）在后台队列执行时，主线程不应出现长间隔。
        var lastHeartbeat = CFAbsoluteTimeGetCurrent()
        var maxMainGapMilliseconds = 0
        let heartbeat = Timer.scheduledTimer(withTimeInterval: 0.005, repeats: true) { _ in
            let now = CFAbsoluteTimeGetCurrent()
            maxMainGapMilliseconds = max(maxMainGapMilliseconds,
                                         Int((now - lastHeartbeat) * 1000))
            lastHeartbeat = now
        }
        heartbeat.tolerance = 0.002
        DispatchQueue.global(qos: .userInitiated).async {
            var totalWindows = 0
            var emptyApps = 0
            var failedApps = 0
            var durations: [Double] = []
            var sampleWindow: DiscoveredWindowDescriptor?
            let startedAt = CFAbsoluteTimeGetCurrent()
            for app in apps {
                let bundle = app.bundleIdentifier ?? "<unknown>"
                let appStartedAt = CFAbsoluteTimeGetCurrent()
                let result = WindowBrowserDiscovery.discover(
                    pid: app.processIdentifier, overlayIDs: [], excludedBundleIDs: [])
                let tookMilliseconds = (CFAbsoluteTimeGetCurrent() - appStartedAt) * 1000
                durations.append(tookMilliseconds)
                switch result {
                case .success(let descriptors), .partial(let descriptors, _):
                    totalWindows += descriptors.count
                    if sampleWindow == nil { sampleWindow = descriptors.first }
                    let minimized = descriptors.filter(\.isMinimized).count
                    let offscreen = descriptors.filter { !$0.isOnScreen }.count
                    // 与 WindowServer 交叉核对：layer-0、可见 alpha、有几何的窗口数。
                    let cgWindows = WindowListCache.shared.allWindows(ofPID: app.processIdentifier)
                        .filter { info in
                            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
                            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0
                            guard layer == 0, alpha > 0.05,
                                  let bounds = cgWindowBounds(info) else { return false }
                            return bounds.width > 1 && bounds.height > 1
                        }
                        .filter { info in
                            guard let number = info[kCGWindowNumber as String] as? NSNumber else {
                                return false
                            }
                            return !isDesktopWidgetWindow(id: CGWindowID(number.uint32Value))
                        }
                    let cgCount = cgWindows.count
                    // “像真实窗口”的子集：有尺寸、有标题。辅助/帮助窗口通常两者都不满足。
                    let cgWindowLike = cgWindows.filter { info in
                        guard let bounds = cgWindowBounds(info),
                              bounds.width > 300, bounds.height > 200 else { return false }
                        return !cleanDisplayTitle(cgWindowName(info)).isEmpty
                    }.count
                    print("catalog-probe: \(bundle) windows=\(descriptors.count) "
                          + "minimized=\(minimized) offscreen=\(offscreen) "
                          + "cgLayer0=\(cgCount) cgWindowLike=\(cgWindowLike) "
                          + "took=\(Int(tookMilliseconds))ms")
                case .empty:
                    emptyApps += 1
                    print("catalog-probe: \(bundle) empty took=\(Int(tookMilliseconds))ms")
                case .failure(let reason):
                    failedApps += 1
                    print("catalog-probe: \(bundle) failure=\(reason) "
                          + "took=\(Int(tookMilliseconds))ms")
                case .timedOut:
                    failedApps += 1
                    print("catalog-probe: \(bundle) timeout took=\(Int(tookMilliseconds))ms")
                }
            }
            let totalMilliseconds = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
            let slowest = durations.max() ?? 0
            if let sample = sampleWindow {
                let key = WindowKey(
                    application: ApplicationInstanceKey(pid: sample.pid, generation: 1),
                    originalWindowID: sample.originalWindowID, windowGeneration: 1)
                if let element = WindowBrowserTargetResolver.enumerate(key: key) {
                    func medianMilliseconds(_ options: WindowBrowserTargetResolver.Options) -> Int {
                        var samples: [Int] = []
                        for _ in 0..<3 {
                            let started = CFAbsoluteTimeGetCurrent()
                            _ = WindowBrowserTargetResolver.inspect(element, key: key,
                                                                   options: options)
                            samples.append(Int((CFAbsoluteTimeGetCurrent() - started) * 1000))
                        }
                        return samples.sorted()[1]
                    }
                    print("catalog-probe: resolve identity="
                          + "\(medianMilliseconds([]))ms geometry="
                          + "\(medianMilliseconds(.geometry))ms capabilities="
                          + "\(medianMilliseconds(.capabilities))ms")
                }
            }
            heartbeat.invalidate()
            print("catalog-probe: apps=\(apps.count) windows=\(totalWindows) "
                  + "empty=\(emptyApps) failed=\(failedApps) "
                  + "total=\(Int(totalMilliseconds))ms slowestApp=\(Int(slowest))ms "
                  + "mainThreadMaxGap=\(maxMainGapMilliseconds)ms")
            exit(0)
        }
    }
}

/// 单窗截图探针：只捕获 WindowShade 自己创建的一个探针窗口，测量真实
/// SCScreenshotManager 单窗捕获的延迟、像素上限与内容，用来验证新缩略图路径。
/// 不捕获用户窗口、不写盘、不联网。
final class WindowBrowserCaptureProbe {
    private var window: NSWindow?
    private var occluder: NSWindow?

    func run() {
        guard hasScreenRecordingPermission() else {
            print("capture-probe: no screen recording permission; result=unverified")
            exit(2)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "WindowShade capture probe"
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemBlue.cgColor
        window.contentView = content
        window.center()
        // 探针窗口需要真实可见并产生明显 damage，否则 ScreenCaptureKit 对
        // 被遮挡/静态窗口只会极低频出帧，测不到配置的 8fps 上限。
        window.level = .floating
        // 不调用 makeKeyAndOrderFront/NSApp.activate：探针不得改变用户的前台应用。
        window.orderFrontRegardless()
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.presentOccluderAndReport(probeWindow: window)
        }
    }

    /// 在蓝窗中央盖一个红窗：单窗过滤器捕获蓝窗时，中心像素应仍是蓝色。
    /// 若实现退回成整屏截图后裁切，中心会拍到红窗内容。
    private func presentOccluderAndReport(probeWindow: NSWindow) {
        let occluder = NSWindow(contentRect: probeWindow.frame.offsetBy(dx: 30, dy: 30),
                                styleMask: [.titled], backing: .buffered, defer: false)
        occluder.title = "WindowShade occluder probe"
        occluder.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemRed.cgColor
        occluder.contentView = content
        occluder.level = .floating
        occluder.orderFrontRegardless()
        self.occluder = occluder
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.captureAndReport()
        }
    }

    private func captureAndReport() {
        guard let window, let id = cgWindowID(for: window) else {
            print("capture-probe: no window id")
            exit(3)
        }
        Task { @MainActor in
            guard let shareable = try? await SCShareableContent.current else {
                print("capture-probe: shareable content unavailable")
                exit(4)
            }
            guard let scWindow = shareable.windows.first(where: { $0.windowID == id }) else {
                print("capture-probe: probe window missing from shareable content")
                exit(5)
            }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let logical = window.frame.size
            let scale = window.backingScaleFactor
            for (label, limit) in [("card", CGSize(width: 512, height: 320)),
                                   ("selectedLarge", CGSize(width: 1024, height: 768))] {
                let sourceWidth = max(1, Int(ceil(logical.width * scale)))
                let sourceHeight = max(1, Int(ceil(logical.height * scale)))
                let outputScale = min(limit.width / CGFloat(sourceWidth),
                                      limit.height / CGFloat(sourceHeight), 1)
                let config = SCStreamConfiguration()
                config.width = max(1, Int(ceil(CGFloat(sourceWidth) * outputScale)))
                config.height = max(1, Int(ceil(CGFloat(sourceHeight) * outputScale)))
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                let started = CFAbsoluteTimeGetCurrent()
                guard let image = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config) else {
                    print("capture-probe: profile=\(label) capture failed")
                    continue
                }
                let milliseconds = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
                let pixel = Self.centerPixel(of: image).map { "(\($0.0),\($0.1),\($0.2))" } ?? "-"
                let verdict: String
                if let value = Self.centerPixel(of: image) {
                    // 探针窗口是 systemBlue，遮挡窗口是 systemRed。
                    let blueDominant = Int(value.2) > Int(value.0) + 40
                    verdict = label == "card" ? " blue=\(blueDominant)" : ""
                } else {
                    verdict = ""
                }
                print("capture-probe: profile=\(label) pixels=\(image.width)x\(image.height) "
                      + "source=\(sourceWidth)x\(sourceHeight) took=\(milliseconds)ms "
                      + "bytesPerRow=\(image.bytesPerRow) center=\(pixel)\(verdict)")
            }
            window.close()
            self.occluder?.close()
            exit(0)
        }
    }

    private static func centerPixel(of image: CGImage) -> (UInt8, UInt8, UInt8)? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1,
                                      bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (pixel[0], pixel[1], pixel[2])
    }
}

/// 回退命中路径的真实探针：使用生产 `DockHoverObserver`，但用给定指针坐标驱动
/// 命中检测（不移动系统指针）。验证“命中图标 → 产出目标”和“停在 Dock 但不在
/// 图标上 → 清除旧目标”这两条行为。
/// Dock 探针共享的只读几何查找：第一个可解析应用项的列表/图标/非图标位置。
enum DockProbeSupport {
    static func firstAppItemGeometry()
        -> (list: CGRect, item: CGRect, nonIconAX: CGRect?, bundle: String)? {
        guard let dockApp = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.dock" }) else { return nil }
        let root = AXUIElementCreateApplication(dockApp.processIdentifier)
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 120 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let children = axChildren(element)
            if axRole(element) == "AXList", let listFrame = axFrameForProbe(element) {
                var appFrames: [CGRect] = []
                var nonAppFrames: [CGRect] = []
                for child in children {
                    guard let frame = axFrameForProbe(child) else { continue }
                    if let url = urlFromAXAttribute(child, kAXURLAttribute as String),
                       url.path.hasSuffix(".app"),
                       Bundle(url: url)?.bundleIdentifier != nil {
                        appFrames.append(frame)
                    } else {
                        nonAppFrames.append(frame)
                    }
                }
                for child in children {
                    guard let url = urlFromAXAttribute(child, kAXURLAttribute as String),
                          url.path.hasSuffix(".app"),
                          let bundle = Bundle(url: url)?.bundleIdentifier,
                          let itemFrame = axFrameForProbe(child) else { continue }
                    let isolated = nonAppFrames.first { candidate in
                        candidate.width >= 12 && appFrames.allSatisfy {
                            !$0.insetBy(dx: -8, dy: -8).contains(
                                CGPoint(x: candidate.midX, y: candidate.midY))
                        }
                    }
                    return (listFrame, itemFrame, isolated, bundle)
                }
            }
            guard depth < 5 else { continue }
            for child in children where children.count <= 64 {
                queue.append((child, depth + 1))
            }
        }
        return nil
    }

    static func axFrameForProbe(_ element: AXUIElement) -> CGRect? {
        guard let position = axPosition(element), let size = axSize(element),
              size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// 轮询等待异步观察器结果；未满足条件时按 interval 重试，必要时先重发指针事件。
    static func poll(attempt: Int, maxAttempts: Int, interval: TimeInterval,
                     condition: @escaping () -> Bool,
                     retry: (() -> Void)? = nil,
                     completion: @escaping () -> Void) {
        if condition() || attempt >= maxAttempts {
            completion()
            return
        }
        if attempt == 2 { retry?() }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
            poll(attempt: attempt + 1, maxAttempts: maxAttempts, interval: interval,
                 condition: condition, retry: retry, completion: completion)
        }
    }
}

final class DockHoverPathProbe {
    private var observer: DockHoverObserver?
    private var target: DockHoverTarget?

    func run() {
        guard AXIsProcessTrusted() else {
            print("hover-probe: no accessibility permission; result=unverified")
            exit(2)
        }
        guard let geometry = firstDockAppItemGeometry() else {
            print("hover-probe: no dock app item; result=unverified")
            exit(3)
        }
        let observer = DockHoverObserver(onTarget: { [weak self] target in
            self?.target = target
        }, onClear: { [weak self] _ in
            self?.target = nil
        })
        self.observer = observer
        observer.start()
        let itemCenter = CGPoint(x: geometry.item.midX,
                                 y: coordinateBaselineY() - geometry.item.midY)
        let listRect = cocoaFrame(fromAXPosition: geometry.list.origin,
                                  size: geometry.list.size)
        let nonIconPoint = geometry.nonIconAX.map {
            CGPoint(x: $0.midX, y: coordinateBaselineY() - $0.midY)
        } ?? CGPoint(x: geometry.list.minX + 2, y: listRect.midY)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            observer.simulatePointer(at: itemCenter)
            // AX 命中与解析已移到后台队列：轮询等待结果（最多约 1.5s，必要时重发一次）。
            DockProbeSupport.poll(attempt: 0, maxAttempts: 10, interval: 0.15, condition: {
                self.target != nil
            }, retry: {
                observer.simulatePointer(at: itemCenter)
            }) {
                if let target = self.target {
                    print("hover-probe: icon-hit pid=\(target.pid) "
                          + "bundle=\(target.bundleIdentifier) "
                          + "expected=\(geometry.bundle) "
                          + "match=\(target.bundleIdentifier == geometry.bundle)")
                } else {
                    print("hover-probe: icon-hit did not resolve a target")
                }
                observer.simulatePointer(at: nonIconPoint)
                DockProbeSupport.poll(attempt: 0, maxAttempts: 10, interval: 0.15, condition: {
                    self.target == nil
                }) {
                    print("hover-probe: non-icon dock point ("
                          + "\(Int(nonIconPoint.x)),\(Int(nonIconPoint.y))) target="
                          + "\(self.target == nil ? "cleared" : "stale(\(self.target!.bundleIdentifier))")")
                    print("hover-probe: diagnostics notificationsReliable="
                          + "\(observer.usesNotifications) "
                          + "generation=\(observer.observerGeneration)")
                    observer.stop()
                    print("hover-probe: observer stopped")
                    exit(0)
                }
            }
        }
    }

    private func firstDockAppItemGeometry()
        -> (list: CGRect, item: CGRect, nonIconAX: CGRect?, bundle: String)? {
        DockProbeSupport.firstAppItemGeometry()
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let position = axPosition(element), let size = axSize(element),
              size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: position, size: size)
    }
}

/// 缩略图服务 + 真实单窗截图的端到端探针：只捕获本应用自己的探针窗口。
/// 验证同 key 共享一次系统截图、缓存命中不重复截图、失效后重新截图。
final class WindowThumbnailPathProbe {
    private final class RealBackend: WindowThumbnailBackend {
        let windowID: CGWindowID
        let logicalSize: CGSize
        let scale: CGFloat
        var captureCount = 0

        init(windowID: CGWindowID, logicalSize: CGSize, scale: CGFloat) {
            self.windowID = windowID
            self.logicalSize = logicalSize
            self.scale = scale
        }

        func capture(request: WindowThumbnailRequest,
                     completion: @escaping (Result<CGImage, WindowThumbnailFailure>) -> Void) {
            captureCount += 1
            Task { @MainActor in
                guard let shareable = try? await SCShareableContent.current,
                      let scWindow = shareable.windows.first(where: { $0.windowID == windowID }) else {
                    completion(.failure(.windowGone))
                    return
                }
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let sourceWidth = max(1, Int(ceil(logicalSize.width * scale)))
                let sourceHeight = max(1, Int(ceil(logicalSize.height * scale)))
                let outputScale = min(request.maxPixelSize.width / CGFloat(sourceWidth),
                                      request.maxPixelSize.height / CGFloat(sourceHeight), 1)
                let config = SCStreamConfiguration()
                config.width = max(1, Int(ceil(CGFloat(sourceWidth) * outputScale)))
                config.height = max(1, Int(ceil(CGFloat(sourceHeight) * outputScale)))
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                if let image = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config) {
                    completion(.success(image))
                } else {
                    completion(.failure(.captureFailed("single-window capture failed")))
                }
            }
        }

        func cancel(request: WindowThumbnailRequest) {}
    }

    private var window: NSWindow?

    func run() {
        guard hasScreenRecordingPermission() else {
            print("thumbnail-probe: no screen recording permission; result=unverified")
            exit(2)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "WindowShade thumbnail probe"
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemGreen.cgColor
        window.contentView = content
        window.center()
        window.orderFrontRegardless()
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.exerciseService(window: window)
        }
    }

    private func exerciseService(window: NSWindow) {
        guard let id = cgWindowID(for: window) else {
            print("thumbnail-probe: no window id")
            exit(3)
        }
        let backend = RealBackend(windowID: id, logicalSize: window.frame.size,
                                  scale: window.backingScaleFactor)
        let service = WindowThumbnailService(backend: backend)
        let key = WindowKey(application: ApplicationInstanceKey(pid: getpid(), generation: 1),
                            originalWindowID: id, windowGeneration: 1)
        var deliveries = 0
        func requestOnce(_ label: String) {
            _ = service.request(windowKey: key, purpose: .card,
                                logicalSize: window.frame.size,
                                onImage: { image in
                deliveries += 1
                print("thumbnail-probe: \(label) delivered \(image.width)x\(image.height) "
                      + "captures=\(backend.captureCount) cachedBytes=\(service.cachedCostBytes)")
            }, onFailure: { failure in
                print("thumbnail-probe: \(label) failed=\(failure)")
            })
        }
        // 同一 key 并发两次：只允许一次真实截图。
        requestOnce("first")
        requestOnce("second")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            // 第三次：命中缓存，不应新增截图。
            requestOnce("cached")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                // 失效后必须重新截图（旧结果不能复用）。
                service.invalidateAll()
                requestOnce("after-invalidate")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    print("thumbnail-probe: deliveries=\(deliveries) "
                          + "captures=\(backend.captureCount) "
                          + "serviceStarted=\(service.startedCount) "
                          + "serviceDelivered=\(service.deliveredCount) "
                          + "running=\(service.runningCaptureCount) "
                          + "cachedBytes=\(service.cachedCostBytes)")
                    window.close()
                    exit(0)
                }
            }
        }
    }
}

/// 低帧率实时预览流探针：只对 WindowShade 自己创建的探针窗口建立一路
/// `WindowStreamCapture(preview: true)`，测量首帧延迟、实测帧率与停止确认。
/// 用来在真机上验证普通窗口实时预览的捕获配置和折叠前的停流路径。
final class WindowStreamPathProbe {
    private var window: NSWindow?
    /// 生产里镜像层由 PinnedLivePreviewView 强持有；探针必须自己持有，
    /// 否则 weak 引用会立刻变 nil。
    private var mirrorLayer: AVSampleBufferDisplayLayer?
    private var contentTicker: Timer?
    private var tickerFires = 0
    private var activity: NSObjectProtocol?

    func run() {
        guard hasScreenRecordingPermission() else {
            print("stream-probe: no screen recording permission; result=unverified")
            exit(2)
        }
        // 正式启动的 WindowShade 持有全局 event tap，会关闭 App Nap；探针进程
        // 同样声明活动，否则后台被节流后 timer 与出帧率都测不准。
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "WindowShade stream probe")
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "WindowShade stream probe"
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.systemOrange.cgColor
        window.contentView = content
        window.center()
        window.orderFrontRegardless()
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            // 静态窗口 ScreenCaptureKit 几乎不出帧；用 15Hz 内容变化让 8fps 上限
            // 成为真正的限制条件，才能测到配置的帧率与镜像子集。
            let mover = NSView(frame: NSRect(x: 0, y: 100, width: 40, height: 60))
            mover.wantsLayer = true
            mover.layer?.backgroundColor = NSColor.black.cgColor
            content.addSubview(mover)
            var phase: CGFloat = 0
            self?.contentTicker = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0,
                                                       repeats: true) { [weak mover] _ in
                guard let mover else { return }
                self?.tickerFires += 1
                phase += 24
                if phase > 360 { phase = 0 }
                mover.frame.origin.x = phase
            }
            self?.startAndMeasure(window: window)
        }
    }

    private func startAndMeasure(window: NSWindow) {
        guard let id = cgWindowID(for: window) else {
            print("stream-probe: no window id")
            exit(3)
        }
        Task { @MainActor in
            guard let shareable = try? await SCShareableContent.current,
                  let scWindow = shareable.windows.first(where: { $0.windowID == id }) else {
                print("stream-probe: probe window missing from shareable content")
                exit(4)
            }
            let display = shareable.displays.max { lhs, rhs in
                lhs.frame.intersection(scWindow.frame).width
                    * lhs.frame.intersection(scWindow.frame).height
                    < rhs.frame.intersection(scWindow.frame).width
                    * rhs.frame.intersection(scWindow.frame).height
            }
            let capture = WindowStreamCapture(preview: true)
            // 同时挂一个镜像层，验证镜像投递路径真的收到采样帧。
            let mirror = AVSampleBufferDisplayLayer()
            self.mirrorLayer = mirror
            capture.mirrorLayer = mirror
            guard let measurement = await Self.measure(capture: capture, window: scWindow,
                                                       display: display) else {
                print("stream-probe: no frame delivered")
                exit(5)
            }
            print("stream-probe: configuredFPS=\(capture.configuredFrameRate) "
                  + "firstFrame=\(measurement.firstFrameMS)ms "
                  + "framesInWindow=\(measurement.frames)/"
                  + "\(measurement.windowMS)ms "
                  + "mirroredFrames=\(capture.mirroredFrameCount) "
                  + "tickerFires=\(self.tickerFires) "
                  + "visible=\(window.isVisible) "
                  + "onScreen=\(window.occlusionState.contains(.visible))")
            // 等价于 PinnedPreviewController.releaseMirror：只摘掉镜像层，
            // 不停止源流。关闭临时面板必须留下仍然运行的持久流。
            let framesBeforeMirrorRelease = capture.deliveredFrameCount
            let mirroredBeforeRelease = capture.mirroredFrameCount
            capture.mirrorLayer = nil
            try? await Task.sleep(nanoseconds: 500_000_000)
            print("stream-probe: afterMirrorRelease running=\(capture.isRunning) "
                  + "mirrorFrames=\(mirroredBeforeRelease)->\(capture.mirroredFrameCount) "
                  + "frames=\(framesBeforeMirrorRelease)->\(capture.deliveredFrameCount)")
            let stopError: Error? = await withCheckedContinuation { continuation in
                capture.stop { error in
                    continuation.resume(returning: error)
                }
            }
            let errorText = stopError.map { "\($0)" } ?? "none"
            let framesAfterStop = capture.deliveredFrameCount
            try? await Task.sleep(nanoseconds: 600_000_000)
            let stable = framesAfterStop == capture.deliveredFrameCount
            print("stream-probe: stopError=\(errorText) "
                  + "framesAfterStop=\(framesAfterStop) "
                  + "framesNow=\(capture.deliveredFrameCount) stable=\(stable)")
            self.contentTicker?.invalidate()
            self.contentTicker = nil
            window.close()
            exit(0)
        }
    }

    private static func measure(capture: WindowStreamCapture, window: SCWindow,
                                display: SCDisplay?)
        async -> (firstFrameMS: Int, frames: UInt64, windowMS: Int)? {
        let startedAt = CFAbsoluteTimeGetCurrent()
        do {
            try await capture.start(window: window, display: display)
        } catch {
            print("stream-probe: start failed \(error.localizedDescription)")
            return nil
        }
        var firstFrameMS: Int?
        for _ in 0..<60 {
            if capture.deliveredFrameCount > 0 {
                firstFrameMS = Int((CFAbsoluteTimeGetCurrent() - startedAt) * 1000)
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let firstFrameMS else { return nil }
        let countAtMark = capture.deliveredFrameCount
        let mark = CFAbsoluteTimeGetCurrent()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let elapsed = max(0.001, CFAbsoluteTimeGetCurrent() - mark)
        let frames = capture.deliveredFrameCount - countAtMark
        return (firstFrameMS, frames, Int(elapsed * 1000))
    }
}

/// 面板激活语义探针：验证 Dock 面板出现时不抢前台、不成为 key window；
/// 键盘面板按设计可以获得 key window 并把焦点交给搜索框。
final class WindowBrowserPanelProbe {
    func run() {
        let frame = NSRect(x: 320, y: 320, width: 460, height: 340)
        let frontmostBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let appActiveBefore = NSApp.isActive
        if ProcessInfo.processInfo.environment["WINDOWSHADE_PANEL_PROBE_SKIP_PRESENT"] == "1" {
            // 对照实验：不显示任何窗口，只看进程本身是否会被激活。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let frontmostAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                print("panel-probe: no-window frontmostBefore=\(frontmostBefore ?? "-") "
                      + "frontmostAfter=\(frontmostAfter ?? "-") "
                      + "unchanged=\(frontmostBefore == frontmostAfter) "
                      + "appActiveBefore=\(appActiveBefore) appActiveAfter=\(NSApp.isActive)")
                exit(0)
            }
            return
        }
        let dockPanel = WindowBrowserPanel(mode: .dock, frame: frame)
        dockPanel.browserContentView.update(mode: .dock, records: [], selection: nil,
                                            style: .grid, busyKeys: [], status: "probe")
        print("panel-probe: before-present appActive=\(NSApp.isActive) "
              + "policy=\(NSApp.activationPolicy().rawValue) key=\(dockPanel.isKeyWindow)")
        dockPanel.presentDockPanel()
        print("panel-probe: after-present appActive=\(NSApp.isActive) "
              + "key=\(dockPanel.isKeyWindow) visible=\(dockPanel.isVisible)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let frontmostAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            print("panel-probe: dock frontmostBefore=\(frontmostBefore ?? "-") "
                  + "frontmostAfter=\(frontmostAfter ?? "-") "
                  + "unchanged=\(frontmostBefore == frontmostAfter) "
                  + "key=\(dockPanel.isKeyWindow) "
                  + "appActiveBefore=\(appActiveBefore) appActiveAfter=\(NSApp.isActive) "
                  + "canBecomeKey=\(dockPanel.canBecomeKey)")
            dockPanel.orderOut(nil)
            let keyPanel = WindowBrowserPanel(mode: .keyboard, frame: frame)
            keyPanel.browserContentView.update(mode: .keyboard, records: [], selection: nil,
                                               style: .grid, busyKeys: [], status: "probe")
            keyPanel.presentKeyboardPanel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let key = keyPanel.isKeyWindow
                let searchFocused = keyPanel.browserContentView.searchFieldIsFocused
                print("panel-probe: keyboard key=\(key) searchFocused=\(searchFocused) "
                      + "canBecomeKey=\(keyPanel.canBecomeKey)")
                keyPanel.close()
                // 第三阶段：同一进程稍后再次显示 Dock 面板。
                // 首次显示可能被“从当前前台应用启动的新进程”规则激活，属于探针启动假象；
                // 这里验证稳态下的悬停面板是否仍然不抢前台。
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let before2 = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                    let activeBefore2 = NSApp.isActive
                    let dockPanel2 = WindowBrowserPanel(mode: .dock, frame: frame)
                    dockPanel2.browserContentView.update(mode: .dock, records: [],
                                                         selection: nil, style: .grid,
                                                         busyKeys: [], status: "probe")
                    dockPanel2.presentDockPanel()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        let after2 = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                        print("panel-probe: dock-second frontmostBefore=\(before2 ?? "-") "
                              + "frontmostAfter=\(after2 ?? "-") "
                              + "unchanged=\(before2 == after2) "
                              + "appActiveBefore=\(activeBefore2) "
                              + "appActiveAfter=\(NSApp.isActive) "
                              + "key=\(dockPanel2.isKeyWindow)")
                        dockPanel2.close()
                        self.checkAnimatedResize()
                    }
                }
            }
        }
    }

    /// 第四阶段：内容驱动的面板换尺寸时必须“窗口多大、内容就多大”。
    ///
    /// 用户实机反馈的截图就是这条不变量被破坏的中间帧：窗口还在旧尺寸（宽而矮的
    /// 列表面板），内容视图却已经被设成新尺寸（窄而高的缩略图面板），系统把偏小的
    /// 内容视图摆到窗口中间，于是露出几乎空的面板、被裁掉的卡片标题和变形的画面。
    private func checkAnimatedResize() {
        let listFrame = NSRect(x: 320, y: 320, width: 544, height: 129)
        let gridFrame = NSRect(x: 320, y: 320, width: 312, height: 236)
        let panel = WindowBrowserPanel(mode: .dock, frame: listFrame)
        panel.browserContentView.update(mode: .dock, records: [Self.probeRecord()],
                                        selection: nil, style: .grid, busyKeys: [],
                                        status: "")
        panel.presentDockPanel()
        panel.layoutIfNeeded()

        func mismatch() -> CGFloat {
            let content = panel.browserContentView.frame.size
            let windowSize = panel.frame.size
            return max(abs(content.width - windowSize.width), abs(content.height - windowSize.height))
        }

        let before = mismatch()
        panel.setPanelFrame(gridFrame, animated: true)
        let immediate = mismatch()
        var worst = immediate
        var samples = 0
        var widths: [CGFloat] = [panel.frame.width]
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            samples += 1
            worst = max(worst, mismatch())
            widths.append(panel.frame.width)
            if samples < 20 { return }
            timer.invalidate()
            let settled = mismatch()
            let frame = panel.frame
            let sizeMatches = abs(frame.width - gridFrame.width) < 0.5
                && abs(frame.height - gridFrame.height) < 0.5
            let interpolated = widths.contains { $0 > gridFrame.width + 1 && $0 < listFrame.width - 1 }
            print("panel-probe: animated-resize before=\(Int(before)) "
                  + "immediate=\(Int(immediate)) worst=\(Int(worst)) settled=\(Int(settled)) "
                  + "samples=\(samples) finalFrame=(\(Int(frame.width))x\(Int(frame.height))) "
                  + "matchesRequestedFrame=\(sizeMatches) interpolatedFrame=\(interpolated)")
            panel.orderOut(nil)
            panel.close()
            exit(0)
        }
    }

    private static func probeRecord() -> WindowRecord {
        let instance = ApplicationInstanceKey(pid: 4242, generation: 1)
        return WindowRecord(
            key: WindowKey(application: instance, originalWindowID: 91, windowGeneration: 1),
            bundleIdentifier: "probe.app",
            appName: "Probe",
            title: "Probe — 一个用来量尺寸的窗口",
            logicalFrame: CGRect(x: 120, y: 120, width: 980, height: 700),
            placementSource: .liveDiscovery,
            systemVisibility: .onScreen,
            shadeState: .normal,
            pinState: .none,
            capabilities: [.activate, .fold, .close],
            confidence: .confirmed,
            metadataRevision: 1,
            isMinimized: false,
            isOnScreen: true,
            isFoldedOffscreen: false,
            isManaged: false)
    }
}

/// 真实入口探针：直接构建设置页与状态栏菜单（不运行 AppDelegate 的启动序列，
/// 不启动传感器、不写 Dock 偏好、不触发救援）。菜单开关在结束时原样恢复。
final class WindowBrowserUIRouteProbe {
    func run() {
        let delegate = AppDelegate()
        let page = delegate.makeWindowBrowserSettingsPage()
        page.frame = NSRect(x: 0, y: 0, width: 560, height: 640)
        page.layoutSubtreeIfNeeded()
        var switches = 0
        var buttons = 0
        var fields = 0
        var recorders = 0
        func walk(_ view: NSView) {
            if view is NSSwitch { switches += 1 }
            if view is NSButton { buttons += 1 }
            if view is NSTextField { fields += 1 }
            if view is HotKeyRecorderView { recorders += 1 }
            view.subviews.forEach(walk)
        }
        walk(page)
        print("ui-probe: settingsPage switches=\(switches) buttons=\(buttons) "
              + "fields=\(fields) hotKeyRecorders=\(recorders) "
              + "fittingHeight=\(Int(page.fittingSize.height))")

        let keyboardWasEnabled = WindowBrowserSettings.keyboardPanelEnabled
        delegate.setupStatusItem()
        func browserMenuItem() -> NSMenuItem? {
            delegate.statusMenu.items.first { $0.title == "选择窗口…" }
        }
        let shortcutItems = delegate.statusMenu.items.filter { !$0.keyEquivalent.isEmpty }
            .map { "\($0.title)=\($0.keyEquivalent)" }
        print("ui-probe: menuShortcuts \(shortcutItems.joined(separator: " "))")
        let outline = delegate.statusMenu.items.map { item -> String in
            if item.isSeparatorItem { return "—" }
            return item.isSectionHeader ? "[\(item.title)]" : item.title
        }
        print("ui-probe: menuOutline \(outline.joined(separator: " | "))")
        let enabledItem = browserMenuItem()
        print("ui-probe: menuItem present=\(enabledItem != nil) "
              + "enabled=\(enabledItem?.isEnabled ?? false) "
              + "hasAction=\(enabledItem?.action != nil)")
        WindowBrowserSettings.keyboardPanelEnabled = false
        delegate.rebuildMenu()
        let disabledItem = browserMenuItem()
        print("ui-probe: menuItemWhenDisabled present=\(disabledItem != nil) "
              + "enabled=\(disabledItem?.isEnabled ?? false)")
        WindowBrowserSettings.keyboardPanelEnabled = keyboardWasEnabled
        delegate.rebuildMenu()
        let restoredItem = browserMenuItem()
        print("ui-probe: menuItemRestored enabled=\(restoredItem?.isEnabled ?? false) "
              + "settingsRestored=\(WindowBrowserSettings.keyboardPanelEnabled == keyboardWasEnabled)")
        exit(0)
    }
}

/// 空闲成本探针：临时关闭 Dock 开关、启动窗口浏览控制器并观察一秒，
/// 验证“功能关闭时新增常驻系统查询为零”，然后把设置原样恢复并停止控制器。
final class WindowBrowserIdleProbe {
    func run() {
        let dockWasEnabled = WindowBrowserSettings.dockEnabled
        WindowBrowserSettings.dockEnabled = false
        let delegate = AppDelegate()
        let controller = WindowBrowserController(owner: delegate)
        controller.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("idle-probe: dockEnabled=false axQueries=\(controller.axQueryCount) "
                  + "thumbnailsInFlight=\(controller.thumbnails.inFlightCount) "
                  + "thumbnailBytes=\(controller.thumbnails.cachedCostBytes)")
            controller.stop()
            WindowBrowserSettings.dockEnabled = dockWasEnabled
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                print("idle-probe: afterStop axQueries=\(controller.axQueryCount) "
                      + "thumbnailsInFlight=\(controller.thumbnails.inFlightCount) "
                      + "thumbnailBytes=\(controller.thumbnails.cachedCostBytes) "
                      + "settingsRestored=\(WindowBrowserSettings.dockEnabled == dockWasEnabled)")
                exit(0)
            }
        }
    }
}

/// 真实鼠标悬停探针：把指针移到 Dock 图标上约 1.2 秒再**原样放回**，用来验证
/// AX 选中子项通知是否随真实悬停触发。只做悬停，不点击、不激活、不打开任何东西。
final class DockHoverLiveProbe {
    private var observer: DockHoverObserver?
    private var target: DockHoverTarget?
    private var savedPointer: NSPoint?

    func run() {
        guard AXIsProcessTrusted() else {
            print("hover-live: no accessibility permission; result=unverified")
            exit(2)
        }
        guard let geometry = DockProbeSupport.firstAppItemGeometry() else {
            print("hover-live: no dock app item; result=unverified")
            exit(3)
        }
        savedPointer = NSEvent.mouseLocation
        let observer = DockHoverObserver(onTarget: { [weak self] target in
            self?.target = target
        }, onClear: { [weak self] _ in
            self?.target = nil
        })
        self.observer = observer
        observer.start()
        let iconAX = CGPoint(x: geometry.item.midX, y: geometry.item.midY)
        let nonIconAX = geometry.nonIconAX.map { CGPoint(x: $0.midX, y: $0.midY) }

        // 等 Dock 树异步发现完成，再真正移动指针。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.postMouseMove(toAX: iconAX)
            // 通知与兜底命中都是异步的，轮询等待结果（必要时重发一次指针事件）。
            DockProbeSupport.poll(attempt: 0, maxAttempts: 12, interval: 0.15, condition: {
                self.target != nil
            }, retry: {
                self.postMouseMove(toAX: iconAX)
            }) {
                let notifications = observer.usesNotifications
                let resolved = self.target?.bundleIdentifier
                let targetFrame = self.target.map {
                    "(\(Int($0.iconFrameAX.minX)),\(Int($0.iconFrameAX.minY)) "
                        + "\(Int($0.iconFrameAX.width))x\(Int($0.iconFrameAX.height)))"
                } ?? "-"
                print("hover-live: icon notificationsReliable=\(notifications) "
                      + "target=\(resolved ?? "none") expected=\(geometry.bundle) "
                      + "match=\(resolved == geometry.bundle) "
                      + "point=(\(Int(iconAX.x)),\(Int(iconAX.y))) "
                      + "expectedFrame=(\(Int(geometry.item.minX)),\(Int(geometry.item.minY)) "
                      + "\(Int(geometry.item.width))x\(Int(geometry.item.height))) "
                      + "targetFrame=\(targetFrame)")
                // 非图标位置（分隔符）再验证一次“旧目标被清除”。
                if let nonIconAX {
                    self.postMouseMove(toAX: nonIconAX)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        let cleared = self.target == nil
                        print("hover-live: non-icon target=\(cleared ? "cleared" : "stale")")
                        self.finish(observer: observer)
                    }
                } else {
                    self.finish(observer: observer)
                }
            }
        }
    }

    private func finish(observer: DockHoverObserver) {
        restorePointer()
        print("hover-live: pointerRestored=true")
        observer.stop()
        exit(0)
    }

    private func postMouseMove(toAX point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                                  mouseType: .mouseMoved,
                                  mouseCursorPosition: point,
                                  mouseButton: .left) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func restorePointer() {
        guard let saved = savedPointer else { return }
        // NSEvent 的 Cocoa 坐标转回 CGEvent 使用的左上原点坐标。
        postMouseMove(toAX: CGPoint(x: saved.x, y: coordinateBaselineY() - saved.y))
    }
}
