import Foundation

// 规格 R35／R13：诊断包的纯逻辑——文件夹命名、挑出属于我们的崩溃报告、摘要不夹带用户内容。
@main
struct DiagnosticsBundleTests {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL \(what)") } }
        let date = Date(timeIntervalSince1970: 1_792_022_400)   // 2026-10-15 00:00:00 UTC
        check(DiagnosticsBundle.folderName(at: date, timeZone: TimeZone(identifier: "UTC")!) == "WindowShade-Diagnostics-20261015-000000",
              "文件夹名带时间")
        let names = ["WindowShade-2026-10-14-101010.ips", "WindowShade-2026-10-15-090000.ips", "Safari-2026-10-15.ips",
                     "WindowShadeUpdateGuard-2026-10-01.crash", "WindowShade-2026-10-15-090000.ips.tmp", "windowshade_x.hang",
                     "Finder.diag", "WindowShadeHelperNotes.txt"]
        let ours = DiagnosticsBundle.ourCrashReports(in: names)
        check(ours == ["windowshade_x.hang", "WindowShadeUpdateGuard-2026-10-01.crash",
                       "WindowShade-2026-10-15-090000.ips", "WindowShade-2026-10-14-101010.ips"],
              "只挑我们的报告，按名字倒序：\(ours)")
        check(DiagnosticsBundle.ourCrashReports(in: (0..<30).map { "WindowShade-\(1000 + $0).ips" }, limit: 10).count == 10, "最多 10 份")
        check(DiagnosticsBundle.ourCrashReports(in: []).isEmpty, "没有报告时为空")
        let facts = DiagnosticsBundle.Facts(appVersion: "1.0.16", build: "16", macOS: "27.0.1", model: "Mac17,4", cpuCount: 10,
                                            displays: 2, interfaceLanguage: "zhHant", accessibility: true, screenRecording: false)
        let summary = DiagnosticsBundle.summary(facts, crashReports: [], logFiles: ["windowshade.log"], exportedAt: date)
        check(summary.contains("version: 1.0.16 (16)") && summary.contains("crash reports: none on this Mac")
              && summary.contains("screen recording: not granted") && summary.contains("has been sent anywhere"), "摘要几行齐全")
        if failures > 0 { exit(1) }
        print("PASS diagnostics-bundle: folder name, our crash reports only (newest 10), summary lines")
    }
}
