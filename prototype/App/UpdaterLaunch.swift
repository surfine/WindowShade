// 应用内更新：main.swift 里、NSApplication 之前要做的两件事。
//
// 1. `--self-check`：长期约定，每一版都得支持。不建窗口、不碰授权、不联网、不写真实状态；
//    只让系统加载全部链接的框架（包括 Sparkle 和 libswift_Concurrency），载入 Duo.metallib，读一遍资源，
//    打印带 build 号的一行就退出。安装前的关和发布关都靠它试跑新版。
//    发布关第 4.9 步另用两个参数（也是长期约定，从第一个带更新器的版本起）：
//      --self-check --write-sample-state <目录>  这一版把停车日志、偏好、更新日志的样例写进 <目录>
//      --self-check --read-state <目录>          上一版读 <目录> 里的样例，读得懂返回 0
//    两者都只碰给定的目录；读偏好只读不写。
// 2. 读更新日志：我是新版就记一条启动（必要时直接交给旧版的看护换回），我是旧版就收尾。
//
// 接线（main.swift 最前面，在 `let app = NSApplication.shared` 之前）。**发布阻断项**：少了这两行，
// 安装前的试跑会拉起一整个 WindowShade，每次都超时不装；新版也写不了 healthy，每次更新都会被换回。
//     if let code = UpdateLaunch.handleEarlyArguments() { exit(code) }
//     UpdateLaunch.recordLaunch()

import Foundation
import Metal

enum UpdateLaunchNotice: Equatable {
    case restored(to: String, from: String, reason: UpdateRestoreReason?)
    case installFailed(to: String, from: String)
    /// 换回没做成：还在用新版。
    case restoreFailed(to: String, from: String)
}

enum UpdateLaunch {
    /// recordLaunch 的结论，UpdaterController.start() 接着用：要不要 10 秒后写 healthy、要不要说一次话。
    nonisolated(unsafe) static var action: UpdateLaunchAction = .none
    nonisolated(unsafe) static var notice: UpdateLaunchNotice?
    nonisolated(unsafe) static var launchedAt = Date()

    // MARK: --self-check

    static let writeSampleStateArgument = "--write-sample-state"
    static let readStateArgument = "--read-state"

    static func handleEarlyArguments(_ arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.contains(UpdateIdentity.selfCheckArgument) else { return nil }
        let code = selfCheck()
        guard code == 0 else { return code }
        func value(after name: String) -> URL? {
            guard let index = arguments.firstIndex(of: name), arguments.count > index + 1 else { return nil }
            return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        }
        if let directory = value(after: writeSampleStateArgument) { return UpdateStateSample.write(to: directory) }
        if let directory = value(after: readStateArgument) { return UpdateStateSample.read(from: directory) }
        return 0
    }

    static func selfCheck(bundle: Bundle = .main) -> Int32 {
        func fail(_ code: Int32, _ why: String) -> Int32 {
            print("WindowShade self-check failed: \(why)")
            return code
        }
        guard let build = bundle.infoDictionary?["CFBundleVersion"] as? String else { return fail(2, "no build") }
        #if canImport(Sparkle)
        // 链接了 Sparkle 时，框架缺失 dyld 在 main 之前就会失败；这里再确认类真的载入了。
        guard NSClassFromString("SPUUpdater") != nil else { return fail(3, "Sparkle not loaded") }
        #endif
        guard let metallib = bundle.url(forResource: "Duo", withExtension: "metallib") else {
            return fail(4, "Duo.metallib missing")
        }
        if let device = MTLCreateSystemDefaultDevice() {
            do { _ = try device.makeLibrary(URL: metallib) } catch { return fail(5, "Duo.metallib: \(error)") }
        }
        if let icon = bundle.object(forInfoDictionaryKey: "CFBundleIconFile") as? String, !icon.isEmpty {
            let name = (icon as NSString).deletingPathExtension
            guard bundle.url(forResource: name, withExtension: "icns") != nil else { return fail(6, "icon missing") }
        }
        print("WindowShade self-check build=\(build) ok")
        return 0
    }

