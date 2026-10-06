import CoreGraphics
import Foundation

/// PERF-06：page 金字塔（离焦基底 + mipmap）只在源内容或采样范围真的变了时才重建。
/// 硬条件：同一张静态源播 120 个变化帧只建一次；源／采样范围／色彩空间／尺寸／像素格式
/// 任一变更各重建一次；只有 GPU 证实成功的那一份才作数。
@main struct FoldPageKeyTests {
    static func main() {
        staticSourceRebuildsOnceTests()
        sourceChangeTests()
        samplingChangeTests()
        formatChangeTests()
        pyramidStateTests()
        sourceVersionTests()
        print(
            "PASS: fold page pyramid rebuilds only on source, sampling, format or size change")
    }

    /// 静态源 + 变化的呈现参数：整段动画只建一次金字塔。
    static func staticSourceRebuildsOnceTests() {
        var state = FoldPagePyramidState()
        var rebuilds = 0
        // 120 个变化帧：progress / 标题比例 / 透明度每帧都不同，但都不进键。
        for _ in 0..<120 {
            let key = FoldPageKey(
                sourceVersion: FoldPageKey.stillSourceVersion(swapCount: 7),
                sourceWidth: 4800, sourceHeight: 2600, pixelFormatRawValue: 80,
                colorSpace: "displayP3", content: CGRect(x: 0, y: 0, width: 1, height: 1),
                pageWidth: 4800, pageHeight: 2600)
            if state.needsRebuild(for: key) {
                rebuilds += 1
                state.confirm(key)
            }
        }
        precondition(rebuilds == 1, "静态源整段动画只建一次 page 金字塔，实际 \(rebuilds) 次")
    }

    /// 源像素换了：必须重建。
    static func sourceChangeTests() {
        var state = FoldPagePyramidState()
        let first = FoldPageKey(
            sourceVersion: FoldPageKey.liveSourceVersion(frameGeneration: 3, frameID: 100),
            sourceWidth: 1600, sourceHeight: 1000, pixelFormatRawValue: 80,
            colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 1600, pageHeight: 1000)
        let nextFrame = FoldPageKey(
            sourceVersion: FoldPageKey.liveSourceVersion(frameGeneration: 3, frameID: 101),
            sourceWidth: 1600, sourceHeight: 1000, pixelFormatRawValue: 80,
            colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 1600, pageHeight: 1000)
        let newSession = FoldPageKey(
            sourceVersion: FoldPageKey.liveSourceVersion(frameGeneration: 4, frameID: 100),
            sourceWidth: 1600, sourceHeight: 1000, pixelFormatRawValue: 80,
            colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 1600, pageHeight: 1000)
        let newStill = FoldPageKey(
            sourceVersion: FoldPageKey.stillSourceVersion(swapCount: 2),
            sourceWidth: 1600, sourceHeight: 1000, pixelFormatRawValue: 80,
            colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 1600, pageHeight: 1000)

        state.confirm(first)
        precondition(state.needsRebuild(for: nextFrame), "新的一帧画面必须重建")
        precondition(state.needsRebuild(for: newSession), "新会话（新代际）必须重建")
        precondition(state.needsRebuild(for: newStill), "换成静图必须重建")
        precondition(!state.needsRebuild(for: first), "同一个源版本不重建")
    }

    /// 采样范围（UV）与 page 尺寸：换一块区域或换一种缩放都必须重建。
    static func samplingChangeTests() {
        var state = FoldPagePyramidState()
        let base = FoldPageKey(
            sourceVersion: 42, sourceWidth: 3000, sourceHeight: 2000, pixelFormatRawValue: 80,
            colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 3000, pageHeight: 2000)
        let cropped = FoldPageKey(
            sourceVersion: 42, sourceWidth: 3000, sourceHeight: 2000, pixelFormatRawValue: 80,
            colorSpace: "sRGB", content: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            pageWidth: 2400, pageHeight: 1600)
        state.confirm(base)
        precondition(state.needsRebuild(for: cropped), "采样范围变了必须重建")
        precondition(!state.needsRebuild(for: base))
    }

    /// 色彩空间、像素格式、源尺寸：都算源身份的一部分。
    static func formatChangeTests() {
        var state = FoldPagePyramidState()
        let base = FoldPageKey(
            sourceVersion: 9, sourceWidth: 1200, sourceHeight: 800, pixelFormatRawValue: 80,
            colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 1200, pageHeight: 800)
        state.confirm(base)

        let p3 = FoldPageKey(
            sourceVersion: 9, sourceWidth: 1200, sourceHeight: 800, pixelFormatRawValue: 80,
            colorSpace: "displayP3", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 1200, pageHeight: 800)
        precondition(state.needsRebuild(for: p3), "色彩空间变了必须重建")

        let bgra = FoldPageKey(
            sourceVersion: 9, sourceWidth: 1200, sourceHeight: 800, pixelFormatRawValue: 80,
            colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 1200, pageHeight: 800)
        let otherFormat = FoldPageKey(
            sourceVersion: 9, sourceWidth: 1200, sourceHeight: 800, pixelFormatRawValue: 81,
            colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 1200, pageHeight: 800)
        precondition(bgra == base)
        precondition(state.needsRebuild(for: otherFormat), "像素格式变了必须重建")

        let resized = FoldPageKey(
            sourceVersion: 9, sourceWidth: 2400, sourceHeight: 1600, pixelFormatRawValue: 80,
            colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 2400, pageHeight: 1600)
        precondition(state.needsRebuild(for: resized), "源尺寸变了必须重建")
    }

    /// 只有 GPU 证实成功的那一份才算建成；失败作废后下一帧一定重建。
    static func pyramidStateTests() {
        var state = FoldPagePyramidState()
        let key = FoldPageKey(
            sourceVersion: 1, sourceWidth: 100, sourceHeight: 100, pixelFormatRawValue: 80,
            colorSpace: "sRGB", content: CGRect(x: 0, y: 0, width: 1, height: 1),
            pageWidth: 100, pageHeight: 100)
        precondition(state.needsRebuild(for: key), "一开始没有可用金字塔")
        // 编了这一帧但 GPU 还没完成：键不能算数。
        precondition(state.needsRebuild(for: key), "未证实的键不作数")
        state.confirm(key)
        precondition(!state.needsRebuild(for: key), "证实后不再重建")
        state.invalidate()
        precondition(state.needsRebuild(for: key), "作废后必须重建")
    }

    /// 实时帧与静图的源版本永远不会撞号。
    static func sourceVersionTests() {
        var live: Set<UInt64> = []
        for generation in UInt64(1)...40 {
            for id in UInt64(0)..<3000 {
                let version = FoldPageKey.liveSourceVersion(frameGeneration: generation, frameID: id)
                precondition(version < 0x8000_0000_0000_0000, "实时帧版本不占最高位")
                precondition(live.insert(version).inserted, "代际 + 帧号组合不重复")
            }
        }
        for swap in UInt64(0)..<1000 {
            let version = FoldPageKey.stillSourceVersion(swapCount: swap)
            precondition(version >= 0x8000_0000_0000_0000, "静图版本占最高位")
            precondition(!live.contains(version), "静图版本不与实时帧撞号")
        }
        precondition(
            FoldPageKey.liveSourceVersion(frameGeneration: 0, frameID: 7) == 7,
            "同代际内版本按帧号单调走")
        precondition(
            FoldPageKey.liveSourceVersion(frameGeneration: 1, frameID: 0) > 1_000_000,
            "换代际要跳开，不能和同代际的帧号重叠")
    }
}
