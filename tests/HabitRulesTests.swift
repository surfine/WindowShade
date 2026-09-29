// 卡住时刘海开口的规则表与判定：纯逻辑，不听按键、不碰用户的设置。
import Foundation
import CoreGraphics

@main
struct HabitRulesTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static let control = HabitCombo.Modifiers.control, option = HabitCombo.Modifiers.option
    static let shift = HabitCombo.Modifiers.shift, command = HabitCombo.Modifiers.command
    static let ctrlC = HabitCombo(8, control)
    static let ctrlShiftC = HabitCombo(8, [.control, .shift])

    static func main() {
        table()
        gate()
        ledgerAndPacing()
        judge()
        scene()
        repeats()
        clipboard()
        shiftTaps()
        altDigits()
        hideWatch()
        desktopSwipes()
        dockDrop()
        shadeWatch()
        words()
        demo()
        menuKey()
        occupancy()
        exclusions()
        focus()
        comboLabels()

        if failures == 0 { print("PASS: habit rules — table lookup, gate by origin, judge per rule, pacing ledger, every state machine, wording") }
        else { print("FAILED \(failures)"); exit(1) }
    }

    // 按键查表：开着的规则才算，自动重复不算。
    static func table() {
        let copy = HabitTable(rules: [.copy], emacs: false)
        expect(copy.classify(keyCode: 8, flags: HabitCombo.controlBit, autorepeat: false) == [.foreign(.copy)],
               "with copy active, ⌃C is the foreign habit")
        expect(copy.classify(keyCode: 8, flags: HabitCombo.controlBit | HabitCombo.shiftBit, autorepeat: false) == [],
               "⌃⇧C is not ⌃C")
        expect(copy.classify(keyCode: 8, flags: HabitCombo.controlBit | 0x10000 | 0x200000, autorepeat: false) == [.foreign(.copy)],
               "caps lock and numeric pad bits do not change ⌃C")
        expect(copy.classify(keyCode: 8, flags: HabitCombo.controlBit, autorepeat: true) == [],
               "auto repeat is not another press")
        expect(copy.classify(keyCode: 8, flags: HabitCombo.commandBit, autorepeat: false) == [.mac(.copy)],
               "⌘C means the user already knows copy")

        let both = HabitTable(rules: [.closeTab, .closeWindow], emacs: false)
        let w = both.classify(keyCode: 13, flags: HabitCombo.commandBit, autorepeat: false)
        expect(w.contains(.mac(.closeTab)) && w.contains(.mac(.closeWindow)),
               "⌘W is the Mac shortcut of both close tab and close window")

        expect(copy.classify(keyCode: HabitKey.v, flags: HabitCombo.controlBit, autorepeat: false) == [],
               "a rule that is not active produces nothing")

        let menuBar = HabitTable(rules: [.menuBar], emacs: false)
        expect(menuBar.classify(keyCode: 46, flags: HabitCombo.fnBit, autorepeat: false) == [.foreign(.menuBar)],
               "with menu bar active, 🌐M is the foreign habit")
        expect(menuBar.classify(keyCode: 46, flags: 0, autorepeat: false) == [],
               "a plain M is just typing")

        let lineEnds = HabitTable(rules: [.lineEnds], emacs: false)
        expect(lineEnds.classify(keyCode: 115, flags: HabitCombo.fnBit, autorepeat: false) == [.foreign(.lineEnds)],
               "Home carries the fn bit and is still Home")

        let trashElsewhere = HabitTable(rules: [.trash], emacs: false)
        expect(trashElsewhere.classify(keyCode: 51, flags: 0, autorepeat: false) == []
               && trashElsewhere.classify(keyCode: 117, flags: 0, autorepeat: false) == [],
               "outside the finder a plain delete or Del never leaves the tap, so typing costs nothing")
        expect(trashElsewhere.classify(keyCode: 51, flags: HabitCombo.commandBit, autorepeat: false) == [.mac(.trash)],
               "⌘delete still counts as knowing trash wherever it is pressed")
        let trashInFinder = HabitTable(rules: [.trash], emacs: false, finderFront: true)
        expect(trashInFinder.classify(keyCode: 51, flags: 0, autorepeat: false) == [.foreign(.trash)]
               && trashInFinder.classify(keyCode: 117, flags: 0, autorepeat: false) == [.foreign(.trash)],
               "with the finder in front a plain delete or Del is the foreign habit")
        expect(HabitTable(rules: [.copy], emacs: false, finderFront: true) == HabitTable(rules: [.copy], emacs: false),
               "the finder being in front changes nothing for the other rules")
        expect(HabitTable(rules: [.copy], emacs: true).classify(keyCode: 14, flags: HabitCombo.controlBit, autorepeat: false) == [.emacs],
               "⌃E counts as Emacs only when the emacs habit is on")
        expect(HabitTable(rules: [.copy], emacs: false).classify(keyCode: 14, flags: HabitCombo.controlBit, autorepeat: false) == [],
               "⌃E means nothing when the emacs habit is off")
    }

    // 来处决定开哪几条，这台 Mac 的情况再筛一遍。
    static func gate() {
        expect(HabitGate.rules(for: .windows).count == 11, "answering Windows opens the 11 Windows-side rules")
        expect(HabitGate.rules(for: .windows).allSatisfy { $0.side == .windows || $0.needsDeviceCheck },
               "the Windows set is all Windows-side except the two device-check rules")
        expect(HabitGate.rules(for: .windows, deviceChecked: [.imeShift, .screenshot]).count == 13,
               "confirming on a real machine brings Windows up to 13")
        expect(HabitGate.rules(for: .ipad) == [.hideApp, .menuBar, .dockRemoved, .titleDoubleClick, .titleFlickUp, .desktopSearch],
               "iPad opens exactly the six iPad-side rules")
        expect(HabitGate.rules(for: .ipad).count == 6, "iPad opens six rules")
        expect(HabitGate.rules(for: .mac).isEmpty, "always-Mac opens nothing")
        expect(HabitGate.rules(for: .unanswered) == [.copy, .cut, .save, .trash, .forceQuit, .closeWindow],
               "unanswered opens only the rules that cannot misfire")

        var memory = HabitMemory()
        memory.ledger.learned("copy")
        expect(!HabitGate.active(origin: .windows, memory: memory).contains(.copy), "a learned rule is dropped")
        memory = HabitMemory()
        memory.ledger.dismiss("copy")
        expect(!HabitGate.active(origin: .windows, memory: memory).contains(.copy), "a dismissed rule is dropped")
        memory = HabitMemory()
        for _ in 0..<3 { memory.ledger.didShow("copy", at: 0) }
        expect(!HabitGate.active(origin: .windows, memory: memory).contains(.copy), "a rule shown three times is dropped")

        memory = HabitMemory()
        for rule in [HabitRule.copy, .paste, .undo] { memory.ledger.learned(rule.rawValue) }
        let quietFamily = HabitGate.active(origin: .windows, memory: memory)
        expect(!quietFamily.contains(.paste) && !quietFamily.contains(.save) && quietFamily.contains(.trash),
               "three learned control-family rules silence the whole family but not the others")
        memory = HabitMemory()
        for rule in [HabitRule.copy, .cut, .save] { memory.ledger.learned(rule.rawValue) }
        expect(HabitGate.active(origin: .unanswered, memory: memory).isEmpty,
               "someone who never answered and already uses three ⌘ shortcuts gets no tips at all, so nothing listens")
        memory = HabitMemory()
        memory.ledger.learned("undo")
        memory.emacsHits = 3
        expect(!HabitGate.active(origin: .windows, memory: memory).contains(.paste),
               "three ⌃E/⌃K presses silence the control family too")
        memory = HabitMemory()
        var environment = HabitGate.Environment()
        environment.remappedModifiers = true
        expect(!HabitGate.active(origin: .windows, memory: memory, environment: environment).contains(.copy),
               "swapped modifier keys silence the control family")
        environment = HabitGate.Environment()
        environment.remapToolRunning = true
        let remap = HabitGate.active(origin: .windows, deviceChecked: [.imeShift, .screenshot], memory: memory, environment: environment)
        expect(!remap.contains(.imeShift) && !remap.contains(.screenshot), "a remap tool running drops ime shift and print screen")
        environment = HabitGate.Environment()
        environment.homeLearned = true
        expect(!HabitGate.active(origin: .ipad, memory: memory, environment: environment).contains(.hideApp),
               "having tapped the notch home drops the hide-app tip")
        memory = HabitMemory()
        memory.desktopSearchSince = 0
        let day: TimeInterval = 86_400
        expect(HabitGate.active(origin: .ipad, memory: memory, now: 13 * day).contains(.desktopSearch),
               "desktop search keeps listening during its first two weeks")
        expect(!HabitGate.active(origin: .ipad, memory: memory, now: 15 * day).contains(.desktopSearch),
               "after two weeks desktop search stops listening to every scroll")
        expect(HabitGate.active(origin: .ipad, memory: memory, now: 15 * day).contains(.menuBar),
               "the two-week limit only drops desktop search")
        memory = HabitMemory()
        expect(HabitGate.active(origin: .ipad, memory: memory, now: 400 * day).contains(.desktopSearch),
               "a rule that never started listening has no clock running")
        environment = HabitGate.Environment()
        environment.spotlightAvailable = false
        expect(!HabitGate.active(origin: .ipad, memory: memory, environment: environment).contains(.desktopSearch),
               "spotlight being unavailable drops the desktop search tip")

        memory = HabitMemory()
        memory.heldShade = true
        let held = HabitGate.active(origin: .ipad, memory: memory)
        expect(!held.contains(.titleDoubleClick) && !held.contains(.titleFlickUp),
               "having rested a shaded window drops both title-bar tips")
        memory = HabitMemory()
        memory.shadeCollapses = 3
        let collapsed = HabitGate.active(origin: .ipad, memory: memory)
        expect(!collapsed.contains(.titleDoubleClick) && !collapsed.contains(.titleFlickUp),
               "collapsing three times drops both title-bar tips")
    }

    // 账本和共用的节奏：两边共用五分钟，同一条最多三次，用过、点掉的不再出。
    static func ledgerAndPacing() {
        CoachPacing.reset()
        var ledger = HabitLedger()
        expect(ledger.canShow("copy", at: 0), "a fresh ledger allows the first tip")
        ledger.didShow("copy", at: 0)
        expect(!ledger.canShow("paste", at: 299), "another id is blocked inside the shared five minutes")
        expect(ledger.canShow("paste", at: 300), "another id is allowed once five minutes passed")

        CoachPacing.reset()
        var coach = GestureCoach()
        var habits = HabitLedger()
        coach.didShow(.halves, at: 1000)
        expect(!habits.canShow("copy", at: 1100), "a gesture tip blocks the habit tip inside five minutes (one shared clock)")
        coach = GestureCoach()
        habits = HabitLedger()
        habits.didShow("copy", at: 0)
        expect(!coach.canShow(.halves, at: 100), "a habit tip blocks the gesture tip inside five minutes")

        CoachPacing.reset()
        var capped = HabitLedger()
        for i in 0..<3 { capped.didShow("copy", at: Double(i) * 300) }
        expect(!capped.canShow("copy", at: 900), "a rule stops after three shows")
        var learned = HabitLedger()
        learned.learned("copy")
        expect(!learned.canShow("copy", at: 0), "a learned rule never shows again")
        var dismissed = HabitLedger()
        dismissed.dismiss("copy")
        expect(!dismissed.canShow("copy", at: 0), "a dismissed rule never shows again")

        CoachPacing.reset()
        CoachPacing.hold([.shade], for: 60)
        var gesture = GestureCoach()
        expect(!gesture.canShow(.shade, at: 0), "holding the shade tip blocks the shade gesture tip")
        expect(gesture.canShow(.halves, at: 0), "holding one tip does not block the others")
        CoachPacing.release()
        expect(gesture.canShow(.shade, at: 0), "releasing the hold lets the tip through again")
        CoachPacing.hold([.shade, .shake], for: -1)
        expect(gesture.canShow(.shade, at: 0) && gesture.canShow(.shake, at: 0),
               "a hold lets go by itself when its time is up, so a tip is never held for good")
        CoachPacing.hold([.shade, .shake], for: 60)
        CoachPacing.hold([.shade, .shake], for: -1)
        expect(!gesture.canShow(.shade, at: 0), "a shorter hold does not cut a longer one short")
        CoachPacing.reset()
        expect(HabitShadeWatch.longest >= HabitShadeWatch.quick + HabitShadeWatch.hold
               && HabitShadeWatch.longest >= HabitShadeWatch.quick + HabitShadeWatch.enlarge
               && HabitShadeWatch.longest <= 20,
               "the hold after a title-bar collapse covers the whole watch and stays under twenty seconds")
        expect(!gesture.canShow(.habit, at: 0), "the habit slot never goes through the gesture ledger")

        let encoded = try! JSONEncoder().encode(capped)
        expect(try! JSONDecoder().decode(HabitLedger.self, from: encoded) == capped, "the ledger round trips through JSON")
        let emptyJSON = Data("{}".utf8)
        expect(try! JSONDecoder().decode(HabitLedger.self, from: emptyJSON) == HabitLedger(), "an empty ledger object decodes to empty")
        let decodedMemory = try! JSONDecoder().decode(HabitMemory.self, from: emptyJSON)
        expect(decodedMemory == HabitMemory(), "an empty habit memory object decodes to empty")
        var dated = HabitMemory()
        dated.desktopSearchSince = 1_000
        expect(try! JSONDecoder().decode(HabitMemory.self, from: JSONEncoder().encode(dated)) == dated,
               "the day desktop search started listening round trips through JSON")

        gesture.didShow(.halves, at: 10)
        let roundTrip = try! JSONDecoder().decode(GestureCoach.self, from: JSONEncoder().encode(gesture))
        expect(roundTrip == gesture, "a gesture coach round trips through JSON")
    }

    // 一条一条规则的判定：只在两件事都有证据时开口。
    static func judge() {
        var copy = HabitSituation()
        copy.menu = .read(hasMac: true, hasForeign: false)
        expect(HabitRules.judge(.copy, copy) == .teach, "⌃C with no reaction and a readable menu teaches ⌘C")
        var silent = copy
        silent.menu = .unreadable
        expect(HabitRules.judge(.copy, silent) == .silent("menu"), "an unreadable menu says nothing")
        silent = copy
        silent.menu = .read(hasMac: true, hasForeign: true)
        expect(HabitRules.judge(.copy, silent) == .silent("menu"), "a menu that already has ⌃C says nothing")
        silent = copy
        silent.pasteboardChanged = true
        expect(HabitRules.judge(.copy, silent) == .silent("copied"), "a clipboard that changed means ⌃C worked")
        silent = copy
        silent.reacted = true
        expect(HabitRules.judge(.copy, silent) == .silent("reacted"), "the app reacting says nothing")
        silent = copy
        silent.excluded = true
        expect(HabitRules.judge(.copy, silent) == .silent("excluded"), "an excluded app says nothing")
        silent = copy
        silent.taken = true
        expect(HabitRules.judge(.copy, silent) == .silent("taken"), "an occupied shortcut says nothing")
        silent = copy
        silent.voiceOver = true
        expect(HabitRules.judge(.copy, silent) == .silent("voiceover"), "VoiceOver says nothing")
        silent = copy
        silent.focus = .secure
        expect(HabitRules.judge(.copy, silent) == .silent("typing"), "a secure field says nothing")
        silent = copy
        silent.composing = true
        expect(HabitRules.judge(.copy, silent) == .silent("typing"), "an input method composing says nothing")

        var browser = copy
        browser.app = .browser
        expect(HabitRules.judge(.copy, browser) == .waitForRepeat, "in a browser the web page may handle ⌃C, so wait for a second press")
        browser.repeated = true
        expect(HabitRules.judge(.copy, browser) == .teach, "a second ⌃C in a browser teaches the Mac shortcut")
        var shell = copy
        shell.app = .webShell
        shell.focus = .text
        expect(HabitRules.judge(.copy, shell) == .silent("editor"), "a web shell with its own text editor keeps quiet")
        shell.focus = .list
        shell.repeated = true
        expect(HabitRules.judge(.copy, shell) == .teach, "a web shell with a list focus teaches on a repeat")

        var cut = copy
        cut.selection = 0
        expect(HabitRules.judge(.cut, cut) == .silent("nothing selected"), "⌃X with nothing selected says nothing")
        cut.selection = 3
        expect(HabitRules.judge(.cut, cut) == .teach, "⌃X with three characters selected teaches ⌘X")
        cut.selection = nil
        cut.finderSelection = true
        expect(HabitRules.judge(.cut, cut) == .teach, "⌃X in a finder list with a selection teaches ⌘X")

        var paste = HabitSituation()
        paste.focus = .list
        paste.menu = .read(hasMac: true, hasForeign: false)
        paste.antecedent = true
        expect(HabitRules.judge(.paste, paste) == .silent("not text"), "⌃V outside text says nothing")
        paste.focus = .text
        paste.antecedent = false
        expect(HabitRules.judge(.paste, paste) == .silent("no reason"), "⌃V with no reason to paste says nothing")
        paste.antecedent = true
        expect(HabitRules.judge(.paste, paste) == .teach, "⌃V in text with a copy just missed teaches ⌘V")
        paste.app = .browser
        expect(HabitRules.judge(.paste, paste) == .waitForRepeat, "⌃V in a browser waits for a second press")
        paste.repeated = true
        expect(HabitRules.judge(.paste, paste) == .teach, "a second ⌃V in a browser teaches")

        var undo = HabitSituation()
        undo.focus = .text
        undo.menu = .read(hasMac: true, hasForeign: false)
        expect(HabitRules.judge(.undo, undo) == .teach, "⌃Z in a native text field teaches ⌘Z")
        undo.app = .browser
        undo.repeated = true
        expect(HabitRules.judge(.undo, undo) == .silent("text changed"), "a browser ⌃Z that changed the text says nothing")
        undo.charactersUnchanged = false
        expect(HabitRules.judge(.undo, undo) == .silent("text changed"), "a browser ⌃Z that changed the text says nothing (explicitly unchanged false)")
        undo.charactersUnchanged = true
        expect(HabitRules.judge(.undo, undo) == .teach, "a browser ⌃Z that left the text unchanged teaches ⌘Z")
        undo.repeated = false
        expect(HabitRules.judge(.undo, undo) == .waitForRepeat, "a browser ⌃Z waits for a second press")

        var save = HabitSituation()
        save.menu = .read(hasMac: true, hasForeign: false)
        save.app = .browser
        save.repeated = true
        expect(HabitRules.judge(.save, save) == .silent("browser"), "⌃S is not taught inside browsers in the first batch")
        save.app = .native
        expect(HabitRules.judge(.save, save) == .teach, "⌃S with a readable menu teaches ⌘S")

        var closeTab = HabitSituation()
        closeTab.focus = .text
        closeTab.menu = .read(hasMac: true, hasForeign: false)
        expect(HabitRules.judge(.closeTab, closeTab) == .silent("focus"), "⌃W inside text says nothing")
        closeTab.focus = .list
        expect(HabitRules.judge(.closeTab, closeTab) == .teach, "⌃W in a list teaches ⌘W")
        var addressBar = closeTab
        addressBar.focus = .addressBar
        addressBar.app = .browser
        addressBar.repeated = true
        expect(HabitRules.judge(.closeTab, addressBar) == .teach, "⌃W in a browser address bar teaches on a repeat")
        closeTab.focus = .unknown
        expect(HabitRules.judge(.closeTab, closeTab) == .silent("focus"), "⌃W with an unknown focus says nothing")

        var trash = HabitSituation()
        trash.finder = true
        trash.focus = .list
        trash.finderSelection = true
        trash.sinceLetter = 2
        expect(HabitRules.judge(.trash, trash) == .teach, "Delete in a finder file list teaches ⌘delete")
        trash.sinceLetter = 0.5
        expect(HabitRules.judge(.trash, trash) == .silent("typing a name"), "Delete half a second after a letter is selecting by name")
        trash.sinceLetter = 2
        trash.finder = false
        expect(HabitRules.judge(.trash, trash) == .silent("not a file list"), "Delete outside the finder says nothing")
        trash.finder = true
        trash.focus = .text
        expect(HabitRules.judge(.trash, trash) == .silent("not a file list"), "Delete in a text field says nothing")

        var lineEnds = HabitSituation()
        lineEnds.focus = .text
        expect(HabitRules.judge(.lineEnds, lineEnds) == .silent("unreadable"), "Home with no caret reading says nothing")
        lineEnds.caretAtEdge = true
        lineEnds.wholeTextVisible = true
        expect(HabitRules.judge(.lineEnds, lineEnds) == .silent("moved"), "Home that already moved the caret says nothing")
        lineEnds.caretAtEdge = false
        lineEnds.wholeTextVisible = false
        expect(HabitRules.judge(.lineEnds, lineEnds) == .silent("could scroll"), "Home on a long text that can scroll says nothing")
        lineEnds.wholeTextVisible = true
        expect(HabitRules.judge(.lineEnds, lineEnds) == .teach, "Home that did not move in a short text teaches ⌘←")
        lineEnds.sinceFn = 0.5
        expect(HabitRules.judge(.lineEnds, lineEnds) == .silent("fn arrow"), "Home right after fn is the Apple fn-arrow, not Home")

        var forceQuit = HabitSituation()
        forceQuit.variant = .deleteKey
        forceQuit.focus = .text
        expect(HabitRules.judge(.forceQuit, forceQuit) == .silent("focus"), "⌃⌥⌫ inside text says nothing")
        forceQuit.focus = .list
        expect(HabitRules.judge(.forceQuit, forceQuit) == .teach, "⌃⌥⌫ outside text teaches ⌥⌘esc")
        forceQuit.variant = .plain
        forceQuit.focus = .text
        expect(HabitRules.judge(.forceQuit, forceQuit) == .teach, "⌃⇧esc in text still teaches ⌥⌘esc")

        var closeWindow = HabitSituation()
        closeWindow.menu = .unreadable
        expect(HabitRules.judge(.closeWindow, closeWindow) == .teach, "⌥F4 with an unreadable menu is still taught")
        closeWindow.menu = .read(hasMac: true, hasForeign: true)
        expect(HabitRules.judge(.closeWindow, closeWindow) == .silent("menu"), "a menu that already has ⌥F4 says nothing")

        var screenshot = HabitSituation()
        screenshot.hotkeyAppRunning = true
        expect(HabitRules.judge(.screenshot, screenshot) == .silent("hotkey app"), "a global hotkey app stealing F13 says nothing")

        var symbols = HabitSituation()
        symbols.focus = .text
        expect(HabitRules.judge(.symbols, symbols) == .silent("not typed"), "⌥ plus keypad digits that typed nothing says nothing")
        symbols.symbolsTyped = true
        expect(HabitRules.judge(.symbols, symbols) == .teach, "⌥ plus keypad digits that typed the digits teaches ⌃⌘空格")

        var menuBar = HabitSituation()
        menuBar.focus = .text
        expect(HabitRules.judge(.menuBar, menuBar) == .silent("typed an m"), "🌐M in text was just typing an m")
        menuBar.focus = .list
        menuBar.menuOpened = true
        expect(HabitRules.judge(.menuBar, menuBar) == .silent("found the menu"), "🌐M that opened the menu says nothing")
        menuBar.menuOpened = false
        expect(HabitRules.judge(.menuBar, menuBar) == .teach, "🌐M outside text that opened no menu teaches ⌃F2")
    }

    // 前后两个样子比一比：有反应就不说。
    static func scene() {
        let before = HabitScene(frontPID: 1, focusedWindow: 2, focusedTitle: "a", windowCount: 3, overlays: [4], pasteboard: 5)
        expect(!before.reacted(to: before), "an unchanged scene is no reaction")
        var more = before
        more.windowCount = 4
        expect(before.reacted(to: more), "a window count change is a reaction")
        var overlay = before
        overlay.overlays = [4, 9]
        expect(before.reacted(to: overlay), "a new floating window is a reaction")
        var fewer = before
        fewer.overlays = []
        expect(!before.reacted(to: fewer), "a floating window going away is not a reaction")
        var same = before
        same.pasteboard = 5
        expect(!before.pasteboardChanged(to: same), "an unchanged clipboard count is no change")
        var changed = before
        changed.pasteboard = 6
        expect(before.pasteboardChanged(to: changed), "a changed clipboard count is a change")
        var unknown = before
        unknown.pasteboard = nil
        expect(!before.pasteboardChanged(to: unknown), "a clipboard count we could not read is no change")
        expect(!before.pasteboardChanged(to: changed) == false, "the readable pair is what counts")
    }

    // 时间窗：四秒内第二次，⌃C/⌃X 之后的 ⌃V 是六十秒。
    static func repeats() {
        var repeats = HabitRepeats()
        repeats.noteMiss(.copy, at: 10)
        expect(repeats.isRepeat(.copy, at: 13.9), "a miss just inside four seconds counts as a repeat")
        expect(!repeats.isRepeat(.copy, at: 14.1), "a miss just outside four seconds is not a repeat")
        expect(repeats.isRepeat(.copy, at: 14.1, scale: 2), "slow keys stretch the window")
        expect(repeats.isRepeat(.paste, at: 69), "⌃V within a minute of a missed ⌃C has an antecedent")
        expect(!repeats.isRepeat(.paste, at: 71), "⌃V more than a minute after a missed ⌃C has none")
        expect(!repeats.isRepeat(.undo, at: 12), "another rule's miss does not count")
        expect(repeats.copyMissed(before: 12), "a missed ⌃C is reported as such")
        expect(!repeats.copyMissed(before: 5), "a miss in the future is not an antecedent")
    }

    // 剪贴板：两分钟内变过、期间没按过 ⌘C/⌘X。
    static func clipboard() {
        var clipboard = HabitClipboard()
        clipboard.sample(5, at: 0)
        expect(clipboard.changedWithoutMacCopy(now: 6, at: 100), "a clipboard that changed within two minutes is a reason")
        expect(!clipboard.changedWithoutMacCopy(now: 6, at: 121), "a clipboard older than two minutes is no reason")
        expect(!clipboard.changedWithoutMacCopy(now: 5, at: 100), "an unchanged clipboard count is no reason")
        var macCopy = HabitClipboard()
        macCopy.sample(5, at: 0)
        macCopy.sample(5, at: 50, macCopy: true)
        expect(!macCopy.changedWithoutMacCopy(now: 6, at: 60), "a ⌘C after the last sample explains the change")
        expect(!HabitClipboard().changedWithoutMacCopy(now: 6, at: 60), "no sample at all is no reason")
    }

    // 单按 ⇧：二十秒内第二次才说。
    static func shiftTaps() {
        var taps = HabitShiftTaps()
        expect(!taps.tap(at: 0), "the first lone ⇧ says nothing")
        expect(taps.tap(at: 15), "the second lone ⇧ inside twenty seconds speaks")
        expect(!taps.tap(at: 15.5), "a third press right after starts a new pair")
        expect(!taps.tap(at: 40.5), "a second lone ⇧ twenty-five seconds later is too late")
    }

    // ⌥ 加小键盘：多出来的字数要和按的数字个数对得上。
    static func altDigits() {
        expect(!HabitAltDigits.typedAsDigits(count: 1, before: 0, after: 1), "one keypad digit is not enough evidence")
        expect(HabitAltDigits.typedAsDigits(count: 3, before: 0, after: 3), "three digits that added three characters")
        expect(HabitAltDigits.typedAsDigits(count: 3, before: 0, after: 2), "the count may be short by one")
        expect(!HabitAltDigits.typedAsDigits(count: 3, before: 0, after: 1), "adding fewer characters than digits means symbols came out")
        expect(!HabitAltDigits.typedAsDigits(count: 3, before: nil, after: 3), "no character count before the press is no evidence")
    }

    // ⌘H：藏起来后没在别处做事、八秒内又找回来，或三秒里藏了两个不同的 App。
    static func hideWatch() {
        var watch = HabitHideWatch()
        watch.commandH(pid: 1, at: 0, hadWindows: true)
        expect(!watch.didHide(pid: 1, at: 0.3), "a single hide is not the story yet")
        expect(watch.watching, "after ⌘H hid the app we watch for it coming back")
        expect(watch.didUnhide(pid: 1, at: 5), "coming back within eight seconds without touching anything else speaks")
        var busy = HabitHideWatch()
        busy.commandH(pid: 1, at: 0, hadWindows: true)
        _ = busy.didHide(pid: 1, at: 0.3)
        busy.activity(pid: 2, ignoring: [])
        expect(!busy.didUnhide(pid: 1, at: 5), "typing in another app while it was hidden means he meant to hide it")
        var ignoredActivity = HabitHideWatch()
        ignoredActivity.commandH(pid: 1, at: 0, hadWindows: true)
        _ = ignoredActivity.didHide(pid: 1, at: 0.3)
        ignoredActivity.activity(pid: 2, ignoring: [2])
        expect(ignoredActivity.didUnhide(pid: 1, at: 5), "activity from the Dock does not count")
        var late = HabitHideWatch()
        late.commandH(pid: 1, at: 0, hadWindows: true)
        _ = late.didHide(pid: 1, at: 0.3)
        expect(!late.didUnhide(pid: 1, at: 9), "coming back after more than eight seconds does not speak")
        var noPress = HabitHideWatch()
        expect(!noPress.didHide(pid: 1, at: 0.3), "a hide with no ⌘H before it is not linked")
        expect(!noPress.watching, "nothing to watch without a ⌘H")
        var emptyApp = HabitHideWatch()
        emptyApp.commandH(pid: 1, at: 0, hadWindows: false)
        expect(!emptyApp.didHide(pid: 1, at: 0.3) && !emptyApp.watching, "an app with no windows on screen is not watched")
        var slow = HabitHideWatch()
        slow.commandH(pid: 1, at: 0, hadWindows: true)
        expect(!slow.didHide(pid: 1, at: 0.6), "a hide six tenths of a second after ⌘H is not linked")
        var twoApps = HabitHideWatch()
        twoApps.commandH(pid: 1, at: 0, hadWindows: true)
        _ = twoApps.didHide(pid: 1, at: 0.2)
        twoApps.commandH(pid: 2, at: 2, hadWindows: true)
        expect(twoApps.didHide(pid: 2, at: 2.1), "hiding two different apps with ⌘H inside three seconds speaks")
        var sameApp = HabitHideWatch()
        sameApp.commandH(pid: 1, at: 0, hadWindows: true)
        _ = sameApp.didHide(pid: 1, at: 0.2)
        sameApp.commandH(pid: 1, at: 1, hadWindows: true)
        expect(!sameApp.didHide(pid: 1, at: 1.1), "hiding the same app twice is not the story")
    }

    // 桌面两指下滑：手指方向换算回来，十秒内两次八十点以上。
    static func desktopSwipes() {
        expect(HabitDesktopSwipes.fingerTravel(deltaY: 30, natural: true) == 30, "natural scrolling keeps the finger direction")
        expect(HabitDesktopSwipes.fingerTravel(deltaY: 30, natural: false) == -30, "reversed scrolling flips the finger direction")
        var swipes = HabitDesktopSwipes()
        expect(!swipes.swipe(fingersDown: 100, onDesktop: true, at: 0), "the first swipe speaks nothing")
        expect(swipes.swipe(fingersDown: 100, onDesktop: true, at: 5), "a second swipe five seconds later speaks")
        var offDesktop = HabitDesktopSwipes()
        _ = offDesktop.swipe(fingersDown: 100, onDesktop: false, at: 0)
        expect(!offDesktop.swipe(fingersDown: 100, onDesktop: false, at: 5), "swipes on a window are not desktop swipes")
        var short = HabitDesktopSwipes()
        _ = short.swipe(fingersDown: 60, onDesktop: true, at: 0)
        expect(!short.swipe(fingersDown: 60, onDesktop: true, at: 5), "swipes shorter than eighty points are not the gesture")
        var apart = HabitDesktopSwipes()
        _ = apart.swipe(fingersDown: 100, onDesktop: true, at: 0)
        expect(!apart.swipe(fingersDown: 100, onDesktop: true, at: 11), "two swipes eleven seconds apart are not one gesture")
    }

    // 从 Dock 拖图标：松手的地方像不像想分屏。
    static func dockDrop() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let press = CGPoint(x: 500, y: 790)
        expect(HabitDockDrop.looksLikeSplit(release: CGPoint(x: 50, y: 400), press: press, screen: screen),
               "releasing at the left edge looks like a split")
        expect(HabitDockDrop.looksLikeSplit(release: CGPoint(x: 500, y: 400), press: press, screen: screen),
               "releasing in the middle looks like opening a window")
        expect(!HabitDockDrop.looksLikeSplit(release: CGPoint(x: 300, y: 400), press: press, screen: screen),
               "releasing a third of the way in looks like moving the icon")
        expect(!HabitDockDrop.looksLikeSplit(release: CGPoint(x: 500, y: 700), press: press, screen: screen),
               "releasing near the Dock looks like removing the icon on purpose")
        expect(HabitDockDrop.looksLikeSplit(release: CGPoint(x: 950, y: 300), press: press, screen: screen),
               "releasing at the right edge looks like a split")
        expect(!HabitDockDrop.looksLikeSplit(release: CGPoint(x: 1200, y: 400), press: press, screen: screen),
               "releasing outside the screen is nothing")
    }

    // 收起后又想放大：说一次；停过十秒、收起过三次的人不说。
    static func shadeWatch() {
        var watch = HabitShadeWatch()
        expect(!watch.collapsed(1, kind: .doubleClick, at: 0, priorCollapses: 3, held: false),
               "someone who collapsed three times is not watched")
        expect(!watch.collapsed(1, kind: .doubleClick, at: 0, priorCollapses: 0, held: true),
               "someone who rested a shaded window is not watched")
        expect(watch.collapsed(1, kind: .doubleClick, at: 0, priorCollapses: 0, held: false),
               "a normal collapse is watched")

        var held = HabitShadeWatch()
        _ = held.collapsed(1, kind: .doubleClick, at: 0, priorCollapses: 0, held: false)
        expect(held.quickCheck(1, stillShaded: true, exists: true, frame: nil, at: 3) == .checkHoldLater,
               "still shaded three seconds later means check again at ten")
        expect(held.holdCheck(1, stillShaded: true), "still shaded after ten seconds means he is using the shaded window")

        var enlarged = HabitShadeWatch()
        _ = enlarged.collapsed(7, kind: .doubleClick, at: 0, priorCollapses: 0, held: false)
        expect(enlarged.quickCheck(7, stillShaded: false, exists: true, frame: CGRect(x: 0, y: 0, width: 100, height: 100), at: 3) == .waitForEnlarge,
               "expanded again three seconds later means watch for an enlarge")
        expect(enlarged.enlargeCandidates == [7], "the window waiting for an enlarge is listed")
        expect(enlarged.resized(7, frame: CGRect(x: 0, y: 0, width: 110, height: 110), fillsScreen: false, at: 8) == .titleDoubleClick,
               "growing more than 15% within ten seconds speaks the double-click tip")
        var small = HabitShadeWatch()
        _ = small.collapsed(7, kind: .doubleClick, at: 0, priorCollapses: 0, held: false)
        _ = small.quickCheck(7, stillShaded: false, exists: true, frame: CGRect(x: 0, y: 0, width: 100, height: 100), at: 3)
        expect(small.resized(7, frame: CGRect(x: 0, y: 0, width: 101, height: 101), fillsScreen: false, at: 8) == nil,
               "growing by one point is not an enlarge")
        var lateGrow = HabitShadeWatch()
        _ = lateGrow.collapsed(7, kind: .doubleClick, at: 0, priorCollapses: 0, held: false)
        _ = lateGrow.quickCheck(7, stillShaded: false, exists: true, frame: CGRect(x: 0, y: 0, width: 100, height: 100), at: 3)
        expect(lateGrow.resized(7, frame: CGRect(x: 0, y: 0, width: 400, height: 400), fillsScreen: false, at: 14) == nil,
               "an enlarge more than ten seconds later says nothing")
        var full = HabitShadeWatch()
        _ = full.collapsed(7, kind: .doubleClick, at: 0, priorCollapses: 0, held: false)
        _ = full.quickCheck(7, stillShaded: false, exists: true, frame: CGRect(x: 0, y: 0, width: 100, height: 100), at: 3)
        expect(full.resized(7, frame: nil, fillsScreen: true, at: 5) == .titleDoubleClick, "going full screen counts as the enlarge too")

        var flick = HabitShadeWatch()
        _ = flick.collapsed(9, kind: .flickUp, at: 0, priorCollapses: 0, held: false)
        _ = flick.quickCheck(9, stillShaded: false, exists: true, frame: CGRect(x: 0, y: 0, width: 100, height: 100), at: 3)
        expect(flick.resized(9, frame: CGRect(x: 0, y: 0, width: 200, height: 200), fillsScreen: false, at: 4) == .titleFlickUp,
               "a flicked-up window that is enlarged speaks the flick tip")
        var gone = HabitShadeWatch()
        _ = gone.collapsed(9, kind: .flickUp, at: 0, priorCollapses: 0, held: false)
        expect(gone.quickCheck(9, stillShaded: false, exists: false, frame: nil, at: 3) == .drop, "a window that is gone is dropped")
    }

    // 刘海上说什么：菜单标题、访达、实际绑定。
    static func words() {
        expect(HabitWords.lines(.copy, menuTitle: "拷贝").title == "Mac 上拷贝按 ⌘C", "the menu title goes into the sentence")
        expect(HabitWords.lines(.copy, menuTitle: "拷贝").subtitle == HabitWords.controlFamily, "copy carries the control-family subtitle")
        expect(HabitWords.lines(.copy, menuTitle: "Copy").title == "Mac 上 Copy 按 ⌘C", "an English menu title goes into the sentence")
        expect(HabitWords.lines(.copy, menuTitle: nil).title == "Mac 上拷贝按 ⌘C", "no menu title falls back to the system name")
        expect(HabitWords.lines(.save, menuTitle: "存储…").title == "Mac 上存储按 ⌘S", "the ellipsis is dropped from the menu title")
        expect(HabitWords.lines(.undo, menuTitle: "撤销键入").title == "Mac 上撤销按 ⌘Z", "a dynamic undo title is shortened")

        let long = String(repeating: "长", count: 20)
        expect(HabitWords.lines(.copy, menuTitle: long).title == "Mac 上拷贝按 ⌘C", "a twenty-character menu title falls back to the system name")

        let tab = HabitWords.lines(.closeTab, menuTitle: "关闭标签页", finder: true)
        expect(!tab.title.contains("⌘Q") && !tab.subtitle.contains("⌘Q"), "the finder has no quit, so close tab says nothing about ⌘Q")
        let tabApp = HabitWords.lines(.closeTab, menuTitle: "关闭标签页", finder: false)
        expect(tabApp.subtitle.contains("⌘Q"), "in an app close tab mentions that quitting is ⌘Q")
        let window = HabitWords.lines(.closeWindow, menuTitle: "关闭窗口", finder: true)
        expect(!window.title.contains("⌘Q") && !window.subtitle.contains("⌘Q"), "the finder close window says nothing about ⌘Q")
        expect(HabitWords.lines(.closeWindow, menuTitle: "关闭窗口", finder: false).subtitle.contains("⌘Q"), "in an app close window mentions ⌘Q")

        expect(HabitWords.lines(.paste, variant: .pagedDown).subtitle.contains("往下翻页"), "⌃V that paged down says what happened")
        let noNotch = HabitWords.lines(.hideApp, variant: .noNotch, shortcut: "⌃⌘L")
        expect(noNotch.subtitle.contains("⌃⌘L"), "on a screen without a notch the shortcut binding is named")
        expect(HabitWords.lines(.hideApp, variant: .noNotch).subtitle.isEmpty, "with no binding that subtitle is empty")
        expect(HabitWords.lines(.desktopSearch, shortcut: "⌃空格").title.contains("⌃空格"), "desktop search names the real binding")

        expect(HabitWords.spoken("Mac 上拷贝按 ⌘C。常用快捷键把 ⌃ 换成 ⌘") == "Mac 上拷贝按 Command C。常用快捷键把 Control 换成 Command",
               "VoiceOver hears the key names, so ⌃ is Control the first time")
        expect(HabitWords.spoken("强制退出 App 按 ⌥⌘esc") == "强制退出 App 按 Option Command esc", "stacked modifiers are named one by one")
        expect(HabitWords.spoken("并排按 🌐⌃←") == "并排按 fn Control ←", "the globe key is read as fn")
        expect(HabitWords.spoken("图标从 Dock 移除了") == "图标从 Dock 移除了", "text without key symbols is read as is")

        for rule in HabitRule.allCases {
            let lines = HabitWords.lines(rule)
            expect(!lines.title.isEmpty && lines.title.count <= 20, "\(rule.rawValue) has a short non-empty title")
            let text = lines.title + lines.subtitle
            expect(!text.contains("AX") && !text.contains("bundle") && !text.contains("pid"),
                   "\(rule.rawValue) talks about keys, not about the system internals")
        }
    }

    // 刘海里演什么。
    static func demo() {
        expect(HabitWords.demo(.copy, pressed: ctrlC) == .keys(from: ["⌃", "C"], to: ["⌘", "C"]),
               "copy plays the pressed ⌃C above the taught ⌘C")
        expect(HabitWords.demo(.hideApp) == .notchHome, "the hide-app tip shows tapping the notch")
        expect(HabitWords.demo(.hideApp, variant: .noNotch, shortcut: ["⌃", "⌘", "L"]) == .keys(from: ["⌘", "H"], to: ["⌃", "⌘", "L"]),
               "on a screen without a notch the hide-app tip plays ⌘H and the launchpad shortcut, not a notch tap")
        expect(HabitWords.demo(.hideApp, variant: .noNotch) == .keys(from: ["⌘", "H"], to: []),
               "with no launchpad shortcut it only plays the ⌘H that was pressed")
        expect(HabitWords.demo(.lineEnds, variant: .end) == .keys(from: [], to: ["⌘", "→"]),
               "the End variant of Home/End plays ⌘→")
        expect(HabitWords.demo(.trash, pressed: HabitCombo(51)) == .keys(from: ["delete"], to: ["⌘", "delete"]),
               "trash plays the pressed delete above ⌘delete")
    }

    // 菜单里的快捷键：两边写法要能对上。
    static func menuKey() {
        expect(HabitMenuKey(HabitCombo(8, command)) == HabitMenuKey(character: "c", virtualKey: nil, modifiers: 0),
               "⌘C in the menu matches the combo with the plain ⌘ modifier value")
        expect(HabitMenuKey(ctrlC).modifiers == 12, "⌃C in a menu has ⌃ plus no-⌘")
        expect(HabitMenuKey(HabitCombo(51, command)) == HabitMenuKey(character: "\u{8}", virtualKey: nil, modifiers: 0),
               "⌘delete in the menu is the backspace character with plain ⌘")
        let optionF4 = HabitMenuKey(HabitCombo(118, option))
        expect(optionF4 == HabitMenuKey(character: nil, virtualKey: 118, modifiers: 10), "⌥F4 is virtual key 118 with ⌥ plus no-⌘")
        expect(optionF4 == HabitMenuKey(character: "\u{F707}", virtualKey: nil, modifiers: 10), "⌥F4 is also the private-use F4 character")
        expect(HabitMenuEvidence.read(hasMac: true, hasForeign: false).supports, "a readable menu with the Mac key and not the foreign one supports")
        expect(!HabitMenuEvidence.read(hasMac: true, hasForeign: true).supports, "a menu with the foreign key does not support")
        expect(!HabitMenuEvidence.unreadable.supports, "an unreadable menu does not support")
    }

    // 已占用的组合：WindowShade 的快捷键和 DefaultKeyBinding.dict。
    static func occupancy() {
        let bindings: [String: Any] = ["^c": "x", "^~a": "x", "\u{F729}": "x", "^C": "x"]
        let combos = HabitOccupancy.keyBindingCombos(bindings)
        expect(combos.contains(ctrlC), "a bound ^c is taken")
        expect(combos.contains(HabitCombo(0, [.control, .option])), "a bound ^~a is taken")
        expect(combos.contains(HabitCombo(115)), "a bound \\UF729 is taken")
        expect(combos.contains(ctrlShiftC), "a bound capital ^C includes shift")
        expect(HabitOccupancy.isTaken(.copy, pressed: ctrlC, taken: [ctrlC]), "the pressed combination being taken counts")
        expect(HabitOccupancy.isTaken(.copy, pressed: nil, taken: [HabitCombo(8, command)]), "the taught combination being taken counts")
        expect(!HabitOccupancy.isTaken(.copy, pressed: ctrlC, taken: []), "nothing taken means the rule is free")
        expect(HabitCombo(carbonKeyCode: 8, carbonModifiers: 0x1100) == HabitCombo(8, [.control, .command]),
               "a Carbon control-command hotkey is the same combination")
    }

    // 永远不说的地方。
    static func exclusions() {
        expect(HabitExclusions.isExcluded(bundleID: "com.apple.Terminal", executablePath: nil), "the terminal is excluded")
        expect(HabitExclusions.isExcluded(bundleID: "com.jetbrains.intellij", executablePath: nil), "JetBrains IDEs are excluded")
        expect(HabitExclusions.isExcluded(bundleID: nil, executablePath: nil), "a process with no bundle id is excluded")
        expect(HabitExclusions.isExcluded(bundleID: "org.example.thing", executablePath: "/Applications/Wine Stable/bin/x"),
               "a Wine executable is excluded")
        expect(!HabitExclusions.isExcluded(bundleID: "com.apple.Safari", executablePath: nil), "Safari is not excluded")
        expect(HabitExclusions.isBrowser("com.apple.Safari"), "Safari is a browser")
        expect(HabitExclusions.isBrowser("com.google.Chrome.app.abc"), "a Chrome web app is a browser")
        expect(HabitExclusions.isChromium("com.google.Chrome") && !HabitExclusions.isChromium("com.apple.Safari"),
               "Chrome is Chromium, Safari is not")
        expect(HabitExclusions.isExcludedHost("vscode.dev"), "vscode.dev is an excluded host")
        expect(HabitExclusions.isExcludedHost("foo.github.dev"), "a github.dev subdomain is excluded")
        expect(!HabitExclusions.isExcludedHost("notgithub.dev"), "a look-alike host is not excluded")
        expect(!HabitExclusions.isExcludedHost(nil), "no host is not excluded")
        expect(HabitExclusions.isGame(category: "public.app-category.action-games", executablePath: nil), "a games category is a game")
    }

    // 焦点：可编辑的文本、地址栏、列表、网页正文、不知道。
    static func focus() {
        expect(HabitFocus.classify(role: "AXTextField", subrole: "AXSecureTextField", editable: true, browser: false,
                                   chromium: false, inToolbar: false) == .secure, "a secure field is secure")
        expect(HabitFocus.classify(role: "AXTextField", subrole: nil, editable: false, browser: false,
                                   chromium: false, inToolbar: false) == .text, "a text field in a native app is text")
        expect(HabitFocus.classify(role: "AXTextField", subrole: nil, editable: false, browser: true,
                                   chromium: false, inToolbar: true) == .addressBar, "a text field in a browser toolbar is the address bar")
        expect(HabitFocus.classify(role: "AXOutline", subrole: nil, editable: false, browser: false,
                                   chromium: false, inToolbar: false) == .list, "an outline is a list")
        expect(HabitFocus.classify(role: "AXWebArea", subrole: nil, editable: false, browser: true,
                                   chromium: true, inToolbar: false) == .unknown, "a Chromium web area is too coarse to know")
        expect(HabitFocus.classify(role: "AXWebArea", subrole: nil, editable: false, browser: true,
                                   chromium: false, inToolbar: false) == .page, "a Safari web area is the page body")
        expect(HabitFocus.classify(role: "AXGroup", subrole: nil, editable: false, browser: false,
                                   chromium: false, inToolbar: false) == .unknown, "a coarse group is unknown")
    }

    // 键帽写出来是什么样。
    static func comboLabels() {
        expect(HabitCombo(53, [.option, .command]).label == "⌥⌘esc", "modifiers come in Apple's order")
        expect(HabitCombo(49, [.control, .command]).label == "⌃⌘空格", "the space key is called 空格")
        expect(HabitCombo(46, globe: true).parts == ["🌐", "M"], "🌐M is its own combination")
    }
}
