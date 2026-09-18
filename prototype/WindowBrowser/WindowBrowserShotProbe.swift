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
        /// 面板页脚文字。空字符串表示“没有状态文字”：这种情况下面板不预留页脚，
        /// 直接贴合内容（对应用户日常打开 Dock 面板时的样子）。
        var statusText: String = "示例数据（fixture）"
    }

    private let outputDirectory: URL
    private var panel: WindowBrowserPanel?
    private var glassRigWindow: NSWindow?

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func run() {
        try? FileManager.default.createDirectory(at: outputDirectory,
                                                withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["WINDOWSHADE_GLASS_RIG"] != nil {
            glassRigWindow = Self.makeGlassRigWindow()
        }
        let scenarios: [Scenario] = [
            Scenario(name: "dock-single", mode: .dock, style: .grid, recordCount: 1,
                     appearance: nil, appearanceStyle: nil, reduceTransparency: false,
                     increaseContrast: false, screenRecordingAvailable: true,
                     searchText: "", selectionIndex: 0,
                     note: "单窗口 Dock 面板：没有状态文字时页脚不占位，卡片下方不再留空档",
                     statusText: ""),
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
        // 经典卷帘条的配色刷新：在浅色下创建 → 切到深色后 refreshPalette()，
        // 必须与“直接在深色下创建”得到同一份配色。
        let previousAppearance = NSApp.appearance
        NSApp.appearance = NSAppearance(named: .aqua)
        let lightCreated = ClassicTitleStripView(frame: NSRect(x: 0, y: 0, width: 480, height: 34),
                                                 appName: "Safari", windowTitle: "OpenAI",
                                                 pid: 99_999)
        let refreshed = ClassicTitleStripView(frame: NSRect(x: 0, y: 0, width: 480, height: 34),
                                              appName: "Safari", windowTitle: "OpenAI",
                                              pid: 99_999)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        refreshed.refreshPalette()
        let freshDark = ClassicTitleStripView(frame: NSRect(x: 0, y: 0, width: 480, height: 34),
                                              appName: "Safari", windowTitle: "OpenAI",
                                              pid: 99_999)
        func paletteMatches(_ a: ClassicPalette, _ b: ClassicPalette,
                            appearance: NSAppearance) -> Bool {
            let keys: [(NSColor, NSColor)] = [(a.paper, b.paper), (a.edge, b.edge),
                                              (a.text, b.text), (a.control, b.control)]
            return keys.allSatisfy { pair in
                let left = SystemAppearancePolicy.resolvedColor(pair.0, appearance: appearance)
                let right = SystemAppearancePolicy.resolvedColor(pair.1, appearance: appearance)
                return abs(left.brightnessComponent - right.brightnessComponent) < 0.02
            }
        }
        let darkAppearance = NSAppearance(named: .darkAqua)!
        let refreshMatchesFresh = paletteMatches(refreshed.paletteForDiagnostics,
                                                 freshDark.paletteForDiagnostics,
                                                 appearance: darkAppearance)
        let lightDiffersFromDark = !paletteMatches(lightCreated.paletteForDiagnostics,
                                                   freshDark.paletteForDiagnostics,
                                                   appearance: darkAppearance)
        print("window-browser-shots: classic-strip-palette "
              + "\((refreshMatchesFresh && lightDiffersFromDark) ? "PASS" : "FAIL") "
              + "(refresh-matches-fresh=\(refreshMatchesFresh) "
              + "light-differs-from-dark=\(lightDiffersFromDark))")
        NSApp.appearance = previousAppearance

        // 系统外观对照：同一卷帘条在普通与“提高对比度”下的真实像素。
        let appearanceBeforeSamples = NSApp.appearance
        for (name, capabilities, note) in [
            ("classic-strip-dark",
             SystemAppearanceCapabilities(reduceTransparency: false, increaseContrast: false,
                                          reduceMotion: false,
                                          supportsGlass: SystemAppearanceCapabilities.runtimeSupportsGlass),
             "经典卷帘条：深色外观（配色随外观重算）"),
            ("classic-strip-normal",
             SystemAppearanceCapabilities(reduceTransparency: false, increaseContrast: false,
                                          reduceMotion: false,
                                          supportsGlass: SystemAppearanceCapabilities.runtimeSupportsGlass),
             "经典卷帘条：普通对比度（0.5pt 细线 + 顶边高光）"),
            ("classic-strip-contrast",
             SystemAppearanceCapabilities(reduceTransparency: false, increaseContrast: true,
                                          reduceMotion: false,
                                          supportsGlass: SystemAppearanceCapabilities.runtimeSupportsGlass),
             "经典卷帘条：提高对比度（1pt 边线、无高光）"),
            ("peek-preview",
             SystemAppearanceCapabilities(reduceTransparency: true, increaseContrast: false,
                                          reduceMotion: false, supportsGlass: false),
             "悬停缩略图：减少透明度回退（不透明底 + withinWindow 混合）"),
        ] {
            if let path = renderSurfaceSample(name: name, capabilities: capabilities, note: note) {
                manifest += "\(name): \(path.lastPathComponent) — \(note)\n"
                print("window-browser-shots: \(name) -> \(path.path)")
            }
        }

        NSApp.appearance = appearanceBeforeSamples

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
        // 与控制器同一条派生规则：标题真的换行才占两行，没有状态文字时页脚不占位。
        let statusText = scenario.screenRecordingAvailable
            ? scenario.statusText : "缺少屏幕录制权限：显示图标与文字"
        let shotParams = WindowBrowserGeometry.derivedParams(
            base: .standard, titles: records.map(\.displayTitle),
            hasStatus: !statusText.isEmpty)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let size: CGSize
        if scenario.mode == .keyboard {
            size = CGSize(width: 800, height: 560)
        } else {
            let plan = WindowBrowserGeometry.layoutPlan(
                iconFrame: NSRect(x: 0, y: 0, width: 52, height: 52), edge: .bottom,
                screenFrame: screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: screen?.visibleFrame ?? NSRect(x: 0, y: 80, width: 1440, height: 820),
                desiredSize: shotParams.dockPanelSize,
                windowCount: records.count, style: scenario.style, isContentDriven: true,
                params: shotParams)
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
        content.params = shotParams
        content.update(mode: scenario.mode, records: records, selection: selection,
                       style: scenario.style, busyKeys: [],
                       screenRecordingAvailable: scenario.screenRecordingAvailable,
                       status: statusText)
        // 诊断对照：强制卡片用实色，用来验证内容层材质到底改变了什么。
        if ProcessInfo.processInfo.environment["WINDOWSHADE_CARD_SURFACE"] == "solid" {
            content.setCardSurfaceForDiagnostics(.solid)
        }
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
            let searchStatus = "搜索：\(scenario.searchText)（\(filtered.count) 个结果）"
            content.params = WindowBrowserGeometry.derivedParams(
                base: .standard, titles: filtered.map(\.displayTitle),
                hasStatus: !searchStatus.isEmpty)
            content.update(mode: scenario.mode, records: filtered,
                           selection: filtered.first?.key, style: scenario.style,
                           busyKeys: [],
                           screenRecordingAvailable: scenario.screenRecordingAvailable,
                           status: searchStatus)
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
                  + "action=\(card.actionFrame) "
                  + "panelRadius=\(content.panelCornerRadiusForDiagnostics)")
        }
        // 默认抓内容视图（离屏 `cacheDisplay`，不需要屏幕录制权限）；设
        // `WINDOWSHADE_SHOTS_REAL=1` 时改抓真实窗口，只有它能看到
        // NSGlassEffectView 由合成器渲染出来的液态玻璃（离屏渲染里玻璃是不可见的）。
        let wantsRealWindow = ProcessInfo.processInfo.environment["WINDOWSHADE_SHOTS_REAL"] != nil
        let image = (wantsRealWindow ? capture(window: panel) : nil) ?? renderImage(of: content)
        // 玻璃的折射只有屏幕截图能看到（单窗口截图拿到的只是窗口自己的表面），
        // 因此留一个“把面板停在屏幕上”的钩子，便于用 screencapture 抓真实观感。
        let holdName = ProcessInfo.processInfo.environment["WINDOWSHADE_SHOTS_HOLD_NAME"]
        if let hold = ProcessInfo.processInfo.environment["WINDOWSHADE_SHOTS_HOLD"]
            .flatMap(Double.init), hold > 0,
           holdName == nil || holdName == scenario.name {
            let screen = NSScreen.main?.frame.height ?? 0
            let frame = panel.frame
            let topLeftY = screen - frame.maxY
            print("window-browser-shots: holding \(scenario.name) for \(hold)s "
                  + "at screen-rect \(Int(frame.minX)),\(Int(topLeftY)) "
                  + "\(Int(frame.width))x\(Int(frame.height)) "
                  + "kind=\(content.materialHostForDiagnostics.kind.rawValue)")
            RunLoop.current.run(until: Date().addingTimeInterval(hold))
        }
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

    /// 玻璃对照背景：确定性图案（高饱和渐变 + 细字 + 明暗分区）放在面板正后方，
    /// 让 regular / clear、不同变暗强度可以在同一背景上直接比较。
    private static func makeGlassRigWindow() -> NSWindow {
        let frame = NSRect(x: 30, y: 30, width: 440, height: 380)
        let window = NSWindow(contentRect: frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isOpaque = true
        window.hasShadow = false
        // 高于普通窗口，低于面板（面板是 .floating），保证对照背景始终在面板正后方。
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        window.isReleasedWhenClosed = false
        window.contentView = GlassRigBackgroundView(frame: NSRect(origin: .zero, size: frame.size))
        window.orderFrontRegardless()
        return window
    }

    /// 真实窗口截图：走合成器，因此包含 NSGlassEffectView 的液态玻璃、材质与阴影轮廓。
    /// 窗口还没被合成时 CGWindowListCreateImage 会返回全透明图，这种结果要丢弃。
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
        return Self.isBlank(image) ? nil : image
    }

    private static func isBlank(_ image: CGImage) -> Bool {
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

    private func sdkVersion() -> String {
        // 运行时可读的 SDK 信息有限；这里记录构建时使用的 SDK 路径版本。
        #if WINDOWSHADE_SDK_HAS_GLASS
        return "macOS SDK 26.x（含公开 AppKit 玻璃 API）"
        #else
        return "macOS SDK 14–15（无公开 AppKit 玻璃 API，仅回退外观）"
        #endif
    }



    // MARK: 表面样例（卷帘条 / 悬停缩略图）

    /// 渲染一张自定义表面的真实像素，用于检查系统外观开关下的表现。
    private func renderSurfaceSample(name: String,
                                     capabilities: SystemAppearanceCapabilities,
                                     note: String) -> URL? {
        let previousAppearance = NSApp.appearance
        if name.hasSuffix("-dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        defer { NSApp.appearance = previousAppearance }
        let size = CGSize(width: 520, height: 120)
        let frame = NSRect(origin: .zero, size: size)
        let host = NSView(frame: frame)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let sample: NSView
        if name.hasPrefix("classic-strip") {
            let strip = ClassicTitleStripView(frame: NSRect(x: 12, y: 34, width: 496, height: 34),
                                              appName: "Safari", windowTitle: "OpenAI · 参考资料",
                                              pid: 99_999)
            strip.refreshPalette()
            strip.appearanceCapabilities = capabilities
            sample = strip
        } else {
            let preview = SafariStylePreviewView(
                frame: NSRect(x: 12, y: 8, width: 320, height: 104),
                image: Self.placeholderImage(named: "peek", size: NSSize(width: 640, height: 400)))
            preview.applySystemAppearance(capabilities: capabilities)
            sample = preview
        }
        host.addSubview(sample)
        let window = NSWindow(contentRect: frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        let image = renderImage(of: host)
        window.orderOut(nil)
        window.close()
        guard let image else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        return url
    }

    /// 与窗口画面同一套绘制方式的合成图，用作缩略图样例内容。
    private static func placeholderImage(named name: String, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        // 与卡片里的占位画面同一规则：真实窗口截图自带窗口圆角，占位画面也要有，
        // 否则缩略图会在圆角容器里露出一块直角。
        SystemCornerPath.path(in: NSRect(origin: .zero, size: size),
                              radius: max(4, SystemCornerRadius.window * 0.6)).addClip()
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.systemTeal.withAlphaComponent(0.85).setFill()
        NSRect(x: 24, y: 120, width: 200, height: 120).fill()
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        NSRect(x: 260, y: 200, width: 340, height: 16).fill()
        NSRect(x: 260, y: 168, width: 280, height: 16).fill()
        (name as NSString).draw(at: NSPoint(x: 24, y: size.height - 44),
                                withAttributes: [.font: NSFont.systemFont(ofSize: 20,
                                                                            weight: .semibold),
                                                 .foregroundColor: NSColor.white])
        image.unlockFocus()
        return image
    }

    // MARK: 主菜单 / 文本编辑快捷键端到端探针

    /// 用真实键盘面板验证“代理应用也需要主菜单”：聚焦搜索框后发送 ⌘V，
    /// 打印面板是否成为 key window 以及搜索框内容。
    func runStandardMenuProbe() {
        // --without-menu 用于对照：证明没有主菜单时同一条快捷键不会粘贴。
        let installsMenu = !CommandLine.arguments.contains("--without-menu")
        if installsMenu {
            NSApp.mainMenu = StandardMenu.make(appName: "WindowShade",
                                               settingsTarget: nil, settingsAction: nil)
        }
        // 只有当前台应用才能拥有 key window；探针临时用 regular 策略取得前台。
        NSApp.setActivationPolicy(.regular)
        // WINDOWSHADE_PROBE_COOPERATIVE_ACTIVATION=1 时改用 macOS 14 起的协作式
        // activate()，用于对比两种激活方式在这个（最少用户手势的）场景下是否都能生效。
        if ProcessInfo.processInfo.environment["WINDOWSHADE_PROBE_COOPERATIVE_ACTIVATION"] != nil {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let frame = NSRect(x: 120, y: 120, width: 640, height: 420)
        let panel = WindowBrowserPanel(mode: .keyboard, frame: frame)
        let records = Self.records(count: 4, includeImages: true)
        let content = panel.browserContentView
        content.update(mode: .keyboard, records: records, selection: records.first?.key,
                       style: .list, busyKeys: [], status: "主菜单探针")
        // 走生产入口（含协作式激活、makeKey、聚焦搜索框与延迟重试）。
        panel.presentKeyboardPanel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("粘贴内容", forType: .string)
        var handled = false
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                        modifierFlags: .command, timestamp: 0,
                                        windowNumber: panel.windowNumber, context: nil,
                                        characters: "v", charactersIgnoringModifiers: "v",
                                        isARepeat: false, keyCode: 9) {
            handled = NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
            if !handled { NSApp.sendEvent(event) }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        print("standard-menu-probe: menu=\(installsMenu) active=\(NSApp.isActive) "
              + "key=\(panel.isKeyWindow) "
              + "panelKey=\(panel.canBecomeKey) handled=\(handled) "
              + "searchText=\"\(content.searchText)\" "
              + "a11y=\"\(content.searchFieldAccessibilityLabel ?? "-")\"")
        panel.orderOut(nil)
        panel.close()
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
    /// 稳定哈希：`String.hashValue` 每个进程都会重新播种，用它挑颜色会让同一份
    /// fixture 每次渲染出不同画面，归档图没法逐像素比较。这里用 FNV-1a 固定下来。
    private static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }

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
        // 真实截图是窗口画面：四角带系统窗口的圆角（按窗口宽度缩放到本图像素）。
        // 归档图里的占位画面必须长得像真截图，否则卡片里会出现一块直角画面。
        let windowWidth = max(1, record.logicalFrame?.width ?? 800)
        let cornerRadius = max(4, min(24, SystemCornerRadius.window * CGFloat(width) / windowWidth))
        SystemCornerPath.path(in: rect, radius: cornerRadius).addClip()
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        rect.fill()
        // 简单的“内容”块：文字、行、色块，用来判断缩放与清晰度。
        let palette: [NSColor] = [.systemBlue, .systemTeal, .systemOrange,
                                  .systemPurple, .systemGreen]
        let accent = palette[Int(stableHash(record.title) % UInt64(palette.count))]
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

/// 玻璃对照背景（只在 `--window-browser-shots` 的诊断入口使用）。
private final class GlassRigBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(colors: [NSColor.systemPink, NSColor.systemTeal,
                                           NSColor.systemYellow, NSColor.systemIndigo])!
        gradient.draw(in: bounds, angle: -35)
        // 明暗分区：玻璃的变暗层与自适应色调在这里最容易看出来。
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height / 3).fill()
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height / 3).fill()
        // 细字：看模糊与可读性。
        let text = "WindowShade glass rig — 液态玻璃对照 0123456789"
        for row in 0..<8 {
            (text as NSString).draw(
                at: NSPoint(x: 12, y: bounds.height - 26 - CGFloat(row) * 18),
                withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: row % 2 == 0 ? .regular : .semibold),
                                 .foregroundColor: NSColor.labelColor])
        }
        // 高频细节：看清晰度与折射。
        for column in 0..<44 {
            NSColor(white: column % 2 == 0 ? 0 : 1, alpha: 0.85).setFill()
            NSRect(x: CGFloat(column) * 10, y: 0, width: 5, height: 14).fill()
        }
    }
}
