// 应用内更新（Core/UpdateVersion、Core/UpdateModels、Core/UpdateDecisions、App/UpdaterSystem）：
// 版本比较、能不能一键更新的判断、每一版启动的收尾、看护的决策表、更新日志的读写、
// 找 Sparkle 解开的 App、备份 / 换回。纯逻辑那部分只喂事实；文件那部分都在 UPDATE_TEST_TMP 下做。
import CryptoKit
import Darwin
import Foundation

@main
struct UpdateTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }
    static func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: String) {
        expect(a == b, a == b ? message : "\(message)（得到 \(a)，应为 \(b)）")
    }
    static func scratch(_ name: String) -> URL {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["UPDATE_TEST_TMP"] ?? NSTemporaryDirectory())
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func write(_ text: String, to url: URL) {
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! text.write(to: url, atomically: true, encoding: .utf8)
    }
    static func iso(_ date: Date) -> Date {
        ISO8601DateFormatter().date(from: ISO8601DateFormatter().string(from: date))!
    }

    static func main() {
        versionAndSystem()
        policy()
        uncleanLaunches()
        launchDecisions()
        guardPolicy()
        gateAfterInstall()
        permissions()
        store()
        stagedFind()
        signedApps()
        if failures == 0 {
            print("PASS: update — 版本比较、能不能一键更新的判断、每一版启动的收尾、看护的决策表、日志读写、找解开的 App、备份与换回")
        } else {
            print("FAILED \(failures)")
            exit(1)
        }
    }

    // MARK: - 1 版本

    static func versionAndSystem() {
        expect(UpdateVersion.compare("14.0", "14.0.0") == .orderedSame, "\"14.0\" == \"14.0.0\"")
        expect(UpdateVersion.isNewer("17", than: "16"), "\"17\" 比 \"16\" 新")
        expect(UpdateVersion.isNewer("1.0.10", than: "1.0.9"), "\"1.0.10\" 比 \"1.0.9\" 新")
        expect(UpdateVersion.compare("1.0b2", "1.0") == .orderedSame, "\"1.0b2\" 按 1.0 算")
        expect(UpdateVersion.systemSatisfies(minimum: nil, system: "14.0.0"), "清单没写最低系统：都满足")
        expect(UpdateVersion.systemSatisfies(minimum: "14.0", system: "14.0.0"), "min 14.0 ≤ 系统 14.0.0")
        expect(!UpdateVersion.systemSatisfies(minimum: "27.1", system: "26.0"), "min 27.1 > 系统 26.0")
        expect(!UpdateVersion.systemSatisfies(minimum: "14.0", system: "13.9.9"), "min 14.0 > 系统 13.9.9")
    }

    // MARK: - 2 能不能一键更新

    static func location(_ path: String = "/Applications/WindowShade.app", translocated: Bool = false,
                         readOnly: Bool = false, inApplications: Bool = true, renameSwap: Bool = true,
                         sameVolume: Bool = true, folderWritable: Bool = true, appWritable: Bool = true) -> UpdateLocationFacts {
        UpdateLocationFacts(path: path, isTranslocated: translocated, isReadOnlyVolume: readOnly,
                            isInApplicationsFolder: inApplications, supportsRenameSwap: renameSwap,
                            sameVolumeAsCaches: sameVolume, folderWritable: folderWritable, appWritable: appWritable)
    }

    static func policy() {
        // needsMove
        expect(UpdatePolicy.needsMove(location(translocated: true)), "被系统挪走：needsMove")
        expect(UpdatePolicy.needsMove(location(inApplications: false)), "不在“应用程序”里：needsMove")
        expect(UpdatePolicy.needsMove(location(readOnly: true)), "只读卷：needsMove")
        expect(!UpdatePolicy.needsMove(location()), "正常位置：不 needsMove")
        // unsupportedVolume
        expect(UpdatePolicy.unsupportedVolume(location(sameVolume: false)), "和缓存不同卷：unsupportedVolume")
        expect(UpdatePolicy.unsupportedVolume(location(renameSwap: false)), "卷不支持交换：unsupportedVolume")
        expect(!UpdatePolicy.unsupportedVolume(location()), "同一卷且支持交换：不 unsupportedVolume")
        // 顺序：位置先于卷、卷先于权限
        let sameVolumeFalse = location(sameVolume: false)
        expectEqual(UpdatePolicy.blocker(location: sameVolumeFalse, otherUserRunning: false, freeBytes: UInt64.max,
                                         packageBytes: 0, refused: false, ignoreRefused: false),
                    .unsupportedVolume, "在 /Applications 但和缓存不同卷：unsupportedVolume")
        expect(!UpdatePolicy.needsMove(sameVolumeFalse), "同一情形 needsMove 为 false")
        expectEqual(UpdatePolicy.blocker(location: sameVolumeFalse, otherUserRunning: false, freeBytes: 0,
                                         packageBytes: 0, refused: false, ignoreRefused: false),
                    .unsupportedVolume, "卷的问题排在空间前面")
        expectEqual(UpdatePolicy.blocker(location: location(appWritable: false), otherUserRunning: false,
                                         freeBytes: UInt64.max, packageBytes: 0, refused: false, ignoreRefused: false),
                    .needsAdmin, "写不进去：needsAdmin")
        expectEqual(UpdatePolicy.blocker(location: location(folderWritable: false), otherUserRunning: false,
                                         freeBytes: UInt64.max, packageBytes: 0, refused: false, ignoreRefused: false),
                    .needsAdmin, "目录写不进去：needsAdmin")
        expectEqual(UpdatePolicy.blocker(location: location(), otherUserRunning: true, freeBytes: UInt64.max,
                                         packageBytes: 0, refused: false, ignoreRefused: false),
                    .otherUserRunning, "别的用户开着：otherUserRunning")
        expectEqual(UpdatePolicy.blocker(location: location(), otherUserRunning: false,
                                         freeBytes: 64 * 1024 * 1024 * 3, packageBytes: 64 * 1024 * 1024,
                                         refused: false, ignoreRefused: false),
                    .lowSpace, "空间不到 4 倍：lowSpace")
        expectEqual(UpdatePolicy.blocker(location: location(), otherUserRunning: false,
                                         freeBytes: 64 * 1024 * 1024 * 4, packageBytes: 64 * 1024 * 1024,
                                         refused: false, ignoreRefused: false),
                    nil, "正好 4 倍：放行")
        expectEqual(UpdatePolicy.blocker(location: location(), otherUserRunning: false, freeBytes: UInt64.max,
                                         packageBytes: 0, refused: true, ignoreRefused: false),
                    .refusedBefore, "拒绝过的版本：refusedBefore")
        expectEqual(UpdatePolicy.blocker(location: location(), otherUserRunning: false, freeBytes: UInt64.max,
                                         packageBytes: 0, refused: true, ignoreRefused: true),
                    nil, "ignoreRefused：拒绝过的版本也放行")
        // 空间：清单没写大小按 64 MB × 4；溢出按不够算，不崩。
        expect(UpdatePolicy.hasEnoughSpace(freeBytes: 64 * 1024 * 1024 * 4, packageBytes: 0), "没写大小按 64 MB × 4")
        expect(!UpdatePolicy.hasEnoughSpace(freeBytes: 64 * 1024 * 1024 * 4 - 1, packageBytes: 0), "差 1 字节算不够")
        expect(!UpdatePolicy.hasEnoughSpace(freeBytes: UInt64.max, packageBytes: UInt64.max), "包大小溢出：算不够，不崩")
        // isApplicationsPath / locationBlocksInstall
        expect(UpdatePolicy.isApplicationsPath("/Applications/WindowShade.app", home: "/Users/x"), "/Applications/… 算")
        expect(UpdatePolicy.isApplicationsPath("/Users/x/Applications/WindowShade.app", home: "/Users/x"),
               "~/Applications/… 算")
        expect(!UpdatePolicy.isApplicationsPath("/Applications2/x.app", home: "/Users/x"),
               "/Applications2/… 是另一个目录")
        expect(!UpdatePolicy.isApplicationsPath("/Applications", home: "/Users/x"), "“/Applications” 自己不算")
        expect(UpdatePolicy.locationBlocksInstall(location(appWritable: false)), "写不进去：不装")
        expect(UpdatePolicy.locationBlocksInstall(location(sameVolume: false)), "不同卷：不装")
        expect(!UpdatePolicy.locationBlocksInstall(location()), "位置、卷、权限都成立：可以装")
        expect(UpdatePolicy.isTranslocated("/private/var/folders/x/AppTranslocation/1/d/WindowShade.app"),
               "AppTranslocation 路径算被挪走")
        expect(!UpdatePolicy.isTranslocated("/Applications/WindowShade.app"), "正常路径不算被挪走")
        // shouldOffer
        expect(!UpdatePolicy.shouldOffer(build: "17", refusedBuilds: ["17"], userInitiated: false),
               "定时检查不提醒拒绝过的版本")
        expect(UpdatePolicy.shouldOffer(build: "17", refusedBuilds: ["17"], userInitiated: true),
               "手动检查照常列出拒绝过的版本")
        // canRollBack
        let now = Date()
        let journal = UpdateJournal(from: ref("16.0", "16"), to: ref("17.0", "17"),
                                    appPath: "/Applications/WindowShade.app", oldDR: "dr", backup: "/x.zip",
                                    backupSHA256: nil, permissionsBefore: UpdatePermissions(accessibility: true, screenRecording: false),
                                    phase: .healthy, startedAt: now.addingTimeInterval(-3600), oldPID: 1, launches: [],
                                    healthyAt: now.addingTimeInterval(-3600), restoreReason: nil, requesterPID: nil)
        let backup = UpdateBackupInfo(version: "16.0", build: "16", dr: "dr", sha256: "s",
                                      file: "WindowShade-16.0-16.zip", createdAt: now)
        expect(UpdatePolicy.canRollBack(journal: journal, myBuild: "17", backup: backup,
                                        backupExists: true, guardExists: true, now: now), "7 天内健康：能回到旧版")
        expect(!UpdatePolicy.canRollBack(journal: journal, myBuild: "17", backup: backup,
                                         backupExists: true, guardExists: true, now: now.addingTimeInterval(8 * 24 * 3600)),
               "超过 7 天：不再提供“回到”")
        expect(!UpdatePolicy.canRollBack(journal: journal, myBuild: "17", backup: backup,
                                         backupExists: false, guardExists: true, now: now), "备份不在：不能回到")
    }

    // MARK: - 3 连续没正常结束的启动

    static func uncleanLaunches() {
        let now = Date()
        func record(_ build: String, clean: Bool, run: Double) -> UpdateLaunchRecord {
            UpdateLaunchRecord(build: build, pid: 10, startedAt: now, cleanExit: clean, runSeconds: run)
        }
        expectEqual(UpdateLaunchPolicy.consecutiveUnclean([record("17", clean: false, run: 5),
                                                           record("17", clean: false, run: 7)], build: "17"),
                    2, "连着两次没正常结束：数到 2")
        expectEqual(UpdateLaunchPolicy.consecutiveUnclean([record("17", clean: false, run: 5),
                                                           record("17", clean: true, run: 5),
                                                           record("17", clean: false, run: 5)], build: "17"),
                    1, "中间有一次 cleanExit：只数后面那一次")
        expectEqual(UpdateLaunchPolicy.consecutiveUnclean([record("17", clean: false, run: UpdatePolicy.normalRunSeconds),
                                                           record("17", clean: false, run: 5)], build: "17"),
                    1, "再往前有一次跑满 30 分钟：数到那里就停")
        expectEqual(UpdateLaunchPolicy.consecutiveUnclean([record("17", clean: false, run: 5),
                                                           record("17", clean: false, run: UpdatePolicy.normalRunSeconds)], build: "17"),
                    0, "最后一条跑满 30 分钟：不算连崩")
        expectEqual(UpdateLaunchPolicy.consecutiveUnclean([record("16", clean: false, run: 5),
                                                           record("17", clean: false, run: 5)], build: "17"),
                    1, "别的 build 的启动记录不参与")
        expectEqual(UpdateLaunchPolicy.consecutiveUnclean([record("17", clean: true, run: 1)], build: "17"),
                    0, "最后一条正常结束：0")
        expectEqual(UpdateLaunchPolicy.consecutiveUnclean([], build: "17"), 0, "没有记录：0")
    }

    // MARK: - 4 每一版启动时的收尾

    static let appPath = "/Applications/WindowShade.app"
    static let otherPath = "/Users/x/Downloads/WindowShade.app"

    static func ref(_ version: String, _ build: String) -> UpdateVersionRef {
        UpdateVersionRef(version: version, build: build)
    }

    static func permissions() {
        let before = UpdatePermissions(accessibility: true, screenRecording: true)
        expect(before.lost(comparedTo: UpdatePermissions(accessibility: false, screenRecording: true)),
               "更新前有辅助功能、更新后没有：丢了")
        expect(before.lost(comparedTo: UpdatePermissions(accessibility: true, screenRecording: false)),
               "更新前有录屏、更新后没有：丢了")
        expect(!before.lost(comparedTo: before), "都没有变：没丢")
        expect(!UpdatePermissions(accessibility: false, screenRecording: false)
                .lost(comparedTo: UpdatePermissions(accessibility: false, screenRecording: false)),
               "更新前就没有：不算丢")
    }

    static func journal(_ phase: UpdatePhase, launches: [UpdateLaunchRecord] = [],
                        healthyAt: Date? = nil, reason: UpdateRestoreReason? = nil,
                        from: UpdateVersionRef? = nil, to: UpdateVersionRef? = nil,
                        backup: String? = nil) -> UpdateJournal {
        UpdateJournal(from: from ?? ref("16.0", "16"), to: to ?? ref("17.0", "17"), appPath: appPath,
                      oldDR: "identifier \"com.windowshade.prototype\"", backup: backup ?? "/tmp/x/WindowShade-16.0-16.zip",
                      backupSHA256: "sha", permissionsBefore: UpdatePermissions(accessibility: true, screenRecording: false),
                      phase: phase, startedAt: iso(Date().addingTimeInterval(-3600)), oldPID: 9, launches: launches,
                      healthyAt: healthyAt, restoreReason: reason, requesterPID: nil)
    }

    static func launchRecord(_ build: String, clean: Bool = false, run: Double = 5) -> UpdateLaunchRecord {
        UpdateLaunchRecord(build: build, pid: 10, startedAt: Date(), cleanExit: clean, runSeconds: run)
    }

    static func context(_ journal: UpdateJournal, myBuild: String, guardAlive: Bool,
                        myPath: String = appPath, backupUsable: Bool = true,
                        now: Date = Date()) -> UpdateLaunchContext {
        UpdateLaunchContext(journal: journal, myBuild: myBuild, myPath: myPath, guardAlive: guardAlive,
                            now: now, backupUsable: backupUsable)
    }

    static func launchDecisions() {
        // 不是日志里那个位置：什么都不做
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.approved), myBuild: "17", guardAlive: false, myPath: otherPath)),
                    .none, "位置不对（下载目录里的原件）：none")
        // 新版：phase 决定怎么收尾
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.approved), myBuild: "17", guardAlive: false)),
                    .recordAndContinue(selfCheckNow: false), "approved：记一条自检不用现在跑")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.started), myBuild: "17", guardAlive: true)),
                    .recordAndContinue(selfCheckNow: true), "started、看护在跑：记一条并现在自查")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.started), myBuild: "17", guardAlive: false)),
                    .recordAndContinue(selfCheckNow: true), "started、看护不在：仍记一条并自查")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.started, launches: [launchRecord("17")]),
                                                      myBuild: "17", guardAlive: false)),
                    .handToGuard(.crashed), "没过关就装上、上一次又是崩的：交回去换回(crashed)")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.launched, launches: [launchRecord("17")]),
                                                      myBuild: "17", guardAlive: false)),
                    .handToGuard(.crashed), "launched、看护已走、上次崩：交回去换回(crashed)")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.launched, launches: [launchRecord("17")]),
                                                      myBuild: "17", guardAlive: false, backupUsable: false)),
                    .announceRestoreFailed, "同样情形但备份不可用：说一次“没能换回”")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.launched, launches: [launchRecord("17")]),
                                                      myBuild: "17", guardAlive: true)),
                    .recordAndContinue(selfCheckNow: false), "launched、看护还在：照常记一条")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.launched, launches: [launchRecord("17", clean: true)]),
                                                      myBuild: "17", guardAlive: false)),
                    .recordAndContinue(selfCheckNow: false), "launched、上次正常结束：照常记一条")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.launched, launches: [launchRecord("16")]),
                                                      myBuild: "17", guardAlive: false)),
                    .recordAndContinue(selfCheckNow: false), "launched、上次崩的是旧版：不算")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.healthy, launches: [launchRecord("17"), launchRecord("17")]),
                                                      myBuild: "17", guardAlive: false)),
                    .handToGuard(.crashed), "healthy 但连着两次崩：再启动时换回")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.healthy, launches: [launchRecord("17")]),
                                                      myBuild: "17", guardAlive: false)),
                    .recordAndContinue(selfCheckNow: false), "healthy、只崩过一次：照常")
        let eightDaysAgo = Date().addingTimeInterval(-8 * 24 * 3600)
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.healthy, healthyAt: eightDaysAgo), myBuild: "17", guardAlive: false)),
                    .expire, "healthy 已超过 7 天：删旧备份和日志")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.healthy, healthyAt: Date().addingTimeInterval(-3600)),
                                                      myBuild: "17", guardAlive: false)),
                    .recordAndContinue(selfCheckNow: false), "healthy 才 1 小时：还没到期")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restoring), myBuild: "17", guardAlive: true)),
                    .yieldToGuard, "换回做到一半、看护还在：让开")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restoring, reason: .drChanged), myBuild: "17", guardAlive: false)),
                    .handToGuard(.drChanged), "换回做到一半、看护不在：按日志里的原因再交一次")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restoring), myBuild: "17", guardAlive: false)),
                    .handToGuard(.crashed), "换回做到一半、没写原因：按 crashed 交")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restoreFailed), myBuild: "17", guardAlive: true)),
                    .announceRestoreFailed, "换回没做成（看护在）：照常运行，说一次")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restoreFailed), myBuild: "17", guardAlive: false)),
                    .announceRestoreFailed, "换回没做成（看护不在）：同样")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restoreFailed), myBuild: "16", guardAlive: false)),
                    .clearSilently, "换回没做成但跑的是旧版：安静清掉")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.abnormal, reason: .drChanged), myBuild: "17", guardAlive: false)),
                    .handToGuard(.drChanged), "abnormal 且原因是 drChanged：换回")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.abnormal), myBuild: "17", guardAlive: false)),
                    .handToGuard(.selfCheckFailed), "abnormal 没写原因：按自查没过换回")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.refused), myBuild: "17", guardAlive: false)),
                    .handToGuard(.selfCheckFailed), "被关拦下却装上了：换回")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restored), myBuild: "17", guardAlive: false)),
                    .handToGuard(.crashed), "说已换回、跑起来却是新版：再交一次")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.cancelled), myBuild: "17", guardAlive: false)),
                    .recordAndContinue(selfCheckNow: true), "cancelled 却被装上：记一条并自查")
        // 旧版
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restored), myBuild: "16", guardAlive: false)),
                    .announceRestored(userRequested: false), "旧版读到已换回：说一次（不是他要的）")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restored, reason: .userRequested), myBuild: "16", guardAlive: false)),
                    .announceRestored(userRequested: true), "他自己点的换回：不说")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.installFailed), myBuild: "16", guardAlive: false)),
                    .announceInstallFailed, "旧版读到没装上：说一次“没能更新”")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restoring), myBuild: "16", guardAlive: false)),
                    .finishRestore(userRequested: false), "换回做到一半、看护不在、跑的是旧版：补写恢复")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restoring, reason: .userRequested), myBuild: "16", guardAlive: false)),
                    .finishRestore(userRequested: true), "补写时也带上“是他要的”")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.restoring), myBuild: "16", guardAlive: true)),
                    .none, "换回做到一半、看护还在：旧版让开")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.cancelled), myBuild: "16", guardAlive: false)),
                    .clearSilently, "旧版读到他取消过：安静清掉")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.cancelled), myBuild: "16", guardAlive: true)),
                    .none, "看护还在：旧版不动日志")
        expectEqual(UpdateLaunchPolicy.decide(context(journal(.healthy), myBuild: "16", guardAlive: false)),
                    .clearSilently, "旧版读到新版健康过（他自己装回了旧版）：安静清掉")
        // 两个都不是
        let stale = journal(.launched, to: ref("17.0", "17"))
        expectEqual(UpdateLaunchPolicy.decide(context(stale, myBuild: "18", guardAlive: false)),
                    .clearSilently, "更晚的版本已装上且看护不在：安静清掉")
        expectEqual(UpdateLaunchPolicy.decide(context(stale, myBuild: "18", guardAlive: true)),
                    .none, "更晚的版本但看护还在：不动")
        let expired = journal(.healthy, healthyAt: eightDaysAgo, to: ref("17.0", "17"))
        expectEqual(UpdateLaunchPolicy.decide(context(expired, myBuild: "18", guardAlive: false)),
                    .expire, "两个都不是但日志早过期：删掉")
        // 备份文件名
        let named = journal(.approved, backup: "/tmp/Previous/WindowShade-16.0-16.zip")
        expect(UpdateLaunchPolicy.backupLooksUsable(journal: named, fileExists: true), "备份名对得上 from：可用")
        let partial = journal(.approved, backup: "/tmp/Previous/WindowShade-16.0-16.zip.partial")
        expect(UpdateLaunchPolicy.backupLooksUsable(journal: partial, fileExists: true), "过关前的 .partial 也算可用")
        let wrongName = journal(.approved, backup: "/tmp/Previous/WindowShade-15.0-15.zip")
        expect(!UpdateLaunchPolicy.backupLooksUsable(journal: wrongName, fileExists: true), "备份名对不上：不可用")
        expect(!UpdateLaunchPolicy.backupLooksUsable(journal: named, fileExists: false), "文件不在：不可用")
    }

    // MARK: - 5 看护的决策表

    static func guardPolicy() {
        let expected: [UpdatePhase: UpdateGuardPolicy.AfterOldExit] = [
            .cancelled: .waitVetoedInstall,
            .refused: .waitVetoedInstall,
            .started: .waitUngatedInstall,
            .gating: .waitUngatedInstall,
            .approved: .waitApprovedInstall,
            .restoring: .restore,
            .rollbackRequested: .restore,
            .installFailed: .exit,
            .restored: .exit,
            .restoreFailed: .exit,
            .healthy: .exit,
            .launched: .exit,
            .abnormal: .exit,
        ]
        expectEqual(Set(expected.keys), Set(UpdatePhase.allCases), "每个 phase 都有一条规则")
        for (phase, action) in expected {
            expectEqual(UpdateGuardPolicy.afterOldExit(phase: phase), action, "旧版退出时 \(phase.rawValue) → \(action)")
        }
        expectEqual(UpdateGuardPolicy.installOutcome(installedBuild: "17", to: "17", jobAlive: true, elapsed: 1),
                    .installed, "版本已变：装上了")
        expectEqual(UpdateGuardPolicy.installOutcome(installedBuild: "16", to: "17", jobAlive: true, elapsed: 119),
                    .keepWaiting, "任务还在跑、不到 120 秒：继续等")
        expectEqual(UpdateGuardPolicy.installOutcome(installedBuild: "16", to: "17", jobAlive: true, elapsed: 121),
                    .notInstalled, "任务还在跑但超过 120 秒：没装上")
        expectEqual(UpdateGuardPolicy.installOutcome(installedBuild: "16", to: "17", jobAlive: false, elapsed: 1),
                    .notInstalled, "任务没了、版本没变：没装上")
        expectEqual(UpdateGuardPolicy.installOutcome(installedBuild: nil, to: "17", jobAlive: false, elapsed: 1),
                    .notInstalled, "读不到装在包里的版本：没装上")
        let launch = launchRecord("17")
        var w = UpdateGuardPolicy.Watch(phase: .approved, launch: nil, pidAlive: false, waited: 21,
                                        sinceLaunch: 0, openedByGuard: false, sinceCleanExit: nil)
        expectEqual(UpdateGuardPolicy.watch(w), .openApp, "没重开、等了 21 秒：自己打开")
        w.waited = 19
        expectEqual(UpdateGuardPolicy.watch(w), .keepWaiting, "才等 19 秒：再等等")
        w = UpdateGuardPolicy.Watch(phase: .approved, launch: nil, pidAlive: false, waited: 41,
                                    sinceLaunch: 0, openedByGuard: true, sinceCleanExit: nil)
        expectEqual(UpdateGuardPolicy.watch(w), .restore(.crashed), "我们打开的、等了 41 秒还没进 main：换回")
        w.waited = 39
        expectEqual(UpdateGuardPolicy.watch(w), .keepWaiting, "我们自己打开后 39 秒：再等等")
        w = UpdateGuardPolicy.Watch(phase: .launched, launch: launch, pidAlive: true, waited: 0,
                                    sinceLaunch: 61, openedByGuard: true, sinceCleanExit: nil)
        expectEqual(UpdateGuardPolicy.watch(w), .terminateThenRestore, "进程还在、60 秒没到 healthy：结束它再换回")
        w.sinceLaunch = 59
        expectEqual(UpdateGuardPolicy.watch(w), .keepWaiting, "进程还在、59 秒：再等等")
        w = UpdateGuardPolicy.Watch(phase: .launched, launch: launch, pidAlive: false, waited: 0,
                                    sinceLaunch: 3, openedByGuard: true, sinceCleanExit: nil)
        expectEqual(UpdateGuardPolicy.watch(w), .restore(.crashed), "没写 cleanExit 就没了：换回(crashed)")
        let clean = launchRecord("17", clean: true)
        w = UpdateGuardPolicy.Watch(phase: .launched, launch: clean, pidAlive: false, waited: 0,
                                    sinceLaunch: 1, openedByGuard: true, sinceCleanExit: 5)
        expectEqual(UpdateGuardPolicy.watch(w), .waitCleanRelaunch, "他按了退出：等它自己重开")
        w.sinceCleanExit = 20
        expectEqual(UpdateGuardPolicy.watch(w), .exit, "干净退出后又等了 20 秒：结束")
        w = UpdateGuardPolicy.Watch(phase: .abnormal, launch: launch, pidAlive: true, waited: 0,
                                    sinceLaunch: 1, openedByGuard: true, sinceCleanExit: nil, reason: .drChanged)
        expectEqual(UpdateGuardPolicy.watch(w), .restore(.drChanged), "自查没过且原因是 drChanged：换回")
        w.reason = nil
        expectEqual(UpdateGuardPolicy.watch(w), .restore(.selfCheckFailed), "自查没过没写原因：按自查没过")
        w = UpdateGuardPolicy.Watch(phase: .healthy, launch: launch, pidAlive: true, waited: 0,
                                    sinceLaunch: 1, openedByGuard: true, sinceCleanExit: nil)
        expectEqual(UpdateGuardPolicy.watch(w), .healthy, "新版健康：收工")
    }

    // MARK: - 6 补关怎么办

    static func gateAfterInstall() {
        expectEqual(UpdateGate.afterInstall(.pass), nil, "试跑过了：放行")
        expectEqual(UpdateGate.afterInstall(.trialTimedOut), nil, "偶然超时：放行，交给 60 秒 healthy")
        expectEqual(UpdateGate.afterInstall(.drChanged("x")), .drChanged, "签名要求变了：换回(drChanged)")
        expectEqual(UpdateGate.afterInstall(.trialFailed("x")), .selfCheckFailed, "试跑没过：换回")
        expectEqual(UpdateGate.afterInstall(.invalid("x")), .selfCheckFailed, "签名不成立：换回")
        expectEqual(UpdateGate.afterInstall(.notFound("x")), .selfCheckFailed, "找不到解开的包：换回")
        expectEqual(UpdateGate.afterInstall(.refusedBefore), .selfCheckFailed, "拒绝过的版本：换回")
        expectEqual(UpdateGate.afterInstall(.systemTooOld("27.0")), .selfCheckFailed, "系统太旧：换回")
        expectEqual(UpdateGate.afterInstall(.location), .selfCheckFailed, "位置不成立：换回")
    }

    // MARK: - 7 日志、拒绝记录、暂存

    static func store() {
        let root = scratch("store")
        let store = UpdateStore(root: root)
        let launchJournal = journal(.launched, healthyAt: iso(Date().addingTimeInterval(-30)))
        try! store.saveJournal(launchJournal)
        expectEqual(store.loadJournal(), launchJournal, "日志存下去再读回来一致（日期按 ISO8601 往返）")
        let text = try! String(contentsOf: store.journalURL, encoding: .utf8)
        expect(text.contains("\"startedAt\" :"), "日志里的 startedAt 是 ISO8601 文本（\(launchJournal.startedAt)）")
        expectEqual(iso(store.loadJournal()!.startedAt), launchJournal.startedAt, "日期按 ISO8601 往返不变")
        expectEqual(store.loadJournal()?.phase, .launched, "读回来的 phase 是 launched")
        // setPhase 的 onlyIf
        _ = store.setPhase(.approved, onlyIf: [.started, .gating])
        expectEqual(store.loadJournal()?.phase, .launched, "launched 不在 onlyIf 里：不改")
        _ = store.setPhase(.restored)
        expectEqual(store.loadJournal()?.phase, .restored, "onlyIf 为空：直接改")
        _ = store.setPhase(.healthy, onlyIf: [.restored])
        expectEqual(store.loadJournal()?.healthyAt != nil, true, "写 healthy 时记下 healthyAt")
        // refused
        let entry17 = UpdateRefusedEntry(build: "17", version: "17.0", reason: .crashed, at: iso(Date()))
        let entry17b = UpdateRefusedEntry(build: "17", version: "17.1", reason: .hung, at: iso(Date()))
        store.addRefused(entry17)
        store.addRefused(entry17b)
        expectEqual(store.refused().count, 1, "同一个 build 只留一条")
        expectEqual(store.refused().first?.version, "17.1", "后写的那条顶掉前一条")
        expect(store.isRefused(build: "17"), "isRefused 认得 17")
        store.addRefused(UpdateRefusedEntry(build: "18", version: "18.0", reason: .hung, at: iso(Date())))
        store.removeRefused(build: "17")
        expect(!store.isRefused(build: "17"), "removeRefused 之后不再认 17")
        expectEqual(store.refused().count, 1, "只剩 18 那一条")
        // 暂存
        let stashedJournal = journal(.healthy, healthyAt: iso(Date().addingTimeInterval(-60)), to: ref("17.0", "17"))
        try! store.saveJournal(stashedJournal)
        store.stashJournal(if: { $0.phase == .healthy })
        try! store.saveJournal(journal(.cancelled))
        store.restoreStashedJournal(replacing: "17")
        expectEqual(store.loadJournal()?.phase, .healthy, "to.build 对得上：另存的那份放回去了")
        try! store.saveJournal(journal(.cancelled))
        store.restoreStashedJournal(replacing: "18")
        expectEqual(store.loadJournal()?.phase, .cancelled, "to.build 对不上：不放回去")
        store.stashJournal(if: { $0.phase == .healthy })
        store.restoreStashedJournal(replacing: "17")
        expectEqual(store.loadJournal()?.phase, .cancelled, "没有另存的：不动日志")
        // durableWrite 不留临时文件
        let dir = root.appendingPathComponent("Durable", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! UpdateStore.durableWrite(Data("hello".utf8), to: dir.appendingPathComponent("a.txt"))
        expectEqual(try! String(contentsOf: dir.appendingPathComponent("a.txt"), encoding: .utf8), "hello", "durableWrite 写出了内容")
        let leftovers = (try! FileManager.default.contentsOfDirectory(atPath: dir.path)).filter { $0.hasSuffix(".tmp") }
        expectEqual(leftovers, [], "durableWrite 没留下 .tmp")
        // 多出来的字段也要能读：换回后的旧版得读得懂新版的日志
        var future = journal(.healthy, healthyAt: iso(Date()))
        future.phase = .approved
        try! store.saveJournal(future)
        var object = try! JSONSerialization.jsonObject(with: Data(contentsOf: store.journalURL)) as! [String: Any]
        object["futureField"] = 1
        try! JSONSerialization.data(withJSONObject: object).write(to: store.journalURL)
        expectEqual(store.loadJournal()?.phase, .approved, "日志里多出未知字段仍能读（向后兼容）")
    }

    // MARK: - 8 找 Sparkle 解开的 App

    static func makeApp(at app: URL, build: String, bundleID: String = "com.windowshade.prototype", version: String = "17.0") {
        write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>\(bundleID)</string>
        <key>CFBundleShortVersionString</key><string>\(version)</string>
        <key>CFBundleVersion</key><string>\(build)</string>
        <key>CFBundleExecutable</key><string>WindowShade</string>
        </dict></plist>
        """, to: app.appendingPathComponent("Contents/Info.plist"))
        write("#!/bin/sh\nexit 0\n", to: app.appendingPathComponent("Contents/MacOS/WindowShade"))
    }

    static func stagedPath(_ lookup: UpdateStagedLookup) -> String? {
        if case .found(let url) = lookup { return url.path }
        return nil
    }

    static func stagedFind() {
        let root = scratch("staged")
        let startedAt = iso(Date().addingTimeInterval(-60))
        let a = root.appendingPathComponent("A", isDirectory: true)
        let app = a.appendingPathComponent("X").appendingPathComponent("WindowShade.app")
        makeApp(at: app, build: "17")
        expectEqual(stagedPath(UpdateStaged.find(in: root, startedAt: startedAt, bundleID: "com.windowshade.prototype", build: "17")),
                    app.standardizedFileURL.path, "刚建好的目录里找到 build 17")
        // .app 的修改时间早于 startedAt 也不看
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)], ofItemAtPath: app.path)
        expectEqual(stagedPath(UpdateStaged.find(in: root, startedAt: startedAt, bundleID: "com.windowshade.prototype", build: "17")),
                    app.standardizedFileURL.path, "解包保留归档时间、.app 的 mtime 是 2001：照样找到")
        expectEqual(UpdateStaged.find(in: root, startedAt: iso(Date().addingTimeInterval(60)), bundleID: "com.windowshade.prototype", build: "17"),
                    .none, "目录建得比 startedAt 早：不算这次解开的")
        expectEqual(UpdateStaged.find(in: root, startedAt: startedAt, bundleID: "com.windowshade.prototype", build: "18"),
                    .none, "build 不对：没有")
        let b = root.appendingPathComponent("B", isDirectory: true)
        let app2 = b.appendingPathComponent("WindowShade.app")
        makeApp(at: app2, build: "17")
        if case .multiple(let n) = UpdateStaged.find(in: root, startedAt: startedAt,
                                                      bundleID: "com.windowshade.prototype", build: "17") {
            expectEqual(n, 2, "两个新目录里各有一个对得上的包：multiple(2)")
        } else {
            expect(false, "两个新目录里各有一个对得上的包：multiple(2)")
        }
    }

    // MARK: - 9 真签名的小 App：备份与换回

    static func makeFakeApp(at root: URL, version: String, build: String) -> URL {
        let app = root.appendingPathComponent("Fake.app")
        write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.windowshade.prototype.test</string>
        <key>CFBundleShortVersionString</key><string>\(version)</string>
        <key>CFBundleVersion</key><string>\(build)</string>
        <key>CFBundleExecutable</key><string>WindowShade</string>
        </dict></plist>
        """, to: app.appendingPathComponent("Contents/Info.plist"))
        try? FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"),
                                          to: app.appendingPathComponent("Contents/MacOS/WindowShade"))
        _ = UpdateFiles.run("/usr/bin/codesign", ["--force", "-s", "-", app.path])
        return app
    }

    static func sign(_ app: URL) -> Bool {
        UpdateFiles.run("/usr/bin/codesign", ["--force", "-s", "-", app.path]).status == 0
    }

    static func signedApps() {
        // 先看这条机器上能不能签名；不能就整组跳过。
        if UpdateFiles.run("/usr/bin/codesign", ["-d", "/usr/bin/true"]).timedOut {
            print("skip 签名那组：codesign 不能跑")
            return
        }
        let root = scratch("signed")
        let old = makeFakeApp(at: root.appendingPathComponent("old", isDirectory: true), version: "16.0", build: "16")
        let new = makeFakeApp(at: root.appendingPathComponent("new", isDirectory: true), version: "17.0", build: "17")
        guard sign(old), sign(new) else {
            print("skip 签名那组：这台机器上 codesign --force -s - 不成功")
            return
        }
        // 签名比对
        let oldDR = UpdateCodeSign.staticDR(of: old)!
        expect(!oldDR.isEmpty, "读得到旧版的签名要求（ad hoc：\(oldDR.prefix(50))…）")
        expectEqual(UpdateCodeSign.check(old, against: oldDR), .same, "同一个 App 对自己的 DR：same")
        expect(UpdateCodeSign.staticDR(of: new) != nil, "另一个 App 也有自己的签名要求")
        if case .notSatisfied = UpdateCodeSign.check(new, against: oldDR) {
            expect(true, "另一个 App（cdhash 不同）：notSatisfied")
        } else {
            expect(false, "另一个 App（cdhash 不同）：notSatisfied（得到 \(UpdateCodeSign.check(new, against: oldDR))）")
        }
        expectEqual(UpdateCodeSign.check(old, against: "identifier \"com.windowshade.prototype.test\""),
                    .differentString(oldDR), "宽一些的要求满足，但 DR 字符串不同：differentString")
        expect(UpdateCodeSign.isValid(old), "签过的小 App 严格校验通过")
        let unsignedRoot = root.appendingPathComponent("unsigned", isDirectory: true)
        let unsigned = makeFakeApp(at: unsignedRoot, version: "16.0", build: "16")
        // 去掉签名
        _ = UpdateFiles.run("/usr/bin/codesign", ["--remove-signature", unsigned.path])
        if case .invalid = UpdateCodeSign.check(unsigned, against: oldDR) {
            expect(true, "没签名的 App：invalid")
        } else {
            expect(false, "没签名的 App：invalid（得到 \(UpdateCodeSign.check(unsigned, against: oldDR))）")
        }
        // 备份
        let store = UpdateStore(root: root.appendingPathComponent("store", isDirectory: true))
        let info = try! UpdateBackup.make(app: old, store: store, expectedDR: oldDR)
        expectEqual(info.version, "16.0", "备份记下版本 16.0")
        expectEqual(info.build, "16", "备份记下 build 16")
        expectEqual(info.file, "WindowShade-16.0-16.zip", "备份文件名按版本和 build")
        let partial = store.previousDirectory.appendingPathComponent("WindowShade-16.0-16.zip.partial")
        expect(FileManager.default.fileExists(atPath: partial.path), "先写成 .partial")
        expectEqual(info.sha256, try! UpdateFiles.sha256(partial), "记下 .partial 的 SHA-256")
        // 期望的 DR 不对：抛错并且不留 .partial
        let badRoot = root.appendingPathComponent("bad", isDirectory: true)
        let badStore = UpdateStore(root: badRoot)
        var threw = false
        do { _ = try UpdateBackup.make(app: old, store: badStore, expectedDR: "identifier \"com.example.other\"") }
        catch { threw = true }
        expect(threw, "期望的 DR 不对：备份抛错")
        let badPartial = badStore.previousDirectory.appendingPathComponent("WindowShade-16.0-16.zip.partial")
        expect(!FileManager.default.fileExists(atPath: badPartial.path), "抛错后不留 .partial")
        // promote
        let promoted = try! UpdateBackup.promote(info, store: store)
        expectEqual(promoted.lastPathComponent, "WindowShade-16.0-16.zip", "promote 改成正式名")
        expect(!FileManager.default.fileExists(atPath: partial.path), "promote 后 .partial 没了")
        expectEqual(store.backupInfo()?.file, "WindowShade-16.0-16.zip", "promote 写了 backup.json")
        expectEqual(store.backupInfo()?.build, "16", "backup.json 里的 build 是 16")
        // 换回
        let installedDir = root.appendingPathComponent("installed/Applications", isDirectory: true)
        let installed = installedDir.appendingPathComponent("WindowShade.app")
        write("placeholder", to: installedDir.appendingPathComponent(".keep"))
        try? FileManager.default.removeItem(at: installed)
        var placedNew = false
        do { try UpdateFiles.ditto([new.path, installed.path]); placedNew = true } catch { placedNew = false }
        expect(placedNew, "把新版放到“应用程序”里")
        var j = journal(.launched, from: ref("16.0", "16"), to: ref("17.0", "17"))
        j.appPath = installed.path
        j.oldDR = oldDR
        j.backup = promoted.path
        j.backupSHA256 = info.sha256
        j.phase = .restoring
        j.restoreReason = .crashed
        j.startedAt = iso(Date().addingTimeInterval(-3600))
        try! store.saveJournal(j)
        try! UpdateRestorer.restore(store: store, reason: .crashed)
        let after = UpdateBundleInfo(appURL: installed)!
        expectEqual(after.build, "16", "换回后装的是 16")
        expectEqual(store.loadJournal()?.phase, .restored, "换回后 phase 是 restored")
        expectEqual(store.loadJournal()?.restoreReason, .crashed, "换回后日志里记着原因")
        expect(store.isRefused(build: "17"), "换回后 refused.json 里有 17")
        // 换回失败（SHA-256 对不上）：先把新版放回“应用程序”里
        try? FileManager.default.removeItem(at: installed)
        var replacedNew = false
        do { try UpdateFiles.ditto([new.path, installed.path]); replacedNew = true } catch { replacedNew = false }
        expect(replacedNew, "失败前重新放上新版")
        let failRoot = root.appendingPathComponent("failstore", isDirectory: true)
        let failStore = UpdateStore(root: failRoot)
        let failBackup = UpdateBackupInfo(version: "16.0", build: "16", dr: oldDR, sha256: "bad",
                                          file: "WindowShade-16.0-16.zip", createdAt: iso(Date()))
        try! FileManager.default.createDirectory(at: failStore.previousDirectory, withIntermediateDirectories: true)
        try! FileManager.default.copyItem(at: promoted, to: failStore.previousDirectory.appendingPathComponent("WindowShade-16.0-16.zip"))
        var f = journal(.restoring, from: ref("16.0", "16"), to: ref("17.0", "17"))
        f.appPath = installed.path
        f.oldDR = oldDR
        f.backup = failStore.previousDirectory.appendingPathComponent(failBackup.file).path
        f.backupSHA256 = "bad"
        f.phase = .restoring
        f.restoreReason = .crashed
        f.startedAt = iso(Date().addingTimeInterval(-3600))
        try! failStore.saveJournal(f)
        var failedThrew = false
        do { try UpdateRestorer.restore(store: failStore, reason: .crashed) } catch { failedThrew = true }
        expect(failedThrew, "备份 SHA-256 对不上：换回抛错")
        expectEqual(failStore.loadJournal()?.phase, .restoreFailed, "换回没做成：phase 是 restoreFailed")
        expect(!failStore.isRefused(build: "17"), "换回没做成：撤掉 refused.json 里那一条")
        expectEqual(UpdateBundleInfo(appURL: installed)?.build, "17", "换回没做成：装着的还是新版 17")
        // 换回失败（备份文件不在）
        let missingRoot = root.appendingPathComponent("missingstore", isDirectory: true)
        let missingStore = UpdateStore(root: missingRoot)
        var m = journal(.restoring)
        m.appPath = installed.path
        m.oldDR = oldDR
        m.backup = missingRoot.appendingPathComponent("Previous/gone.zip").path
        m.phase = .restoring
        m.restoreReason = .crashed
        m.startedAt = iso(Date().addingTimeInterval(-3600))
        try! missingStore.saveJournal(m)
        var missingThrew = false
        do { try UpdateRestorer.restore(store: missingStore, reason: .crashed) } catch { missingThrew = true }
        expect(missingThrew, "备份文件不在：换回抛错")
        expectEqual(missingStore.loadJournal()?.phase, .restoreFailed, "备份不在：phase 是 restoreFailed")
    }
}
