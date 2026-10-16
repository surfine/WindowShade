// 终端回跳（A1）的纯逻辑：身份校验、TERM_PROGRAM 认 App、tty/目录匹配强度、tmux 参数。无权限、无 UI、无进程。
import Foundation

@main struct TerminalBindingTests {
    nonisolated(unsafe) static var assertions = 0
    static func expect(_ condition: Bool, _ message: String) {
        assertions += 1
        precondition(condition, "断言失败: \(message)")
    }
    typealias M = AgentSessionWindowMatch
    typealias B = TerminalBinding
    typealias I = TerminalIdentity

    static func main() {
        // 身份：字段各自过白名单，不合格的丢字段，全空是 nil。
        let id = I.sanitized(program: "iTerm.app", itermSession: "w0t1p0:6F1A-22", tmuxPane: "%12", tty: "/dev/ttys003")
        expect(id?.program == "iTerm.app" && id?.itermSession == "w0t1p0:6F1A-22" && id?.tmuxPane == "%12" && id?.tty == "/dev/ttys003", "四个字段原样留")
        expect(I.sanitized(program: nil, itermSession: nil, tmuxPane: nil, tty: nil) == nil, "没有任何身份是 nil")
        let partial = I.sanitized(program: "ghostty", itermSession: "bad value;", tmuxPane: "12", tty: "/dev/../etc/passwd")
        expect(partial == I(program: "ghostty"), "不合格的字段整个丢掉，合格的留下")
        expect(I.sanitized(program: "a b", itermSession: "", tmuxPane: "%", tty: "/dev/tty") == nil, "空格、空串、只有 %、没有编号的 tty 都不收")
        expect(!I.validTTY("/dev/ttys0031234") && I.validTTY("/dev/ttys003") && I.validTTY("/dev/ttyp1") && !I.validTTY("/dev/disk0"), "tty 只认终端设备")
        expect(!I.validTmuxPane("%1;rm") && !I.validTmuxPane("%-1") && I.validTmuxPane("%0"), "tmux 窗格编号只认 %数字")
        expect(!I.validProgram(String(repeating: "a", count: 65)), "超长不收")

        // 线上格式：往返；多余字段、非字符串、不合格值、空对象都拒。
        expect(I.parse(wire: id!.wire) == id, "wire 往返")
        expect(I.parse(wire: ["program": "x", "extra": "y"]) == nil, "多余字段拒")
        expect(I.parse(wire: ["program": 1]) == nil, "非字符串拒")
        expect(I.parse(wire: ["tmuxPane": "%1 "]) == nil, "不合格值拒")
        expect(I.parse(wire: [String: String]()) == nil && I.parse(wire: "x") == nil, "空对象和非对象拒")

        // TERM_PROGRAM → App。
        expect(B.searchBundleIDs(for: I(program: "Apple_Terminal")) == ["com.apple.Terminal"], "Terminal")
        expect(B.searchBundleIDs(for: I(program: "iTerm.app")) == ["com.googlecode.iterm2"], "iTerm2")
        expect(B.searchBundleIDs(for: I(program: "ghostty")) == ["com.mitchellh.ghostty"], "Ghostty")
        expect(B.searchBundleIDs(for: I(program: "WarpTerminal")) == ["dev.warp.Warp-Stable"], "Warp")
        expect(B.searchBundleIDs(for: I(program: "vscode")).contains("com.microsoft.VSCode"), "IDE 终端")
        expect(B.searchBundleIDs(for: I(program: "tmux")) == B.defaultTerminalBundleIDs, "tmux 里外面是谁不知道：找默认四个")
        expect(B.searchBundleIDs(for: I(program: "SomethingNew")) == B.defaultTerminalBundleIDs, "不认识：默认四个")
        expect(B.searchBundleIDs(for: nil) == B.defaultTerminalBundleIDs && B.searchBundleIDs(for: I(tmuxPane: "%1")) == B.defaultTerminalBundleIDs, "没有 program：默认四个")
        expect(B.defaultTerminalBundleIDs == M.terminalBundleIDs, "默认四个和原来的一致")

        // 匹配强度：tty 名整段出现算完整匹配，比目录更精确。
        let home = "/Users/a"
        let tty = I(tty: "/dev/ttys003")
        expect(B.titleHasTTY("zsh — ttys003 — 80x24", tty: "/dev/ttys003"), "标题里的 tty 名")
        expect(!B.titleHasTTY("zsh — ttys0030", tty: "/dev/ttys003") && !B.titleHasTTY("ttys0", tty: "/dev/ttys003"), "tty 名只作整段")
        expect(B.strength(identity: tty, cwd: "/Users/a/p", title: "ttys003", document: nil, home: home) == .strong, "tty 命中")
        expect(B.strength(identity: nil, cwd: "/Users/a/p", title: "ttys003", document: nil, home: home) == nil, "没有身份就不看 tty")
        expect(B.strength(identity: tty, cwd: "", title: "ttys003", document: nil, home: home) == .strong, "没有目录也能凭 tty 认")
        expect(B.strength(identity: tty, cwd: "/Users/a/p", title: "~/p", document: nil, home: home) == .strong, "tty 没命中回到目录匹配")
        let candidates: [M.Candidate] = [
            .init(windowID: 1, pid: 10, title: "~/p", document: nil),
            .init(windowID: 2, pid: 10, title: "zsh ttys003", document: nil),
            .init(windowID: 3, pid: 10, title: "other", document: nil),
        ]
        expect(B.best(identity: tty, cwd: "/Users/a/p", among: candidates, home: home)?.windowID == 1, "同强度取前面的")
        expect(B.best(identity: tty, cwd: "", among: candidates, home: home)?.windowID == 2, "同一目录开了两扇窗时，tty 能挑出对的那扇")
        expect(B.best(identity: I(tty: "/dev/ttys099"), cwd: "/Users/a/none", among: candidates, home: home) == nil, "都对不上是 nil：如实说跳不了")

        // tmux 命令：只有合格的窗格编号才有命令；参数里没有别的东西。
        expect(B.tmuxSelectArguments(for: I(tmuxPane: "%12")) == [["select-window", "-t", "%12"], ["select-pane", "-t", "%12"]], "tmux 先窗口后窗格")
        expect(B.tmuxSelectArguments(for: nil) == nil && B.tmuxSelectArguments(for: I(program: "tmux")) == nil, "没有窗格编号就没有命令")
        var bad = I(); bad.tmuxPane = "%1;touch x"
        expect(B.tmuxSelectArguments(for: bad) == nil, "不合格的编号不拼命令")

        print("TerminalBindingTests: \(assertions) assertions passed")
    }
}
