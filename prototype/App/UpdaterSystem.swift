// 应用内更新：碰文件、签名、进程和 launchd 的那一层（不依赖 AppKit 和 Sparkle）。
//
// App、看护（prototype/Watchdog/main.swift）和 tests/run-update-tests.sh 编译同一份：
// 签名要求（DR）比对、找 Sparkle 解开的 App、试跑、备份、换回、提交看护、位置与卷的事实。
// “下一步做什么”的判断都在 Core/UpdateDecisions.swift，这里只做事、只报事实。

import CryptoKit
import Darwin
import Foundation
import Security
import ServiceManagement

// MARK: - 包信息

struct UpdateBundleInfo: Equatable {
    var bundleID: String
    var version: String
    var build: String
    var executable: String
    var minimumSystem: String?

    /// 直接读 Info.plist，不走 Bundle 的缓存：交换后同一路径上的包已经换了。
    init?(appURL: URL) {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) as? [String: Any],
              let bundleID = dict["CFBundleIdentifier"] as? String,
              let build = dict["CFBundleVersion"] as? String else { return nil }
        self.bundleID = bundleID
        self.build = build
        self.version = dict["CFBundleShortVersionString"] as? String ?? build
        self.executable = dict["CFBundleExecutable"] as? String ?? "WindowShade"
        self.minimumSystem = dict["LSMinimumSystemVersion"] as? String
    }
}

// MARK: - 签名要求（DR）

enum UpdateDRVerdict: Equatable {
    case same
    case invalid(String)          // 签名本身不成立
    case notSatisfied(String)     // 不满足旧版的 DR：授权会丢
    case differentString(String)  // 满足，但 DR 字符串变了：下一次更新就没法比了
}

enum UpdateCodeSign {
    static let strictFlags = SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSCheckAllArchitectures)
        | SecCSFlags.RawValue(kSecCSStrictValidate) | SecCSFlags.RawValue(kSecCSCheckNestedCode))

    static func staticCode(_ url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess else { return nil }
        return code
    }

    static func designatedString(_ code: SecStaticCode) -> String? {
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
        return text as String
    }

    private static func selfStaticCode() -> SecStaticCode? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess else { return nil }
        return staticCode
    }

    /// 正在运行这一版的 DR。
    static func runningDR() -> String? { selfStaticCode().flatMap(designatedString) }

    static func staticDR(of url: URL) -> String? { staticCode(url).flatMap(designatedString) }

    /// G1 第 2 步：新版签名严格有效、满足旧 DR，而且自己的 DR 字符串和旧的逐字相同。
    /// 默认不把证书过期算失败（不传 kSecCSConsiderExpiration），和授权数据库一致。
    static func check(_ url: URL, against dr: String) -> UpdateDRVerdict {
        guard let code = staticCode(url) else { return .invalid("no static code") }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(dr as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return .invalid("bad requirement") }
        var error: Unmanaged<CFError>?
        let validity = SecStaticCodeCheckValidityWithErrors(code, strictFlags, nil, &error)
        if validity != errSecSuccess {
            return .invalid(error.map { "\($0.takeRetainedValue())" } ?? "status \(validity)")
        }
        let satisfied = SecStaticCodeCheckValidityWithErrors(code, strictFlags, requirement, &error)
        if satisfied != errSecSuccess {
            return .notSatisfied(error.map { "\($0.takeRetainedValue())" } ?? "status \(satisfied)")
        }
        guard let newDR = designatedString(code) else { return .invalid("no designated requirement") }
        return newDR == dr ? .same : .differentString(newDR)
    }

    /// G1 第 3 步：新版启动后确认自己满足日志里的旧 DR，且 DR 字符串相同。
    static func runningSatisfies(_ dr: String) -> Bool {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(dr as CFString, [], &requirement) == errSecSuccess else { return false }
        guard SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        return runningDR() == dr
    }

    static func teamID(of code: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSSigningInformation)),
                                            &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func teamID(of url: URL) -> String? { staticCode(url).flatMap(teamID) }

    static func runningTeamID() -> String? { selfStaticCode().flatMap(teamID) }

    static func isValid(_ url: URL) -> Bool {
        guard let code = staticCode(url) else { return false }
        return SecStaticCodeCheckValidityWithErrors(code, strictFlags, nil, nil) == errSecSuccess
    }
}

