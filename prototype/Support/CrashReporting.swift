import Foundation
import PLCrashReporterNative

// 崩溃报告只落本地（规格 R13）：启动时启用 PLCrashReporter（静态链进主程序，Mach 异常方式）；
// 下次启动时若有上次留下的报告，转成文本放进 ~/Library/Logs/WindowShade/crash-reports/（最多 10 份，留最新的），
// 再从崩溃库里清掉。诊断包（DiagnosticsExport）导出时一并带上。
// 没有任何联网代码：崩溃库只写本机缓存目录，我们只把文本存在这台 Mac 上，由用户导出后自己决定交给谁。
// 与现有处理不冲突：全工程没有别的 NSSetUncaughtExceptionHandler 或崩溃信号处理（只有一处忽略 SIGPIPE）。
enum CrashReporting {
    static let keepCount = 10
    static let probeArgument = "--probe-crash"
    static let probeEnvironment = "WINDOWSHADE_ALLOW_CRASH_PROBE"

    /// 崩溃库对象要活到进程结束；只在启动时在主线程设置一次，之后不再访问。
    nonisolated(unsafe) private static var reporter: PLCrashReporter?

    static var reportsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/WindowShade/crash-reports", isDirectory: true)
    }

    /// 启动时调一次：启用，并把上次留下的报告转成文本。被调试器附着时不启用（Mach 处理器会和调试器抢异常口）。
    static func startAtLaunch() {
        guard !isBeingDebugged() else { return }
        let config = PLCrashReporterConfig(signalHandlerType: .mach, symbolicationStrategy: [],
                                           shouldRegisterUncaughtExceptionHandler: true)
        guard let crashReporter = PLCrashReporter(configuration: config) else {
            wlog("crash-reporting: could not create reporter"); return
        }
        // 先取上次的报告再启用：启用本身不会清掉它，但先取更直观。
        saveLastCrashIfAny(crashReporter)
        do {
            try crashReporter.enableAndReturnError()
            reporter = crashReporter
            wlog("crash-reporting: enabled (local only)")
        } catch {
            wlog("crash-reporting: enable failed \(error.localizedDescription)")
        }
    }

    /// 只给探针用：必须同时带 --probe-crash 和环境变量，正式使用不会走到这里。
    static func crashForProbeIfRequested() {
        guard CommandLine.arguments.contains(probeArgument),
              getenv(probeEnvironment) != nil else { return }
        wlog("crash-reporting: probe crash requested")
        fatalError("WindowShade crash probe (R13)")
    }

    private static func saveLastCrashIfAny(_ crashReporter: PLCrashReporter) {
        guard crashReporter.hasPendingCrashReport() else { return }
        defer { _ = crashReporter.purgePendingCrashReport() }
        do {
            let data = try crashReporter.loadPendingCrashReportDataAndReturnError()
            let report = try PLCrashReport(data: data)
            let body = PLCrashReportTextFormatter.stringValue(for: report, with: PLCrashReportTextFormatiOS)
            let crashedAt = report.systemInfo?.timestamp ?? Date()
            let info = Bundle.main.infoDictionary ?? [:]
            let header = [
                "WindowShade crash report (kept on this Mac only; nothing was sent anywhere)",
                "app version: \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))",
                "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                "model: \(hardwareModel()), \(ProcessInfo.processInfo.processorCount) cores",
                "", "",
            ].joined(separator: "\n")
            let directory = reportsDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent(DiagnosticsBundle.ownCrashReportName(at: crashedAt))
            try Data((header + (body ?? "")).utf8).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            prune(directory: directory)
            wlog("crash-reporting: saved last crash as \(url.lastPathComponent)")
        } catch {
            wlog("crash-reporting: could not read last crash \(error.localizedDescription)")
        }
    }

    private static func prune(directory: URL) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in DiagnosticsBundle.ownCrashReportsToDelete(in: names, keep: keepCount) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func isBeingDebugged() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}
