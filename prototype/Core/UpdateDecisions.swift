// 应用内更新：所有“下一步做什么”的判断（纯逻辑，不碰文件、进程和界面）。
//
// 三组判断：
// 1. 能不能一键更新（位置、写权限、别的用户、空间、拒绝过的版本）；
// 2. 每一版启动时读到更新日志后怎么收尾（新版 / 旧版 / 看护在不在 / 连续崩溃）；
// 3. 看护的决策表（旧版退出时的 phase、已装的版本、新版 pid、cleanExit、healthy、超时）。
// 真正去查文件、起进程的代码在 App/UpdaterSystem.swift，这里只接它给的事实。

import Foundation

// MARK: - 能不能一键更新

struct UpdateLocationFacts: Equatable {
    var path: String
    var isTranslocated: Bool
    var isReadOnlyVolume: Bool
    var isInApplicationsFolder: Bool
    var supportsRenameSwap: Bool
    var sameVolumeAsCaches: Bool
    var folderWritable: Bool
    var appWritable: Bool
}

enum UpdateBlocker: Equatable {
    case needsMove          // 被系统挪走、只读卷、不在“应用程序”里：移到“应用程序”就能更新
    case unsupportedVolume  // 在“应用程序”里，但卷不支持原子交换或和缓存不在同一个卷（多半是 home 在外接磁盘上）：移也没用
    case needsAdmin         // 当前账户写不进去
    case otherUserRunning   // 别的用户开着 WindowShade
    case lowSpace           // 空间不够
    case refusedBefore      // 这个 build 上次没能正常打开
}

enum UpdatePolicy {
    /// 空间至少是安装包的 4 倍：备份、下载、解开、交换。清单里没写大小时按 64 MB 算。
    static let spaceMultiplier: UInt64 = 4
    static let assumedPackageBytes: UInt64 = 64 * 1024 * 1024
    static let rollbackWindow: TimeInterval = 7 * 24 * 3600
    static let normalRunSeconds: Double = 30 * 60

    static func isApplicationsPath(_ path: String, home: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let roots = ["/Applications", (home as NSString).appendingPathComponent("Applications")]
        return roots.contains { standardized.hasPrefix($0 + "/") }
    }

    static func isTranslocated(_ path: String) -> Bool { path.contains("/AppTranslocation/") }

    /// “能不能一键更新”表的第一行：位置不对，先移到“应用程序”就好。欢迎窗口的那一步只用它。
    static func needsMove(_ facts: UpdateLocationFacts) -> Bool {
        facts.isTranslocated || facts.isReadOnlyVolume || !facts.isInApplicationsFolder
    }

    /// 第二行：卷不支持 RENAME_SWAP，或和 ~/Library/Caches 不在同一个卷。移到“应用程序”也改变不了
    ///（home 在外接卷上时 /Applications 永远和缓存不同卷），所以不进欢迎窗口，只在更新小窗里说原因。
    static func unsupportedVolume(_ facts: UpdateLocationFacts) -> Bool {
        !facts.supportsRenameSwap || !facts.sameVolumeAsCaches
    }

    /// 关在最后再核一次位置：任何一项不成立都不装。
    static func locationBlocksInstall(_ facts: UpdateLocationFacts) -> Bool {
        needsMove(facts) || unsupportedVolume(facts) || !facts.folderWritable || !facts.appWritable
    }

    static func hasEnoughSpace(freeBytes: UInt64, packageBytes: UInt64) -> Bool {
        let package = packageBytes > 0 ? packageBytes : assumedPackageBytes
        let (needed, overflow) = package.multipliedReportingOverflow(by: spaceMultiplier)
        return !overflow && freeBytes >= needed
    }

    /// 按表里的顺序给出第一个拦住更新的原因；nil 表示可以一键更新。
    /// 拒绝过的版本只在他手动检查时出现（定时检查已经在清单那一步滤掉），他点“再试一次”后传 ignoreRefused。
    static func blocker(location: UpdateLocationFacts, otherUserRunning: Bool,
                        freeBytes: UInt64, packageBytes: UInt64,
                        refused: Bool, ignoreRefused: Bool) -> UpdateBlocker? {
        if needsMove(location) { return .needsMove }
        if unsupportedVolume(location) { return .unsupportedVolume }
        if !location.folderWritable || !location.appWritable { return .needsAdmin }
        if otherUserRunning { return .otherUserRunning }
        if !hasEnoughSpace(freeBytes: freeBytes, packageBytes: packageBytes) { return .lowSpace }
        if refused && !ignoreRefused { return .refusedBefore }
        return nil
    }

    /// 定时检查不提醒拒绝过的版本；手动检查照常列出（界面上再说明原因）。
    static func shouldOffer(build: String, refusedBuilds: Set<String>, userInitiated: Bool) -> Bool {
        userInitiated || !refusedBuilds.contains(build)
    }

