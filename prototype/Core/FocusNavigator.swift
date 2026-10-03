// WindowShade 2 · 原创，屏幕点几何；不读 AppKit 或辅助功能。
import Foundation

/// 四向焦点算法。相同输入得到相同结果，不依赖字典遍历顺序。
struct FocusNavigator: Sendable {
    enum Direction: Sendable { case up, down, left, right }
    struct Rect: Equatable, Sendable {
        let x: Double; let y: Double; let width: Double; let height: Double
        var valid: Bool { [x,y,width,height,x+width,y+height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
        var cx: Double { x + width / 2 }; var cy: Double { y + height / 2 }
    }
    struct Item: Equatable, Sendable {
        let id: String; let group: String; let display: WS2.DisplayID; let rect: Rect
        let visible: Bool; let enabled: Bool
    }
    enum Result: Equatable, Sendable { case focused(String), none, invalidInput }
    private(set) var remembered: [String: String] = [:]
    static let maximumItems = 512
    mutating func move(from currentID: String?, direction: Direction, display: WS2.DisplayID,
                       items: [Item]) -> Result {
        guard items.count <= Self.maximumItems, items.allSatisfy({ !$0.id.isEmpty && !$0.group.isEmpty && $0.rect.valid }),
              Set(items.map(\.id)).count == items.count else { return .invalidInput }
        let eligible = items.filter { $0.visible && $0.enabled && $0.display == display }
        remembered = remembered.filter { pair in eligible.contains { $0.group == pair.key && $0.id == pair.value } }
        guard !eligible.isEmpty else { return .none }
        guard let currentID, let origin = eligible.first(where: { $0.id == currentID }) else {
            let first = eligible.sorted {
                if $0.rect.y != $1.rect.y { return $0.rect.y < $1.rect.y }
                if $0.rect.x != $1.rect.x { return $0.rect.x < $1.rect.x }
                return $0.id < $1.id
            }[0]
            remember(first)
            return .focused(first.id)
        }
        remember(origin)
        struct Candidate {
            let item: Item; let sameGroup: Bool; let remembered: Bool; let overlap: Double
            let distance: Double; let crossDistance: Double
        }
        let candidates: [Candidate] = eligible.compactMap { item in
            guard item.id != origin.id else { return nil }
            let dx = item.rect.cx - origin.rect.cx, dy = item.rect.cy - origin.rect.cy
            let forward: Double; let cross: Double; let overlap: Double
            switch direction {
            case .right: forward = dx; cross = abs(dy); overlap = max(0, min(item.rect.y + item.rect.height, origin.rect.y + origin.rect.height) - max(item.rect.y, origin.rect.y))
            case .left: forward = -dx; cross = abs(dy); overlap = max(0, min(item.rect.y + item.rect.height, origin.rect.y + origin.rect.height) - max(item.rect.y, origin.rect.y))
            case .down: forward = dy; cross = abs(dx); overlap = max(0, min(item.rect.x + item.rect.width, origin.rect.x + origin.rect.width) - max(item.rect.x, origin.rect.x))
            case .up: forward = -dy; cross = abs(dx); overlap = max(0, min(item.rect.x + item.rect.width, origin.rect.x + origin.rect.width) - max(item.rect.x, origin.rect.x))
            }
            guard forward > 0, forward.isFinite, cross.isFinite else { return nil }
            return Candidate(item: item, sameGroup: item.group == origin.group,
                remembered: remembered[item.group] == item.id, overlap: overlap,
                distance: hypot(forward, cross), crossDistance: cross)
        }
        let best = candidates.sorted {
            if $0.sameGroup != $1.sameGroup { return $0.sameGroup }
            if $0.remembered != $1.remembered { return $0.remembered }
            if $0.overlap != $1.overlap { return $0.overlap > $1.overlap }
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.crossDistance != $1.crossDistance { return $0.crossDistance < $1.crossDistance }
            return $0.item.id < $1.item.id
        }.first?.item ?? origin // 到边缘保持原焦点；不绕回另一边。
        remember(best)
        return .focused(best.id)
    }
    mutating func clear() { remembered.removeAll(keepingCapacity: true) }
    private mutating func remember(_ item: Item) {
        if remembered.count >= Self.maximumItems && remembered[item.group] == nil { remembered.removeAll(keepingCapacity: true) }
        remembered[item.group] = item.id
    }
}
