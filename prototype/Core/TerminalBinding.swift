// 终端回跳（规格 A1）：hook 把“它跑在哪个终端里”一并报来，这里是纯逻辑——校验、认是哪个 App、窗口匹配强度、
// tmux 切换的参数。不碰窗口、不起进程、不读文件；窗口和进程由 App 层按这里的结论去做。
// 走辅助功能这条路（只需要辅助功能，不要每个终端 App 的自动化授权）：能到窗口，到不了 tab；
// tab 级要 AppleScript 逐 tab 比 tty，那要每个 App 单独授权，这里不做。
import Foundation

enum TerminalBinding {
    /// 以前就找的四个终端 App；身份认不出是哪个时在这几个里找。
    static let defaultTerminalBundleIDs = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable"]

    /// TERM_PROGRAM → 可能的 App。IDE 终端（vscode）一个值对应几个发行版，都列上。
    static func bundleIDs(forProgram program: String) -> [String] {
        switch program {
        case "Apple_Terminal": return ["com.apple.Terminal"]
        case "iTerm.app": return ["com.googlecode.iterm2"]
        case "ghostty": return ["com.mitchellh.ghostty"]
        case "WarpTerminal": return ["dev.warp.Warp-Stable"]
        case "WezTerm": return ["com.github.wez.wezterm"]
        case "vscode": return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "com.vscodium"]
        default: return []
        }
    }

    /// 该去哪几个 App 里找窗口。认得出 TERM_PROGRAM 就只找它（它没开就是找不到，不去别的终端里碰运气）；
    /// 在 tmux 里（TERM_PROGRAM=tmux，外面是哪个终端不知道）、没有身份、不认识的值：回到默认四个。
    static func searchBundleIDs(for identity: TerminalIdentity?) -> [String] {
        guard let program = identity?.program, !program.isEmpty else { return defaultTerminalBundleIDs }
        let known = bundleIDs(forProgram: program)
        return known.isEmpty ? defaultTerminalBundleIDs : known
    }

    /// 窗口标题里作为整段出现的 tty 名（ttys003）。Terminal 打开“显示 tty 名”时标题里会有。
    static func ttyName(_ tty: String) -> String? {
        TerminalIdentity.validTTY(tty) ? String(tty.dropFirst("/dev/".count)) : nil
    }

    static func titleHasTTY(_ title: String?, tty: String) -> Bool {
        guard let title, let name = ttyName(tty) else { return false }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,()[]|—–·-/"))
        return title.components(separatedBy: separators).contains(name)
    }

    /// 在目录匹配（cwd）之外，标题里有 tty 名就当完整匹配：tty 比目录更精确。
    static func strength(identity: TerminalIdentity?, cwd: String, title: String?, document: String?, home: String) -> AgentSessionWindowMatch.Strength? {
        if let tty = identity?.tty, !tty.isEmpty, titleHasTTY(title, tty: tty) { return .strong }
        return AgentSessionWindowMatch.strength(cwd: cwd, title: title, document: document, home: home)
    }

    static func best(identity: TerminalIdentity?, cwd: String, among candidates: [AgentSessionWindowMatch.Candidate], home: String) -> AgentSessionWindowMatch.Candidate? {
        var best: (AgentSessionWindowMatch.Candidate, AgentSessionWindowMatch.Strength)?
        for candidate in candidates {
            guard let value = strength(identity: identity, cwd: cwd, title: candidate.title, document: candidate.document, home: home) else { continue }
            if best == nil || value > best!.1 { best = (candidate, value) }
        }
        return best?.0
    }

    /// tmux：把那个窗格所在的窗口、再把窗格本身选到前面。窗格编号全局唯一，所以只要 -t %N。
    /// 编号没过白名单就没有命令（nil），不拼任何用户给的字符串。
    static func tmuxSelectArguments(for identity: TerminalIdentity?) -> [[String]]? {
        guard let pane = identity?.tmuxPane, TerminalIdentity.validTmuxPane(pane) else { return nil }
        return [["select-window", "-t", pane], ["select-pane", "-t", pane]]
    }
}
