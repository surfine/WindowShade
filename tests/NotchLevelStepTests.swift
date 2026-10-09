import Foundation

/// LV1：步长 1/16 与 1/64、落格、夹 0–1、到头次数、橡皮筋拉长、符号分档、键盘灯键与修饰键解析。
@main struct NotchLevelStepTests {
    typealias Step = NotchLevelStep

    static func main() {
        sizes()
        coarseSteps()
        fineSteps()
        snapToGrid()
        edges()
        mutedStep()
        edgeCounter()
        stretch()
        volumeTiers()
        brightnessTiers()
        keyboardTiers()
        modifiers()
        keyEvents()
        legacyParseUnchanged()
        gateKnowsKeyboardLight()
        print("PASS: notch level step, tiers and key event parsing")
    }

    static func close(_ a: Double, _ b: Double, _ note: String = "", line: UInt = #line) {
        precondition(abs(a - b) < 1e-9, "\(note) \(a) vs \(b)", line: line)
    }

    static func sizes() {
        close(Step.coarse, 0.0625)
        close(Step.fine, 0.015625)
        close(Step.size(modifiers: .none), Step.coarse)
        close(Step.size(modifiers: .optionShift), Step.fine)
        // 其它修饰键我们不接，但真走到这里时按普通步长。
        close(Step.size(modifiers: .other), Step.coarse)
        // 条长 54：一格 3.4 点，细调 0.84 点。
        close(54 * Step.coarse, 3.375)
        close(54 * Step.fine, 0.84375)
    }

    static func coarseSteps() {
        close(Step.step(from: 0.5, direction: .up).value, 0.5625)
        close(Step.step(from: 0.5, direction: .down).value, 0.4375)
        close(Step.step(from: 0, direction: .up).value, 0.0625)
        close(Step.step(from: 0.9375, direction: .up).value, 1)
        close(Step.step(from: 1, direction: .down).value, 0.9375)
        // 从 0 连按 16 下正好到 100%，不多不少。
        var v = 0.0
        for _ in 0..<16 { v = Step.step(from: v, direction: .up).value }
        close(v, 1)
        precondition(Step.step(from: v, direction: .up).edge == .upper)
    }

    static func fineSteps() {
        close(Step.step(from: 0.5, direction: .up, modifiers: .optionShift).value, 0.515625)
        close(Step.step(from: 0.5, direction: .down, modifiers: .optionShift).value, 0.484375)
        var v = 0.0
        for _ in 0..<64 { v = Step.step(from: v, direction: .up, modifiers: .optionShift).value }
        close(v, 1)
    }

    static func snapToGrid() {
        // 细调之后再普通按：先落到 1/16 的格上。
        let fine = Step.step(from: 0.5, direction: .up, modifiers: .optionShift).value   // 33/64
        close(Step.step(from: fine, direction: .up).value, 0.5625, "上：落到上一格之上的格")
        close(Step.step(from: fine, direction: .down).value, 0.5, "下：落到下面的格")
        // 31/64 在 1/16 格 7.75 上。
        close(Step.step(from: 31.0 / 64, direction: .up).value, 0.5)
        close(Step.step(from: 31.0 / 64, direction: .down).value, 0.4375)
        // 系统读回来的数带一点误差，仍算在格上，不多走也不少走。
        close(Step.step(from: 0.5 + 1e-8, direction: .up).value, 0.5625)
        close(Step.step(from: 0.5 - 1e-8, direction: .down).value, 0.4375)
        // 任意读到的数：走完一定落在格上。
        for raw in stride(from: 0.013, to: 1.0, by: 0.0371) {
            for mods in [NotchLevelModifiers.none, .optionShift] {
                for dir in [Step.Direction.up, .down] {
                    let r = Step.step(from: raw, direction: dir, modifiers: mods)
                    let cells = r.value / Step.size(modifiers: mods)
                    precondition(abs(cells - cells.rounded()) < 1e-9, "\(raw) \(dir) not on grid: \(r.value)")
                    precondition(r.value >= 0 && r.value <= 1)
                }
            }
        }
        // 超出范围的读数先夹住。
        close(Step.step(from: 1.4, direction: .down).value, 0.9375)
        close(Step.step(from: -0.2, direction: .up).value, 0.0625)
    }

