// 卡住时刘海开口：旧习惯的规则表和判定。纯逻辑，可单测（tests/run-habit-rules-tests.sh）。
// 按键在 App/HabitKeys.swift 里听（只听、不吞），前台 App、焦点和菜单在 App/HabitContext.swift 里读，
// 刘海上怎么说、点一下做什么在 App/Notch+Habit.swift。规则、出处和误报条件见 docs/stuck-habits.md。
//
// 只在两件事都有证据时开口：刚才那一下在这里没反应（或做了别的、他马上撤回），而要教的那一下在这里一定管用。
// 第一批：Windows 第一批 13 条、iPad 先上的 6 条（⌘H、🌐M、从 Dock 拖出图标、双击标题栏、往上甩、桌面两指下滑）；其余都不开。
// 其中单按 ⇧ 切换中英文、PC 键盘的 Print Screen 要先上真机确认，确认之前不开（needsDeviceCheck）。
// 来处（SwitcherOrigin）决定开哪几条：答 Windows 开 Windows 那一半，答 iPad 开 iPad 那一半，答“一直用 Mac”都不开，
// 没答的只开不会误报的几条（⌃C、⌃X、⌃S、访达里 Delete、强制退出、Alt+F4）。
// 节奏和手势提示共用一本账（Core/GestureCoach.swift 的 HabitLedger、CoachPacing）。

import Foundation
import CoreGraphics

// MARK: - 组合键

/// 规则用到的虚拟键码（与键盘布局无关的位置码；字母按 ANSI 排列，别的布局在判断时核对，见 HabitContext）。
enum HabitKey {
    static let a: UInt16 = 0, s: UInt16 = 1, f: UInt16 = 3, h: UInt16 = 4, z: UInt16 = 6, x: UInt16 = 7
    static let c: UInt16 = 8, v: UInt16 = 9, q: UInt16 = 12, w: UInt16 = 13, e: UInt16 = 14, k: UInt16 = 40, m: UInt16 = 46
    static let three: UInt16 = 20, four: UInt16 = 21, five: UInt16 = 23
    static let space: UInt16 = 49, delete: UInt16 = 51, escape: UInt16 = 53, function: UInt16 = 63
    static let forwardDelete: UInt16 = 117, home: UInt16 = 115, end: UInt16 = 119
    static let f2: UInt16 = 120, f4: UInt16 = 118, f13: UInt16 = 105
    static let left: UInt16 = 123, right: UInt16 = 124
    /// 小键盘的 0–9。
    static let keypadDigits: Set<UInt16> = [82, 83, 84, 85, 86, 87, 88, 89, 91, 92]

    /// 字母键（ANSI 位置）：访达里“按名字选文件”、fn 位只对它们算数。
    static let letters: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
    ]
    static let digits: [UInt16: String] = [18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0"]

    /// 键帽上的名字：字母大写，特殊键照 Mac 键帽写（delete、esc、空格），PC 独有的照 PC 键帽（Home、End、Del）。
    static func name(_ code: UInt16) -> String {
        if let letter = letters[code] { return letter }
        if let digit = digits[code] { return digit }
        switch code {
        case space: return "空格"
        case delete: return "delete"
        case escape: return "esc"
        case forwardDelete: return "Del"
        case home: return "Home"
        case end: return "End"
        case f2: return "F2"
        case f4: return "F4"
        case f13: return "F13"
        case left: return "←"
        case right: return "→"
        case 82: return "0"
        case 83...89: return String(code - 82)
        case 91: return "8"
        case 92: return "9"
        default: return "#\(code)"
        }
    }
}

/// 一个组合键：虚拟键码加四个修饰键（⌃⌥⇧⌘）。
/// G 要求修饰键完全一致，并屏蔽 fn、小键盘、大写锁定那几位；只有字母键带 🌐（fn）时算不同的组合（🌐M 不是 M）。
struct HabitCombo: Hashable {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: UInt8
        static let control = Modifiers(rawValue: 1)
        static let option = Modifiers(rawValue: 2)
        static let shift = Modifiers(rawValue: 4)
        static let command = Modifiers(rawValue: 8)
    }

    let keyCode: UInt16
    let modifiers: Modifiers
    /// 按着 🌐（fn）按字母。方向键、Home、F 键本来就带 fn 位，不算。
    let globe: Bool

    init(_ keyCode: UInt16, _ modifiers: Modifiers = [], globe: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.globe = globe && HabitKey.letters[keyCode] != nil
    }

    // CGEventFlags 的原始位。
    static let controlBit: UInt64 = 0x40000, optionBit: UInt64 = 0x80000, shiftBit: UInt64 = 0x20000
    static let commandBit: UInt64 = 0x100000, fnBit: UInt64 = 0x800000

    /// 从按键事件的原始修饰位取：只看 ⌃⌥⇧⌘（和字母键上的 🌐）。
    init(keyCode: UInt16, flags: UInt64) {
        self.init(keyCode, Self.modifiers(flags: flags), globe: flags & Self.fnBit != 0)
    }

    static func modifiers(flags: UInt64) -> Modifiers {
        var result: Modifiers = []
        if flags & controlBit != 0 { result.insert(.control) }
        if flags & optionBit != 0 { result.insert(.option) }
        if flags & shiftBit != 0 { result.insert(.shift) }
        if flags & commandBit != 0 { result.insert(.command) }
        return result
    }

    /// Carbon 热键（WindowShade 自己注册的快捷键）：cmdKey 0x100、shiftKey 0x200、optionKey 0x800、controlKey 0x1000。
    init(carbonKeyCode: UInt32, carbonModifiers: UInt32) {
        var result: Modifiers = []
        if carbonModifiers & 0x1000 != 0 { result.insert(.control) }
        if carbonModifiers & 0x800 != 0 { result.insert(.option) }
        if carbonModifiers & 0x200 != 0 { result.insert(.shift) }
        if carbonModifiers & 0x100 != 0 { result.insert(.command) }
        self.init(UInt16(truncatingIfNeeded: carbonKeyCode), result)
    }

    /// 键帽一个一个排出来：修饰键按 Apple 的顺序 🌐⌃⌥⇧⌘，最后是键名。
    var parts: [String] {
        var result: [String] = []
        if globe { result.append("🌐") }
        if modifiers.contains(.control) { result.append("⌃") }
        if modifiers.contains(.option) { result.append("⌥") }
        if modifiers.contains(.shift) { result.append("⇧") }
        if modifiers.contains(.command) { result.append("⌘") }
        result.append(HabitKey.name(keyCode))
        return result
    }

    /// 写进句子里的样子：“⌘C”“⌥⌘esc”“⌃⌘空格”。
    var label: String { parts.joined() }
}

// MARK: - 规则

/// 第一批要开口的规则。名字就是记在账上的 id（HabitLedger 按它记），改名等于换一条新规则。
enum HabitRule: String, CaseIterable, Codable {
    // Windows 第一批（docs/stuck-habits.md 第一部分 §2）
    case copy, paste, undo, save, imeShift, closeTab, cut, trash, lineEnds, forceQuit, closeWindow, screenshot, symbols
    // iPad 先上的 6 条（第二部分 §3 的第 6、22、17、7、11、14 条）
    case hideApp, menuBar, dockRemoved, titleDoubleClick, titleFlickUp, desktopSearch

    enum Side { case windows, ipad }

    var side: Side {
        switch self {
        case .hideApp, .menuBar, .dockRemoved, .titleDoubleClick, .titleFlickUp, .desktopSearch: return .ipad
        default: return .windows
        }
    }

    /// 没答来处的人也开：这几条不会误报（Aaron 定，2026-09-29 第 4 条）。
    var anyOrigin: Bool { [.copy, .cut, .save, .trash, .forceQuit, .closeWindow].contains(self) }

