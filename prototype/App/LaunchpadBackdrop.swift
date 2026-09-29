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