// MARK: - 文件

enum UpdateFiles {
    enum Failure: Error, CustomStringConvertible {
        case tool(String)
        case verify(String)
        case missing(String)
        var description: String {
            switch self {
            case .tool(let s): return "tool: \(s)"
            case .verify(let s): return "verify: \(s)"
            case .missing(let s): return "missing: \(s)"
            }
        }
    }

    static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    struct RunResult {
        var status: Int32
        var output: String
        var timedOut: Bool
    }

    /// 起一个子进程并等它结束；超时先 SIGTERM，1 秒后 SIGKILL。
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 120) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let collected = OutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collected.append(data) }
        }
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return RunResult(status: -1, output: "\(error)", timedOut: false)
        }
        var timedOut = false
        if done.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if done.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = done.wait(timeout: .now() + 2)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        if let rest = try? pipe.fileHandleForReading.readToEnd() { collected.append(rest) }
        return RunResult(status: process.isRunning ? -1 : process.terminationStatus,
                         output: collected.text, timedOut: timedOut)
    }

    private final class OutputBuffer: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()
        func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    static func ditto(_ arguments: [String]) throws {
        let result = run("/usr/bin/ditto", arguments)
        guard result.status == 0 else { throw Failure.tool("ditto \(arguments.joined(separator: " ")): \(result.output)") }
    }

    /// 和目标同一个卷上的临时目录，改名和交换都不跨卷。
    static func replacementDirectory(near url: URL) throws -> URL {
        try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                    appropriateFor: url, create: true)
    }

    /// 解开 zip，里面必须正好一个 .app。
    static func unzipSingleApp(_ zip: URL, into directory: URL) throws -> URL {
        try ditto(["-x", "-k", zip.path, directory.path])
        let apps = (try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "app" }
        guard apps.count == 1 else { throw Failure.verify("expected one app in \(zip.lastPathComponent), found \(apps.count)") }
        return apps[0]
    }

    /// 原子交换两个路径上的东西（APFS 的 renamex_np RENAME_SWAP）。
    static func swap(_ a: URL, _ b: URL) throws {
        guard renamex_np(a.path, b.path, UInt32(RENAME_SWAP)) == 0 else {
            throw Failure.tool("renamex_np swap errno=\(errno)")
        }
    }

    /// 放进目标位置：已有东西就原子交换，交换下来的留在 source 路径上，由调用方处理。
    static func place(_ source: URL, at destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try swap(source, destination)
        } else {
            guard rename(source.path, destination.path) == 0 else { throw Failure.tool("rename errno=\(errno)") }
        }
    }

    static func removeQuarantine(_ root: URL) {
        let name = "com.apple.quarantine"
        removexattr(root.path, name, XATTR_NOFOLLOW)
        guard let items = FileManager.default.enumerator(atPath: root.path) else { return }
        for case let relative as String in items {
            removexattr(root.appendingPathComponent(relative).path, name, XATTR_NOFOLLOW)
        }
    }

    static func creationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }
}

// MARK: - 找 Sparkle 解开的 App

enum UpdateStagedLookup: Equatable {
    case found(URL)
    case none
    case multiple(Int)
}

