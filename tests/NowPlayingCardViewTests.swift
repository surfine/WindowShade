import Cocoa

/// 正在播放大卡（NP-4）：尺寸照稿；点耳朵、点那一排的格子、启动台走的是同一张卡；
/// 进度条按下加粗、松手才跳、播放器不让跳时不加粗不发跳转；输出设备列表选完 0.3 秒收；
/// Esc、点卡外、指针离开 1.5 秒收回，拖动和开着列表时不收；输入权被撤销后一律不响应。
@main enum NowPlayingCardViewTests {
    @MainActor final class FakeSource: NowPlayingCardSource {
        var nowPlayingContent: NowPlayingCardContent?
        var nowPlayingArtwork: NowPlayingArtworkImage?
        var commands: [NotchMusicCommand] = []
        var seeks: [Double] = []
        func nowPlayingCommand(_ command: NotchMusicCommand) { commands.append(command) }
        func nowPlayingSeek(toSeconds seconds: Double) { seeks.append(seconds) }
    }

    @MainActor static func main() async {
        _ = NSApplication.shared
        // 候选默认关闭实时活动；本组测显式开启后的卡片，退出时恢复测试进程偏好。
        let activityKey = NotchActivityController.enabledKey
        let savedActivityPreference = UserDefaults.standard.object(forKey: activityKey)
        defer {
            if let savedActivityPreference { UserDefaults.standard.set(savedActivityPreference, forKey: activityKey) }
            else { UserDefaults.standard.removeObject(forKey: activityKey) }
        }
        NotchActivityController.isEnabled = true
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition { print("ok   \(label)") } else { failures += 1; print("FAIL \(label)") }
        }
        func close(_ a: Double?, _ b: Double, _ label: String) {
            expect(a != nil && abs(a! - b) < 1e-6, "\(label)（实际 \(String(describing: a))）")
        }
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                             characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint, window: NSWindow) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        func settle(_ seconds: Double) async {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        }
        func content(paused: Bool = false, seekable: Bool = true, duration: Double? = 200, elapsed: Double = 50,
                     playing at: Double = 1000) -> NowPlayingCardContent {
            NowPlayingCardContent(
                title: "晚风里的灯", artist: "林间合唱团", isPaused: paused, bundleID: "com.apple.Music",
                timeline: NowPlayingTimeline(duration: duration, elapsed: elapsed, stamp: at, rate: paused ? 0 : 1), seekable: seekable)
        }
        let geometry = NowPlayingCard.NotchGeometry(width: 185, height: 33.5, virtual: false)
        func makeCard(_ geometry: NowPlayingCard.NotchGeometry = geometry, seekable: Bool = true) -> (NowPlayingCard, NSWindow) {
            let card = NowPlayingCard(geometry: geometry)
            card.clock = { 1000 }
            card.inputIsCurrent = { true }
            let size = card.interactionSize
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView?.addSubview(card)
            card.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
            card.update(content(seekable: seekable), artwork: nil)
            card.layoutSubtreeIfNeeded()
            return (card, window)
        }

        print("CASE NP4-C01 | 尺寸照稿：420 × (175.5 − 33.5)")
        let (card, window) = makeCard()
        expect(card.interactionSize == NSSize(width: 420, height: 142), "真刘海：卡片视图 420 × 142")
        let capsule = NowPlayingCard(geometry: NowPlayingCard.NotchGeometry(width: 190, height: 24, virtual: true))
        expect(capsule.interactionSize == NSSize(width: 420, height: 175.5), "胶囊：整张岛都是内容 420 × 175.5")
        expect(card.accessibilityLabel() == "晚风里的灯，林间合唱团，正在播放", "读屏念歌名、歌手、正在播放")

        print("CASE NP4-C02 | 键盘：空格播放 / 暂停，Esc 收回；输入权被撤销后不响应")
        var commands: [NotchMusicCommand] = [], cancelled = 0
        card.onCommand = { commands.append($0) }
        card.onCancel = { cancelled += 1 }
        card.keyDown(with: key(49))
        expect(commands == [.playPause], "空格 = 播放 / 暂停")
        card.cancelOperation(nil)
        expect(cancelled == 1, "Esc 收回")
        card.inputIsCurrent = { false }
        card.keyDown(with: key(49))
        expect(commands == [.playPause], "输入权被撤销：空格不响应")
        card.inputIsCurrent = { true }

        print("CASE NP4-C03 | 进度条：按下加粗并跳到按下处，松手才发跳转")
        var seeks: [Double] = []
        card.onSeek = { seeks.append($0) }
        var interactionChanges = 0
        card.onInteractionChange = { interactionChanges += 1 }
        // 进度条中线在岛坐标 y = 90，视图 y = 90 − 33.5；视图朝下，窗口坐标朝上。
        func windowPoint(fraction: Double) -> NSPoint { NSPoint(x: 14 + 392 * fraction, y: 142 - (90 - 33.5)) }
        card.mouseDown(with: mouse(.leftMouseDown, windowPoint(fraction: 0.5), window: window))
        expect(card.isDragging && card.scrub.barHeight == 8, "按下：条加粗到 8")
        expect(seeks.isEmpty, "按下的时候还不跳")
        card.mouseDragged(with: mouse(.leftMouseDragged, windowPoint(fraction: 0.75), window: window))
        close(card.scrub.displayFraction(player: 0.25, now: 1000), 0.75, "拖动跟手")
        expect(seeks.isEmpty, "拖动中也不跳")
        card.mouseUp(with: mouse(.leftMouseUp, windowPoint(fraction: 0.75), window: window))
        expect(seeks.count == 1, "松手跳一次")
        close(seeks.first, 150, "松手跳到 75% × 200 = 150 秒")
        expect(!card.isDragging && card.scrub.barHeight == 4, "松手变回 4 高")
        expect(interactionChanges == 2, "按下和松手各通知一次（收回条件要重算）")
        card.inputIsCurrent = { false }
        card.mouseDown(with: mouse(.leftMouseDown, windowPoint(fraction: 0.5), window: window))
        expect(!card.isDragging, "输入权被撤销：按下不接")
        card.inputIsCurrent = { true }

        print("CASE NP4-C04 | 播放器不让跳：条不加粗，也不发跳转")
        let (fixed, fixedWindow) = makeCard(seekable: false)
        var fixedSeeks: [Double] = []
        fixed.onSeek = { fixedSeeks.append($0) }
        fixed.mouseDown(with: mouse(.leftMouseDown, windowPoint(fraction: 0.5), window: fixedWindow))
        fixed.mouseUp(with: mouse(.leftMouseUp, windowPoint(fraction: 0.5), window: fixedWindow))
        expect(!fixed.isDragging && fixed.scrub.barHeight == 4 && !fixed.scrub.showsHandCursor, "不让跳：不加粗、没有手形")
        expect(fixedSeeks.isEmpty, "不让跳：不发跳转")

        print("CASE NP4-C05 | 直播：条换成“直播”，没有剩余时间")
        let (live, _) = makeCard()
        live.update(content(seekable: false, duration: nil), artwork: nil)
        live.layoutSubtreeIfNeeded()
        expect(live.accessibilityValue() as? String == "直播，已播 50 秒", "直播读屏只念已播放时长")

        print("CASE NP4-C06 | 输出设备：点开往下长，选完 0.3 秒收，读屏；列表开着进度条不接")
        func fakeRoute(_ name: String, _ kind: AudioOutputKind, current: Bool) -> AudioOutputRoute {
            AudioOutputRoute(id: UInt32(name.count), uid: "uid-\(name)", name: name, kind: kind, isCurrent: current)
        }
        let routes = [fakeRoute("这台 Mac", .mac, current: true), fakeRoute("AirPods Pro", .headphones, current: false),
                      fakeRoute("Studio Display", .speaker, current: false), fakeRoute("客厅的音箱", .speaker, current: false)]
        var sizeEvents: [Bool] = [], picked: [String] = []
        card.loadRoutes = { routes }
        card.onSizeChange = { sizeEvents.append($0) }
        card.onSelectRoute = { picked.append($0.name) }
        card.openList()
        expect(card.listOpen && sizeEvents == [true], "点开：列表出来，岛往下长")
        expect(card.interactionSize.height == 256 - 33.5, "4 个设备：总高 256，扣掉刘海 222.5")
        card.mouseDown(with: mouse(.leftMouseDown, windowPoint(fraction: 0.5), window: window))
        expect(!card.isDragging, "列表开着：进度条不接按下")
        card.inputIsCurrent = { false }
        card.closeList()
        card.inputIsCurrent = { true }
        expect(card.listOpen == false, "closeList 本身不看输入权（收回路径）")
        card.openList()
        expect(card.routes.filter(\.isCurrent).map(\.name) == ["这台 Mac"], "当前设备打勾")
        // 选 AirPods：立刻打勾换过去，0.3 秒后收列表。
        let rows = card.all(NowPlayingRouteRow.self)
        expect(rows.count == 4, "四行")
        rows[1].mouseDown(with: mouse(.leftMouseDown, .zero, window: window))
        expect(picked == ["AirPods Pro"], "选了就切换默认输出")
        expect(card.routes.filter(\.isCurrent).map(\.name) == ["AirPods Pro"] && rows[1].checked && !rows[0].checked, "打勾跟着换")
        expect(card.listOpen, "刚选完列表还开着")
        await settle(0.5)
        expect(!card.listOpen && sizeEvents.suffix(1) == [false], "选完 0.3 秒收列表，岛收回来")
        expect(card.interactionSize.height == 142, "收回后回到 142")
        // 一个设备也读不到：沿既有列表显示反馈，仍能返回播放控制。
        let (empty, _) = makeCard()
        empty.loadRoutes = { [] }
        empty.openList()
        expect(empty.listOpen && empty.routes.isEmpty, "读不到设备：显示空列表反馈")
        empty.closeList()
        expect(!empty.listOpen && empty.interactionSize.height == 142, "空列表可以返回播放控制")
        // 超过 5 个设备：高度按 5 行封顶。
        let many = (0..<8).map { fakeRoute("设备\($0)", .speaker, current: $0 == 0) }
        let (big, _) = makeCard()
        big.loadRoutes = { many }
        big.openList()
        expect(big.interactionSize.height == (84 + 5 * 34 + 36) - 33.5, "8 个设备：最多 5 行，其余滚")

        print("CASE NP4-C07 | 点耳朵、点那一格、启动台：同一张卡")
        let source = FakeSource()
        source.nowPlayingContent = content()
        let presenter = NowPlayingCardPresenter()
        presenter.source = source
        presenter.unlocked = { true }
        presenter.outputKind = { .headphones }
        presenter.selectRoute = { _ in }
        var shownCards: [NowPlayingCard] = []
        var onDismissCallbacks: [(WS2.LeaseRevocation) -> Void] = []
        var dismissed = 0
        presenter.present = { card, onDismiss in
            shownCards.append(card); onDismissCallbacks.append(onDismiss); return true
        }
        presenter.dismissCard = { card in
            dismissed += 1
            if let index = shownCards.firstIndex(where: { $0 === card }) { onDismissCallbacks[index](.released) }
        }
        var inside = true
        var sizeChanges: [Bool] = []
        let host = NowPlayingCardHost(notch: geometry, islandContains: { _ in inside }, interactionSizeChanged: { sizeChanges.append($0) },
                                      earCoverVisible: true)
        // NotchRow 的音乐格长成大卡；耳朵走面板钩子；两条路最后都是 presenter.open(host:)。
        let cell = NotchRow.OngoingCell(activityID: "source.music", kind: .music, title: "歌", subtitle: "人", symbol: "music.note",
                                        phase: nil, isPaused: false)
        expect(cell.action == .nowPlayingOpen, "那一格的动作是“长成大卡”")
        NotchActivityController.isEnabled = false
        expect(!presenter.open(host: host) && shownCards.isEmpty, "实时活动关闭时不创建大卡")
        NotchActivityController.isEnabled = true
        expect(presenter.open(host: host), "点耳朵：开")
        expect(presenter.open(host: host), "再从那一格点：还是开着的那一张")
        expect(presenter.open(host: host), "从启动台点：同一张")
        expect(shownCards.count == 1 && presenter.openCount == 1 && presenter.isShowing, "不管从哪里点，只有一张卡")
        expect(shownCards[0].earCoverFrame != nil, "紧凑左耳有封面：卡里的封面从耳朵长出来")
        presenter.dismiss()
        expect(!presenter.isShowing && dismissed == 1, "收回")
        expect(presenter.open(host: host) && shownCards.count == 2 && presenter.openCount == 2, "收回以后再点是新开一张")
        presenter.dismiss()
        source.nowPlayingContent = nil
        expect(!presenter.open(host: host) && shownCards.count == 2, "没有在放的歌：不开，退回点刘海的行为")
        source.nowPlayingContent = content()
        presenter.unlocked = { false }
        expect(!presenter.open(host: host), "锁屏：不开")
        presenter.unlocked = { true }

        print("CASE NP4-C08 | 收回：点卡外、指针离开 1.5 秒；拖动和开着列表时不收")
        var now = 100.0
        presenter.uptime = { now }
        var pointer = NSPoint(x: 5, y: 5)
        presenter.pointerLocation = { pointer }
        shownCards.removeAll(); onDismissCallbacks.removeAll(); dismissed = 0
        expect(presenter.open(host: host), "开一张")
        let open = shownCards[0]
        open.inputIsCurrent = { true }
        // 点在岛上不收；点在岛外收。
        inside = true
        presenter.clickedSomewhere()
        expect(presenter.isShowing, "点在岛上（含刘海）：不收")
        inside = false
        presenter.clickedSomewhere()
        expect(!presenter.isShowing && dismissed == 1, "点卡外：收回")

        expect(presenter.open(host: host), "再开一张")
        let second = shownCards[1]
        second.inputIsCurrent = { true }
        inside = false
        second.onPointer?(false)
        now = 100.5
        await settle(0.5)
        expect(presenter.isShowing, "离开 0.5 秒：还在")
        now = 101.6
        await settle(0.5)
        expect(!presenter.isShowing, "离开满 1.5 秒：收回")

        // 从耳朵点开：指针在刘海那一截，卡从没收到过 mouseEntered / mouseExited。
        expect(presenter.open(host: host), "再开一张（从耳朵点开，不经过任何 onPointer）")
        let ear = shownCards[2]
        ear.inputIsCurrent = { true }
        now = 120
        inside = true
        await settle(0.5)
        expect(presenter.isShowing, "指针还在岛上（耳朵）：不收")
        inside = false
        now = 121
        await settle(0.5)
        now = 121.6
        await settle(0.5)
        expect(presenter.isShowing, "指针离开岛 0.6 秒：还在")
        now = 123
        await settle(0.5)
        expect(!presenter.isShowing, "耳朵点开后指针离开岛满 1.5 秒：收回")

        expect(presenter.open(host: host), "再开一张")
        let third = shownCards[3]
        third.inputIsCurrent = { true }
        third.clock = { 1000 }
        third.update(content(), artwork: nil)
        third.layoutSubtreeIfNeeded()
        let thirdWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 142), styleMask: [.borderless], backing: .buffered, defer: false)
        thirdWindow.contentView?.addSubview(third)
        third.frame = NSRect(x: 0, y: 0, width: 420, height: 142)
        third.layoutSubtreeIfNeeded()
        now = 200
        inside = false
        // 拖着进度条离开：不收。
        third.mouseDown(with: mouse(.leftMouseDown, windowPoint(fraction: 0.4), window: thirdWindow))
        third.onPointer?(false)
        now = 205
        await settle(0.5)
        expect(presenter.isShowing && third.isDragging, "拖进度条时指针在外面：不收")
        // 松手时指针还在外面：从松手起数 1.5 秒。
        third.mouseUp(with: mouse(.leftMouseUp, windowPoint(fraction: 0.4), window: thirdWindow))
        now = 205.5
        await settle(0.5)
        expect(presenter.isShowing, "松手后 0.5 秒：还在")
        now = 207
        await settle(0.5)
        expect(!presenter.isShowing, "松手后满 1.5 秒：收回")

        expect(presenter.open(host: host), "再开一张")
        let fourth = shownCards[4]
        fourth.inputIsCurrent = { true }
        fourth.loadRoutes = { routes }
        fourth.openList()
        now = 300
        fourth.onPointer?(false)
        now = 310
        await settle(0.5)
        expect(presenter.isShowing, "输出设备列表开着：指针离开也不收")
        expect(sizeChanges.contains(true), "列表开出来时岛按新高度长")
        fourth.closeList()
        now = 312
        await settle(0.5)
        expect(!presenter.isShowing, "列表关上后指针还在外面：再数 1.5 秒收回")

        print("CASE NP4-C09 | 这首歌没了：等 2.6 秒再收，曲目之间的空档不收；回来了就留着")
        expect(presenter.open(host: host), "再开一张")
        source.nowPlayingContent = nil
        presenter.refresh()
        expect(presenter.isShowing, "刚没有数据：先不收")
        source.nowPlayingContent = content()
        presenter.refresh()
        await settle(0.1)
        expect(presenter.isShowing, "数据回来了：留着")
        presenter.dismiss()

        print("CASE NP5-C10 | 大卡里的音量条：按键换成条、不出两耳、1.2 秒换回、可拖、计时器空闲为 0")
        // 展示端：卡没开时不接（归两耳）；开着就接。
        presenter.dismiss()
        expect(!presenter.showVolume(value: 0.5, muted: false), "大卡没开：不接，两耳照常")
        expect(NotchLeaseHub.Owner.nowPlaying != .pomodoro && NotchLeaseHub.Owner.nowPlaying.layer == .opened,
               "大卡有自己的租约主人，不再借番茄钟的名字")
        var written: [Double] = []
        presenter.writeVolume = { written.append($0) }
        let stillPlaying = shownCards.count
        expect(presenter.open(host: host), "再开一张")
        let volumeCard = shownCards[stillPlaying]
        let volumeWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 142), styleMask: [.borderless], backing: .buffered, defer: false)
        volumeCard.inputIsCurrent = { true }
        volumeCard.clock = { 1000 }
        volumeCard.update(content(paused: true), artwork: nil)
        volumeWindow.contentView?.addSubview(volumeCard)
        volumeCard.frame = NSRect(x: 0, y: 0, width: 420, height: 142)
        volumeCard.layoutSubtreeIfNeeded()
        presenter.pointerLocation = { NSPoint(x: 5, y: 5) }
        inside = true
        volumeCard.onPointer?(true)
        expect(!volumeCard.volumeShown && volumeCard.pendingTimerCount == 0, "没按键：没有音量条，也没有计时器在等")
        expect(!presenter.leaveTimerRunning, "指针在卡里：离开检查的 0.25 秒计时器是停的")
        expect(presenter.showVolume(value: 0.4, muted: false), "大卡开着按音量键：卡接")
        expect(volumeCard.volumeShown && abs(volumeCard.volumeValue - 0.4) < 1e-9, "控制那一行换成音量条")
        expect(volumeCard.pendingTimerCount == 1, "只有一个“松键后换回”的计时器")
        await settle(0.6)
        presenter.showVolume(value: 0.5, muted: false)
        await settle(0.8)
        expect(volumeCard.volumeShown, "每按一下把换回往后推：距上一下 0.8 秒还在")
        await settle(0.6)
        expect(!volumeCard.volumeShown && volumeCard.pendingTimerCount == 0, "松键 1.2 秒后换回，计时器清零")
        // 拖条改系统音量。
        let row = NowPlayingVolumeRow.frame(cardWidth: 420)
        let range = NowPlayingVolumeRow.barRange(rowWidth: row.width)
        expect(NowPlayingVolumeRow.minMarkerSymbol == "speaker.fill" && NowPlayingVolumeRow.maxMarkerSymbol == "speaker.wave.3.fill",
               "条两头固定“最小 / 最大”喇叭，不随音量变")
        expect(range.upperBound <= row.width - NowPlayingVolumeRow.maxMarkerWidth, "条在右端“最大”标记之前收住")
        func volumePoint(_ fraction: Double) -> NSPoint {
            NSPoint(x: row.minX + range.lowerBound + CGFloat(fraction) * (range.upperBound - range.lowerBound), y: 142 - (row.midY - 33.5))
        }
        presenter.showVolume(value: 0.2, muted: false)
        volumeCard.mouseDown(with: mouse(.leftMouseDown, volumePoint(0.5), window: volumeWindow))
        expect(volumeCard.isDragging && written.count == 1 && abs(written[0] - 0.5) < 0.02, "按在条上：跳到按下处并写系统音量")
        expect(volumeCard.pendingTimerCount == 0, "手按在条上时不数 1.2 秒")
        volumeCard.mouseDragged(with: mouse(.leftMouseDragged, volumePoint(0.9), window: volumeWindow))
        expect(written.count == 2 && abs(written[1] - 0.9) < 0.02, "拖动跟手写")
        volumeCard.mouseDragged(with: mouse(.leftMouseDragged, volumePoint(1.4), window: volumeWindow))
        expect(abs(written[2] - 1) < 1e-9, "拖过头夹在 1")
        presenter.pointerLocation = { NSPoint(x: 5, y: 5) }
        volumeCard.onPointer?(false)
        expect(!presenter.leaveTimerRunning, "拖音量条时离开检查的计时器停着")
        volumeCard.mouseUp(with: mouse(.leftMouseUp, volumePoint(0.3), window: volumeWindow))
        expect(!volumeCard.isDragging && volumeCard.volumeShown && volumeCard.pendingTimerCount == 1, "松手后才开始数 1.2 秒")
        // 输入权被撤销：不接。
        volumeCard.inputIsCurrent = { false }
        let before = written.count
        volumeCard.mouseDown(with: mouse(.leftMouseDown, volumePoint(0.7), window: volumeWindow))
        expect(written.count == before && !volumeCard.isDragging, "输入权被撤销：条不接")
        volumeCard.inputIsCurrent = { true }
        await settle(1.4)
        expect(!volumeCard.volumeShown && volumeCard.pendingTimerCount == 0, "再换回，计时器清零")
        // 列表开着：键照接（不出两耳），但控制行本来就让位了，不换条。
        volumeCard.loadRoutes = { routes }
        volumeCard.openList()
        expect(presenter.showVolume(value: 0.6, muted: false) && !volumeCard.volumeShown && volumeCard.pendingTimerCount == 0,
               "列表开着：卡接下键但不换条，也不起计时器")
        expect(!presenter.leaveTimerRunning, "列表开着：离开检查的计时器停着")
        volumeCard.closeList()
        expect(presenter.leaveTimerRunning, "列表关上、指针在卡外：计时器再起")
        volumeCard.onPointer?(true)
        expect(!presenter.leaveTimerRunning, "指针回到卡里：计时器又停")
        presenter.dismiss()
        expect(!presenter.leaveTimerRunning && volumeCard.pendingTimerCount == 0, "卡收回后一个计时器都不留")

        // 设了 NP4_SNAPSHOT_DIR 才出图：把卡画成 PNG 放进去，方便对着稿看（不设就什么都不做）。
        if let directory = ProcessInfo.processInfo.environment["NP4_SNAPSHOT_DIR"] {
            await snapshot(into: directory, geometry: geometry, content: content, settle: settle)
        }

        print(failures == 0 ? "PASS NowPlayingCardViewTests" : "FAIL NowPlayingCardViewTests: \(failures) failure(s)")
        if failures > 0 { exit(1) }
    }
}

