import Foundation

/// LV1：《音量与亮度》稿“什么时候拦键”判定表，每行一条；再加几条先后顺序和写回失败。
@main struct NotchLevelSuppressionTests {
    typealias S = NotchLevelSuppression

    static func main() {
        row01_ready()
        row02_fullScreen()
        row03_missionControl()
        row04_locked()
        row05_release()
        row06_outputNotAdjustable()
        row07_externalBrightness()
        row08_keyboardLightUnavailable()
        row09_modifiers()
        row10_foreignHUD()
        row11_noAccessibility()
        row12_versionNotVerified()
        row13_writeMismatch()
        row14_paused()
        row15_processGone()
        settingOffAndGesture()
        precedence()
        print("PASS: notch level suppression table (15 rows)")
    }

    static func decision(_ kind: NotchLevelKind = .volume, _ edit: (inout S.Input) -> Void = { _ in }) -> S.Decision {
        var input = S.Input()
        edit(&input)
        return S().decide(kind, input)
    }

    static func expect(_ d: S.Decision, _ action: S.Action, _ writer: S.Writer, _ visible: S.Visible, _ reason: S.Reason,
                       _ note: String, line: UInt = #line) {
        precondition(d == S.Decision(action: action, writer: writer, visible: visible, reason: reason),
                     "\(note): got \(d)", line: line)
    }

    // 1 已允许、版本核对过、扬声器或耳机能调 → 拦，我们写，只有刘海。三种键都一样。
    static func row01_ready() {
        for kind in [NotchLevelKind.volume, .brightness, .keyboardLight] {
            expect(decision(kind), .intercept, .us, .notchOnly, .ready, "row 1 \(kind)")
        }
        precondition(decision().notchDraws && decision().intercepts)
    }

    // 2 原生全屏且面板可见 → 拦；看不见 → 按调度中心那一行处理。
    static func row02_fullScreen() {
        expect(decision { $0.fullScreen = .visible }, .intercept, .us, .notchOnly, .fullScreenVisible, "row 2 visible")
        expect(decision { $0.fullScreen = .notVisible }, .passThrough, .system, .systemOnly, .fullScreenNotVisible,
               "row 2 not visible")
    }

    // 3 调度中心 → 不拦，系统，只有系统。
    static func row03_missionControl() {
        let d = decision { $0.missionControl = true }
        expect(d, .passThrough, .system, .systemOnly, .missionControl, "row 3")
        precondition(!d.notchDraws)
    }

    // 4 锁屏、登录窗口、屏保。
    static func row04_locked() {
        expect(decision { $0.locked = true }, .passThrough, .system, .systemOnly, .locked, "row 4")
    }

    // 5 刷脸解锁中、等你批准（放行在交互之上）。
    static func row05_release() {
        expect(decision { $0.authorizationRelease = true }, .passThrough, .system, .systemOnly, .authorizationRelease, "row 5")
    }

    // 6 输出不能调音量（HDMI / DP、部分 USB 声卡、多输出设备）：拦了键就失灵，不拦。
    static func row06_outputNotAdjustable() {
        expect(decision(.volume) { $0.deviceAdjustable = false }, .passThrough, .system, .systemOnly,
               .outputNotAdjustable, "row 6")
        // 音量不能调不连累亮度。
        expect(decision(.brightness) { _ in }, .intercept, .us, .notchOnly, .ready, "row 6 brightness unaffected")
    }

    // 7 亮度要调的是外接屏：不拦，不做 DDC。
    static func row07_externalBrightness() {
        expect(decision(.brightness) { $0.brightnessTargetsExternal = true }, .passThrough, .system, .systemOnly,
               .externalDisplay, "row 7")
        // 这个标志只管亮度。
        expect(decision(.volume) { $0.brightnessTargetsExternal = true }, .intercept, .us, .notchOnly, .ready,
               "row 7 volume ignores it")
        expect(decision(.brightness) { $0.deviceAdjustable = false }, .passThrough, .system, .systemOnly,
               .brightnessNotAdjustable, "row 7 no built-in display")
    }

    // 8 读不到键盘灯（没有背光、接口不在）。
    static func row08_keyboardLightUnavailable() {
        expect(decision(.keyboardLight) { $0.deviceAdjustable = false }, .passThrough, .system, .systemOnly,
               .keyboardLightUnavailable, "row 8")
    }

    // 9 按着 ⌥、⇧ 或 ⌃（不是 ⌥⇧）不拦；只有 ⌥⇧ 细调由我们接。
    static func row09_modifiers() {
        expect(decision { $0.modifiers = .other }, .passThrough, .system, .systemOnly, .otherModifiers, "row 9 other")
        expect(decision { $0.modifiers = .optionShift }, .intercept, .us, .notchOnly, .ready, "row 9 option-shift")
        expect(decision { $0.modifiers = .none }, .intercept, .us, .notchOnly, .ready, "row 9 none")
    }