    /// ⌃ 家族：副句“常用快捷键把 ⌃ 换成 ⌘”一次教了整个家族；Mac 老手、改过修饰键的人整个家族一起不说。
    var controlFamily: Bool { [.copy, .paste, .undo, .save, .closeTab, .cut].contains(self) }

    /// 上线前要先上真机确认：苹果拼音单按 ⇧ 是否确实没反应、PC 键盘的 PrtSc 是不是到达为 F13。确认之前不开。
    var needsDeviceCheck: Bool { self == .imeShift || self == .screenshot }

    /// 靠按键认出来的那几下（按了没用的那一下）。单按 ⇧、⌥ 加小键盘、鼠标和触控板的几条不在这里，由各自的状态机认。
    var foreignCombos: [HabitCombo] {
        switch self {
        case .copy: return [HabitCombo(HabitKey.c, .control)]
        case .paste: return [HabitCombo(HabitKey.v, .control)]
        case .undo: return [HabitCombo(HabitKey.z, .control)]
        case .save: return [HabitCombo(HabitKey.s, .control)]
        case .closeTab: return [HabitCombo(HabitKey.w, .control)]
        case .cut: return [HabitCombo(HabitKey.x, .control)]
        case .trash: return [HabitCombo(HabitKey.delete), HabitCombo(HabitKey.forwardDelete)]
        case .lineEnds: return [HabitCombo(HabitKey.home), HabitCombo(HabitKey.end)]
        case .forceQuit:
            return [HabitCombo(HabitKey.escape, [.control, .shift]), HabitCombo(HabitKey.forwardDelete, [.control, .option]),
                    HabitCombo(HabitKey.delete, [.control, .option])]
        case .closeWindow: return [HabitCombo(HabitKey.f4, .option)]
        case .screenshot: return [HabitCombo(HabitKey.f13), HabitCombo(HabitKey.f13, .option)]
        case .hideApp: return [HabitCombo(HabitKey.h, .command)]
        case .menuBar: return [HabitCombo(HabitKey.m, globe: true)]
        case .imeShift, .symbols, .dockRemoved, .titleDoubleClick, .titleFlickUp, .desktopSearch: return []
        }
    }

    /// Mac 上的那一下：他自己按了，这条就算会了（W，以及“用过就不再说”）。第一个是要教的那一下。
    var macCombos: [HabitCombo] {
        switch self {
        case .copy: return [HabitCombo(HabitKey.c, .command)]
        case .paste: return [HabitCombo(HabitKey.v, .command)]
        case .undo: return [HabitCombo(HabitKey.z, .command)]
        case .save: return [HabitCombo(HabitKey.s, .command)]
        case .closeTab: return [HabitCombo(HabitKey.w, .command)]
        case .cut: return [HabitCombo(HabitKey.x, .command)]
        case .trash: return [HabitCombo(HabitKey.delete, .command)]
        case .lineEnds: return [HabitCombo(HabitKey.left, .command), HabitCombo(HabitKey.right, .command)]
        case .forceQuit: return [HabitCombo(HabitKey.escape, [.option, .command])]
        case .closeWindow: return [HabitCombo(HabitKey.w, .command), HabitCombo(HabitKey.q, .command)]
        case .screenshot:
            return [HabitCombo(HabitKey.four, [.shift, .command]), HabitCombo(HabitKey.three, [.shift, .command]),
                    HabitCombo(HabitKey.five, [.shift, .command])]
        case .symbols: return [HabitCombo(HabitKey.space, [.control, .command])]
        case .imeShift: return [HabitCombo(HabitKey.space, .control)]
        case .menuBar: return [HabitCombo(HabitKey.f2, .control)]
        case .desktopSearch: return [HabitCombo(HabitKey.space, .command)]
        case .hideApp, .dockRemoved, .titleDoubleClick, .titleFlickUp: return []
        }
    }

    /// 要教的那一下（没有按键可教的几条是 nil）。
    var taughtCombo: HabitCombo? { macCombos.first }

    /// 这条要不要菜单证据 M：前台 App 菜单里有 Mac 那一下，而且没有到达的这个组合；读不到就不说。
    var needsMenu: Bool { controlFamily }

    /// 要不要看剪贴板（按键那一刻在钩子里读一次 changeCount）。
    var watchesPasteboard: Bool { self == .copy || self == .cut || self == .paste }

    /// 按了没用的那一下只在访达里才可能卡住（单按 delete、Del）：访达在前台时才放进钩子的表。
    /// 别的 App 里打字时的每一下退格都不出钩子（查表不中就原样放行），不排队、不读 AX。
    var foreignOnlyInFinder: Bool { self == .trash }
}

/// 一下按键在规则表里是什么意思。
enum HabitSignal: Equatable {
    /// 旧习惯的那一下（按了可能没用）。
    case foreign(HabitRule)
    /// Mac 上的那一下：这条会了。
    case mac(HabitRule)
    /// ⌃E、⌃K（Emacs 派的 Mac 老手在文本里常按）：累计三次，整个 ⌃ 家族不说。
    /// ⌃A、⌃N、⌃P 不算：Windows 用户会按它们全选、新建、打印。
    case emacs
}

/// 钩子回调里查的表：按键码和四个修饰键查，O(1)。只装开着的规则。
struct HabitTable: Equatable {
    private(set) var signals: [HabitCombo: [HabitSignal]] = [:]

    init() {}

    /// finderFront：访达在前台（只在访达里才算数的那几下这时才放进表）。
    init(rules: Set<HabitRule>, emacs: Bool, finderFront: Bool = false) {
        for rule in HabitRule.allCases where rules.contains(rule) {
            if !rule.foreignOnlyInFinder || finderFront {
                for combo in rule.foreignCombos { signals[combo, default: []].append(.foreign(rule)) }
            }
            for combo in rule.macCombos { signals[combo, default: []].append(.mac(rule)) }
        }
        if emacs {
            for code in [HabitKey.e, HabitKey.k] { signals[HabitCombo(code, .control), default: []].append(.emacs) }
        }
    }

    var isEmpty: Bool { signals.isEmpty }

    /// 回调里的判定：自动重复的不算（按住不放不是又按了一次）。
    func classify(keyCode: UInt16, flags: UInt64, autorepeat: Bool) -> [HabitSignal] {
        guard !autorepeat else { return [] }
        return signals[HabitCombo(keyCode: keyCode, flags: flags)] ?? []
    }
}

// MARK: - 来处和开关

enum HabitGate {
    /// 这个来处开哪几条（第一批以内）。要上真机确认的，没确认之前不开。
    static func rules(for origin: SwitcherOrigin, deviceChecked: Set<HabitRule> = []) -> Set<HabitRule> {
        Set(HabitRule.allCases.filter { rule in
            guard !rule.needsDeviceCheck || deviceChecked.contains(rule) else { return false }
            switch origin {
            case .windows: return rule.side == .windows
            case .ipad: return rule.side == .ipad
            case .mac: return false
            case .unanswered: return rule.side == .windows && rule.anyOrigin
            }
        })
    }

    /// 算“开着”时要看的这台 Mac 的情况（在 App 这边读好传进来）。
    struct Environment: Equatable {
        /// 系统设置里对调过修饰键（-currentHost 的 com.apple.keyboard.modifiermapping.*）：分不清他按的是哪个键，⌃ 家族不说。
        var remappedModifiers = false
        /// Karabiner、BetterTouchTool 这类改键工具在跑：单按修饰键的几条和 F13 不说。
        var remapToolRunning = false
        /// 他自己点过刘海回到主屏幕（手势提示那本账里 .notchHome 用过了）：教“回到主屏幕”的几条一起闭嘴。
        var homeLearned = false
        /// 聚焦搜索的快捷键开着：关着就没什么可教。
        var spotlightAvailable = true
    }

