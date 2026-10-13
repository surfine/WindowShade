// FS-03：拖文件、文字、图片、链接靠近刘海时，刘海垂下落点小岛（文件那一种：三格）。
// 规则见 docs/design-drafts/文件架.html 的“拖近刘海”“文件的三格”“落点小岛怎么分文件和窗口”。
//
// 这个文件分三层：
// 1. 纯逻辑（只靠 Foundation / CoreGraphics）：拖的是哪一类、三格哪格灰、松在哪里算什么、几何数字。单测直接编它。
// 2. FileDragSensor：只在你拖东西的时候看一眼“系统的拖动剪贴板换没换”，不轮询。
// 3. FileDropIslandView：落点小岛里那三格和两耳的字。
import AppKit
import Foundation

// MARK: - 拖的是哪一类

/// 正在拖的是什么：只看类型和个数，不读内容（文件夹要看路径末尾有没有斜杠，只在内存里判一下，不记）。
enum FileDragKind: Equatable, Sendable {
    case files(count: Int, hasFolder: Bool)
    case text
    case image
    case link

    /// 拖动剪贴板里的一项：它带哪些类型、是不是文件夹。
    struct Item: Equatable, Sendable {
        var types: Set<String>
        var isFolder: Bool = false
    }

    static let fileURLType = "public.file-url"
    static let legacyFilenamesType = "NSFilenamesPboardType"
    static let promisedFileTypes: Set<String> = ["com.apple.pasteboard.promised-file-url", "com.apple.NSFilePromiseItemMetaData"]
    static let imageTypes: Set<String> = ["public.png", "public.tiff", "public.jpeg", "public.heic"]
    static let linkTypes: Set<String> = ["public.url", "Apple URL pasteboard type"]
    static let textTypes: Set<String> = ["public.utf8-plain-text", "public.plain-text", "NSStringPboardType"]
    /// 从文件架拖出来的东西带这个记号：经过刘海不再出落点小岛。
    static let fileShelfSourceType = "app.windowshade.fileshelf.item"

    /// 有文件就只当文件；然后图片、链接、文字（文件和文字混着拖，只收文件）。认不出就是 nil（不出小岛）。
    /// 从文件架拖出来的（带记号）也是 nil。
    static func classify(_ items: [Item]) -> FileDragKind? {
        guard !items.isEmpty else { return nil }
        if items.contains(where: { $0.types.contains(fileShelfSourceType) }) { return nil }
        let real = items.filter { $0.types.contains(fileURLType) || $0.types.contains(legacyFilenamesType) }
        if !real.isEmpty { return .files(count: real.count, hasFolder: real.contains { $0.isFolder }) }
        let all = items.reduce(into: Set<String>()) { $0.formUnion($1.types) }
        if !all.isDisjoint(with: imageTypes) { return .image }
        let promised = items.filter { !$0.types.isDisjoint(with: promisedFileTypes) }
        if !promised.isEmpty { return .files(count: promised.count, hasFolder: false) }
        if !all.isDisjoint(with: linkTypes) { return .link }
        if !all.isDisjoint(with: textTypes) { return .text }
        return nil
    }

    var isFiles: Bool { if case .files = self { return true } else { return false } }

    /// 左耳上拿着的东西：“3 个”“文件夹”“文字”“图片”“链接”。一个文件写“文件”。
    var holdingLabel: String {
        switch self {
        case .files(let count, let hasFolder):
            if count == 1 { return hasFolder ? WSL10n.text("launchpad.folder", zh: "文件夹") : WSL10n.text("fileDrag.file", zh: "文件") }
            return WSL10n.text("fileDrag.countItems", zh: "%@ 个", String(count))
        case .text: return WSL10n.text("fileDrag.text", zh: "文字")
        case .image: return WSL10n.text("fileDrag.image", zh: "图片")
        case .link: return WSL10n.text("fileDrag.link", zh: "链接")
        }
    }

    /// 左耳上的符号。
    var holdingSymbol: String {
        switch self {
        case .files(let count, let hasFolder): return count == 1 ? (hasFolder ? "folder.fill" : "doc.fill") : "doc.on.doc.fill"
        case .text: return "text.alignleft"
        case .image: return "photo.fill"
        case .link: return "link"
        }
    }

