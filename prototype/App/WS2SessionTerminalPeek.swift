import AVFoundation
import Cocoa
import ScreenCaptureKit

/// A3「卡片上停一下：看一眼那扇终端」。悬停会话卡约半秒后，按会话目录找到那扇终端窗口，
/// 在会话页下方浮一块实时画面；指针移开或页面收起就停流收板。
/// 只在编程会话开着、屏幕录制已授权、普通窗口实时预览开着时才工作；
/// 找不到窗口就不出，不硬造截图。不点击、不切桌面、不激活那扇窗。
@MainActor final class WS2SessionTerminalPeekController {
    static let dwell: TimeInterval = 0.5
    static let maxWidth: CGFloat = 460
    static let maxHeight: CGFloat = 300

    private var panel: NSPanel?
    private var capture: WindowStreamCapture?
    private var lookupGeneration = 0
    private var frameSink: UInt64 = 0
    /// 探针用：最近一次解析到的窗口；浮层是否在屏上。
    var probeWindowID: UInt32?
    var probePanelVisible: Bool { panel?.isVisible == true }

    func begin(cwd: String, terminal: TerminalIdentity?, anchor: NSRect) {
        guard WindowBrowserSettings.livePreviewEnabled,
              hasScreenRecordingPermission(),
              !EffectSecurityBoundary.isLocked else { return }
        lookupGeneration += 1
        let mine = lookupGeneration
        WS2AgentSessionWindowFinder.lookupAsync(cwd: cwd, terminal: terminal) { [weak self] found in
            guard let self, self.lookupGeneration == mine, let found else { return }
            self.probeWindowID = found.windowID
            self.show(windowID: found.windowID, anchor: anchor)
        }
    }

    func end() {
        lookupGeneration += 1
        probeWindowID = nil
        if let capture {
            capture.videoLayer.removeFromSuperlayer()
            capture.stop()
            self.capture = nil
        }
        if let panel {
            panel.orderOut(nil)
            self.panel = nil
        }
    }

    private func show(windowID: UInt32, anchor: NSRect) {
        let capture = WindowStreamCapture(preview: true)
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        let host = NSView()
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.masksToBounds = true
        let layer = capture.videoLayer
        layer.videoGravity = .resizeAspect
        host.layer?.addSublayer(layer)
        let caption = NSTextField(labelWithString: WSL10n.text("agent.peek.caption", zh: "会话的终端 · 看一眼"))
        caption.font = .systemFont(ofSize: 11, weight: .medium)
        caption.textColor = .white
        caption.layer?.cornerRadius = 6
        caption.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        caption.alignment = .center
        host.addSubview(caption)
        panel.contentView = host
        let size = Self.maxSize(for: anchor)
        layer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        caption.frame = CGRect(x: 8, y: size.height - 24, width: size.width - 16, height: 16)
        panel.setContentSize(size)
        panel.setFrameOrigin(Self.origin(for: size, anchor: anchor))
        panel.orderFrontRegardless()
        self.panel = panel
        self.capture = capture
        frameSink &+= 1
        let sink = frameSink
        Task { [weak self] in
            do {
                let content = try await ShareableContentLoader.current()
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    throw PeekFailure.noWindow
                }
                let display = content.displays.max { lhs, rhs in
                    lhs.frame.intersection(window.frame).width * lhs.frame.intersection(window.frame).height
                        > rhs.frame.intersection(window.frame).width * rhs.frame.intersection(window.frame).height
                }
                try await capture.start(window: window, display: display)
                _ = sink
            } catch {
                guard let self else { return }
                wlog("agent peek: stream failed (\(String(describing: type(of: error))))")
                self.end()
            }
        }
    }

    private enum PeekFailure: Error { case noWindow }

    private static func maxSize(for anchor: NSRect) -> NSSize {
        NSSize(width: min(maxWidth, max(240, anchor.width)),
               height: maxHeight)
    }

    private static func origin(for size: NSSize, anchor: NSRect) -> NSPoint {
        let screen = NSScreen.screenContaining(anchor) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let x = max(visible.minX + 8, min(anchor.midX - size.width / 2, visible.maxX - size.width - 8))
        let below = anchor.minY - 10 - size.height
        return below >= visible.minY
            ? NSPoint(x: x, y: below)
            : NSPoint(x: x, y: min(anchor.maxY + 10, visible.maxY - size.height))
    }
}

extension NSScreen {
    /// 包住这块矩形（或与它交叠最多）的那块屏。
    static func screenContaining(_ rect: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }
    }
}

private extension NSRect {
    var area: CGFloat { width * height }
}
