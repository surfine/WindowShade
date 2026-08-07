// 卷帘条整理与专注 shelf：排列算法、桌面小组件避让、聚焦栏布局、
// 全部展开。作为 AppDelegate 扩展实现。

import Cocoa

extension AppDelegate {
    func restoreArrangedOverlayFrames(ids requestedIDs: Set<CGWindowID>? = nil) -> Bool {
        arrangedOverlayFrames = arrangedOverlayFrames.filter { shaded[$0.key]?.overlay != nil }
        let entries = arrangedOverlayFrames.compactMap { id, frame -> (CGWindowID, NSWindow, NSRect)? in
            if let requestedIDs, !requestedIDs.contains(id) { return nil }
            guard let overlay = shaded[id]?.overlay else { return nil }
            return (id, overlay, frame)
        }
        guard !entries.isEmpty else {
            if requestedIDs == nil {
                arrangedOverlayFrames.removeAll()
                focusSideStackFrames.removeAll()
            }
            return false
        }

        isProgrammaticOverlayArrangement = true
        defer { isProgrammaticOverlayArrangement = false }

        for (id, overlay, savedFrame) in entries {
            let frame = clampedFrame(savedFrame, margin: 8, preferredDisplayID: shaded[id]?.sourceDisplayID)
            if !framesAlmostEqual(overlay.frame, frame) {
                if let proxy = overlay as? NativeProxyOverlayWindow {
                    let oldResize = proxy.onResize
                    proxy.onResize = nil
                    proxy.setFrame(frame, display: true, animate: true)
                    proxy.onResize = oldResize
                } else {
                    overlay.setFrame(frame, display: true, animate: true)
                }
            }
            applyOverlayPresentation(overlay, bringForward: true)
            syncRestoreJournal(id: id, fromOverlayFrame: frame)
            focusPulledOutOverlayIDs.remove(id)
            focusSideStackFrames.removeValue(forKey: id)
            focusPulledOutRestoreFrames.removeValue(forKey: id)
            focusPulledOutOriginalSizes.removeValue(forKey: id)
            focusRejoinStackFrames.removeValue(forKey: id)
            focusRejoinEntries.removeValue(forKey: id)
            arrangedOverlayFrames.removeValue(forKey: id)
            wlog("arrange: restore id=\(id) frame=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))")
        }

        if let active = activePreview, active.trigger == .titlebarPeek {
            updateHoverPreviewFrame(active.ownerID)
        }
        scheduleMenuRebuild()
        return true
    }

    func restoreReferenceFrame(id: CGWindowID, overlay: NSWindow) -> NSRect {
        if focusPulledOutOverlayIDs.contains(id) {
            return focusPulledOutRestoreFrames[id] ?? overlay.frame
        }
        return arrangedOverlayFrames[id] ?? overlay.frame
    }

    func arrangedDisplayWidth(for state: ShadeState, overlay: NSWindow,
                                      visibleFrame: NSRect) -> CGFloat {
        guard state.appearanceMode == .proxyTitleBar else { return overlay.frame.width }
        let hasIcon = runningApp(pid: state.pid)?.icon != nil
        let fitting = NativeProxyTitleContentView.titleFittingWindowWidth(
            appName: state.appName,
            windowTitle: state.title,
            hasIcon: hasIcon
        )
        let minWidth = max(240, (overlay as? NativeProxyOverlayWindow)?.minimumReadableWidth ?? 0)
        let maxWidth = max(minWidth, visibleFrame.width)
        return min(max(fitting, minWidth), maxWidth)
    }

    func arrangedStairStepWidth(for state: ShadeState, visibleFrame: NSRect) -> CGFloat {
        let base = ProxyTitleLayoutMetrics.trafficLightDiameter * 0.95
        let clamped = min(visibleFrame.width * 0.05, base)
        switch state.appearanceMode {
        case .proxyTitleBar, .nativeScreenshot:
            return max(10, clamped)
        case .interactiveNative, .classicSemantic:
            return max(9, clamped * 0.9)
        }
    }

    func desktopWidgetScanLane(visibleFrame: NSRect) -> NSRect {
        let width = min(max(520, visibleFrame.width * 0.34), min(760, visibleFrame.width * 0.48))
        return NSRect(x: visibleFrame.minX,
                      y: visibleFrame.minY,
                      width: width,
                      height: visibleFrame.height)
    }

