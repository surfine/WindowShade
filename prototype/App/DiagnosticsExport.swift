import Cocoa

// 一键导出诊断包（规格 R35／R13）：把运行记录、版本与机器信息、本机的崩溃报告复制进一个新文件夹，
// 放在运行记录文件夹里，然后在访达里显示。只读、只在这一次读；不上传、不计数。
// 入口目前只有命令行 --export-diagnostics；界面上的按钮放哪等设计决定。
@MainActor
enum DiagnosticsExport {
    static var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/WindowShade", isDirectory: true)
    }
    static var crashReportsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    static func facts() -> DiagnosticsBundle.Facts {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let info = Bundle.main.infoDictionary ?? [:]
        return DiagnosticsBundle.Facts(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            model: String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
            cpuCount: ProcessInfo.processInfo.activeProcessorCount,
            displays: NSScreen.screens.count,
            interfaceLanguage: InterfaceLanguagePreference.stored(in: .standard).rawValue,
            accessibility: AXIsProcessTrusted(),
            screenRecording: hasScreenRecordingPermission())
    }

    /// 导出，返回新文件夹。
    static func export(to parent: URL? = nil, now: Date = Date()) throws -> URL {
        let files = FileManager.default
        let folder = (parent ?? logsDirectory).appendingPathComponent(DiagnosticsBundle.folderName(at: now), isDirectory: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let logNames = ((try? files.contentsOfDirectory(atPath: logsDirectory.path)) ?? [])
            .filter { $0.hasPrefix("windowshade") && $0.contains(".log") }.sorted()
        for name in logNames {
            try? files.copyItem(at: logsDirectory.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
        let reportNames = DiagnosticsBundle.ourCrashReports(
            in: (try? files.contentsOfDirectory(atPath: crashReportsDirectory.path)) ?? [])
        if !reportNames.isEmpty {
            let reports = folder.appendingPathComponent("crash-reports", isDirectory: true)
            try files.createDirectory(at: reports, withIntermediateDirectories: true)
            for name in reportNames {
                try? files.copyItem(at: crashReportsDirectory.appendingPathComponent(name), to: reports.appendingPathComponent(name))
            }
        }
        let summary = DiagnosticsBundle.summary(facts(), crashReports: reportNames, logFiles: logNames, exportedAt: now)
        try summary.write(to: folder.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        wlog("diagnostics: exported \(logNames.count) log file(s) and \(reportNames.count) crash report(s)")
        return folder
    }

    static func exportAndReveal() {
        do {
            let folder = try export()
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            wlog("diagnostics: export failed \(error.localizedDescription)")
        }
    }
}
