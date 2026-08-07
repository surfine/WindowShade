// 悬停预览：标题栏单击 peek 与菜单悬停预览的统一展示/隐藏机制，
// 懒截图请求与预览定位。作为 AppDelegate 扩展实现。

import Cocoa

extension AppDelegate {
    func fullSizeTitlebarPreviewFrame(overlayFrame: NSRect, imageSize: NSSize) -> NSRect {
        let rawVisible = visibleFrame(for: overlayFrame)
        var visible = rawVisible.insetBy(dx: 8, dy: 8)
        if visible.width <= 80 || visible.height <= 60 {
            visible = rawVisible
        }

        let scale = min(visible.width / max(1, imageSize.width),
                        visible.height / max(1, imageSize.height),
                        1)
        let size = NSSize(width: max(1, floor(imageSize.width * scale)),
                          height: max(1, floor(imageSize.height * scale)))
        let gap: CGFloat = 8
        let spaceBelow = overlayFrame.minY - visible.minY - gap
        let spaceAbove = visible.maxY - overlayFrame.maxY - gap

        var origin = NSPoint(x: overlayFrame.midX - size.width / 2,
                             y: overlayFrame.minY - size.height - gap)
        if spaceBelow < size.height && spaceAbove > spaceBelow {
            origin.y = overlayFrame.maxY + gap
        }
        if spaceBelow < size.height && spaceAbove < size.height {
            origin.y = visible.midY - size.height / 2
        }

        return clampedFrame(NSRect(origin: origin, size: size), margin: 8)
    }

    func hoverPreviewFrame(id: CGWindowID, overlayFrame: NSRect, imageSize: NSSize,
                                   fullSizeForOriginalStrip: Bool = false) -> NSRect {
        if fullSizeForOriginalStrip,
           shaded[id]?.appearanceMode == .nativeScreenshot {
            return fullSizeTitlebarPreviewFrame(overlayFrame: overlayFrame, imageSize: imageSize)
        }

        let rawVisible = visibleFrame(for: overlayFrame)
        var visible = rawVisible.insetBy(dx: 8, dy: 8)
        if visible.width <= 80 || visible.height <= 60 {
            visible = rawVisible
        }

        let isShelfStrip = isFocusShelfMember(id: id) && !focusPulledOutOverlayIDs.contains(id)
        let size: NSSize
        if isShelfStrip {
            let width = min(max(1, overlayFrame.width), max(1, visible.width))
            let naturalHeight = width * max(1, imageSize.height) / max(1, imageSize.width)
            let maxHeight = min(260, max(80, visible.height * 0.45))
            size = NSSize(width: floor(width),
                          height: floor(min(max(naturalHeight, 96), maxHeight)))
        } else {
            let maxSize = NSSize(width: min(360, max(1, visible.width)),
                                 height: min(240, max(1, visible.height)))
            let scale = min(maxSize.width / max(1, imageSize.width),
                            maxSize.height / max(1, imageSize.height),
                            1)
            size = NSSize(width: max(1, floor(imageSize.width * scale)),
                          height: max(1, floor(imageSize.height * scale)))
        }
        let gap: CGFloat = 8
        let spaceBelow = overlayFrame.minY - visible.minY - gap
        let spaceAbove = visible.maxY - overlayFrame.maxY - gap
        var origin = NSPoint(x: overlayFrame.midX - size.width / 2,
                             y: overlayFrame.minY - size.height - gap)
        if spaceBelow < size.height && spaceAbove > spaceBelow {
            origin.y = overlayFrame.maxY + gap
        }

        let unclamped = NSRect(origin: origin, size: size)
        return clampedFrame(unclamped, margin: 8)
    }

    func safariStylePreviewFrame(id: CGWindowID, overlayFrame: NSRect, imageSize: NSSize) -> NSRect {
        let rawVisible = visibleFrame(for: overlayFrame)
        var visible = rawVisible.insetBy(dx: 8, dy: 8)
        if visible.width <= 80 || visible.height <= 60 {
            visible = rawVisible
        }

        let size = safariStylePreviewSize(anchorWidth: overlayFrame.width,
                                          imageSize: imageSize,
                                          visibleWidth: visible.width)
        let gap: CGFloat = 8
        let spaceBelow = overlayFrame.minY - visible.minY - gap
        let spaceAbove = visible.maxY - overlayFrame.maxY - gap

        var origin = NSPoint(x: overlayFrame.midX - size.width / 2,
                             y: overlayFrame.minY - size.height - gap)
        if spaceBelow < size.height && spaceAbove > spaceBelow {
            origin.y = overlayFrame.maxY + gap
        }
        return clampedFrame(NSRect(origin: origin, size: size), margin: 8)
    }