    func desktopWidgetFrames(for screen: NSScreen, visibleFrame: NSRect) -> [NSRect] {
        let desktopWidgetLayer = -2147483601
        let scanLane = desktopWidgetScanLane(visibleFrame: visibleFrame)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { info -> NSRect? in
            let layer = info[kCGWindowLayer as String] as? Int ?? Int.min
            guard layer == desktopWidgetLayer,
                  let bounds = cgWindowBounds(info) else { return nil }
            let frame = cocoaFrame(fromWindowServerBounds: bounds)
            guard screen.frame.intersects(frame),
                  scanLane.intersects(frame),
                  frame.width >= 96,
                  frame.height >= 80 else { return nil }
            return frame
        }
    }

    func desktopWidgetAvoidanceTop(for screen: NSScreen, visibleFrame: NSRect,
                                           widgetFrames: [NSRect]) -> CGFloat? {
        let leftLaneWidth = min(max(280, visibleFrame.width * 0.28), 420)
        let lane = NSRect(x: visibleFrame.minX,
                          y: visibleFrame.minY,
                          width: leftLaneWidth,
                          height: visibleFrame.height)
        let widgets = widgetFrames.filter { screen.frame.intersects($0) && lane.intersects($0) }
        guard !widgets.isEmpty else { return nil }
        let widgetBottom = widgets.map(\.minY).min() ?? visibleFrame.maxY
        let gap = max(18, proxyTitleBarHeight * 0.6)
        return max(visibleFrame.minY, widgetBottom - gap)
    }

    func desktopWidgetColumnFrame(for screen: NSScreen, visibleFrame: NSRect,
                                          widgetFrames: [NSRect]) -> NSRect? {
        let scanWidth = min(max(340, visibleFrame.width * 0.34), 560)
        let lane = NSRect(x: visibleFrame.minX,
                          y: visibleFrame.minY,
                          width: scanWidth,
                          height: visibleFrame.height)
        let widgets = widgetFrames.filter { screen.frame.intersects($0) && lane.intersects($0) }
        guard !widgets.isEmpty else { return nil }
        let minX = widgets.map(\.minX).min() ?? visibleFrame.minX
        let width = max(240, widgets.map(\.width).max() ?? NativeProxyTitleContentView.arrangedColumnFallbackWidth)
        return NSRect(x: minX, y: visibleFrame.minY, width: width, height: visibleFrame.height)
    }

    func arrangedColumnWidth(for screen: NSScreen, visibleFrame: NSRect,
                                     widgetFrames: [NSRect]) -> CGFloat {
        let widgetWidth = desktopWidgetColumnFrame(for: screen, visibleFrame: visibleFrame,
                                                   widgetFrames: widgetFrames)?.width
        let fallback = min(max(340, NativeProxyTitleContentView.arrangedColumnFallbackWidth),
                           visibleFrame.width - 24)
        return min(widgetWidth ?? fallback, visibleFrame.width - 24)
    }

    func arrangedColumnStartX(for screen: NSScreen, visibleFrame: NSRect,
                                      widgetFrames: [NSRect]) -> CGFloat {
        if let widgetColumn = desktopWidgetColumnFrame(for: screen, visibleFrame: visibleFrame,
                                                       widgetFrames: widgetFrames) {
            return widgetColumn.minX
        }
        return visibleFrame.minX + 12
    }

    func arrangedHousekeepingStartX(for screen: NSScreen, visibleFrame: NSRect) -> CGFloat {
        visibleFrame.minX + 12
    }

    func desktopWidgetTopExclusion(for screen: NSScreen, visibleFrame: NSRect,
                                           widgetFrames: [NSRect]) -> NSRect? {
        let topBand = NSRect(x: visibleFrame.minX,
                             y: visibleFrame.maxY - min(visibleFrame.height * 0.42, 460),
                             width: min(visibleFrame.width * 0.62, 760),
                             height: min(visibleFrame.height * 0.42, 460))
        let widgets = widgetFrames.filter { screen.frame.intersects($0) && topBand.intersects($0) }
        guard !widgets.isEmpty else { return nil }
        return widgets.dropFirst().reduce(widgets[0]) { $0.union($1) }
    }

    func focusShelfWidth(visibleFrame: NSRect) -> CGFloat {
        min(420, max(340, visibleFrame.width * 0.22))
    }