extension NowPlayingCardViewTests {
    @MainActor static func snapshot(into directory: String, geometry: NowPlayingCard.NotchGeometry,
                                    content: (Bool, Bool, Double?, Double, Double) -> NowPlayingCardContent,
                                    settle: (Double) async -> Void) async {
        func gradientArtwork() -> NowPlayingArtworkImage {
            let side = NowPlayingArtworkImage.side
            var pixels = [UInt8](repeating: 255, count: side * side * 4)
            for y in 0..<side { for x in 0..<side {
                let i = (y * side + x) * 4
                pixels[i] = UInt8(40 + 160 * x / side); pixels[i + 1] = UInt8(60 + 40 * y / side); pixels[i + 2] = UInt8(200 - 120 * x / side)
            } }
            var straight: [UInt8] = []
            for y in 0..<ArtworkPalette.side { for x in 0..<ArtworkPalette.side {
                let i = ((y * 2) * side + x * 2) * 4
                straight += [pixels[i], pixels[i + 1], pixels[i + 2], 255]
            } }
            return NowPlayingArtworkImage(trackKey: "k", rgba: Data(pixels), palette: ArtworkPalette.make(rgba: straight),
                                          fingerprint: ArtworkPalette.fingerprint(of: straight))
        }
        func render(_ name: String, paused: Bool, live: Bool = false, list: Bool = false, thick: Bool = false) async {
            let card = NowPlayingCard(geometry: geometry)
            card.clock = { 1000 }
            card.inputIsCurrent = { true }
            card.loadRoutes = { [
                AudioOutputRoute(id: 1, uid: "a", name: "这台 Mac 的扬声器", kind: .mac, isCurrent: false),
                AudioOutputRoute(id: 2, uid: "b", name: "AirPods Pro", kind: .headphones, isCurrent: true),
                AudioOutputRoute(id: 3, uid: "c", name: "Studio Display", kind: .speaker, isCurrent: false),
                AudioOutputRoute(id: 4, uid: "d", name: "客厅的音箱", kind: .speaker, isCurrent: false)] }
            card.update(content(paused, !live, live ? nil : 214, 72, 1000), artwork: gradientArtwork())
            card.setOutputKind(.headphones)
            if list { card.openList() }
            let size = card.interactionSize
            let total = NSSize(width: size.width, height: size.height + geometry.height)
            let window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: total.width, height: total.height),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.backgroundColor = .black
            let root = NSView(frame: NSRect(origin: .zero, size: total))
            root.wantsLayer = true
            root.layer?.backgroundColor = NSColor.black.cgColor
            card.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height)
            root.addSubview(card)
            window.contentView = root
            window.orderFrontRegardless()
            await settle(0.6)
            if thick { card.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 210, y: size.height - 56.5),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!) }
            await settle(0.4)
            let scale: CGFloat = 2
            guard let context = CGContext(data: nil, width: Int(total.width * scale), height: Int(total.height * scale), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.scaleBy(x: scale, y: scale)
            root.layer?.render(in: context)
            if let image = context.makeImage() {
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            }
            window.orderOut(nil)
        }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        await render("card-playing", paused: false)
        await render("card-paused", paused: true)
        await render("card-live", paused: false, live: true)
        await render("card-pressed", paused: false, thick: true)
        await render("card-list", paused: false, list: true)
    }
}

private extension NSView {
    func all<T: NSView>(_ type: T.Type) -> [T] {
        var found: [T] = []
        for view in subviews {
            if let match = view as? T { found.append(match) }
            found += view.all(type)
        }
        return found
    }
}
