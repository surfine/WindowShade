import CoreGraphics

/// One thumbnail request batch, confined to the controller's AX resolver queue.
/// This is not a time-based cache: each viewport request gets a fresh batch, and
/// actions do not use it. Every reused candidate still undergoes identity checks.
final class WindowBrowserTargetBatch<Element> {
    private var snapshots: [ApplicationInstanceKey: [CGWindowID: [Element]]] = [:]
    private var requestedKeys: [CGWindowID: WindowKey] = [:]

    func resolve<Result>(key: WindowKey,
                         load: () -> [(CGWindowID, Element)],
                         inspect: (Element) -> Result?) -> Result? {
        if let previous = requestedKeys[key.originalWindowID], previous != key {
            snapshots.removeValue(forKey: key.application)
        }
        requestedKeys[key.originalWindowID] = key
        if let snapshot = snapshots[key.application],
           let matches = snapshot[key.originalWindowID], matches.count == 1,
           let result = inspect(matches[0]) {
            return result
        }
        // Missing, ambiguous or stale candidates require a fresh enumeration.
        // A valid sibling can still reuse the refreshed application snapshot.
        var snapshot: [CGWindowID: [Element]] = [:]
        for (id, element) in load() { snapshot[id, default: []].append(element) }
        snapshots[key.application] = snapshot
        guard let matches = snapshot[key.originalWindowID], matches.count == 1 else { return nil }
        return inspect(matches[0])
    }
}
