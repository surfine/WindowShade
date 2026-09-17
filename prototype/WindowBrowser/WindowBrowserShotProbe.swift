// 隔离展示入口：用生产 AppKit 组件渲染真实截图，供视觉验收使用。
//
// 只用内置的确定性记录与本地生成的占位图像；不打开、不激活、不操作任何用户的
// 真实窗口，也不请求屏幕录制权限。探针会短暂显示它自己的临时面板窗口（约 1 秒），
// 面板是非激活的，不会抢走其他应用的键盘焦点。
//
// 用法：WindowShade.app/Contents/MacOS/WindowShade --window-browser-shots [输出目录]

import Cocoa
import ImageIO
import UniformTypeIdentifiers

final class WindowBrowserShotProbe {
    private struct Scenario {
        let name: String
        let mode: WindowBrowserPanelMode
        let style: WindowBrowserDisplayStyle
        let recordCount: Int
        let appearance: NSAppearance.Name?
        let appearanceStyle: WindowBrowserAppearanceStyle?
        let reduceTransparency: Bool
        let increaseContrast: Bool
        let screenRecordingAvailable: Bool
        let searchText: String
        let selectionIndex: Int
        let note: String
    }

    private let outputDirectory: URL
    private var panel: WindowBrowserPanel?

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func run() {
        try? FileManager.default.createDirectory(at: outputDirectory,
                                                withIntermediateDirectories: true)
        let scenarios: [Scenario] = [
            Scenario(name: "dock-single", mode: .dock, style: .grid, recordCount: 1,
                     appearance: nil, appearanceStyle: nil, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: true,
                     searchText: "", selectionIndex: 0,
                     note: "单窗口 Dock 面板：紧凑、标题优先、无大面积空白"),
            Scenario(name: "dock-three", mode: .dock, style: .grid, recordCount: 3,
                     appearance: nil, appearanceStyle: nil, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: true,
                     searchText: "", selectionIndex: 1,
                     note: "三个窗口：卡片一致，强调只落在当前项"),
            Scenario(name: "keyboard-list-eight", mode: .keyboard, style: .list, recordCount: 8,
                     appearance: nil, appearanceStyle: nil, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: true,
                     searchText: "", selectionIndex: 2,
                     note: "八窗口列表：行间距、长标题、选中详情与滚动"),
            Scenario(name: "keyboard-search", mode: .keyboard, style: .list, recordCount: 12,
                     appearance: nil, appearanceStyle: nil, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: true,
                     searchText: "Safari", selectionIndex: 0,
                     note: "键盘搜索：顶部搜索框、过滤结果与当前选择"),
            Scenario(name: "paper-light", mode: .keyboard, style: .grid, recordCount: 4,
                     appearance: .aqua, appearanceStyle: .paper, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: true,
                     searchText: "", selectionIndex: 0,
                     note: "纸面浅色：中性层次与细边线"),
            Scenario(name: "paper-dark", mode: .keyboard, style: .grid, recordCount: 4,
                     appearance: .darkAqua, appearanceStyle: .paper, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: true,
                     searchText: "", selectionIndex: 1,
                     note: "纸面深色：深色下的对比与选中指示"),
            Scenario(name: "system-glass-light", mode: .keyboard, style: .grid, recordCount: 4,
                     appearance: .aqua, appearanceStyle: .system, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: true,
                     searchText: "", selectionIndex: 0,
                     note: "系统玻璃浅色：控制层为真实 AppKit 玻璃"),
            Scenario(name: "system-glass-dark", mode: .keyboard, style: .grid, recordCount: 4,
                     appearance: .darkAqua, appearanceStyle: .system, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: true,
                     searchText: "", selectionIndex: 0,
                     note: "系统玻璃深色：控制层为真实 AppKit 玻璃"),
            Scenario(name: "reduce-transparency-contrast", mode: .keyboard, style: .grid,
                     recordCount: 4, appearance: .darkAqua, appearanceStyle: .paper,
                     reduceTransparency: true, increaseContrast: true,
                     screenRecordingAvailable: true, searchText: "", selectionIndex: 0,
                     note: "减少透明度 + 提高对比度：不透明回退，选择不只靠颜色"),
            Scenario(name: "states-without-image", mode: .keyboard, style: .grid, recordCount: 6,
                     appearance: nil, appearanceStyle: .paper, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: false,
                     searchText: "", selectionIndex: 0,
                     note: "无图像 / 缺权限 / 已折叠 / 最小化：信息明确"),
            Scenario(name: "dock-list-many", mode: .dock, style: .list, recordCount: 18,
                     appearance: nil, appearanceStyle: nil, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: true,
                     searchText: "", selectionIndex: 3,
                     note: "Dock 入口的紧凑列表：面板不占满屏幕宽度"),
        ]

        var manifest = """
        WindowShade 窗口浏览视觉验收截图（生产 AppKit 组件 + 确定性数据）
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        SDK: \(sdkVersion())
        scale: \(Int(NSScreen.main?.backingScaleFactor ?? 1))x
        数据来源：内置记录与本地生成的占位截图，未打开或操作任何真实窗口

        """
        if ProcessInfo.processInfo.environment["WINDOWSHADE_SHOTS_CLIP"] != nil {
            let clip = renderInteractionClip()
            manifest += "interaction-clip: \(clip?.lastPathComponent ?? "FAILED")"
                + " — 真实面板的状态变化序列（网格/列表切换、选择、搜索、失败状态）\n"
            print("window-browser-shots: interaction-clip -> "
                  + (clip?.path ?? "failed"))
        }
        for scenario in scenarios {
            let path = render(scenario: scenario)
            manifest += "\(scenario.name): \(path?.lastPathComponent ?? "FAILED")"
                + " — \(scenario.note)\n"
            print("window-browser-shots: \(scenario.name) -> "
                  + (path?.path ?? "failed"))
        }
        try? manifest.write(to: outputDirectory.appendingPathComponent("manifest.txt"),
                            atomically: true, encoding: .utf8)
        print("window-browser-shots: done output=\(outputDirectory.path)")
    }