    func safariStylePreviewSize(anchorWidth: CGFloat, imageSize: NSSize,
                                        visibleWidth: CGFloat) -> NSSize {
        let targetWidth = min(max(280, min(anchorWidth, 340)), max(1, visibleWidth))
        let thumbnailWidth = max(1, targetWidth - 20)
        let thumbnailHeight = min(176, max(92, floor(thumbnailWidth * imageSize.height / max(1, imageSize.width))))
        return NSSize(width: targetWidth, height: thumbnailHeight + 20)
    }

    func statusMenuWindowFrame(near mouse: NSPoint) -> NSRect? {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let candidates = windows.compactMap { info -> NSRect? in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == selfPID,
                  let bounds = cgWindowBounds(info) else { return nil }
            let frame = cocoaFrame(fromWindowServerBounds: bounds)
            guard frame.width >= 180,
                  frame.height >= 80,
                  frame.insetBy(dx: -8, dy: -8).contains(mouse) else { return nil }
            return frame
        }
        return candidates.min { ($0.width * $0.height) < ($1.width * $1.height) }
    }

    func estimatedStatusMenuItemAnchor(near mouse: NSPoint) -> NSRect {
        let rawVisible = visibleFrame(for: NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1))
        let visible = rawVisible.insetBy(dx: 8, dy: 8)
        if let menuFrame = statusMenuWindowFrame(near: mouse) {
            return NSRect(x: menuFrame.minX,
                          y: mouse.y - 1,
                          width: menuFrame.width,
                          height: 2)
        }