    /// 读屏念的：拿着什么。
    var spokenLabel: String {
        switch self {
        case .files(let count, let hasFolder): return count == 1 ? (hasFolder ? WSL10n.text("fileDrag.oneFolder", zh: "一个文件夹") : WSL10n.text("fileDrag.oneFile", zh: "一个文件")) : "\(count) 个文件"
        case .text: return WSL10n.text("fileDrag.someText", zh: "一段文字")
        case .image: return WSL10n.text("fileDrag.oneImage", zh: "一张图片")
        case .link: return WSL10n.text("fileDrag.oneLink", zh: "一个链接")
        }
    }
}

// MARK: - 三格

enum FileDropCell: Int, CaseIterable, Sendable {
    case stage, airDrop, openWith

    var title: String {
        switch self {
        case .stage: return WSL10n.text("fileDrag.stage", zh: "暂存")
        case .airDrop: return WSL10n.text("silent.activity.airdrop", zh: "隔空投送")
        case .openWith: return WSL10n.text("fileDrag.openWith", zh: "用 App 打开")
        }
    }

    var symbol: String {
        switch self {
        case .stage: return "tray.and.arrow.down.fill"
        case .airDrop: return "dot.radiowaves.left.and.right"
        case .openWith: return "arrow.up.forward.app.fill"
        }
    }
}

/// 现在的事实：文件架开没开、满没满，隔空投送能不能用、是不是正忙。
struct FileDropEnvironment: Equatable, Sendable {
    var shelfEnabled = true
    var shelfFull = false
    var airDropAvailable = true
    var airDropBusy = false
}

struct FileDropCellState: Equatable, Sendable {
    var enabled: Bool
    /// 做不了的原因，右耳说；做得了是 nil。
    var reason: String?
}

/// 指针在小岛的哪里。
enum FileDropHit: Equatable, Sendable {
    /// 在某一格里。
    case cell(FileDropCell)
    /// 在刘海那一条上（岛里、不在格子里）：松手 = 暂存。
    case strip
    /// 在岛里，但是格子外面的边距。
    case margin
    /// 在岛外。
    case outside
}

/// 松手会发生什么。
enum FileDropRelease: Equatable, Sendable {
    case stage, airDrop, openWith, nothing
}

enum FileDropPlan {
    /// 这一格能不能用。
    static func state(of cell: FileDropCell, kind: FileDragKind, env: FileDropEnvironment) -> FileDropCellState {
        switch cell {
        case .stage:
            if !env.shelfEnabled { return FileDropCellState(enabled: false, reason: WSL10n.text("fileDrag.reason.shelfOff", zh: "文件架没开")) }
            if env.shelfFull { return FileDropCellState(enabled: false, reason: WSL10n.text("fileDrag.reason.shelfFull", zh: "文件架满了")) }
            return FileDropCellState(enabled: true, reason: nil)
        case .airDrop:
            if !env.airDropAvailable { return FileDropCellState(enabled: false, reason: WSL10n.text("fileDrag.reason.airDropOff", zh: "隔空投送没开")) }
            if env.airDropBusy { return FileDropCellState(enabled: false, reason: WSL10n.text("fileDrag.reason.airDropBusy", zh: "正在隔空投送")) }
            return FileDropCellState(enabled: true, reason: nil)
        case .openWith:
            switch kind {
            case .text: return FileDropCellState(enabled: false, reason: WSL10n.text("fileDrag.reason.textNoApp", zh: "文字挑不了 App"))
            case .image: return FileDropCellState(enabled: false, reason: WSL10n.text("fileDrag.reason.imageNoApp", zh: "图片挑不了 App"))
            case .files, .link: return FileDropCellState(enabled: true, reason: nil)
            }
        }
    }

    /// 松手在 hit 上：格子里 = 那一格（灰的什么都不做）；刘海那一条上 = 暂存（Aaron 定）；别处什么都不做。
    static func release(at hit: FileDropHit, kind: FileDragKind, env: FileDropEnvironment) -> FileDropRelease {
        switch hit {
        case .cell(let cell):
            guard state(of: cell, kind: kind, env: env).enabled else { return .nothing }
            switch cell {
            case .stage: return .stage
            case .airDrop: return .airDrop
            case .openWith: return .openWith
            }
        case .strip:
            return state(of: .stage, kind: kind, env: env).enabled ? .stage : .nothing
        case .margin, .outside:
            return .nothing
        }
    }

