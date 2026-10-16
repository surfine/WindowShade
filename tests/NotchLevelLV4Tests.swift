import Foundation

/// LV4：音量亮度的门闸接判定表（全屏可见才出两耳、调度中心不出）、输出设备分类（AirPods / 耳机 / 内建）、
/// 设置那一行的三种副标题与“允许…”的 2 分钟等待。纯逻辑，不碰 AppKit、Core Audio。
@main struct NotchLevelLV4Tests {
    static func main() {
        screenMapping()
        gateAndTable()
        transport()
        outputs()
        settingRow()
        settingDefault()
        allowWatch()
        print("PASS: notch level gate, output classification and settings row")
    }

    // MARK: 全屏、调度中心

    static func screenMapping() {
        typealias S = NotchLevelScreen
        precondition(S.suppressionFullScreen(isFullScreen: false, panelVisibility: .visible) == .no, "不是全屏就是 no")
        precondition(S.suppressionFullScreen(isFullScreen: false, panelVisibility: .notVisible) == .no)
        precondition(S.suppressionFullScreen(isFullScreen: true, panelVisibility: .visible) == .visible)
        precondition(S.suppressionFullScreen(isFullScreen: true, panelVisibility: .notVisible) == .notVisible)
        precondition(S.suppressionFullScreen(isFullScreen: true, panelVisibility: .no) == .notVisible, "没确认过可见按看不见")
        precondition(S.suppressionFullScreen(isFullScreen: nil, panelVisibility: .visible) == .notVisible, "查不到按看不见")
    }

    static func decide(isFullScreen: Bool?, missionControl: Bool?, visibility: NotchLevelSuppression.FullScreen,
                       tweak: (inout NotchLevelSuppression.Input) -> Void = { _ in }) -> NotchLevelSuppression.Decision {
        var input = NotchLevelSuppression.Input()
        NotchLevelScreen.apply(to: &input, isFullScreen: isFullScreen, missionControl: missionControl, panelVisibility: visibility)
        tweak(&input)
        return NotchLevelSuppression().decide(.volume, input)
    }

    static func gateAndTable() {
        // 老门闸：全屏不再挡（交给判定表和面板可见性），锁屏、调度中心照挡。
        var gate = NotchLevelGate(keysAvailable: true)
        precondition(gate.keyPressed(.volumeUp, at: 1, context: NotchLevelScreen.gateContext(locked: false, missionControl: false)) == .show)
        precondition(gate.keyPressed(.volumeUp, at: 2, context: NotchLevelScreen.gateContext(locked: true, missionControl: false)) == .ignore(.locked))
        precondition(gate.keyPressed(.volumeUp, at: 3, context: NotchLevelScreen.gateContext(locked: false, missionControl: true)) == .ignore(.missionControl))
        precondition(NotchLevelScreen.gateContext(locked: false, missionControl: false).fullScreen == false)

        // 全屏而且面板可见：拦，两耳在刘海上（只有我们）。
        let visible = decide(isFullScreen: true, missionControl: false, visibility: .visible)
        precondition(visible.intercepts && visible.reason == .fullScreenVisible && visible.notchDraws && visible.visible == .notchOnly)
        // 全屏但面板看不见、或者全屏状态都查不到：不拦，系统的提示照出。
        let hidden = decide(isFullScreen: true, missionControl: false, visibility: .notVisible)
        precondition(!hidden.intercepts && hidden.reason == .fullScreenNotVisible && hidden.visible == .systemOnly)
        let unknown = decide(isFullScreen: nil, missionControl: false, visibility: .visible)
        precondition(!unknown.intercepts && unknown.reason == .fullScreenNotVisible)
        // 调度中心开着：不拦，不画；全屏可见也一样（调度中心先赢）。
        let mission = decide(isFullScreen: true, missionControl: true, visibility: .visible)
        precondition(!mission.intercepts && mission.reason == .missionControl && !mission.notchDraws)
        // 调度中心读不到当没开。
        precondition(decide(isFullScreen: false, missionControl: nil, visibility: .no).reason == .ready)
        // 普通桌面：拦。
        precondition(decide(isFullScreen: false, missionControl: false, visibility: .no).intercepts)
        // 设置关了：什么都不拦（先于全屏）。
        let off = decide(isFullScreen: true, missionControl: false, visibility: .visible) { $0.settingEnabled = false }
        precondition(!off.intercepts && off.reason == .settingOff)
        // 版本没核对过：全屏可见也不拦，两个提示都在（默认：版本表为空）。
        let unverified = decide(isFullScreen: true, missionControl: false, visibility: .visible) { $0.versionVerified = false }
        precondition(!unverified.intercepts && unverified.reason == .versionNotVerified && unverified.visible == .both)
        // 全屏两耳的可见性事实：和 NotchLevelEars 的判定对得上。
        precondition(NotchLevelEars.fullScreenVisibility(panelVisible: true, onActiveSpace: true, occlusionVisible: true) == .visible)
        precondition(NotchLevelEars.fullScreenVisibility(panelVisible: true, onActiveSpace: nil, occlusionVisible: true) == .notVisible)
        precondition(NotchLevelEars.mayDraw(yielding: true, missionControl: false, fullScreen: .visible))
        precondition(!NotchLevelEars.mayDraw(yielding: true, missionControl: true, fullScreen: .visible))
        precondition(!NotchLevelEars.mayDraw(yielding: true, missionControl: false, fullScreen: .notVisible))
    }