    /// 更新后 7 天内设置里有“回到 x.y.z”。
    static func canRollBack(journal: UpdateJournal?, myBuild: String, backup: UpdateBackupInfo?,
                            backupExists: Bool, guardExists: Bool, now: Date) -> Bool {
        guard let journal, let backup, backupExists, guardExists else { return false }
        guard journal.to.build == myBuild, journal.from.build == backup.build else { return false }
        guard journal.phase == .healthy || journal.phase == .launched else { return false }
        return now.timeIntervalSince(journal.startedAt) < rollbackWindow
    }
}

// MARK: - 每一版启动时怎么收尾

struct UpdateLaunchContext {
    var journal: UpdateJournal
    var myBuild: String
    var myPath: String
    var guardAlive: Bool
    var now: Date
    /// 日志里写的备份文件在，而且文件名对得上 from 那一版的版本和 build。不成立就不交出去换回（换不回来，只会反复退出）。
    var backupUsable: Bool = true
}

enum UpdateLaunchAction: Equatable {
    /// 和这一次更新无关，照常启动。
    case none
    /// 我是新版：记一条启动，写 launched，照常启动。selfCheckNow：关没跑完就被装上了，先做 DR 自查。
    case recordAndContinue(selfCheckNow: Bool)
    /// 我是新版，但不能再往下跑：交给旧版的看护换回，然后退出。
    case handToGuard(UpdateRestoreReason)
    /// 该换回却换不回（换回没做成，或备份不在）：照常运行这一版，说一次“没能换回”，然后清掉日志。
    case announceRestoreFailed
    /// 看护正在换回，我让开。
    case yieldToGuard
    /// 我是旧版：说一次“已经换回”（他自己要的换回不说），然后清掉日志。
    case announceRestored(userRequested: Bool)
    /// 我是旧版：说一次“没能更新”，然后清掉日志。
    case announceInstallFailed
    /// 我是旧版，换回做到一半而看护不在：交换已经做完（跑的就是我），补写 restored 再说一次。
    case finishRestore(userRequested: Bool)
    /// 这次没装上或早已结束，安静地清掉日志（备份留着）。
    case clearSilently
    /// 更新成功超过 7 天：删掉旧备份和日志。
    case expire
}

enum UpdateLaunchPolicy {
    /// 从最后一条往前数，同一 build 连续几次既没 cleanExit、也没跑满 30 分钟。
    static func consecutiveUnclean(_ launches: [UpdateLaunchRecord], build: String) -> Int {
        var count = 0
        for record in launches.reversed() where record.build == build {
            if record.cleanExit || record.runSeconds >= UpdatePolicy.normalRunSeconds { break }
            count += 1
        }
        return count
    }

    /// 备份文件在、名字对得上 from 那一版（.zip 或过关前的 .zip.partial）。
    static func backupLooksUsable(journal: UpdateJournal, fileExists: Bool) -> Bool {
        guard fileExists else { return false }
        let name = (journal.backup as NSString).lastPathComponent
        let expected = UpdateStore.backupFileName(version: journal.from.version, build: journal.from.build)
        return name == expected || name == expected + ".partial"
    }

    static func decide(_ ctx: UpdateLaunchContext) -> UpdateLaunchAction {
        let journal = ctx.journal
        func restore(_ reason: UpdateRestoreReason) -> UpdateLaunchAction {
            ctx.backupUsable ? .handToGuard(reason) : .announceRestoreFailed
        }
        // 只管装在日志里那个位置的那一份：“下载”里的原件、缓存里解开的副本都不参与。
        guard (ctx.myPath as NSString).standardizingPath == (journal.appPath as NSString).standardizingPath else {
            return .none
        }
        let userRequested = journal.restoreReason == .userRequested
        if ctx.myBuild == journal.to.build && journal.to.build != journal.from.build {
            let previousUnclean = consecutiveUnclean(journal.launches, build: ctx.myBuild)
            switch journal.phase {
            case .restoreFailed:
                // 换回没做成：别再交出去（会反复退出），照常运行，说一次。
                return .announceRestoreFailed
            case .restoring, .rollbackRequested:
                return ctx.guardAlive ? .yieldToGuard : restore(journal.restoreReason ?? .crashed)
            case .restored:
                // 换回写完了，跑起来的却还是新版：交换没生效，再交一次。
                return ctx.guardAlive ? .yieldToGuard : restore(journal.restoreReason ?? .crashed)
            case .refused:
                // 关拦下了它，它却被装上了：换回。
                return ctx.guardAlive ? .yieldToGuard : restore(journal.restoreReason ?? .selfCheckFailed)
            case .abnormal:
                return ctx.guardAlive ? .yieldToGuard : restore(journal.restoreReason ?? .selfCheckFailed)
            case .started, .gating, .cancelled, .installFailed:
                // 没过关就被装上了。
                if !ctx.guardAlive && previousUnclean >= 1 { return restore(.crashed) }
                return .recordAndContinue(selfCheckNow: true)
            case .approved:
                return .recordAndContinue(selfCheckNow: false)
            case .launched:
                // 看护不在、上一次启动没正常结束：新版能跑到这里就交回去换回。
                if !ctx.guardAlive && previousUnclean >= 1 { return restore(.crashed) }
                return .recordAndContinue(selfCheckNow: false)
            case .healthy:
                if let healthyAt = journal.healthyAt,
                   ctx.now.timeIntervalSince(healthyAt) >= UpdatePolicy.rollbackWindow {
                    return .expire
                }
                // 7 天内连续两次没正常结束，第三次启动时换回。
                if previousUnclean >= 2 { return restore(.crashed) }
                return .recordAndContinue(selfCheckNow: false)
            }
        }
        if ctx.myBuild == journal.from.build {
            switch journal.phase {
            case .restored:
                return .announceRestored(userRequested: userRequested)
            case .installFailed:
                return .announceInstallFailed
            case .restoring, .rollbackRequested:
                return ctx.guardAlive ? .none : .finishRestore(userRequested: userRequested)
            case .started, .gating, .approved, .cancelled, .refused, .restoreFailed:
                return ctx.guardAlive ? .none : .clearSilently
            case .launched, .healthy, .abnormal:
                // 日志说新版起来过，装着的却是旧版：他自己装回了旧版。
                return ctx.guardAlive ? .none : .clearSilently
            }
        }
        // 两个都不是：更晚的版本已经手动装上，或者日志早就过期。
        if journal.phase == .healthy, let healthyAt = journal.healthyAt,
           ctx.now.timeIntervalSince(healthyAt) >= UpdatePolicy.rollbackWindow {
            return .expire
        }
        if UpdateVersion.isNewer(ctx.myBuild, than: journal.to.build) && !ctx.guardAlive {
            return .clearSilently
        }
        return .none
    }
}