    /// 右耳：指着的那一格做不了时说为什么，其余时候空着（格子上已经写了字）。
    static func rightEar(at hit: FileDropHit, kind: FileDragKind, env: FileDropEnvironment) -> String? {
        switch hit {
        case .cell(let cell): return state(of: cell, kind: kind, env: env).reason
        case .strip: return state(of: .stage, kind: kind, env: env).reason
        case .margin, .outside: return nil
        }
    }
}

// MARK: - 几何

/// 落点小岛（文件那一种）的数字，照稿：340 × 84，圆角 22，格 100.7 × 34.5、圆角 12，格间 6，边距 10。
enum FileDropGeometry {
    static let islandSize = CGSize(width: 340, height: 84)
    static let islandCorner: CGFloat = 22
    static let cellSize = CGSize(width: 100.7, height: 34.5)
    static let cellCorner: CGFloat = 12
    static let cellGap: CGFloat = 6
    static let margin: CGFloat = 10
    /// 指针离屏幕顶 60 点内、横向在刘海中心 ±194 点内就垂下。
    static let triggerDepth: CGFloat = 60
    static let triggerHalfWidth: CGFloat = 194
    /// 指针出了岛外这么远就收。
    static let dismissDistance: CGFloat = 24
    static let disabledAlpha: CGFloat = 0.32
    static let litFillAlpha: CGFloat = 0.16
    static let litStroke: CGFloat = 1.5
    /// 停在“用 App 打开”上这么久，主屏幕就弹开（今天的值）。
    static let openWithDwell: TimeInterval = 0.35

    /// Cocoa 坐标（y 向上）。screenTop：这块屏的顶边 y。
    static func shouldShow(pointer: CGPoint, screenTop: CGFloat, notchMidX: CGFloat) -> Bool {
        pointer.y <= screenTop + 1 && screenTop - pointer.y <= triggerDepth && abs(pointer.x - notchMidX) <= triggerHalfWidth
    }

    /// 已经垂下之后：还在岛里或离岛不到 24 点就留着。
    static func shouldKeep(pointer: CGPoint, island: CGRect) -> Bool {
        island.insetBy(dx: -dismissDistance, dy: -dismissDistance).contains(pointer)
    }

    /// 岛的外框：顶边贴着屏幕顶，横向居中在刘海上。
    static func island(notchMidX: CGFloat, screenTop: CGFloat) -> CGRect {
        CGRect(x: notchMidX - islandSize.width / 2, y: screenTop - islandSize.height,
               width: islandSize.width, height: islandSize.height)
    }

    /// 三格的外框（从左到右：暂存、隔空投送、用 App 打开），横向居中、底边距岛底 10 点。
    static func cellRects(in island: CGRect) -> [CGRect] {
        let total = cellSize.width * 3 + cellGap * 2
        let left = island.midX - total / 2
        return (0..<3).map { index in
            CGRect(x: left + CGFloat(index) * (cellSize.width + cellGap), y: island.minY + margin,
                   width: cellSize.width, height: cellSize.height)
        }
    }

    /// 指针在哪：格子里（格间的缝算挨着的那一格）、刘海那一条上、格子外的边距、岛外。
    static func hit(_ point: CGPoint, island: CGRect) -> FileDropHit {
        guard island.contains(point) else { return .outside }
        let rects = cellRects(in: island)
        let rowTop = rects[0].maxY
        if point.y > rowTop { return .strip }
        guard point.y >= rects[0].minY else { return .margin }
        for (index, rect) in rects.enumerated() {
            let lower = index == 0 ? rect.minX : rect.minX - cellGap / 2
            let upper = index == 2 ? rect.maxX : rect.maxX + cellGap / 2
            if point.x >= lower && (index == 2 ? point.x <= upper : point.x < upper) {
                return .cell(FileDropCell(rawValue: index) ?? .stage)
            }
        }
        return .margin
    }
}

// MARK: - 拖动的读取与动作（松手后才读内容）

/// 松在格子上才读的内容。
enum FileDropPayload {
    case files([URL])
    /// 从邮件、照片这类 App 拖来的“承诺文件”：松手后才由对方写出来（NSFilePromiseReceiver）。
    case promises([NSFilePromiseReceiver])
    case text(String)
    case image(Data, fileExtension: String)
    case link(URL)