    // MARK: 读更新日志

    static var myBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }
    static var myVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? myBuild }

    @discardableResult
    static func recordLaunch(store: UpdateStore = .standard, now: Date = Date()) -> UpdateLaunchAction {
        launchedAt = now
        expireStaleBackup(store: store, now: now)
        guard let journal = store.loadJournal() else { return .none }
        let context = UpdateLaunchContext(journal: journal, myBuild: myBuild, myPath: Bundle.main.bundleURL.path,
                                          guardAlive: UpdateGuardHandoff.isAlive(store: store), now: now,
                                          backupUsable: UpdateRestorer.backupUsable(journal))
        var decided = UpdateLaunchPolicy.decide(context)
        UpdateLog.write("launch build=\(myBuild) phase=\(journal.phase.rawValue) -> \(decided)")
        switch decided {
        case .none:
            break
        case .recordAndContinue(let selfCheckNow):
            if selfCheckNow && !UpdateCodeSign.runningSatisfies(journal.oldDR) {
                // 关没跑完就被装上了，而签名要求对不上：授权会丢，换回。换不回就照常运行、说一次。
                if UpdateRestorer.backupUsable(journal) { handToGuard(store: store, reason: .drChanged) }
                giveUpRestore(store: store, journal: journal)
                decided = .none
                break
            }
            store.mutateJournal { j in
                guard j != nil else { return }
                j!.launches.append(UpdateLaunchRecord(build: myBuild, pid: getpid(), startedAt: now, cleanExit: false, runSeconds: 0))
                if j!.phase != .healthy { j!.phase = .launched }
                // 只留最近 20 条，连续崩溃只看最后几条。
                if j!.launches.count > 20 { j!.launches.removeFirst(j!.launches.count - 20) }
            }
        case .handToGuard(let reason):
            handToGuard(store: store, reason: reason)
            // 回到这里说明看护交不出去、进程内也没换回：照常运行这一版。
            giveUpRestore(store: store, journal: journal)
            decided = .none
        case .announceRestoreFailed:
            giveUpRestore(store: store, journal: journal)
            decided = .none
        case .yieldToGuard:
            exit(0)
        case .announceRestored(let userRequested), .finishRestore(let userRequested):
            if case .finishRestore = decided { store.setPhase(.restored) }
            if !userRequested {
                notice = .restored(to: journal.to.version, from: journal.from.version, reason: journal.restoreReason)
            }
            store.clearJournal()
            store.removeBackup()
            decided = .none
        case .announceInstallFailed:
            notice = .installFailed(to: journal.to.version, from: journal.from.version)
            store.clearJournal()
            UpdateBackup.discardPartials(store: store)
        case .clearSilently:
            store.clearJournal()
            UpdateBackup.discardPartials(store: store)
        case .expire:
            store.clearJournal()
            store.removeBackup()
        }
        action = decided
        return decided
    }

    /// 该换回却换不回：撤掉 refused 里这一条、清掉日志和已经没用的备份，照常运行这一版，启动完成后说一次“没能换回”。
    static func giveUpRestore(store: UpdateStore, journal: UpdateJournal) {
        UpdateLog.write("cannot restore \(journal.from.build); continuing with \(myBuild)")
        store.removeRefused(build: journal.to.build)
        notice = .restoreFailed(to: journal.to.version, from: journal.from.version)
        UpdateGuardHandoff.remove()
        store.clearJournal()
        store.removeBackup()
    }

    /// 交给旧版的看护换回：发起回退的代码来自已知能跑的那一版。那份不在时才用这一版自带的 UpdateRestorer。
    /// 交出去了、或进程内换回成功，这个进程直接退出；两条路都没走通才返回（UpdateRestorer 已写下 restoreFailed）。
    static func handToGuard(store: UpdateStore, reason: UpdateRestoreReason) {
        store.mutateJournal { j in
            guard j != nil else { return }
            j!.phase = .rollbackRequested
            j!.restoreReason = reason
            j!.requesterPID = getpid()
        }
        do {
            try UpdateGuardHandoff.submit(store: store, restore: true)
            UpdateLog.write("handed to guard for restore (\(reason.rawValue))")
        } catch {
            UpdateLog.write("guard unavailable (\(error)); restoring in process")
            do {
                try UpdateRestorer.restore(store: store, reason: reason)
                if let journal = store.loadJournal() { reopen(journal.appPath) }
            } catch {
                UpdateLog.write("in-process restore failed: \(error)")
                return
            }
        }
        exit(0)
    }

    static func reopen(_ appPath: String) {
        _ = UpdateFiles.run("/usr/bin/open", ["-n", appPath], timeout: 10)
    }

    /// 没有进行中的更新时，超过 7 天的备份删掉。
    static func expireStaleBackup(store: UpdateStore, now: Date) {
        guard store.loadJournal() == nil, let info = store.backupInfo(),
              now.timeIntervalSince(info.createdAt) >= UpdatePolicy.rollbackWindow else { return }
        store.removeBackup()
    }

    // MARK: 退出与运行时长

    /// applicationWillTerminate 里调用：这一版正常结束。
    static func markCleanExit(store: UpdateStore = .standard) {
        updateOwnLaunch(store: store) { $0.cleanExit = true }
    }

    /// 运行满 30 分钟也记为正常。
    static func markRunSeconds(_ seconds: Double, store: UpdateStore = .standard) {
        updateOwnLaunch(store: store) { $0.runSeconds = max($0.runSeconds, seconds) }
    }

    private static func updateOwnLaunch(store: UpdateStore, _ body: (inout UpdateLaunchRecord) -> Void) {
        guard case .recordAndContinue = action else { return }
        let pid = getpid()
        store.mutateJournal { j in
            guard j != nil, let index = j!.launches.lastIndex(where: { $0.pid == pid && $0.build == myBuild }) else { return }
            body(&j!.launches[index])
        }
    }
}

