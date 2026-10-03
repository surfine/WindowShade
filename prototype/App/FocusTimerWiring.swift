import Cocoa

/// T2：App 里唯一的番茄钟宿主。
///
/// 它只做三件事：把连续时钟和日历喂给 T1 的模型、把模型变化推给刘海、把刘海的动作转回模型。
/// 「收进聊天 / 全部收进刘海 / 放回」属于 T3：本轮只在 effects 里登记，不假装已经接线。
@MainActor
final class FocusTimerRuntime {
    private let clock = WS2ContinuousClock()
    private let bootID = UUID()
    private let preset: FocusTimer.Preset
    private let tuckChatEnabled: Bool
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// 模型变化时回调：当前模型与采样时刻。宿主只在 MainActor 上调用它。
    var onChange: ((FocusTimer, WS2.Instant) -> Void)?
    /// 还没接线的效果按顺序记下来，供 T3 接线时取用；不丢弃、也不假装做过。
    private(set) var pendingEffects: [FocusTimer.Effect] = []

    private lazy var host: FocusTimerHost = {
        let timerHost = FocusTimerHost(
            model: FocusTimer(bootID: bootID, preset: preset, tuckChatEnabled: tuckChatEnabled),
            clock: clock,
            calendarSample: { [weak self] now, deadline in
                self?.sample(now: now, deadline: deadline)
                    ?? FocusTimer.CalendarSample(today: "", deadlineDay: "")
            },
            effects: { [weak self] effects in self?.receive(effects) })
        timerHost.onChange = { [weak self] model, now in self?.onChange?(model, now) }
        return timerHost
    }()

    init(preset: FocusTimer.Preset = .minutes25, tuckChatEnabled: Bool = false) {
        self.preset = preset
        self.tuckChatEnabled = tuckChatEnabled
    }

    var model: FocusTimer { host.model }
    var isRunning: Bool { host.model.phase != .idle }

    /// 现在几点了（宿主自己的连续时钟）。
    func now() -> WS2.Instant { clock.now() }

    /// 刘海那一排末尾的 `timer` 按钮和卡片按钮都走这里。
    func perform(_ action: NotchActivityAction) {
        switch action {
        case .focusStart:
            switch host.model.phase {
            case .idle: host.handle(.start)
            default: if host.model.isPaused { host.handle(.resume) }
            }
        case .focusPause:
            host.handle(host.model.isPaused ? .resume : .pause)
        case .focusSkip: host.handle(.skip)
        case .focusEnd: host.handle(.end)
        default: break
        }
    }

    /// 刘海里展开还是收着：决定下一次醒来是整分钟还是按秒。
    func presentation(_ value: FocusTimer.Presentation) {
        guard host.presentation != value else { return }
        host.presentation = value
    }

    func systemLockChanged(_ locked: Bool) { host.handle(locked ? .locked : .unlocked) }
    func systemSleepChanged(_ sleeping: Bool) { host.handle(sleeping ? .sleep : .wake) }

    private func receive(_ effects: [FocusTimer.Effect]) {
        pendingEffects.append(contentsOf: effects)
        for effect in effects {
            switch effect {
            case .fault(let fault):
                wlog("focus timer fault: \(fault.rawValue)")
            case .sound, .tuckChat, .tuckAll, .restoreChat, .restoreAll:
                // T3：窗口动作与提示音还没接线，先只登记。
                break
            }
        }
    }

    /// 今天与旧截止时刻各自的本地自然日。截止是连续时钟上的点，换算成墙上时间只为记“今天第几个”。
    private func sample(now: WS2.Instant, deadline: WS2.Instant?) -> FocusTimer.CalendarSample {
        let wallNow = Date()
        let today = dayFormatter.string(from: wallNow)
        guard let deadline, deadline > now else { return .init(today: today, deadlineDay: today) }
        let remaining = Double(deadline.elapsed(since: now)) / 1_000_000_000
        return .init(today: today, deadlineDay: dayFormatter.string(from: wallNow.addingTimeInterval(remaining)))
    }
}

extension AppDelegate {
    /// 启动时接一次：动作、状态变化、锁屏与睡眠。刘海没开也照样能跑，只是没有地方显示。
    @MainActor
    func startFocusTimerWiring() {
        let timer = focusTimer
        notch.activities.onFocusAction = { [weak self] action in self?.focusTimer.perform(action) }
        timer.onChange = { [weak self] model, now in self?.publishFocus(model, now: now) }
        let workspace = NSWorkspace.shared.notificationCenter
        focusObservers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusTimer.systemSleepChanged(true) }
        })
        focusObservers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusTimer.systemSleepChanged(false) }
        })
        let distributed = DistributedNotificationCenter.default()
        focusObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusTimer.systemLockChanged(true) }
        })
        focusObservers.append(distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusTimer.systemLockChanged(false) }
        })
        publishFocus(timer.model, now: timer.now())
    }

    /// 把番茄钟现在的状态推给刘海：空闲时结束那条活动。
    @MainActor
    func publishFocus(_ model: FocusTimer, now: WS2.Instant) {
        guard model.phase != .idle else {
            notch.activities.setFocus(nil)
            return
        }
        let total = model.phase == .rest ? model.preset.rest : model.preset.focus
        let remaining = model.remaining(at: now)
        let fraction = total == 0 ? 0 : 1 - Double(remaining) / Double(total)
        let startedSeconds = ProcessInfo.processInfo.systemUptime - Double(total - remaining) / 1_000_000_000
        let item = NotchActivity(id: "focus", kind: .focus,
                                 title: model.compactText(at: now),
                                 subtitle: model.phase == .rest ? "看看远处" : "今天第 \(max(1, model.completedToday + 1)) 个",
                                 symbol: "timer",
                                 startedAt: max(0, startedSeconds),
                                 updatedAt: ProcessInfo.processInfo.systemUptime,
                                 progress: min(1, max(0, fraction)),
                                 isPaused: model.isPaused,
                                 detail: model.expandedText(at: now))
        notch.activities.setFocus(item)
    }
}