    /// 真正开着的规则：来处开的，去掉已经不用再说的（会了、点掉、说满三次、听够了日子）和这台 Mac 上不该说的。
    /// now：墙上时间（Date().timeIntervalSince1970），算桌面两指下滑那条听了多少天。
    static func active(origin: SwitcherOrigin, deviceChecked: Set<HabitRule> = [], memory: HabitMemory,
                       environment: Environment = Environment(), now: TimeInterval = 0) -> Set<HabitRule> {
        // 没答来处、又已经是 Mac 老手（用过三个 ⌘ 版本，或在文本里用 ⌃E、⌃K）：剩下的几条也是 Windows 的习惯，不会再有，
        // 全部不开，钩子整个拆掉（老用户升级后很快回到不听按键的样子；强制退出那条的 ⌥⌘esc 是系统键，钩子看不到，等不来“会了”）。
        if origin == .unanswered, memory.controlFamilySilenced { return [] }
        var result = rules(for: origin, deviceChecked: deviceChecked).filter { !memory.ledger.isDone($0.rawValue) }
        if memory.controlFamilySilenced || environment.remappedModifiers { result = result.filter { !$0.controlFamily } }
        if environment.remapToolRunning { result.subtract([.imeShift, .screenshot]) }
        if environment.homeLearned { result.remove(.hideApp) }
        if !environment.spotlightAvailable { result.remove(.desktopSearch) }
        if memory.shadeLearned { result.subtract([.titleDoubleClick, .titleFlickUp]) }
        if memory.desktopSearchExpired(now: now) { result.remove(.desktopSearch) }
        return result
    }
}

/// 卡住时的提示要记住的事：那本账，加上几条规则自己的进度。存在 Notch.habits 里。
struct HabitMemory: Codable, Equatable {
    var ledger = HabitLedger()
    /// 用 WindowShade 收起过几次（双击、往上甩标题栏）。
    var shadeCollapses = 0
    /// 收起后停过 10 秒以上：他是在用收起窗口，不是想铺满。
    var heldShade = false
    /// ⌃E、⌃K 在文本里按过几次。
    var emacsHits = 0
    /// 桌面两指下滑那条从什么时候开始听（墙上时间）。它要听所有滚动，而“会了”要靠 ⌘空格，
    /// 钩子不一定看得到这个系统键（stuck-habits §4.10 第 3 条待真机确认），所以听满 14 天就收手。
    var desktopSearchSince: TimeInterval?

    static let emacsLimit = 3
    static let collapseLimit = 3
    /// ⌃ 家族里会了几条（他自己按过 ⌘ 版本、或点提示让刘海替他做过）到三条，就当他已经会了整个家族。
    static let familyLimit = 3
    static let desktopSearchDays: TimeInterval = 14

    init() {}

    /// 桌面两指下滑那条听满了日子。
    func desktopSearchExpired(now: TimeInterval) -> Bool {
        guard let since = desktopSearchSince else { return false }
        return now - since > Self.desktopSearchDays * 86_400
    }

    /// 已经是 Mac 老手：用过三个不同的 ⌘ 版本，或者在文本里用 ⌃E、⌃K 用了三次。
    var controlFamilySilenced: Bool {
        emacsHits >= Self.emacsLimit
            || HabitRule.allCases.filter { $0.controlFamily && ledger.used.contains($0.rawValue) }.count >= Self.familyLimit
    }

    /// 双击、往上甩那两条不用再说了：已经收起过三次，或者收起后停过 10 秒。
    var shadeLearned: Bool { heldShade || shadeCollapses >= Self.collapseLimit }

    private enum CodingKeys: String, CodingKey { case ledger, shadeCollapses, heldShade, emacsHits, desktopSearchSince }

    /// 缺哪一项就当没有（以后加字段、读老记录都不会整本作废）。
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ledger = try values.decodeIfPresent(HabitLedger.self, forKey: .ledger) ?? HabitLedger()
        shadeCollapses = try values.decodeIfPresent(Int.self, forKey: .shadeCollapses) ?? 0
        heldShade = try values.decodeIfPresent(Bool.self, forKey: .heldShade) ?? false
        emacsHits = try values.decodeIfPresent(Int.self, forKey: .emacsHits) ?? 0
        desktopSearchSince = try values.decodeIfPresent(TimeInterval.self, forKey: .desktopSearchSince)
    }
}

// MARK: - 永远不说的地方（第 3 节）

enum HabitExclusions {
    /// 终端、自己绑定 ⌃ 键或 Home/End 的编辑器和 IDE、自己认 ⌃ 快捷键的 Office、设计软件、虚拟机和远程桌面。
    static let bundleIDs: Set<String> = [
        // 虚拟机、远程桌面、Windows 兼容层
        "com.microsoft.rdc.macos", "com.microsoft.rdc.mac", "com.vmware.fusion", "com.utmapp.UTM",
        "org.virtualbox.app.VirtualBoxVM", "com.omnissa.horizon.client.mac", "com.vmware.horizon", "com.amazon.workspaces",
        "com.apple.ScreenSharing", "com.apple.RemoteDesktop", "com.realvnc.vncviewer", "com.teamviewer.TeamViewer",
        "com.philandro.anydesk", "com.p5sys.jump.mac.viewer", "com.carriez.rustdesk", "tv.parsec.www",
        "com.moonlight-stream.Moonlight", "com.codeweavers.CrossOver", "com.isaacmarovitz.Whisky", "com.apple.iphonesimulator",
        // 终端
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "org.alacritty", "io.alacritty", "com.github.wez.wezterm", "co.zeit.hyper", "org.tabby", "com.termius-dmg.mac",
        "com.vandyke.SecureCRT", "com.lemonmojo.RoyalTSX.App", "com.panic.prompt.3", "com.raphaelamorim.rio",
        "dev.commandline.waveterm",
        // 编辑器、IDE
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium", "com.todesktop.230313mzl4w4u92",
        "com.exafunction.windsurf", "dev.zed.Zed", "dev.zed.Zed-Preview", "com.google.android.studio", "com.apple.dt.Xcode",
        "org.gnu.Emacs", "org.vim.MacVim", "com.qvacua.VimR", "com.neovide.neovide", "com.barebones.bbedit", "com.panic.Nova",
        // Office
        "com.microsoft.Excel", "com.microsoft.Word", "com.microsoft.Powerpoint", "com.microsoft.Outlook",
        "com.microsoft.onenote.mac", "com.kingsoft.wpsoffice.mac",
        // 设计、3D
        "com.figma.Desktop", "com.bohemiancoding.sketch3", "org.blenderfoundation.blender", "com.maxon.cinema4d",
    ]

    static let prefixes: [String] = [
        "com.parallels.", "com.vmware.proxyApp.", "com.citrix.receiver.", "com.splashtop.", "com.edovia.screens.",
        "com.jetbrains.", "com.sublimetext.", "com.autodesk.", "com.sketchup.",
    ]

