import Foundation

/// LV3：两耳的几何（337×33.5 在 185 宽刘海上）、条的拉长、符号分档与设备符号、读屏那一句、全屏可见性判定。
@main struct NotchLevelEarsTests {
    typealias Ears = NotchLevelEars

    static func main() {
        geometry()
        shoulders()
        barLayout()
        stretchedBar()
        symbolOffset()
        volumeSymbols()
        deviceSymbols()
        brightnessAndKeyboardSymbols()
        spoken()
        timing()
        fullScreen()
        print("PASS: notch level ears geometry, symbols and visibility")
    }

    static func close(_ a: Double, _ b: Double, _ note: String = "", line: UInt = #line) {
        precondition(abs(a - b) < 1e-9, "\(note) \(a) vs \(b)", line: line)
    }

    static func geometry() {
        // 稿：刘海 185，两耳各 76，总宽 337；右耳放得下 8 + 54 + 14。
        close(Ears.totalWidth(notchWidth: 185), 337)
        close(Ears.earWidth, Ears.barNotchGap + Ears.barLength + Ears.barOuterInset)
        close(Ears.totalWidth(notchWidth: 180), 332)
    }

    static func shoulders() {
        // 比 34 宽不画肩；紧凑两耳（34）以内仍画。
        precondition(!Ears.drawsShoulders())
        precondition(!Ears.drawsShoulders(earWidth: 35))
        precondition(Ears.drawsShoulders(earWidth: 34))
    }

    static func barLayout() {
        let bar = Ears.bar(slotMinX: 261, slotHeight: 33.5, value: 0.5, stretch: nil)
        close(bar.x, 269)
        close(bar.width, 54)
        close(bar.height, 6)
        close(bar.y, (33.5 - 6) / 2)
        close(bar.fillWidth, 27)
        close(bar.maxX, 323)
        // 右耳 261…337：条右端离外沿 14。
        close(337 - bar.maxX, 14)
        close(Ears.bar(slotMinX: 0, slotHeight: 30, value: 2, stretch: nil).fillWidth, 54, "夹到 1")
        close(Ears.bar(slotMinX: 0, slotHeight: 30, value: -1, stretch: nil).fillWidth, 0, "夹到 0")
        close(Ears.trackAlpha(increasedContrast: false), 0.22)
        close(Ears.trackAlpha(increasedContrast: true), 0.45)
        close(Ears.fillAlpha, 1)
    }

    static func stretchedBar() {
        let upper = NotchLevelStep.stretch(edge: .upper, pushes: 1)!
        let up = Ears.bar(slotMinX: 261, slotHeight: 33.5, value: 1, stretch: upper)
        precondition(up.maxX > 323 && up.x == 269, "100% 再按往外沿拉长")
        close(up.height, 5, "拉着变细到 5")
        close(up.width, 54 + upper.points)
        close(up.fillWidth, 54, "填充不跟着拉")
        let lower = NotchLevelStep.stretch(edge: .lower, pushes: 1)!
        let low = Ears.bar(slotMinX: 261, slotHeight: 33.5, value: 0, stretch: lower)
        precondition(low.x < 269 && abs(low.maxX - 323) < 1e-9, "0% 再按往刘海那侧拉长")
        // 一直顶着：最多 8 点，永远到不了。
        let held = NotchLevelStep.stretch(edge: .upper, pushes: 50)!
        precondition(held.points < 8 && held.points > 7.5)
        precondition(Ears.bar(slotMinX: 261, slotHeight: 33.5, value: 1, stretch: held).width < 62.0)
        // 刘海那侧的 8 点空隙正好够最多拉 8 点。
        precondition(Ears.bar(slotMinX: 261, slotHeight: 33.5, value: 0,
                              stretch: NotchLevelStep.stretch(edge: .lower, pushes: 50)!).x > 261)
    }

    static func symbolOffset() {
        close(Ears.symbolOffset(stretch: nil), 0)
        let upper = NotchLevelStep.stretch(edge: .upper, pushes: 3)!
        close(Ears.symbolOffset(stretch: upper), -upper.points / 4, "往外沿：左耳的外沿在左")
        let lower = NotchLevelStep.stretch(edge: .lower, pushes: 3)!
        close(Ears.symbolOffset(stretch: lower), lower.points / 4, "往刘海：向右")
    }

    static func volumeSymbols() {
        func name(_ v: Double, muted: Bool = false) -> String { Ears.symbolName(kind: .volume, value: v, muted: muted) }
        precondition(name(0) == "speaker.fill")
        precondition(name(0.01) == "speaker.wave.1.fill")
        precondition(name(1.0 / 3.0) == "speaker.wave.1.fill")
        precondition(name(0.34) == "speaker.wave.2.fill")
        precondition(name(2.0 / 3.0) == "speaker.wave.2.fill")
        precondition(name(0.67) == "speaker.wave.3.fill")
        precondition(name(1) == "speaker.wave.3.fill")
        precondition(name(0.8, muted: true) == "speaker.slash.fill", "静音一律斜线，哪怕数值不是 0")
    }

