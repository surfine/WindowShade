// 系统设置里打开了“减少动态效果”：弹簧不回弹、不接甩出去的速度，截图不飞、原处淡出目标处淡入
// （HIG：Motion，“让动效可以不要”：收紧弹簧、减少回弹；挪位置可以先淡出、到了再淡入）。

import Cocoa

enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

extension FlickGlidePath {
    /// 真窗口滑行的路径：平时接上甩出去的速度、落定时带一点回弹；减少动态效果时不回弹、不带速度。
    static func honoringMotion(from: CGRect, to: CGRect, velocity: CGVector) -> FlickGlidePath {
        Motion.reduced ? FlickGlidePath(from: from, to: to, velocity: .zero, position: .calm, size: .calm)
                       : FlickGlidePath(from: from, to: to, velocity: velocity)
    }
}
