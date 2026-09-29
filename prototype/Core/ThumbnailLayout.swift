// 缩略图的几何（“收起后的样子”选“缩略图”）：多大、放在哪、按 ⌃⌘0 怎么排成一排。
// 纯计算，不碰 AppKit；坐标一律 Cocoa（y 向上），数值取自小样做法 A（docs/direction.md“缩略图”）。
//
// 缩略图的左上角对着窗口原来的左上角；App 图标压在右下角、探出去一点。覆盖层窗口的外框 =
// 缩略图 + 右边和下边探出去的那一截，所以外框的左上角仍是窗口的左上角：展开、整理、恢复日志
// 都照卷帘条的老规矩按外框左上角算。

import CoreGraphics

enum ThumbnailLayout {
    /// 缩略图放进这么大的方框里（点）：横窗宽 180，竖窗高 180，长宽比跟窗口一样。
    static let box: CGFloat = 180
    /// 短边至少这么长，太扁的窗口也点得中；这时长边最多到 2 × box，多出来的画面裁掉。
    static let minShortSide: CGFloat = 28
    /// 圆角：和窗口浏览里的卡片同一档（SystemCornerRadius.item）。
    static let cornerRadius: CGFloat = 8
    /// 右下角的 App 图标。
    static let iconSize: CGFloat = 26
    /// 图标往右、往下探出缩略图的长度。
    static let iconOverhang: CGFloat = 7
    /// 整理成一排：离可用区域左边 16、下边 12，彼此隔 10。
    static let tidyLeading: CGFloat = 16
    static let tidyBottom: CGFloat = 12
    static let tidyGap: CGFloat = 10

    /// 窗口多大，缩略图就多大（点，取整）。比方框还小的窗口不放大。
    static func size(for window: CGSize) -> CGSize {
        guard window.width >= 1, window.height >= 1 else {
            return CGSize(width: box, height: (box * 0.625).rounded())
        }
        let scale = min(box / window.width, box / window.height, 1)
        var width = window.width * scale
        var height = window.height * scale
        let short = min(width, height)
        let wanted = min(minShortSide, min(window.width, window.height))
        if short < wanted {
            let up = wanted / short
            width = min(width * up, box * 2)
            height = min(height * up, box * 2)
        }
        return CGSize(width: max(1, width.rounded()), height: max(1, height.rounded()))
    }

    /// 缩略图本身：左上角贴着 anchor（窗口或原位的左上角，Cocoa 坐标）。
    static func thumbnail(topLeft anchor: CGPoint, window: CGSize) -> CGRect {
        let size = size(for: window)
        return CGRect(x: anchor.x, y: anchor.y - size.height, width: size.width, height: size.height)
    }

    /// 覆盖层窗口的外框：缩略图 + 右、下两边给图标探出去的那一截。
    static func overlayFrame(thumbnail: CGRect) -> CGRect {
        CGRect(x: thumbnail.minX, y: thumbnail.minY - iconOverhang,
               width: thumbnail.width + iconOverhang, height: thumbnail.height + iconOverhang)
    }

    /// 反过来：从覆盖层外框取回缩略图。
    static func thumbnail(inOverlayFrame frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.minY + iconOverhang,
               width: max(1, frame.width - iconOverhang), height: max(1, frame.height - iconOverhang))
    }

    /// 缩略图在覆盖层视图里的位置（视图坐标，原点在左下）。
    static func thumbnailInView(overlaySize: CGSize) -> CGRect {
        CGRect(x: 0, y: iconOverhang, width: max(1, overlaySize.width - iconOverhang),
               height: max(1, overlaySize.height - iconOverhang))
    }

    /// 图标在覆盖层视图里的位置：贴着右下角。
    static func iconInView(overlaySize: CGSize) -> CGRect {
        CGRect(x: overlaySize.width - iconSize, y: 0, width: iconSize, height: iconSize)
    }

    /// 按 ⌃⌘0 整理：从可用区域左下角起，按给的顺序从左往右排成一排；一排放不下，往上再起一排。
    /// 返回每张缩略图（不含图标探出的那一截）排好后的位置。
    static func tidy(_ sizes: [CGSize], in visible: CGRect) -> [CGRect] {
        let reach = iconOverhang
        let left = visible.minX + tidyLeading
        let right = visible.maxX - tidyLeading
        var x = left
        var rowBottom = visible.minY + tidyBottom + reach
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        for size in sizes {
            if x > left, x + size.width + reach > right {
                rowBottom += rowHeight + tidyGap + reach
                x = left
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: rowBottom, width: size.width, height: size.height))
            x += size.width + reach + tidyGap
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
