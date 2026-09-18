import Cocoa
import AVFoundation

/// Offscreen AppKit component regression: no global event injection, capture,
/// permissions, or interaction with the user's windows.
@main
enum PaperSurfaceTests {
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 360),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 360))
        root.clipsToBounds = true
        window.contentView = root
        // 先把窗口真正上屏再断言 visibleRect：紧跟多个 GUI 进程之后，WindowServer
        // 尚未提交窗口时 visibleRect 可能仍是空的，会让本回归假失败。
        window.orderFrontRegardless()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let video = AVSampleBufferDisplayLayer()
        let preview = PinnedPreviewContentView(videoLayer: video, title: "Test preview")
        preview.frame = NSRect(x: 24, y: 24, width: 552, height: 220)
        root.addSubview(preview)
        root.layoutSubtreeIfNeeded()
        preview.updateTrackingAreas()

        precondition(preview.visibleRect == preview.bounds, "hover region escaped preview bounds")
        guard let tracking = preview.trackingAreas.first,
              let owner = tracking.owner as? PinnedPreviewContentView,
              let title = preview.subviews.first(where: { $0 is NSVisualEffectView })
                as? NSVisualEffectView else {
            fatalError("missing production tracking owner or title")
        }
        // 离屏回归里这个窗口不在合成器里（实测 occlusionState 不含 .visible），
        // 材质视图不会自己变成 layer-backed，而没有 layer 时第一次 alpha 动画
        // 会被丢掉：实测 alpha 一直停在 0。真实面板是合成出来的，材质显示时就
        // 有 layer。这里显式开启 layer，混合模式仍保留生产用的 behindWindow，
        // 覆盖的仍是 mouseEntered → setTitleVisible 这条真实代码路径。
        title.wantsLayer = true
        precondition(owner === preview && tracking.options.contains(.mouseEnteredAndExited))
        precondition(title.alphaValue == 0, "idle title obscures preview")

        var entered = 0
        var exited = 0
        var clicked = 0
        preview.onMouseEntered = { entered += 1 }
        preview.onMouseExited = { exited += 1 }
        preview.onMouseDown = { _ in clicked += 1 }
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.enterExitEvent(with: type, location: NSPoint(x: 80, y: 230),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        }
        func finishTransition() {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        }

        // Deliver the same tracking-owner callbacks AppKit dispatches, without
        // posting an event to the system or synthesizing a physical pointer.
        owner.mouseEntered(with: event(.mouseEntered))
        finishTransition()
        precondition(entered == 1 && title.alphaValue > 0.99, "enter did not reveal title")

        let point = NSPoint(x: preview.frame.midX, y: preview.frame.maxY - 12)
        guard let hit = root.hitTest(point) else { fatalError("missing title-area hit target") }
        precondition(hit === preview, "title material intercepted preview click")
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        hit.mouseDown(with: click)
        precondition(clicked == 1, "preview click callback was lost")

        owner.mouseExited(with: event(.mouseExited))
        finishTransition()
        precondition(exited == 1 && title.alphaValue < 0.01, "exit left title visible")
        preview.frame.size = NSSize(width: 300, height: 160)
        root.layoutSubtreeIfNeeded()
        preview.updateTrackingAreas()
        precondition(preview.visibleRect == preview.bounds, "resize expanded hover region")
        precondition(video.frame == preview.bounds, "video did not follow preview resize")
        window.close()
        print("PASS: bounded hover region, idle title hidden, enter/reveal, title click passthrough, exit/hide, resize")

        // MARK: 系统外观策略（减少透明度 / 提高对比度 / 减少动态效果）

        let opaque = SystemAppearanceCapabilities(reduceTransparency: true,
                                                  increaseContrast: false,
                                                  reduceMotion: false,
                                                  supportsGlass: true)
        let contrast = SystemAppearanceCapabilities(reduceTransparency: false,
                                                    increaseContrast: true,
                                                    reduceMotion: false,
                                                    supportsGlass: true)
        let calm = SystemAppearanceCapabilities(reduceTransparency: false,
                                                increaseContrast: false,
                                                reduceMotion: false,
                                                supportsGlass: true)
        let reducedMotion = SystemAppearanceCapabilities(reduceTransparency: false,
                                                         increaseContrast: false,
                                                         reduceMotion: true,
                                                         supportsGlass: true)

        precondition(SystemAppearancePolicy.usesOpaqueFallback(opaque),
                     "reduce transparency must request the opaque fallback")
        precondition(SystemAppearancePolicy.material(.transientPeek, opaque) == .contentBackground,
                     "reduce transparency must not keep translucent vibrancy")
        precondition(SystemAppearancePolicy.blendingMode(opaque) == .withinWindow,
                     "the opaque fallback must blend within the window")
        precondition(SystemAppearancePolicy.material(.transientPeek, calm) == .popover,
                     "normal appearance keeps the popover material")
        precondition(SystemAppearancePolicy.material(.floatingChrome, calm) == .hudWindow,
                     "floating chrome keeps the HUD material")
        let opaqueVeil = SystemAppearancePolicy.contentVeilColor(.transientPeek, opaque)
        precondition(opaqueVeil.alphaComponent > 0.99,
                     "the opaque fallback must not dilute its background with a veil")
        let normalVeil = SystemAppearancePolicy.contentVeilColor(.transientPeek, calm)
        precondition(normalVeil.alphaComponent > 0.1 && normalVeil.alphaComponent < 0.9,
                     "the normal appearance keeps the light content veil")
        precondition(SystemAppearancePolicy.edgeWidth(contrast)
                        > SystemAppearancePolicy.edgeWidth(calm),
                     "increase contrast must thicken hairlines")
        precondition(SystemAppearancePolicy.highlightAlpha(contrast) == 0,
                     "increase contrast must drop the decorative top highlight")
        precondition(SystemAppearancePolicy.shadowColor(contrast).alphaComponent
                        > SystemAppearancePolicy.shadowColor(calm).alphaComponent,
                     "increase contrast must deepen the paper shadow")
        precondition(SystemAppearancePolicy.animationDuration(0.15, reducedMotion) == 0,
                     "reduce motion must zero the new transitions")
        precondition(SystemAppearancePolicy.animationDuration(0.15, calm) == 0.15,
                     "normal appearance keeps the tuned duration")

        // MARK: 视图接线：材质、薄纱与边线跟随同一份策略

        let sampleImage = NSImage(size: NSSize(width: 40, height: 24))
        let peek = SafariStylePreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 200),
                                          image: sampleImage)
        peek.applySystemAppearance(capabilities: opaque)
        precondition(peek.appliedCapabilitiesForDiagnostics == opaque,
                     "the peek preview records the applied appearance")
        precondition(peek.appliedMaterialForDiagnostics == NSVisualEffectView.Material.contentBackground,
                     "the peek preview switches to the opaque fallback")
        peek.applySystemAppearance(capabilities: calm)
        precondition(peek.appliedMaterialForDiagnostics == NSVisualEffectView.Material.popover,
                     "the peek preview returns to the popover material")

        let live = PinnedLivePreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 200),
                                         videoLayer: AVSampleBufferDisplayLayer())
        live.applySystemAppearance(capabilities: opaque)
        precondition(live.appliedMaterialForDiagnostics == NSVisualEffectView.Material.contentBackground,
                     "the live thumbnail follows the same material policy")

        let pinnedContent = PinnedPreviewContentView(videoLayer: AVSampleBufferDisplayLayer(),
                                                     title: "WindowShade — 置顶预览")
        pinnedContent.applySystemAppearance(capabilities: opaque)
        precondition(pinnedContent.titleMaterialForDiagnostics.material == NSVisualEffectView.Material.contentBackground,
                     "the pinned preview title bar follows the same material policy")
        precondition(pinnedContent.accessibilityRole() == .group,
                     "the pinned preview is one accessible group")
        precondition((pinnedContent.accessibilityLabel() ?? "").contains("置顶预览"),
                     "the pinned preview announces its window title")

        // MARK: 动态分组盒填充：浅深色在绘制时各自解析
        let fill = SystemAppearancePolicy.groupBoxFill()
        let lightFill = SystemAppearancePolicy.resolvedColor(
            fill, appearance: NSAppearance(named: .aqua)!)
        let darkFill = SystemAppearancePolicy.resolvedColor(
            fill, appearance: NSAppearance(named: .darkAqua)!)
        precondition(lightFill.brightnessComponent > darkFill.brightnessComponent + 0.3,
                     "the group box fill follows the appearance instead of freezing one value "
                     + "(light=\(lightFill.brightnessComponent) dark=\(darkFill.brightnessComponent))")
        precondition(SystemAppearancePolicy.resolvedColor(
            SystemAppearancePolicy.groupBoxFill(),
            appearance: NSAppearance(named: .darkAqua)!).brightnessComponent < 0.5,
                     "the dark group box stays dark")

        // MARK: 设置页字号：默认外观与原来的固定字号一致，同时跟随系统文字大小
        let sharedBody = SystemAppearancePolicy.bodyFontSize
        precondition(abs(sharedBody - NSFont.preferredFont(forTextStyle: .body).pointSize) < 0.01,
                     "the shared body size follows the system text-size preference")
        precondition(SystemAppearancePolicy.fontSize(relativeToBody: 0) == sharedBody,
                     "delta 0 is the body size")
        precondition(SystemAppearancePolicy.fontSize(relativeToBody: -1) == max(9, sharedBody - 1)
                        && SystemAppearancePolicy.fontSize(relativeToBody: -2) == max(9, sharedBody - 2),
                     "detail sizes stay relative to the body size")
        if abs(sharedBody - 13) < 0.01 {
            precondition(SystemAppearancePolicy.font(relativeToBody: 0).pointSize == 13
                            && SystemAppearancePolicy.font(relativeToBody: -1).pointSize == 12
                            && SystemAppearancePolicy.font(relativeToBody: -2).pointSize == 11
                            && SystemAppearancePolicy.font(relativeToBody: 7).pointSize == 20,
                         "at the default text size the settings fonts keep their original sizes")
        }
        print("settings-fonts: body=\(sharedBody) "
              + "sizes=\(SystemAppearancePolicy.fontSize(relativeToBody: 0))/"
              + "\(SystemAppearancePolicy.fontSize(relativeToBody: -1))/"
              + "\(SystemAppearancePolicy.fontSize(relativeToBody: -2))")

        // MARK: 悬停缩略图说明自己是哪个窗口（tooltip + VoiceOver）
        let titledPeek = SafariStylePreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 200),
                                                image: sampleImage,
                                                windowTitle: "Safari — OpenAI")
        precondition((titledPeek.accessibilityLabel() ?? "").contains("Safari — OpenAI"),
                     "the peek preview announces the window it shows")
        precondition(titledPeek.toolTip == "Safari — OpenAI",
                     "the peek preview offers the window name as a tooltip")
        titledPeek.configureWindowTitle("   ")
        precondition((titledPeek.accessibilityLabel() ?? "") == "窗口预览"
                        && titledPeek.toolTip == "窗口预览",
                     "an untitled preview falls back to a generic name")
        let titledLive = PinnedLivePreviewView(frame: NSRect(x: 0, y: 0, width: 320, height: 200),
                                               videoLayer: AVSampleBufferDisplayLayer(),
                                               windowTitle: "WindowShade — 置顶预览")
        precondition((titledLive.accessibilityLabel() ?? "").contains("置顶预览"),
                     "the menu thumbnail announces its window too")

        // MARK: 系统设置深链：按本机是否装了新隐私面板决定顺序
        let modernFirst = SystemSettingsLinks.privacyPaneCandidates(
            pane: "Privacy_Accessibility", hasModernPane: true)
        precondition(modernFirst.count == 2
                        && modernFirst[0].contains(SystemSettingsLinks.modernSecurityPane)
                        && modernFirst[1].contains(SystemSettingsLinks.legacySecurityPane)
                        && modernFirst.allSatisfy { $0.hasSuffix("Privacy_Accessibility") },
                     "a modern system tries the ExtensionKit pane first and keeps the legacy fallback")
        let legacyFirst = SystemSettingsLinks.privacyPaneCandidates(
            pane: "Privacy_ScreenCapture", hasModernPane: false)
        precondition(legacyFirst[0].contains(SystemSettingsLinks.legacySecurityPane),
                     "an older system tries the legacy pane first")
        precondition(SystemSettingsLinks.privacyPaneCandidates(
            pane: "Privacy_ScreenCapture", hasModernPane: true)[0].hasSuffix("Privacy_ScreenCapture"),
                     "the requested privacy pane is preserved in the URL")
        let accessibilityModern = SystemSettingsLinks.accessibilityDisplayCandidates(
            hasModernPane: true)
        precondition(accessibilityModern.count == 3
                        && accessibilityModern[0].contains(SystemSettingsLinks.modernAccessibilityPane)
                        && accessibilityModern[0].hasSuffix("Seeing_Display")
                        && accessibilityModern[1].hasSuffix("Seeing_Display"),
                     "a modern system opens the accessibility display section directly")
        let accessibilityLegacy = SystemSettingsLinks.accessibilityDisplayCandidates(
            hasModernPane: false)
        precondition(accessibilityLegacy[0].contains(SystemSettingsLinks.legacyAccessibilityPane)
                        && accessibilityLegacy[0].hasSuffix("Seeing_Display")
                        && accessibilityLegacy.last?.contains(
                            SystemSettingsLinks.modernAccessibilityPane) == true,
                     "an older system falls back to the legacy pane but keeps the modern URL last")
        print("system-settings-links: hasModernPane=\(SystemSettingsLinks.hasModernPrivacyPane()) "
              + "hasModernAccessibilityPane=\(SystemSettingsLinks.hasModernAccessibilityPane())")

        // MARK: 卷帘条可访问性文案

        precondition(PaperSurfaceAccessibility.stripLabel(appName: "Safari", windowTitle: "OpenAI")
                        == "WindowShade 卷帘：Safari — OpenAI",
                     "the strip announces app and window title")
        precondition(PaperSurfaceAccessibility.stripLabel(appName: "", windowTitle: "  ")
                        == "WindowShade 卷帘：窗口",
                     "an untitled window still has a readable strip label")
        precondition(PaperSurfaceAccessibility.stripHelp().contains("双击展开"),
                     "the strip help explains how to unfold")
        precondition(PaperSurfaceAccessibility.previewLabel(windowTitle: "")
                        == "窗口预览",
                     "an untitled preview falls back to a generic label")
        precondition(PaperSurfaceAccessibility.statusItemValue(foldedCount: 0)
                        == "没有折叠的窗口",
                     "the status item announces an empty state instead of a bare zero")
        precondition(PaperSurfaceAccessibility.statusItemValue(foldedCount: 3)
                        == "3 个折叠窗口",
                     "the status item announces the folded window count")
        precondition(PaperSurfaceAccessibility.statusItemLabel == "WindowShade",
                     "the status item keeps a stable accessible name")
        // 临时提示必须短：否则一句提示会把菜单栏条挤宽。
        let longNotice = "窗口浏览：把鼠标停在 Dock 图标上查看该应用的窗口，或用菜单里的“选择窗口…”打开窗口选择面板。"
        let shortTitle = PaperSurfaceAccessibility.statusItemNoticeTitle(longNotice)
        precondition(shortTitle.count <= 15, "a long notice is truncated for the menu bar")
        precondition(shortTitle.hasSuffix("…"), "a truncated notice ends with an ellipsis")
        precondition(!longNotice.hasPrefix(shortTitle.replacingOccurrences(of: "…", with: "")) == false,
                     "the truncated title still starts with the beginning of the message")
        precondition(PaperSurfaceAccessibility.statusItemNoticeTitle("需要辅助功能权限")
                        == "需要辅助功能权限",
                     "a short notice is shown unchanged")

        print("PASS: system appearance policy, material wiring, paper accessibility")
    }
}
