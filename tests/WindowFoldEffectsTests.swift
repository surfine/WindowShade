
// The runner appends this extension to its production-file snapshot, allowing
// private lifecycle tests without ScreenCaptureKit or real window mutations.
extension WindowFoldEffects {
  @MainActor static func verifyLifecycle() async {
    let owner = AppDelegate()
    let effects = WindowFoldEffects()
    effects.owner = owner
    let element = AXUIElementCreateApplication(getpid())
    let id: CGWindowID = 4_000_000
    var completions: [Bool] = []
    var lastToken: UUID?
    // 第九份的完成通知在投递前会重查锁态与具体事务；测试把锁态固定成未锁屏，
    // 并在需要“成功”时装一份真实 folded 状态，走的就是生产里的结算门槛。
    let savedLockState = AuthorizationService.shared.lockState
    AuthorizationService.shared.lockState = { .unlocked }
    defer { AuthorizationService.shared.lockState = savedLockState }
    func wait() {
      lastToken = owner.registerFoldWaiter(id: id) { completions.append($0) }
    }
    // 第九份起：完成通知先整批取出、再排队投递，而且不再有「只按窗口 ID 报成功」的路径。
    // 测试照生产顺序先把 token 绑到一个事务、再按该事务结算；投递落到下一轮主队列，用 flush 对账。
    func installLiveState() -> ShadeState {
      let state = ShadeState(element: element,
                             sourceWindowID: id,
                             originalPosition: .zero,
                             originalSize: CGSize(width: 800, height: 600),
                             sourceDisplayID: nil,
                             sourceSpaceID: nil,
                             overlay: nil,
                             overlayID: nil,
                             hide: .offscreen,
                             pid: getpid(),
                             bundleID: "com.windowshade.test",
                             appName: "WindowShadeTest",
                             title: "fold-waiter-test",
                             appearanceMode: .nativeScreenshot,
                             lifecycleStage: .folded,
                             previewImage: nil,
                             quickLookReopenURL: nil,
                             ignoreAppRevealUntil: .distantPast,
                             observer: nil)
      owner.shaded[id] = state
      return state
    }
    func settleLatest(_ success: Bool) {
      guard let token = lastToken else { return }
      let transaction = success ? installLiveState().foldTransactionID : UUID()
      owner.bindFoldWaiters(id: id, tokens: [token], transaction: transaction)
      owner.settleFoldWaiters(id: id, transaction: transaction, success: success)
    }
    func flush() async { await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } }
    func install(_ phase: Phase = .preparing, folded: Bool = true) -> Job {
      let job = Job(id: id, element: element, folded: folded)
      job.phase = phase
      effects.jobs[id] = job
      return job
    }

    let old = install()
    let replacement = install()
    wait()
    effects.cancel(old)
    precondition(effects.jobs[id] === replacement && completions.isEmpty,
                 "An old continuation cannot cancel its replacement or settle its waiters")
    effects.cancel(replacement)
    await flush()
    precondition(effects.jobs[id] == nil && completions == [false])
    effects.cancel(replacement)
    await flush()
    precondition(completions == [false], "Cancellation completes only once")

    completions = []
    let reversal = install()
    wait()
    effects.request(reversal, folded: false)
    await flush()
    precondition(effects.jobs[id] == nil && completions == [false],
                 "Reversing preparation cancels the unstarted fold")

    completions = []
    let hidden = install(.hiding)
    wait()
    effects.cancel(hidden)
    precondition(effects.jobs[id] == nil && completions.isEmpty,
                 "Removing a cover must not settle an in-flight hide")
    settleLatest(true)
    await flush()
    precondition(completions == [true])

    completions = []
    let fallback = install(.hiding)
    wait()
    effects.fallback(fallback)
    precondition(effects.jobs[id] == nil && completions.isEmpty)
    settleLatest(false)
    await flush()
    precondition(completions == [false], "Legacy rollback still owns fallback completion")

    completions = []
    let handedOff = install()
    wait()
    effects.dispose(handedOff)
    precondition(completions.isEmpty, "Resource disposal preserves completion for handoff")
    settleLatest(true)
    await flush()
    precondition(completions == [true])

    let timed = install()
    let first = effects.beginHide(timed)
    timed.phase = .unfolding
    effects.hideWatchdogExpired(timed, generation: first)
    precondition(effects.jobs[id] === timed, "Old hide timeout cannot interrupt unfolding")
    let second = effects.beginHide(timed)
    effects.hideWatchdogExpired(timed, generation: first)
    precondition(effects.jobs[id] === timed, "Same job's next hide has a separate deadline")
    effects.hideWatchdogExpired(timed, generation: second)
    precondition(effects.jobs[id] == nil)

    let late = install(folded: false)
    let generation = effects.beginHide(late)
    effects.hideWatchdogExpired(late, generation: generation)
    precondition(effects.restoreAfterHide[id] != nil,
                 "Reversal survives a cover timeout before the hidden session is installed")
    effects.restoreAfterHide.removeAll()

    // Cancellation callbacks may synchronously install a new job and waiter.
    // They belong to the next request and must survive cancelAll's snapshot.
    _ = install()
    var spawned: Job?
    var newCompleted = false
    owner.registerFoldWaiter(id: id) { _ in
      spawned = install()
      owner.registerFoldWaiter(id: id) { _ in newCompleted = true }
    }
    effects.cancelAll()
    await flush()
    precondition(effects.jobs[id] === spawned && !newCompleted)
    effects.cancelAll()
    await flush()
    precondition(effects.jobs.isEmpty && newCompleted)

    // Closing a fold settles only the captured waiter set. A replacement request
    // registered by a completion must not be canceled by that old cleanup.
    var replacementCompleted = false
    var originalCompleted = false
    var replacementToken: UUID?
    let original = owner.registerFoldWaiter(id: id) { success in
      precondition(!success)
      originalCompleted = true
      replacementToken = owner.registerFoldWaiter(id: id) { _ in replacementCompleted = true }
    }
    owner.cancelFoldWaiters(id: id, tokens: [original])
    await flush()
    precondition(originalCompleted && !replacementCompleted)
    owner.cancelFoldWaiters(id: id, tokens: [original])
    await flush()
    precondition(!replacementCompleted)
    if let replacementToken {
      let replacementTransaction = installLiveState().foldTransactionID
      owner.bindFoldWaiters(id: id, tokens: [replacementToken], transaction: replacementTransaction)
      owner.settleFoldWaiters(id: id, transaction: replacementTransaction, success: true)
      await flush()
    }
    precondition(replacementCompleted)
    print("PASS: stale cancellation, reversal, handoff, hide completion ownership, watchdog generations and reentrant cancellation")
  }
}

@main enum WindowFoldEffectsTests {
  @MainActor static func main() async {
    _ = NSApplication.shared
    await WindowFoldEffects.verifyLifecycle()
  }
}