enum UpdateStaged {
    /// ~/Library/Caches/<bundle id>/org.sparkle-project.Sparkle/Installation/（Sparkle 内部实现，不是 API）
    static func installationRoot(bundleID: String = UpdateIdentity.bundleID) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("org.sparkle-project.Sparkle/Installation", isDirectory: true)
    }

    /// 只看创建时间晚于 startedAt 的第一层临时目录，往里（最多三层）找 bundle ID 和 build 都对的 .app。
    /// 不看 .app 的修改时间：解包保留归档里的时间，一定早于 startedAt。必须正好一个。
    static func find(in root: URL, startedAt: Date, bundleID: String, build: String) -> UpdateStagedLookup {
        let fm = FileManager.default
        guard let firstLevel = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]) else {
            return .none
        }
        var matches: [URL] = []
        for dir in firstLevel {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let created = UpdateFiles.creationDate(dir), created > startedAt else { continue }
            collectApps(in: dir, depth: 3, into: &matches)
        }
        let hits = matches.filter { app in
            guard let info = UpdateBundleInfo(appURL: app) else { return false }
            return info.bundleID == bundleID && info.build == build
        }
        switch hits.count {
        case 0: return .none
        case 1: return .found(hits[0])
        default: return .multiple(hits.count)
        }
    }

    private static func collectApps(in dir: URL, depth: Int, into result: inout [URL]) {
        guard depth > 0,
              let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        else { return }
        for item in items {
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            if item.pathExtension == "app" { result.append(item) } else { collectApps(in: item, depth: depth - 1, into: &result) }
        }
    }
}

// MARK: - 试跑

enum UpdateTrialResult: Equatable {
    case passed
    case failed(String)   // 返回非零、输出里没有 build、框架缺失：记进 refused.json
    case timedOut         // 偶发超时：这次不装，不记坏版本
}

enum UpdateTrial {
    /// 以超时 10 秒运行 `<App>/Contents/MacOS/<可执行文件> --self-check`，要求返回 0、输出里带这次的 build。超时重试一次。
    static func run(app: URL, expectedBuild: String, timeout: TimeInterval = 10) -> UpdateTrialResult {
        guard let info = UpdateBundleInfo(appURL: app) else { return .failed("no Info.plist") }
        let executable = app.appendingPathComponent("Contents/MacOS/\(info.executable)")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { return .failed("no executable") }
        for attempt in 1...2 {
            let result = UpdateFiles.run(executable.path, [UpdateIdentity.selfCheckArgument], timeout: timeout)
            if result.timedOut {
                UpdateLog.write("trial run timed out attempt=\(attempt)")
                continue
            }
            guard result.status == 0 else { return .failed("status \(result.status): \(result.output.suffix(300))") }
            guard result.output.contains("build=\(expectedBuild)") else { return .failed("build missing: \(result.output.suffix(300))") }
            return .passed
        }
        return .timedOut
    }
}

// MARK: - 备份

enum UpdateBackup {
    static func partialURL(for info: UpdateBackupInfo, store: UpdateStore) -> URL {
        store.previousDirectory.appendingPathComponent(info.file + ".partial")
    }

    /// 把当前的 App 压成 Previous/<名>.zip.partial，解到临时目录验签名、确认 DR 等于正在运行的这一版。
    /// 版本、build、DR、SHA-256 都从备份里的 App 读出。不过就抛错，不更新。
    static func make(app: URL, store: UpdateStore, expectedDR: String) throws -> UpdateBackupInfo {
        let fm = FileManager.default
        try fm.createDirectory(at: store.previousDirectory, withIntermediateDirectories: true)
        guard let current = UpdateBundleInfo(appURL: app) else { throw UpdateFiles.Failure.missing("Info.plist") }
        let file = UpdateStore.backupFileName(version: current.version, build: current.build)
        let partial = store.previousDirectory.appendingPathComponent(file + ".partial")
        try? fm.removeItem(at: partial)
        try UpdateFiles.ditto(["-c", "-k", "--keepParent", app.path, partial.path])
        let scratch = try UpdateFiles.replacementDirectory(near: store.previousDirectory)
        defer { try? fm.removeItem(at: scratch) }
        let unpacked = try UpdateFiles.unzipSingleApp(partial, into: scratch)
        guard let info = UpdateBundleInfo(appURL: unpacked) else { throw UpdateFiles.Failure.verify("backup has no Info.plist") }
        let verdict = UpdateCodeSign.check(unpacked, against: expectedDR)
        guard verdict == .same else {
            try? fm.removeItem(at: partial)
            throw UpdateFiles.Failure.verify("backup DR \(verdict)")
        }
        return UpdateBackupInfo(version: info.version, build: info.build, dr: expectedDR,
                                sha256: try UpdateFiles.sha256(partial), file: file, createdAt: Date())
    }

