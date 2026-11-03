// // 紧凑与最小样式的几个小视图：下巴点、紧凑段、最小形胶囊、被挡提醒的点、信息点的位置与语气色。

import Cocoa
import ApplicationServices

/// 下巴上的点：一个点一扇收进刘海的窗；有变化的另加一个强调色的点。
final class NotchDotsView: NSView {
    private var count = 0
    private var changed = false
    private var y: CGFloat = 2.5

    func update(count: Int, changed: Bool, y: CGFloat) {
        guard count != self.count || changed != self.changed || y != self.y else { return }
        self.count = count
        self.changed = changed
        self.y = y
        needsDisplay = true
    }

    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let white = min(count, 5)
        let total = white + (changed ? 1 : 0)
        guard total > 0 else { return }
        let spacing: CGFloat = 7
        let startX = bounds.width / 2 - CGFloat(total - 1) * spacing / 2
        for i in 0..<total {
            (i < white ? NSColor.white.withAlphaComponent(0.88) : NSColor.controlAccentColor).setFill()
            NSBezierPath(ovalIn: NSRect(x: startX + CGFloat(i) * spacing - 2, y: y, width: 4, height: 4)).fill()
        }
    }
}

/// 紧凑样式：左边一段放 App 图标，右边一段放个数（有变化时旁边一个强调色的点）。
final class NotchCompactView: NSView {
    private var compact: NotchPanel.Compact?
    private var slots: (leading: NSRect, trailing: NSRect)?
    /// 编程会话在跑：右耳的转圈。Core Animation 自己转，不起计时器；不在跑就拿掉。
    private let spinner = NotchSessionSpinner.makeLayer()
    /// 实时活动的量（M12）：右耳的环或不确定弧。数变了只改 strokeEnd，画法变了才重排。
    private let part = NotchProgressPartLayers()
    /// 环或弧此刻画在右耳上（放得下才画）。
    private var partShown = false
    /// 右耳上实际写的字：放不下“第 3 / 12”时换成短写法。
    private var earText: String?

    // MARK: 文件架个数（右耳）：图层自己滚、自己弹，不重画。
    private let shelfText = CATextLayer()
    private var shelfShownText: String?

    // MARK: 音量亮度两耳（左耳符号、右耳白条）。图层自己动，不重画。
    private let levelSymbol = CALayer()
    private let levelTrack = CALayer()
    private let levelFill = CALayer()
    private let levelCap = CALayer()
    private var shownLevel: NotchPanel.LevelEar?
    private var shownSymbolName: String?

    // MARK: 正在播放两耳（NP-2）：左耳封面、右耳 5 个静止取色点。图层各自带色，不重画；不画任何会动的波形。
    private let coverHost = CALayer()
    private let coverImage = CALayer()
    private let coverPlaceholder = CALayer()
    private let coverNote = CALayer()
    private let dotLayers: [CALayer] = (0..<NowPlayingEars.dotCount).map { _ in CALayer() }
    private var musicShown = false
    private var shownCoverKey: String?
    private var shownNoteSide: Double?
    /// 右耳 5 根（NP-6）：今天的静止点，或跟着声音跳 / 减少动态效果时的填充色点。暂停一律按暂停画。
    private var wave = NowPlayingWave.dots

    func setMusicWave(_ next: NowPlayingWave) {
        guard next != wave else { return }
        let modeChanged = next.mode != wave.mode
        wave = next
        guard musicShown, let (_, music) = coverEars, let slots else { return }
        CATransaction.begin()
        // 换样子（静止点 ↔ 跟着跳）沿 0.18 秒淡过去；每秒 30 次的高度直接到位，起落已经在电平里了。
        if modeChanged && !Motion.reduced { CATransaction.setAnimationDuration(NowPlayingEars.fadeSeconds) }
        else { CATransaction.setDisableActions(true) }
        layoutDots(music: music, trailing: Self.slot(slots.trailing))
        CATransaction.commit()
    }

    private static func slot(_ rect: NSRect) -> NowPlayingEars.Slot {
        NowPlayingEars.Slot(minX: Double(rect.minX), minY: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }

    /// 5 个点的位置、大小、颜色。跟着跳：根高 = 2.4 + 11.6 × 电平，竖直居中，全部主色；
    /// 减少动态效果：静止的填充色点；其余（没开、没权限、录不到、蓝牙 + Spotify）：主色副色交替的静止点；暂停：白 0.45。
    private func layoutDots(music: NotchPanel.MusicEar, trailing: NowPlayingEars.Slot) {
        let mode: NowPlayingWaveMode = music.paused ? .paused : (wave.mode == .paused ? .dots : wave.mode)
        let base = NowPlayingEars.dotColors(palette: music.artwork?.palette, paused: music.paused)
        let filled = mode == .live || mode == .still
        for (index, dot) in dotLayers.enumerated() {
            var box = NowPlayingEars.dotFrame(index: index, in: trailing)
            if mode == .live, index < wave.levels.count {
                let height = AudioLevelBands.rootHeight(level: wave.levels[index])
                box.y += (box.height - height) / 2
                box.height = height
            }
            dot.isHidden = false
            dot.bounds = CGRect(x: 0, y: 0, width: box.width, height: box.height)
            dot.position = CGPoint(x: box.x, y: box.y)
            dot.cornerRadius = CGFloat(min(box.width, box.height) / 2)
            let color = filled ? base[0] : base[index]
            dot.backgroundColor = NSColor(srgbRed: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b),
                                          alpha: CGFloat(color.alpha)).cgColor
        }
    }