    /// 读系统的拖动剪贴板。认不出就是 nil。
    static func read(_ pasteboard: NSPasteboard, kind: FileDragKind) -> FileDropPayload? {
        switch kind {
        case .files:
            let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            if !urls.isEmpty { return .files(urls) }
            let receivers = (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]) ?? []
            return receivers.isEmpty ? nil : .promises(receivers)
        case .image:
            if let png = pasteboard.data(forType: .png) { return .image(png, fileExtension: "png") }
            if let jpeg = pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg")) { return .image(jpeg, fileExtension: "jpg") }
            if let tiff = pasteboard.data(forType: .tiff),
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                return .image(png, fileExtension: "png")
            }
            return nil
        case .link:
            let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
            guard let url = objects?.first(where: { !$0.isFileURL }) else { return nil }
            return .link(url)
        case .text:
            guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
            return .text(text)
        }
    }

    /// 交给隔空投送的东西。
    var sharingItems: [Any] {
        switch self {
        case .files(let urls): return urls
        case .promises: return []
        case .text(let text): return [text]
        case .image(let data, _): return NSImage(data: data).map { [$0] } ?? []
        case .link(let url): return [url]
        }
    }

    /// 给“用 App 打开”：文件和链接可以，文字、图片不行。
    var openableURLs: [URL] {
        switch self {
        case .files(let urls): return urls
        case .link(let url): return [url]
        case .text, .image, .promises: return []
        }
    }

    /// 放进文件架（异步；结果回主线程）。
    @MainActor
    func stage(into store: FileShelfStore, completion: @escaping @MainActor (FileShelfAddOutcome) -> Void,
               failure: @escaping @MainActor (String) -> Void = { _ in }) {
        let done: @Sendable (FileShelfAddOutcome) -> Void = { outcome in
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(outcome) } }
        }
        switch self {
        case .files(let urls): store.add(urls: urls, completion: done)
        case .promises(let receivers):
            FileShelfPromises.receive(receivers) { urls, failed in
                if failed > 0 { DispatchQueue.main.async { MainActor.assumeIsolated { failure(FileShelfPromises.failureText) } } }
                if urls.isEmpty {
                    done(FileShelfAddOutcome(rejection: .empty))
                } else {
                    store.add(urls: urls, completion: done)
                }
            }
        case .text(let text): store.addText(text, completion: done)
        case .image(let data, let ext): store.addImage(data, fileExtension: ext, completion: done)
        case .link(let url): store.addLink(url, completion: done)
        }
    }
}

/// 收承诺文件（NSFilePromiseReceiver）：对方把文件写进我们给的文件夹，收齐后照常记位置（书签）。
/// 写进文件架自己的“收到的”文件夹，不放临时目录，免得系统清掉后书签找不到。
enum FileShelfPromises {
    static var failureText: String { WSL10n.text("fileDrag.failure", zh: "这个文件没能拿到，没有放进文件架") }

    static var defaultDestination: URL {
        FileShelf.defaultRoot.appendingPathComponent("收到的", isDirectory: true)
    }

    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "WindowShade.FileShelf.promises"
        queue.qualityOfService = .utility
        return queue
    }()

    /// 汇总每个承诺的结果；全部回来后只调一次 finish。
    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        private var urls: [URL] = []
        private var failed = 0
        private let finish: @Sendable ([URL], Int) -> Void

        init(expected: Int, finish: @escaping @Sendable ([URL], Int) -> Void) {
            remaining = expected
            self.finish = finish
            if expected <= 0 { finish([], 0) }
        }

        func record(url: URL?) {
            lock.lock()
            if let url { urls.append(url) } else { failed += 1 }
            remaining -= 1
            let done = remaining == 0
            let result = (urls, failed)
            lock.unlock()
            if done { finish(result.0.sorted { $0.path < $1.path }, result.1) }
        }
    }

    @MainActor
    static func receive(_ receivers: [NSFilePromiseReceiver], destination: URL = defaultDestination,
                        finish: @escaping @Sendable ([URL], Int) -> Void) {
        let expected = receivers.reduce(0) { $0 + max(1, $1.fileNames.count) }
        let collector = Collector(expected: expected, finish: finish)
        let batch = destination.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: batch, withIntermediateDirectories: true)) != nil else {
            for _ in 0..<expected { collector.record(url: nil) }
            return
        }
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: batch, options: [:], operationQueue: queue) { url, error in
                collector.record(url: error == nil ? url : nil)
            }
        }
    }
}

