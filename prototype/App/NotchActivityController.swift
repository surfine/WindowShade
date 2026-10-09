import Cocoa
import MapKit

/// Owns the five source lifetimes. The UI never reads devices, runs scripts or calculates routes.
@MainActor
final class NotchActivityController: NSObject, NSSharingServiceDelegate {
    nonisolated static let enabledKey = "Notch.activitiesEnabled"
    nonisolated static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
    var onChange: (([NotchActivity], String?) -> Void)?
    var ws2FocusAction: ((NotchActivityAction) -> Void)?
    /// 正在播放的封面（NP-2）：换曲取到、换掉或丢掉时通知刘海紧凑左耳；没有推送流就一直是 nil。
    var onNowPlayingArtwork: ((NowPlayingArtworkImage?) -> Void)?
    var nowPlayingArtwork: NowPlayingArtworkImage? { sources.nowPlayingArtwork }
    /// 点了“正在播放”那一格（或启动台上那张卡）要长成大卡：刘海接上，选屏、收那一排都在那边做（NP-4）。
    var onOpenNowPlayingCard: (() -> Void)?
    /// 正在播放大卡的展示与收回。第一次用到才建；没建过就没有卡可刷新。
    private var nowPlayingPresenter: NowPlayingCardPresenter?
    var nowPlayingCard: NowPlayingCardPresenter {
        if let nowPlayingPresenter { return nowPlayingPresenter }
        let presenter = NowPlayingCardPresenter()
        presenter.source = self
        nowPlayingPresenter = presenter
        return presenter
    }
    func ws2PublishFocus(title: String?, trailing: String? = nil, subtitle: String = "", paused: Bool = false, progress: Double? = nil) {
        guard Self.isEnabled, !suspended else { return }
        configure()
        if let title {
            // 收场立即：番茄钟回到空闲时分不出是“一轮做完”还是点了结束（稿：一轮做完 ✓ 留 4 秒，要番茄钟的模型给出最后的样子才做）。
            put(id: "ws2.focus", kind: .focus, title: title, subtitle: subtitle, symbol: "timer", progress: .reported(progress), paused: paused,
                trailing: trailing, closing: .immediate)
        } else if let old = store.live(id: "ws2.focus") {
            store.end(id: old.id, generation: old.generation, now: ProcessInfo.processInfo.systemUptime)
        }
        publish()
    }
    /// 计时器（⌃⌥T，只倒数一次）：宿主、选分钟、大卡和时间到都在 `countdown`；两耳由 `ws2PublishTimer` 发布。
    /// 第一次用到就建，宿主不另起定时器（空闲和暂停都没有唤醒）。
    private(set) lazy var countdown: CountdownTimerPresenter = {
        let host = CountdownTimerHost(lastMinutes: CountdownTimerSettings.lastMinutes, chime: { shadeSounds.beep() })
        let presenter = CountdownTimerPresenter(host: host)
        presenter.publish = { [weak self] timer, now in self?.ws2PublishTimer(timer, at: now) }
        return presenter
    }()
    /// 左耳橙色的环（剩余 ÷ 总长），右耳“9 分”（最后 60 秒“0:42”，超时“+3 分”）；空闲时收掉。权重 75 由种类给。
    func ws2PublishTimer(_ timer: CountdownTimer, at now: WS2.Instant) {
        guard Self.isEnabled, !suspended else { return }
        configure()
        if timer.state == .idle {
            if let old = store.live(id: Self.timerActivityID) {
                store.end(id: old.id, generation: old.generation, now: ProcessInfo.processInfo.systemUptime)
            }
        } else {
            let remaining = timer.total > 0 ? Double(timer.remaining(at: now)) / Double(timer.total) : 0
            put(id: Self.timerActivityID, kind: .timer, title: "计时器", subtitle: CountdownTimerText.subtitle(for: timer),
                symbol: "timer", progress: .reported(timer.state == .done ? 1 : min(1, max(0, remaining))),
                paused: timer.state == .paused, trailing: CountdownTimerText.ear(for: timer, at: now))
        }
        publish()
    }
    nonisolated static let timerActivityID = "ws2.timer"
    /// 日程（CAL-3）：来源在 `sources.calendar`，提醒引擎、大卡、加入在 `calendar`；两耳由 `publishCalendar` 发布。
    /// 第一次开始跑就建；空闲时没有定时器（见 CalendarPresenter）。
    private(set) lazy var calendar: CalendarPresenter = {
        let presenter = CalendarPresenter(source: sources.calendar)
        presenter.onUpdate = { [weak self] output, context in self?.publishCalendar(output, sharing: context.sharing) }
        return presenter
    }()
    nonisolated static let calendarActivityID = "ws2.calendar"
    /// 左耳日历色环（剩余 ÷ 提前量），右耳“4 分”（最后一分钟“0:42”）；开始后能加入时满环加绿色摄像机；没有就收掉。权重 85 由种类给。
    /// 共享屏幕时标题换成“日程”，地点不写。
    private func publishCalendar(_ output: CalendarReminderEngine.Output, sharing: Bool) {
        guard Self.isEnabled, !suspended, running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let selection = output.selection, let ear = output.ear {
            let item = selection.current
            let place = sharing ? "" : (item.event.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = [CalendarWords.timeRange(start: item.event.start, end: item.event.end), place]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            put(id: Self.calendarActivityID, kind: .calendar, title: CalendarWords.title(item.event, sharing: sharing),
                subtitle: subtitle, symbol: "calendar", progress: .reported(ear.ringFraction), trailing: ear.trailing,
                calendar: NotchCalendarFace(colorRGB: ear.colorRGB, joinable: ear.mode == .joinable, hasLink: ear.hasLink,
                                            spoken: CalendarWords.spoken(item, sharing: sharing)), now: now)
        } else if let old = store.activities.first(where: { $0.id == Self.calendarActivityID }) {
            store.end(id: old.id, generation: old.generation, now: now)
        }
        publish()
    }
    /// 欢迎窗口第三步、设置里点“允许”：这时才第一次问系统。结果在主线程回来。
    func requestCalendarAccess(_ done: @escaping @MainActor (Bool) -> Void) {
        sources.calendar.requestAccess(done)
    }
    /// 设置里改了开关或提前量：按新设置重新起停来源（没授权一律不起）。
    func calendarSettingsChanged() {
        sources.syncCalendar()
        if CalendarSettings.enabled { calendar.refresh() } else { calendar.reset() }
    }
    /// iPhone 上的遥控器连着时左耳的遥控器符号（只有符号，不写字）；断开就收掉。
    /// `symbol` 默认是遥控器；走进会话时换成指挥棒（M09）。
    func ws2PublishRemote(connected: Bool, symbol: String = "appletvremote.gen4") {
        guard Self.isEnabled, !suspended else { return }
        configure()
        if connected {
            put(id: "ws2.remote", kind: .remote, title: "iPhone 上的遥控器", subtitle: "", symbol: symbol, trailing: "")
        } else if let old = store.live(id: "ws2.remote") {
            store.end(id: old.id, generation: old.generation, now: ProcessInfo.processInfo.systemUptime)
        }
        publish()
    }
    // MARK: 编程会话（M08）：在跑 / 等你 / 做完了成为一条持续的 `.session` 活动

    /// 进入“等你”时开口一次（主句“\(项目)在等你”，副句“\(助手)想执行 \(摘要)”）。由 App 接到刘海的播报上。
    var onSessionBloom: ((CodingSessionActivities.Bloom) -> Void)?
    /// “过去”：去那个会话所在的终端窗口；找不到时由接手的人打开会话页。参数是会话所在的目录。
    var onSessionGo: ((String) -> Void)?
    /// 等你的会话变了（菜单要重建一行）。
    var onSessionMenuChange: (() -> Void)?
    private(set) var sessions = CodingSessionActivities()
    /// 菜单里的“等你”行：有会话等你才有，结束就消失。
    var sessionMenuRows: [CodingSessionActivities.MenuRow] { sessions.menuRows }
    /// 有会话在等你的目录（M07 的 NotchTile.waiting 读这个，M11 再接到那一排）。
    var waitingSessionDirectories: Set<String> { sessions.waitingDirectories }
    func isSessionWaiting(cwd: String) -> Bool { sessions.isWaiting(cwd: cwd) }

    /// 一个会话的状态变了。返回时刘海上的持续活动已经对上；开口那一句交给 `onSessionBloom`。
    /// 睡着、锁屏时只记状态不上刘海（项目名不上锁屏），回来时再对一次。
    func ws2PublishSession(_ change: CodingSessionActivities.Change) {
        let before = sessions.menuRows
        let now = ProcessInfo.processInfo.systemUptime
        let output = sessions.apply(change, now: now)
        guard Self.isEnabled, !suspended else {
            if sessions.menuRows != before { onSessionMenuChange?() }
            return
        }
        configure()
        syncSessions(now: now)
        publish()
        if let bloom = output.bloom { onSessionBloom?(bloom) }
        if sessions.menuRows != before { onSessionMenuChange?() }
    }

    /// 额度读数变了（用量，实验）。nil = 没有数据：右耳回到会话状态。第一次掉到 10% 以内开口一次。
    func ws2PublishUsage(_ usage: CodingSessionUsage?) {
        let bloom = sessions.applyUsage(usage)
        guard Self.isEnabled, !suspended else { return }
        configure()
        syncSessions(now: ProcessInfo.processInfo.systemUptime)
        publish()
        if let bloom { onSessionBloom?(bloom) }
    }

    /// 编程会话整个关掉（开关关了）：忘掉所有会话，收掉那两条活动。
    func ws2ResetSessions() {
        let hadRows = !sessions.menuRows.isEmpty
        sessions.reset()
        if running { syncSessions(now: ProcessInfo.processInfo.systemUptime); publish() }
        if hadRows { onSessionMenuChange?() }
    }

    /// 菜单里点“等你”行。
    func ws2GoToSession(_ id: String) {
        guard let cwd = sessions.cwd(ofSession: id) else { return }
        onSessionGo?(cwd)
    }

    /// 把模型对到 store：持续那一条（在跑却 120 秒没消息就过期）、做完那一条（4 秒后自己过期）。
    private func syncSessions(now: Double) {
        func sync(_ id: String, _ spec: CodingSessionActivities.Spec?) {
            if let spec {
                // 收场立即：做完时“✓ 完成”那一条（completionID，留 4 秒）就是最后的样子，持续那一条不再另留一份。
                put(id: id, kind: .session, title: spec.title, subtitle: spec.subtitle, symbol: spec.symbol, detail: spec.cwd,
                    trailing: spec.trailing, sessionPhase: spec.phase, expires: spec.expiresAt,
                    stale: .at(spec.staleAt), closing: .immediate, now: now)
            } else if let old = store.live(id: id) {
                store.end(id: id, generation: old.generation, now: now)
            }
        }
        sync(CodingSessionActivities.activityID, sessions.liveSpec)
        sync(CodingSessionActivities.completionID, sessions.doneSpec(at: now))
    }

    private(set) var store = NotchActivityStore()
    private let sources = NotchActivitySources()
    private let downloads = DownloadActivitySource()
    /// 文件拷贝进度（实验，默认关：`Activities.copyProgress`）。
    private let copies = CopyProgressSource()
    /// 下好了的文件名（「离开期间」摘要记一笔；只在摘要开着、人不在时才有人收）。
    var onDownloadsFinished: (([String]) -> Void)?
    private var generation: UInt64 = 0
    private var running = false
    private var expiry: Timer?
    private var operationEpoch = 0
    private var choosingFiles = false
    private var sharing: NSSharingService?
    private var routeTask: Task<Void, Never>?
    private var routeEpoch = 0
    private var routeItems: [MKMapItem] = []
    private var observers: [NSObjectProtocol] = []
    private var lastVisible: [NotchActivity] = []
    private var lastSelection: String?
    private var suspensions: Set<String> = []
    private var suspended: Bool { !suspensions.isEmpty }

    override init() {
        super.init()
        sources.onSnapshot = { [weak self] items in self?.receive(items) }
        sources.onArtwork = { [weak self] image in
            self?.onNowPlayingArtwork?(image)
            self?.nowPlayingPresenter?.refresh()
        }
        downloads.onChange = { [weak self] update in self?.receiveDownloads(update) }
        copies.onChange = { [weak self] update in self?.receiveCopies(update) }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, reason) in [(NSWorkspace.willSleepNotification, "sleep"), (NSWorkspace.sessionDidResignActiveNotification, "session")] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspend(reason) }
            })
        }
        for (name, reason) in [(NSWorkspace.didWakeNotification, "sleep"), (NSWorkspace.sessionDidBecomeActiveNotification, "session")] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume(reason) }
            })
        }
        for (name, lock) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if lock { self?.suspend("lock") } else { self?.resume("lock") } }
            })
        }
    }

    func configure() {
        guard Self.isEnabled, !suspended else { stop(); return }
        guard !running else { return }
        running = true
        _ = calendar
        sources.start()
        downloads.start()
        copies.start()
        rescheduleExpiry()
        // 睡眠、锁屏期间 store 被清空；回来时把还在跑、在等你的会话放回去。
        syncSessions(now: ProcessInfo.processInfo.systemUptime)
    }

    private func suspend(_ reason: String) { suspensions.insert(reason); calendar.suspend(); stop() }
    /// 回来时：锁着或睡着时过去的最后 10 秒不补；来源重新起来后（configure）会重新算一次，直接出紧凑。
    private func resume(_ reason: String) { suspensions.remove(reason); calendar.noteResume(); configure() }
    private func stop() {
        running = false; operationEpoch += 1; choosingFiles = false
        sources.stop()
        downloads.stop()
        copies.stop()
        expiry?.invalidate(); expiry = nil
        routeEpoch += 1; routeTask?.cancel(); routeTask = nil; routeItems = []
        sharing?.delegate = nil; sharing = nil
        store = NotchActivityStore()
        publish()
    }

    func select(_ id: String) { if store.select(id: id) { publish() } }
    func move(_ delta: Int) { store.moveSelection(by: delta); publish() }

    private func receive(_ items: [NotchSourceSnapshot]) {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for kind in [NotchActivityKind.music, .airPods, .recording] {
            let id = "source.\(kind.rawValue)"
            if let item = items.first(where: { $0.kind == kind }) {
                put(id: id, kind: kind, title: item.title, subtitle: item.subtitle, symbol: item.symbol,
                    progress: .reported(item.progress), paused: item.isPaused, detail: item.detail, now: now)
            } else if let old = store.live(id: id) {
                store.end(id: id, generation: old.generation, now: now)
            }
        }
        publish()
    }

    /// 打开或关掉“浏览器下载”卡。关掉立刻停止盯文件夹；打开后才第一次读（系统会问文件夹权限）。
    func setDownloadsEnabled(_ on: Bool) {
        DownloadActivitySource.isEnabled = on
        if on { configure(); downloads.start() } else {
            downloads.stop()
            let now = ProcessInfo.processInfo.systemUptime
            for id in ["source.download", "owned.download.done"] {
                if let old = store.live(id: id) { store.end(id: id, generation: old.generation, now: now) }
            }
            publish()
        }
    }

    /// 打开或关掉“拷贝进度”（实验）。关掉立刻不再订阅；打开后才开始订阅。
    func setCopyProgressEnabled(_ on: Bool) {
        CopyProgressSource.isEnabled = on
        if on { configure(); copies.start() } else {
            copies.stop()
            let now = ProcessInfo.processInfo.systemUptime
            for id in ["source.copy", "owned.copy.done", "owned.copy.failed"] {
                if let old = store.live(id: id) { store.end(id: id, generation: old.generation, now: now) }
            }
            publish()
        }
    }

    private func receiveCopies(_ update: CopyProgressUpdate) {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let summary = update.active {
            let card = CopyCard.copying(summary)
            // 1.5 秒内拷完的不出现；30 秒没进展算过期；收场立即（“拷好了”“没拷完”那一张卡就是最后的样子）。
            put(id: "source.copy", kind: .copy, title: card.title, subtitle: card.subtitle, symbol: card.symbol,
                progress: card.quantity, detail: card.detail, stale: .noProgress, appearAfter: NotchActivityKind.copy.appearAfter,
                closing: .immediate, now: now)
        } else if let old = store.live(id: "source.copy") {
            store.end(id: old.id, generation: old.generation, now: now)
        }
        // 拷好了、没拷完各说一句；用户自己取消的什么都不说。这两张卡本身就是最后的样子（到点自己收），关掉开关时立即收。
        if !update.finished.isEmpty {
            let card = CopyCard.finished(update.finished)
            put(id: "owned.copy.done", kind: .copy, title: card.title, subtitle: card.subtitle, symbol: card.symbol,
                detail: card.detail, expires: now + (card.lifetime ?? 4), closing: .immediate, now: now)
        }
        if let failure = update.failed.first {
            let card = CopyCard.failed(failure)
            put(id: "owned.copy.failed", kind: .copy, title: card.title, subtitle: card.subtitle, symbol: card.symbol,
                detail: card.detail, expires: now + (card.lifetime ?? 6), closing: .immediate, now: now)
        }
        publish()
    }

    private func receiveDownloads(_ update: DownloadUpdate) {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let summary = update.active {
            let card = DownloadCard.downloading(summary)
            // 1.5 秒内下完的不出现；30 秒没进展算过期；收场立即（“下载好了”那一张卡就是最后的样子，留 4 秒）。
            put(id: "source.download", kind: .download, title: card.title, subtitle: card.subtitle,
                symbol: card.symbol, progress: card.quantity, detail: card.detail, stale: .noProgress,
                appearAfter: NotchActivityKind.download.appearAfter, closing: .immediate, now: now)
        } else if let old = store.live(id: "source.download") {
            store.end(id: old.id, generation: old.generation, now: now)
        }
        // 下好了才提示一下；被取消的什么都不说，卡片安静收掉。
        if !update.finished.isEmpty {
            onDownloadsFinished?(update.finished)
            let card = DownloadCard.finished(update.finished)
            put(id: "owned.download.done", kind: .download, title: card.title, subtitle: card.subtitle,
                symbol: card.symbol, detail: card.detail, expires: now + (card.lifetime ?? 4), closing: .immediate, now: now)
        }
        publish()
    }

    /// 一条活动怎么算过期（稿“每一件的生命周期”表）。
    private enum Staleness {
        /// 不会过期。
        case never
        /// 来源说了算（编程会话：最近一次消息 + 120 秒）。
        case at(Double?)
        /// 按种类的 `staleAfter`，从内容最后一次真的变了算起（下载 / 拷贝“30 秒没进展”）。
        /// 只在量得出进展（比例、第 k / n）时才算：不知道总量的下载内容本来就不会变，不能因此说它停了。
        case noProgress
    }

    private func put(id: String, kind: NotchActivityKind, title: String, subtitle: String,
                     symbol: String, progress: NotchActivity.Quantity = .unknown, paused: Bool = false, detail: String = "",
                     trailing: String? = nil, sessionPhase: NotchSessionPhase? = nil, calendar: NotchCalendarFace? = nil,
                     expires: Double? = nil, relevance: Int = 0, stale: Staleness = .never, appearAfter: Double = 0,
                     closing: NotchActivity.Closing? = nil, finalLook: NotchActivity.FinalLook? = nil,
                     now: Double = ProcessInfo.processInfo.systemUptime) {
        // 结束了正留着最后样子的那条不算“上一版”：重新开始换一代。
        let old = store.live(id: id)
        if old == nil { generation += 1 }
        var next = NotchActivity(id: id, generation: old?.generation ?? generation, kind: kind,
                                 title: title, subtitle: subtitle, symbol: symbol,
                                 startedAt: old?.startedAt ?? now, updatedAt: now, expiresAt: expires,
                                 progress: progress, isPaused: paused, detail: detail, trailing: trailing,
                                 sessionPhase: sessionPhase, calendar: calendar, relevance: relevance, appearAfter: appearAfter,
                                 closing: closing ?? kind.closing, finalLook: finalLook)
        // 内容没变（轮询又报了一遍）不算更新：排序里的“最近更新”和“没进展”都只认真的变化。
        let unchanged = old.map { Self.sameContent($0, next) } ?? false
        if unchanged, let old { next.updatedAt = old.updatedAt }
        switch stale {
        case .never: next.staleAt = nil
        case .at(let time): next.staleAt = time
        case .noProgress:
            switch progress {
            case .fraction, .count:
                if unchanged, let kept = old?.staleAt { next.staleAt = kept }
                else { next.staleAt = kind.staleAfter.map { now + $0 } }
            case .indeterminate, .unknown:
                next.staleAt = nil
            }
        }
        store.upsert(next, now: now)
    }

    /// 两版内容一样吗（不看时间）。
    private static func sameContent(_ a: NotchActivity, _ b: NotchActivity) -> Bool {
        a.title == b.title && a.subtitle == b.subtitle && a.symbol == b.symbol && a.progress == b.progress
            && a.isPaused == b.isPaused && a.detail == b.detail && a.trailing == b.trailing
            && a.sessionPhase == b.sessionPhase && a.relevance == b.relevance && a.expiresAt == b.expiresAt
    }

    /// 那一排结束了还没看过的那几件，跟在能露面的后面（稿：结束后那一排里留到看过一次，或 15 分钟）。
    var rowActivities: [NotchActivity] { store.rowActivities }

    /// 那一排被看过一次（展开那一排的人调用）：结束了的不再留在那一排。
    func rowSeen() { store.rowSeen() }

    /// 只按 store 里最早的变化时刻（收掉、过期、过出现门槛、那一排留到的时间）排一次性定时器；什么都没有就不排（F06）。
    private func rescheduleExpiry() {
        expiry?.invalidate(); expiry = nil
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard let delay = IdleTimerPolicy.expiryDelay(nextExpiry: store.nextTransition, now: now) else { return }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.expiry = nil
                self.store.prune(now: ProcessInfo.processInfo.systemUptime)
                self.publish()
            }
        }
        timer.tolerance = IdleTimerPolicy.expiryTolerance
        RunLoop.main.add(timer, forMode: .common)
        expiry = timer
    }

    private func publish() {
        rescheduleExpiry()
        // 耳朵给第一件；人挑过的那件留在耳朵上直到它结束（store.followFirst）。
        store.followFirst()
        let visible = store.visible
        // A poll with unchanged metadata does not cause a compositor transaction.
        func equivalent(_ a: NotchActivity, _ b: NotchActivity) -> Bool {
            a.id == b.id && a.generation == b.generation && a.title == b.title && a.subtitle == b.subtitle
                && a.symbol == b.symbol && a.progress == b.progress && a.isPaused == b.isPaused && a.detail == b.detail
                && a.trailing == b.trailing && a.sessionPhase == b.sessionPhase && a.calendar == b.calendar
                && a.isStale == b.isStale && a.endedAt == b.endedAt && a.relevance == b.relevance
        }
        guard lastVisible.count != visible.count || !zip(lastVisible, visible).allSatisfy({ equivalent($0, $1) })
                || lastSelection != store.selectedID else { return }
        lastVisible = visible; lastSelection = store.selectedID
        onChange?(visible, store.selectedID)
        nowPlayingPresenter?.refresh()
    }

    /// 设置里的“正在播放”开关（默认开）。关掉：音乐的两耳、那一格和大卡一起收；打开：重新对账。
    func setMusicEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: NotchNowPlayingDefaults.musicKey)
        if running { sources.musicSettingChanged() }
    }

    func perform(_ action: NotchActivityAction) {
        guard Self.isEnabled, !suspended else { return }
        configure()
        if action == .timerOpen { countdown.openCard(); return }
        if action == .nowPlayingOpen { onOpenNowPlayingCard?(); return }
        if store.selected?.kind == .calendar {
            switch action {
            case .open: calendar.openCard(); return
            case .join: calendar.joinCurrent(); return
            default: break
            }
        }
        if store.selected?.kind == .timer {
            switch action {
            case .open: countdown.openCard(); return
            case .end: countdown.end(); return
            case .focusTogglePause: countdown.togglePause(); return
            default: break
            }
        }
        if store.selected?.kind == .focus && [.open, .end, .focusTogglePause, .focusSkip].contains(action) {
            ws2FocusAction?(action); return
        }
        switch action {
        case .focusOpen: ws2FocusAction?(.focusOpen)
        case .focusTogglePause, .focusSkip, .timerOpen, .nowPlayingOpen, .join: return
        case .enableMusic: sources.enableMusic()
        case .playPause: sources.musicCommand(.playPause)
        case .previous: sources.musicCommand(.previous)
        case .next: sources.musicCommand(.next)
        case .airDrop: chooseFiles()
        case .route: chooseRoute()
        case .voiceMemos: openApp("com.apple.VoiceMemos")
        case .end:
            guard let selected = store.selected, selected.kind == .route else { return }
            routeEpoch += 1; routeTask?.cancel(); routeTask = nil; routeItems = []
            store.end(id: selected.id, generation: selected.generation, now: ProcessInfo.processInfo.systemUptime)
            publish()
        case .open:
            guard let selected = store.selected else { return }
            switch selected.kind {
            case .focus: return
            case .music: openApp(selected.detail)
            case .recording: openApp("com.apple.VoiceMemos")
            case .route: if !routeItems.isEmpty { MKMapItem.openMaps(with: routeItems, launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]) }
            case .download, .copy, .remote, .calendar, .timer, .shelf: return
            case .session:
                if let target = sessions.target(forActivity: selected.id, at: ProcessInfo.processInfo.systemUptime) { onSessionGo?(target.cwd) }
            case .airPods: NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
            case .airDrop:
                let app = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
                NSWorkspace.shared.openApplication(at: app, configuration: .init())
            }
        }
    }

    private func openApp(_ id: String) {
        guard ["com.apple.Music", "com.spotify.client", "com.apple.VoiceMemos"].contains(id),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func chooseFiles() {
        guard sharing == nil, !choosingFiles else { return }
        choosingFiles = true
        let epoch = operationEpoch
        let picker = NSOpenPanel()
        picker.title = "隔空投送"; picker.prompt = "选择文件"
        picker.allowsMultipleSelection = true; picker.canChooseDirectories = true
        picker.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, self.operationEpoch == epoch else { return }
                self.choosingFiles = false
                guard response == .OK, self.running, !picker.urls.isEmpty else { return }
                self.sendViaAirDrop(items: picker.urls)
            }
        }
    }

    /// 现在有没有一次隔空投送在等（落点小岛据此把“隔空投送”灰掉）。
    var isSharing: Bool { sharing != nil || choosingFiles }

    /// 直接交给系统的隔空投送窗口挑设备（FS-05）。等的时候是一件持续活动：左耳隔空投送，右耳一段不定长的弧
    /// （系统不给进度，不画假进度）；结果说“已送出”或“没送出去”，你自己取消的不说。
    func sendViaAirDrop(items: [Any]) {
        guard Self.isEnabled, !suspended, sharing == nil, !items.isEmpty else { return }
        configure()
        guard running else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items) else {
            put(id: "owned.airDrop", kind: .airDrop, title: "隔空投送", subtitle: "没送出去",
                symbol: "airdrop", expires: ProcessInfo.processInfo.systemUptime + 4)
            publish(); return
        }
        sharing = service; service.delegate = self
        put(id: "owned.airDrop", kind: .airDrop, title: "隔空投送", subtitle: "",
            symbol: "airdrop", progress: .indeterminate, trailing: "")
        publish()
        service.perform(withItems: items)
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard sharing === sharingService else { return }
        finishShare("已送出")
    }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        guard sharing === sharingService else { return }
        // 你自己取消的不说，活动安静地收掉。
        finishShare((error as NSError).code == NSUserCancelledError ? nil : "没送出去")
    }
    private func finishShare(_ text: String?) {
        sharing?.delegate = nil; sharing = nil
        let now = ProcessInfo.processInfo.systemUptime
        if let text {
            put(id: "owned.airDrop", kind: .airDrop, title: "隔空投送", subtitle: text,
                symbol: text == "已送出" ? "checkmark.circle.fill" : "airdrop", expires: now + 4, now: now)
        } else if let old = store.activities.first(where: { $0.id == "owned.airDrop" }) {
            store.end(id: old.id, generation: old.generation, now: now)
        }
        publish()
    }

    private func chooseRoute() {
        let epoch = operationEpoch
        let dialog = NSAlert()
        dialog.messageText = "查看路线"
        dialog.informativeText = "输入出发地和目的地。"
        dialog.addButton(withTitle: "查找路线"); dialog.addButton(withTitle: "取消")
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 66))
        let start = NSTextField(frame: NSRect(x: 0, y: 36, width: 320, height: 26))
        let end = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        start.placeholderString = "出发地"; end.placeholderString = "目的地"
        form.addSubview(start); form.addSubview(end); dialog.accessoryView = form
        // Native modal panels keep the event loop running; no synchronous route I/O here.
        guard dialog.runModal() == .alertFirstButtonReturn else { return }
        let from = start.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = end.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, running, operationEpoch == epoch else { return }
        calculateRoute(from: from, to: to)
    }

    private func calculateRoute(from: String, to: String) {
        routeEpoch += 1
        let epoch = routeEpoch
        routeTask?.cancel(); routeItems = []
        put(id: "owned.route", kind: .route, title: to, subtitle: "正在查找路线", symbol: "map.fill")
        publish()
        routeTask = Task { [weak self] in
            do {
                let first = MKLocalSearch.Request(); first.naturalLanguageQuery = from
                let second = MKLocalSearch.Request(); second.naturalLanguageQuery = to
                let source = try await MKLocalSearch(request: first).start()
                try Task.checkCancellation()
                let destination = try await MKLocalSearch(request: second).start()
                try Task.checkCancellation()
                guard let a = source.mapItems.first, let b = destination.mapItems.first else { throw CocoaError(.fileReadUnknown) }
                let request = MKDirections.Request(); request.source = a; request.destination = b; request.transportType = .automobile
                let directions = try await MKDirections(request: request).calculate()
                try Task.checkCancellation()
                guard let self, self.running, self.routeEpoch == epoch, let route = directions.routes.first else { return }
                self.routeItems = [a, b]
                let minutes = max(1, Int(ceil(route.expectedTravelTime / 60)))
                let distance = String(format: "%.1f 公里", route.distance / 1000)
                self.put(id: "owned.route", kind: .route, title: b.name ?? to,
                         subtitle: "预计 \(minutes) 分钟 · \(distance)", symbol: "car.fill", detail: "在地图中打开路线")
                self.publish()
            } catch {
                guard let self, self.running, self.routeEpoch == epoch, !Task.isCancelled else { return }
                self.put(id: "owned.route", kind: .route, title: to, subtitle: "没能找到路线", symbol: "map.fill",
                         expires: ProcessInfo.processInfo.systemUptime + 6)
                self.publish()
            }
        }
    }
}