    /// 计时器的橙色（稿 #ff9f0a）；超时的右耳字用它。
    private static let timerOrange = NSColor(srgbRed: CountdownTimerStyle.orangeRGB.0, green: CountdownTimerStyle.orangeRGB.1,
                                             blue: CountdownTimerStyle.orangeRGB.2, alpha: 1)
    private static func earFont() -> NSFont {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        return font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
    }
    static func textWidth(_ text: String) -> CGFloat {
        text.isEmpty ? 0 : ceil(NSAttributedString(string: text, attributes: [.font: earFont()]).size().width)
    }

    /// 右耳放得下什么：环（或弧）加字都放得下才画图形，放不下就退回原来的样子（音乐、拷贝的比例回到细条，不确定弧不画）；
    /// 只写个数的，放不下“第 3 / 12”就写“3/12”。
    private func resolveEar() {
        partShown = false
        earText = compact?.trailing
        guard coverEars == nil else { return }
        guard let compact, compact.leading != nil, compact.sessionPhase == nil, let slots else { return }
        let room = slots.trailing.width - CGFloat(NotchProgressPart.edgeInset) - 4
        let text = compact.trailing ?? ""
        switch compact.quantity.drawing {
        case .ring, .spinningArc:
            let need = Self.textWidth(text) + CGFloat(NotchProgressPart.reservedWidth(for: .ring))
            partShown = (text.isEmpty ? CGFloat(NotchProgressPart.ringDiameter) : need) <= room
        case .countText:
            if let full = compact.quantity.countText, text == full, Self.textWidth(text) > room,
               let short = compact.quantity.shortCountText { earText = short }
        case .none: break
        }
    }

    /// 环或弧：位置贴着右耳的右边缘、竖直居中。
    private func syncPart() {
        let quantity = partShown ? (compact?.quantity ?? .unknown) : .unknown
        if quantity.drawing != .none {
            wantsLayer = true
            if part.root.superlayer == nil { layer?.addSublayer(part.root) }
        }
        if let slots {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            part.root.position = CGPoint(x: slots.trailing.maxX - CGFloat(NotchProgressPart.edgeInset) - NotchProgressPartLayers.side / 2,
                                         y: slots.trailing.midY)
            CATransaction.commit()
        }
        part.apply(quantity, tone: compact?.progressTone ?? .playback)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        part.setAttached(window != nil)
    }

    func update(_ compact: NotchPanel.Compact?, slots: (leading: NSRect, trailing: NSRect)?) {
        self.compact = compact
        self.slots = slots
        resolveEar()
        needsDisplay = true
        syncPart()
        updateSpinner()
        syncLevel()
        syncMusic()
        syncShelfCount()
        setAccessibilityElement(compact != nil && compact?.level == nil)
        setAccessibilityRole(.staticText)
        // 过期：两耳降到 0.5；增强对比度时也靠右耳的“—”认，不只靠暗。
        alphaValue = compact?.stale == true ? CGFloat(NotchActivity.staleAlpha) : 1
        defer {
            if compact?.stale == true { setAccessibilityLabel(NotchEarText.spoken(accessibilityLabel() ?? "", stale: true)) }
        }
        if let compact {
            if let flash = compact.flash {
                setAccessibilityLabel(flash.spoken)
            } else if let music = compact.music {
                setAccessibilityLabel(music.spoken)
            } else if let spoken = compact.shelfSpoken {
                setAccessibilityLabel(spoken)
            } else if let spoken = compact.calendar?.spoken, !spoken.isEmpty {
                setAccessibilityLabel(spoken)
            } else if let leading = compact.leading {
                let joinText = WSL10n.text("notch.join", zh: "，")
                switch compact.sessionPhase {
                case .waiting?:
                    setAccessibilityLabel(compact.sessionSpoken ?? leading + joinText + WSL10n.text("notch.row.waiting", zh: "在等你"))
                case .running?:
                    setAccessibilityLabel(leading + joinText + WSL10n.text("notch.row.running", zh: "在跑"))
                case .quota?:
                    let running = WSL10n.text("notch.row.running", zh: "在跑")
                    let withEar = compact.trailing.flatMap {
                        $0.isEmpty ? nil : WSL10n.text("notch.row.runningWithEar", zh: "在跑，%@", $0)
                    }
                    setAccessibilityLabel(leading + joinText + (withEar ?? running))
                case .quotaLow?:
                    setAccessibilityLabel(leading + joinText
                        + WSL10n.text("notch.row.runningQuotaLow", zh: "在跑，额度快用完了"))
                case .done?: setAccessibilityLabel(leading)
                case nil:
                    let tail = compact.trailing.flatMap { $0.isEmpty ? nil : $0 }
                    setAccessibilityLabel(tail.map { "\(leading)，\($0)" } ?? leading)
                }
            } else {
                setAccessibilityLabel(compact.count > 0
                    ? WSL10n.text("notch.folded.count", zh: "刘海里收着 %@ 扇窗口", String(compact.count))
                    : WSL10n.text("notch.folded.changed", zh: "收起的窗口有变化"))
            }
        }
    }

    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 此刻画着的是某件活动的两耳（照系统的岛：点耳朵打开它的 App）。音乐放不下封面退回音符时也算：它还是音乐的两耳。
    /// 音量亮度条、电量那一下、窗口个数的两耳不算。
    var showsActivityEars: Bool {
        guard let compact, slots != nil, !isHidden, compact.level == nil, compact.flash == nil else { return false }
        return compact.music != nil || compact.leading != nil || compact.calendar != nil || compact.shelfSpoken != nil
    }

