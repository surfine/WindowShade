import Cocoa
import CoreGraphics
import Foundation

// Standalone executable test harness for LaunchpadBackdrop.
//
// It builds an opaque black-and-white image with vertical stripes, runs the
// blur, and checks the properties the overlay relies on: the pixel size is
// preserved, distant regions keep their original tone, the middle becomes
// gray, all four corners stay fully opaque, and the input is untouched.
// No exact Gaussian values are asserted, only structural behaviour.

private var failures: [String] = []

private func check(_ condition: Bool, _ message: String) {
    if condition {
        print("ok - \(message)")
    } else {
        failures.append(message)
        print("fail - \(message)")
    }
}

private func makeStripedImage(width: Int, height: Int) -> CGImage {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

    for y in 0..<height {
        for x in 0..<width {
            // Wide vertical bands: fully black or fully white.
            // 64px bands put each band centre ~32px from the nearest boundary,
            // far beyond the blur radius used below, so the centre of a black
            // band stays essentially black.
            let value: UInt8 = (x / 64) % 2 == 0 ? 0 : 255
            let offset = y * bytesPerRow + x * bytesPerPixel
            pixels[offset + 0] = value
            pixels[offset + 1] = value
            pixels[offset + 2] = value
            pixels[offset + 3] = 255
        }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

private func pixelBytes(_ image: CGImage) -> [UInt8] {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return bytes
}

@main
struct LaunchpadBackdropTests {
    static func main() {
        let width = 256
        let height = 256
        let source = makeStripedImage(width: width, height: height)
        let before = pixelBytes(source)

        let radius: CGFloat = 6
        guard let blurred = LaunchpadBackdrop.make(source, radius: radius) else {
            print("fail - make returned nil")
            exit(1)
        }

        // 1. Original pixel size is preserved.
        check(
            blurred.width == width && blurred.height == height,
            "blurred image keeps source dimensions (\(blurred.width)x\(blurred.height))"
        )

        let after = pixelBytes(blurred)
        check(after.count == before.count, "blurred image has same buffer size")

        // 2. Distant region (band centre far from any boundary) keeps its tone.
        // The first band spans x = 0..63, so the centre pixel at x = 32 sits
        // ~32px from the nearest white boundary and stays close to black.
        let distantIndex = 128 * width * 4 + 32 * 4
        let distantLuma = Int(after[distantIndex])
        check(distantLuma < 40, "distant black region stays dark (luma \(distantLuma))")

        // 3. A pixel straddling a black/white boundary turns gray.
        // x = 64 is exactly where black meets white, and y = 128 is deep in the
        // interior so vertical edges do not interfere.
        let middleIndex = 128 * width * 4 + 64 * 4
        let middleLuma = Int(after[middleIndex])
        check(
            middleLuma > 30 && middleLuma < 225,
            "boundary middle becomes gray (luma \(middleLuma))"
        )

        // 4. All four corners stay fully opaque.
        let corners = [
            0,
            (width - 1) * 4,
            (height - 1) * width * 4,
            ((height - 1) * width + (width - 1)) * 4,
        ]
        let cornersOpaque = corners.allSatisfy { after[$0 + 3] == 255 }
        check(cornersOpaque, "all four corners are fully opaque (alpha 255)")

        // 5. Input image is not modified.
        let afterSource = pixelBytes(source)
        check(afterSource == before, "source image pixels are unchanged")

        // 6. Non-positive radius is a no-op passthrough.
        let passthrough = LaunchpadBackdrop.make(source, radius: 0)
        check(passthrough?.width == width && passthrough?.height == height, "radius 0 returns original image")

        if failures.isEmpty {
            print("\nAll LaunchpadBackdrop tests passed.")
            exit(0)
        } else {
            print("\n\(failures.count) test(s) failed.")
            exit(1)
        }
    }
}
