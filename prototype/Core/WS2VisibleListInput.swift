import Foundation

/// Adapts the existing stable-ID SelectionModel to physical press/release. No second list state machine.
@MainActor final class WS2VisibleListInput {
    private(set) var selection = WS2SelectionModel()
    private var prepared: (ticket: WS2SemanticInputRouter.Ticket, activation: WS2SelectionModel.Activation)?
    private(set) var context: WS2SemanticInputRouter.Context?
    var onArmed: ((String?) -> Void)?
    var onSelection: ((String?) -> Void)?
    var onActivate: ((String) -> Bool)?
    var onCancel: (() -> Void)?
    var ready = false

    func replace(_ items: [WS2SelectionModel.Item], selectedID: String?) throws {
        prepared = nil; onArmed?(nil)
        try selection.replace(items)
        if let selectedID { _ = selection.select(id: selectedID, expectedRevision: selection.revision) }
        onSelection?(selection.selectedID)
    }
    func bind(_ context: WS2SemanticInputRouter.Context?) {
        if self.context != context { cancelAll() }
        self.context = context
    }
    @discardableResult func select(_ id: String) -> Bool {
        cancelAll()
        let changed = selection.select(id: id, expectedRevision: selection.revision)
        if changed { onSelection?(selection.selectedID) }
        return changed
    }
    @discardableResult func prepare(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool {
        guard ready, ticket.context == context, ticket.context.domain != .review,
              ticket.context.targetRevision == selection.revision else { return false }
        guard ticket.intent == .openSelection else { return ticket.intent != .interruptTurn }
        guard prepared == nil, let activation = selection.reserveActivation(expectedRevision: selection.revision) else { return false }
        prepared = (ticket, activation)
        onArmed?(activation.itemID)
        return prepared?.ticket == ticket && ready && self.context == ticket.context
    }
    func cancel(context: WS2SemanticInputRouter.Context, presses: [UInt64]) {
        guard let p = prepared, p.ticket.context == context, presses.contains(p.ticket.press) else { return }
        cancelAll()
    }
    func cancelAll() {
        prepared = nil; onArmed?(nil)
        // select the same row to invalidate a pending activation without changing the snapshot revision.
        if let id = selection.selectedID { _ = selection.select(id: id, expectedRevision: selection.revision) }
    }
    @discardableResult func execute(_ ticket: WS2SemanticInputRouter.Ticket) -> Bool {
        guard ready, ticket.context == context, ticket.context.domain != .review,
              ticket.context.targetRevision == selection.revision else { cancelAll(); return false }
        switch ticket.intent {
        case .previous, .next:
            cancelAll()
            _ = selection.move(ticket.intent == .previous ? -1 : 1, expectedRevision: selection.revision)
            onSelection?(selection.selectedID)
            // Reaching an edge is a consumed navigation, not a reason to disable the attachment.
            return true
        case .openSelection:
            guard let p = prepared, p.ticket == ticket else { return false }
            prepared = nil; onArmed?(nil)
            guard let id = selection.consume(p.activation) else { return false }
            return onActivate?(id) ?? false
        case .cancel:
            cancelAll(); onCancel?(); return true
        case .interruptTurn:
            return false // This surface selects models; it cannot send, approve, or stop a turn.
        }
    }
    func revoke() { ready = false; context = nil; prepared = nil; selection.revoke(); onArmed?(nil) }
}
