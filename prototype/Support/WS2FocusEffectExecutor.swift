import Foundation

@MainActor protocol WS2FocusMutationPort: AnyObject {
    // Perform at most one mutation. Recheck mayCommit plus live identity/revision at the final AX/WS boundary.
    // Awaiting the initial animation request is insufficient; report only its actual completion/reconciliation.
    func perform(_ operation: WS2FocusEffectPlan.Operation,
                 mayCommit: @escaping @MainActor () -> Bool) async -> WS2FocusEffectPlan.Outcome
}

@MainActor final class WS2FocusEffectExecutor {
    private(set) var plan = WS2FocusEffectPlan()
    private let port: any WS2FocusMutationPort
    private var worker: Task<Void, Never>?
    var onBlocked: (() -> Void)?
    init(port: any WS2FocusMutationPort) { self.port = port }
    func transition(run: WS2.Token?, windows: [WS2FocusEffectPlan.Window]) throws {
        try plan.transition(run: run, windows: windows); pump()
    }
    func suspend() { plan.setSuspended(true) }
    func resumeAfterVerifiedUnlock() { plan.setSuspended(false); pump() }
    func manualChange(_ identity: WS2FocusEffectPlan.Identity) { plan.manualChange(identity); pump() }
    // Do not cancel an in-flight port call and forget it. Its late completion may require compensation.
    func end() throws { try transition(run: nil, windows: []) }
    private func pump() {
        guard worker == nil, !plan.blocked else { return }
        worker = Task { [self] in
            while let operation = plan.next() {
                let outcome = await port.perform(operation, mayCommit: { [weak self] in self?.plan.mayCommit(operation) == true })
                do { try plan.complete(operation, outcome) } catch { onBlocked?(); break }
                if plan.blocked { onBlocked?(); break }
            }
            worker = nil
        }
    }
}
