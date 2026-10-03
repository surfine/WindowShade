// WindowShade 2 审查包：原创边界骨架，非完整功能。
import Foundation
struct FocusNode {
    let id: String
    let x: Double
    let y: Double
    let enabled: Bool
}
enum FocusNavigator {
    // 坐标已归一为 x 向右、y 向下；这是最小中心距离策略。
    static func next(from current: FocusNode, nodes: [FocusNode],
                     dx: Double, dy: Double) -> String? {
        guard abs(dx) + abs(dy) == 1, dx * dy == 0 else { return nil }
        return nodes.filter {
            $0.enabled && $0.id != current.id && $0.x.isFinite && $0.y.isFinite &&
            ($0.x - current.x) * dx + ($0.y - current.y) * dy > 0
        }.sorted {
            let a = pow($0.x - current.x, 2) + pow($0.y - current.y, 2)
            let b = pow($1.x - current.x, 2) + pow($1.y - current.y, 2)
            return a == b ? $0.id < $1.id : a < b
        }.first?.id
    }
}
