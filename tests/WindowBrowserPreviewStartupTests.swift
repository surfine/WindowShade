import Foundation

@MainActor
private final class Gate {
    private var entered = false
    private var pending: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            pending = continuation
            entered = true
            observer?.resume()
            observer = nil
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }

    func open() {
        pending?.resume()
        pending = nil
    }
}

@main
enum WindowBrowserPreviewStartupTests {
    enum Failure: Error { case unavailable }

    @MainActor
    static func main() async {
        // The source API need not cooperate with Task cancellation. Its late
        // response must not start a capture after the panel has been closed.
        let loading = Gate()
        var starts = 0
        var ready = 0
        var failures = 0
        var discards = 0
        let cancelled = Task { @MainActor in
            await WindowBrowserPreviewStartup.run(
                load: { await loading.wait(); return 1 },
                start: { _ in starts += 1 },
                isCurrent: { true }, discard: { discards += 1 },
                ready: { ready += 1 }, failed: { _ in failures += 1 })
        }
        await loading.waitUntilEntered()
        cancelled.cancel()
        loading.open()
        await cancelled.value
        precondition(starts == 0 && ready == 0 && failures == 0 && discards == 1,
                     "cancel during source lookup must not start capture or publish failure")

        // If cancellation happens inside startCapture, dispose of the created
        // resource when that uncooperative API eventually returns.
        let starting = Gate()
        var current = true
        var resources = 0
        let replaced = Task { @MainActor in
            await WindowBrowserPreviewStartup.run(
                load: { 1 },
                start: { _ in resources += 1; await starting.wait() },
                isCurrent: { current }, discard: { resources = 0 },
                ready: { ready += 1 }, failed: { _ in failures += 1 })
        }
        await starting.waitUntilEntered()
        current = false
        starting.open()
        await replaced.value
        precondition(resources == 0 && ready == 0 && failures == 0,
                     "superseded start must dispose its stream without attaching a view")

        // An old failure must not clear or report an error over a replacement
        // which has already become ready.
        let oldLoad = Gate()
        var oldIsCurrent = true
        let old = Task { @MainActor in
            await WindowBrowserPreviewStartup.run(
                load: { () async throws -> Int in
                    await oldLoad.wait()
                    throw Failure.unavailable
                }, start: { _ in preconditionFailure("failed lookup cannot start") },
                isCurrent: { oldIsCurrent }, discard: { discards += 1 },
                ready: { preconditionFailure("failed lookup cannot become ready") },
                failed: { _ in failures += 1 })
        }
        await oldLoad.waitUntilEntered()
        oldIsCurrent = false
        await WindowBrowserPreviewStartup.run(
            load: { 2 }, start: { _ in starts += 1 },
            isCurrent: { true }, discard: { preconditionFailure("valid capture must survive") },
            ready: { ready += 1 }, failed: { _ in failures += 1 })
        oldLoad.open()
        await old.value
        precondition(ready == 1 && starts == 1 && failures == 0 && discards == 2,
                     "late failure must not affect replacement state")

        await WindowBrowserPreviewStartup.run(
            load: { 3 }, start: { _ in throw Failure.unavailable },
            isCurrent: { true }, discard: { discards += 1 },
            ready: { preconditionFailure("failed capture cannot become ready") },
            failed: { _ in failures += 1 })
        precondition(failures == 1 && discards == 3,
                     "current failures still clean up and report once")

        let notStarted = Task { @MainActor in
            await WindowBrowserPreviewStartup.run(
                load: { () -> Int in preconditionFailure("cancelled task must not load") },
                start: { _ in preconditionFailure("cancelled task must not start") },
                isCurrent: { true }, discard: { discards += 1 },
                ready: { preconditionFailure("cancelled task must not publish") },
                failed: { _ in preconditionFailure("cancellation is not a capture error") })
        }
        notStarted.cancel()
        await notStarted.value
        precondition(discards == 4)
        print("PASS: preview startup cancellation before load, during lookup/start, stale failure, current failure")
    }
}
