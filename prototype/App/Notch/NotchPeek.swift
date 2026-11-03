// // 在窗口原来的位置显示它收起时的画面：从刘海里看一眼，不拿出来。

import Cocoa
import ApplicationServices

/// 在窗口原来的位置显示它收起时的画面：从刘海里看一眼，不拿出来。右下角写明“收起时的画面”。
@MainActor
final class NotchPeek {
    private let panel: NSPanel

    init(image: CGImage, frame: NSRect) {
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resize
        let label = NSTextField(labelWithString: WSL10n.text("glance.stalePicture", zh: "收起时的画面"))
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        label.layer?.cornerRadius = 8
        let size = label.intrinsicContentSize
        label.frame = NSRect(x: frame.width - size.width - 22, y: 10, width: size.width + 12, height: size.height + 4)
        label.alignment = .center
        view.addSubview(label)
        panel.contentView = view
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.fadeDuration
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Motion.fadeDuration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            // 动画完成回调在主线程。
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}
