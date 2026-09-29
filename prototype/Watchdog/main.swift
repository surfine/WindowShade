// WindowShade 的更新看护（WindowShadeUpdateGuard.app，放在 Contents/Helpers/，由 build.sh 单独编译）。
//
// 他点“更新并重新打开”时，正在运行的旧版把自己包里的这个小 App 拷到
// ~/Library/Application Support/WindowShade/Update/，用 SMJobSubmit 在用户域提交（标签 com.windowshade.prototype.update-guard）。
// 从这一刻起它盯着旧版；旧版一退出就接手，直到新版写下 healthy，或换回旧版：
//   1. 旧版还开着：用 kqueue（DispatchSource 进程源，NOTE_EXIT）等旧 pid 退出，用目录的文件源等日志变化，不轮询。
//      否决（cancelled / refused）后不自己退出：App 确认 Sparkle 的安装任务没了才 SMJobRemove 看护；删不掉时看护留着兜底。
//      只有日志被换掉（放回了另存的日志、或已删掉）才退出，那一定发生在 App 确认之后。
//   2. 旧版退出了：显示和 WindowShade 相同的菜单栏图标（看得见的进程不受后台活动限制，菜单栏也不空出来），然后按 phase 分：
//      started / gating：关没跑完旧版就没了。等 Sparkle 安装任务结束（最多 120 秒）：没装上就打开旧版；装上了就补做 DR 比对和试跑。
//      cancelled / refused：否决了，但旧版可能在确认安装任务没了之前就退出。同样等任务结束：没装上就安静退出（他自己退的，不重开）；
//        装上了：refused 直接换回，cancelled 补关，不过就换回。
//      approved：等交换完成；任务没了版本也没变是交换失败，打开旧版。
//   3. 新版 20 秒没进 main 就自己按路径打开；4. 60 秒内等 healthy，崩溃、自查没过、卡住就换回；
//   5. 换回先写 refused.json 和 restoring 再动文件；没做成就写终态 restoreFailed，打开装着的那一版，由它说“没能换回”；
//   6. 拿到 healthy 就收起图标退出。
// 补关只能把 started / gating / cancelled 改成 approved，不盖掉新版同时写下的 launched 或 healthy。
// 带 --restore 时一起来就换回（新版在 main 里发现起不来，或他在设置里点了“回到 x.y.z”）。
// 判断在 Core/UpdateDecisions.swift，做事的代码在 App/UpdaterSystem.swift，App 和看护编译同一份；图标在 Watchdog/GuardIcon.swift。

import Cocoa

let guardArguments = CommandLine.arguments

func guardArgument(_ name: String) -> String? {
    guard let index = guardArguments.firstIndex(of: name), guardArguments.count > index + 1 else { return nil }
    return guardArguments[index + 1]
}

let guardStore = UpdateStore(root: guardArgument("--store").map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? UpdateStore.standard.root)
let guardRestoreMode = guardArguments.contains("--restore")

private let guardLogURL = guardStore.updateDirectory.appendingPathComponent("guard.log")
private let guardLogLock = NSLock()

UpdateLog.sink = { line in
    guardLogLock.lock()
    defer { guardLogLock.unlock() }
    let stamp = ISO8601DateFormatter().string(from: Date())
    let data = Data("\(stamp) [\(getpid())] \(line)\n".utf8)
    if let size = (try? FileManager.default.attributesOfItem(atPath: guardLogURL.path))?[.size] as? Int, size > 256 * 1024 {
        try? FileManager.default.removeItem(at: guardLogURL)
    }
    if let handle = try? FileHandle(forWritingTo: guardLogURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: guardLogURL)
    }
}

/// 旧 pid 退出（kqueue EVFILT_PROC / NOTE_EXIT）或 Update/ 目录有变化（日志原子改名）时唤醒等待的线程。
final class GuardEvents: @unchecked Sendable {
    private let signal = DispatchSemaphore(value: 0)
    private let queue = DispatchQueue(label: "com.windowshade.update-guard.events")
    private var sources: [DispatchSourceProtocol] = []

    init(pid: Int32, directory: URL) {
        let signal = self.signal
        if pid > 0 {
            let process = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            process.setEventHandler { signal.signal() }
            process.resume()
            sources.append(process)
        }
        let fd = Darwin.open(directory.path, O_EVTONLY)
        if fd >= 0 {
            let folder = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                                   queue: queue)
            folder.setEventHandler { signal.signal() }
            folder.setCancelHandler { Darwin.close(fd) }
            folder.resume()
            sources.append(folder)
        }
    }

    /// 等下一个事件；timeout 只是兜底（pid 在注册前就已退出、目录源没建起来）。
    func wait(timeout: TimeInterval) { _ = signal.wait(timeout: .now() + timeout) }

    func cancel() { sources.forEach { $0.cancel() } }
}

