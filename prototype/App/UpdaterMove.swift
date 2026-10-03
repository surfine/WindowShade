// 应用内更新：“移到‘应用程序’”。欢迎窗口第一次打开时需要就多这一步；更新小窗里位置不对时也走这里。
//
// 不接 LetsMove 库，只借它的流程：复制正在运行的这一份（被系统挪走时 Bundle.main.bundleURL 也读得到）到目标卷的临时目录，
// 清掉隔离标记，验签名和 DR 与自己相同，再改名放进去；目标处有旧版就原子交换，换下来的移到废纸篓；
// 从新位置打开（带 --after-move），当前进程退出。“下载”里的原件不动。
// 两条保护（欢迎窗口和更新小窗都走 moveToApplications，所以都有）：
//   “应用程序”里已有的那一份不比自己旧，就改成打开它，绝不拿旧的换掉新的；
//   目标处已有的包签名要求（DR）和自己不同，不替换（那不是我们签的同一个 WindowShade），按“没能移过去”处理。
//
// 接线（Welcome.swift，欢迎窗口三步之前、同一个舞台）：
//     if let step = UpdaterMove.shared.welcomeStep() { …按 step 的文字画这一步… }
//     主按钮：UpdaterMove.shared.performPrimary { result in if case .failed = result { …显示 UpdateCopy.moveFailed 和“在访达中显示”… } }
//     “跳过”：UpdaterMove.shared.declineForWelcome()
//     新进程带 --after-move 时（UpdaterMove.shared.launchedAfterMove）欢迎窗口从第 1 步接着走。
//     授权页导语下：if UpdaterMove.shared.isStandardAccount { UpdateCopy.standardAccount }

import Cocoa

struct UpdaterMoveStep: Equatable {
    enum Kind: Equatable {
        case move
        case replaceOlder(String)
        case alreadyThere(String)
    }

    var kind: Kind
    var title: String { UpdateCopy.moveTitle }
    var lead: String {
        if case .alreadyThere(let version) = kind { return UpdateCopy.moveAlreadyThere(version) }
        return UpdateCopy.moveLead
    }
    /// 副句：那里已有旧版时说明会被换掉。
    var note: String? {
        if case .replaceOlder(let version) = kind { return UpdateCopy.moveReplaces(version) }
        return nil
    }
    var primaryTitle: String {
        if case .alreadyThere = kind { return UpdateCopy.moveOpenIt }
        return UpdateCopy.moveButton
    }
    var secondaryTitle: String { UpdateCopy.moveSkip }
}

enum UpdaterMoveResult: Equatable {
    case relaunching
    case failed(String)
}

@MainActor
final class UpdaterMove {
    static let shared = UpdaterMove()

    var launchedAfterMove: Bool { CommandLine.arguments.contains(UpdateIdentity.afterMoveArgument) }
    var isStandardAccount: Bool { !UpdateFacts.isAdminUser() }

    private var source: URL { Bundle.main.bundleURL }

    /// 放进“应用程序”的目标：/Applications 写得进去就用它，否则 ~/Applications（标准账户）。两处都能一键更新。
    private func destinationFolder() -> URL {
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        if access(system.path, W_OK) == 0 { return system }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    }

    private func destination() -> URL {
        destinationFolder().appendingPathComponent("WindowShade.app", isDirectory: true)
    }