    /// 浏览器：网页自己处理 ctrlKey，菜单里看不出来，证据弱，要 R。
    static let browsers: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome", "com.google.Chrome.beta",
        "com.google.Chrome.dev", "com.google.Chrome.canary", "org.chromium.Chromium", "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition", "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.brave.Browser",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "com.kagi.kagimacOS",
        "app.zen-browser.zen",
    ]
    /// 网页 App（PWA）按浏览器处理。
    static let webAppPrefixes: [String] = [
        "com.google.Chrome.app.", "com.microsoft.edgemac.app.", "com.brave.Browser.app.", "com.apple.Safari.WebApp.",
    ]
    /// Chromium 系：焦点报成 AXWebArea 时太粗，当作“不知道”。
    static let chromiumPrefixes: [String] = [
        "com.google.Chrome", "org.chromium.", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.",
        "com.operasoftware.", "com.vivaldi.",
    ]

    /// 网页里的远程桌面、网页 IDE、网页终端、网页版设计软件（读得到网址时比对，后缀匹配）。
    static let hosts: [String] = [
        "remotedesktop.google.com", "windows365.microsoft.com", "client.wvd.microsoft.com", "shell.cloud.google.com",
        "ssh.cloud.google.com", "vscode.dev", "github.dev", "replit.com", "codesandbox.io", "stackblitz.com",
        "colab.research.google.com", "overleaf.com", "figma.com",
    ]

    /// 改键工具：在跑时单按修饰键的几条和 F13 不说。
    static let remapTools: Set<String> = [
        "com.hegenberg.BetterTouchTool", "org.hammerspoon.Hammerspoon", "com.stairways.keyboardmaestro.engine",
        "io.github.imasanari.cmd-eikana", "com.runjuu.Input-Source-Pro",
    ]
    static let remapToolPrefixes: [String] = ["org.pqrs."]

    /// 占着 F13 这类键的全局热键 App：在跑时 Print Screen 那条不说。
    static let hotkeyApps: Set<String> = ["com.elgato.StreamDeck", "com.obsproject.obs-studio", "com.hnc.Discord"]

    /// 网页终端（xterm.js）的输入框。
    static let webTerminalDescription = "Terminal input"

    static func isExcluded(bundleID: String?, executablePath: String?) -> Bool {
        // 没有 bundle id 的前台进程（Wine、qemu、裸 Java），可执行路径里含 wine 的：都不说。
        guard let bundleID, !bundleID.isEmpty else { return true }
        if let path = executablePath?.lowercased(), path.contains("wine") { return true }
        if bundleIDs.contains(bundleID) { return true }
        return prefixes.contains { bundleID.hasPrefix($0) }
    }

    static func isBrowser(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return browsers.contains(bundleID) || webAppPrefixes.contains { bundleID.hasPrefix($0) }
    }

    static func isChromium(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return chromiumPrefixes.contains { bundleID.hasPrefix($0) }
    }

    static func isExcludedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased(), !host.isEmpty else { return false }
        if host.contains("jupyter") { return true }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Info.plist 的 LSApplicationCategoryType 含 games（public.app-category.games、…-games）。
    static func isGame(category: String?, executablePath: String?) -> Bool {
        if let category = category?.lowercased(), category.contains("games") { return true }
        if let path = executablePath?.lowercased(), path.contains("/steamapps/") || path.contains("/steam.app/") { return true }
        return false
    }

    static func isRemapTool(_ bundleID: String) -> Bool {
        remapTools.contains(bundleID) || remapToolPrefixes.contains { bundleID.hasPrefix($0) }
    }
}

// MARK: - 已占用的组合

enum HabitOccupancy {
    /// 按下的那一下、或者要教的那一下，被 WindowShade 的快捷键或 DefaultKeyBinding.dict 占着：这条不说。
    static func isTaken(_ rule: HabitRule, pressed: HabitCombo?, taken: Set<HabitCombo>) -> Bool {
        if let pressed, taken.contains(pressed) { return true }
        if let taught = rule.taughtCombo, taken.contains(taught) { return true }
        return false
    }

    /// ~/Library/KeyBindings/DefaultKeyBinding.dict 里绑定过的组合（键名如 "^c"、"^~a"、"\UF729"）：当作已占用。
    /// ^ ⌃、~ ⌥、$ ⇧、@ ⌘、# 小键盘（不看）；只认字母和 Home、End。
    static func keyBindingCombos(_ bindings: [String: Any]) -> Set<HabitCombo> {
        let letters = Dictionary(uniqueKeysWithValues: HabitKey.letters.map { ($0.value.lowercased(), $0.key) })
        var result = Set<HabitCombo>()
        for key in bindings.keys {
            var modifiers: HabitCombo.Modifiers = []
            var rest = Substring(key)
            while let first = rest.first, "^~$@#".contains(first), rest.count > 1 {
                switch first {
                case "^": modifiers.insert(.control)
                case "~": modifiers.insert(.option)
                case "$": modifiers.insert(.shift)
                case "@": modifiers.insert(.command)
                default: break
                }
                rest = rest.dropFirst()
            }
            let name = String(rest)
            if let code = letters[name.lowercased()] {
                // 大写字母本身就带 ⇧。
                if name != name.lowercased() { modifiers.insert(.shift) }
                result.insert(HabitCombo(code, modifiers))
            } else if name == "\u{F729}" || name.uppercased() == "\\UF729" {
                result.insert(HabitCombo(HabitKey.home, modifiers))
            } else if name == "\u{F72B}" || name.uppercased() == "\\UF72B" {
                result.insert(HabitCombo(HabitKey.end, modifiers))
            }
        }
        return result
    }
}

// MARK: - 菜单证据 M

/// 菜单项上的快捷键：字符（大写）或虚拟键码，加 kAXMenuItemCmdModifiers（0 只有 ⌘；1 ⇧、2 ⌥、4 ⌃、8 不带 ⌘）。
struct HabitMenuKey: Hashable {
    let key: String
    let modifiers: Int

    /// 组合键在菜单里的样子。字母、数字用字符，别的键用虚拟键码。
    init(_ combo: HabitCombo) {
        if let letter = HabitKey.letters[combo.keyCode] ?? HabitKey.digits[combo.keyCode] {
            key = letter
        } else {
            key = "vk:\(combo.keyCode)"
        }
        var value = 0
        if combo.modifiers.contains(.shift) { value |= 1 }
        if combo.modifiers.contains(.option) { value |= 2 }
        if combo.modifiers.contains(.control) { value |= 4 }
        if !combo.modifiers.contains(.command) { value |= 8 }
        modifiers = value
    }

    /// 从菜单项读到的几个属性拼出来。字符是退格、esc、方向、Home/End、F 键这类私用区字符时换成虚拟键码。
    init?(character: String?, virtualKey: Int?, modifiers: Int?) {
        let mods = modifiers ?? 0
        if let character, let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 {
            switch scalar.value {
            case 0x08, 0x7F: self.key = "vk:\(HabitKey.delete)"
            case 0x1B: self.key = "vk:\(HabitKey.escape)"
            case 0xF702: self.key = "vk:\(HabitKey.left)"
            case 0xF703: self.key = "vk:\(HabitKey.right)"
            case 0xF728: self.key = "vk:\(HabitKey.forwardDelete)"
            case 0xF729: self.key = "vk:\(HabitKey.home)"
            case 0xF72B: self.key = "vk:\(HabitKey.end)"
            case 0xF704...0xF726:
                // F1 = 0xF704：换成虚拟键码（只认规则用到的几个）。
                let number = Int(scalar.value) - 0xF703
                let codes: [Int: UInt16] = [2: HabitKey.f2, 4: HabitKey.f4, 13: HabitKey.f13]
                guard let code = codes[number] else { return nil }
                self.key = "vk:\(code)"
            case 0x20: self.key = "vk:\(HabitKey.space)"
            case 0x21...0x7E: self.key = character.uppercased()
            default: return nil
            }
            self.modifiers = mods
            return
        }
        guard let virtualKey, virtualKey >= 0 else { return nil }
        if let letter = HabitKey.letters[UInt16(virtualKey)] {
            self.key = letter
        } else {
            self.key = "vk:\(virtualKey)"
        }
        self.modifiers = mods
    }
}

/// 菜单证据：读不到，或者读到了（有没有 Mac 那一下、有没有到达的这个组合）。
enum HabitMenuEvidence: Equatable {
    case unreadable
    case read(hasMac: Bool, hasForeign: Bool)

