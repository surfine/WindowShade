
// The runner appends this extension to its production-file snapshot, allowing
// private lifecycle tests without ScreenCaptureKit or real window mutations.
extension WindowFoldEffects {
  @MainActor static func verifyLifecycle() {
    let owner = AppDelegate()
    let effects = WindowFoldEffects()
    effects.owner = owner
    let element = AXUIElementCreateApplication(getpid())
    let id: CGWindowID = 4_000_000
    var completions: [Bool] = []
    func wait() {
      owner.registerFoldWaiter(id: id) { completions.append($0) }
    }
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
    precondition(effects.jobs[id] == nil && completions == [false])
    effects.cancel(replacement)
    precondition(completions == [false], "Cancellation completes only once")

    completions = []
    let reversal = install()
    wait()
    effects.request(reversal, folded: false)
    precondition(effects.jobs[id] == nil && completions == [false],
                 "Reversing preparation cancels the unstarted fold")

    completions = []
    let hidden = install(.hiding)
    wait()
    effects.cancel(hidden)
    precondition(effects.jobs[id] == nil && completions.isEmpty,
                 "Removing a cover must not settle an in-flight hide")
    owner.settleFoldWaiters(id: id, success: true)
    precondition(completions == [true])

    completions = []
    let fallback = install(.hiding)
    wait()
    effects.fallback(fallback)
    precondition(effects.jobs[id] == nil && completions.isEmpty)
    owner.settleFoldWaiters(id: id, success: false)
    precondition(completions == [false], "Legacy rollback still owns fallback completion")

    completions = []
    let handedOff = install()
    wait()
    effects.dispose(handedOff)
    precondition(completions.isEmpty, "Resource disposal preserves completion for handoff")
    owner.settleFoldWaiters(id: id, success: true)
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
    precondition(effects.jobs[id] === spawned && !newCompleted)
    effects.cancelAll()
    precondition(effects.jobs.isEmpty && newCompleted)

    // Closing a fold settles only the captured waiter set. A replacement request
    // registered by a completion must not be canceled by that old cleanup.
    var replacementCompleted = false
    var originalCompleted = false
    let original = owner.registerFoldWaiter(id: id) { success in
      precondition(!success)
      originalCompleted = true
      owner.registerFoldWaiter(id: id) { _ in replacementCompleted = true }
    }
    owner.cancelFoldWaiters(id: id, tokens: [original])
    precondition(originalCompleted && !replacementCompleted)
    owner.cancelFoldWaiters(id: id, tokens: [original])
    precondition(!replacementCompleted)
    owner.settleFoldWaiters(id: id, success: true)
    precondition(replacementCompleted)
    print("PASS: stale cancellation, reversal, handoff, hide completion ownership, watchdog generations and reentrant cancellation")
  }
}

@main enum WindowFoldEffectsTests {
  @MainActor static func main() {
    _ = NSApplication.shared
    WindowFoldEffects.verifyLifecycle()
  }
}
