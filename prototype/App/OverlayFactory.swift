// 覆盖层工厂：按外观模式构建截图条 / 经典条 / 代理标题栏窗口，
// 复用简单条窗口池。作为 AppDelegate 扩展实现。

import Cocoa

extension AppDelegate {
    func makeBaseOverlay(axPos: CGPoint, width: CGFloat, height: CGFloat) -> NSWindow {
        let frame = cocoaFrame(fromAXPosition: axPos, size: CGSize(width: width, height: height))

        // 复用已回收的简单卷帘条窗口，避免频繁创建 NSWindow；池取不到才新建。
        let overlay = ShadeStripPool.shared.take()
            ?? OverlayWindow(contentRect: frame, styleMask: .borderless,
                             backing: .buffered, defer: false)
        overlay.isReleasedWhenClosed = false
        overlay.setFrame(frame, display: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        applyOverlayPresentation(overlay, bringForward: false)
        overlay.hasShadow = true
        overlay.collectionBehavior = [.managed, .fullScreenNone, .fullScreenDisallowsTiling]
        return overlay
    }

    func makeScreenshotOverlay(image: CGImage, axPos: CGPoint, width: CGFloat, height: CGFloat,
                                       buttons: [(CGRect, TrafficAction)], id: CGWindowID,
                                       windowManagement: WindowManagementCapability,
                                       trafficLights: ProxyTrafficLightConfiguration) -> NSWindow {
        if !buttons.isEmpty {
            let effectiveWindowManagement: WindowManagementCapability = trafficLights.style == .quickLook
                ? .fullScreen
                : windowManagement
            let frame = cocoaFrame(fromAXPosition: axPos, size: CGSize(width: width, height: height))
            var style: NSWindow.StyleMask = [.titled, .fullSizeContentView]
            if trafficLights.closeVisible { style.insert(.closable) }
            if trafficLights.minimizeVisible { style.insert(.miniaturizable) }
            if effectiveWindowManagement.isEnabled || trafficLights.zoomVisible { style.insert(.resizable) }
            let contentRect = NSWindow.contentRect(forFrameRect: frame, styleMask: style)
            let overlay = NativeProxyOverlayWindow(contentRect: contentRect, styleMask: style,
                                                   backing: .buffered, defer: false)
            overlay.delegate = overlay
            overlay.fixedTitlebarHeight = frame.height
            overlay.allowsHorizontalResize = false
            overlay.minimumReadableWidth = frame.width
            overlay.setFrame(frame, display: false)
            overlay.titleVisibility = .hidden
            overlay.titlebarAppearsTransparent = true
            overlay.isMovableByWindowBackground = true
            overlay.isReleasedWhenClosed = false
            overlay.acceptsMouseMovedEvents = true
            overlay.isOpaque = false
            overlay.backgroundColor = .clear
            overlay.hasShadow = true
            overlay.collectionBehavior = trafficLights.style == .quickLook
                ? [.managed, .fullScreenPrimary]
                : [.managed, .fullScreenNone, .fullScreenDisallowsTiling]
            overlay.minSize = NSSize(width: frame.width, height: frame.height)
            overlay.maxSize = effectiveWindowManagement == .fullScreen
                ? NSSize(width: 10000, height: 10000)
                : NSSize(width: 10000, height: frame.height)
            if #available(macOS 11.0, *) {
                overlay.titlebarSeparatorStyle = .none
                overlay.toolbarStyle = .unifiedCompact
            }

            let iv = TitleStripView(frame: NSRect(origin: .zero, size: frame.size))
            iv.image = NSImage(cgImage: image, size: frame.size)
            iv.imageScaling = .scaleAxesIndependently
            iv.onDoubleClick = { [weak self] in self?.unshade(id) }
            iv.onPreviewPeek = { [weak self] in self?.peekHoverPreview(id) }
            iv.onMoveEnded = { [weak self] frame in
                self?.noteUserMovedOverlay(id: id, frame: frame)
            }
            overlay.contentView = iv
            overlay.configureTrafficLightButtons(trafficLights)
            overlay.alignStandardTrafficButtons(to: buttons)
            overlay.configureWindowManagementButton(capability: effectiveWindowManagement)
            overlay.onAction = { [weak self] action in self?.handleTrafficLight(action, id) }
            overlay.onWindowManagementPopover = { [weak self] in self?.showRealWindowManagementPopover(id) }
            overlay.onFrameMoved = { [weak self] frame in
                self?.noteUserMovedOverlay(id: id, frame: frame)
            }
            overlay.onDragEnded = { [weak self] frame in
                self?.noteUserMovedOverlay(id: id, frame: frame)
            }
            overlay.onDoubleClick = { [weak self] in self?.unshade(id) }
            applyOverlayPresentation(overlay, bringForward: false)
            return overlay
        }

        let overlay = makeBaseOverlay(axPos: axPos, width: width, height: height)
        let frame = overlay.frame
        let iv = TitleStripView(frame: NSRect(origin: .zero, size: frame.size))
        iv.image = NSImage(cgImage: image, size: frame.size)
        iv.imageScaling = .scaleAxesIndependently
        iv.onDoubleClick = { [weak self] in self?.unshade(id) }
        iv.onPreviewPeek = { [weak self] in self?.peekHoverPreview(id) }
        iv.onMoveEnded = { [weak self] frame in
            self?.noteUserMovedOverlay(id: id, frame: frame)
        }
        if !buttons.isEmpty {                                  // 在真灯位置盖透明命中区
            let union = buttons.dropFirst().reduce(buttons[0].0) { $0.union($1.0) }
            let tlFrame = union.insetBy(dx: -4, dy: -4)
            let local = buttons.map { ($0.0.offsetBy(dx: -tlFrame.minX, dy: -tlFrame.minY), $0.1) }
            let tl = TrafficLightsView(frame: tlFrame, lights: local)
            tl.onAction = { [weak self] action in self?.handleTrafficLight(action, id) }
            iv.addSubview(tl)
        }
        overlay.contentView = iv
        overlay.invalidateShadow()                 // 阴影跟随（已镜像的）圆角轮廓
        return overlay
    }