// MARK: - 看护的决策表

enum UpdateGuardPolicy {
    static let installWait: TimeInterval = 120
    static let launchWait: TimeInterval = 20
    static let healthyWait: TimeInterval = 60
    static let cleanRelaunchWait: TimeInterval = 20

    enum AfterOldExit: Equatable {
        case exit                 // 这次更新早已结束
        case waitUngatedInstall   // 关没跑完旧版就没了：等 Sparkle 安装任务结束再看装没装，没装上就打开旧版
        case waitVetoedInstall    // 已经否决（cancelled / refused），但旧版可能在确认安装任务没了之前就退出了：
                                  // 等任务结束再看装没装；没装上就安静退出（他自己退的），装上了补关或换回
        case waitApprovedInstall  // 过了关：等交换完成
        case restore              // 换回请求
    }

    static func afterOldExit(phase: UpdatePhase) -> AfterOldExit {
        switch phase {
        case .installFailed, .restored, .restoreFailed, .healthy, .launched, .abnormal: return .exit
        case .started, .gating: return .waitUngatedInstall
        case .cancelled, .refused: return .waitVetoedInstall
        case .approved: return .waitApprovedInstall
        case .restoring, .rollbackRequested: return .restore
        }
    }

    enum InstallOutcome: Equatable {
        case keepWaiting
        case installed
        case notInstalled
    }

    static func installOutcome(installedBuild: String?, to: String, jobAlive: Bool, elapsed: TimeInterval) -> InstallOutcome {
        if installedBuild == to { return .installed }
        if jobAlive && elapsed < installWait { return .keepWaiting }
        // 任务没了、版本也没变：交换失败或安装器被杀。
        return .notInstalled
    }

    struct Watch: Equatable {
        var phase: UpdatePhase
        /// 这一版最新的一条启动记录；nil 表示还没进 main。
        var launch: UpdateLaunchRecord?
        var pidAlive: Bool
        /// 从开始等新版起算。
        var waited: TimeInterval
        /// 从这条启动记录开始算。
        var sinceLaunch: TimeInterval
        var openedByGuard: Bool
        /// 新版干净退出后又等了多久。
        var sinceCleanExit: TimeInterval?
        /// 日志里写的换回原因（新版写 abnormal 时会带上，比如 drChanged）。
        var reason: UpdateRestoreReason? = nil
    }

    enum WatchAction: Equatable {
        case keepWaiting
        case openApp
        case healthy
        case restore(UpdateRestoreReason)
        case terminateThenRestore
        case waitCleanRelaunch
        case exit
    }

    static func watch(_ w: Watch) -> WatchAction {
        if w.phase == .healthy { return .healthy }
        if w.phase == .abnormal { return .restore(w.reason ?? .selfCheckFailed) }
        guard let launch = w.launch else {
            // Sparkle 没重开就自己按路径打开；打开后还是进不了 main，就换回。
            if !w.openedByGuard { return w.waited >= launchWait ? .openApp : .keepWaiting }
            return w.waited >= 2 * launchWait ? .restore(.crashed) : .keepWaiting
        }
        if w.pidAlive {
            return w.sinceLaunch >= healthyWait ? .terminateThenRestore : .keepWaiting
        }
        if launch.cleanExit {
            // 他按了退出、授权后系统要求重开、移位置后重开：不算失败。
            if let since = w.sinceCleanExit, since >= cleanRelaunchWait { return .exit }
            return .waitCleanRelaunch
        }
        return .restore(.crashed)
    }
}
