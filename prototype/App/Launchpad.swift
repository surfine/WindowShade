// 启动台：macOS 26 起系统的启动台换成了 Spotlight 里的“应用程序”，没有自己的排列、没有分页、没有文件夹。这里照 iPadOS 主屏幕
// （SpringBoard）的样子做一个，也当作 iPadOS 式多任务的入口。
//
// - 像回到主屏幕：清晰的壁纸铺满，挡住桌面上的窗口；图标一页一页排（7 列 × 5 行，窄屏 6 列），名字白字带一点投影。
//   程序坞留在上面照常能用。底下一颗玻璃小胶囊：平时写着“搜索”，翻页时变成页码点；直接打字就是搜索，中文名可以打拼音或首字母。
// - 文件夹照 iOS：毛玻璃底板上排着 3×3 的小图标；点开时底板长大成一块面板、后面的主屏幕模糊下去，小图标飞到各自的位置变成
//   原大；面板里 4×4 一页，可以翻页。第一次打开时照旧版启动台，把实用工具收进“其他”文件夹。编辑时把一个 App 拖到另一个上面
//   停一下就建文件夹（名字按它的类别），拖到文件夹上就放进去，从打开的文件夹里拖出面板就拿出来；编辑时点标题可以改名。
// - 最后一页是 App 资料库：按 App 自己写的类别分好组，每组一块毛玻璃，三个大图标点了直接开，第四格是一小撮，点开看这一组全部。
//   “建议”是最近用过的，“最近添加”是最近装的。顶上的搜索框列出全部 App（按拼音分字母）。编辑时点图标左上角的“−”，
//   App 只是不在主屏幕上了，资料库里还有。
// - 手感照 iPad：出现时图标从外面收拢、带一点弹性落到位；点开 App 时它的图标放大、整个主屏幕往里推进；指针停在图标上，
//   图标轻轻浮起来；按下时变暗一点。两指左右划翻页，一比一跟手，两头有阻尼，松手按惯性推算停在哪页（WWDC18）。
// - 按住图标不放进入编辑：图标抖起来，拖动重新排列，别的图标带弹性让位；拖到屏幕边停一会儿翻到那一页。排列记下来。
// - iPadOS 式多任务（照 iPadOS 26.2 从程序坞拖出 App）：按住图标直接拖出来，主屏幕让开、露出桌面；拖着的图标变成一块窗口的样子——
//   在中间是横的（照常打开），靠左靠右是竖的（半屏；靠上靠下是那一角；顶上正中铺满），靠到最边上出现侧拉的小箭头。松手，App 打开，
//   窗口一出来就放到那里。
// - 全画在 Core Animation 图层上（图标、名字都是预先画好的位图，毛玻璃是图层的背景滤镜），翻页、进出由渲染进程播，主线程忙也不掉帧。
// 打开“减少动态效果”时不缩放、不弹，只淡入淡出。
//
// 这个文件：找 App、画图、一格图标、毛玻璃、翻页。控制器在 LaunchpadController.swift，主屏幕在 LaunchpadView.swift，
// 文件夹在 LaunchpadFolders.swift，App 资料库在 LaunchpadLibrary.swift。

import Cocoa
import CoreServices
import ImageIO

// MARK: - 找 App、画图

enum AppCatalog {
    /// 经典启动台列的就是这几处（含一层子文件夹）。Safari 这些随系统更新的 App 装在 Cryptexes 里。
    static var roots: [String] {
        ["/Applications", "/System/Applications", "/System/Cryptexes/App/System/Applications", NSHomeDirectory() + "/Applications"]
    }