    // MARK: 输出设备

    static func fourCC(_ text: String) -> UInt32 { NotchLevelTransport.fourCC(text) }

    static func transport() {
        precondition(NotchLevelTransport(code: fourCC("bltn")) == .builtIn)
        precondition(NotchLevelTransport(code: fourCC("blue")) == .bluetooth)
        precondition(NotchLevelTransport(code: fourCC("blea")) == .bluetooth)
        precondition(NotchLevelTransport(code: fourCC("usb ")) == .usb)
        precondition(NotchLevelTransport(code: fourCC("hdmi")) == .hdmi)
        precondition(NotchLevelTransport(code: fourCC("dprt")) == .displayPort)
        precondition(NotchLevelTransport(code: fourCC("airp")) == .airPlay)
        precondition(NotchLevelTransport(code: fourCC("virt")) == .virtual)
        precondition(NotchLevelTransport(code: fourCC("xxxx")) == .other)
        precondition(NotchLevelTransport(code: nil) == .unknown)
    }

    static func outputs() {
        typealias O = NotchLevelEars.Output
        // AirPods 系列按型号名各取各的，不管传输方式。
        precondition(O.classify(name: "Aaron’s AirPods Pro", transport: .bluetooth) == .airPodsPro)
        precondition(O.classify(name: "Aaron’s AirPods Max", transport: .bluetooth) == .airPodsMax)
        precondition(O.classify(name: "Aaron’s AirPods", transport: .bluetooth) == .airPods)
        precondition(O.classify(name: "AirPods Pro", transport: .unknown) == .airPodsPro)
        // 内建扬声器；耳机口插着（数据源 hdpn）变耳机，名字不变。
        precondition(O.classify(name: "MacBook Air Speakers", transport: .builtIn) == .speaker)
        precondition(O.classify(name: "MacBook Air Speakers", transport: .builtIn, dataSource: fourCC("ispk")) == .speaker)
        precondition(O.classify(name: "MacBook Air Speakers", transport: .builtIn, dataSource: O.headphoneJackSource) == .headphones)
        precondition(O.classify(name: nil, transport: .builtIn, dataSource: O.headphoneJackSource) == .headphones)
        // 只有内建输出的数据源才算耳机口。
        precondition(O.classify(name: "Studio DAC", transport: .usb, dataSource: O.headphoneJackSource) == .speaker)
        // 其它蓝牙耳机是耳机，蓝牙音箱不是。
        precondition(O.classify(name: "WH-1000XM5", transport: .bluetooth) == .headphones)
        precondition(O.classify(name: "Beats Studio Buds", transport: .bluetooth) == .headphones)
        precondition(O.classify(name: "JBL Flip Speaker", transport: .bluetooth) == .speaker)
        precondition(O.classify(name: "小米音箱", transport: .bluetooth) == .speaker)
        // USB / HDMI / 隔空播放 / 读不到：扬声器；USB 耳机按名字认。
        precondition(O.classify(name: "USB Audio", transport: .usb) == .speaker)
        precondition(O.classify(name: "Logitech USB Headset", transport: .usb) == .headphones)
        precondition(O.classify(name: "C27F390", transport: .hdmi) == .speaker)
        precondition(O.classify(name: "Living Room", transport: .airPlay) == .speaker)
        precondition(O.classify(name: nil, transport: .unknown) == .speaker)
        // 设备符号：扬声器沿用分档，其余换设备符号；静音仍是斜线喇叭。
        precondition(NotchLevelEars.symbolName(kind: .volume, value: 0.5, muted: false, output: .airPodsPro) == "airpodspro")
        precondition(NotchLevelEars.symbolName(kind: .volume, value: 0.5, muted: false, output: .headphones) == "headphones")
        precondition(NotchLevelEars.symbolName(kind: .volume, value: 0.5, muted: true, output: .airPodsMax) == "speaker.slash.fill")
        precondition(NotchLevelEars.symbolName(kind: .brightness, value: 0.8, muted: false, output: .airPodsMax)
                     == NotchLevelStep.tier(kind: .brightness, value: 0.8).symbolName)
    }

