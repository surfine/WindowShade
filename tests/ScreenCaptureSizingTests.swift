import CoreGraphics
import Foundation

/// PERF-02：预览/PiP 输出尺寸的唯一出口。纯函数，含边界与异常输入。
@main struct ScreenCaptureSizingTests {
    static func main() {
        precondition(CaptureOutputSizing.previewMaxPixelSize == CGSize(width: 640, height: 400))
        previewTests()
        pinnedTests()
        pictureInPictureTests()
        abnormalInputTests()
        print("PASS: capture output sizing (preview cap, pinned full size, PiP priority, fractional scale, abnormal input)")
    }

    static func previewTests() {
        // 1× 大窗：等比收进 640×400，不放大、不裁边。
        let one = CaptureOutputSizing.pixelSize(
            mode: .preview, pointSize: CGSize(width: 800, height: 600), scale: 1)
        precondition(one.width <= 640 && one.height <= 400, "Preview must stay within the cap")
        precondition(abs(one.width - 534) <= 1 && abs(one.height - 400) <= 1, "Preview keeps its aspect")

        // 2× 本来就小的窗：不该被缩小。
        let small = CaptureOutputSizing.pixelSize(
            mode: .preview, pointSize: CGSize(width: 200, height: 150), scale: 2)
        precondition(small == CGSize(width: 400, height: 300), "Below the cap the preview is untouched")

        // 竖长窗：高度顶到 400，宽度按比例，不会因为只比宽度而被放大。
        let tall = CaptureOutputSizing.pixelSize(
            mode: .preview, pointSize: CGSize(width: 400, height: 900), scale: 2)
        precondition(tall.width <= 640 && abs(tall.height - 400) <= 1, "Tall preview pins the height")

        // 0.5× 的缩放也不能把尺寸算大。
        let half = CaptureOutputSizing.pixelSize(
            mode: .preview, pointSize: CGSize(width: 800, height: 600), scale: 0.5)
        precondition(half == CGSize(width: 400, height: 300))
    }

    static func pinnedTests() {
        // 跟随窗口：2× 就是 2×，不套小预览上限。
        let full = CaptureOutputSizing.pixelSize(
            mode: .pinnedPreview, pointSize: CGSize(width: 800, height: 600), scale: 2)
        precondition(full == CGSize(width: 1600, height: 1200), "Pinned preview is never capped to 640×400")

        // 非整数 scale：先乘浮点再取整（1.5× 不能被压成 1×）。
        let fractional = CaptureOutputSizing.pixelSize(
            mode: .pinnedPreview, pointSize: CGSize(width: 100, height: 100), scale: 1.5)
        precondition(fractional == CGSize(width: 150, height: 150), "Float scale must survive")

        // 向上取整：半像素也算一个像素。
        let partial = CaptureOutputSizing.pixelSize(
            mode: .pinnedPreview, pointSize: CGSize(width: 10.2, height: 10.2), scale: 1)
        precondition(partial == CGSize(width: 11, height: 11))
    }

    static func pictureInPictureTests() {
        // 画中画用自己给的像素，优先级高于小预览上限。
        let pip = CaptureOutputSizing.pixelSize(
            mode: .pictureInPicture, pointSize: CGSize(width: 200, height: 200), scale: 2,
            pipPixels: CGSize(width: 320, height: 180))
        precondition(pip == CGSize(width: 320, height: 180))

        // 比 640×400 大的画中画不会被小预览上限误伤。
        let large = CaptureOutputSizing.pixelSize(
            mode: .pictureInPicture, pointSize: .zero, scale: 0,
            pipPixels: CGSize(width: 1200, height: 800))
        precondition(large == CGSize(width: 1200, height: 800), "PiP must win over the preview cap")

        // 窗口再大也不影响画中画。
        let ignoresWindow = CaptureOutputSizing.pixelSize(
            mode: .pictureInPicture, pointSize: CGSize(width: 5000, height: 5000), scale: 3,
            pipPixels: CGSize(width: 200, height: 100))
        precondition(ignoresWindow == CGSize(width: 200, height: 100))
    }

    static func abnormalInputTests() {
        // 非有限点尺寸按 1 处理，不产生 NaN/0。
        let nanPoint = CaptureOutputSizing.pixelSize(
            mode: .pinnedPreview, pointSize: CGSize(width: CGFloat.nan, height: 10), scale: 2)
        precondition(nanPoint == CGSize(width: 1, height: 20))

        // 非法 scale 退回 1。
        for scale: CGFloat in [0, -3, CGFloat.nan, CGFloat.infinity] {
            let size = CaptureOutputSizing.pixelSize(
                mode: .pinnedPreview, pointSize: CGSize(width: 100, height: 100), scale: scale)
            precondition(size == CGSize(width: 100, height: 100), "Bad scale must fall back to 1×")
        }

        // 负尺寸与 0 至少是 1×1。
        let zero = CaptureOutputSizing.pixelSize(
            mode: .preview, pointSize: CGSize(width: 0, height: -5), scale: 2)
        precondition(zero == CGSize(width: 1, height: 1))
        let emptyPip = CaptureOutputSizing.pixelSize(
            mode: .pictureInPicture, pointSize: .zero, scale: 0, pipPixels: .zero)
        precondition(emptyPip == CGSize(width: 1, height: 1))

        // 超大输入夹到硬上限，避免异常分配。
        let huge = CaptureOutputSizing.pixelSize(
            mode: .pinnedPreview, pointSize: CGSize(width: 1_000_000, height: 1_000_000), scale: 2)
        precondition(huge == CGSize(
            width: CGFloat(CaptureOutputSizing.maximumPixelSize),
            height: CGFloat(CaptureOutputSizing.maximumPixelSize)))

        // 收边永不放大。
        precondition(CaptureOutputSizing.capped(CGSize(width: 100, height: 50), to: CGSize(width: 640, height: 400))
            == CGSize(width: 100, height: 50))
    }
}