    /// 过关时把 .partial 改成正式名，替换旧备份并写 backup.json；此前旧备份一直留着。
    static func promote(_ info: UpdateBackupInfo, store: UpdateStore) throws -> URL {
        let fm = FileManager.default
        let partial = partialURL(for: info, store: store)
        let final = store.previousDirectory.appendingPathComponent(info.file)
        if let items = try? fm.contentsOfDirectory(at: store.previousDirectory, includingPropertiesForKeys: nil) {
            // 按文件名比：contentsOfDirectory 给的 URL 和拼出来的 URL 形式可能不同（相对/绝对、/private 前缀），直接比 URL 会把 .partial 自己删掉。
            for item in items where item.lastPathComponent != partial.lastPathComponent { try? fm.removeItem(at: item) }
        }
        guard rename(partial.path, final.path) == 0 else { throw UpdateFiles.Failure.tool("rename backup errno=\(errno)") }
        try store.saveBackupInfo(info)
        return final
    }

    static func discardPartials(store: UpdateStore) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: store.previousDirectory, includingPropertiesForKeys: nil) else { return }
        for item in items where item.pathExtension == "partial" { try? fm.removeItem(at: item) }
    }
}

// MARK: - 换回

enum UpdateRestorer {
    /// 先写 refused.json 和 phase=restoring，再动文件：交换后、写日志前掉电，旧版也知道这是换回，不会安静清掉。
    /// 解备份到和 App 同一个卷的临时目录，核对 SHA-256，确认 DR 等于 oldDR（换回也不能丢授权），原子交换，删掉换下来的坏版。
    /// 没做成时写终态 restoreFailed、撤掉 refused.json 里这一条再抛错：交换是最后一步，抛错时装着的仍是新版，
    /// 调用方按路径打开它，它读到 restoreFailed 就照常运行、说一次“没能换回”，不会再交出去形成“启动→退出”的循环。
    static func restore(store: UpdateStore, reason: UpdateRestoreReason) throws {
        guard let journal = store.loadJournal() else { throw UpdateFiles.Failure.missing("journal") }
        store.addRefused(UpdateRefusedEntry(build: journal.to.build, version: journal.to.version, reason: reason, at: Date()))
        store.setPhase(.restoring, reason: reason)
        do {
            try swapInBackup(journal: journal)
        } catch {
            markFailed(store: store, journal: journal)
            throw error
        }
        store.setPhase(.restored, reason: reason)
        UpdateLog.write("restored \(journal.from.version) (\(reason.rawValue))")
    }

    static func markFailed(store: UpdateStore, journal: UpdateJournal) {
        UpdateLog.write("restore of \(journal.from.build) failed; keeping \(journal.to.build)")
        store.setPhase(.restoreFailed)
        store.removeRefused(build: journal.to.build)
    }

    /// 交出去换回之前的快检：备份文件在、名字对得上 from 那一版。完整校验（SHA-256、DR）留给换回本身。
    static func backupUsable(_ journal: UpdateJournal) -> Bool {
        UpdateLaunchPolicy.backupLooksUsable(journal: journal,
                                             fileExists: FileManager.default.fileExists(atPath: journal.backup))
    }

    static func swapInBackup(journal: UpdateJournal) throws {
        let fm = FileManager.default
        let zip = URL(fileURLWithPath: journal.backup)
        guard fm.fileExists(atPath: zip.path) else { throw UpdateFiles.Failure.missing("backup \(zip.lastPathComponent)") }
        if let expected = journal.backupSHA256 {
            let actual = try UpdateFiles.sha256(zip)
            guard actual == expected else { throw UpdateFiles.Failure.verify("backup SHA-256 mismatch") }
        }
        let appURL = URL(fileURLWithPath: journal.appPath)
        let scratch = try UpdateFiles.replacementDirectory(near: appURL)
        defer { try? fm.removeItem(at: scratch) }
        let unpacked = try UpdateFiles.unzipSingleApp(zip, into: scratch)
        guard let info = UpdateBundleInfo(appURL: unpacked), info.build == journal.from.build else {
            throw UpdateFiles.Failure.verify("backup is not \(journal.from.build)")
        }
        let verdict = UpdateCodeSign.check(unpacked, against: journal.oldDR)
        guard verdict == .same else { throw UpdateFiles.Failure.verify("backup DR \(verdict)") }
        try UpdateFiles.place(unpacked, at: appURL)
        // 交换下来的坏版此时在 unpacked 路径上，随临时目录删掉。
    }
}

