import CoreGraphics
import Foundation

/// 采集输出像素尺寸的唯一出口（PERF-02）。
///
/// 初始化、重启、resize、跨屏、画中画裁剪都从这里算尺寸，普通预览的小尺寸上限
/// 不会再被别的配置路径绕过。模式优先级固定：**画中画 > 小预览上限 > 跟随窗口**，
/// 用户正在看的大预览与画中画不会被缩略图的上限误伤。
enum CaptureOutputSizing {
    /// 普通窗口浏览的小预览：8fps、最大 640×400。
    static let previewMaxPixelSize = CGSize(width: 640, height: 400)
    /// 像素尺寸硬上限：挡住异常输入（远大于任何 Mac 显示器）。
    static let maximumPixelSize = 16384

    enum Mode: Equatable {
        /// 窗口浏览的小预览：8fps、有上限。
        case preview
        /// 置顶/侧拉的实时预览：跟随窗口像素，不套小预览上限。
        case pinnedPreview
        /// 画中画：由它自己的像素尺寸与裁剪决定，优先级最高。
        case pictureInPicture
    }

    /// 算出该模式下的输出像素尺寸。
    /// - `pointSize`／`scale`：窗口（或裁剪前）的点尺寸与浮点缩放；画中画模式忽略。
    /// - `pipPixels`：画中画要求的像素尺寸；仅画中画模式使用。
    static func pixelSize(
        mode: Mode, pointSize: CGSize, scale: CGFloat, pipPixels: CGSize = .zero
    ) -> CGSize {
        switch mode {
        case .pictureInPicture:
            return sanitized(pipPixels)
        case .preview:
            return capped(scaled(pointSize, scale), to: previewMaxPixelSize)
        case .pinnedPreview:
            return scaled(pointSize, scale)
        }
    }

    /// 点尺寸乘**浮点** scale 再向上取整；不要先把 scale 取整（那会把 1.5× 压成 1×）。
    static func scaled(_ pointSize: CGSize, _ scale: CGFloat) -> CGSize {
        let usableScale = (scale.isFinite && scale > 0) ? scale : 1
        let width = pointSize.width.isFinite ? pointSize.width : 0
        let height = pointSize.height.isFinite ? pointSize.height : 0
        return sanitized(
            CGSize(width: (width * usableScale).rounded(.up), height: (height * usableScale).rounded(.up)))
    }

    /// 等比缩到不超过 `limit`；原本就小于 `limit` 时不动，绝不放大。
    static func capped(_ size: CGSize, to limit: CGSize) -> CGSize {
        let base = sanitized(size)
        let limitWidth = (limit.width.isFinite && limit.width > 0) ? limit.width : base.width
        let limitHeight = (limit.height.isFinite && limit.height > 0) ? limit.height : base.height
        let ratio = min(limitWidth / base.width, limitHeight / base.height)
        guard ratio.isFinite, ratio < 1 else { return base }
        return sanitized(
            CGSize(width: (base.width * ratio).rounded(.up), height: (base.height * ratio).rounded(.up)))
    }

    /// 夹到 `[1, maximumPixelSize]`；非有限值按 1 处理，取整到最近整数像素。
    static func sanitized(_ size: CGSize) -> CGSize {
        func clamp(_ value: CGFloat) -> CGFloat {
            guard value.isFinite else { return 1 }
            return min(CGFloat(maximumPixelSize), max(1, value.rounded()))
        }
        return CGSize(width: clamp(size.width), height: clamp(size.height))
    }
}