/// 紧凑右耳上“在跑”的转圈：一段 270° 的弧，Core Animation 自己转，不起计时器；帧率压在 10…20（首选 15），
/// 文字只在状态变化时才改。系统开了“减弱动态效果”就只画静止的弧。
@MainActor
enum NotchSessionSpinner {
    static let diameter: CGFloat = 12
    static let lineWidth: CGFloat = 2
    static let animationKey = "session.spin"

    static func makeLayer(color: NSColor = .white) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: diameter / 2, y: diameter / 2), radius: (diameter - lineWidth) / 2,
                    startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
        layer.path = path
        layer.fillColor = nil
        layer.strokeColor = color.cgColor
        layer.lineWidth = lineWidth
        layer.lineCap = .round
        return layer
    }

    static func start(_ layer: CALayer) {
        guard !Motion.reduced, layer.animation(forKey: animationKey) == nil else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = NotchSessionEar.spinnerPeriod
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        let rate = NotchSessionEar.spinnerFrameRate
        spin.preferredFrameRateRange = CAFrameRateRange(minimum: rate.minimum, maximum: rate.maximum, preferred: rate.preferred)
        layer.add(spin, forKey: animationKey)
    }

    static func stop(_ layer: CALayer) { layer.removeAnimation(forKey: animationKey) }
}