// MARK: - launchd 任务（看护、Sparkle 的安装器）

/// SMJob* 自 10.10 起弃用，但仍是同步提交一次性 launchd 任务的接口（Sparkle 的安装器也这么提交）。
/// 换成 SMAppService 会改变看护的生命周期，要另立工单；这里只把弃用调用收在一处，经协议转发，
/// 免得警告视为错误时挡住整个构建。
private protocol LegacyLaunchdJobCalls {
    static func copyDictionary(_ domain: CFString, _ label: CFString) -> Unmanaged<CFDictionary>?
    static func remove(_ domain: CFString, _ label: CFString,
                       _ error: UnsafeMutablePointer<Unmanaged<CFError>?>) -> Bool
    static func submit(_ domain: CFString, _ job: CFDictionary,
                       _ error: UnsafeMutablePointer<Unmanaged<CFError>?>) -> Bool
}

private enum SMJobCalls: LegacyLaunchdJobCalls {
    @available(macOS, deprecated: 10.10)
    static func copyDictionary(_ domain: CFString, _ label: CFString) -> Unmanaged<CFDictionary>? {
        SMJobCopyDictionary(domain, label)
    }
    @available(macOS, deprecated: 10.10)
    static func remove(_ domain: CFString, _ label: CFString,
                       _ error: UnsafeMutablePointer<Unmanaged<CFError>?>) -> Bool {
        SMJobRemove(domain, label, nil, true, error)
    }
    @available(macOS, deprecated: 10.10)
    static func submit(_ domain: CFString, _ job: CFDictionary,
                       _ error: UnsafeMutablePointer<Unmanaged<CFError>?>) -> Bool {
        SMJobSubmit(domain, job, nil, error)
    }
}

enum UpdateJobs {
    private static var domain: CFString { kSMDomainUserLaunchd }
    private static let calls: any LegacyLaunchdJobCalls.Type = SMJobCalls.self

    static func dictionary(label: String) -> [String: Any]? {
        guard let unmanaged = calls.copyDictionary(domain, label as CFString) else { return nil }
        return unmanaged.takeRetainedValue() as? [String: Any]
    }

    static func exists(label: String) -> Bool { dictionary(label: label) != nil }

    /// 任务还在跑（有 PID）。LaunchOnlyOnce 的任务跑完后可能仍挂在 launchd 里，不算在跑。
    static func isRunning(label: String) -> Bool { dictionary(label: label)?["PID"] != nil }

    @discardableResult
    static func remove(label: String) -> Bool {
        guard exists(label: label) else { return true }
        var error: Unmanaged<CFError>?
        let ok = calls.remove(domain, label as CFString, &error)
        if !ok { UpdateLog.write("SMJobRemove \(label) failed: \(error.map { "\($0.takeRetainedValue())" } ?? "?")") }
        return ok || !exists(label: label)
    }

    /// 字典照抄 Sparkle 提交安装器的写法：RunAtLoad、LaunchOnlyOnce，不写 plist 文件。
    static func submit(label: String, arguments: [String]) -> Bool {
        remove(label: label)
        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "LaunchOnlyOnce": true,
            "EnableTransactions": false,
            "ProcessType": "Interactive",
        ]
        var error: Unmanaged<CFError>?
        let ok = calls.submit(domain, job as CFDictionary, &error)
        if !ok { UpdateLog.write("SMJobSubmit \(label) failed: \(error.map { "\($0.takeRetainedValue())" } ?? "?")") }
        return ok
    }

    /// 等任务不在跑，最多 timeout 秒。
    static func waitUntilNotRunning(label: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isRunning(label: label) { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return !isRunning(label: label)
    }
}

// MARK: - 看护的交接

enum UpdateGuardHandoff {
    enum Failure: Error { case missing, signature, submit }