    /// 紧凑那一件是不是正在播放（点它的耳朵是长成大卡，不是打开 Music）。
    var compactIsMusic: Bool { compact?.music != nil }

    /// 此刻是不是画封面耳：有音乐两耳、没被音量亮度顶掉、而且封面放得下（放不下就是今天的样子）。
    private var coverEars: (side: Double, music: NotchPanel.MusicEar)? {
        guard slots != nil, compact?.level == nil, let music = compact?.music, let side = music.coverSide else { return nil }
        return (side, music)
    }

    private func prepareMusicLayers() {
        wantsLayer = true
        guard let host = layer, coverHost.superlayer == nil else { return }
        // 位置、大小、圆角、图片都直接到位；只有颜色和透明度沿 0.18 秒淡过去（见 syncMusic）。
        let still: [String: CAAction] = ["bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull(),
                                         "contents": NSNull(), "hidden": NSNull()]
        coverHost.actions = still
        coverHost.anchorPoint = .zero
        coverHost.masksToBounds = true
        coverHost.cornerCurve = .continuous
        for sub in [coverImage, coverPlaceholder, coverNote] {
            sub.actions = still
            sub.anchorPoint = .zero
            coverHost.addSublayer(sub)
        }
        coverImage.contentsGravity = .resizeAspectFill
        coverImage.magnificationFilter = .linear
        coverImage.minificationFilter = .trilinear
        coverPlaceholder.backgroundColor = NSColor(white: CGFloat(NowPlayingEars.placeholderFillWhite), alpha: 1).cgColor
        host.addSublayer(coverHost)
        for dot in dotLayers {
            dot.actions = still
            dot.anchorPoint = .zero
            host.addSublayer(dot)
        }
    }

    private func hideMusicLayers() {
        guard musicShown else { return }
        coverHost.isHidden = true
        for dot in dotLayers { dot.isHidden = true }
        coverImage.contents = nil
        shownCoverKey = nil
        musicShown = false
    }