    // MARK: 场景渲染

    private func render(scenario: Scenario) -> URL? {
        let records = Self.records(count: scenario.recordCount,
                                   includeImages: scenario.screenRecordingAvailable)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let size: CGSize
        if scenario.mode == .keyboard {
            size = CGSize(width: 800, height: 560)
        } else {
            let plan = WindowBrowserGeometry.layoutPlan(
                iconFrame: NSRect(x: 0, y: 0, width: 52, height: 52), edge: .bottom,
                screenFrame: screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: screen?.visibleFrame ?? NSRect(x: 0, y: 80, width: 1440, height: 820),
                desiredSize: WindowBrowserLayoutParams.standard.dockPanelSize,
                windowCount: records.count, style: scenario.style, isContentDriven: true)
            size = plan.panelFrame.size
        }
        let frame = NSRect(x: 80, y: 80, width: size.width, height: size.height)
        let panel = WindowBrowserPanel(mode: scenario.mode, frame: frame)
        panel.ignoresMouseEvents = true
        if let appearance = scenario.appearance {
            panel.appearance = NSAppearance(named: appearance)
        }
        let content = panel.browserContentView
        let wantsGlass = scenario.appearanceStyle != .paper
        let capabilities = WindowBrowserSystemCapabilities(
            supportsGlass: wantsGlass && WindowBrowserSystemCapabilities.runtimeSupportsGlass,
            reduceTransparency: scenario.reduceTransparency,
            increaseContrast: scenario.increaseContrast,
            reduceMotion: false)
        content.materialOverride = (scenario.appearanceStyle ?? .system, capabilities)

        let selection = records.indices.contains(scenario.selectionIndex)
            ? records[scenario.selectionIndex].key : records.first?.key
        content.update(mode: scenario.mode, records: records, selection: selection,
                       style: scenario.style, busyKeys: [],
                       screenRecordingAvailable: scenario.screenRecordingAvailable,
                       status: scenario.screenRecordingAvailable
                           ? "示例数据（fixture）" : "缺少屏幕录制权限：显示图标与文字")
        for record in records {
            if !scenario.screenRecordingAvailable {
                // 与控制器一致：缺少屏幕录制权限时仍然显示图标、标题与原因。
                content.applyThumbnail(nil, for: record.key,
                                       note: "缺少屏幕录制权限，显示应用图标与标题")
            } else if record.title.contains("图像失败") {
                content.applyThumbnail(nil, for: record.key, note: "截图不可用，显示应用图标与标题")
            } else {
                content.applyThumbnail(Self.placeholderImage(for: record),
                                       for: record.key, note: "示例窗口画面")
            }
        }
        if !scenario.searchText.isEmpty {
            content.setSearchTextForDiagnostics(scenario.searchText)
            // 与控制器一样，按查询过滤后再发布一份快照。
            let needle = WindowBrowserSearch.normalize(scenario.searchText)
            let filtered = records.filter {
                WindowBrowserSearch.matches(normalizedQuery: needle, record: $0)
            }
            content.update(mode: scenario.mode, records: filtered,
                           selection: filtered.first?.key, style: scenario.style,
                           busyKeys: [],
                           screenRecordingAvailable: scenario.screenRecordingAvailable,
                           status: "搜索：\(scenario.searchText)（\(filtered.count) 个结果）")
            for record in filtered where scenario.screenRecordingAvailable {
                content.applyThumbnail(Self.placeholderImage(for: record), for: record.key,
                                       note: "示例窗口画面")
            }
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        content.layoutSubtreeIfNeeded()
        // 让 AppKit 完成一次绘制与外观解析，再抓取内容视图。
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        content.layoutSubtreeIfNeeded()
        if ProcessInfo.processInfo.environment["WINDOWSHADE_SHOTS_DEBUG"] != nil,
           let card = content.debugFirstCardFrames() {
            print("shots-debug: cell=\(content.plan.cellSize) cardBounds=\(card.bounds) "
                  + "thumbnail=\(card.thumbnailHostFrame) title=\(card.titleFrame) "
                  + "action=\(card.actionFrame)")
        }
        let image = renderImage(of: content)
        panel.orderOut(nil)
        panel.close()
        guard let image else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let url = outputDirectory.appendingPathComponent("\(scenario.name).png")
        try? data.write(to: url)
        return url
    }

    private func renderImage(of view: NSView) -> CGImage? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    private func sdkVersion() -> String {
        // 运行时可读的 SDK 信息有限；这里记录构建时使用的 SDK 路径版本。
        #if WINDOWSHADE_SDK_HAS_GLASS
        return "macOS SDK 26.x（含公开 AppKit 玻璃 API）"
        #else
        return "macOS SDK 14–15（无公开 AppKit 玻璃 API，仅回退外观）"
        #endif
    }


    // MARK: 交互片段

    /// 真实面板的状态变化序列：只改面板自身状态（选择、搜索、样式、失败提示），
    /// 不悬停真实 Dock、不操作真实窗口。输出为循环 GIF。
    private func renderInteractionClip() -> URL? {
        let records = Self.records(count: 8, includeImages: true)
        let frame = NSRect(x: 80, y: 80, width: 800, height: 560)
        let panel = WindowBrowserPanel(mode: .keyboard, frame: frame)
        panel.ignoresMouseEvents = true
        let content = panel.browserContentView
        content.materialOverride = (.paper, WindowBrowserSystemCapabilities(
            supportsGlass: WindowBrowserSystemCapabilities.runtimeSupportsGlass,
            reduceTransparency: true, increaseContrast: false, reduceMotion: false))
        panel.orderFrontRegardless()

        var frames: [CGImage] = []
        func capture(selection: WindowKey?, style: WindowBrowserDisplayStyle,
                     search: String, status: String, records visible: [WindowRecord]) {
            content.update(mode: .keyboard, records: visible, selection: selection,
                           style: style, busyKeys: [], status: status)
            content.layoutSubtreeIfNeeded()
            for record in visible where !record.title.contains("图像失败") {
                content.applyThumbnail(Self.placeholderImage(for: record), for: record.key,
                                       note: "示例窗口画面")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            content.layoutSubtreeIfNeeded()
            if let image = renderImage(of: content) { frames.append(image) }
        }

        // 1) 首次出现（键盘入口，列表）。
        capture(selection: records[0].key, style: .list, search: "",
                status: "键盘入口：列表与选中项", records: records)
        for index in 1...3 {
            capture(selection: records[index].key, style: .list, search: "",
                    status: "方向键移动选中（第 \(index + 1) 项）", records: records)
        }
        // 2) 搜索过滤。
        for query in ["S", "Sa", "Saf"] {
            let needle = WindowBrowserSearch.normalize(query)
            let filtered = records.filter {
                WindowBrowserSearch.matches(normalizedQuery: needle, record: $0)
            }
            capture(selection: filtered.first?.key, style: .list, search: query,
                    status: "搜索：\(query)（\(filtered.count) 个结果）", records: filtered)
        }
        // 3) 切换到缩略图网格并移动选择。
        let safariOnly = records.filter { $0.appName == "Safari" }
        capture(selection: safariOnly.first?.key, style: .grid, search: "",
                status: "切换为缩略图网格（不重建流）", records: safariOnly)
        for index in safariOnly.indices {
            capture(selection: safariOnly[index].key, style: .grid, search: "",
                    status: "网格选择（第 \(index + 1) 项）", records: safariOnly)
        }
        // 4) 失败状态与回到快照，再切回列表释放。
        capture(selection: records[3].key, style: .grid, search: "",
                status: "实时预览不可用，已回到快照", records: records)
        capture(selection: records[3].key, style: .list, search: "",
                status: "回到列表：取消选择后释放资源", records: records)
        capture(selection: nil, style: .list, search: "", status: "", records: records)
        panel.orderOut(nil)
        panel.close()

        guard frames.count >= 2 else { return nil }
        let url = outputDirectory.appendingPathComponent("window-browser-interaction.gif")
        return Self.writeGIF(frames: frames.map { Self.downscaled($0, factor: 0.5) ?? $0 },
                             delay: 0.45, to: url) ? url : nil
    }

    /// GIF 只用于观察状态变化，按 0.5 缩放以控制体积。
    private static func downscaled(_ image: CGImage, factor: CGFloat) -> CGImage? {
        let width = max(1, Int(CGFloat(image.width) * factor))
        let height = max(1, Int(CGFloat(image.height) * factor))
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func writeGIF(frames: [CGImage], delay: Double, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
            return false
        }
        let loop: [CFString: Any] = [kCGImagePropertyGIFLoopCount: 0]
        CGImageDestinationSetProperties(
            destination, [kCGImagePropertyGIFDictionary: loop] as CFDictionary)
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDelayTime: delay,
            kCGImagePropertyGIFUnclampedDelayTime: delay
        ]
        for frame in frames {
            CGImageDestinationAddImage(destination, frame,
                                       frameProperties as CFDictionary)
        }
        return CGImageDestinationFinalize(destination)
    }

    // MARK: 数据

    private static func records(count: Int, includeImages: Bool) -> [WindowRecord] {
        let titles = ["Safari — OpenAI", "Safari — 文档草稿", "Finder — Downloads",
                      "预览 — 图像失败：受保护内容", "文本编辑 — 未命名",
                      "终端 — 恢复中", "备忘录 — 一个非常长的中英文混合窗口标题 Window Title",
                      "照片 — 置顶预览"]
        var records: [WindowRecord] = []
        for index in 0..<max(1, count) {
            let pid = pid_t(7300 + (index % 5))
            let appNames = ["Safari", "Finder", "预览", "文本编辑", "终端"]
            let instance = ApplicationInstanceKey(pid: pid, generation: 1)
            let key = WindowKey(application: instance,
                                originalWindowID: CGWindowID(800 + index),
                                windowGeneration: 1)
            var shade: WindowBrowserShadeState = .normal
            var pin: WindowBrowserPinState = .none
            var visibility: WindowBrowserSystemVisibility = .onScreen
            if index == 4 { shade = .folded; visibility = .offScreen }
            if index == 5 { shade = .restoring }
            if index == 6 { visibility = .minimized }
            if index == 7 { pin = .running }
            let record = WindowRecord(
                key: key,
                bundleIdentifier: "fixture.app.\(pid)",
                appName: appNames[index % appNames.count],
                title: titles[index % titles.count] + (index >= titles.count
                                                       ? " · \(index)" : ""),
                logicalFrame: CGRect(x: 120, y: 120, width: 980, height: 700),
                placementSource: index == 4 ? .managedFold : .liveDiscovery,
                systemVisibility: visibility,
                shadeState: shade,
                pinState: pin,
                capabilities: includeImages
                    ? [.activate, .fold, .unfold, .pinPreview, .unpinPreview, .close,
                       .minimize, .capture]
                    : [.activate, .fold, .close, .minimize],
                confidence: .confirmed,
                metadataRevision: UInt64(index + 1),
                isMinimized: visibility == .minimized,
                isOnScreen: visibility == .onScreen,
                isFoldedOffscreen: shade == .folded,
                isManaged: shade == .folded || pin == .running)
            records.append(record)
        }
        return records
    }

    /// 本地生成的占位窗口画面：代表一张复杂背景上的真实窗口截图，
    /// 不来自任何用户窗口，也不写入磁盘之外的位置。
    private static func placeholderImage(for record: WindowRecord) -> CGImage? {
        let width = 640
        let height = 400
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        rect.fill()
        // 简单的“内容”块：文字、行、色块，用来判断缩放与清晰度。
        let palette: [NSColor] = [.systemBlue, .systemTeal, .systemOrange,
                                  .systemPurple, .systemGreen]
        let accent = palette[abs(record.title.hashValue) % palette.count]
        accent.withAlphaComponent(0.9).setFill()
        NSRect(x: 24, y: 120, width: 260, height: 140).fill()
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        NSRect(x: 320, y: 210, width: 280, height: 16).fill()
        NSRect(x: 320, y: 176, width: 240, height: 16).fill()
        NSRect(x: 320, y: 142, width: 200, height: 16).fill()
        NSColor(calibratedWhite: 0.30, alpha: 1).setFill()
        NSRect(x: 0, y: height - 40, width: width, height: 40).fill()
        let text = record.displayTitle as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        text.draw(in: NSRect(x: 16, y: height - 32, width: width - 32, height: 26),
                  withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }
}