    /// M 成立：菜单里有 Mac 那一下，而且没有到达的这个组合。
    var supports: Bool { self == .read(hasMac: true, hasForeign: false) }
}

// MARK: - 焦点

enum HabitFocus: Equatable {
    /// 可编辑的文本。
    case text
    /// 浏览器的地址栏。
    case addressBar
    /// 列表、表格、访达的文件视图。
    case list
    /// 网页正文（Safari 报得准；Chromium 的 AXWebArea 太粗，当作不知道）。
    case page
    /// 密码框：本来也收不到按键，一律不说。
    case secure
    /// 报成粗元素（AXWindow、AXGroup、Chromium 的 AXWebArea）或读不到：不知道，不说。
    case unknown

    var isText: Bool { self == .text || self == .addressBar }
    /// 焦点“明确”不是文本。
    var isNonText: Bool { self == .list || self == .page }

    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    static let listRoles: Set<String> = ["AXList", "AXOutline", "AXTable", "AXBrowser", "AXGrid"]

    /// editable：焦点自己或它的祖先是可编辑的（有 AXEditableAncestor）。inToolbar：浏览器里这个文本框在工具栏里（地址栏）。
    static func classify(role: String?, subrole: String?, editable: Bool, browser: Bool, chromium: Bool,
                         inToolbar: Bool) -> HabitFocus {
        if subrole == "AXSecureTextField" { return .secure }
        if let role, textRoles.contains(role) || editable {
            return browser && inToolbar ? .addressBar : .text
        }
        guard let role else { return .unknown }
        if listRoles.contains(role) { return .list }
        if role == "AXWebArea" { return chromium ? .unknown : .page }
        return .unknown
    }
}

// MARK: - 判定

/// 这一下来自哪种 App：原生、浏览器（网页自己处理 ctrlKey）、套网页的壳（Electron、CEF、QtWebEngine）。
enum HabitAppKind: Equatable { case native, browser, webShell }

/// 一条规则的几种说法。
enum HabitVariant: Equatable {
    case plain
    /// ⌃V 在文本里往下翻了一页。
    case pagedDown
    /// ⌃⌥⌫：只在非文本时说。
    case deleteKey
    /// ⌥F13：截一扇窗口。
    case window
    /// 单按 ⇧：开了“用大写锁定键切换 ABC”。
    case capsLock
    /// 单按 ⇧：🌐 键设成了切换输入法。
    case globe
    /// Home（行首）/ End（行尾）。
    case home, end
    /// 指针所在的屏没有刘海（隐形刘海空着时点不到）：“回到主屏幕”改说启动台快捷键的实际绑定，没绑定就不提。
    case noNotch
}

/// 判断一下按键时看到的一切（App 这边读好，交给 judge）。缺省值都是“不开口”那一边。
struct HabitSituation: Equatable {
    var app: HabitAppKind = .native
    var finder = false
    /// 第 3 节的名单、网页终端、网页 IDE、游戏、演示……
    var excluded = false
    /// 按下的那一下或要教的那一下被 WindowShade、DefaultKeyBinding.dict 占着。
    var taken = false
    var voiceOver = false
    /// 输入法正在组字。
    var composing = false
    var focus: HabitFocus = .unknown
    var menu: HabitMenuEvidence = .unreadable
    /// P：前台、焦点窗口和标题、窗口数、layer>0 的窗口有变化（有反应，或第三方热键接走了）。
    var reacted = false
    var pasteboardChanged = false
    /// 选区长度（读不到是 nil）。
    var selection: Int? = nil
    /// 访达里有选中的项。
    var finderSelection = false
    /// ⌃Z（浏览器）：两次按完字数都没变。
    var charactersUnchanged: Bool? = nil
    /// R：4 秒内第二次同一组合；⌃C/⌃X 没生效后 60 秒内的 ⌃V 也算。
    var repeated = false
    /// ⌃V 的前因：60 秒内 ⌃C/⌃X 没生效，或剪贴板 2 分钟内变过、期间没按过 ⌘C/⌘X。
    var antecedent = false
    /// 访达：离上一次按字母多久（排除按名字选文件）。
    var sinceLetter: TimeInterval = .infinity
    /// Home/End：离上一次按下 fn 多久（排除 Apple 键盘的 fn←）。
    var sinceFn: TimeInterval = .infinity
    /// Home/End：120ms 后光标在行首（行尾）了吗；整段字都在可见范围里吗（滚不动才能说“没反应”）。读不到是 nil。
    var caretAtEdge: Bool? = nil
    var wholeTextVisible: Bool? = nil
    /// ⌥ 加小键盘：松开后多出来的字数和按的数字个数对得上。
    var symbolsTyped = false
    /// 🌐M：3 秒内菜单打开过（或他点了菜单栏）。
    var menuOpened = false
    /// Print Screen：Stream Deck、OBS、Discord 在跑。
    var hotkeyAppRunning = false
    var variant: HabitVariant = .plain
}

enum HabitVerdict: Equatable {
    case teach
    /// 证据弱（浏览器、网页 App、套网页的壳）：等他 4 秒内再按一次。
    case waitForRepeat
    case silent(String)
}

enum HabitRules {
    /// W：按键后等这么久，他自己按了 Mac 那一下就不说、记成会了。
    static let grace: TimeInterval = 0.8
    /// P：按键后这么久比较前后。
    static let settle: TimeInterval = 0.3
    /// Home/End：这么久后看光标。
    static let caretCheck: TimeInterval = 0.12
    /// 访达：按字母后这么久内的 delete 不算（按名字选文件）。
    static let letterQuiet: TimeInterval = 1
    /// Home/End：fn 按下后这么久内的不算（Apple 键盘的 fn←）。
    static let fnQuiet: TimeInterval = 1

    static func judge(_ rule: HabitRule, _ s: HabitSituation) -> HabitVerdict {
        if s.excluded { return .silent("excluded") }
        if s.taken { return .silent("taken") }
        if s.voiceOver { return .silent("voiceover") }
        if s.focus == .secure || s.composing { return .silent("typing") }
        if s.reacted { return .silent("reacted") }
        // 自带编辑器的网页壳（例如 Obsidian）：文本里整个 ⌃ 家族都不说。
        if rule.controlFamily, s.app == .webShell, s.focus.isText { return .silent("editor") }
        let weak = s.app != .native
        switch rule {
        case .copy, .cut:
            guard s.menu.supports else { return .silent("menu") }
            if s.pasteboardChanged { return .silent("copied") }
            if rule == .cut, (s.selection ?? 0) <= 0, !s.finderSelection { return .silent("nothing selected") }
            return weak && !s.repeated ? .waitForRepeat : .teach
        case .paste:
            guard s.focus.isText else { return .silent("not text") }
            guard s.menu.supports else { return .silent("menu") }
            guard s.antecedent else { return .silent("no reason") }
            return weak && !s.repeated ? .waitForRepeat : .teach
        case .undo:
            guard s.focus.isText else { return .silent("not text") }
            guard s.menu.supports else { return .silent("menu") }
            if weak {
                guard s.repeated else { return .waitForRepeat }
                guard s.charactersUnchanged == true else { return .silent("text changed") }
            }
            return .teach
        case .save:
            // 第一批不在浏览器和网页壳里做。
            guard !weak else { return .silent("browser") }
            guard s.menu.supports else { return .silent("menu") }
            return .teach
        case .closeTab:
            guard s.focus.isNonText || s.focus == .addressBar else { return .silent("focus") }
            guard s.menu.supports else { return .silent("menu") }
            return weak && !s.repeated ? .waitForRepeat : .teach
        case .trash:
            guard s.finder, s.focus == .list, s.finderSelection else { return .silent("not a file list") }
            guard s.sinceLetter > letterQuiet else { return .silent("typing a name") }
            return .teach
        case .lineEnds:
            guard s.focus.isText else { return .silent("not text") }
            guard s.sinceFn > fnQuiet else { return .silent("fn arrow") }
            guard let edge = s.caretAtEdge, let whole = s.wholeTextVisible else { return .silent("unreadable") }
            if edge { return .silent("moved") }
            if !whole { return .silent("could scroll") }
            return .teach
        case .forceQuit:
            if s.variant == .deleteKey, !s.focus.isNonText { return .silent("focus") }
            return .teach
        case .closeWindow:
            // 菜单里有 ⌥F4 这一项：它在这个 App 里有用。读不到也照说（它在 Mac 上没有含义）。
            if case .read(_, true) = s.menu { return .silent("menu") }
            return .teach
        case .screenshot:
            return s.hotkeyAppRunning ? .silent("hotkey app") : .teach
        case .symbols:
            guard s.focus.isText, s.symbolsTyped else { return .silent("not typed") }
            return .teach
        case .menuBar:
            guard !s.focus.isText else { return .silent("typed an m") }
            return s.menuOpened ? .silent("found the menu") : .teach
        case .imeShift, .hideApp, .dockRemoved, .titleDoubleClick, .titleFlickUp, .desktopSearch:
            // 这几条的证据在各自的状态机里（HabitShiftTaps、HabitHideWatch……），走到这里已经齐了。
            return .teach
        }
    }
}

