// // 岛里的一层内容：提示字、下巴点、紧凑样式、提醒、一排格子、下拉图标（换内容整层换）。

import Cocoa
import ApplicationServices

/// 岛里的一层内容：提示字、下巴上的点、紧凑样式、提醒、一排格子、往下拉时露出来的图标。
/// 换内容时整层换：旧的一层淡出（不再接指针），新的一层淡入。
final class NotchContentView: NSView {
    var inert = false
    var onTileClicked: ((CGWindowID, NSRect?) -> Void)?
    var onTileHover: ((CGWindowID, Bool, NSRect?) -> Void)?
    var onTileAccessory: ((CGWindowID) -> Void)?
    let activityView = NotchActivityView(frame: .zero)
    private let hint = NSTextField(labelWithString: "")
    private let dots = NotchDotsView()
    private let compactView = NotchCompactView()
    private let mark = NotchSecondaryMark()
    private let alertView = NotchAlertView()
    /// 左段窗口和右段正在进行的之间那一条竖线（只在两段都有格子时露出）。
    private let divider = NotchRowDivider()
    /// 第二条竖线（离开期间、窗口、正在进行的三段都有时）。
    private let divider2 = NotchRowDivider()
    /// 离开期间那一段的小标题：写在刘海左边，读屏念「离开期间，N 件」（这一组的名字）。
    private let awayHeading = NSTextField(labelWithString: "")
    /// 那一排的滚动：视口（固定、裁边、左右淡出）里放一张比它宽的文档，格子和竖线都在文档上，滚动就是挪文档。
    private let rowViewport = NSView()
    private let rowDocument = NSView()
    private let rowFade = CAGradientLayer()
    /// 现在滚到哪（点，0 = 最左）；格子数、视口宽变了会夹回范围内。
    private(set) var rowOffset: Double = 0
    private var rowContentWidth: Double = 0
    private var rowViewportWidth: Double = 0
    private var rowLayout = NotchRow.Layout(windows: 0, ongoing: 0)
    /// 格子编号到它在留着的格子里的序号（键盘焦点滚进视口用）。
    private var rowRank: [CGWindowID: Int] = [:]
    private static let rowScrollKey = "row.scroll"
    func echoAlertKeys() { alertView.echoKeys() }
    /// 换歌一瞥收回两耳：只把那一行淡掉，两耳留在原地（NotchCanvasView.morph 的退场）。
    func fadeAlert(duration: TimeInterval, completion: @escaping @MainActor @Sendable () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            alertView.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { completion() }
        })
    }
    func setMusicWave(_ wave: NowPlayingWave) { compactView.setMusicWave(wave) }
    private let pullView = NSImageView()
    /// 落点里的符号：托盘，收下后换成对勾（原地换，符号自己的过渡）。
    private let glyph = NSImageView()
    private var glyphState: NotchPanel.DropState = .none
    /// FS-03：文件那一种落点小岛（三格加两耳）。
    private let fileIsland = FileDropIslandView()
    /// 落点小岛上的五个去处。
    private var choiceViews: [NSImageView] = []
    private var tileViews: [NotchTileView] = []
    private(set) var pullIconRect: NSRect?
    let isEmpty: Bool
    /// 打字筛选（LA-7）：刘海左边那一段的字（13 半粗）加一个光标，以及一格也没有时的话。
    private let queryLabel = NSTextField(labelWithString: "")
    private let queryCursor = NSView()
    private let noMatchLabel = NSTextField(labelWithString: NotchRowFilter.noMatchText)
    /// 上一次排版时留着的格子：变了才动画。
    private var placedShownIDs: Set<CGWindowID>?
    private var placedOnce = false

    init(content: NotchCanvasView.Content) {
        isEmpty = content.tiles.isEmpty && content.hint == nil && content.compact == nil && content.alert == nil
            && content.activities.isEmpty && content.dots == 0 && !content.dotsChanged && content.pullIcon == nil
            && !content.secondaryDot && content.fileDrop == nil
        super.init(frame: .zero)
        wantsLayer = true
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.85)
        hint.alignment = .center
        hint.stringValue = content.hint ?? ""
        hint.isHidden = content.hint == nil
        addSubview(hint)
        addSubview(dots)
        addSubview(compactView)
        addSubview(mark)
        addSubview(alertView)
        addSubview(activityView)
        divider.isHidden = true
        divider2.isHidden = true
        awayHeading.font = .systemFont(ofSize: 13, weight: .semibold)
        awayHeading.textColor = NSColor.white.withAlphaComponent(0.85)
        awayHeading.alignment = .right
        awayHeading.lineBreakMode = .byClipping
        awayHeading.isHidden = true
        awayHeading.setAccessibilityRole(.staticText)
        rowViewport.wantsLayer = true
        rowViewport.layer?.masksToBounds = true
        rowFade.startPoint = CGPoint(x: 0, y: 0.5)
        rowFade.endPoint = CGPoint(x: 1, y: 0.5)
        rowFade.actions = ["colors": NSNull(), "locations": NSNull(), "bounds": NSNull(), "position": NSNull()]
        rowViewport.layer?.mask = rowFade
        rowDocument.wantsLayer = true
        rowDocument.addSubview(divider)
        rowDocument.addSubview(divider2)
        rowViewport.addSubview(rowDocument)
        addSubview(rowViewport)
        queryLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        queryLabel.textColor = .white
        queryLabel.alignment = .right
        queryLabel.lineBreakMode = .byClipping
        queryLabel.isHidden = true
        queryCursor.wantsLayer = true
        queryCursor.layer?.backgroundColor = NSColor.white.cgColor
        queryCursor.layer?.cornerRadius = 0.75
        queryCursor.isHidden = true
        noMatchLabel.font = .systemFont(ofSize: 13, weight: .medium)
        noMatchLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        noMatchLabel.alignment = .center
        noMatchLabel.isHidden = true
        addSubview(awayHeading)
        addSubview(queryLabel)
        addSubview(queryCursor)
        addSubview(noMatchLabel)
        pullView.imageScaling = .scaleProportionallyUpOrDown
        pullView.image = content.pullIcon
        addSubview(pullView)
        glyph.imageScaling = .scaleProportionallyUpOrDown
        glyph.contentTintColor = .white
        addSubview(glyph)
        fileIsland.isHidden = true
        addSubview(fileIsland)
        choiceViews = NotchPanel.DropChoice.allCases.map { choice in
            let view = NSImageView()
            view.imageScaling = .scaleProportionallyUpOrDown
            view.contentTintColor = .white
            view.image = NSImage(systemSymbolName: choice.symbol, accessibilityDescription: choice.title)?
                .withSymbolConfiguration(.init(pointSize: 18, weight: .semibold))
            view.isHidden = true
            addSubview(view)
            return view
        }
        tileViews = content.tiles.map { tile in
            let view = NotchTileView(tile: tile)
            view.setPosition((content.tiles.firstIndex { $0.id == tile.id } ?? 0) + 1, of: content.tiles.count)
            view.onClick = { [weak self] rect in self?.onTileClicked?(tile.id, rect) }
            view.onAccessory = { [weak self] in self?.onTileAccessory?(tile.id) }
            view.onHover = { [weak self, weak view] inside in
                let rect = view.flatMap { view in view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) } }
                self?.onTileHover?(tile.id, inside, rect)
            }
            rowDocument.addSubview(view)
            return view
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// 这一格的画面到了：原地换。
    func updateSnapshot(id: CGWindowID, image: CGImage?) {
        tileViews.first { $0.tileID == id }?.setSnapshot(image)
    }

    func updateOngoingQuantity(id: CGWindowID, quantity: NotchActivity.Quantity, text: String?) {
        tileViews.first { $0.tileID == id }?.setQuantity(quantity, text: text)
    }

    /// 键盘焦点亮在哪一格（nil 全熄）。`bump`：那一格到头了，顶一下。焦点格在视口外时把它滚进来。
    func setFocus(_ id: CGWindowID?, bump: FocusNavigator.Direction? = nil, animated: Bool = true) {
        for view in tileViews {
            let lit = view.tileID == id
            view.setFocused(lit, bump: lit ? bump : nil, animated: animated)
        }
        if let id { revealRowCell(id, animated: animated) }
    }

    /// 只滚不亮：按住小圆展开后滚到那件活动的格。
    func revealTile(_ id: CGWindowID) { revealRowCell(id, animated: true) }

    // MARK: 那一排的滚动（照系统的岛：宽固定 408，格子全部排出，放不下左右滚）

    /// 那一排放不下、能滚。
    var rowCanScroll: Bool {
        !inert && !rowViewport.isHidden && NotchRow.maxScrollOffset(contentWidth: rowContentWidth, viewport: rowViewportWidth) > 0
    }

    /// 窗口坐标里的这一点在那一排的范围里（视口加四周的边距）：横扫在这里归那一排，在别处照旧。
    func rowScrollArea(contains windowPoint: NSPoint) -> Bool {
        guard !rowViewport.isHidden, rowViewport.frame.height > 0 else { return false }
        let point = convert(windowPoint, from: nil)
        let margin = CGFloat(NotchRow.edgeMargin)
        return rowViewport.frame.insetBy(dx: -margin, dy: -margin).contains(point)
    }

    /// 手指或滚轮滚了 `delta` 点（正 = 往后看）。跟手：不加动画；正在飞的键盘滚动从它此刻的位置接手。返回有没有滚。
    @discardableResult
    func scrollRow(by delta: Double) -> Bool {
        guard rowCanScroll else { return false }
        syncRowOffsetToPresentation()
        let next = NotchRow.clampedOffset(rowOffset + delta, contentWidth: rowContentWidth, viewport: rowViewportWidth)
        guard next != rowOffset else { return true }
        rowOffset = next
        rowDocument.frame.origin.x = CGFloat(-next)
        updateRowFade()
        return true
    }

    /// 键盘焦点走到某一格：滚到看得全它。有动画时挂一根弹簧（令牌 calm），中途再滚就从此刻的位置和速度接上。
    private func revealRowCell(_ id: CGWindowID, animated: Bool) {
        guard rowCanScroll, let rank = rowRank[id] else { return }
        let current = Double(-RowSpringMotion.presentedMinX(rowDocument))
        let target = NotchRow.offset(toReveal: rank, in: rowLayout, current: current, viewport: rowViewportWidth)
        guard abs(target - rowOffset) > 0.5 || rowDocument.layer?.animation(forKey: Self.rowScrollKey) != nil else { return }
        let before = RowSpringMotion.presentedX(rowDocument)
        rowOffset = target
        rowDocument.frame.origin.x = CGFloat(-target)
        if animated, !Motion.reduced, let layer = rowDocument.layer {
            RowSpringMotion.slide(layer, key: Self.rowScrollKey, presentedX: before, modelX: RowSpringMotion.modelX(rowDocument), token: .calm)
        } else {
            rowDocument.layer?.removeAnimation(forKey: Self.rowScrollKey)
        }
        updateRowFade()
    }

    /// 手接手：正在飞的滚动动画停下，把此刻呈现的位置记成模型位置。
    private func syncRowOffsetToPresentation() {
        guard let layer = rowDocument.layer, layer.animation(forKey: Self.rowScrollKey) != nil else { return }
        let presented = RowSpringMotion.presentedMinX(rowDocument)
        layer.removeAnimation(forKey: Self.rowScrollKey)
        rowOffset = NotchRow.clampedOffset(Double(-presented), contentWidth: rowContentWidth, viewport: rowViewportWidth)
        rowDocument.frame.origin.x = CGFloat(-rowOffset)
    }

    /// 整排重建时（有格子进出）把滚动位置带过来：补位后可见的格子不跳。
    func carryRowOffset(_ offset: Double) { rowOffset = max(0, offset) }

    /// 左右边缘的淡出：滚过了左边淡，后面还有右边淡。
    private func updateRowFade() {
        let width = max(1, CGFloat(rowViewportWidth))
        let fades = NotchRow.edgeFades(offset: rowOffset, contentWidth: rowContentWidth, viewport: rowViewportWidth)
        let edge = min(0.5, IslandMetrics.rowEdgeFadeWidth / width)
        func alpha(_ faded: Bool) -> CGColor { NSColor.black.withAlphaComponent(faded ? 0 : 1).cgColor }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rowFade.locations = [0, NSNumber(value: Double(edge)), NSNumber(value: Double(1 - edge)), 1]
        rowFade.colors = [alpha(fades.leading), NSColor.black.cgColor, NSColor.black.cgColor, alpha(fades.trailing)]
        CATransaction.commit()
    }

    var alertIconScreenRect: NSRect? { alertView.iconScreenRect }

    /// 格子先全透明，再按序号一格一格淡入：第 i 格在形状开始后 0.09 + 0.04 × i 秒起。
    func staggerTiles(fade: TimeInterval) {
        guard tileViews.count > 0 else { return }
        for view in tileViews where !view.isHidden { view.alphaValue = 0 }
        for (index, view) in tileViews.enumerated() where !view.isHidden {
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchSmallBehaviour.tileFadeDelay(index: index)) { [weak view] in
                MainActor.assumeIsolated {
                    guard let view else { return }
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = fade
                        view.animator().alphaValue = 1
                    }
                }
            }
        }
    }

    /// 某一格此刻在屏幕上的位置（键盘「看一眼」要从这里长出来）。
    func tileScreenRect(_ id: CGWindowID) -> NSRect? {
        guard let view = tileViews.first(where: { $0.tileID == id }), let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    /// 键盘上的 Return 打开某一格。找不到这一格返回 false。
    @discardableResult
    func activateTile(_ id: CGWindowID) -> Bool {
        guard let view = tileViews.first(where: { $0.tileID == id }) else { return false }
        view.activateFromKeyboard()
        return true
    }

    /// 第二层（副句、按钮）比第一层晚 `lag` 秒淡入。第一层刚开始淡入时调用；`lag` 为 0（减少动态效果）时不分层。
    func revealSecondLayer(after lag: TimeInterval, duration: TimeInterval) {
        guard lag > 0, !activityView.isHidden else { return }
        activityView.setSecondLayer(alpha: 0, duration: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + lag) { [weak self] in
            MainActor.assumeIsolated { self?.activityView.setSecondLayer(alpha: 1, duration: duration) }
        }
    }

    /// 辅助功能的 hit-test 可以从后台线程进来：AppKit 随时可能调，方法不能挂 MainActor 隔离
    /// （真机 --notch 探针实证：隔离断言在进方法体之前炸出 SIGTRAP）。主线程内才碰状态。
    nonisolated override func hitTest(_ point: NSPoint) -> NSView? {
        guard Thread.isMainThread else { return nil }
        return MainActor.assumeIsolated { inert ? nil : super.hitTest(point) }
    }

    /// 窗口坐标里的这一点，是不是落在某件活动的紧凑左耳或右耳上（NP-2 留的入口，现在每种活动都算）。
    func isOnActivityEar(windowPoint: NSPoint) -> Bool {
        guard !inert, compactView.showsActivityEars else { return false }
        let point = convert(windowPoint, from: nil)
        guard bounds.contains(point) else { return false }
        let region = IslandInteraction.region(x: point.x, islandWidth: bounds.width, notchWidth: placedNotchWidth)
        return IslandInteraction.tap(in: region, earsAreActivity: true) == .openActivity
    }
    /// 紧凑那一件是不是正在播放（点它的耳朵是长成大卡，不是打开 Music）。
    var compactIsMusic: Bool { compactView.compactIsMusic }
    /// 上一次排版时的刘海宽（分左耳、右耳、本体用）。
    private var placedNotchWidth: CGFloat = 0

    /// 按岛的终点排好（rect：画布坐标里岛的外框）。
    func place(in rect: NSRect, content: NotchCanvasView.Content) {
        frame = rect
        placedNotchWidth = content.notchWidth
        let bounds = NSRect(origin: .zero, size: rect.size)
        dots.frame = bounds
        dots.update(count: content.dots, changed: content.dotsChanged, y: content.dotsY)
        compactView.isHidden = content.compact == nil
        compactView.frame = bounds
        compactView.update(content.compact, slots: content.compactSlots, underPeekLine: content.peeksOverEars,
                           notched: content.compactNotched)
        mark.frame = bounds
        mark.visible = content.secondaryDot
        // 换歌一瞥在原地长出来、收回去（同一层，两耳不重建）：只有那一行自己淡入；收回时它先由 fadeAlert 淡掉。
        let alertWasHidden = alertView.isHidden
        alertView.isHidden = content.alert == nil
        if placedOnce, content.alert != nil, alertWasHidden || alertView.alphaValue < 1 {
            if alertWasHidden { alertView.alphaValue = 0 }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.Fade.fadeIn()
                alertView.animator().alphaValue = 1
            }
        }
        // 真刘海屏的提醒分四块（besideNotch）：刘海两侧那一条也归它排，视图盖住整块岛；其余只占刘海下面。
        alertView.frame = NSRect(x: 0, y: 0, width: rect.width,
                                 height: content.alert?.besideNotch != nil ? rect.height : max(0, rect.height - content.notchHeight))
        alertView.update(content.alert)
        activityView.isHidden = content.activities.isEmpty || !content.activitiesExpanded
        let activityHeight: CGFloat = content.activitiesExpanded ? 142 : 30
        activityView.frame = NSRect(x: 0, y: max(0, rect.height - content.notchHeight - activityHeight), width: rect.width, height: activityHeight)
        activityView.update(content.activities, selected: content.activitySelection, expanded: content.activitiesExpanded)
        // 外框圆角 28、四周边距 14；格子之间 8。窗口在左，竖线，正在进行的在右（M11）。
        // 打字筛选时（LA-7）只排留着的格子；离开的淡出，剩下的并拢（第一次排版直接到位，不动画）。
        let top = rect.height - content.notchHeight
        let shownIDs = content.shownIDs
        func isShown(_ index: Int) -> Bool {
            guard let shownIDs, index < content.tiles.count else { return true }
            return shownIDs.contains(content.tiles[index].id)
        }
        let shownCount = (0..<tileViews.count).filter(isShown).count
        let ongoingCount = (0..<tileViews.count).filter { isShown($0) && $0 < content.tiles.count && content.tiles[$0].kind.isOngoing }.count
        let awayShown = (0..<tileViews.count).filter { isShown($0) && $0 < content.tiles.count && content.tiles[$0].kind.isAway }
        let layout = NotchRow.layout(windows: shownCount - ongoingCount - awayShown.count, ongoing: ongoingCount,
                                     away: awayShown.count, awayNarrow: awayShown.last.map { content.tiles[$0].away?.isNarrow == true } ?? false)
        // 那一排固定高：格子 124 × 104（稿）。活动卡叠在窗口上面的旧样子（activitiesExpanded）仍按剩下的高度算。
        let cellsHeight = content.activitiesExpanded
            ? max(0, top - 22 - 142)
            : max(0, min(IslandMetrics.rowCellHeight, top - 22))
        // 滚动视口：岛的四周留 14 边距，格子放不下就左右滚；放得下居中。
        let viewportWidth = max(0, rect.width - 2 * CGFloat(NotchRow.edgeMargin))
        let contentWidth = layout.contentWidth
        let origin = CGFloat(NotchRow.contentOrigin(contentWidth: contentWidth, viewport: Double(viewportWidth)))
        rowViewport.frame = NSRect(x: CGFloat(NotchRow.edgeMargin), y: 14, width: viewportWidth, height: cellsHeight)
        rowViewport.isHidden = shownCount == 0
        rowFade.frame = rowViewport.bounds
        rowLayout = layout
        rowContentWidth = contentWidth
        rowViewportWidth = Double(viewportWidth)
        rowOffset = NotchRow.clampedOffset(rowOffset, contentWidth: contentWidth, viewport: rowViewportWidth)
        rowDocument.frame = NSRect(x: CGFloat(-rowOffset), y: 0, width: max(viewportWidth, CGFloat(contentWidth)), height: cellsHeight)
        updateRowFade()
        let filterChanged = placedOnce && placedShownIDs != shownIDs
        let animateSettle = filterChanged && !Motion.reduced
        var rank = 0
        var ranks: [CGWindowID: Int] = [:]
        for (index, tile) in tileViews.enumerated() {
            if index < content.tiles.count, content.tiles[index].kind.isOngoing { tile.updateOngoing(content.tiles[index]) }
            guard isShown(index) else {
                if tile.isHidden { continue }
                if filterChanged {
                    NSAnimationContext.runAnimationGroup({ context in
                        context.duration = animateSettle ? Motion.fadeDuration : 0
                        tile.animator().alphaValue = 0
                    }, completionHandler: { [weak tile] in
                        MainActor.assumeIsolated { tile?.isHidden = true }
                    })
                } else {
                    tile.isHidden = true
                }
                continue
            }
            let frame = NSRect(x: origin + CGFloat(layout.x(ofCell: rank)), y: 0,
                               width: CGFloat(layout.width(ofCell: rank)), height: cellsHeight)
            ranks[tile.tileID] = rank
            let wasHidden = tile.isHidden
            if wasHidden {
                tile.frame = frame
                tile.isHidden = false
                tile.alphaValue = 0
            }
            tile.setPosition(rank + 1, of: shownCount)
            if placedOnce, !wasHidden, !Motion.reduced, tile.frame.minX != frame.minX {
                // 补位：真弹簧（令牌 calm），旁边的格子挪走时接上它此刻的位置和速度，半路改主意也不跳。
                let before = RowSpringMotion.presentedX(tile)
                tile.frame = frame
                if let layer = tile.layer {
                    RowSpringMotion.slide(layer, key: "row.settle", presentedX: before, modelX: RowSpringMotion.modelX(tile), token: .calm)
                }
                if tile.alphaValue < 1 {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = Motion.fadeDuration
                        tile.animator().alphaValue = 1
                    }
                }
            } else {
                tile.frame = frame
                if tile.alphaValue < 1, placedOnce {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = animateSettle ? Motion.fadeDuration : 0
                        tile.animator().alphaValue = 1
                    }
                }
            }
            rank += 1
        }
        rowRank = ranks
        placedShownIDs = shownIDs
        placedOnce = true
        for (index, line) in [divider, divider2].enumerated() {
            if index < layout.dividerXs.count {
                line.frame = NSRect(x: origin + CGFloat(layout.dividerXs[index]), y: CGFloat(NotchRow.dividerInset), width: CGFloat(NotchRow.dividerWidth),
                                    height: max(0, cellsHeight - 2 * CGFloat(NotchRow.dividerInset)))
                line.isHidden = false
            } else {
                line.isHidden = true
            }
        }
        placeAwayHeading(content, rect: rect, tileIndexes: awayShown)
        placeQuery(content, rect: rect, cellsMinY: 14, cellsHeight: cellsHeight, shownCount: shownCount)
        hint.stringValue = content.hint ?? ""
        hint.isHidden = content.hint == nil
        let size = hint.intrinsicContentSize
        if let island = content.fileDrop, content.drop != .none {
            // 文件那一种：三格加两耳，整块由 FileDropIslandView 画（FS-03）。
            fileIsland.isHidden = false
            fileIsland.frame = bounds
            fileIsland.update(island)
            glyph.isHidden = true
            choiceViews.forEach { $0.isHidden = true }
            hint.isHidden = true
        } else if content.drop != .none {
            fileIsland.isHidden = true
            // 落点：五个去处一排在上、一行字在下，一起居中在刘海下面那一块里。指着的那一格亮、放大一点。
            let side: CGFloat = 26, gap: CGFloat = 6
            let block = side + gap + size.height
            let bottom = max(6, (top - block) / 2)
            hint.frame = NSRect(x: (rect.width - size.width) / 2, y: bottom, width: size.width, height: size.height)
            let slot = rect.width / CGFloat(choiceViews.count)
            let showRow = !content.stripLanding && (content.drop == .offered || content.drop == .armed)
            for (index, view) in choiceViews.enumerated() {
                let chosen = content.drop == .armed && index == content.dropChoice.rawValue
                let edge = chosen ? side + 4 : side - 2
                view.frame = NSRect(x: slot * CGFloat(index) + (slot - edge) / 2,
                                    y: bottom + size.height + gap - (chosen ? 2 : -1), width: edge, height: edge)
                view.alphaValue = content.dropDisabled.contains(index) ? NotchSmallBehaviour.disabledAlpha
                    : chosen ? 1 : (content.drop == .armed ? 0.38 : 0.6)
                view.isHidden = !showRow
            }
            glyph.frame = NSRect(x: slot * CGFloat(content.dropChoice.rawValue) + (slot - side) / 2,
                                 y: bottom + size.height + gap, width: side, height: side)
            glyph.isHidden = showRow
            if content.drop != glyphState {
                let name = content.drop == .confirmed ? "checkmark.circle.fill" : "tray.and.arrow.down.fill"
                let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 22, weight: .semibold))
                if let symbol {
                    if glyphState == .none || Motion.reduced { glyph.image = symbol }
                    else { glyph.setSymbolImage(symbol, contentTransition: .replace) }
                }
                glyph.alphaValue = content.drop == .offered ? 0.6 : 1
                glyphState = content.drop
            }
        } else {
            fileIsland.isHidden = true
            glyph.isHidden = true
            choiceViews.forEach { $0.isHidden = true }
            hint.frame = NSRect(x: (rect.width - size.width) / 2, y: max(8, (top - size.height) / 2),
                                width: size.width, height: size.height)
        }
        // 往下拉出来的那一截：图标在正中，拉得越多越大、越清楚。
        if content.pullIcon != nil, content.pullExtra > 4 {
            let side = 18 + 10 * min(1, content.pullProgress)
            let icon = NSRect(x: rect.width / 2 - side / 2, y: max(2, content.pullExtra / 2 - side / 2), width: side, height: side)
            pullView.frame = icon
            pullView.alphaValue = min(1, content.pullProgress * 1.4)
            pullView.isHidden = false
            pullIconRect = icon
        } else {
            pullView.isHidden = true
            pullIconRect = nil
        }
    }
}