    /// 扫一遍（在后台调用）：同一个 App 装了两份只留先找到的那份（/Applications 优先），按名字排好（中文按拼音）。
    /// 顺带记下类别（App 资料库分组）、装进来的时间（最近添加）、上次打开的时间（建议）。
    static func scan() -> [LaunchpadApp] {
        let fm = FileManager.default
        var apps: [LaunchpadApp] = []
        var seen = Set<String>()
        func add(_ path: String) {
            guard let bundle = Bundle(path: path) else { return }
            let info = bundle.infoDictionary ?? [:]
            if (info["LSBackgroundOnly"] as? Bool) == true || (info["LSBackgroundOnly"] as? String) == "1" { return }
            if let id = bundle.bundleIdentifier, !seen.insert(id).inserted { return }
            var name = localizedName(bundle) ?? fm.displayName(atPath: path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
            let added = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.addedToDirectoryDateKey]))?.addedToDirectoryDate
            let used = MDItemCreate(kCFAllocatorDefault, path as CFString).flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
            apps.append(LaunchpadApp(path: path, name: name, bundleID: bundle.bundleIdentifier,
                                     category: info["LSApplicationCategoryType"] as? String, added: added, lastUsed: used))
        }
        func walk(_ dir: String, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for item in items where !item.hasPrefix(".") {
                let path = (dir as NSString).appendingPathComponent(item)
                if item.hasSuffix(".app") { add(path); continue }
                var isDir: ObjCBool = false
                if depth > 1, fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
                   !NSWorkspace.shared.isFilePackage(atPath: path) {
                    walk(path, depth: depth - 1)
                }
            }
        }
        for root in roots { walk(root, depth: 2) }
        return apps.sorted(by: LaunchpadSearch.ordered)
    }

    /// App 按这台 Mac 的语言显示的名字（和访达里一样）。FileManager.displayName 按 WindowShade 自己的语言来，
    /// 而 WindowShade 的进程语言是英文，所以直接读 App 的本地化信息：InfoPlist.strings，或者系统 App 用的 InfoPlist.loctable。
    static func localizedName(_ bundle: Bundle) -> String? {
        let pick = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: Locale.preferredLanguages).first
        func name(in table: [String: Any]?) -> String? {
            (table?["CFBundleDisplayName"] as? String) ?? (table?["CFBundleName"] as? String)
        }
        if let pick {
            if let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: pick),
               let found = name(in: NSDictionary(contentsOfFile: path) as? [String: Any]) {
                return found
            }
            if let path = bundle.path(forResource: "InfoPlist", ofType: "loctable"),
               let table = NSDictionary(contentsOfFile: path) as? [String: Any],
               let found = name(in: table[pick] as? [String: Any]) {
                return found
            }
        }
        return nil
    }

    /// 图标画成指定像素大小的位图（后台可用）。
    static func icon(for path: String, pixels: Int) -> CGImage? {
        let image = NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    /// 名字画成位图：白字、一行、放不下省略，带一点投影（在任何壁纸上都看得清）。画成位图，几百个名字叠在一起也不费劲。
    static func label(_ text: String, width: CGFloat, scale: CGFloat) -> CGImage? {
        let height: CGFloat = 20
        let pixelsW = Int(ceil(width * scale)), pixelsH = Int(ceil(height * scale))
        guard pixelsW > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelsW, height: pixelsH, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph, .shadow: shadow,
        ]
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: attributes)
            .draw(with: NSRect(x: 2, y: 3, width: width - 4, height: height - 3), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// 一行大字（文件夹标题）画成位图，返回位图和它的点大小。
    static func title(_ text: String, size: CGFloat, maxWidth: CGFloat, scale: CGFloat) -> (CGImage, CGSize)? {
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.white, .shadow: shadow, .paragraphStyle: paragraph,
        ])
        let line = ceil(font.ascender - font.descender + font.leading)
        let width = min(maxWidth, ceil(string.size().width) + 16), height = line + 12
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(ceil(width * scale)), height: Int(ceil(height * scale)), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        string.draw(with: NSRect(x: 8, y: 6 - font.descender, width: width - 16, height: line), options: [.truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage().map { ($0, CGSize(width: width, height: height)) }
    }

    /// 这块屏的桌面图片，在后台解码并模糊，主屏幕沿用 macOS 15 启动台的处理。
    /// 用户壁纸读不到时退到系统的 DefaultDesktop.heic（同一套缩略图选项），再模糊；两条都失败才返回 nil，不联网。
    static func wallpaper(url: URL, pixels: CGFloat) -> CGImage? {
        guard let image = thumbnail(url: url, pixels: pixels) else {
            let fallback = URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic")
            return thumbnail(url: fallback, pixels: pixels).flatMap { LaunchpadBackdrop.make($0, radius: radius(for: $0)) ?? $0 }
        }
        return LaunchpadBackdrop.make(image, radius: radius(for: image)) ?? image
    }

    /// 用同一套缩略图选项解码一张图；URL 打开失败或解码失败都返回 nil。
    static func thumbnail(url: URL, pixels: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(pixels),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func radius(for image: CGImage) -> CGFloat {
        CGFloat(max(image.width, image.height)) * 0.018
    }
}

// MARK: - 面板

@MainActor
final class LaunchpadPanel: NSPanel {
    let view: LaunchpadView

    init(screen: NSScreen) {
        view = LaunchpadView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // 在程序坞下面一层：程序坞照常能用（点它里面的 App，主屏幕就让开）。
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    func present() {
        makeKeyAndOrderFront(nil)
        view.focusSearch()
        view.animateIn()
    }

    /// launching：刚点开一个 App，主屏幕往里推进着消失；否则图标往外散开。
    func dismiss(launching: Bool) {
        let duration = view.animateOut(launching: launching)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in self?.orderOut(nil) }
    }
}

// MARK: - 毛玻璃

enum LaunchpadGlass {
    /// 毛玻璃：把后面的东西模糊、提一点饱和度，再蒙一层白（iOS 文件夹、App 资料库的底板）。图层的背景滤镜，渲染进程实时算。
    static func make(blur: CGFloat, tint: CGFloat) -> CALayer {
        let layer = LaunchpadFrostLayer()
        layer.blur = blur
        layer.tint = tint
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.refresh()
        return layer
    }

    /// 模糊（名字叫 blur，半径可以做动画：backgroundFilters.blur.inputRadius）和提饱和度。
    static func filters(blur: CGFloat, saturation: CGFloat = 1.5) -> [CIFilter] {
        var list: [CIFilter] = []
        if let filter = CIFilter(name: "CIGaussianBlur") {
            filter.name = "blur"
            filter.setValue(blur, forKey: kCIInputRadiusKey)
            list.append(filter)
        }
        if let filter = CIFilter(name: "CIColorControls") {
            filter.name = "color"
            filter.setValue(saturation, forKey: kCIInputSaturationKey)
            list.append(filter)
        }
        return list
    }
}

/// 文件夹/分类属于内容层的磨砂，不伪称 Liquid Glass。可访问性设置改变时原位更新。
final class LaunchpadFrostLayer: CALayer {
    var blur: CGFloat = 26
    var tint: CGFloat = 0.14
    override init() { super.init() }
    override init(layer: Any) {
        if let original = layer as? LaunchpadFrostLayer { blur = original.blur; tint = original.tint }
        super.init(layer: layer)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    func refresh(opaque: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                 contrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast) {
        backgroundFilters = opaque || contrast ? nil : LaunchpadGlass.filters(blur: blur)
        backgroundColor = opaque || contrast ? NSColor(white: 0.16, alpha: 1).cgColor
            : NSColor.white.withAlphaComponent(tint).cgColor
        borderColor = NSColor.white.withAlphaComponent(contrast ? 0.8 : 0.15).cgColor
        borderWidth = contrast ? 1.5 : 0.5
    }
}

// MARK: - 一格：App 或文件夹

@MainActor
final class LaunchpadCell {
    enum Kind: Equatable {
        case app(LaunchpadApp)
        case folder(LaunchpadFolder)
    }

    /// 整格。锚点在图标中心：位置就是图标中心，悬停放大、编辑时抖动都绕着图标转；名字挂在下面。
    let root = CALayer()
    /// App：图标位图；文件夹：里面是毛玻璃底板和 3×3 小图标。
    let icon = CALayer()
    let label = CALayer()
    /// 按下时盖在图标上的一层暗色（App 按图标的形状，文件夹按底板的圆角）。
    let shade = CALayer()
    private(set) var kind: Kind
    private(set) var side: CGFloat = 0
    private var glass: CALayer?
    private(set) var minis: [CALayer] = []
    private var badge: CALayer?
    /// 名字位图画的是哪几个字（文件夹改名后要重画）。
    var labelText = ""

    /// macOS 的图标四周留了一圈透明边：看得见的圆角方块只占 80.5%。
    static let squircle: CGFloat = 0.805

    init(_ kind: Kind) {
        self.kind = kind
        for layer in [root, icon, label, shade] { layer.actions = ["contents": NSNull()] }
        icon.contentsGravity = .resizeAspect
        icon.minificationFilter = .trilinear
        icon.shadowColor = NSColor.black.cgColor
        icon.shadowOpacity = 0
        icon.shadowRadius = 10
        icon.shadowOffset = CGSize(width: 0, height: 6)
        label.contentsGravity = .center
        shade.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        shade.opacity = 0
        if case .folder = kind {
            let glass = LaunchpadGlass.make(blur: 14, tint: 0.28)
            icon.addSublayer(glass)
            self.glass = glass
            shade.cornerCurve = .continuous
            minis = (0..<9).map { _ in
                let mini = CALayer()
                mini.contentsGravity = .resizeAspect
                mini.minificationFilter = .trilinear
                mini.actions = ["contents": NSNull()]
                glass.addSublayer(mini)
                return mini
            }
        } else {
            let mask = CALayer()
            mask.contentsGravity = .resizeAspect
            shade.mask = mask
        }
        icon.addSublayer(shade)
        root.addSublayer(icon)
        root.addSublayer(label)
    }

    static func key(_ kind: Kind) -> String {
        switch kind {
        case .app(let app): return app.path
        case .folder(let folder): return "folder:" + folder.id
        }
    }

    var key: String { Self.key(kind) }
    var app: LaunchpadApp? { if case .app(let app) = kind { return app }; return nil }
    var folder: LaunchpadFolder? { if case .folder(let folder) = kind { return folder }; return nil }

    /// 同一格换了内容（文件夹里多了少了、改了名；App 的信息更新了）。
    func update(_ kind: Kind) { self.kind = kind }

    /// 文件夹底板在图标方框里的位置：和 App 图标看得见的圆角方块一样大。
    static func plateRect(side: CGFloat) -> CGRect {
        let inset = side * (1 - squircle) / 2
        return CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    }

    /// 底板里 3×3 小图标看得见的方块（底板坐标）。
    static func miniRects(plate: CGFloat) -> [CGRect] {
        let mini = plate * 0.215, gap = plate * 0.06
        let pad = (plate - mini * 3 - gap * 2) / 2
        return (0..<9).map { i in
            CGRect(x: pad + CGFloat(i % 3) * (mini + gap), y: pad + CGFloat(i / 3) * (mini + gap), width: mini, height: mini)
        }
    }

    func layout(icon side: CGFloat, width: CGFloat) {
        guard side != self.side || root.bounds.width != width else { return }
        self.side = side
        let height = side + 30
        root.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        root.anchorPoint = CGPoint(x: 0.5, y: side / 2 / height)
        icon.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        icon.position = CGPoint(x: width / 2, y: side / 2)
        label.bounds = CGRect(x: 0, y: 0, width: width - 12, height: 20)
        label.position = CGPoint(x: width / 2, y: side + 14)
        let plate = Self.plateRect(side: side)
        let radius = plate.width * 0.225
        icon.shadowPath = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if let glass {
            glass.frame = plate
            glass.cornerRadius = radius
            shade.frame = plate
            shade.cornerRadius = radius
            for (mini, rect) in zip(minis, Self.miniRects(plate: plate.width)) {
                let grow = (rect.width / Self.squircle - rect.width) / 2
                mini.frame = rect.insetBy(dx: -grow, dy: -grow)
            }
        } else {
            shade.frame = icon.bounds
            shade.mask?.frame = icon.bounds
        }
        badge?.position = badgeCenter
    }

    func setArt(icon image: CGImage?, label text: CGImage?, scale: CGFloat) {
        if let image, glass == nil { icon.contents = image; shade.mask?.contents = image }
        if let text { label.contents = text; label.contentsScale = scale }
    }

    /// 文件夹的 3×3 小图标（缺的留空）。
    func setMinis(_ images: [CGImage?]) {
        for (i, mini) in minis.enumerated() { mini.contents = i < images.count ? images[i] : nil }
    }

    /// 小图标 i 看得见的方块，在这一格的图标坐标里（相对图标中心）。
    func miniOffset(_ i: Int) -> CGRect {
        let plate = Self.plateRect(side: side)
        let rect = Self.miniRects(plate: plate.width)[min(max(i, 0), 8)]
        return rect.offsetBy(dx: plate.minX - side / 2, dy: plate.minY - side / 2)
    }

    // MARK: 编辑时的“−”

    private var badgeCenter: CGPoint {
        let inset = side * (1 - Self.squircle) / 2
        return CGPoint(x: root.bounds.width / 2 - side / 2 + inset + 3, y: inset + 3)
    }

    /// “−”相对图标中心在哪（点它：从主屏幕移除）。
    var badgeOffset: CGPoint {
        CGPoint(x: badgeCenter.x - root.bounds.width / 2, y: badgeCenter.y - side / 2)
    }

    var hasBadge: Bool { badge != nil }

    func showBadge(_ on: Bool, animated: Bool) {
        if on, badge == nil {
            let circle = CALayer()
            circle.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
            circle.cornerRadius = 11
            circle.backgroundColor = NSColor(white: 0.9, alpha: 0.96).cgColor
            circle.shadowOpacity = 0.28
            circle.shadowRadius = 3
            circle.shadowOffset = CGSize(width: 0, height: 1)
            let bar = CALayer()
            bar.bounds = CGRect(x: 0, y: 0, width: 10, height: 2.2)
            bar.cornerRadius = 1.1
            bar.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
            bar.position = CGPoint(x: 11, y: 11)
            circle.addSublayer(bar)
            circle.position = badgeCenter
            root.addSublayer(circle)
            badge = circle
            if animated {
                let grow = Motion.spring(.pop, keyPath: "transform.scale")
                grow.keyPath = "transform.scale"
                grow.fromValue = 0.2
                grow.toValue = 1
                grow.duration = grow.settlingDuration
                circle.add(grow, forKey: "in")
            }
        } else if !on, let circle = badge {
            badge = nil
            guard animated else { circle.removeFromSuperlayer(); return }
            CATransaction.begin()
            CATransaction.setAnimationDuration(Motion.fadeDuration)
            CATransaction.setCompletionBlock { circle.removeFromSuperlayer() }
            circle.transform = CATransform3DMakeScale(0.2, 0.2, 1)
            circle.opacity = 0
            CATransaction.commit()
        }
    }

    // MARK: 拖着一个 App 停在上面：要建文件夹 / 放进这个文件夹

    private var target: CALayer?

    /// App：图标缩小一点、后面长出一块毛玻璃底板（松手就一起建文件夹）；文件夹：底板放大一点（松手就放进去）。
    func showTarget(_ on: Bool, reduced: Bool) {
        let plate = Self.plateRect(side: side)
        func pop(_ layer: CALayer, transform: CATransform3D? = nil, opacity: Float? = nil) {
            let bounce = reduced ? 0 : Motion.Spring.pop.bounce
            if let transform {
                if reduced {
                    layer.removeAnimation(forKey: "transform")
                    layer.transform = transform
                } else {
                    let animation = CASpringAnimation(perceptualDuration: Motion.Spring.pop.response, bounce: bounce)
                    animation.keyPath = "transform"
                    animation.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
                    animation.toValue = NSValue(caTransform3D: transform)
                    animation.duration = animation.settlingDuration
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layer.add(animation, forKey: "transform")
                    layer.transform = transform
                    CATransaction.commit()
                }
            }
            if let opacity {
                if reduced {
                    layer.removeAnimation(forKey: "opacity")
                    layer.opacity = opacity
                } else {
                    let animation = CASpringAnimation(perceptualDuration: Motion.Spring.pop.response, bounce: bounce)
                    animation.keyPath = "opacity"
                    animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
                    animation.toValue = opacity
                    animation.duration = animation.settlingDuration
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    layer.add(animation, forKey: "opacity")
                    layer.opacity = opacity
                    CATransaction.commit()
                }
            }
        }
        if glass != nil {
            pop(icon, transform: on ? CATransform3DMakeScale(1.14, 1.14, 1) : CATransform3DIdentity)
        } else if on, target == nil {
            let backing = LaunchpadGlass.make(blur: 14, tint: 0.28)
            backing.bounds = CGRect(origin: .zero, size: plate.size)
            backing.position = icon.position
            backing.cornerRadius = plate.width * 0.225
            backing.opacity = 0
            backing.transform = CATransform3DMakeScale(0.9, 0.9, 1)
            root.insertSublayer(backing, below: icon)
            target = backing
            pop(backing, transform: CATransform3DMakeScale(1.2, 1.2, 1), opacity: 1)
            pop(icon, transform: CATransform3DMakeScale(0.74, 0.74, 1))
        } else if !on, let backing = target {
            target = nil
            pop(backing, transform: CATransform3DMakeScale(0.9, 0.9, 1), opacity: 0)
            pop(icon, transform: CATransform3DIdentity)
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.Spring.pop.response) { backing.removeFromSuperlayer() }
        }
    }
}

// MARK: - 玻璃小胶囊（搜索 / 页码点、完成、文件夹标题）

@MainActor
final class LaunchpadCapsule: NSView {
    private let material: NSView
    let content = NSView()
    /// 圆角：nil 就是胶囊（高度的一半）。
    var radius: CGFloat? { didSet { applyCorners() } }
    /// Mac 主屏幕搜索使用平面磨砂框；iPad 资料库和编辑控件保留玻璃。
    var flat = false { didSet {
        guard oldValue != flat else { return }
        material.isHidden = flat
#if WINDOWSHADE_SDK_HAS_GLASS
        if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
            glass.contentView = nil
            if flat { addSubview(content) } else { glass.contentView = content }
        }
#endif
        layer?.backgroundColor = flat ? NSColor.white.withAlphaComponent(0.10).cgColor : nil
        layer?.borderColor = flat ? NSColor.white.withAlphaComponent(0.18).cgColor : nil
        layer?.borderWidth = flat ? 0.5 : 0
        layer?.cornerRadius = flat ? 5 : 0
        content.frame = bounds
    } }


    override init(frame: NSRect) {
        func fallback() -> NSView {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            return effect
        }
#if WINDOWSHADE_SDK_HAS_GLASS
        if #available(macOS 26.0, *) { material = NSGlassEffectView() } else { material = fallback() }
#else
        material = fallback()
#endif
        super.init(frame: frame)
        wantsLayer = true
        material.frame = bounds
        material.autoresizingMask = [.width, .height]
        addSubview(material)
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
#if WINDOWSHADE_SDK_HAS_GLASS
        if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
            glass.contentView = content
        } else { addSubview(content) }
#else
        addSubview(content)
#endif
        applyCorners()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        applyCorners()
    }

    private func applyCorners() {
        let radius = self.radius ?? bounds.height / 2
#if WINDOWSHADE_SDK_HAS_GLASS
        if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
            glass.cornerRadius = radius
            return
        }
