// 设置窗口截图入口：用生产设置窗口渲染每一页，不需要屏幕录制权限。
//
// 与 `SettingsDesignPreview`（走 ScreenCaptureKit 的整窗截图）互补：这里用
// `CGWindowListCreateImage` 抓自己这扇窗（已合成系统侧栏材质），失败时退回
// `cacheDisplay`；后者拍的是主题框架，侧栏由系统材质绘制、离屏渲染会是透明区域，
// 因此只在整窗截图拿不到结果时使用。
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
        let shotSize = Self.requestedShotSize()
        let sidebarCheck = Self.requestedSidebarCheck()
        let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        var manifest = """
        设置窗口页面截图（生产设置窗口整窗截图，含系统侧栏材质；拿不到整窗结果时才退回
        cacheDisplay 离屏渲染，那种情况下侧栏区域是透明的）
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        scale: \(Int(NSScreen.main?.backingScaleFactor ?? 1))x
        截图尺寸: \(Int(shotSize.width))x\(Int(shotSize.height))

        """
        for (appearanceName, appearance) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            for section in WindowShadeSettingsSection.allCases {
                owner.showDuoSettings(section: section)
                RunLoop.current.run(until: Date().addingTimeInterval(0.45))
                guard let window = owner.duoController.settingsWindow?.window else { continue }
                window.setContentSize(shotSize)
                window.setFrameOrigin(NSPoint(x: window.frame.origin.x,
                                              y: window.frame.origin.y))
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                if appearanceName == "light", let offset = owner.duoController.settingsWindow?
                    .contentColumnOffsetForDiagnostics {
                    let verdict = abs(offset) < 0.5 ? "PASS" : "FAIL"
                    print("settings-shots: 内容列居中偏移 \(String(format: "%.1f", offset))pt \(verdict)")
                }
                if let sidebarCheck, section == .shade,
                   let settings = owner.duoController.settingsWindow {
                    // 切换侧栏只应重新分配窗口内部的宽度，窗口本身不能变大变小。
                    let before = window.frame.width
                    settings.sidebarCollapsedForDiagnostics = sidebarCheck
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                    let after = window.frame.width
                    let verdict = abs(after - before) < 0.5 ? "PASS" : "FAIL"
                    print("settings-shots: 侧栏\(sidebarCheck ? "收起" : "展开")时窗口宽 "
                          + "\(String(format: "%.0f", after))pt（切换前 \(String(format: "%.0f", before))pt）\(verdict)")
                    settings.sidebarCollapsedForDiagnostics = false
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                }
                let theme = window.contentView?.superview ?? window.contentView
                guard let theme,
                      let image = capture(window: window) ?? render(view: theme) else { continue }
                let bitmap = NSBitmapImageRep(cgImage: image)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { continue }
                let name = "settings-\(appearanceName)-\(section.title).png"
                try? data.write(to: outputDirectory.appendingPathComponent(name))
                manifest += "\(name): \(Int(window.frame.width))x\(Int(window.frame.height)) "
                    + "section=\(section.title)\n"
                print("settings-shots: \(name)")
            }
        }
        // 引导窗口（“使用说明…”）：新用户第一眼看到的就是它，浅深色各拍一张。
        for (appearanceName, appearance) in appearances {
            NSApp.appearance = NSAppearance(named: appearance)
            owner.showPermissionOnboarding()
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            guard let window = owner.onboardingWindow,
                  let image = capture(window: window)
                    ?? window.contentView.flatMap({ render(view: $0) }) else { continue }
            let name = "onboarding-\(appearanceName).png"
            if let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: outputDirectory.appendingPathComponent(name))
                manifest += "\(name): \(Int(window.frame.width))x\(Int(window.frame.height))\n"
                print("settings-shots: \(name)")
            }
            // orderOut 而不是 close：关闭会把“看过引导”写进偏好，探针不写用户偏好。
            window.orderOut(nil)
        }
        try? manifest.write(to: outputDirectory.appendingPathComponent("manifest.txt"),
                            atomically: true, encoding: .utf8)
        owner.duoController.settingsWindow?.close()
        completion()
    }

    /// 截图尺寸默认 900 × 680（窗口默认尺寸）。设置 `WINDOWSHADE_SETTINGS_SHOTS_SIZE=1115x680`
    /// 可以把同一批页面渲染成别的窗口尺寸——窗口可自由缩放，内容列的左右留白是否对称、
    /// 收起侧栏后的宽详情区是否还留大片空白，都要在非默认宽度上看过才算数。
    private static func requestedShotSize() -> NSSize {
        let fallback = NSSize(width: 900, height: 680)
        guard let raw = ProcessInfo.processInfo.environment["WINDOWSHADE_SETTINGS_SHOTS_SIZE"] else {
            return fallback
        }
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]),
              width >= 640, height >= 400 else { return fallback }
        return NSSize(width: width, height: height)
    }

    /// `WINDOWSHADE_SETTINGS_SHOTS_SIDEBAR=collapsed|expanded` 时，在拍卷帘页之前先把侧栏切到该状态，
    /// 并核对窗口宽度没有跟着变——"展开/收起侧栏把窗口撑大"就是这条自检要挡住的回归。
    private static func requestedSidebarCheck() -> Bool? {
        switch ProcessInfo.processInfo.environment["WINDOWSHADE_SETTINGS_SHOTS_SIDEBAR"]?.lowercased() {
        case "collapsed": return true
        case "expanded": return false
        default: return nil
        }
    }

    private func render(view: NSView) -> CGImage? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    /// 整窗截图：这是唯一能把系统侧栏材质一起拍下来的路径（`cacheDisplay` 在侧栏
    /// 区域会留透明）。CGWindowListCreateImage 已被 Apple 标为废弃但仍可用，所以
    /// 走 dlsym 拿符号，拿不到就退回离屏渲染，不写死对已废弃 API 的依赖。
    private func capture(window: NSWindow) -> CGImage? {
        let number = window.windowNumber
        guard number > 0 else { return nil }
        typealias CreateImage = @convention(c) (CGRect, CGWindowListOption, CGWindowID,
                                                CGWindowImageOption) -> Unmanaged<CGImage>?
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                                  RTLD_LAZY),
              let symbol = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        guard let image = createImage(.null, .optionIncludingWindow, CGWindowID(number),
                                      [.boundsIgnoreFraming, .bestResolution])?
            .takeRetainedValue() else { return nil }
        return isBlank(image) ? nil : image
    }

    /// 窗口还没被合成时 CGWindowListCreateImage 会返回一张全透明图，这种结果要丢弃。
    private func isBlank(_ image: CGImage) -> Bool {
        let width = min(image.width, 32)
        let height = min(image.height, 32)
        guard width > 1, height > 1,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return true }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return true }
        for index in stride(from: 3, to: width * height * 4, by: 4) where data[index] > 0 {
            return false
        }
        return true
    }
}