    func focusShelfFrame(index: Int, barHeight: CGFloat,
                                 screen: NSScreen, visibleFrame: NSRect,
                                 widgetTopExclusion: NSRect?) -> NSRect {
        let width = min(focusShelfWidth(visibleFrame: visibleFrame), visibleFrame.width - 24)
        let gap: CGFloat = 18
        let rowGap: CGFloat = 10
        let topY = visibleFrame.maxY - barHeight
        var startX = visibleFrame.minX + 12
        if let widgets = widgetTopExclusion,
           widgets.maxY > topY - rowGap {
            let widgetRight = widgets.maxX + gap
            if widgetRight + width <= visibleFrame.maxX {
                startX = max(startX, widgetRight)
            }
        }
        let usableWidth = max(width, visibleFrame.maxX - startX)
        let itemsPerRow = max(1, Int(floor((usableWidth + gap) / (width + gap))))
        let row = index / itemsPerRow
        let column = index % itemsPerRow
        let x = startX + CGFloat(column) * (width + gap)
        let y = topY - CGFloat(row) * (barHeight + rowGap)
        return clampedFrame(NSRect(x: x, y: y, width: width, height: barHeight), margin: 8)
    }

    func arrangeCurrentFocusShelf(excluding excludedIDs: Set<CGWindowID> = []) {
        guard let session = focusSession, session.stage == .arrangedAway else { return }
        let entries = session.entries.keys.compactMap { id -> (CGWindowID, ShadeState, NSWindow)? in
            guard !excludedIDs.contains(id),
                  let state = shaded[id],
                  state.appearanceMode == .proxyTitleBar,
                  let overlay = state.overlay else { return nil }
            return (id, state, overlay)
        }
        guard !entries.isEmpty else { return }
        arrangeShadedEntries(entries, reason: "focus")
    }

