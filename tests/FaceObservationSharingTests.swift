import Foundation

private final class CaptureDouble: FaceCaptureWorker, @unchecked Sendable {
    struct State {
        var starts = 0
        var stops = 0
        var rates: [Double] = []
        var generations: [UInt64] = []
        var deliveries: [@Sendable (FaceObservation) -> Void] = []
        var failures: [@Sendable (Error) -> Void] = []
    }
    private let lock = NSLock()
    private var state = State()
    func snapshot() -> State { lock.withLock { state } }
    func start(deviceID: String, token: UInt64, requestedFPS: Double,
               deliver: @escaping @Sendable (FaceObservation) -> Void,
               fail: @escaping @Sendable (Error) -> Void) async throws {
        lock.withLock {
            state.starts += 1; state.generations.append(token); state.rates.append(requestedFPS)
            state.deliveries.append(deliver); state.failures.append(fail)
        }
    }
    func setRequestedFPS(_ fps: Double) { lock.withLock { state.rates.append(fps) } }
    func stop() { lock.withLock { state.stops += 1 } }
    func countersSnapshot() async -> FacePipelineCounters { .init() }
    func emit(_ sample: FaceObservation, session: Int = 0) { snapshot().deliveries[session](sample) }
    func fail(session: Int = 0) { snapshot().failures[session](FaceObservationSourceError.interrupted) }
}

@MainActor private final class TestClock { var now = 10.0 }