    static func edges() {
        let top = Step.step(from: 1, direction: .up)
        precondition(top.edge == .upper && !top.changed)
        close(top.value, 1)
        let bottom = Step.step(from: 0, direction: .down)
        precondition(bottom.edge == .lower && !bottom.changed)
        close(bottom.value, 0)
        // 差一格到头：这一下走到头，不算“顶到头”；再按才算。
        let arrive = Step.step(from: 0.9375, direction: .up)
        precondition(arrive.changed && arrive.edge == nil)
        close(arrive.value, 1)
        // 在头上往回按是正常走。
        precondition(Step.step(from: 1, direction: .down).edge == nil)
        precondition(Step.step(from: 0, direction: .up).edge == nil)
        // 细调同样：差 1/64 走到 0，再按到头。
        let fineArrive = Step.step(from: 1.0 / 64, direction: .down, modifiers: .optionShift)
        precondition(fineArrive.changed && fineArrive.edge == nil)
        precondition(Step.step(from: fineArrive.value, direction: .down, modifiers: .optionShift).edge == .lower)
    }

    static func mutedStep() {
        // 静音时按音量 +/−：先取消静音再走一格。
        let up = Step.step(from: 0.5, direction: .up, muted: true)
        precondition(up.unmutes)
        close(up.value, 0.5625)
        precondition(!Step.step(from: 0.5, direction: .up).unmutes)
    }

    static func edgeCounter() {
        var counter = Step.EdgeCounter()
        let hit = Step.step(from: 1, direction: .up)
        let normal = Step.step(from: 0.5, direction: .up)
        precondition(counter.record(normal, at: 0) == 0)
        // 按住往同一头顶：1、2、3…
        precondition(counter.record(hit, at: 1.00) == 1)
        precondition(counter.record(hit, at: 1.38) == 2, "按住第一次连发在 0.38 秒后")
        precondition(counter.record(hit, at: 1.47) == 3)
        // 隔得久了从头数（窗口 0.6 秒）。
        precondition(counter.record(hit, at: 3.0) == 1)
        // 换到另一头从头数。
        precondition(counter.record(Step.step(from: 0, direction: .down), at: 3.1) == 1)
        // 中间走了正常的一下，清零。
        precondition(counter.record(normal, at: 3.2) == 0 && counter.count == 0)
        precondition(counter.record(hit, at: 3.3) == 1)
        counter.reset()
        precondition(counter.count == 0)
    }

    static func stretch() {
        precondition(Step.stretch(edge: .upper, pushes: 0) == nil)
        precondition(Step.stretch(edge: .upper, pushes: -1) == nil)
        var previous = 0.0
        for n in 1...200 {
            let s = Step.stretch(edge: .upper, pushes: n)!
            precondition(s.points > previous, "越顶越长")
            precondition(s.points < Step.maxStretch, "最多 8 点，永远到不了")
            close(s.thickness, 5)
            close(s.symbolShift, s.points / 4, "符号挪 ¼")
            previous = s.points
        }
        // 公式：x·d·c / (d + c·x)，d = 8，c = 0.55。
        let one = Step.stretch(edge: .lower, pushes: 1)!
        close(one.points, 8.0 * 8 * 0.55 / (8 + 0.55 * 8))
        precondition(one.edge == .lower)
        precondition(one.points > 2 && one.points < 4, "按一下就看得出来")
        precondition(Step.stretch(edge: .upper, pushes: 200)!.points > 7.5, "一直顶着逼近 8")
        close(Step.barThickness, 6)
    }