    private func noteImage(side: Double, scale: CGFloat) -> (CGImage, CGSize)? {
        let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(side * 0.5), weight: .semibold)
            .applying(.init(paletteColors: [NSColor(white: CGFloat(NowPlayingEars.placeholderNoteWhite), alpha: 1)]))
        guard let image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return (cgImage, image.size)
    }

    /// 左耳封面（没封面画占位：白 0.14 的圆角方块加白 0.6 的音符）、右耳 5 个静止点（主色副色交替）。
    /// 暂停：封面透明度 0.5、点变白 0.45，沿 0.18 秒淡过去；减少动态效果直接换。
    private func syncMusic() {
        guard let (side, music) = coverEars, let slots else { hideMusicLayers(); return }
        prepareMusicLayers()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let leading = NowPlayingEars.Slot(minX: Double(slots.leading.minX), minY: Double(slots.leading.minY),
                                          width: Double(slots.leading.width), height: Double(slots.leading.height))
        let trailing = NowPlayingEars.Slot(minX: Double(slots.trailing.minX), minY: Double(slots.trailing.minY),
                                           width: Double(slots.trailing.width), height: Double(slots.trailing.height))
        let frame = NowPlayingEars.coverFrame(in: leading, side: side)
        let animated = musicShown && !Motion.reduced
        let key = music.artwork.map { "\($0.trackKey)#\($0.fingerprint)" }
        CATransaction.begin()
        if animated { CATransaction.setAnimationDuration(NowPlayingEars.fadeSeconds) } else { CATransaction.setDisableActions(true) }
        coverHost.isHidden = false
        coverHost.bounds = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
        coverHost.position = CGPoint(x: frame.x, y: frame.y)
        coverHost.cornerRadius = CGFloat(NowPlayingEars.coverCorner(side: side))
        coverHost.opacity = Float(NowPlayingEars.coverAlpha(paused: music.paused))
        for sub in [coverImage, coverPlaceholder] { sub.bounds = coverHost.bounds; sub.position = .zero }
        coverImage.contentsScale = scale
        if key != shownCoverKey {
            let image = music.artwork?.makeCGImage()
            if animated, !Motion.reduced {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = NowPlayingEars.fadeSeconds
                coverImage.add(fade, forKey: "cover.fade")
            }
            coverImage.contents = image
            coverImage.isHidden = image == nil
            coverPlaceholder.isHidden = image != nil
            coverNote.isHidden = image != nil
            shownCoverKey = key
        }
        if shownNoteSide != side {
            if let (note, size) = noteImage(side: side, scale: scale) {
                coverNote.contents = note
                coverNote.contentsScale = scale
                coverNote.bounds = CGRect(origin: .zero, size: size)
                coverNote.position = CGPoint(x: (frame.width - size.width) / 2, y: (frame.height - size.height) / 2)
                shownNoteSide = side
            }
        }
        layoutDots(music: music, trailing: trailing)
        CATransaction.commit()
        musicShown = true
    }

    /// 右耳的转圈：只在编程会话“在跑”时有。位置贴着右耳的右边缘，竖直居中。
    private func updateSpinner() {
        let running = compact?.sessionFace?.mark == .spinner && slots != nil
        if running, let slots {
            wantsLayer = true
            if spinner.superlayer == nil { layer?.addSublayer(spinner) }
            let side = NotchSessionSpinner.diameter
            spinner.position = CGPoint(x: slots.trailing.minX + IslandMetrics.sessionEarInset + side / 2, y: slots.trailing.midY)
            spinner.isHidden = false
            NotchSessionSpinner.start(spinner)
        } else {
            NotchSessionSpinner.stop(spinner)
            spinner.isHidden = true
        }
    }

    private func prepareLevelLayers() {
        wantsLayer = true
        guard let host = layer else { return }
        for sub in [levelTrack, levelFill, levelCap, levelSymbol] where sub.superlayer == nil {
            sub.anchorPoint = .zero
            sub.actions = ["bounds": NSNull(), "position": NSNull(), "cornerRadius": NSNull(), "opacity": NSNull(),
                           "contents": NSNull(), "backgroundColor": NSNull()]
            host.addSublayer(sub)
        }
    }

    private func hideLevelLayers() {
        for sub in [levelTrack, levelFill, levelCap, levelSymbol] { sub.isHidden = true; sub.removeAllAnimations() }
        shownLevel = nil
        shownSymbolName = nil
    }

    /// 把一层挪到新位置：平时沿 pop 弹过去，减少动态效果直接到位。
    private func place(_ layer: CALayer, bounds: CGRect, position: CGPoint, radius: CGFloat, animated: Bool) {
        let from = layer.presentation() ?? layer
        let moves: [(String, Any, Any)] = [
            ("bounds", NSValue(rect: from.bounds), NSValue(rect: bounds)),
            ("position", NSValue(point: from.position), NSValue(point: position)),
            ("cornerRadius", from.cornerRadius, radius),
        ]
        layer.bounds = bounds
        layer.position = position
        layer.cornerRadius = radius
        layer.removeAllAnimations()
        guard animated, !Motion.reduced else { return }
        for (key, start, end) in moves where !(start as AnyObject).isEqual(end) {
            let animation = Motion.spring(.pop, keyPath: key)
            animation.fromValue = start
            animation.toValue = end
            layer.add(animation, forKey: "level." + key)
        }
    }

    private func levelSymbolImage(_ name: String, kind: NotchPanel.LevelKind) -> (CGImage, CGSize)? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        let fallback: String
        switch kind {
        case .volume: fallback = "speaker.wave.2.fill"
        case .brightness: fallback = "sun.max.fill"
        case .keyboardLight: fallback = "light.max"
        }
        guard let image = (NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: fallback, accessibilityDescription: nil))?
            .withSymbolConfiguration(configuration) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return (cgImage, image.size)
    }

    /// 左耳符号、右耳条。同一种里数值、符号、拉长变了就原地换（条沿 pop 一格接一格扫过去）；
    /// 到头再按条拉长、符号顺着挪，回来时 pop 弹回；减少动态效果不拉长，条的那一头从白 0.6 亮到 1。
    private func syncLevel() {
        guard let level = compact?.level, let slots else {
            if shownLevel != nil { hideLevelLayers() }
            return
        }
        prepareLevelLayers()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let animated = shownLevel?.kind == level.kind
        let bar = NotchLevelEars.bar(slotMinX: Double(slots.trailing.minX), slotHeight: Double(slots.trailing.height),
                                     value: level.value, stretch: level.stretch)
        let originY = slots.trailing.minY
        let fillWidth = CGFloat(bar.fillWidth)
        let height = CGFloat(bar.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        levelTrack.backgroundColor = NSColor.white.withAlphaComponent(NotchLevelEars.trackAlpha(increasedContrast: contrast)).cgColor
        levelFill.backgroundColor = NSColor.white.withAlphaComponent(NotchLevelEars.fillAlpha).cgColor
        levelCap.backgroundColor = NSColor.white.cgColor
        levelCap.opacity = 0
        for sub in [levelTrack, levelFill, levelSymbol] { sub.isHidden = false }
        levelCap.isHidden = false
        place(levelTrack, bounds: CGRect(x: 0, y: 0, width: bar.width, height: bar.height),
              position: CGPoint(x: bar.x, y: originY + bar.y), radius: height / 2, animated: animated)
        place(levelFill, bounds: CGRect(x: 0, y: 0, width: fillWidth, height: bar.height),
              position: CGPoint(x: slots.trailing.minX + NotchLevelEars.barNotchGap, y: originY + bar.y),
              radius: min(height / 2, fillWidth / 2), animated: animated)
        levelFill.isHidden = fillWidth < 0.5
        // 符号：喇叭身子不动，声波往右长，所以按左边对齐；拉长时顺着条的方向挪 ¼。
        if level.symbol != shownSymbolName || level.kind != shownLevel?.kind,
           let (image, size) = levelSymbolImage(level.symbol, kind: level.kind) {
            levelSymbol.contents = image
            levelSymbol.contentsScale = scale
            levelSymbol.bounds = CGRect(origin: .zero, size: size)
            shownSymbolName = level.symbol
        }
        let symbolSize = levelSymbol.bounds.size
        place(levelSymbol, bounds: levelSymbol.bounds,
              position: CGPoint(x: slots.leading.minX + CGFloat(NotchLevelEars.symbolInset + NotchLevelEars.symbolOffset(stretch: level.stretch)),
                                y: slots.leading.midY - symbolSize.height / 2),
              radius: 0, animated: animated)
        levelSymbol.opacity = level.dimmed ? 0.35 : 1
        CATransaction.commit()
        // 减少动态效果：到头再按，条的那一头亮一下（上头是条尾，下头是条头的小圆点）。
        if Motion.reduced, level.edge != nil, level.edgePushes != shownLevel?.edgePushes {
            if level.edge == .upper, fillWidth >= 0.5 {
                flash(levelFill)
            } else {
                levelCap.bounds = CGRect(x: 0, y: 0, width: height, height: height)
                levelCap.cornerRadius = height / 2
                levelCap.position = CGPoint(x: level.edge == .upper ? CGFloat(bar.maxX) - height : CGFloat(bar.x),
                                            y: originY + bar.y)
                flash(levelCap)
            }
        }
        shownLevel = level
    }

    private func flash(_ layer: CALayer) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = NotchLevelEars.reducedFlashFrom
        animation.toValue = 1.0
        animation.duration = NotchLevelEars.reducedFlashSeconds
        layer.opacity = layer === levelCap ? 0 : 1
        layer.add(animation, forKey: "level.flash")
    }

    /// 做完：右耳一个绿色对勾。
    private func drawDoneMark(in slot: NSRect) {
        let side: CGFloat = 14
        let configuration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            .applying(.init(paletteColors: [.systemGreen]))
        NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)?
            .draw(in: NSRect(x: slot.maxX - side - 6, y: slot.midY - side / 2, width: side, height: side))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let compact, let slots else { return }
        if compact.level != nil { return }
        if let flash = compact.flash {
            let tint = Self.flashColor(flash.tone)
            drawEar("", symbol: flash.symbol, ring: nil, in: slots.leading, align: .left, tint: tint)
            let percentage = Self.flashPercentageLayout(flash, in: slots.trailing, color: tint)
            percentage.text.draw(at: percentage.frame.origin)
            return
        }
        if coverEars != nil {
            // 封面耳：封面和点在图层上；有收起的窗口时，信息点照旧画。
            if compact.count > 0 {
                compact.dotTone.color.setFill()
                NSBezierPath(ovalIn: NotchInfoDot.rect(in: bounds)).fill()
            }
            return
        }
        if let leading = compact.leading {
            let ring = compact.progressStyle == .ring ? (compact.progress ?? 0, compact.progressTone) : nil
            let timerEar = compact.progressTone == .timer || compact.progressTone == .timerPaused
                || compact.progressTone == .calendar || compact.progressTone == .calendarJoin || compact.shelfSpoken != nil
            drawEar(timerEar ? "" : leading, symbol: compact.leadingSymbol, ring: ring, in: slots.leading, align: .left)
            if compact.progressTone == .calendarJoin {
                // 开始后能加入：左耳满环，右耳一枚绿色摄像机，不写字。
                drawEar("", symbol: "video.fill", ring: nil, in: slots.trailing, align: .right, tint: .systemGreen)
                if compact.count > 0 {
                    compact.dotTone.color.setFill()
                    NSBezierPath(ovalIn: NotchInfoDot.rect(in: bounds)).fill()
                }
                return
            }
            // 编程会话（在跑、等你、好几个）：左耳只留符号，右耳画转圈或点加字。做完仍走下面的对勾。
            if let face = compact.sessionFace, face.mark != .check {
                drawEar("", symbol: compact.leadingSymbol, ring: nil, in: slots.leading, align: .left)
                drawSessionFace(face, in: slots.trailing)
                if compact.count > 0 {
                    compact.dotTone.color.setFill()
                    NSBezierPath(ovalIn: NotchInfoDot.rect(in: bounds)).fill()
                }
                return
            }
            // 编程会话：在跑是转圈（子图层）、等你是橙色的字、做完是对勾。
            // 活动的量：环（或弧）是子图层，字让出它的位置。
            drawEar(compact.shelfSpoken != nil ? "" : (earText ?? ""), symbol: nil, ring: nil, in: slots.trailing, align: .right,
                    color: (compact.sessionPhase == .waiting || compact.sessionPhase == .quotaLow) ? .systemOrange
                        : (compact.progressTone == .timerPaused ? NSColor.white.withAlphaComponent(0.92 * CGFloat(CountdownTimerStyle.pausedAlpha))
                           : (compact.progressTone == .timer && (earText ?? "").hasPrefix("+") ? Self.timerOrange : nil)),
                    trailingInset: partShown ? CGFloat(NotchProgressPart.reservedWidth(for: compact.quantity.drawing)) : 0)
            if compact.sessionPhase == .done { drawDoneMark(in: slots.trailing) }
            if let progress = barFraction {
                drawProgress(progress, in: slots.trailing)
            }
            if compact.count > 0 {
                compact.dotTone.color.setFill()
                NSBezierPath(ovalIn: NotchInfoDot.rect(in: bounds)).fill()
            }
            return
        }
        let side = min(20, slots.leading.height - 8)
        if let icon = compact.icon {
            icon.draw(in: NSRect(x: slots.leading.midX - side / 2, y: slots.leading.midY - side / 2, width: side, height: side))
        }
        let dot: CGFloat = compact.changed ? 6 : 0
        var number = NSAttributedString()
        if compact.count > 0 {
            // 个数用等宽数字（§4.10）：1 和 11 一样宽，数字不会跳。
            let font = NSFont.monospacedDigitSystemFont(ofSize: min(13, slots.trailing.height - 10), weight: .semibold)
            let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: font.pointSize) } ?? font
            number = NSAttributedString(string: "\(compact.count)", attributes: [
                .font: rounded, .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            ])
        }
        let size = number.size()
        let gap: CGFloat = size.width > 0 && dot > 0 ? 4 : 0
        let width = size.width + gap + dot
        let startX = slots.trailing.midX - width / 2
        number.draw(at: NSPoint(x: startX, y: slots.trailing.midY - size.height / 2))
        if dot > 0 {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: startX + size.width + gap, y: slots.trailing.midY - dot / 2, width: dot, height: dot)).fill()
        }
    }

    /// 文件架个数：右耳一个文字图层。变了滚到新值（0.28 秒），变多时右耳再弹一下（pop 0.30 / 0.75）；减少动态效果直接换。
    private func syncShelfCount() {
        guard let compact, compact.shelfSpoken != nil, compact.level == nil, let slots, let text = compact.trailing else {
            shelfText.isHidden = true
            shelfShownText = nil
            return
        }
        wantsLayer = true
        guard let host = layer else { return }
        let font = Self.earFont()
        let height = ceil(font.ascender - font.descender + font.leading)
        let width = max(0, slots.trailing.width - 12)
        let frame = CGRect(x: slots.trailing.maxX - 6 - width, y: slots.trailing.midY - height / 2, width: width, height: height)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        func style(_ layer: CATextLayer, _ string: String) {
            layer.font = font
            layer.fontSize = font.pointSize
            layer.alignmentMode = .right
            layer.foregroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
            layer.contentsScale = scale
            layer.frame = frame
            layer.string = string
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if shelfText.superlayer == nil { host.addSublayer(shelfText) }
        shelfText.isHidden = false
        let old = shelfShownText
        style(shelfText, text)
        CATransaction.commit()
        shelfShownText = text
        guard let old, old != text, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let roll = NotchShelfEars.roll(from: Int(old), to: Int(text) ?? 0)
        if roll != .none {
            // 变多：旧值往上顶出去、新值从下面上来；变少反过来。
            let travel: CGFloat = roll == .up ? 10 : -10
            let outgoing = CATextLayer()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            style(outgoing, old)
            host.addSublayer(outgoing)
            CATransaction.commit()
            func slide(from: CGFloat, to: CGFloat, fadeFrom: Float, fadeTo: Float) -> CAAnimationGroup {
                let move = CABasicAnimation(keyPath: "transform.translation.y")
                move.fromValue = from; move.toValue = to
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = fadeFrom; fade.toValue = fadeTo
                let group = CAAnimationGroup()
                group.animations = [move, fade]
                group.duration = NotchShelfEars.rollDuration
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                return group
            }
            CATransaction.begin()
            CATransaction.setCompletionBlock { outgoing.removeFromSuperlayer() }
            outgoing.add(slide(from: 0, to: travel, fadeFrom: 1, fadeTo: 0), forKey: "roll")
            outgoing.opacity = 0
            CATransaction.commit()
            shelfText.add(slide(from: -travel, to: 0, fadeFrom: 0, fadeTo: 1), forKey: "roll")
        }
        if NotchShelfEars.pops(from: Int(old), to: Int(text) ?? 0) {
            let stiffness = pow(2 * Double.pi / NotchShelfEars.popResponse, 2)
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.fromValue = 1.28; spring.toValue = 1
            spring.mass = 1
            spring.stiffness = stiffness
            spring.damping = 2 * NotchShelfEars.popDamping * stiffness.squareRoot()
            spring.duration = spring.settlingDuration
            shelfText.add(spring, forKey: "pop")
        }
    }

    /// 右耳下面那条细条的比例：音量、亮度一直是它；活动的比例放不下环加字时退回到它（和原来一样）。
    private var barFraction: Double? {
        if coverEars != nil { return nil }
        if let progress = compact?.progress, compact?.progressStyle == .bar { return progress }
        if compact?.leading != nil, !partShown, compact?.quantity.drawing == .ring { return compact?.quantity.fractionValue }
        return nil
    }

    /// 电量那一下的颜色：高于 20% 绿、20% 及以下红、低电量模式黄（系统色，随浅深色与对比度）。
    static func flashColor(_ tone: PowerFlashTone) -> NSColor {
        switch tone {
        case .green: return .systemGreen
        case .red: return .systemRed
        case .yellow: return .systemYellow
        }
    }

    /// 0…100% is one compact value. Keep every digit and the percent sign within the 34pt ear.
    static func flashPercentageLayout(_ flash: PowerFlash, in slot: NSRect, color: NSColor) -> (text: NSAttributedString, frame: NSRect) {
        let base = earFont()
        let font = NSFont(descriptor: base.fontDescriptor, size: 10)
            ?? NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let text = NSAttributedString(string: flash.trailing, attributes: [.font: font, .foregroundColor: color])
        let size = text.size()
        return (text, NSRect(x: slot.maxX - 2 - size.width, y: slot.midY - size.height / 2,
                             width: size.width, height: size.height))
    }

    private func drawEar(_ text: String, symbol: String?, ring: (progress: Double, tone: NotchPanel.Compact.ProgressTone)?,
                         in slot: NSRect, align: NSTextAlignment, color: NSColor? = nil, trailingInset: CGFloat = 0,
                         tint: NSColor? = nil) {
        guard !text.isEmpty || symbol != nil || ring != nil else { return }
        var x = slot.minX + 6
        let side: CGFloat = 14
        if let ring {
            let box = CGFloat(NotchFocusRing.viewport)
            drawRing(ring.progress, tone: ring.tone, in: NSRect(x: x, y: slot.midY - box / 2, width: box, height: box))
            x += box + 4
        } else if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(tint.map { .init(pointSize: 12, weight: .semibold).applying(.init(paletteColors: [$0])) }
                                     ?? .init(pointSize: 12, weight: .semibold)) {
            image.draw(in: NSRect(x: align == .right ? slot.maxX - side - 6 : x, y: slot.midY - side / 2, width: side, height: side))
            if align != .right { x += side + 4 }
        }
        let rounded = Self.earFont()
        let string = NSAttributedString(string: text, attributes: [
            .font: rounded, .foregroundColor: color ?? NSColor.white.withAlphaComponent(0.92),
        ])
        let size = string.size()
        let maxWidth = max(0, slot.width - (x - slot.minX) - 6 - trailingInset)
        let drawX = align == .right ? slot.maxX - min(size.width, maxWidth) - 6 - trailingInset : x
        let hasBar = barFraction != nil
        let textY = slot.midY - size.height / 2 + (hasBar ? 2 : 0)
        string.draw(with: NSRect(x: drawX, y: textY, width: min(size.width, maxWidth), height: size.height),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    /// 会话右耳：转圈（子图层）或状态点在左，字跟在后面；好几个时个数在前、点在后。
    private func drawSessionFace(_ face: NotchSessionEar.Face, in slot: NSRect) {
        let inset = IslandMetrics.sessionEarInset, gap = IslandMetrics.sessionEarGap
        let dotSide = IslandMetrics.sessionDotDiameter
        func dot(at x: CGFloat, _ color: NSColor) {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: slot.midY - dotSide / 2, width: dotSide, height: dotSide)).fill()
        }
        func text(_ string: String, at x: CGFloat, width: CGFloat, color: NSColor) {
            let attributed = NSAttributedString(string: string, attributes: [.font: Self.earFont(), .foregroundColor: color])
            let size = attributed.size()
            attributed.draw(with: NSRect(x: x, y: slot.midY - size.height / 2, width: width, height: size.height),
                            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
        var x = slot.minX + inset
        if face.isCount {
            text(face.text, at: x, width: face.textWidth, color: NSColor.white.withAlphaComponent(0.92))
            x += face.textWidth + gap
            switch face.mark {
            case .amberDot?: dot(at: x, .systemOrange)
            case .quietDot?: dot(at: x, NSColor.white.withAlphaComponent(0.55))
            default: break
            }
            return
        }
        switch face.mark {
        case .spinner?: x += IslandMetrics.sessionSpinnerDiameter + gap
        case .amberDot?: dot(at: x, .systemOrange); x += dotSide + gap
        default: break
        }
        guard !face.text.isEmpty else { return }
        let color = face.mark == .amberDot ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.92)
        text(face.text, at: x, width: min(face.textWidth, max(0, slot.maxX - inset - x)), color: color)
    }

    private func drawProgress(_ progress: Double, in slot: NSRect) {
        let width = min(32, max(18, slot.width - 12))
        let bar = NSRect(x: slot.maxX - 6 - width, y: slot.minY + 4, width: width, height: 3.5)
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.75, yRadius: 1.75).fill()
        var fill = bar
        fill.size.width = max(3.5, bar.width * CGFloat(min(1, max(0, progress))))
        switch compact?.progressTone {
        case .focus: NSColor.systemRed.setFill()
        case .playback, .rest: NSColor.systemGreen.setFill()
        case .accent, nil: NSColor.controlAccentColor.setFill()
        case .timer?, .timerPaused?: Self.timerOrange.setFill()
        case .calendar?, .calendarJoin?: CalendarEarImage.color(compact?.calendar?.colorRGB).setFill()
        }
        NSBezierPath(roundedRect: fill, xRadius: 1.75, yRadius: 1.75).fill()
    }

    /// 番茄钟的进度环：16 pt 视口、半径 6.5、线宽 2.2；底环白 18%，专注红、休息绿，从正上方顺时针走。
    private func drawRing(_ progress: Double, tone: NotchPanel.Compact.ProgressTone, in box: NSRect) {
        let center = NSPoint(x: box.midX, y: box.midY)
        let radius = CGFloat(NotchFocusRing.radius)
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = CGFloat(NotchFocusRing.lineWidth)
        NSColor.white.withAlphaComponent(NotchFocusRing.trackWhiteAlpha).setStroke()
        track.stroke()
        let value = min(1, max(0, progress))
        if tone == .calendar || tone == .calendarJoin,
           let glyph = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 7, weight: .semibold).applying(.init(paletteColors: [.white]))) {
            // 稿：环里一枚缩小的日历符号。
            let g = glyph.size
            glyph.draw(in: NSRect(x: center.x - g.width / 2, y: center.y - g.height / 2, width: g.width, height: g.height))
        }
        if tone == .timerPaused {
            // 暂停：环降到 0.5，环中间两道竖线。
            let bars = NSBezierPath()
            for dx in [CGFloat(-1.8), 1.8] { bars.move(to: NSPoint(x: center.x + dx, y: center.y - 2.4)); bars.line(to: NSPoint(x: center.x + dx, y: center.y + 2.4)) }
            bars.lineWidth = 1.5; bars.lineCapStyle = .round
            NSColor.white.withAlphaComponent(0.92).setStroke(); bars.stroke()
        }
        guard value > 0 else { return }
        let rgb: (Double, Double, Double)
        switch tone {
        case .timer, .timerPaused: rgb = CountdownTimerStyle.orangeRGB
        case .calendar, .calendarJoin:
            let c = CalendarEarImage.color(compact?.calendar?.colorRGB).usingColorSpace(.sRGB) ?? .systemBlue
            rgb = (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
        case .rest: rgb = NotchFocusRing.restRGB
        default: rgb = NotchFocusRing.focusRGB
        }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * CGFloat(value), clockwise: true)
        arc.lineWidth = CGFloat(NotchFocusRing.lineWidth)
        arc.lineCapStyle = .round
        NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: tone == .timerPaused ? CGFloat(CountdownTimerStyle.pausedAlpha) : 1).setStroke()
        arc.stroke()
    }
}