/// 进度零件的图层（M12）：紧凑右耳和右段的格子共用。比例画环（底环加前景弧，数值更新只改 strokeEnd），
/// 只知道在做就画一段转着的不确定弧（Core Animation 自己转，帧率沿用编程会话转圈的设定），其余什么都不画。
/// 同一种画法下数变了不重排、不重启动画；画法变了才重排一次（`NotchProgressPart.Model` 判断）。
@MainActor
final class NotchProgressPartLayers {
    let root = CALayer()
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let arc = CAShapeLayer()
    private(set) var model = NotchProgressPart.Model()
    private var tone: NotchPanel.Compact.ProgressTone = .playback
    /// 所在视图在窗口里时，不确定弧才转；离开窗口就停。
    private var attached = true

    static let side = CGFloat(NotchProgressPart.ringDiameter)

    init() {
        let side = Self.side
        root.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        root.isHidden = true
        let lineWidth = CGFloat(NotchProgressPart.ringLineWidth)
        let radius = (side - lineWidth) / 2
        let center = CGPoint(x: side / 2, y: side / 2)
        // 从正上方顺时针走。
        let circle = CGMutablePath()
        circle.addArc(center: center, radius: radius, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        let sweep = CGMutablePath()
        sweep.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
        for (layer, path) in [(track, circle), (fill, circle), (arc, sweep)] {
            layer.bounds = root.bounds
            layer.position = CGPoint(x: side / 2, y: side / 2)
            layer.path = path
            layer.fillColor = nil
            layer.lineWidth = lineWidth
            layer.lineCap = .round
            root.addSublayer(layer)
        }
        track.lineCap = .butt
        track.strokeColor = NSColor.white.withAlphaComponent(CGFloat(NotchProgressPart.trackWhiteAlpha)).cgColor
        fill.strokeEnd = 0
        track.isHidden = true; fill.isHidden = true; arc.isHidden = true
        recolor()
    }

    /// 按量更新。返回这一次是不是重排（测试和调试用）。
    @discardableResult
    func apply(_ quantity: NotchActivity.Quantity, tone next: NotchPanel.Compact.ProgressTone) -> NotchProgressPart.Model.Change {
        if next != tone { tone = next; recolor() }
        let change = model.apply(quantity)
        switch change {
        case .none: break
        case .valueOnly: setEnd(quantity)
        case .relayout: relayout(for: quantity)
        }
        return change
    }

    func setAttached(_ on: Bool) {
        attached = on
        syncAnimation()
    }

    private func relayout(for quantity: NotchActivity.Quantity) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        switch quantity.drawing {
        case .ring:
            root.isHidden = false
            track.isHidden = false
            arc.isHidden = true
            setEnd(quantity)
        case .spinningArc:
            root.isHidden = false
            track.isHidden = true; fill.isHidden = true
            arc.isHidden = false
        case .countText, .none:
            root.isHidden = true
            track.isHidden = true; fill.isHidden = true; arc.isHidden = true
        }
        CATransaction.commit()
        syncAnimation()
    }