    static func volumeTiers() {
        precondition(Step.volumeTier(0, muted: false) == .volumeZero)
        precondition(Step.volumeTier(0.0625, muted: false) == .volumeLow)
        precondition(Step.volumeTier(1.0 / 3.0, muted: false) == .volumeLow, "≤ ⅓ 含 ⅓")
        precondition(Step.volumeTier(0.34, muted: false) == .volumeMid)
        precondition(Step.volumeTier(2.0 / 3.0, muted: false) == .volumeMid, "≤ ⅔ 含 ⅔")
        precondition(Step.volumeTier(0.67, muted: false) == .volumeHigh)
        precondition(Step.volumeTier(1, muted: false) == .volumeHigh)
        // 静音一律斜线，哪怕数值是 0 或满格。
        for v in [0.0, 0.2, 0.5, 1.0] { precondition(Step.volumeTier(v, muted: true) == .volumeMuted) }
        // 降到 0 但没静音：不带声波的喇叭，不是斜线。
        precondition(Step.volumeTier(0, muted: false).symbolName == "speaker.fill")
        precondition(Step.volumeTier(0, muted: true).symbolName == "speaker.slash.fill")
        precondition(Step.volumeTier(0.2, muted: false).symbolName == "speaker.wave.1.fill")
        precondition(Step.volumeTier(0.5, muted: false).symbolName == "speaker.wave.2.fill")
        precondition(Step.volumeTier(0.9, muted: false).symbolName == "speaker.wave.3.fill")
        // 一格一格走过：档位只升不降。
        var rank = -1
        for i in 0...16 {
            let t = Step.volumeTier(Double(i) / 16, muted: false)
            let r = [Step.Tier.volumeZero, .volumeLow, .volumeMid, .volumeHigh].firstIndex(of: t)!
            precondition(r >= rank)
            rank = r
        }
    }

    static func brightnessTiers() {
        precondition(Step.brightnessTier(0) == .brightnessLow)
        precondition(Step.brightnessTier(0.4999) == .brightnessLow)
        precondition(Step.brightnessTier(0.5) == .brightnessHigh, "< 50% 才是小太阳")
        precondition(Step.brightnessTier(1) == .brightnessHigh)
        precondition(Step.brightnessTier(0.25).symbolName == "sun.min.fill")
        precondition(Step.brightnessTier(0.75).symbolName == "sun.max.fill")
    }

    static func keyboardTiers() {
        precondition(Step.keyboardLightTier(0) == .keyboardOff)
        precondition(Step.keyboardLightTier(0).isDimmed && !Step.keyboardLightTier(0.2).isDimmed)
        precondition(Step.keyboardLightTier(0.0625) == .keyboardLow)
        precondition(Step.keyboardLightTier(0.4999) == .keyboardLow)
        precondition(Step.keyboardLightTier(0.5) == .keyboardHigh)
        precondition(Step.keyboardLightTier(1) == .keyboardHigh)
        precondition(Step.keyboardLightTier(0.2).symbolName == "light.min")
        precondition(Step.keyboardLightTier(0.8).symbolName == "light.max")
        // 按种类分派。
        precondition(Step.tier(kind: .volume, value: 0.5, muted: true) == .volumeMuted)
        precondition(Step.tier(kind: .brightness, value: 0.5) == .brightnessHigh)
        precondition(Step.tier(kind: .keyboardLight, value: 0) == .keyboardOff)
    }

    // NSEvent.ModifierFlags 原始位：shift 1<<17，control 1<<18，option 1<<19，command 1<<20，capsLock 1<<16，fn 1<<23。
    static let shift: UInt = 1 << 17, control: UInt = 1 << 18, option: UInt = 1 << 19, command: UInt = 1 << 20
    static let capsLock: UInt = 1 << 16, fn: UInt = 1 << 23, numericPad: UInt = 1 << 21