#endif
        material.wantsLayer = true
        material.layer?.cornerRadius = radius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
    }
}

// MARK: - 翻页

/// 一排横着翻的页（主屏幕、文件夹共用）：一比一跟手，两头有阻尼，松手按惯性推算停在哪页（WWDC18），弹簧接上手指的速度；
/// 翻到一半再抓住，从它当时的位置接着拖。
@MainActor
final class LaunchpadPager {
    let strip: CALayer
    var width: CGFloat = 1
    /// 仅主屏幕允许负一屏；文件夹仍从零开始。
    var minimumPage = 0
    var count = 1 {
        didSet { if page > count - 1 { page = max(count - 1, 0) } }
    }
    private(set) var page = 0
    /// 拖出去多少页（往左拖为正）。
    private(set) var offset: CGFloat = 0
    /// 没加阻尼的拖动量（页）：阻尼按它算，不会越拖越黏。
    private var raw: CGFloat = 0
    private var samples: [(TimeInterval, CGFloat)] = []
    private(set) var tracking = false
    var reduced = false

    init(strip: CALayer) { self.strip = strip }

    /// 当前在第几页的位置（含拖出去的部分），比如 1.3。
    var position: CGFloat {
        if strip.animation(forKey: "page") != nil, let shown = strip.presentation() {
            return -shown.transform.m41 / width
        }
        return CGFloat(page) + offset
    }