    // 10 Alcove、MediaMate 在运行：让位，对方写，对方的提示；我们也不画。
    static func row10_foreignHUD() {
        let d = decision { $0.foreignHUDRunning = true }
        expect(d, .passThrough, .other, .otherApp, .foreignHUD, "row 10")
        precondition(!d.notchDraws)
    }

    // 11 没允许辅助功能：只旁听，系统写，两个都在。
    static func row11_noAccessibility() {
        let d = decision { $0.listener = .listenOnly }
        expect(d, .passThrough, .system, .both, .noAccessibility, "row 11")
        precondition(d.notchDraws, "旁听时刘海照画")
    }

    // 12 这个 macOS 版本没核对过：只旁听，两个都在。
    static func row12_versionNotVerified() {
        expect(decision { $0.versionVerified = false }, .passThrough, .system, .both, .versionNotVerified, "row 12")
    }

    // 13 写进去读回来不对：这一下已拦 → 原样补发；这一类键本次开机不再拦，别的类不受影响。
    static func row13_writeMismatch() {
        var s = S()
        let input = S.Input()
        expect(s.decide(.volume, input), .intercept, .us, .notchOnly, .ready, "row 13 first press intercepted")
        precondition(s.wrote(.volume, .matched) == .done)
        expect(s.decide(.volume, input), .intercept, .us, .notchOnly, .ready, "row 13 matched keeps intercepting")
        precondition(s.wrote(.volume, .mismatched) == .reissueToSystem, "写错了补发给系统")
        expect(s.decide(.volume, input), .passThrough, .system, .both, .writeFailedEarlier, "row 13 later presses")
        expect(s.decide(.brightness, input), .intercept, .us, .notchOnly, .ready, "row 13 other kinds unaffected")
        expect(s.decide(.keyboardLight, input), .intercept, .us, .notchOnly, .ready, "row 13 keyboard light unaffected")
    }

    // 14 监听被系统暂停：暂停期间不拦，两个都在。
    static func row14_paused() {
        expect(decision { $0.listener = .paused }, .passThrough, .system, .both, .listenerPaused, "row 14")
    }

    // 15 WindowShade 崩溃或被强制退出：监听跟着进程没了，下一下就是系统的提示。
    static func row15_processGone() {
        expect(S.processGone, .passThrough, .system, .systemOnly, .processGone, "row 15")
        precondition(!S.processGone.notchDraws && !S.processGone.intercepts)
    }

    // 设置关、手势层先来的手势：不在 15 行里，但稿里写了。
    static func settingOffAndGesture() {
        expect(decision { $0.settingEnabled = false }, .passThrough, .system, .systemOnly, .settingOff, "setting off")
        expect(decision { $0.gestureInFlight = true }, .passThrough, .system, .systemOnly, .gestureInFlight, "gesture")
        // R12 改回用系统的提示：能拦的情形下也不拦；系统的提示照出，刘海跟着画；三类键都一样。
        for kind in [NotchLevelKind.volume, .brightness, .keyboardLight] {
            let d = decision(kind) { $0.useSystemPopups = true }
            expect(d, .passThrough, .system, .both, .systemPopups, "system popups \(kind)")
            precondition(d.notchDraws && !d.intercepts, "system popups \(kind): 不拦，刘海跟着画")
        }
        // 默认（没开）还是拦：行为不变。
        expect(decision { _ in }, .intercept, .us, .notchOnly, .ready, "default unchanged")
        // 总开关关着比它先判，原因仍是 settingOff。
        expect(decision { $0.settingEnabled = false; $0.useSystemPopups = true }, .passThrough, .system, .systemOnly, .settingOff, "setting off first")
    }

    // 几条同时成立时谁先赢。
    static func precedence() {
        // 锁屏压过一切别的理由，包括对方 App：锁屏归系统。
        expect(decision { $0.locked = true; $0.foreignHUDRunning = true; $0.listener = .listenOnly },
               .passThrough, .system, .systemOnly, .locked, "locked beats foreign HUD")
        // 放行在交互之上：全屏可见也不拦。
        expect(decision { $0.authorizationRelease = true; $0.fullScreen = .visible },
               .passThrough, .system, .systemOnly, .authorizationRelease, "release beats fullscreen")
        // 设备不能调，比没权限更早说：HDMI 时系统要画它自己的“不能调”。
        expect(decision { $0.deviceAdjustable = false; $0.listener = .listenOnly },
               .passThrough, .system, .systemOnly, .outputNotAdjustable, "unadjustable beats listen-only")
        // 只旁听时全屏可见：不拦，但刘海照画（两个都在）。
        let d = decision { $0.listener = .listenOnly; $0.fullScreen = .visible }
        expect(d, .passThrough, .system, .both, .noAccessibility, "listen-only in fullscreen")
        // ⌥⇧ 在只旁听时不改变结论。
        expect(decision { $0.listener = .listenOnly; $0.modifiers = .optionShift },
               .passThrough, .system, .both, .noAccessibility, "option-shift while listen-only")
    }
}
