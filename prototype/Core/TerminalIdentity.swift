// 终端回跳（规格 A1）的终端身份：hook 子进程继承来的 TERM_PROGRAM／ITERM_SESSION_ID／TMUX_PANE／tty。
// 纯值与白名单校验；hook 小程序和主程序共用这一份，所以只依赖 Foundation。
import Foundation

/// hook 子进程继承来的终端身份。每个字段都先过白名单，不合格的整个字段丢掉；全空就是没有身份。
struct TerminalIdentity: Equatable, Sendable {
    /// TERM_PROGRAM，例如 Apple_Terminal、iTerm.app、ghostty、WarpTerminal、vscode、tmux。
    var program: String = ""
    /// ITERM_SESSION_ID，例如 w0t1p0:UUID。
    var itermSession: String = ""
    /// TMUX_PANE，例如 %12。
    var tmuxPane: String = ""
    /// tmux 服务器的 socket 路径（$TMUX 的第一段）；用 -L／-S 起了别的服务器时，只有带上它才选得对窗格。
    var tmuxSocket: String = ""
    /// 终端设备，例如 /dev/ttys003。
    var tty: String = ""

    static let wireKeys: Set<String> = ["program", "itermSession", "tmuxPane", "tmuxSocket", "tty"]

    var isEmpty: Bool { program.isEmpty && itermSession.isEmpty && tmuxPane.isEmpty && tmuxSocket.isEmpty && tty.isEmpty }

    private static func matches(_ value: String, _ allowed: (Character) -> Bool, limit: Int, prefix: String = "") -> Bool {
        guard !value.isEmpty, value.utf8.count <= limit, value.hasPrefix(prefix) else { return false }
        return value.dropFirst(prefix.count).allSatisfy(allowed)
    }
    private static func word(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "_" || c == "." || c == "-") }
    private static func digit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    static func validProgram(_ v: String) -> Bool { matches(v, word, limit: 64) }
    static func validITermSession(_ v: String) -> Bool { matches(v, { word($0) || $0 == ":" }, limit: 128) }
    static func validTmuxPane(_ v: String) -> Bool { matches(v, digit, limit: 10, prefix: "%") && v.count > 1 }
    static func validTmuxSocket(_ v: String) -> Bool {
        v.hasPrefix("/") && v.utf8.count <= 104 && v.utf8.allSatisfy { $0 >= 0x20 && $0 < 0x7f }
    }
    static func validTTY(_ v: String) -> Bool {
        guard v.hasPrefix("/dev/tty") else { return false }
        let rest = v.dropFirst("/dev/tty".count)
        let digits = rest.reversed().prefix(while: digit).reversed()
        let letters = rest.dropLast(digits.count)
        return !digits.isEmpty && digits.count <= 4 && letters.count <= 2 && letters.allSatisfy { $0.isASCII && $0.isLowercase }
    }

    /// 原始字符串（来自环境变量）→ 身份。不合格的字段当作没有；全空返回 nil。
    static func sanitized(program: String?, itermSession: String?, tmuxPane: String?, tmuxSocket: String? = nil, tty: String?) -> TerminalIdentity? {
        var result = TerminalIdentity()
        if let v = program, validProgram(v) { result.program = v }
        if let v = itermSession, validITermSession(v) { result.itermSession = v }
        if let v = tmuxPane, validTmuxPane(v) { result.tmuxPane = v }
        if let v = tmuxSocket, validTmuxSocket(v) { result.tmuxSocket = v }
        if let v = tty, validTTY(v) { result.tty = v }
        return result.isEmpty ? nil : result
    }

    /// socket 上的 JSON 对象 → 身份。多余字段、非字符串、不合格的值一律拒（nil）；空对象也拒。
    static func parse(wire object: Any) -> TerminalIdentity? {
        guard let body = object as? [String: Any], !body.isEmpty, Set(body.keys).isSubset(of: wireKeys) else { return nil }
        var result = TerminalIdentity()
        for (key, raw) in body {
            guard let value = raw as? String else { return nil }
            switch key {
            case "program": guard validProgram(value) else { return nil }; result.program = value
            case "itermSession": guard validITermSession(value) else { return nil }; result.itermSession = value
            case "tmuxPane": guard validTmuxPane(value) else { return nil }; result.tmuxPane = value
            case "tmuxSocket": guard validTmuxSocket(value) else { return nil }; result.tmuxSocket = value
            default: guard validTTY(value) else { return nil }; result.tty = value
            }
        }
        return result
    }

    var wire: [String: String] {
        var result: [String: String] = [:]
        if !program.isEmpty { result["program"] = program }
        if !itermSession.isEmpty { result["itermSession"] = itermSession }
        if !tmuxPane.isEmpty { result["tmuxPane"] = tmuxPane }
        if !tmuxSocket.isEmpty { result["tmuxSocket"] = tmuxSocket }
        if !tty.isEmpty { result["tty"] = tty }
        return result
    }
}