    static func modifiers() {
        typealias M = NotchLevelModifiers
        precondition(M.classify(rawFlags: 0) == .none)
        precondition(M.classify(rawFlags: option | shift) == .optionShift)
        precondition(M.classify(rawFlags: option) == .other)
        precondition(M.classify(rawFlags: shift) == .other)
        precondition(M.classify(rawFlags: control) == .other)
        precondition(M.classify(rawFlags: command) == .other)
        precondition(M.classify(rawFlags: option | shift | control) == .other, "⌥⇧⌃ 不是 ⌥⇧")
        precondition(M.classify(rawFlags: option | shift | command) == .other)
        // 大写锁定、fn、数字键盘位不算按着修饰键。
        precondition(M.classify(rawFlags: capsLock) == .none)
        precondition(M.classify(rawFlags: fn | numericPad) == .none)
        precondition(M.classify(rawFlags: option | shift | fn | capsLock) == .optionShift)
        // 设备无关的低位不影响。
        precondition(M.classify(rawFlags: (option | shift) | 0x20) == .optionShift)
    }

    static func data1(_ code: Int, down: Bool = true, repeating: Bool = false) -> Int {
        (code << 16) | ((down ? 0x0A : 0x0B) << 8) | (repeating ? 1 : 0)
    }

    static func keyEvents() {
        typealias E = NotchLevelKeyEvent
        let keyboardUp = E.parse(subtype: 8, data1: data1(21), modifierFlags: 0)
        precondition(keyboardUp == E(key: .keyboardLightUp, isDown: true, isRepeat: false, modifiers: .none))
        let keyboardDown = E.parse(subtype: 8, data1: data1(22), modifierFlags: 0)
        precondition(keyboardDown?.key == .keyboardLightDown)
        precondition(keyboardUp?.key.kind == .keyboardLight && keyboardDown?.key.kind == .keyboardLight)
        // 原来五个键照认。
        let codes: [(Int, NotchLevelKey)] = [(0, .volumeUp), (1, .volumeDown), (2, .brightnessUp),
                                             (3, .brightnessDown), (7, .mute)]
        for (code, key) in codes {
            precondition(E.parse(subtype: 8, data1: data1(code), modifierFlags: 0)?.key == key)
        }
        // 连发位。
        precondition(E.parse(subtype: 8, data1: data1(0, repeating: true), modifierFlags: 0)?.isRepeat == true)
        precondition(E.parse(subtype: 8, data1: data1(0), modifierFlags: 0)?.isRepeat == false)
        // 松开也交出来（按住时松手才弹回）。
        let up = E.parse(subtype: 8, data1: data1(1, down: false), modifierFlags: 0)
        precondition(up?.key == .volumeDown && up?.isDown == false)
        // 修饰键。
        precondition(E.parse(subtype: 8, data1: data1(0), modifierFlags: option | shift)?.modifiers == .optionShift)
        precondition(E.parse(subtype: 8, data1: data1(2), modifierFlags: option)?.modifiers == .other)
        // 别的媒体键（播放 16）、别的 subtype、别的状态都不认。
        precondition(E.parse(subtype: 8, data1: data1(16), modifierFlags: 0) == nil)
        precondition(E.parse(subtype: 7, data1: data1(0), modifierFlags: 0) == nil)
        precondition(E.parse(subtype: 8, data1: (0 << 16) | (0x05 << 8), modifierFlags: 0) == nil)
    }

    static func legacyParseUnchanged() {
        // 现有调用方用的 NotchLevelKey.parse 行为不变：键盘灯键还是 nil，松开还是 nil。
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(21)) == nil)
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(22)) == nil)
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(0, down: false)) == nil)
        precondition(NotchLevelKey.parse(subtype: 8, data1: data1(0)) == .volumeUp)
    }

    static func gateKnowsKeyboardLight() {
        var gate = NotchLevelGate(keysAvailable: true)
        precondition(gate.keyPressed(.keyboardLightUp, at: 1, context: .init()) == .show)
        precondition(gate.valueChanged(.keyboardLight, at: 1.1, context: .init()) == .show)
        precondition(gate.valueChanged(.keyboardLight, at: 1.7, context: .init()) == .ignore(.noKey))
        // 按的是键盘灯，音量自己变了不算。
        precondition(gate.valueChanged(.volume, at: 1.1, context: .init()) == .ignore(.noKey))
        precondition(gate.recentlyPressed(.keyboardLight, at: 1.3) && !gate.recentlyPressed(.volume, at: 1.3))
    }
}