    /// 已经在“应用程序”里的那一份（先看 /Applications，再看 ~/Applications）。
    private func installedCopy() -> (URL, UpdateBundleInfo)? {
        let candidates = [URL(fileURLWithPath: "/Applications/WindowShade.app"),
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/WindowShade.app")]
        for url in candidates where url.standardizedFileURL != source.standardizedFileURL {
            if let info = UpdateBundleInfo(appURL: url), info.bundleID == (Bundle.main.bundleIdentifier ?? UpdateIdentity.bundleID) {
                return (url, info)
            }
        }
        return nil
    }

    /// 欢迎窗口要不要多这一步；nil 表示不用。
    func welcomeStep() -> UpdaterMoveStep? {
        guard !launchedAfterMove else { return nil }
        let facts = UpdateFacts.location(of: source)
        guard UpdatePolicy.needsMove(facts) else { return nil }
        if let (url, info) = installedCopy() {
            if !UpdateVersion.isNewer(UpdateLaunch.myBuild, than: info.build) {
                // 他又打开了“下载”里的原件：替他打开“应用程序”里那一份。
                return UpdaterMoveStep(kind: .alreadyThere(info.version))
            }
            guard !UserDefaults.standard.bool(forKey: UpdateSettingsKeys.moveDeclined) else { return nil }
            // 只有旧版就在要放进去的那个位置时才说“会换成这一版”（标准账户放进 ~/Applications，/Applications 里的旧版不动）。
            if url.standardizedFileURL == destination().standardizedFileURL {
                return UpdaterMoveStep(kind: .replaceOlder(info.version))
            }
            return UpdaterMoveStep(kind: .move)
        }
        guard !UserDefaults.standard.bool(forKey: UpdateSettingsKeys.moveDeclined) else { return nil }
        return UpdaterMoveStep(kind: .move)
    }

    /// 点“跳过”后不再追问；定时检查照常，更新小窗里还会再给这一步。
    func declineForWelcome() {
        UserDefaults.standard.set(true, forKey: UpdateSettingsKeys.moveDeclined)
    }

    /// 欢迎窗口的主按钮：“移到‘应用程序’”或“打开它”。
    func performPrimary(completion: @escaping @MainActor (UpdaterMoveResult) -> Void) {
        moveToApplications(completion: completion)
    }

    /// 欢迎窗口和更新小窗共用。“应用程序”里已有的那一份不比自己旧，就打开它，不移动。
    func moveToApplications(completion: @escaping @MainActor (UpdaterMoveResult) -> Void) {
        if let (url, info) = installedCopy(), !UpdateVersion.isNewer(UpdateLaunch.myBuild, than: info.build) {
            UpdateLog.write("move: \(url.path) already has \(info.build); opening it")
            relaunch(at: url, afterMove: false)
            completion(.relaunching)
            return
        }
        let source = self.source
        let destination = self.destination()
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            completion(.failed("already at destination"))
            return
        }
        guard let dr = UpdateCodeSign.runningDR() else {
            completion(.failed("no designated requirement"))
            return
        }
        // 目标处有旧版且正在运行时，先请它退出。
        for app in NSWorkspace.shared.runningApplications
        where app.bundleURL?.standardizedFileURL == destination.standardizedFileURL && app.processIdentifier != getpid() {
            app.terminate()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result<Void, Error> {
                try Self.waitForOthersToQuit(at: destination)
                try Self.copy(source, to: destination, expectedDR: dr)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .success:
                        UpdateLog.write("moved to \(destination.path)")
                        self.relaunch(at: destination, afterMove: true)
                        completion(.relaunching)
                    case .failure(let error):
                        UpdateLog.write("move failed: \(error)")
                        completion(.failed("\(error)"))
                    }
                }
            }
        }
    }

    nonisolated private static func waitForOthersToQuit(at destination: URL) throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? UpdateIdentity.bundleID)
                .contains { $0.bundleURL?.standardizedFileURL == destination.standardizedFileURL && !$0.isTerminated }
            if !running { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw UpdateFiles.Failure.verify("old copy still running")
    }

    /// 先复制到目标卷的临时目录、清隔离、验 DR，再放进去；已有旧版就原子交换，换下来的移到废纸篓。
    nonisolated static func copy(_ source: URL, to destination: URL, expectedDR: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let scratch = try UpdateFiles.replacementDirectory(near: destination.deletingLastPathComponent())
        defer { try? fm.removeItem(at: scratch) }
        let staged = scratch.appendingPathComponent(destination.lastPathComponent, isDirectory: true)
        try UpdateFiles.ditto([source.path, staged.path])
        UpdateFiles.removeQuarantine(staged)
        let verdict = UpdateCodeSign.check(staged, against: expectedDR)
        guard verdict == .same else { throw UpdateFiles.Failure.verify("copy DR \(verdict)") }
        let replacing = fm.fileExists(atPath: destination.path)
        if replacing {
            // 目标处那一份不是同一个签名的 WindowShade（别人签的、改过的、或根本不是 App）：不替换。
            guard let existingDR = UpdateCodeSign.staticDR(of: destination), existingDR == expectedDR else {
                throw UpdateFiles.Failure.verify("existing copy at \(destination.path) has a different signature")
            }
        }
        try UpdateFiles.place(staged, at: destination)
        if replacing { try? fm.trashItem(at: staged, resultingItemURL: nil) }
    }

    /// 等这个进程退出后从新位置打开；新进程带 --after-move，欢迎窗口从第 1 步接着走。
    private func relaunch(at app: URL, afterMove: Bool) {
        let script = "while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open -n \"$1\""
            + (afterMove ? " --args \(UpdateIdentity.afterMoveArgument)" : "")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", app.path]
        do {
            try process.run()
        } catch {
            UpdateLog.write("relaunch helper failed: \(error)")
            NSWorkspace.shared.open(app)
        }
        NSApp.terminate(nil)
    }
}