    /// 把正在运行这一版里的 Contents/Helpers/WindowShadeUpdateGuard.app 拷到 Update/：换包时它不能在包里。
    /// 拷过去以后验签名和我们同一个 Team。
    static func installCopy(from appBundle: URL, store: UpdateStore) throws {
        let fm = FileManager.default
        let source = appBundle.appendingPathComponent("Contents/Helpers/\(UpdateIdentity.guardAppName)")
        guard fm.fileExists(atPath: source.path) else { throw Failure.missing }
        try fm.createDirectory(at: store.updateDirectory, withIntermediateDirectories: true)
        let destination = store.guardAppURL
        try? fm.removeItem(at: destination)
        try UpdateFiles.ditto([source.path, destination.path])
        guard UpdateCodeSign.isValid(destination),
              let team = UpdateCodeSign.teamID(of: destination), team == UpdateCodeSign.runningTeamID() else {
            try? fm.removeItem(at: destination)
            throw Failure.signature
        }
    }

    static func guardExecutable(store: UpdateStore) -> URL {
        store.guardAppURL.appendingPathComponent("Contents/MacOS/\(UpdateIdentity.guardExecutableName)")
    }

    /// 在用户域提交看护；restore 为 true 时它一起来就换回。
    static func submit(store: UpdateStore, restore: Bool) throws {
        let executable = guardExecutable(store: store)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw Failure.missing }
        var arguments = [executable.path, "--store", store.root.path]
        if restore { arguments.append("--restore") }
        guard UpdateJobs.submit(label: UpdateIdentity.guardLabel, arguments: arguments) else { throw Failure.submit }
    }

    static func remove() { UpdateJobs.remove(label: UpdateIdentity.guardLabel) }

    /// 看护在跑：guard.pid 里的进程还活着，而且确实是看护。
    static func isAlive(store: UpdateStore) -> Bool {
        guard let pid = store.guardPID(), UpdateFacts.isAlive(pid),
              let path = UpdateFacts.processPath(pid) else { return false }
        return path.hasSuffix("/" + UpdateIdentity.guardExecutableName)
    }
}

// MARK: - 位置、卷、进程的事实

enum UpdateFacts {
    static func location(of app: URL, home: String = NSHomeDirectory()) -> UpdateLocationFacts {
        let path = app.path
        let folder = app.deletingLastPathComponent().path
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].path
        return UpdateLocationFacts(
            path: path,
            isTranslocated: UpdatePolicy.isTranslocated(path),
            isReadOnlyVolume: isReadOnly(path),
            isInApplicationsFolder: UpdatePolicy.isApplicationsPath(path, home: home),
            supportsRenameSwap: supportsRenameSwap(path),
            sameVolumeAsCaches: device(folder) != nil && device(folder) == device(caches),
            folderWritable: access(folder, W_OK) == 0,
            appWritable: access(path, W_OK) == 0)
    }

    static func isReadOnly(_ path: String) -> Bool {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return true }
        return (fs.f_flags & UInt32(MNT_RDONLY)) != 0
    }

    static func device(_ path: String) -> dev_t? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return st.st_dev
    }

    static func mountPoint(_ path: String) -> String? {
        var fs = statfs()
        guard statfs(path, &fs) == 0 else { return nil }
        return withUnsafePointer(to: &fs.f_mntonname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// 卷支持 renamex_np 的 RENAME_SWAP（getattrlist 的 VOL_CAP_INT_RENAME_SWAP）。
    static func supportsRenameSwap(_ path: String) -> Bool {
        guard let mount = mountPoint(path) else { return false }
        struct Reply {
            var length: UInt32 = 0
            var caps = vol_capabilities_attr_t()
        }
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_CAPABILITIES)
        var reply = Reply()
        let status = getattrlist(mount, &request, &reply, MemoryLayout<Reply>.size, 0)
        guard status == 0 else { return false }
        let flag = UInt32(VOL_CAP_INT_RENAME_SWAP)
        return (reply.caps.valid.1 & flag) != 0 && (reply.caps.capabilities.1 & flag) != 0
    }

    static func freeBytes(at url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return UInt64(important) }
        var fs = statfs()
        guard statfs(url.path, &fs) == 0 else { return 0 }
        return UInt64(fs.f_bavail) * UInt64(fs.f_bsize)
    }

    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    static func processPath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// 别的用户开着同一路径的 WindowShade（按进程表查，uid 不同）。读不到路径时按“开着”算。
    static func otherUserRunning(executablePath: String, processName: String) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return false }
        let count = size / MemoryLayout<kinfo_proc>.stride + 16
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        size = count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &procs, &size, nil, 0) == 0 else { return false }
        let me = getuid()
        let name = String(processName.prefix(Int(MAXCOMLEN)))
        for proc in procs.prefix(size / MemoryLayout<kinfo_proc>.stride) {
            var comm = proc.kp_proc.p_comm
            let command = withUnsafePointer(to: &comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) { String(cString: $0) }
            }
            guard command == name, proc.kp_eproc.e_ucred.cr_uid != me else { continue }
            guard let path = processPath(proc.kp_proc.p_pid) else { return true }
            if (path as NSString).standardizingPath == (executablePath as NSString).standardizingPath { return true }
        }
        return false
    }

    static func isAdminUser() -> Bool {
        var groups = [gid_t](repeating: 0, count: 64)
        let count = getgroups(Int32(groups.count), &groups)
        guard count > 0 else { return false }
        return groups.prefix(Int(count)).contains(80)
    }
}

