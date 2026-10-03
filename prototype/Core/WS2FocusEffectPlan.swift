// Deterministic, serialized phase transitions. The port must return real mutation receipts.
import Foundation

struct WS2FocusEffectPlan: Sendable {
    typealias Identity = WS2FocusWindowOwnership.Identity
    typealias Receipt = WS2FocusWindowOwnership.Receipt
    struct Window: Equatable, Sendable { let identity: Identity; let revision: UInt64 }
    enum Kind: Equatable, Sendable { case tuck(Window, WS2.Token, UInt64), restore(Receipt) }
    struct Operation: Equatable, Sendable { let id: UUID; let kind: Kind }
    enum Outcome: Sendable { case completed(revision: UInt64), unchanged, userChanged, unknown }
    enum Failure: Error { case invalid, capacity, overflow, unexpectedCompletion }
    private(set) var phase: UInt64 = 0
    private(set) var blocked = false
    private(set) var suspended = false
    private(set) var pending: Operation?
    private var run: WS2.Token?
    private var desired: [Window] = []
    private var receipts: [Receipt] = []
    private var attempted = Set<Identity>()
    private var relinquished = Set<Identity>()
    var receiptCount: Int { receipts.count }
    var isSettled: Bool { pending == nil && receipts.isEmpty && desired.isEmpty }
    // Call once per actual timer phase transition, not per tick. Every new phase restores the old phase first.
    mutating func transition(run: WS2.Token?, windows: [Window]) throws {
        guard windows.count <= 512 else { throw Failure.capacity }
        guard run != nil || windows.isEmpty, Set(windows.map(\.identity)).count == windows.count else { throw Failure.invalid }
        guard phase < UInt64.max else { blocked = true; throw Failure.overflow }
        phase += 1; self.run = run; desired = windows; attempted.removeAll()
        // Do not clear unknown completion faults through a subsequent transition.
    }
    mutating func setSuspended(_ value: Bool) { suspended = value }
    mutating func manualChange(_ identity: Identity) {
        receipts.removeAll { $0.identity == identity }
        desired.removeAll { $0.identity == identity }; attempted.insert(identity)
        // Remember manual interference only for an in-flight action; do not accumulate window IDs forever.
        if let pending, Self.identity(pending.kind) == identity { relinquished.insert(identity) }
    }
    private static func identity(_ kind: Kind) -> Identity {
        switch kind { case .tuck(let w, _, _): return w.identity; case .restore(let r): return r.identity }
    }
    mutating func next() -> Operation? {
        guard !blocked, !suspended, pending == nil else { return nil }
        if let receipt = receipts.first(where: { $0.effectGeneration != phase }) {
            let operation = Operation(id: UUID(), kind: .restore(receipt)); pending = operation; return operation
        }
        guard let run, let window = desired.first(where: { !attempted.contains($0.identity) }) else { return nil }
        attempted.insert(window.identity)
        let operation = Operation(id: UUID(), kind: .tuck(window, run, phase)); pending = operation; return operation
    }
    // This check must run immediately before the port's actual mutation, not just before snapshot capture.
    func mayCommit(_ operation: Operation) -> Bool {
        guard pending == operation, !blocked, !suspended,
              !relinquished.contains(Self.identity(operation.kind)) else { return false }
        switch operation.kind {
        case .tuck(let window, let token, let generation):
            return generation == phase && token == run && desired.contains(window)
        case .restore(let receipt): return receipts.contains(receipt)
        }
    }
    mutating func complete(_ operation: Operation, _ outcome: Outcome) throws {
        guard pending == operation else { throw Failure.unexpectedCompletion }
        pending = nil
        let identity = Self.identity(operation.kind)
        if relinquished.remove(identity) != nil { return }
        switch outcome {
        case .unknown: blocked = true
        case .userChanged: manualChange(identity)
        case .unchanged:
            // A cancelled pre-mutation tuck is safe; an unexplained failed restore is not.
            if case .restore = operation.kind { blocked = true }
        case .completed(let revision):
            switch operation.kind {
            case .tuck(let window, let token, let generation):
                guard revision > window.revision, receipts.count < 512,
                      !receipts.contains(where: { $0.identity == identity }) else { blocked = true; return }
                // Even a late completed tuck creates a receipt; the next operation compensates before new tucks.
                receipts.append(Receipt(identity: identity, run: token, effectGeneration: generation,
                                        beforeRevision: window.revision, afterRevision: revision))
            case .restore(let receipt):
                guard revision > receipt.afterRevision else { blocked = true; return }
                receipts.removeAll { $0 == receipt }
            }
        }
    }
}