final class UpdateGuard: NSObject, @unchecked Sendable {
    private let store: UpdateStore
    private var statusItem: NSStatusItem?
    private let poll: TimeInterval = 0.5

    init(store: UpdateStore) { self.store = store }

    // MARK: 界面：只有一个菜单栏图标

    private func showIcon() {
        DispatchQueue.main.async {
            guard self.statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = makeGuardStatusIcon()
            item.button?.setAccessibilityLabel("WindowShade")
            let menu = NSMenu()
            let line = NSMenuItem(title: UpdateCopy.relaunching, action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(line)
            item.menu = menu
            self.statusItem = item
        }
    }

    private func finish(_ why: String) -> Never {
        UpdateLog.write("guard done: \(why)")
        store.clearGuardPID()
        DispatchQueue.main.sync {
            if let item = self.statusItem { NSStatusBar.system.removeStatusItem(item) }
        }
        exit(0)
    }

    private func open(_ appPath: String) {
        let url = URL(fileURLWithPath: appPath)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            // 按路径打开，不按 bundle ID：“下载”里的原件、缓存里解开的副本、换回用的临时副本都可能被 LaunchServices 选中。
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error { UpdateLog.write("open \(appPath) failed: \(error)") }
                done.signal()
            }
        }
        _ = done.wait(timeout: .now() + 15)
    }

    private func sleep() { Thread.sleep(forTimeInterval: poll) }

    private func waitForExit(_ pid: Int32, timeout: TimeInterval?) -> Bool {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        while UpdateFacts.isAlive(pid) {
            if let deadline, Date() >= deadline { return false }
            sleep()
        }
        return true
    }

    private func stop(_ pid: Int32) {
        guard UpdateFacts.isAlive(pid) else { return }
        kill(pid, SIGTERM)
        if !waitForExit(pid, timeout: 5) { kill(pid, SIGKILL) }
        _ = waitForExit(pid, timeout: 5)
    }

    // MARK: 换回

    /// 换回前先停掉正在运行的新版（补关没过时 Sparkle 可能已经把它打开了），否则交换会换掉它脚下的包。
    private func stopRunningCopies(of journal: UpdateJournal) {
        let appPath = (journal.appPath as NSString).standardizingPath
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: UpdateIdentity.bundleID)
            .filter { ($0.bundleURL?.path).map { ($0 as NSString).standardizingPath } == appPath && $0.processIdentifier != getpid() }
        for app in running { stop(app.processIdentifier) }
    }

    /// 换回没做成时 UpdateRestorer 已写下终态 restoreFailed、撤掉了 refused 那一条：照样按路径打开装着的那一版，
    /// 它读到 restoreFailed 就照常运行、说一次“没能换回”，不会再交回来。
    private func restore(_ journal: UpdateJournal, reason: UpdateRestoreReason) -> Never {
        showIcon()
        stopRunningCopies(of: journal)
        do {
            try UpdateRestorer.restore(store: store, reason: reason)
        } catch {
            UpdateLog.write("restore failed: \(error)")
        }
        open(journal.appPath)
        finish("restore \(reason.rawValue)")
    }

    // MARK: 主流程（后台线程，阻塞式轮询）

    func run() -> Never {
        store.writeGuardPID(getpid())
        var loaded: UpdateJournal?
        for _ in 0..<10 {
            loaded = store.loadJournal()
            if loaded != nil { break }
            sleep()
        }
        guard let journal = loaded else { finish("no journal") }
        let target = journal.to.build
        UpdateLog.write("guard start \(journal.from.build) -> \(target) phase=\(journal.phase.rawValue) restore=\(guardRestoreMode)")

        if guardRestoreMode {
            if let requester = journal.requesterPID, !waitForExit(requester, timeout: 30) { stop(requester) }
            showIcon()
            let reason = store.loadJournal()?.restoreReason ?? journal.restoreReason ?? .crashed
            restore(journal, reason: reason)
        }

        // 1. 旧版还开着：等事件，不轮询。
        let events = GuardEvents(pid: journal.oldPID, directory: store.updateDirectory)
        while UpdateFacts.isAlive(journal.oldPID) {
            guard let current = store.loadJournal(), current.to.build == target else { finish("journal superseded") }
            events.wait(timeout: 30)
        }
        events.cancel()

        // 2. 旧版退出了
        guard let atExit = store.loadJournal(), atExit.to.build == target else { finish("journal gone at old exit") }
        UpdateLog.write("old exited at phase \(atExit.phase.rawValue)")
        let sparkleLabel = UpdateIdentity.sparkleInstallerLabel()
        let plan = UpdateGuardPolicy.afterOldExit(phase: atExit.phase)
        switch plan {
        case .exit:
            finish("nothing to watch")
        case .restore:
            restore(atExit, reason: atExit.restoreReason ?? .crashed)
        case .waitUngatedInstall, .waitApprovedInstall, .waitVetoedInstall:
            // 否决后他自己退出的，多半什么都没装：安装任务还在时才亮图标。
            if plan != .waitVetoedInstall { showIcon() }
            let started = Date()
            var outcome = UpdateGuardPolicy.InstallOutcome.keepWaiting
            while outcome == .keepWaiting {
                let jobAlive = UpdateJobs.isRunning(label: sparkleLabel)
                if jobAlive { showIcon() }
                outcome = UpdateGuardPolicy.installOutcome(
                    installedBuild: UpdateBundleInfo(appURL: URL(fileURLWithPath: atExit.appPath))?.build, to: target,
                    jobAlive: jobAlive, elapsed: Date().timeIntervalSince(started))
                if outcome == .keepWaiting { sleep() }
            }
            if outcome == .notInstalled {
                if plan == .waitVetoedInstall {
                    // 旧版没来得及收尾：替它丢掉半截备份、放回上一次成功更新的日志（“回到 x.y.z”还在）。
                    UpdateBackup.discardPartials(store: store)
                    store.restoreStashedJournal(replacing: target)
                    finish("vetoed and not installed")
                }
                store.setPhase(.installFailed)
                open(atExit.appPath)
                finish("not installed")
            }
            showIcon()
            if atExit.phase == .refused {
                // 关拦下的版本还是被装上了（否决没送到、任务没删掉）：直接换回。
                restore(atExit, reason: atExit.restoreReason ?? .selfCheckFailed)
            }
            if atExit.phase != .approved {
                // 没过关的安装：对已装的新版补做 DR 比对和试跑，规则同关。
                let verdict = UpdateGate.check(staged: URL(fileURLWithPath: atExit.appPath), oldDR: atExit.oldDR, build: target)
                UpdateLog.write("ungated install check: \(verdict)")
                if let reason = UpdateGate.afterInstall(verdict) { restore(store.loadJournal() ?? atExit, reason: reason) }
                // 只改还停在关前的 phase：新版可能已经起来写了 launched，甚至 healthy。
                store.setPhase(.approved, onlyIf: [.started, .gating, .cancelled])
            }
        }

        // 3–4. 等新版起来、等 healthy
        let watchStarted = Date()
        var opened = false
        var cleanExitSeen: (pid: Int32, at: Date)?
        while true {
            sleep()
            guard let current = store.loadJournal(), current.to.build == target else { finish("journal superseded") }
            let launch = current.launches.last { $0.build == target && $0.startedAt >= atExit.startedAt }
            let alive = launch.map { UpdateFacts.isAlive($0.pid) } ?? false
            if let launch, launch.cleanExit, !alive {
                if cleanExitSeen?.pid != launch.pid { cleanExitSeen = (launch.pid, Date()) }
            } else {
                cleanExitSeen = nil
            }
            let now = Date()
            let action = UpdateGuardPolicy.watch(.init(
                phase: current.phase, launch: launch, pidAlive: alive,
                waited: now.timeIntervalSince(watchStarted),
                sinceLaunch: launch.map { now.timeIntervalSince($0.startedAt) } ?? 0,
                openedByGuard: opened,
                sinceCleanExit: cleanExitSeen.map { now.timeIntervalSince($0.at) },
                reason: current.restoreReason))
            switch action {
            case .keepWaiting, .waitCleanRelaunch:
                continue
            case .openApp:
                UpdateLog.write("new version did not start; opening it")
                open(current.appPath)
                opened = true
            case .healthy:
                finish("healthy")
            case .restore(let reason):
                restore(current, reason: reason)
            case .terminateThenRestore:
                if let pid = launch?.pid { stop(pid) }
                restore(current, reason: .hung)
            case .exit:
                finish("new version exited cleanly")
            }
        }
    }
}

let guardApp = NSApplication.shared
guardApp.setActivationPolicy(.accessory)
let updateGuard = UpdateGuard(store: guardStore)
Thread.detachNewThread { updateGuard.run() }
guardApp.run()