// MARK: - 安装前的关（在后台线程跑，只读事实）

enum UpdateGate {
    enum Verdict: Equatable {
        case pass
        case notFound(String)
        case location
        case refusedBefore
        case invalid(String)
        case drChanged(String)
        case systemTooOld(String)
        case trialFailed(String)
        case trialTimedOut
    }

    /// 找到解开的 App、不在 refused.json 里且位置仍成立、比 DR、看系统版本、试跑。
    static func evaluate(journal: UpdateJournal, build: String, bundleID: String, location: UpdateLocationFacts,
                         refused: Bool, installationRoot: URL? = nil) -> Verdict {
        let staged: URL
        let root = installationRoot ?? UpdateStaged.installationRoot(bundleID: bundleID)
        switch UpdateStaged.find(in: root, startedAt: journal.startedAt, bundleID: bundleID, build: build) {
        case .found(let url): staged = url
        case .none: return .notFound("none")
        case .multiple(let n): return .notFound("\(n) candidates")
        }
        if refused { return .refusedBefore }
        if UpdatePolicy.locationBlocksInstall(location) { return .location }
        return check(staged: staged, oldDR: journal.oldDR, build: build)
    }

    /// 看护对“没过关就被装上”的包补关后怎么办：nil 表示放行（按 approved 接着盯 healthy），否则按给出的原因换回。
    /// 试跑偶发超时不算坏包：已经装上了，交给 60 秒的 healthy 去判断。其余不是明确通过的结论一律换回。
    static func afterInstall(_ verdict: Verdict) -> UpdateRestoreReason? {
        switch verdict {
        case .pass, .trialTimedOut: return nil
        case .drChanged: return .drChanged
        case .invalid, .systemTooOld, .trialFailed, .notFound, .location, .refusedBefore: return .selfCheckFailed
        }
    }

    /// DR、系统版本、试跑。看护对“没过关就被装上”的包也跑这一段。
    static func check(staged: URL, oldDR: String, build: String) -> Verdict {
        switch UpdateCodeSign.check(staged, against: oldDR) {
        case .same: break
        case .invalid(let why): return .invalid(why)
        case .notSatisfied(let why): return .drChanged(why)
        case .differentString(let dr): return .drChanged(dr)
        }
        let minimum = UpdateBundleInfo(appURL: staged)?.minimumSystem
        guard UpdateVersion.systemSatisfies(minimum: minimum, system: UpdateVersion.currentSystem) else {
            return .systemTooOld(minimum ?? "?")
        }
        switch UpdateTrial.run(app: staged, expectedBuild: build) {
        case .passed: return .pass
        case .failed(let why): return .trialFailed(why)
        case .timedOut: return .trialTimedOut
        }
    }
}
