// 分屏里一扇窗的最小模型：编号 + 现在的位置（AX 坐标：左上角为原点、y 向下）。
// 认对、拖分屏把手、松手落点的逻辑都在 SeamLayout.swift；这里只留它和 SplitScan 共用的这一个类型。

import CoreGraphics

/// 一扇窗：编号 + 现在的位置。
struct SplitWindow: Equatable {
    let id: UInt32
    let frame: CGRect
}
