// 应用内更新：更新日志、拒绝过的版本、备份记录（App、看护、新旧两版共用）。
//
// 文件都在 ~/Library/Application Support/WindowShade/ 下：
//   Update/journal.json   这一次更新走到哪一步（phase）、新旧版本、备份、启动记录
//   Update/refused.json   换回过或试跑没过的 build；“拒绝过的版本”只认这一份
//   Update/guard.pid      看护正在跑时写下的 pid
//   Update/WindowShadeUpdateGuard.app  从旧版拷出来的看护
//   Previous/backup.json  备份的版本、build、DR、SHA-256，全部从备份里的 App 读出
//   Previous/WindowShade-<版本>-<build>.zip(.partial)
// 每次写都先写临时文件、F_FULLFSYNC 落盘再原子改名，改名后再同步所在目录：掉电后“先写 restoring 再交换”的顺序仍成立。
// 读改写用 flock 串起来，App 和看护同时写也不丢记录。
// 格式只加字段不改字段：换回后的旧版必须读得懂。

import Foundation

enum UpdateLog {
    /// App 里接到 wlog，看护里接到自己的日志；测试里留空。
    nonisolated(unsafe) static var sink: ((String) -> Void)?
    static func write(_ message: String) { sink?("update: " + message) }
}

enum UpdateIdentity {
    static let bundleID = "com.windowshade.prototype"
    static let guardBundleID = "com.windowshade.prototype.update-guard"
    static let guardLabel = "com.windowshade.prototype.update-guard"
    static let guardAppName = "WindowShadeUpdateGuard.app"
    static let guardExecutableName = "WindowShadeUpdateGuard"
    /// Sparkle 提交安装器时用的 launchd 标签（SUInstallerLauncher：<bundle id>-sparkle-updater）。
    static func sparkleInstallerLabel(bundleID: String = bundleID) -> String { "\(bundleID)-sparkle-updater" }
    /// 看护判断“新版起来了”的依据是日志里的启动记录，不是进程表。
    static let selfCheckArgument = "--self-check"
    static let afterMoveArgument = "--after-move"
}

enum UpdatePhase: String, Codable, CaseIterable {
    case started            // 已备份、已交出看护，交给 Sparkle 下载
    case gating             // 安装前的关在跑
    case approved           // 过关，等 Sparkle 退出、交换、重开
    case launched           // 新版进了 main
    case healthy            // 新版稳定运行 10 秒且自查通过
    case abnormal           // 新版自查没过
    case cancelled          // 他取消，或退出请求把这次更新否决了
    case refused            // 关把这一版拦下
    case installFailed      // 旧版退出后没装上
    case restoring          // 换回做到一半
    case restored           // 已经换回
    case rollbackRequested  // 交给旧版的看护换回（新版自己发起或他在设置里点了）
    case restoreFailed      // 换回没做成（备份缺失、校验不过、交换失败）：终态，装着的那一版照常运行，说一次“没能换回”
}

enum UpdateRestoreReason: String, Codable {
    case crashed            // 新版起不来、没写 cleanExit 就结束、连续崩溃
    case hung               // 60 秒没到 healthy
    case selfCheckFailed    // 试跑没过、装后自查没过
    case drChanged          // 签名要求变了
    case userRequested      // 他在设置里点了“回到 x.y.z”
}

struct UpdateVersionRef: Codable, Equatable {
    var version: String
    var build: String
}

struct UpdatePermissions: Codable, Equatable {
    var accessibility: Bool
    var screenRecording: Bool

    /// 更新前有、现在没有的那几项。
    func lost(comparedTo now: UpdatePermissions) -> Bool {
        (accessibility && !now.accessibility) || (screenRecording && !now.screenRecording)
    }
}

struct UpdateLaunchRecord: Codable, Equatable {
    var build: String
    var pid: Int32
    var startedAt: Date
    var cleanExit: Bool
    var runSeconds: Double
}

struct UpdateJournal: Codable, Equatable {
    var from: UpdateVersionRef
    var to: UpdateVersionRef
    var appPath: String
    var oldDR: String
    /// 备份 zip 的路径：过关前是 .partial，过关后改成正式名。换回只认这里写的那一份。
    var backup: String
    var backupSHA256: String?
    var permissionsBefore: UpdatePermissions
    var phase: UpdatePhase
    var startedAt: Date
    var oldPID: Int32
    var launches: [UpdateLaunchRecord]
    var healthyAt: Date?
    var restoreReason: UpdateRestoreReason?
    /// 发起换回的进程；看护等它退出再动文件。
    var requesterPID: Int32?
}

