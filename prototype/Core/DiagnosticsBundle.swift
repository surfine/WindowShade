import Foundation

// 一键导出诊断包（规格 R35）与本地崩溃报告（规格 R13）：纯逻辑部分。
// 定案：纯本地，永不上网、不做任何计数。包里是运行记录、版本与机器信息，以及 macOS 自己为
// WindowShade 留在这台 Mac 上的崩溃报告（~/Library/Logs/DiagnosticReports），加上 PLCrashReporter 在本机落的文本报告
// （~/Library/Logs/WindowShade/crash-reports，见 Support/CrashReporting.swift）。
// 导出后在访达里显示，由用户自己看过再决定交给谁。
enum DiagnosticsBundle {
    struct Facts: Equatable {
        var appVersion: String
        var build: String
        var macOS: String
        var model: String
        var cpuCount: Int
        var displays: Int
        var interfaceLanguage: String
        var accessibility: Bool
        var screenRecording: Bool
    }

    /// 文件夹名带时间，便于一次排查导出好几份时分清先后。
    static func folderName(at date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "WindowShade-Diagnostics-%04d%02d%02d-%02d%02d%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// 我们自己（PLCrashReporter）落的文本报告：windowshade-crash-时间.txt，时间用 UTC，名字倒序即新到旧。
    static func ownCrashReportName(at date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "windowshade-crash-%04d%02d%02d-%02d%02d%02dZ.txt",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    static func isOwnCrashReport(_ name: String) -> Bool {
        name.hasPrefix("windowshade-crash-") && name.hasSuffix(".txt")
    }

    /// 超过 keep 份时要删的（旧的）。别的文件不动。
    static func ownCrashReportsToDelete(in names: [String], keep: Int) -> [String] {
        Array(names.filter(isOwnCrashReport).sorted(by: >).dropFirst(max(0, keep)))
    }

    /// 崩溃报告目录里属于我们的：主程序与更新看护的 .ips／.crash／.hang。按名字倒序（时间戳在名字里），最多 limit 份。
    static func ourCrashReports(in names: [String], limit: Int = 10) -> [String] {
        let ours = names.filter { name in
            let lower = name.lowercased()
            let isReport = [".ips", ".crash", ".hang", ".diag"].contains { lower.hasSuffix($0) }
            return isReport && (lower.hasPrefix("windowshade-") || lower.hasPrefix("windowshade_")
                                || lower.hasPrefix("windowshadeupdateguard"))
        }
        return Array(ours.sorted(by: >).prefix(limit))
    }

    /// summary.txt：给人看的几行；没有窗口标题、文件名这类内容。
    static func summary(_ f: Facts, crashReports: [String], logFiles: [String], exportedAt: Date) -> String {
        let iso = ISO8601DateFormatter().string(from: exportedAt)
        var lines = [
            "WindowShade diagnostics",
            "exported: \(iso)",
            "version: \(f.appVersion) (\(f.build))",
            "macOS: \(f.macOS)",
            "model: \(f.model), \(f.cpuCount) cores, \(f.displays) display(s)",
            "interface language: \(f.interfaceLanguage)",
            "accessibility: \(f.accessibility ? "granted" : "not granted")",
            "screen recording: \(f.screenRecording ? "granted" : "not granted")",
            "logs: \(logFiles.isEmpty ? "none" : logFiles.joined(separator: ", "))",
            "crash reports: \(crashReports.isEmpty ? "none on this Mac" : crashReports.joined(separator: ", "))",
            "",
            "Nothing in this folder has been sent anywhere. Look it over before attaching it to a report.",
        ]
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