// MARK: - 发布关第 4.9 步：上一版读得懂这一版写下的状态

/// 样例只写进给定目录：RecoveryJournal.plist（停车日志，格式同 Recovery/Journal.swift）、Preferences.plist（这一版偏好的快照）、
/// Update/journal.json（更新日志）。改停车日志的字段时同步改这里的样例条目和 read 里的必需字段。
enum UpdateStateSample {
    static let recoveryFile = "RecoveryJournal.plist"
    static let preferencesFile = "Preferences.plist"
    /// 读的一方认得的最高 schemaVersion。
    static let knownRecoverySchema = 3

    static func sampleRecoveryEntries(now: TimeInterval = Date().timeIntervalSince1970) -> [[String: Any]] {
        let base: [String: Any] = [
            "schemaVersion": 3, "id": 4242, "pid": 4242, "bundleID": "com.apple.TextEdit",
            "appName": "TextEdit", "title": "Sample", "hide": HideMethod.offscreen.rawValue,
            "stage": ShadeLifecycleStage.folded.rawValue, "state": ShadeLifecycleStage.folded.rawValue,
            "originalX": 100.0, "originalY": 120.0, "originalWidth": 640.0, "originalHeight": 480.0,
            "parkedX": -30000.0, "parkedY": 120.0, "originalAlpha": 1.0, "createdAt": now, "updatedAt": now,
        ]
        var intent = base
        intent["id"] = 4243
        intent["hide"] = HideMethod.none.rawValue
        intent["stage"] = ShadeLifecycleStage.preparing.rawValue
        intent["state"] = ShadeLifecycleStage.preparing.rawValue
        intent.removeValue(forKey: "parkedX")
        intent.removeValue(forKey: "parkedY")
        return [base, intent]
    }