    func makeClassicOverlay(axPos: CGPoint, width: CGFloat, height: CGFloat,
                                    pid: pid_t, appName: String, title: String, id: CGWindowID) -> NSWindow {
        let overlay = makeBaseOverlay(axPos: axPos, width: width, height: height)
        overlay.hasShadow = false
        let view = ClassicTitleStripView(frame: NSRect(origin: .zero, size: overlay.frame.size),
                                         appName: appName, windowTitle: title,
                                         palette: classicPalette(pid: pid))
        view.onDoubleClick = { [weak self] in self?.unshade(id) }
        view.onAction = { [weak self] action in self?.handleClassicAction(action, id) }
        view.onMoveEnded = { [weak self] frame in
            self?.noteUserMovedOverlay(id: id, frame: frame)
        }
        overlay.contentView = view
        overlay.invalidateShadow()
        return overlay
    }

    func makeProxyOverlay(axPos: CGPoint, width: CGFloat, height: CGFloat,
                                  pid: pid_t, appName: String, title: String, id: CGWindowID,
                                  canResize: Bool, windowManagement: WindowManagementCapability,
                                  trafficLights: ProxyTrafficLightConfiguration) -> NSWindow {
        let effectiveWindowManagement: WindowManagementCapability = trafficLights.style == .quickLook
            ? .fullScreen
            : windowManagement
        let minimumReadableWidth = NativeProxyTitleContentView.minimumReadableWindowWidth(
            appName: appName,
            windowTitle: title,
            hasIcon: runningApp(pid: pid)?.icon != nil,
            trafficLightSlots: trafficLights.visibleSlotCount
        )
        let displayWidth = canResize ? width : max(width, minimumReadableWidth)
        let frame = cocoaFrame(fromAXPosition: axPos, size: CGSize(width: displayWidth, height: height))
        var style: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        if trafficLights.closeVisible { style.insert(.closable) }
        if trafficLights.minimizeVisible { style.insert(.miniaturizable) }
        if canResize || effectiveWindowManagement.isEnabled || trafficLights.zoomVisible { style.insert(.resizable) }
        let contentRect = NSWindow.contentRect(forFrameRect: frame, styleMask: style)
        let overlay = NativeProxyOverlayWindow(contentRect: contentRect, styleMask: style,
                                               backing: .buffered, defer: false)
        overlay.delegate = overlay
        overlay.fixedTitlebarHeight = frame.height
        overlay.allowsHorizontalResize = canResize
        overlay.allowsWindowManagement = effectiveWindowManagement.isEnabled
        overlay.minimumReadableWidth = minimumReadableWidth
        overlay.usesProxyTitleLayout = true
        overlay.trafficLightConfiguration = trafficLights
        overlay.setFrame(frame, display: false)
        overlay.title = proxyDisplayTitle(appName: appName, windowTitle: title)
        overlay.titleVisibility = .hidden
        overlay.titlebarAppearsTransparent = true
        overlay.isMovableByWindowBackground = true
        overlay.isReleasedWhenClosed = false
        overlay.acceptsMouseMovedEvents = true
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = true
        overlay.collectionBehavior = trafficLights.style == .quickLook
            ? [.managed, .fullScreenPrimary]
            : [.managed, .fullScreenNone, .fullScreenDisallowsTiling]
        if canResize {
            overlay.minSize = NSSize(width: overlay.minimumReadableWidth, height: frame.height)
            overlay.maxSize = effectiveWindowManagement == .fullScreen
                ? NSSize(width: 10000, height: 10000)
                : NSSize(width: 10000, height: frame.height)
        } else if effectiveWindowManagement.isEnabled {
            overlay.minSize = NSSize(width: frame.width, height: frame.height)
            overlay.maxSize = effectiveWindowManagement == .fullScreen
                ? NSSize(width: 10000, height: 10000)
                : NSSize(width: 10000, height: frame.height)
        } else {
            overlay.minSize = NSSize(width: frame.width, height: frame.height)
            overlay.maxSize = NSSize(width: frame.width, height: frame.height)
        }
        if #available(macOS 11.0, *) {
            overlay.titlebarSeparatorStyle = .none
            overlay.toolbarStyle = .unifiedCompact
        }