    @discardableResult
    func arrangeShadedEntries(_ entries: [(CGWindowID, ShadeState, NSWindow)],
                                      reason: String) -> Bool {
        guard !entries.isEmpty else {
            return false
        }

        let sorted = entries.sorted {
            let a = $0.2.frame
            let b = $1.2.frame
            if abs(a.maxY - b.maxY) > 1 { return a.maxY > b.maxY }
            if abs(a.minX - b.minX) > 1 { return a.minX < b.minX }
            return $0.0 < $1.0
        }

        var grouped: [NSScreen: [(CGWindowID, ShadeState, NSWindow)]] = [:]
        for entry in sorted {
            let screen = screenForCocoaFrame(entry.2.frame) ?? NSScreen.main ?? NSScreen.screens.first
            if let screen {
                grouped[screen, default: []].append(entry)
            }
        }

        for (screen, group) in grouped {
            let visible = screen.visibleFrame.insetBy(dx: 24, dy: 24)
            guard visible.width > 80, visible.height > 40 else { continue }
            let widgetFrames = desktopWidgetFrames(for: screen, visibleFrame: visible)

            let usesFocusColumnLayout = reason == "focus" && group.allSatisfy { $0.1.appearanceMode == .proxyTitleBar }
            let usesOriginalHousekeepingColumnLayout = reason == "housekeeping" &&
                group.allSatisfy { $0.1.appearanceMode != .proxyTitleBar }
            let verticalGap: CGFloat = 14
            let widestExisting = group.map {
                arrangedDisplayWidth(for: $0.1, overlay: $0.2, visibleFrame: visible)
            }.max() ?? visible.width
            let tallestBar = max(1, group.map { $0.2.frame.height }.max() ?? proxyTitleBarHeight)
            let stepY = tallestBar + verticalGap
            let startTop: CGFloat
            if usesOriginalHousekeepingColumnLayout {
                startTop = visible.maxY
            } else {
                startTop = desktopWidgetAvoidanceTop(for: screen, visibleFrame: visible,
                                                     widgetFrames: widgetFrames) ?? visible.maxY
            }
            let availableHeight = max(stepY, startTop - visible.minY)
            let maxRows = max(1, Int(floor(availableHeight / stepY)))
            let columnGap = min(28, max(14, visible.width * 0.012))
            let columnWidth: CGFloat
            let columnStep: CGFloat
            let columnStartX: CGFloat
            let stairStepX: CGFloat
            let widgetTopExclusion = usesFocusColumnLayout
                ? desktopWidgetTopExclusion(for: screen, visibleFrame: visible, widgetFrames: widgetFrames)
                : nil
            if usesFocusColumnLayout {
                columnWidth = arrangedColumnWidth(for: screen, visibleFrame: visible,
                                                  widgetFrames: widgetFrames)
                columnStep = min(columnWidth + columnGap, visible.width * 0.60)
                columnStartX = arrangedColumnStartX(for: screen, visibleFrame: visible,
                                                    widgetFrames: widgetFrames)
                stairStepX = 0
            } else if usesOriginalHousekeepingColumnLayout {
                columnWidth = widestExisting
                columnStep = min(max(widestExisting + columnGap, widestExisting * 1.04),
                                 visible.width * 0.52)
                columnStartX = arrangedHousekeepingStartX(for: screen, visibleFrame: visible)
                stairStepX = 0
            } else {
                let stairDepthCap = 4
                stairStepX = group.map {
                    arrangedStairStepWidth(for: $0.1, visibleFrame: visible)
                }.max() ?? max(10, ProxyTitleLayoutMetrics.trafficLightDiameter * 0.95)
                let maxStairOffset = CGFloat(stairDepthCap) * stairStepX
                columnWidth = widestExisting
                columnStep = min(max(widestExisting + maxStairOffset + columnGap,
                                     widestExisting * 1.08),
                                 visible.width * 0.52)
                columnStartX = visible.minX + min(18, max(8, visible.width * 0.006))
            }

            isProgrammaticOverlayArrangement = true
            defer { isProgrammaticOverlayArrangement = false }
            let animateFrames = reason != "focus"
            for (index, entry) in group.enumerated() {
                let id = entry.0
                let overlay = entry.2
                let row = index % maxRows
                let column = index / maxRows
                var frame = overlay.frame
                arrangedOverlayFrames[id] = arrangedOverlayFrames[id] ?? overlay.frame
                if usesFocusColumnLayout {
                    frame = focusShelfFrame(index: index, barHeight: frame.height,
                                            screen: screen, visibleFrame: visible,
                                            widgetTopExclusion: widgetTopExclusion)
                } else {
                    frame.size.width = arrangedDisplayWidth(for: entry.1, overlay: overlay, visibleFrame: visible)
                    let stackOffsetX = CGFloat(column) * columnStep
                    let x = columnStartX + stackOffsetX +
                        (usesOriginalHousekeepingColumnLayout ? 0 : CGFloat(row) * stairStepX)
                    let y = startTop - CGFloat(row) * stepY - frame.height
                    frame.origin = NSPoint(x: x, y: y)
                    frame = clampedFrame(frame, margin: 8)
                }
                if usesFocusColumnLayout {
                    focusSideStackFrames[id] = frame
                } else {
                    focusSideStackFrames.removeValue(forKey: id)
                }

                if let proxy = overlay as? NativeProxyOverlayWindow {
                    let oldResize = proxy.onResize
                    proxy.onResize = nil
                    if usesFocusColumnLayout {
                        proxy.allowsHorizontalResize = false
                        proxy.minSize = NSSize(width: frame.width, height: frame.height)
                        proxy.maxSize = NSSize(width: frame.width, height: frame.height)
                    }
                    if !framesAlmostEqual(proxy.frame, frame) {
                        proxy.setFrame(frame, display: true, animate: animateFrames)
                    }
                    proxy.onResize = oldResize
                } else {
                    if !framesAlmostEqual(overlay.frame, frame) {
                        overlay.setFrame(frame, display: true, animate: animateFrames)
                    }
                }
                applyOverlayPresentation(overlay, bringForward: true)
                wlog("arrange: side-stack reason=\(reason) id=\(id) row=\(row) column=\(column) frame=(\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height)))")
            }
        }

        if let active = activePreview, active.trigger == .titlebarPeek {
            updateHoverPreviewFrame(active.ownerID)
        }
        scheduleMenuRebuild()
        return true
    }

@objc func arrangeShadedWindows() {
        if restoreArrangedOverlayFrames() { return }

        let entries = shaded.compactMap { id, state -> (CGWindowID, ShadeState, NSWindow)? in
            guard let overlay = state.overlay else { return nil }
            return (id, state, overlay)
        }
        guard arrangeShadedEntries(entries, reason: "housekeeping") else {
            quietNotice("没有已折叠窗口", log: "arrange: no shaded overlays")
            return
        }
    }

    @objc func restoreAll() {
        guard !shaded.isEmpty else { return }
        let playSound = soundEnabled
        suppressUnshadeSounds = true
        withMenuRebuildSuppressed {
            for id in Array(shaded.keys) { unshade(id) }
        }
        suppressUnshadeSounds = false
        if playSound {
            playUnfoldSound()
        }
    }
}
