import Cocoa
import CoreImage

/// Builds a blurred backdrop image for the Launchpad overlay.
///
/// The helper is intentionally small and pure: it takes a source image plus a
/// blur radius and returns a new image of the same pixel dimensions. The source
/// image is never mutated, and an opaque source keeps opaque blurred edges so
/// the overlay can bleed past the screen bounds without showing dark fringes.
enum LaunchpadBackdrop {
    /// Single shared context so background callers can reuse the same pipeline
    /// (and its caches) instead of allocating one per call.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// 模糊图只解码到整屏像素的 1/4：模糊后本来就没有细节，图层放大时线性过滤，省约 15/16 的内存和计算。
    static let downscale = 4

    /// 解码用的最长边像素（整屏最长边像素除以 `downscale`，至少 1）。
    static func decodePixels(forScreenPixels pixels: CGFloat) -> Int {
        max(1, Int((pixels / CGFloat(downscale)).rounded(.down)))
    }

    /// 模糊半径：按已降采样图的最长边算，放大 `downscale` 倍后与整屏尺寸上 `0.018 × 最长边` 的半径一致。
    static func radius(forPixelWidth width: Int, height: Int) -> CGFloat {
        CGFloat(max(width, height)) * 0.018
    }

    /// 只保留 `keeping` 里还在用的键；其余淘汰。屏幕或壁纸变了，旧缓存不再占内存。
    static func retaining<Value>(_ cache: [String: Value], keeping keys: Set<String>) -> [String: Value] {
        cache.filter { keys.contains($0.key) }
    }

    /// Returns a Gaussian-blurred copy of `image` using `radius`.
    ///
    /// - Parameters:
    ///   - image: The source image. It is treated as read-only.
    ///   - radius: Blur radius in pixels. Values `<= 0` return the original image.
    /// - Returns: A new image with the same pixel width/height and clamped edges,
    ///   or the original image when the blur is a no-op.
    static func make(_ image: CGImage, radius: CGFloat) -> CGImage? {
        guard radius > 0 else { return image }

        let source = CIImage(cgImage: image)
        let extent = source.extent

        // Clamping to the extent keeps the border pixels from smearing into
        // transparency, so the blurred result stays opaque at the edges.
        let blurred = source
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)

        return context.createCGImage(blurred, from: extent)
    }
}