extension FileShelf {
    /// 唯一一份文件架存取。没开文件架时不会 start，也就什么都不记。
    static let shared = FileShelfStore()
}

/// 隔空投送能不能用（只问系统有没有这项服务；真正能不能发，等交出去那一下系统会说）。
enum FileDropAirDrop {
    @MainActor static var isAvailable: Bool {
        guard let service = NSSharingService(named: .sendViaAirDrop) else { return false }
        return service.canPerform(withItems: [URL(fileURLWithPath: NSTemporaryDirectory())])
    }
}

// MARK: - 感知拖动

/// 落点小岛在拖动里的几步：进来、移动、离开、松手。
enum IslandDragPhase { case entered, updated, exited, perform }

/// 只在你按着鼠标拖东西的时候工作：按下时记一下系统的拖动剪贴板换到第几份，拖动里它换了，
/// 就是你拖起了一样东西（文件、文字、图片或链接）。不轮询，没有定时器；停止时监听就拆掉。
@MainActor
final class FileDragSensor {
    /// 拖起了一样东西（哪一类）。返回 false 表示这次不接（全屏、锁屏、认证中……）。
    var onBegan: ((FileDragKind) -> Bool)?
    /// 拖着时指针的位置（Cocoa 坐标）。
    var onMoved: ((CGPoint) -> Void)?
    /// 鼠标抬起了。
    var onEnded: (() -> Void)?

    private var monitor: Any?
    private var baseline = 0
    private var state: State = .idle
    private enum State { case idle, watching, dragging, ignored }

    var isRunning: Bool { monitor != nil }
    var isDragging: Bool { state == .dragging }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            let point = NSEvent.mouseLocation
            MainActor.assumeIsolated { self?.handle(type, at: point) }
        }
    }

    func stop() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        if state == .dragging { onEnded?() }
        state = .idle
    }

    private func handle(_ type: NSEvent.EventType, at point: CGPoint) {
        switch type {
        case .leftMouseDown:
            baseline = NSPasteboard(name: .drag).changeCount
            state = .watching
        case .leftMouseDragged:
            switch state {
            case .watching:
                let pasteboard = NSPasteboard(name: .drag)
                guard pasteboard.changeCount != baseline else { return }
                guard let kind = Self.kind(of: pasteboard) else { state = .ignored; return }
                if onBegan?(kind) == true {
                    state = .dragging
                    onMoved?(point)
                } else {
                    state = .ignored
                }
            case .dragging: onMoved?(point)
            case .idle, .ignored: break
            }
        case .leftMouseUp:
            if state == .dragging { onEnded?() }
            state = .idle
        default: break
        }
    }

    /// 看拖动剪贴板里每一项带什么类型。只在拖动开始时看一次。
    static func kind(of pasteboard: NSPasteboard) -> FileDragKind? {
        let items = (pasteboard.pasteboardItems ?? []).prefix(500).map { item -> FileDragKind.Item in
            let types = Set(item.types.map(\.rawValue))
            var folder = false
            if types.contains(FileDragKind.fileURLType), let text = item.string(forType: .fileURL) {
                folder = text.hasSuffix("/")
            }
            return FileDragKind.Item(types: types, isFolder: folder)
        }
        return FileDragKind.classify(Array(items))
    }
}

// MARK: - 画：三格和两耳

/// 落点小岛（文件那一种）要画的东西。
struct FileDropIslandModel: Equatable {
    var kind: FileDragKind
    var env: FileDropEnvironment
    var hit: FileDropHit
    /// 刘海宽：左右耳在刘海两边。
    var notchWidth: CGFloat

    var rightEar: String? { FileDropPlan.rightEar(at: hit, kind: kind, env: env) }
}