struct UpdateRefusedEntry: Codable, Equatable {
    var build: String
    var version: String
    var reason: UpdateRestoreReason
    var at: Date
}

struct UpdateBackupInfo: Codable, Equatable {
    var version: String
    var build: String
    var dr: String
    var sha256: String
    var file: String
    var createdAt: Date
}

final class UpdateStore: @unchecked Sendable {  // 只有不可变的 root；并发由 flock 管
    let root: URL

    init(root: URL) { self.root = root }

    static var standard: UpdateStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return UpdateStore(root: base.appendingPathComponent("WindowShade", isDirectory: true))
    }

    var updateDirectory: URL { root.appendingPathComponent("Update", isDirectory: true) }
    var previousDirectory: URL { root.appendingPathComponent("Previous", isDirectory: true) }
    var journalURL: URL { updateDirectory.appendingPathComponent("journal.json") }
    var refusedURL: URL { updateDirectory.appendingPathComponent("refused.json") }
    var guardPIDURL: URL { updateDirectory.appendingPathComponent("guard.pid") }
    /// 开始新一次更新时，上一次成功更新的日志先放这里：这次被取消或拦下时放回去，“回到 x.y.z”还在。
    var stashedJournalURL: URL { updateDirectory.appendingPathComponent("journal.previous.json") }
    var guardAppURL: URL { updateDirectory.appendingPathComponent(UpdateIdentity.guardAppName, isDirectory: true) }
    var backupInfoURL: URL { previousDirectory.appendingPathComponent("backup.json") }
    private var lockURL: URL { updateDirectory.appendingPathComponent(".lock") }

    static func backupFileName(version: String, build: String) -> String {
        "WindowShade-\(version)-\(build).zip"
    }

    // MARK: 编解码

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try Self.decoder.decode(type, from: data) } catch {
            UpdateLog.write("could not decode \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(value)
        try Self.durableWrite(data, to: url)
    }

    enum WriteFailure: Error { case posix(String, Int32) }

    /// 写临时文件 → F_FULLFSYNC → 改名 → 同步目录。APFS 不保证不同文件的数据按写入顺序落盘，
    /// 所以 refused.json、restoring、approved 这几次写必须真的落盘后才能去交换 App。文件都只有几 KB。
    static func durableWrite(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(url.lastPathComponent).\(getpid()).tmp")
        let fd = Darwin.open(temp.path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        guard fd >= 0 else { throw WriteFailure.posix("open", errno) }
        var written = 0
        let ok: Bool = data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return true }
            while written < buffer.count {
                let n = Darwin.write(fd, base + written, buffer.count - written)
                if n < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                written += n
            }
            return true
        }
        let synced = ok && (fcntl(fd, F_FULLFSYNC) == 0 || fsync(fd) == 0)
        let code = errno
        Darwin.close(fd)
        guard synced else {
            unlink(temp.path)
            throw WriteFailure.posix("write", code)
        }
        guard Darwin.rename(temp.path, url.path) == 0 else {
            let code = errno
            unlink(temp.path)
            throw WriteFailure.posix("rename", code)
        }
        let dirFD = Darwin.open(directory.path, O_RDONLY)
        if dirFD >= 0 {
            if fcntl(dirFD, F_FULLFSYNC) != 0 { _ = fsync(dirFD) }
            Darwin.close(dirFD)
        }
    }

    /// 同一台机器上 App、看护、新旧两版的读改写互斥。拿不到锁时照样执行（宁可丢一条启动记录也不卡住启动）。
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        try? FileManager.default.createDirectory(at: updateDirectory, withIntermediateDirectories: true)
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        if fd >= 0 { flock(fd, LOCK_EX) }
        defer {
            if fd >= 0 {
                flock(fd, LOCK_UN)
                close(fd)
            }
        }
        return try body()
    }

    // MARK: 更新日志

    func loadJournal() -> UpdateJournal? { read(UpdateJournal.self, from: journalURL) }

    func saveJournal(_ journal: UpdateJournal) throws { try write(journal, to: journalURL) }

    func clearJournal() { try? FileManager.default.removeItem(at: journalURL) }

    /// 读、改、写一次；body 把日志设为 nil 就删掉它。返回写下去的结果。
    @discardableResult
    func mutateJournal(_ body: (inout UpdateJournal?) -> Void) -> UpdateJournal? {
        withLock {
            var journal = loadJournal()
            body(&journal)
            if let journal {
                do { try saveJournal(journal) } catch { UpdateLog.write("journal write failed: \(error)") }
            } else {
                clearJournal()
            }
            return journal
        }
    }

    /// 只改 phase；日志不在时什么都不做。onlyIf 非空时，当前 phase 不在其中就不改
    ///（看护和新版会同时写：看护补完关只能把 started/gating 改成 approved，不能盖掉新版写下的 launched 或 healthy）。
    @discardableResult
    func setPhase(_ phase: UpdatePhase, reason: UpdateRestoreReason? = nil, onlyIf: Set<UpdatePhase> = []) -> UpdateJournal? {
        mutateJournal { journal in
            guard journal != nil else { return }
            if !onlyIf.isEmpty && !onlyIf.contains(journal!.phase) {
                UpdateLog.write("phase stays \(journal!.phase.rawValue) (wanted \(phase.rawValue))")
                return
            }
            UpdateLog.write("phase \(journal!.phase.rawValue) -> \(phase.rawValue)")
            journal!.phase = phase
            if let reason { journal!.restoreReason = reason }
            if phase == .healthy { journal!.healthyAt = Date() }
        }
    }

    /// 当前日志满足条件就另存一份（覆盖旧的）；不满足就删掉旧的另存。
    func stashJournal(if keep: (UpdateJournal) -> Bool) {
        withLock {
            if let journal = loadJournal(), keep(journal) {
                try? write(journal, to: stashedJournalURL)
            } else {
                try? FileManager.default.removeItem(at: stashedJournalURL)
            }
        }
    }

    /// 这一次（to == build）没成：有另存的就放回去。
    func restoreStashedJournal(replacing build: String) {
        withLock {
            defer { try? FileManager.default.removeItem(at: stashedJournalURL) }
            guard loadJournal()?.to.build == build,
                  let stashed = read(UpdateJournal.self, from: stashedJournalURL) else { return }
            try? saveJournal(stashed)
        }
    }

    func dropStashedJournal() { try? FileManager.default.removeItem(at: stashedJournalURL) }

    // MARK: 拒绝过的版本

    func refused() -> [UpdateRefusedEntry] { read([UpdateRefusedEntry].self, from: refusedURL) ?? [] }

    func isRefused(build: String) -> Bool { refused().contains { $0.build == build } }

    /// 换回没做成时撤掉这一条：装着的仍是它，不能再当成“拒绝过的版本”。
    func removeRefused(build: String) {
        withLock {
            let entries = refused()
            guard entries.contains(where: { $0.build == build }) else { return }
            do { try write(entries.filter { $0.build != build }, to: refusedURL) } catch {
                UpdateLog.write("refused write failed: \(error)")
            }
        }
    }

    func addRefused(_ entry: UpdateRefusedEntry) {
        withLock {
            var entries = refused().filter { $0.build != entry.build }
            entries.append(entry)
            do { try write(entries, to: refusedURL) } catch { UpdateLog.write("refused write failed: \(error)") }
        }
    }

    // MARK: 备份

    func backupInfo() -> UpdateBackupInfo? { read(UpdateBackupInfo.self, from: backupInfoURL) }

    func saveBackupInfo(_ info: UpdateBackupInfo) throws { try write(info, to: backupInfoURL) }

    func backupURL(for info: UpdateBackupInfo) -> URL { previousDirectory.appendingPathComponent(info.file) }

    /// 删掉旧备份和它的记录（7 天后，或下一次更新成功时）。
    func removeBackup() {
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(at: previousDirectory, includingPropertiesForKeys: nil) {
            for item in items { try? fm.removeItem(at: item) }
        }
    }

    // MARK: 看护

    func writeGuardPID(_ pid: Int32) {
        try? FileManager.default.createDirectory(at: updateDirectory, withIntermediateDirectories: true)
        try? "\(pid)".data(using: .utf8)?.write(to: guardPIDURL, options: .atomic)
    }

    func guardPID() -> Int32? {
        guard let text = try? String(contentsOf: guardPIDURL, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func clearGuardPID() { try? FileManager.default.removeItem(at: guardPIDURL) }
}
