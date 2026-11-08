#if canImport(Cocoa)
import Cocoa
#else
import Foundation
#endif

// Shared by browser/gesture requests. Mutations are MainActor-owned. Test hosts
// supply only the actual dictionaries below, not an AppKit implementation.
@MainActor extension AppDelegate {
    @discardableResult
    func registerFoldWaiter(id: CGWindowID, completion: @escaping (Bool) -> Void) -> UUID {
        let token = UUID()
        foldWaiters[id, default: [:]][token] = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.settleFoldWaiter(id: id, token: token, success: false)
        }
        return token
    }

    /// Only the request's captured tokens may be bound to its newly installed state.
    func bindFoldWaiters(id: CGWindowID, tokens: [UUID], transaction: UUID) {
        for token in tokens where foldWaiters[id]?[token] != nil {
            guard foldWaiterTransactions[token] == nil else { continue }
            foldWaiterTransactions[token] = transaction
        }
    }

    func settleFoldWaiter(id: CGWindowID, token: UUID, success: Bool) {
        settleFoldWaiters(id: id, tokens: [token], success: success)
    }

    /// No window-ID-only success path: a completion must name the exact transaction.
    func settleFoldWaiters(id: CGWindowID, transaction: UUID, success: Bool) {
        let tokens = (foldWaiters[id] ?? [:]).keys.filter { foldWaiterTransactions[$0] == transaction }
        settleFoldWaiters(id: id, tokens: tokens, success: success)
    }

    func cancelFoldWaiters(id: CGWindowID, tokens: [UUID]) {
        settleFoldWaiters(id: id, tokens: tokens, success: false)
    }

    func settleFoldWaiters(id: CGWindowID, tokens: [UUID], success: Bool) {
        guard var waiting = foldWaiters[id] else { return }
        var callbacks: [(callback: (Bool) -> Void, stamp: WS2FoldCallbackStamp?)] = []
        for token in tokens {
            guard let callback = waiting.removeValue(forKey: token) else { continue }
            let transaction = foldWaiterTransactions.removeValue(forKey: token)
            let stamp = success ? transaction.flatMap { foldWaiterDeliveryStamp(id: id, transaction: $0) } : nil
            callbacks.append((callback, stamp))
        }
        foldWaiters[id] = waiting.isEmpty ? nil : waiting
        // Drain the entire captured batch before any client callback. Delivery is
        // queued so a client cannot reenter a half-finished install or cleanup.
        guard !callbacks.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            for delivery in callbacks {
                let fresh: Bool
                if let stamp = delivery.stamp, let owner = self {
                    fresh = owner.foldCallbackIsCurrent(stamp)
                } else { fresh = false }
                delivery.callback(success && fresh)
            }
        }
    }
}