/// 三格加两耳。坐标原点在岛的左下角（和 NotchContentView 的 bounds 一致）。
final class FileDropIslandView: NSView {
    private let leftIcon = NSImageView()
    private let leftLabel = NSTextField(labelWithString: "")
    private let rightLabel = NSTextField(labelWithString: "")
    private var cellViews: [FileDropCellView] = []
    private(set) var model: FileDropIslandModel?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for label in [leftLabel, rightLabel] {
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = NSColor.white.withAlphaComponent(0.85)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }
        rightLabel.alignment = .right
        leftIcon.imageScaling = .scaleProportionallyUpOrDown
        leftIcon.contentTintColor = .white
        addSubview(leftIcon)
        cellViews = FileDropCell.allCases.map { cell in
            let view = FileDropCellView(cell: cell)
            addSubview(view)
            return view
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ model: FileDropIslandModel) {
        self.model = model
        let island = bounds
        let rects = FileDropGeometry.cellRects(in: island)
        for (index, view) in cellViews.enumerated() {
            let cell = view.cell
            let state = FileDropPlan.state(of: cell, kind: model.kind, env: model.env)
            view.frame = rects[index]
            view.apply(enabled: state.enabled, light: Self.light(of: cell, hit: model.hit, enabled: state.enabled))
        }
        // 两耳：刘海两边，贴着刘海那一条（顶部 notchHeight 高）。
        let earWidth = max(0, (island.width - model.notchWidth) / 2)
        let stripHeight = max(0, island.height - rects[0].maxY)
        let earY = island.maxY - min(stripHeight, 33.5) + (min(stripHeight, 33.5) - 15) / 2
        let inset: CGFloat = 12
        let iconSide: CGFloat = 14
        leftIcon.image = NSImage(systemSymbolName: model.kind.holdingSymbol, accessibilityDescription: model.kind.spokenLabel)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        leftIcon.frame = NSRect(x: inset, y: earY, width: iconSide, height: 15)
        leftLabel.stringValue = model.kind.holdingLabel
        leftLabel.frame = NSRect(x: inset + iconSide + 4, y: earY, width: max(0, earWidth - inset - iconSide - 4 - 4), height: 15)
        let reason = model.rightEar
        rightLabel.stringValue = reason ?? ""
        rightLabel.isHidden = reason == nil
        rightLabel.textColor = NSColor.white.withAlphaComponent(0.85)
        rightLabel.frame = NSRect(x: island.maxX - earWidth + 4, y: earY, width: max(0, earWidth - inset - 4), height: 15)
        setAccessibilityElement(false)
    }

    private static func light(of cell: FileDropCell, hit: FileDropHit, enabled: Bool) -> FileDropCellView.Light {
        guard enabled else { return .off }
        switch hit {
        case .cell(let hovered): return hovered == cell ? .lit : .off
        // 指针在刘海那一条上时，“暂存”淡淡地亮，表示松手去这里。
        case .strip: return cell == .stage ? .soft : .off
        case .margin, .outside: return .off
        }
    }
}

final class FileDropCellView: NSView {
    enum Light { case off, soft, lit }
    let cell: FileDropCell
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(cell: FileDropCell) {
        self.cell = cell
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = FileDropGeometry.cellCorner
        layer?.cornerCurve = .continuous
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .white
        icon.image = NSImage(systemSymbolName: cell.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        label.stringValue = cell.title
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        addSubview(icon)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        let iconSide: CGFloat = 14
        let textWidth = ceil(label.intrinsicContentSize.width)
        let gap: CGFloat = 4
        let total = min(bounds.width - 8, iconSide + gap + textWidth)
        let left = (bounds.width - total) / 2
        icon.frame = NSRect(x: left, y: (bounds.height - iconSide) / 2, width: iconSide, height: iconSide)
        label.frame = NSRect(x: left + iconSide + gap, y: (bounds.height - 15) / 2,
                             width: max(0, total - iconSide - gap), height: 15)
    }

    func apply(enabled: Bool, light: Light) {
        needsLayout = true
        alphaValue = enabled ? 1 : FileDropGeometry.disabledAlpha
        let white: CGFloat
        switch light {
        case .off: white = 0.07
        case .soft: white = 0.10
        case .lit: white = FileDropGeometry.litFillAlpha
        }
        layer?.backgroundColor = NSColor.white.withAlphaComponent(white).cgColor
        layer?.borderWidth = light == .lit ? FileDropGeometry.litStroke : 0
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        setAccessibilityLabel(enabled ? cell.title
                                      : cell.title + WSL10n.text("fileDrag.notUsableNow", zh: "，现在不能用"))
    }
}