@main @MainActor struct FaceObservationSharingTests {
    static var checks = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); checks += 1
    }
    static func drain() async { for _ in 0..<20 { await Task.yield() } }
    static func sample(_ time: Double, sequence: UInt64, generation: UInt64, camera: String = "camera") -> FaceObservation {
        .init(cameraID: camera, generation: generation, sequence: sequence, observedAt: time,
              faceCount: 1, yaw: 0, pitch: 0, leftEyeOpenness: 0.3, rightEyeOpenness: 0.3,
              faceBoundingBox: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5), confidence: 1,
              mouthLandmarks: [CGPoint(x: 0.3, y: 0.2), CGPoint(x: 0.7, y: 0.2)], sourceFPS: 25)
    }
    static func main() async throws {
        let worker = CaptureDouble()
        let clock = TestClock()
        let hub = FaceObservationHub(worker: worker, clock: { clock.now }, authorize: { true })
        let geometry = FaceObservationSource(hub: hub), command = FaceObservationSource(hub: hub)
        var geometryFrames = 0, commandFrames = 0, failures = 0
        let geometryToken = try await geometry.subscribe(deviceID: "camera", purpose: .geometry, validFor: 20,
            onObservation: { _ in geometryFrames += 1 }, onFailure: { _ in failures += 1 })
        let commandToken = try await command.subscribe(deviceID: "camera", purpose: .command, validFor: 2,
            onObservation: { _ in commandFrames += 1 }, onFailure: { _ in failures += 1 })
        check(worker.snapshot().starts == 1, "two consumers share one physical start")
        check(worker.snapshot().rates.last == 25, "command requests real 25 Hz capture")
        do {
            _ = try await command.subscribe(deviceID: "other", purpose: .command) { _ in }
            preconditionFailure("must reject a competing camera")
        } catch FaceObservationSourceError.cameraInUse { checks += 1 }
        let generation = worker.snapshot().generations[0]
        worker.emit(sample(10, sequence: 1, generation: generation)); await drain()
        clock.now = 10.04
        worker.emit(sample(10.04, sequence: 2, generation: generation)); await drain()
        check(commandFrames == 2 && geometryFrames == 1, "independent consumer rate limits do not duplicate frames")
        for bad in [sample(10.04, sequence: 3, generation: generation),
                    sample(10.01, sequence: 4, generation: generation),
                    sample(9, sequence: 5, generation: generation),
                    sample(11, sequence: 6, generation: generation),
                    sample(10.04, sequence: 7, generation: generation + 1),
                    sample(10.04, sequence: 8, generation: generation, camera: "other")] {
            worker.emit(bad)
        }
        await drain()
        check(commandFrames == 2, "duplicate, reversed, stale, future and foreign samples are rejected")
        clock.now = 12
        hub.expireConsumers()
        check(failures == 1 && worker.snapshot().stops == 0, "expiry fails only the expired consumer")
        check(worker.snapshot().rates.last == 8, "last fast consumer leaving restores geometry capture rate")
        command.unsubscribe(commandToken)
        check(worker.snapshot().stops == 0, "expired unsubscribe is idempotent")
        geometry.unsubscribe(geometryToken)
        check(worker.snapshot().stops == 1, "last consumer stops capture exactly once")
        geometry.stop(); command.stop()
        check(worker.snapshot().stops == 1, "repeated stops do not tear down twice")

        let fresh = try await geometry.subscribe(deviceID: "camera", purpose: .securityChallenge) { _ in geometryFrames += 1 }
        worker.emit(sample(12, sequence: 100, generation: generation)); worker.fail()
        await drain()
        check(worker.snapshot().stops == 1 && geometryFrames == 1, "late callbacks from previous capture cannot touch new session")
        worker.fail(session: 1); worker.fail(session: 1); await drain()
        check(worker.snapshot().stops == 2, "runtime failure cleans up exactly once")
        geometry.unsubscribe(fresh)
        check(worker.snapshot().stops == 2, "post-failure token cleanup is harmless")

        // Stop while authorization is pending: the eventual grant must never start capture.
        let pendingWorker = CaptureDouble()
        var grant: CheckedContinuation<Bool, Never>?
        let pendingHub = FaceObservationHub(worker: pendingWorker, authorize: {
            await withCheckedContinuation { grant = $0 }
        })
        let pending = FaceObservationSource(hub: pendingHub)
        let attempt = Task { try await pending.subscribe(deviceID: "camera", purpose: .command) { _ in } }
        while grant == nil { await Task.yield() }
        pending.stop()
        do { _ = try await attempt.value; preconditionFailure("cancelled lease cannot succeed") }
        catch { checks += 1 }
        grant?.resume(returning: true); await drain()
        check(pendingWorker.snapshot().starts == 0, "permission grant after stop never opens camera")

        // Cancelling one pending subscriber preserves a second subscriber's eventual grant.
        grant = nil
        let sharedWorker = CaptureDouble()
        let sharedHub = FaceObservationHub(worker: sharedWorker, authorize: {
            await withCheckedContinuation { grant = $0 }
        })
        let first = FaceObservationSource(hub: sharedHub), second = FaceObservationSource(hub: sharedHub)
        let cancelled = Task { try await first.subscribe(deviceID: "camera", purpose: .command) { _ in } }
        while grant == nil { await Task.yield() }
        let survivor = Task { try await second.subscribe(deviceID: "camera", purpose: .geometry) { _ in } }
        await drain(); cancelled.cancel(); await drain()
        do { _ = try await cancelled.value; preconditionFailure("task cancellation must win before permission returns") }
        catch { checks += 1 }
        grant?.resume(returning: true)
        let survivorToken = try await survivor.value
        check(sharedWorker.snapshot().starts == 1 && sharedWorker.snapshot().stops == 0,
              "one cancelled waiter does not cancel shared startup")
        second.unsubscribe(survivorToken)
        check(sharedWorker.snapshot().stops == 1, "remaining subscriber owns final stop")
        for lifetime in [0.0, -1, 86_401, Double.infinity, Double.nan] {
            do {
                _ = try await second.subscribe(deviceID: "camera", purpose: .command, validFor: lifetime) { _ in }
                preconditionFailure("invalid lifetime accepted")
            } catch FaceObservationSourceError.invalidLifetime { checks += 1 }
        }
        let timedWorker = CaptureDouble()
        let timedHub = FaceObservationHub(worker: timedWorker, authorize: { true })
        let timed = FaceObservationSource(hub: timedHub)
        var timedFailures = 0
        _ = try await timed.subscribe(deviceID: "camera", purpose: .command, validFor: 0.02,
                                       onObservation: { _ in }, onFailure: { _ in timedFailures += 1 })
        try await Task.sleep(for: .milliseconds(60))
        check(timedFailures == 1 && timedWorker.snapshot().stops == 1, "leases expire even when camera emits no frames")

        let deniedWorker = CaptureDouble()
        let denied = FaceObservationSource(hub: FaceObservationHub(worker: deniedWorker, authorize: { false }))
        var deniedFailures = 0
        do {
            _ = try await denied.subscribe(deviceID: "camera", purpose: .command,
                onObservation: { _ in }, onFailure: { _ in deniedFailures += 1 })
            preconditionFailure("denial accepted")
        } catch FaceObservationSourceError.authorizationDenied { checks += 1 }
        check(deniedFailures == 1 && deniedWorker.snapshot().starts == 0, "denial reports once without capture")

        let releasedWorker = CaptureDouble()
        let releasedHub = FaceObservationHub(worker: releasedWorker, authorize: { true })
        var released: FaceObservationSource? = FaceObservationSource(hub: releasedHub)
        _ = try await released!.subscribe(deviceID: "camera", purpose: .geometry) { _ in }
        released = nil; await drain()
        check(releasedWorker.snapshot().stops == 1, "owner deallocation releases its lease")
        print("FaceObservationSharingTests: \(checks) checks passed; no camera or model was run")
    }
}
