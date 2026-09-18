// 设置窗口的离屏截图入口：用生产设置窗口渲染每一页，不需要屏幕录制权限。
//
// 与 `SettingsDesignPreview`（走 ScreenCaptureKit 的整窗截图）互补：这里用
// `cacheDisplay` 拍主题框架，因此包含工具栏与内容区；侧栏由系统材质绘制，离屏
// 渲染可能为空，需要侧栏时仍用设计预览入口。
//
// 用法：WindowShade.app/Contents/MacOS/WindowShade --settings-shots [输出目录]

import Cocoa

final class SettingsShotProbe {
    private let owner: AppDelegate
    private let outputDirectory: URL

    init(owner: AppDelegate, outputDirectory: URL) {
        self.owner = owner
        self.outputDirectory = outputDirectory
    }

    func run(completion: @escaping () -> Void) {
        try? FileManager.default.createDirectory(at: outputDirectory,
                                                withIntermediateDirectories: true)
        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        var manifest = """
        设置窗口页面截图（生产设置窗口，cacheDisplay 离屏渲染；侧栏由系统材质绘制，不在此图内）
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        scale: \(Int(NSScreen.main?.backingScaleFactor ?? 1))x

        """
        for (appearanceName, appearance) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            for section in WindowShadeSettingsSection.allCases {
                owner.showDuoSettings(section: section)
                RunLoop.current.run(until: Date().addingTimeInterval(0.45))
                guard let window = owner.duoController.settingsWindow?.window else { continue }
                window.setContentSize(NSSize(width: 900, height: 680))
                window.setFrameOrigin(NSPoint(x: window.frame.origin.x,
                                              y: window.frame.origin.y))
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                let theme = window.contentView?.superview ?? window.contentView
                guard let theme, let image = render(view: theme) else { continue }
                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
                let name = "settings-\(appearanceName)-\(section.title).png"
                try? data.write(to: outputDirectory.appendingPathComponent(name))
                manifest += "\(name): \(Int(window.frame.width))x\(Int(window.frame.height)) "
                    + "section=\(section.title)\n"
                print("settings-shots: \(name)")
            }
        }
        try? manifest.write(to: outputDirectory.appendingPathComponent("manifest.txt"),
                            atomically: true, encoding: .utf8)
        owner.duoController.settingsWindow?.close()
        completion()
    }

    private func render(view: NSView) -> CGImage? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }
}