extension NotchInfoDot {
    /// 信息点在岛里的位置：右 10、下 8，直径 8。
    static func rect(in bounds: NSRect) -> NSRect {
        NSRect(x: bounds.maxX - CGFloat(trailingInset + diameter), y: bounds.minY + CGFloat(bottomInset),
               width: CGFloat(diameter), height: CGFloat(diameter))
    }
}

extension NotchInfoDot.Tone {
    var color: NSColor {
        switch self {
        case .accent: return .controlAccentColor
        case .volume: return .systemBlue
        case .playback: return .systemGreen
        case .focus: return NSColor(srgbRed: 0xFF / 255, green: 0x6B / 255, blue: 0x5E / 255, alpha: 1)
        case .rest: return NSColor(srgbRed: 0x5F / 255, green: 0xD3 / 255, blue: 0x8A / 255, alpha: 1)
        }
    }
}

/// 最小形（M13）：黑色小胶囊，里面是语气色圆点，有比例时圆点外绕一圈 2pt 的弧。
/// 读屏当按钮读（“正在进行：标题”），点一下和紧凑互换。鼠标由画布统一接，这里不挡。
final class NotchMinimumView: NSView {
    private(set) var shapeID: String
    var onSelect: ((String) -> Void)?
    private let dot = CALayer()
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()