// MARK: - P：前后比较

/// 按键前后的样子（都是元数据，不需要录屏权限）。
struct HabitScene: Equatable {
    var frontPID: Int32 = 0
    var focusedWindow: UInt32? = nil
    var focusedTitle: String? = nil
    /// 这个 App 在屏上的普通窗口数。
    var windowCount = 0
    /// 屏上 layer>0 的窗口（不含 WindowShade 自己的）。
    var overlays: Set<UInt32> = []
    var pasteboard: Int? = nil

    /// 前台、焦点窗口和标题、窗口数变了，或者多出了 layer>0 的窗口：有反应（或第三方热键接走了），不说。
    func reacted(to later: HabitScene) -> Bool {
        frontPID != later.frontPID || focusedWindow != later.focusedWindow || focusedTitle != later.focusedTitle
            || windowCount != later.windowCount || !later.overlays.subtracting(overlays).isEmpty
    }

    func pasteboardChanged(to later: HabitScene) -> Bool {
        guard let before = pasteboard, let after = later.pasteboard else { return false }
        return before != after
    }
}

// MARK: - 时间窗

/// R：同一组合 4 秒内又没生效一次；⌃C/⌃X 没生效后 60 秒内的 ⌃V 也算第二次。
/// scale：慢速键开着时，时间窗按比例放宽。
struct HabitRepeats: Equatable {
    static let window: TimeInterval = 4
    static let pairWindow: TimeInterval = 60
    private(set) var misses: [HabitRule: TimeInterval] = [:]

    /// 这一下之前，同一条没生效过、而且还在时间窗里。
    func isRepeat(_ rule: HabitRule, at now: TimeInterval, scale: Double = 1) -> Bool {
        if let last = misses[rule], now > last, now - last <= Self.window * scale { return true }
        if rule == .paste { return copyMissed(before: now, scale: scale) }
        return false
    }

    /// ⌃V 的前因之一：60 秒内 ⌃C 或 ⌃X 没生效过。
    func copyMissed(before now: TimeInterval, scale: Double = 1) -> Bool {
        [HabitRule.copy, .cut].contains { rule in
            guard let last = misses[rule] else { return false }
            return now > last && now - last <= Self.pairWindow * scale
        }
    }

    /// 这一下没反应（P 没变），不管说没说。
    mutating func noteMiss(_ rule: HabitRule, at now: TimeInterval) { misses[rule] = now }
}

/// ⌃V 的另一个前因：剪贴板 2 分钟内变过，期间没按过 ⌘C/⌘X（说明是右键菜单拷贝的）。
/// 没有轮询：每次按到和剪贴板有关的键（⌃C/⌃X/⌃V/⌘C/⌘X/⌘V）时在钩子里读一次 changeCount，拿相邻两次比。
struct HabitClipboard: Equatable {
    static let window: TimeInterval = 120
    private(set) var lastSample: (count: Int, at: TimeInterval)?
    private(set) var lastMacCopyAt: TimeInterval?

    static func == (a: HabitClipboard, b: HabitClipboard) -> Bool {
        a.lastSample?.count == b.lastSample?.count && a.lastSample?.at == b.lastSample?.at && a.lastMacCopyAt == b.lastMacCopyAt
    }

    /// 按 ⌃V 这一刻：上一次看到的剪贴板在 2 分钟以内，现在变了，而且那之后没按过 ⌘C/⌘X。
    func changedWithoutMacCopy(now count: Int, at now: TimeInterval) -> Bool {
        guard let sample = lastSample, now - sample.at <= Self.window, count != sample.count else { return false }
        if let copy = lastMacCopyAt, copy >= sample.at { return false }
        return true
    }

    /// 记下这一次看到的 changeCount（在按键交给 App 之前读的）。macCopy：这一下是 ⌘C 或 ⌘X。
    mutating func sample(_ count: Int, at now: TimeInterval, macCopy: Bool = false) {
        lastSample = (count, now)
        if macCopy { lastMacCopyAt = now }
    }
}

/// 单按 ⇧ 切换中英文（要先上真机确认）：20 秒内第二次才说。
struct HabitShiftTaps: Equatable {
    static let window: TimeInterval = 20
    private(set) var last: TimeInterval?

    /// 返回 true：20 秒内第二次，该说了；说过之后从头数（第三下不算第二次）。
    mutating func tap(at now: TimeInterval) -> Bool {
        if let last, now - last <= Self.window {
            self.last = nil
            return true
        }
        last = now
        return false
    }
}

/// ⌥ 加小键盘数字：按了至少两个，松开 ⌥ 后多出来的字数和数字个数对得上（数字原样打了出来，没打出符号）。
/// 按第一下之前的字数是在按下后才读的，可能已经多了一个，所以差一个也算。
enum HabitAltDigits {
    static func typedAsDigits(count: Int, before: Int?, after: Int?) -> Bool {
        guard count >= 2, let before, let after else { return false }
        let added = after - before
        return added == count || added == count - 1
    }
}

/// iPad 第 6 条：按 ⌘H 回主屏幕，结果把 App 藏起来了。
/// 0.5 秒内这个 App 真的藏了（藏之前有屏上窗口），然后：(a) 藏着的时候没在别的 App 里按键或点按，8 秒内又把它找回来；
/// 或 (b) 3 秒内连按两次 ⌘H，藏了两个不同的 App。第一次就说。卷帘条转发的 ⌘H、“让开这个 App”藏的，都不是先按了 ⌘H，不算。
struct HabitHideWatch: Equatable {
    static let link: TimeInterval = 0.5
    static let comeBack: TimeInterval = 8
    static let twice: TimeInterval = 3

    private struct Press: Equatable { let pid: Int32; let at: TimeInterval; let hadWindows: Bool }
    private struct Hidden: Equatable { let pid: Int32; let at: TimeInterval; var busy: Bool }
    private var press: Press?
    private var hidden: Hidden?
    private var lastHide: (pid: Int32, at: TimeInterval)?

    static func == (a: HabitHideWatch, b: HabitHideWatch) -> Bool {
        a.press == b.press && a.hidden == b.hidden && a.lastHide?.pid == b.lastHide?.pid && a.lastHide?.at == b.lastHide?.at
    }

    /// 正在等他把藏起来的 App 找回来（这段时间要看别处的按键和点按）。
    var watching: Bool { hidden != nil }