    static func deviceSymbols() {
        func name(_ output: Ears.Output, value: Double = 0.5, muted: Bool = false) -> String {
            Ears.symbolName(kind: .volume, value: value, muted: muted, output: output)
        }
        precondition(name(.airPodsPro) == "airpodspro")
        precondition(name(.airPods) == "airpods")
        precondition(name(.airPodsMax) == "airpodsmax")
        precondition(name(.headphones) == "headphones")
        precondition(name(.airPodsPro, muted: true) == "speaker.slash.fill", "静音仍是带斜线的喇叭")
        precondition(name(.headphones, muted: true) == "speaker.slash.fill")
        precondition(name(.speaker, value: 1) == "speaker.wave.3.fill")
        // 亮度、键盘灯不看设备。
        precondition(Ears.symbolName(kind: .brightness, value: 0.2, muted: false, output: .airPods) == "sun.min.fill")
        // 按设备名分。
        precondition(Ears.Output.classify(name: "Aaron 的 AirPods Pro", isHeadphoneTransport: true) == .airPodsPro)
        precondition(Ears.Output.classify(name: "AirPods Max", isHeadphoneTransport: true) == .airPodsMax)
        precondition(Ears.Output.classify(name: "Aaron's AirPods", isHeadphoneTransport: true) == .airPods)
        precondition(Ears.Output.classify(name: "WH-1000XM5", isHeadphoneTransport: true) == .headphones)
        precondition(Ears.Output.classify(name: "外置耳机", isHeadphoneTransport: true) == .headphones)
        precondition(Ears.Output.classify(name: "MacBook Air 扬声器", isHeadphoneTransport: false) == .speaker)
        precondition(Ears.Output.classify(name: nil, isHeadphoneTransport: false) == .speaker)
    }

    static func brightnessAndKeyboardSymbols() {
        precondition(Ears.symbolName(kind: .brightness, value: 0.49, muted: false) == "sun.min.fill")
        precondition(Ears.symbolName(kind: .brightness, value: 0.5, muted: false) == "sun.max.fill")
        precondition(Ears.symbolName(kind: .keyboardLight, value: 0, muted: false) == "light.min")
        precondition(Ears.symbolName(kind: .keyboardLight, value: 0.3, muted: false) == "light.min")
        precondition(Ears.symbolName(kind: .keyboardLight, value: 0.5, muted: false) == "light.max")
    }

    static func spoken() {
        precondition(Ears.spokenText(kind: .volume, value: 0.45, muted: false) == "音量 45%")
        precondition(Ears.spokenText(kind: .volume, value: 0.45, muted: true) == "静音")
        precondition(Ears.spokenText(kind: .brightness, value: 0.7, muted: false) == "亮度 70%")
        precondition(Ears.spokenText(kind: .keyboardLight, value: 0.4, muted: false) == "键盘灯 40%")
        precondition(Ears.spokenText(kind: .volume, value: 3, muted: false) == "音量 100%")
    }

    static func timing() {
        close(Ears.holdSeconds, 1.2)
        close(Ears.announceDelay, 0.5)
        close(Ears.reducedFlashFrom, 0.6)
        close(Ears.reducedFlashSeconds, 0.25)
    }

    static func fullScreen() {
        typealias FS = NotchLevelSuppression.FullScreen
        // 三项都确认才算看得见；查不到（nil）一律不出。
        precondition(Ears.fullScreenVisibility(panelVisible: true, onActiveSpace: true, occlusionVisible: true) == .visible)
        precondition(Ears.fullScreenVisibility(panelVisible: true, onActiveSpace: false, occlusionVisible: true) == .notVisible)
        precondition(Ears.fullScreenVisibility(panelVisible: true, onActiveSpace: true, occlusionVisible: false) == .notVisible)
        precondition(Ears.fullScreenVisibility(panelVisible: false, onActiveSpace: true, occlusionVisible: true) == .notVisible)
        precondition(Ears.fullScreenVisibility(panelVisible: true, onActiveSpace: nil, occlusionVisible: true) == .notVisible)
        precondition(Ears.fullScreenVisibility(panelVisible: true, onActiveSpace: true, occlusionVisible: nil) == .notVisible)
        // 没让开：照常画。
        precondition(Ears.mayDraw(yielding: false, missionControl: nil, fullScreen: .notVisible))
        // 全屏里面板可见：出；调度中心：不出；调度中心查不到：不出；全屏里看不见：不出。
        precondition(Ears.mayDraw(yielding: true, missionControl: false, fullScreen: FS.visible))
        precondition(!Ears.mayDraw(yielding: true, missionControl: true, fullScreen: FS.visible))
        precondition(!Ears.mayDraw(yielding: true, missionControl: nil, fullScreen: FS.visible))
        precondition(!Ears.mayDraw(yielding: true, missionControl: false, fullScreen: FS.notVisible))
        precondition(!Ears.mayDraw(yielding: true, missionControl: false, fullScreen: FS.no))
    }
}