    private func setEnd(_ quantity: NotchActivity.Quantity) {
        guard let value = quantity.fractionValue, value.isFinite else { return }
        let clamped = CGFloat(min(1, max(0, value)))
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.strokeEnd = clamped
        // 0 时圆头会留一个点：不画。
        fill.isHidden = clamped <= 0
        CATransaction.commit()
    }

    private func syncAnimation() {
        if attached, model.quantity.drawing == .spinningArc { NotchSessionSpinner.start(arc) } else { NotchSessionSpinner.stop(arc) }
    }

    private func recolor() {
        let color: NSColor
        switch tone {
        case .focus: color = .systemRed
        case .timer, .timerPaused: color = NSColor(srgbRed: CountdownTimerStyle.orangeRGB.0, green: CountdownTimerStyle.orangeRGB.1, blue: CountdownTimerStyle.orangeRGB.2, alpha: 1)
        case .calendar, .calendarJoin: color = .systemBlue
        case .playback, .rest: color = .systemGreen
        case .accent: color = .controlAccentColor
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        fill.strokeColor = color.cgColor
        arc.strokeColor = color.cgColor
        CATransaction.commit()
    }
}


// MARK: - 正在播放大卡的数据来源（NP-4）

extension NotchActivityController: NowPlayingCardSource {
    var nowPlayingContent: NowPlayingCardContent? {
        guard let item = store.activities.first(where: { $0.kind == .music }) else { return nil }
        let timeline = sources.nowPlayingTimeline
        let seekable = NowPlayingCardPolicy.isSeekable(streamHealthy: sources.nowPlayingStreamHealthy,
                                                       duration: timeline?.duration, artist: item.subtitle)
        return NowPlayingCardContent(title: item.title, artist: item.subtitle, isPaused: item.isPaused, bundleID: item.detail,
                                     timeline: timeline, seekable: seekable)
    }

    func nowPlayingCommand(_ command: NotchMusicCommand) {
        switch command {
        case .playPause: perform(.playPause)
        case .previous: perform(.previous)
        case .next: perform(.next)
        }
    }

    func nowPlayingSeek(toSeconds seconds: Double) {
        guard Self.isEnabled, !suspended else { return }
        sources.seek(toSeconds: seconds)
    }
}