extension NotchContentView {
    /// 离开期间的小标题：写在刘海左边（右对齐、紧挨刘海）；没有刘海的屏、正在打字筛选、没有这一段时不画。
    fileprivate func placeAwayHeading(_ content: NotchCanvasView.Content, rect: NSRect, tileIndexes: [Int]) {
        let visible = !tileIndexes.isEmpty && content.query.isEmpty && content.notchHeight > 0
        awayHeading.isHidden = !visible
        guard visible else { return }
        let cells = tileIndexes.map { content.tiles[$0].away }
        let total = cells.reduce(0) { $0 + ($1?.isNarrow == true ? ($1?.omitted ?? 0) : 1) }
        awayHeading.stringValue = AwaySummary.heading
        awayHeading.setAccessibilityLabel(WSL10n.text("away.group", zh: "离开期间，%@ 件", String(total)))
        let right = (rect.width - content.notchWidth) / 2 - 8
        let room = max(0, right - CGFloat(NotchRow.edgeMargin))
        let width = min(room, ceil((AwaySummary.heading as NSString).size(withAttributes: [.font: awayHeading.font as Any]).width) + 2)
        let height: CGFloat = 16
        awayHeading.frame = NSRect(x: right - width, y: rect.height - content.notchHeight / 2 - height / 2, width: width, height: height)
    }