        let measuredWidth = ceil(statusMenu.size.width)
        let menuWidth = min(max(280, measuredWidth), min(640, visible.width))
        let cursorOffsetFromMenuLeft = min(max(menuWidth * 0.28, 96), menuWidth - 80)
        let x = min(max(mouse.x - cursorOffsetFromMenuLeft, visible.minX), visible.maxX - menuWidth)
        return NSRect(x: x, y: mouse.y - 1, width: menuWidth, height: 2)
    }

    func menuHoverPreviewFrame(anchor: NSRect, imageSize: NSSize) -> NSRect {
        let rawVisible = visibleFrame(for: anchor)
        let visible = rawVisible.insetBy(dx: 8, dy: 8)
        let size = safariStylePreviewSize(anchorWidth: max(anchor.width, menuHoverPreviewMaxSize.width),
                                          imageSize: imageSize,
                                          visibleWidth: visible.width)
        let gap: CGFloat = 10
        var origin = NSPoint(x: anchor.minX - size.width - gap,
                             y: anchor.midY - size.height / 2)
        if origin.x < visible.minX {
            origin.x = anchor.maxX + gap
        }
        if origin.x + size.width > visible.maxX {
            origin.x = min(max(anchor.midX - size.width / 2, visible.minX), visible.maxX - size.width)
            origin.y = anchor.minY - size.height - gap
        }
        let frame = NSRect(origin: origin, size: size)
        return clampedFrame(frame, margin: 8)
    }

    func showMenuHoverPreview(_ id: CGWindowID, anchor: NSRect?) {
        guard let anchor else { return }
        if shaded[id] != nil {
            showShadedMenuHoverPreview(id, anchor: anchor)
        } else if pinnedPreviewController.isPreviewing(id: id) {
            showPinnedMenuHoverPreview(id, anchor: anchor)
        }
    }

    func showShadedMenuHoverPreview(_ id: CGWindowID, anchor: NSRect) {
        guard let state = shaded[id] else { return }
        guard let image = state.previewImage,
              image.size.width > 1,
              image.size.height > 1 else {
            requestCachedPreview(id, reason: "menu") { [weak self] in
                guard let self,
                      self.menuPreviewHoverID == id else { return }
                self.showMenuHoverPreview(id, anchor: self.menuPreviewAnchor ?? anchor)
            }
            return
        }

        let frame = menuHoverPreviewFrame(anchor: anchor, imageSize: image.size)
        let previewView = SafariStylePreviewView(frame: NSRect(origin: .zero, size: frame.size),
                                                 image: image)
        presentPreview(ownerID: id, frame: frame, contentView: previewView,
                       trigger: .menuHover, isPinnedLive: false)
    }

    // 已置顶窗口的实时缩略图：镜像该会话仍在运行的 ScreenCaptureKit 流，无需静态截图。
    // 老板键挂起中的 session 没有 capture 在跑，视同「没有预览」，不接一个收不到
    // 采样帧的 mirror layer 出来（否则弹出一个永远空白的预览面板）。
    func showPinnedMenuHoverPreview(_ id: CGWindowID, anchor: NSRect) {
        guard !pinnedPreviewController.isSuspended(id: id),
              let sourceSize = pinnedPreviewController.thumbnailSourceSize(id: id),
              sourceSize.width > 1, sourceSize.height > 1 else { return }
        let frame = menuHoverPreviewFrame(anchor: anchor, imageSize: sourceSize)
        guard let previewView = pinnedPreviewController.makeThumbnailPreviewView(
            frame: NSRect(origin: .zero, size: frame.size), id: id) else { return }
        presentPreview(ownerID: id, frame: frame, contentView: previewView,
                       trigger: .menuHover, isPinnedLive: true)
    }

    // 唯一的预览显示入口：菜单悬停和标题栏 peek 都经过这里建窗/挂载内容，同时保证
    // 系统中只有一个预览视窗存在——显示新的一定先关掉旧的（无论是哪种触发路径
    // 留下的），不需要每个调用端各自记得「要不要顺手关掉另一边」。
    func presentPreview(ownerID: CGWindowID, frame: NSRect, contentView: NSView,
                                trigger: PreviewTrigger, isPinnedLive: Bool, alpha: CGFloat = 1) {
        hidePreview(reason: "replaced")
        let window = PreviewWindow(contentRect: frame, styleMask: .borderless,
                                   backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.transient, .ignoresCycle]
        window.hasShadow = true
        window.contentView = contentView
        window.alphaValue = alpha
        activePreview = ActivePreview(ownerID: ownerID, window: window, trigger: trigger, isPinnedLive: isPinnedLive)
        window.orderFrontRegardless()
    }

    // 隐藏当前活跃预览。ownerID/trigger 给定时先核对，只清掉匹配的那一个——不匹配
    // 就是另一条触发路径正显示着别的窗口，什么都不做。
    func hidePreview(ownerID: CGWindowID? = nil, trigger: PreviewTrigger? = nil, reason: String) {
        guard let active = activePreview else { return }
        if let ownerID, active.ownerID != ownerID { return }
        if let trigger, active.trigger != trigger { return }
        // 若当前预览是已置顶窗口的实时镜像，断开镜像层，停止向其投喂采样帧。
        // 对静态图预览是安全的空操作。
        if active.isPinnedLive {
            pinnedPreviewController.detachThumbnail(id: active.ownerID)
        }
        active.window.orderOut(nil)
        activePreview = nil
    }

    func requestCachedPreview(_ id: CGWindowID, reason: String,
                                      completion: @escaping () -> Void) {
        guard #available(macOS 14.0, *) else { return }
        guard !previewCapturePendingIDs.contains(id),
              let state = shaded[id] else { return }
        previewCapturePendingIDs.insert(id)
        wlog("preview-cache: capture request id=\(id) app=\(state.appName) reason=\(reason)")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let currentPos = axPosition(state.element) ?? state.originalPosition
            let capturePos = windowIsVisible(pos: currentPos, size: state.originalSize)
                ? currentPos
                : state.originalPosition
            let image = await self.captureWindow(id: id,
                                                 axPos: capturePos,
                                                 size: state.originalSize,
                                                 maxPixelSize: hoverPreviewMaxPixelSize)
            self.previewCapturePendingIDs.remove(id)
            guard let image,
                  var latest = self.shaded[id] else {
                wlog("preview-cache: capture unavailable id=\(id) reason=\(reason)")
                return
            }
            latest.previewImage = NSImage(cgImage: image, size: latest.originalSize)
            self.shaded[id] = latest
            completion()
        }
    }

    func hideMenuHoverPreview(id: CGWindowID? = nil) {
        hidePreview(ownerID: id, trigger: .menuHover, reason: "menu-hide")
    }

    func updateHoverPreviewFrame(_ id: CGWindowID) {
        guard let active = activePreview, active.trigger == .titlebarPeek, active.ownerID == id,
              let state = shaded[id],
              let overlay = state.overlay else { return }
        let imageSize = (active.window.contentView as? SafariStylePreviewView)?.imageView.image?.size
            ?? state.previewImage?.size ?? active.window.frame.size
        let frame = safariStylePreviewFrame(id: id, overlayFrame: overlay.frame, imageSize: imageSize)
        if abs(active.window.frame.minX - frame.minX) > 0.5 ||
           abs(active.window.frame.minY - frame.minY) > 0.5 ||
           abs(active.window.frame.width - frame.width) > 0.5 ||
           abs(active.window.frame.height - frame.height) > 0.5 {
            active.window.setFrame(frame, display: true)
        }
    }

    func mouseIsInsideOverlay(_ id: CGWindowID, padding: CGFloat = 2) -> Bool {
        guard let overlay = shaded[id]?.overlay else { return false }
        return overlay.frame.insetBy(dx: -padding, dy: -padding).contains(NSEvent.mouseLocation)
    }

    func hoverPreviewIsSuppressed(_ id: CGWindowID) -> Bool {
        guard let until = hoverPreviewSuppressedUntil[id] else { return false }
        if until > Date() { return true }
        hoverPreviewSuppressedUntil.removeValue(forKey: id)
        return false
    }

    func peekHoverPreview(_ id: CGWindowID) {
        guard !hoverPreviewIsSuppressed(id) else { return }
        if let state = shaded[id],
           cleanupProxyIfSourceWindowVisible(id: id, state: state, reason: "peek-preview") {
            return
        }
        if let active = activePreview, active.trigger == .titlebarPeek, active.ownerID == id,
           active.window.isVisible {
            hideHoverPreview(id: id)
            return
        }
        peekHoverID = id
        if let active = activePreview, active.trigger == .titlebarPeek, active.ownerID != id {
            hideHoverPreview(preserveHover: true)
        }
        if shaded[id]?.previewImage != nil {
            showHoverPreview(id, requireMouseInside: false)
            return
        }
        // 专注 shelf 成员折叠当下不截图（保持批量折叠/reflow 快），但这里是用户
        // 主动点击、不在热路径上：懒截图一次，与菜单悬停本来就允许的行为对齐。
        requestCachedPreview(id, reason: "click") { [weak self] in
            guard let self,
                  self.peekHoverID == id else { return }
            self.showHoverPreview(id, requireMouseInside: false)
        }
    }

    func hideHoverPreview(id: CGWindowID? = nil, preserveHover: Bool = false) {
        if let id {
            if !preserveHover, peekHoverID == id {
                peekHoverID = nil
            }
            guard activePreview?.trigger == .titlebarPeek, activePreview?.ownerID == id else { return }
        } else if !preserveHover {
            peekHoverID = nil
        }
        hidePreview(trigger: .titlebarPeek, reason: "peek-hide")
    }

    func clickPreviewImage(for state: ShadeState, overlay: NSWindow) -> NSImage? {
        guard let image = state.previewImage,
              image.size.width > 1,
              image.size.height > 1 else { return nil }
        let overlayFrame = overlay.frame
        guard state.appearanceMode == .nativeScreenshot,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              state.originalSize.width > 1,
              state.originalSize.height > overlayFrame.height + 1 else {
            return image
        }

        let scale = CGFloat(cg.width) / max(1, state.originalSize.width)
        let cropTop = min(cg.height - 1, max(1, Int(ceil(overlayFrame.height * scale))))
        let cropRect = CGRect(x: 0, y: cropTop,
                              width: cg.width,
                              height: max(1, cg.height - cropTop))
        guard let content = cg.cropping(to: cropRect) else { return image }
        let contentSize = NSSize(width: image.size.width,
                                 height: max(1, image.size.height - overlayFrame.height))
        let titlebarRadius = (overlay.contentView as? TitleStripView)?.image
            .flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
            .flatMap { estimatedCornerRadiusPixels(from: $0) }
        let fallbackRadius = max(10, min(32, overlayFrame.height * 0.48)) * scale
        let radius = titlebarRadius ?? fallbackRadius
        let rounded = roundedClippedImage(content, cornerRadius: radius,
                                          whitePreviewGradient: true) ?? content
        return NSImage(cgImage: rounded, size: contentSize)
    }

    func showHoverPreview(_ id: CGWindowID, requireMouseInside: Bool = true) {
        guard peekHoverID == id,
              !requireMouseInside || mouseIsInsideOverlay(id) else { return }
        guard let state = shaded[id],
              let overlay = state.overlay,
              let image = clickPreviewImage(for: state, overlay: overlay),
              image.size.width > 1,
              image.size.height > 1 else { return }
        if cleanupProxyIfSourceWindowVisible(id: id, state: state, reason: "show-preview") {
            return
        }

        let overlayFrame = overlay.frame
        let frame = safariStylePreviewFrame(id: id, overlayFrame: overlayFrame, imageSize: image.size)
        let previewView = SafariStylePreviewView(frame: NSRect(origin: .zero, size: frame.size),
                                                 image: image)
        // 不再跟随「半透明卷帘条」设置——peek 靠白纱+圆角本身就足够区分于真实窗口，
        // 不需要借用户的透明度偏好，也让它跟菜单悬停预览视觉上一致。
        presentPreview(ownerID: id, frame: frame, contentView: previewView,
                       trigger: .titlebarPeek, isPinnedLive: false)
        peekHoverID = id
        wlog("preview: show id=\(id) style=safari-card size=(\(Int(frame.width))x\(Int(frame.height)))")
    }
}