    // MARK: 设置那一行

    static func settingRow() {
        typealias R = NotchLevelSettingRow
        // 平时。
        let normal = R.make(accessibilityTrusted: true, versionVerified: true)
        precondition(normal.subtitle == "按音量、亮度键时显示" && normal.allowButton == nil && normal.info == R.normalInfo)
        // 没允许辅助功能：副标题说系统的提示也会出现，带“允许…”。
        let missing = R.make(accessibilityTrusted: false, versionVerified: true)
        precondition(missing.subtitle == "系统的提示也会出现" && missing.allowButton == "允许…" && missing.info == R.missingInfo)
        // 版本没核对过：副标题不变，ⓘ 说版本；没允许时仍带按钮，但不再说“就会藏起来”。
        let unverified = R.make(accessibilityTrusted: true, versionVerified: false)
        precondition(unverified.subtitle == "按音量、亮度键时显示" && unverified.allowButton == nil
                     && unverified.info == R.unverifiedInfo && unverified.info.contains("还没核对过"))
        let both = R.make(accessibilityTrusted: false, versionVerified: false)
        precondition(both.subtitle == "系统的提示也会出现" && both.allowButton != nil && both.info == R.unverifiedInfo)
        // 每种写法都有 ⓘ，副标题都在一行里放得下（16 字以内）。
        for row in [normal, missing, unverified, both] {
            precondition(!row.info.isEmpty && row.subtitle.count <= 16)
        }
        precondition(R.title == "音量和亮度")
    }

    static func settingDefault() {
        let suite = "NotchLevelLV4Tests.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(!NotchLevelSetting.isEnabled(in: defaults), "1.0.16 真机验过前默认关（ReleaseDefaults）")
        NotchLevelSetting.setEnabled(false, in: defaults)
        precondition(!NotchLevelSetting.isEnabled(in: defaults))
        NotchLevelSetting.setEnabled(true, in: defaults)
        precondition(NotchLevelSetting.isEnabled(in: defaults))
        // R12：没写过这个键就是关；写了再读得回来。
        precondition(!NotchLevelSetting.usesSystemPopups(in: defaults), "改回用系统的提示：默认关")
        NotchLevelSetting.setUsesSystemPopups(true, in: defaults)
        precondition(NotchLevelSetting.usesSystemPopups(in: defaults))
        NotchLevelSetting.setUsesSystemPopups(false, in: defaults)
        precondition(!NotchLevelSetting.usesSystemPopups(in: defaults))
    }

    // MARK: 点“允许…”之后

    static func allowWatch() {
        let watch = NotchLevelAllowWatch(startedAt: 100)
        precondition(NotchLevelAllowWatch.interval == 1 && NotchLevelAllowWatch.limit == 120)
        precondition(watch.step(now: 101, trusted: false, windowInFront: true) == .waiting)
        precondition(watch.step(now: 101, trusted: true, windowInFront: true) == .allowed)
        // 设置窗口不在前台：停下，不查；但已经允许了（回到前台那一次检查）照样认。
        precondition(watch.step(now: 130, trusted: false, windowInFront: false) == .paused)
        precondition(watch.step(now: 130, trusted: true, windowInFront: false) == .allowed)
        // 2 分钟到：不再查（不管前不前台）；最后一刻之前还在等。
        precondition(watch.step(now: 219.9, trusted: false, windowInFront: true) == .waiting)
        precondition(watch.step(now: 220, trusted: false, windowInFront: true) == .expired)
        precondition(watch.step(now: 500, trusted: false, windowInFront: false) == .expired)
    }
}