    /// 打字筛选（LA-7）：字写在刘海左边那一段（右对齐、紧挨刘海，13 半粗，后面一个光标）；一格也没有时在格子那一块写“没有匹配的”。
    /// 左边放不下整串就留最后几个字。不用计时器：光标不闪，免得空闲时还在重画。
    fileprivate func placeQuery(_ content: NotchCanvasView.Content, rect: NSRect, cellsMinY: CGFloat, cellsHeight: CGFloat,
                                shownCount: Int) {
        let query = content.query
        let showsQuery = !query.isEmpty && content.notchHeight > 0
        queryLabel.isHidden = !showsQuery
        queryCursor.isHidden = !showsQuery
        compactView.alphaValue = showsQuery ? 0 : 1
        if showsQuery {
            let notchLeft = (rect.width - content.notchWidth) / 2
            let right = notchLeft - 8
            let room = max(0, right - CGFloat(NotchRow.edgeMargin) - 3)
            var text = query
            var width = (text as NSString).size(withAttributes: [.font: queryLabel.font as Any]).width
            var limit = query.count
            while width > room, limit > 2 {
                limit -= 1
                text = NotchRowFilter.visibleTail(of: query, limit: limit)
                width = (text as NSString).size(withAttributes: [.font: queryLabel.font as Any]).width
            }
            queryLabel.stringValue = text
            queryLabel.setAccessibilityLabel(WSL10n.text("notch.filter.label", zh: "筛选：%@", query))
            let height: CGFloat = 16
            let y = rect.height - content.notchHeight / 2 - height / 2
            queryCursor.frame = NSRect(x: right - 1.5, y: y + 1, width: 1.5, height: height - 2)
            queryLabel.frame = NSRect(x: max(CGFloat(NotchRow.edgeMargin), right - 3.5 - ceil(width) - 2), y: y,
                                      width: min(room, ceil(width) + 2), height: height)
        }
        let empty = shownCount == 0 && content.shownIDs != nil
        noMatchLabel.isHidden = !empty
        if empty {
            let size = noMatchLabel.intrinsicContentSize
            noMatchLabel.frame = NSRect(x: (rect.width - size.width) / 2, y: cellsMinY + (cellsHeight - size.height) / 2,
                                        width: size.width, height: size.height)
        }
    }
}

