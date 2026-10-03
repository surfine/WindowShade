import Cocoa

/// T3：番茄钟真正动窗口的那一层。
///
/// 只动这一轮自己收起来、而且没有被别人动过的窗口：收的时候按前后差算出名单，
/// 用 `WS2FocusWindowOwnership` 收据比对进程、进程启动时间和窗口 revision，放不回去就跳过。
/// 「专注时把聊天收进刘海」还缺私人 App 名单（T3 的另一半），所以那两条效果只登记、不执行——
/// 绝不用「把全部窗口收起来」冒充「把聊天收起来」。
@MainActor
final class WS2FocusExecutor {
    private weak var owner: AppDelegate?
    private var ownership = WS2FocusWindowOwnership()
    private var launches: [CGWindowID: TimeInterval] = [:]
    private var snapshots: [WS2.Token: UInt64] = [:]

    /// 收聊天要的私人 App 名单还没有；设置里的那一项据此保持不可用。
    static let chatTuckingReady = false

    init(owner: AppDelegate) { self.owner = owner }

    func handle(_ effects: [FocusTimer.Effect]) {
        for effect in effects {
            switch effect {
            case .tuckAll(let token): tuckAll(token)
            case .restoreAll(let token): restoreAll(token)
            case .sound(.restStarted): owner?.playFoldSound()
            case .sound(.restFinished): owner?.playUnfoldSound()
            case .tuckChat(let token), .restoreChat(let token):
                // 没有名单就不动窗口：不收、不放，也不拿别的动作顶替。
                wlog("focus: chat tucking not wired, token \(token.serial)")
            case .fault(let fault):
                wlog("focus executor fault: \(fault.rawValue)")
            }
        }
    }

    private func tuckAll(_ token: WS2.Token) {
        guard let notch = owner?.notch, NotchController.isEnabled else { return }
        let before = Set(notch.tuckedWindowIDs)
        let revisionBefore = notch.tuckRevision
        _ = notch.tuckAll()
        let added = notch.tuckedWindowIDs.filter { !before.contains($0) }
        guard !added.isEmpty, notch.tuckRevision > revisionBefore else { return }
        let generation = UInt64(1 + snapshots.count)
        var recorded = 0
        for id in added {
            guard let pid = notch.tuckedPID(of: id) else { continue }
            let launch = NSRunningApplication(processIdentifier: pid)?.launchDate?.timeIntervalSince1970 ?? 0
            launches[id] = launch
            let identity = WS2FocusWindowOwnership.Identity(pid: pid, processStart: UInt64(max(0, launch)),
                                                            windowID: id, windowGeneration: notch.tuckRevision)
            let receipt = WS2FocusWindowOwnership.Receipt(identity: identity, run: token, effectGeneration: generation,
                                                          beforeRevision: revisionBefore, afterRevision: notch.tuckRevision)
            if ownership.record(receipt, didComplete: true) { recorded += 1 }
        }
        guard recorded > 0 else { return }
        snapshots[token] = generation
        wlog("focus: tucked \(recorded) windows for run \(token.serial)")
    }

    private func restoreAll(_ token: WS2.Token) {
        guard let notch = owner?.notch, let generation = snapshots.removeValue(forKey: token) else { return }
        let stillTucked = Set(notch.tuckedWindowIDs)
        var restored = 0
        for id in stillTucked {
            guard let pid = notch.tuckedPID(of: id),
                  NSRunningApplication(processIdentifier: pid)?.launchDate?.timeIntervalSince1970 ?? 0 == launches[id] else { continue }
            let identity = WS2FocusWindowOwnership.Identity(pid: pid, processStart: UInt64(max(0, launches[id] ?? 0)),
                                                            windowID: id, windowGeneration: notch.tuckRevision)
            guard ownership.takeForRestore(identity, run: token, effectGeneration: generation,
                                           liveRevision: notch.tuckRevision) != nil else { continue }
            notch.release(id, reason: "focus")
            restored += 1
        }
        wlog("focus: restored \(restored) windows for run \(token.serial)")
    }
}
