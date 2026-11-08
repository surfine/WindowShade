import Foundation

/// Stable-ID selection for existing native lists. Does not synthesize keyboard events.
struct WS2SelectionModel: Sendable {
    struct Item: Equatable, Sendable { let id: String; let enabled: Bool }
    struct Activation: Equatable, Sendable { let revision: UInt64; let serial: UInt64; let itemID: String }
    enum Failure: Error { case invalidSnapshot, exhausted }
    private(set) var items: [Item] = []
    private(set) var selectedID: String?
    private(set) var revision: UInt64 = 0
    private var serial: UInt64 = 0
    private var pending: Activation?
    private var exhausted = false
    mutating func replace(_ next: [Item]) throws {
        pending = nil
        guard !exhausted, revision < .max else { exhausted = true; items = []; selectedID = nil; throw Failure.exhausted }
        revision += 1
        var seen = Set<String>()
        guard next.count <= 512, next.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 512 && seen.insert($0.id).inserted }) else {
            items = []; selectedID = nil; throw Failure.invalidSnapshot
        }
        items = next
        if !items.contains(where: { $0.id == selectedID && $0.enabled }) { selectedID = items.first(where: \.enabled)?.id }
    }
    @discardableResult mutating func move(_ direction: Int, expectedRevision: UInt64) -> Bool {
        guard !exhausted, expectedRevision == revision, direction == -1 || direction == 1 else { return false }
        let enabled = items.filter(\.enabled)
        guard !enabled.isEmpty else { return false }
        let old = enabled.firstIndex { $0.id == selectedID } ?? 0
        let index = min(enabled.count - 1, max(0, old + direction))
        guard index != old else { return false }
        pending = nil; selectedID = enabled[index].id; return true
    }
    @discardableResult mutating func select(id: String, expectedRevision: UInt64) -> Bool {
        guard !exhausted, expectedRevision == revision, items.contains(where: { $0.id == id && $0.enabled }) else { return false }
        pending = nil; selectedID = id; return true
    }
    mutating func reserveActivation(expectedRevision: UInt64) -> Activation? {
        guard !exhausted, expectedRevision == revision, pending == nil, serial < .max,
              let id = selectedID, items.contains(where: { $0.id == id && $0.enabled }) else { return nil }
        serial += 1
        let value = Activation(revision: revision, serial: serial, itemID: id); pending = value; return value
    }
    mutating func consume(_ value: Activation) -> String? {
        guard !exhausted, pending == value, value.revision == revision, value.itemID == selectedID,
              items.contains(where: { $0.id == value.itemID && $0.enabled }) else { return nil }
        pending = nil; return value.itemID
    }
    mutating func revoke() { pending = nil; items = []; selectedID = nil; if revision < .max { revision += 1 } else { exhausted = true } }
}