    func apply() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.transform = CATransform3DMakeTranslation(-(CGFloat(page) + offset) * width, 0, 0)
        CATransaction.commit()
    }

    func begin(at time: TimeInterval) {
        // 正在翻：从看得见的位置接着拖，不跳。
        let now = position
        strip.removeAnimation(forKey: "page")
        offset = now - CGFloat(page)
        raw = offset
        tracking = true
        samples = [(time, offset)]
        apply()
    }

    /// delta：这次拖了多少点（往左拖、朝下一页为正）。
    func drag(by delta: CGFloat, at time: TimeInterval) {
        guard tracking else { return }
        raw += delta / width
        let lower = CGFloat(minimumPage - page), upper = CGFloat(count - 1 - page)
        if raw < lower {
            offset = lower - CGFloat(LaunchpadPaging.rubberBand(Double(lower - raw), width: 0.35))
        } else if raw > upper {
            offset = upper + CGFloat(LaunchpadPaging.rubberBand(Double(raw - upper), width: 0.35))
        } else {
            offset = raw
        }
        samples.append((time, offset))
        samples = Array(samples.suffix(6))
        apply()
    }

    /// 松手：按惯性推算停在哪页。返回停在哪页。
    @discardableResult
    func end() -> Int {
        tracking = false
        var velocity: CGFloat = 0
        if let first = samples.first, let last = samples.last, last.0 - first.0 > 0.005 {
            velocity = (last.1 - first.1) / CGFloat(last.0 - first.0)
        }
        let target = LaunchpadPaging.settle(page: page - minimumPage, offset: Double(offset), velocity: Double(velocity), pages: count - minimumPage) + minimumPage
        settle(to: target, velocity: velocity)
        return target
    }

    /// 系统取消不等于松手；回到手势开始的页，不投射速度提交下一页。
    func cancel(animated: Bool = true) {
        guard tracking || strip.animation(forKey: "page") != nil else { return }
        settle(to: page, animated: animated)
        samples.removeAll()
    }

    /// 翻到 target 页：弹簧接上手指的速度（页/秒）。animated 为 false 时直接到位。
    func settle(to target: Int, velocity: CGFloat = 0, animated: Bool = true) {
        let from = -position * width
        tracking = false
        page = min(max(target, minimumPage), max(count - 1, minimumPage))
        offset = 0
        raw = 0
        let to = -CGFloat(page) * width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.removeAnimation(forKey: "page")
        strip.transform = CATransform3DMakeTranslation(to, 0, 0)
        if animated, !reduced, abs(to - from) > 0.5 {
            let spring = Motion.spring(.settle, keyPath: "transform.translation.x")
            spring.keyPath = "transform.translation.x"
            spring.fromValue = from
            spring.toValue = to
            spring.initialVelocity = max(-40, min(40, -velocity * width / (to - from)))
            spring.duration = spring.settlingDuration
            strip.add(spring, forKey: "page")
        }
        CATransaction.commit()
    }
}

/// 读屏里的一个按钮（App、文件夹、资料库里的一组）：按下就打开。
final class LaunchpadAccessibilityItem: NSAccessibilityElement {
    private let open: () -> Void

    init(title: String, open: @escaping () -> Void) {
        self.open = open
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    override func accessibilityPerformPress() -> Bool {
        open()
        return true
    }
}