    mutating func commandH(pid: Int32, at now: TimeInterval, hadWindows: Bool) {
        press = Press(pid: pid, at: now, hadWindows: hadWindows)
    }

    /// 系统报告藏起了一个 App。返回 true：3 秒里用 ⌘H 连藏了两个不同的 App，该说了。
    mutating func didHide(pid: Int32, at now: TimeInterval) -> Bool {
        guard let p = press, p.pid == pid, now >= p.at, now - p.at <= Self.link, p.hadWindows else { return false }
        press = nil
        if let last = lastHide, last.pid != pid, now - last.at <= Self.twice {
            lastHide = nil
            hidden = nil
            return true
        }
        lastHide = (pid, now)
        hidden = Hidden(pid: pid, at: now, busy: false)
        return false
    }

    /// 藏着的时候在别的 App 里按了键或点了一下（Dock、WindowShade 自己、藏起来的那个不算）。
    mutating func activity(pid: Int32, ignoring: Set<Int32>) {
        guard var h = hidden, pid != h.pid, !ignoring.contains(pid) else { return }
        h.busy = true
        hidden = h
    }

    /// 系统报告又显示了。返回 true：藏起来后没在别处做事，8 秒内又找回来了。
    mutating func didUnhide(pid: Int32, at now: TimeInterval) -> Bool {
        guard let h = hidden, h.pid == pid else { return false }
        hidden = nil
        return !h.busy && now - h.at <= Self.comeBack
    }
}

/// iPad 第 14 条：在桌面上两指往下滑，想找搜索。一次完整的两指手势（不算惯性），换算回手指方向后往下 80 点以上；10 秒内两次。
struct HabitDesktopSwipes: Equatable {
    static let distance: CGFloat = 80
    static let window: TimeInterval = 10
    private(set) var hits: [TimeInterval] = []

    /// 手指往下走了多少：“自然滚动”开着时和滚动量同向，关着时反向。
    static func fingerTravel(deltaY: CGFloat, natural: Bool) -> CGFloat { natural ? deltaY : -deltaY }

    mutating func swipe(fingersDown: CGFloat, onDesktop: Bool, at now: TimeInterval) -> Bool {
        guard onDesktop, fingersDown >= Self.distance else { return false }
        hits = hits.filter { now - $0 <= Self.window } + [now]
        guard hits.count >= 2 else { return false }
        hits = []
        return true
    }
}

/// iPad 第 17 条：把 App 图标从 Dock 拖到屏幕边或正中，想分屏或开窗口，结果图标被移除。
enum HabitDockDrop {
    static let farFromDock: CGFloat = 200
    static let edgeShare: CGFloat = 0.15

    /// 松手的地方像是想分屏或开窗口：屏幕左右 15% 以内，或正中那一块；离按下的地方 200 点以上（在 Dock 附近松手是有意移除）。
    /// 坐标都是全局坐标（左上角原点），screen 是这块屏的范围。
    static func looksLikeSplit(release: CGPoint, press: CGPoint, screen: CGRect) -> Bool {
        guard hypot(release.x - press.x, release.y - press.y) >= farFromDock, screen.contains(release) else { return false }
        let edge = screen.width * edgeShare
        if release.x <= screen.minX + edge || release.x >= screen.maxX - edge { return true }
        return abs(release.x - screen.midX) <= edge && abs(release.y - screen.midY) <= screen.height * 0.25
    }
}

/// iPad 第 7、11 条（WindowShade 自己和 iPad 相反的动作）：双击标题栏、往上甩标题栏，在 iPad 上是铺满，在这里是收起窗口。
/// 只对还没用会收起的人：之前收起不到 3 次，也从没收起后停过 10 秒。收起后 3 秒内又展开同一扇，展开后 10 秒内又想放大它
/// （绿色按钮、拖边角、🌐⌃F、往下拉）：说一次。收起后停过 10 秒，两条永远不说。
struct HabitShadeWatch: Equatable {
    enum Kind: Equatable { case doubleClick, flickUp }
    static let quick: TimeInterval = 3
    static let hold: TimeInterval = 10
    static let enlarge: TimeInterval = 10
    /// 面积大了这么多才算“放大”。
    static let grow: CGFloat = 1.15

    struct Watch: Equatable {
        let kind: Kind
        let collapsedAt: TimeInterval
        var expandedAt: TimeInterval?
        var frame: CGRect?
    }
    private(set) var watches: [UInt32: Watch] = [:]

    static func rule(for kind: Kind) -> HabitRule { kind == .doubleClick ? .titleDoubleClick : .titleFlickUp }

    /// 收起了一扇。之前已经收起过三次、或者停过 10 秒的人不再盯。返回要不要盯这一扇。
    mutating func collapsed(_ id: UInt32, kind: Kind, at now: TimeInterval, priorCollapses: Int, held: Bool) -> Bool {
        guard !held, priorCollapses < HabitMemory.collapseLimit else { return false }
        watches[id] = Watch(kind: kind, collapsedAt: now)
        return true
    }

    enum Check: Equatable {
        /// 已经展开了：接着看他 10 秒内是不是又想放大。
        case waitForEnlarge
        /// 还收着：10 秒时再看一眼。
        case checkHoldLater
        /// 窗口没了或者不认识：不盯了。
        case drop
    }

    /// 收起 3 秒时看一眼。
    mutating func quickCheck(_ id: UInt32, stillShaded: Bool, exists: Bool, frame: CGRect?, at now: TimeInterval) -> Check {
        guard var watch = watches[id] else { return .drop }
        guard exists else { watches[id] = nil; return .drop }
        if stillShaded { return .checkHoldLater }
        guard let frame else { watches[id] = nil; return .drop }
        watch.expandedAt = now
        watch.frame = frame
        watches[id] = watch
        return .waitForEnlarge
    }

    /// 收起 10 秒时还收着：他是在用收起窗口。返回 true 表示从此两条都不说。
    mutating func holdCheck(_ id: UInt32, stillShaded: Bool) -> Bool {
        guard let watch = watches[id], watch.expandedAt == nil else { return false }
        watches[id] = nil
        return stillShaded
    }

    /// 展开后窗口变了样：变大了（或铺满这块屏、进了全屏）就说一次。返回要说的那条。
    mutating func resized(_ id: UInt32, frame: CGRect?, fillsScreen: Bool, at now: TimeInterval) -> HabitRule? {
        guard let watch = watches[id], let expandedAt = watch.expandedAt, let before = watch.frame else { return nil }
        guard now - expandedAt <= Self.enlarge else { watches[id] = nil; return nil }
        let grew = frame.map { $0.width * $0.height >= before.width * before.height * Self.grow } ?? false
        guard grew || fillsScreen else { return nil }
        watches[id] = nil
        return Self.rule(for: watch.kind)
    }

    /// 过了时间窗的都丢掉。
    mutating func expire(at now: TimeInterval) {
        watches = watches.filter { _, watch in
            if let expanded = watch.expandedAt { return now - expanded <= Self.enlarge }
            return now - watch.collapsedAt <= Self.hold + 1
        }
    }

    /// 正在等放大的窗口（鼠标松开、按 🌐⌃F 时去看它们）。
    var enlargeCandidates: [UInt32] { watches.filter { $0.value.expandedAt != nil }.map(\.key) }

    /// 从收起那一刻起，最久盯这么久（3 秒时看一眼，再等 10 秒放大或看他是不是停着）。收起后的普通提示在这段时间里压着。
    static var longest: TimeInterval { quick + max(hold, enlarge) + 1 }
}

// MARK: - 说什么、演什么

