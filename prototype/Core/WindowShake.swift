// 晃一晃（Windows 的 Aero Shake）：拖着标题栏左右（或上下）来回晃，别的窗口收走；再晃一下放回来。
// 这里只认“是不是在晃”：最近 0.8 秒里沿同一个方向来回至少三次折返，每一段都走了 28 点以上，
// 而且来回的幅度加起来比整体挪了多远大得多（真在挪窗口时不会这样）。

import CoreGraphics
import Foundation

enum WindowShake {
    static let window: TimeInterval = 0.8
    static let minimumLeg: CGFloat = 28
    static let reversals = 3

    static func detected(in samples: [FlickSample]) -> Bool {
        guard let last = samples.last else { return false }
        let recent = samples.filter { last.time - $0.time <= window }
        guard recent.count >= 6 else { return false }
        return turns(recent.map(\.point.x)) >= reversals || turns(recent.map(\.point.y)) >= reversals
    }

    /// 一条轴上的折返次数：只算走满一段（≥ minimumLeg）之后的掉头。
    static func turns(_ values: [CGFloat]) -> Int {
        guard var anchor = values.first else { return 0 }
        var direction: CGFloat = 0
        var count = 0
        var travelled: CGFloat = 0
        for value in values.dropFirst() {
            let step = value - anchor
            if direction == 0 {
                if abs(step) >= minimumLeg { direction = step > 0 ? 1 : -1; anchor = value; travelled += abs(step) }
                continue
            }
            if step * direction > 0 {
                travelled += abs(step)
                anchor = value
            } else if abs(step) >= minimumLeg {
                count += 1
                direction = -direction
                travelled += abs(step)
                anchor = value
            }
        }
        // 来回的路程要远大于起点到终点的距离：一直往一边挪不算晃。
        let net = abs((values.last ?? 0) - (values.first ?? 0))
        return travelled > net * 2.5 ? count : 0
    }
}