    static func write(to directory: URL) -> Int32 {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try DurableShadeJournal(url: directory.appendingPathComponent(recoveryFile)).save(sampleRecoveryEntries())
            let bundleID = Bundle.main.bundleIdentifier ?? UpdateIdentity.bundleID
            let preferences = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
            let data = try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0)
            try data.write(to: directory.appendingPathComponent(preferencesFile))
            let sample = UpdateJournal(
                from: UpdateVersionRef(version: "0.0.1", build: "1"), to: UpdateVersionRef(version: UpdateLaunch.myVersion, build: UpdateLaunch.myBuild),
                appPath: "/Applications/WindowShade.app", oldDR: "identifier \"\(bundleID)\"",
                backup: directory.appendingPathComponent("WindowShade-0.0.1-1.zip").path, backupSHA256: nil,
                permissionsBefore: UpdatePermissions(accessibility: true, screenRecording: true), phase: .healthy,
                startedAt: Date(), oldPID: 1, launches: [UpdateLaunchRecord(build: UpdateLaunch.myBuild, pid: 2, startedAt: Date(), cleanExit: true, runSeconds: 12)],
                healthyAt: Date())
            try UpdateStore(root: directory).saveJournal(sample)
            print("WindowShade sample state written to \(directory.path)")
            return 0
        } catch {
            print("WindowShade sample state failed: \(error)")
            return 10
        }
    }

    static func read(from directory: URL) -> Int32 {
        var problems: [String] = []
        do {
            let entries = try DurableShadeJournal(url: directory.appendingPathComponent(recoveryFile)).load() ?? []
            if entries.isEmpty { problems.append("recovery journal empty") }
            for (index, entry) in entries.enumerated() {
                problems += recoveryProblems(entry).map { "recovery[\(index)]: \($0)" }
            }
        } catch {
            problems.append("recovery journal unreadable: \(error)")
        }
        let prefsURL = directory.appendingPathComponent(preferencesFile)
        if let data = try? Data(contentsOf: prefsURL),
           let sample = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            let bundleID = Bundle.main.bundleIdentifier ?? UpdateIdentity.bundleID
            let mine = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
            for (key, value) in sample {
                guard let current = mine[key] else { continue }
                if kind(of: value) != kind(of: current) { problems.append("preference \(key) changed type") }
            }
        } else {
            problems.append("preferences unreadable")
        }
        if UpdateStore(root: directory).loadJournal() == nil { problems.append("update journal unreadable") }
        guard problems.isEmpty else {
            problems.forEach { print("WindowShade read-state: \($0)") }
            return 11
        }
        print("WindowShade read-state ok build=\(UpdateLaunch.myBuild)")
        return 0
    }

    /// 救回窗口要用到的字段。
    static func recoveryProblems(_ entry: [String: Any]) -> [String] {
        var problems: [String] = []
        let numbers = ["schemaVersion", "id", "pid", "originalX", "originalY", "originalWidth", "originalHeight"]
        for key in numbers where !(entry[key] is NSNumber) { problems.append("\(key) missing") }
        if let schema = (entry["schemaVersion"] as? NSNumber)?.intValue, schema > knownRecoverySchema {
            problems.append("schemaVersion \(schema) > \(knownRecoverySchema)")
        }
        if !(entry["bundleID"] is String) { problems.append("bundleID missing") }
        if HideMethod(rawValue: entry["hide"] as? String ?? "") == nil { problems.append("hide unknown") }
        if ShadeLifecycleStage(rawValue: entry["stage"] as? String ?? "") == nil { problems.append("stage unknown") }
        if entry["stage"] as? String == ShadeLifecycleStage.folded.rawValue {
            for key in ["parkedX", "parkedY"] where !(entry[key] is NSNumber) { problems.append("\(key) missing") }
        }
        return problems
    }

    private static func kind(of value: Any) -> String {
        let object = value as AnyObject
        let id = CFGetTypeID(object)
        if id == CFBooleanGetTypeID() { return "bool" }
        if id == CFNumberGetTypeID() { return "number" }
        if id == CFStringGetTypeID() { return "string" }
        if id == CFDataGetTypeID() { return "data" }
        if id == CFDateGetTypeID() { return "date" }
        if id == CFArrayGetTypeID() { return "array" }
        if id == CFDictionaryGetTypeID() { return "dictionary" }
        return "other"
    }
}