/// 刘海里那一小段演示（App/NotchCoach.swift 画）。
enum HabitDemo: Equatable {
    /// 两排键帽：上面一排是刚才按的（变暗），下面一排是 Mac 上的那一下（亮起，修饰键写键帽上的字）。from 为空时只有下面一排。
    case keys(from: [String], to: [String])
    /// 点一下刘海：回到主屏幕。
    case notchHome
    /// 往下甩一下标题栏：铺满屏幕。
    case flickDown
    /// 屏幕最上面的菜单栏亮一下。
    case menuBar
}

enum HabitWords {
    static let controlFamily = "常用快捷键把 ⌃ 换成 ⌘"

    /// 读不到菜单时用系统菜单的叫法。
    static func fallback(_ rule: HabitRule) -> String {
        switch rule {
        case .copy: return "拷贝"
        case .paste: return "粘贴"
        case .cut: return "剪切"
        case .undo: return "撤销"
        case .save: return "存储"
        case .closeTab: return "关闭标签页"
        case .closeWindow: return "关闭窗口"
        case .trash: return "移到废纸篓"
        default: return ""
        }
    }

    /// 菜单项的标题拿来当这句话里的动作：去掉“…”，撤销类的动态标题（“撤销键入”）只留“撤销”；空的、太长的、多行的换成系统的叫法。
    static func command(_ title: String?, for rule: HabitRule) -> String {
        let fallback = fallback(rule)
        guard var text = title?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return fallback }
        for suffix in ["…", "..."] where text.hasSuffix(suffix) { text = String(text.dropLast(suffix.count)) }
        text = text.trimmingCharacters(in: .whitespaces)
        if rule == .undo {
            if text.hasPrefix("撤销") { return "撤销" }
            if text.lowercased().hasPrefix("undo") { return "Undo" }
        }
        guard !text.isEmpty, text.count <= 10, !text.contains("\n") else { return fallback }
        return text
    }

    /// 中文和英文、数字之间留一个空格（Apple 中文文案的习惯）；两边都是中文就直接连上。
    static func join(_ parts: String...) -> String {
        var result = ""
        for part in parts where !part.isEmpty {
            if let last = result.last, let first = part.first, last != " ", first != " ",
               isLatin(last) != isLatin(first), isLatin(last) || isLatin(first), isCJK(last) || isCJK(first) {
                result += " "
            }
            result += part
        }
        return result
    }

    private static func isLatin(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
    private static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    /// 主句和副句。menuTitle：前台 App 菜单里 Mac 那一项的标题；finder：前台是访达（访达没有退出，不说“退出按 ⌘Q”）；
    /// shortcut：实际绑定的组合（桌面两指下滑是聚焦搜索的，没有刘海的屏上 ⌘H 那条是启动台的）。
    static func lines(_ rule: HabitRule, menuTitle: String? = nil, finder: Bool = false, variant: HabitVariant = .plain,
                      shortcut: String? = nil) -> (title: String, subtitle: String) {
        let command = command(menuTitle, for: rule)
        switch rule {
        case .copy: return (join("Mac 上", command, "按 ⌘C"), controlFamily)
        case .cut: return (join("Mac 上", command, "按 ⌘X"), controlFamily)
        case .paste:
            return (join("Mac 上", command, "按 ⌘V"), variant == .pagedDown ? "⌃V 在 Mac 上是往下翻页" : controlFamily)
        case .undo: return (join("Mac 上", command, "按 ⌘Z"), "重做是 ⇧⌘Z")
        case .save: return (join("Mac 上", command, "按 ⌘S"), controlFamily)
        case .closeTab: return (join(command, "按 ⌘W"), finder ? "" : "App 不会跟着退出，退出按 ⌘Q")
        case .closeWindow: return (join(command, "按 ⌘W"), finder ? "" : "退出整个 App 按 ⌘Q")
        case .trash: return (join(command, "按 ⌘delete"), "废纸篓就是回收站")
        case .lineEnds: return ("到行首、行尾按 ⌘← ⌘→", "Home、End 在 Mac 上只滚动页面")
        case .forceQuit: return ("强制退出 App 按 ⌥⌘esc", "看谁占资源，打开“活动监视器”")
        case .screenshot:
            return (variant == .window ? "截这扇窗口：⇧⌘4 再按空格" : "截一块屏幕按 ⇧⌘4", "整屏按 ⇧⌘3；加按 ⌃ 存进剪贴板")
        case .symbols: return ("打特殊符号按 ⌃⌘空格", "在“表情与符号”里搜名字")
        case .imeShift:
            switch variant {
            case .capsLock: return ("切换中英文：轻按 Caps Lock", "按住它才是大写锁定")
            case .globe: return ("切换中英文按一下 🌐", "")
            default: return ("切换中英文按 ⌃空格", "")
            }
        case .hideApp:
            guard variant == .noNotch else { return ("⌘H 是隐藏 App", "回到主屏幕：点一下刘海") }
            return ("⌘H 是隐藏 App", shortcut.map { "回到主屏幕按 \($0)" } ?? "")
        case .menuBar: return ("菜单栏一直在屏幕最上面", "用键盘走到菜单栏按 ⌃F2")
        case .dockRemoved: return ("图标从 Dock 移除了", "并排按 🌐⌃←")
        case .titleDoubleClick: return ("双击标题栏是收起窗口", "铺满屏幕：往下甩一下标题栏")
        case .titleFlickUp: return ("往上甩标题栏是收起窗口", "铺满屏幕：往下甩一下标题栏")
        case .desktopSearch: return ("搜索按 \(shortcut ?? "⌘空格")，和 iPad 一样", "")
        }
    }

    /// 念给 VoiceOver 的样子：修饰键符号换成键名（⌃ 念 Control），第一次听到也知道是哪个键。
    static func spoken(_ text: String) -> String {
        let names: [Character: String] = ["🌐": "fn", "⌃": "Control", "⌥": "Option", "⇧": "Shift", "⌘": "Command"]
        var result = ""
        for character in text {
            if let name = names[character] {
                if let last = result.last, last != " " { result += " " }
                result += name + " "
            } else {
                // 键名后面跟着的空格、标点不再多加一个空格。
                if character == " ", result.last == " " { continue }
                if character.isPunctuation, result.last == " " { result.removeLast() }
                result.append(character)
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// 刘海里演什么。pressed：刚才按的那一下（上面一排）；shortcut：实际绑定的组合拆成的键帽（聚焦搜索的；没有刘海的屏上 ⌘H 那条是启动台的）。
    static func demo(_ rule: HabitRule, pressed: HabitCombo? = nil, variant: HabitVariant = .plain,
                     shortcut: [String]? = nil) -> HabitDemo {
        let from = pressed?.parts ?? []
        switch rule {
        case .hideApp:
            // 没有刘海可点：演他按的 ⌘H，和启动台快捷键（没绑定就只有 ⌘H 那一排）。
            guard variant == .noNotch else { return .notchHome }
            return .keys(from: ["⌘", "H"], to: shortcut ?? [])
        case .titleDoubleClick, .titleFlickUp: return .flickDown
        case .menuBar: return .menuBar
        case .dockRemoved: return .keys(from: [], to: ["🌐", "⌃", "←"])
        case .desktopSearch: return .keys(from: [], to: shortcut ?? ["⌘", "空格"])
        case .lineEnds: return .keys(from: from, to: ["⌘", variant == .end ? "→" : "←"])
        case .symbols: return .keys(from: ["⌥", "1", "2"], to: ["⌃", "⌘", "空格"])
        case .imeShift:
            switch variant {
            case .capsLock: return .keys(from: ["⇧"], to: ["caps lock"])
            case .globe: return .keys(from: ["⇧"], to: ["🌐"])
            default: return .keys(from: ["⇧"], to: ["⌃", "空格"])
            }
        default: return .keys(from: from, to: rule.taughtCombo?.parts ?? [])
        }
    }
}