    init(shape: NotchMinimumShape) {
        shapeID = shape.id
        super.init(frame: shape.frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerCurve = .continuous
        let diameter = NotchMinimalPresentation.arcDiameter
        let line = NotchMinimalPresentation.arcLineWidth
        let ring = CGMutablePath()
        ring.addArc(center: CGPoint(x: diameter / 2, y: diameter / 2), radius: (diameter - line) / 2,
                    startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        for layer in [track, arc] {
            layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            layer.path = ring
            layer.fillColor = nil
            layer.lineWidth = line
            layer.lineCap = .round
            self.layer?.addSublayer(layer)
        }
        track.lineCap = .butt
        track.strokeColor = NSColor.white.withAlphaComponent(CGFloat(NotchProgressPart.trackWhiteAlpha)).cgColor
        dot.bounds = CGRect(x: 0, y: 0, width: NotchMinimalPresentation.dotDiameter, height: NotchMinimalPresentation.dotDiameter)
        dot.cornerRadius = NotchMinimalPresentation.dotDiameter / 2
        self.layer?.addSublayer(dot)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        update(shape)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ shape: NotchMinimumShape) {
        shapeID = shape.id
        setAccessibilityLabel(shape.label)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = shape.frame.height / 2
        let center = CGPoint(x: shape.frame.width / 2, y: shape.frame.height / 2)
        dot.position = center
        track.position = center
        arc.position = center
        let color = shape.tone.color.cgColor
        dot.backgroundColor = color
        arc.strokeColor = color
        if let fraction = shape.fraction {
            track.isHidden = false
            arc.isHidden = false
            arc.strokeEnd = CGFloat(fraction)
        } else {
            track.isHidden = true
            arc.isHidden = true
        }
        CATransaction.commit()
    }

    func select() { onSelect?(shapeID) }
    override func accessibilityPerformPress() -> Bool { select(); return true }
}

/// 被挡住的提醒留下的点。不把那一句补说一遍。
final class NotchSecondaryMark: NSView {
    var visible = false {
        didSet { guard visible != oldValue else { return }; needsDisplay = true }
    }
    nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard visible else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NotchInfoDot.rect(in: bounds)).fill()
    }
}

