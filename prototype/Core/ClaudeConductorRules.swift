import Foundation

/// 指挥页里 Claude 一侧的两条纯规则：认出「没登录」，和转写只留最近几百行。
enum ClaudeConductorRules {
    /// 转写在内存里最多留这么多行（10-29 第 50 条）；更早的行丢掉，屏幕上看到的是最近的。
    static let maxTranscriptLines = 300

    /// 登录失效的文字特征，全小写。只在结构化字段认不出时才看文字。
    private static let loginPhrases = [
        "failed to authenticate",
        "oauth session expired",
        "oauth token has expired",
        "invalid authentication credentials",
        "invalid api key",
        "not logged in",
        "please run /login",
    ]

    /// 这一轮的结果是不是「没登录」。先认结构化字段（api_error_status 为 401），再退到文字。
    static func isLoginFailure(_ result: ClaudeWire.Result) -> Bool {
        guard result.isError else { return false }
        if result.apiErrorStatus == 401 { return true }
        return isLoginFailureText(result.text)
    }

    /// 单条文字（assistant 里的错误提示）。太长的当作模型在聊登录，不算。
    static func isLoginFailureText(_ text: String?) -> Bool {
        guard let text, text.count <= 600 else { return false }
        let lower = text.lowercased()
        return loginPhrases.contains { lower.contains($0) }
    }

    /// 只留最后 `maxLines` 行。没超就原样返回。
    static func trimmed(_ transcript: String, maxLines: Int = maxTranscriptLines) -> String {
        guard maxLines > 0 else { return "" }
        var newlines = 0
        for scalar in transcript.utf8 where scalar == 0x0A { newlines += 1 }
        guard newlines >= maxLines else { return transcript }
        let lines = transcript.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(maxLines).joined(separator: "\n")
    }
}