        if let content = overlay.contentView {
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.clear.cgColor

            let material = NSVisualEffectView(frame: content.bounds)
            material.autoresizingMask = [.width, .height]
            material.material = .titlebar
            material.blendingMode = .behindWindow
            material.state = .active
            content.addSubview(material)

            let titleView = NativeProxyTitleContentView(frame: content.bounds,
                                                        appName: appName,
                                                        windowTitle: title,
                                                        appIcon: runningApp(pid: pid)?.icon,
                                                        trafficLightSlots: trafficLights.visibleSlotCount)
            titleView.autoresizingMask = [.width, .height]
            content.addSubview(titleView)
            overlay.configureTrafficLightButtons(trafficLights)
        }

        overlay.onAction = { [weak self] action in self?.handleTrafficLight(action, id) }
        overlay.onWindowManagementPopover = { [weak self] in self?.showRealWindowManagementPopover(id) }
        overlay.onPreviewPeek = { [weak self] in self?.peekHoverPreview(id) }
        overlay.onFrameMoved = { [weak self] frame in
            self?.noteUserMovedOverlay(id: id, frame: frame)
        }
        overlay.onDragEnded = { [weak self] frame in
            self?.noteUserMovedOverlay(id: id, frame: frame)
        }
        if canResize {
            overlay.onResize = { [weak self] window in self?.resizeShadedWindowFromProxy(id, proxyFrame: window.frame) }
        }
        overlay.configureWindowManagementButton(capability: effectiveWindowManagement)
        overlay.onDoubleClick = { [weak self] in self?.unshade(id) }
        applyOverlayPresentation(overlay, bringForward: false)
        return overlay
    }
}
