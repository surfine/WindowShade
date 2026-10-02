// 刘海里的格子缩略图：一张画面能新鲜多久、一次抓几张、画面缩到多大、什么样的画面能收（docs/direction.md「回到窗口」）。
//
// 纯逻辑：只判断新鲜度、尺寸和画面质量，不碰私有接口、不碰界面。

import CoreGraphics
import Foundation

enum NotchThumbnailPolicy {
    /// 一张格子里的画面放这么久就算不新鲜了（秒）。
    static let ttl: Double = 10
    /// 同时最多抓两张。
    static let maxInFlight = 2
    /// 格子里的画面缩到最长边这么多像素。
    static let tileMaxPixel = 320

    /// 这张画面还算新鲜吗。
    static func isFresh(capturedAt: Double, now: Double) -> Bool {
        now - capturedAt < ttl
    }

    /// expectedPoints 是 .zero 时不挑。否则要求宽高比和期望的差不到一成，并且像素宽度至少是期望点宽的 0.9 倍
    /// （整数倍缩放的截图至少得有一倍大小）。正在最小化 / 还原动画里的画面会被挡掉。
    static func acceptsPicture(pixelWidth: Int, pixelHeight: Int, expectedPoints: CGSize) -> Bool {
        guard expectedPoints.width > 0, expectedPoints.height > 0 else { return true }
        guard pixelWidth > 0, pixelHeight > 0 else { return false }
        let expected = expectedPoints.width / expectedPoints.height
        let actual = CGFloat(pixelWidth) / CGFloat(pixelHeight)
        guard abs(actual - expected) / expected <= 0.1 else { return false }
        return CGFloat(pixelWidth) >= 0.9 * expectedPoints.width
    }

    enum StillQuality {
        case thumbnail
        case full
    }

    /// 窗口点大小换成 4 字节一像素的位图超过 16M 就只留缩略图，否则整张留。
    static func stillQuality(windowPoints: CGSize) -> StillQuality {
        windowPoints.width * windowPoints.height * 4 > 16_000_000 ? .thumbnail : .full
    }
}
