import CoreGraphics
import Foundation

/// page 金字塔（离焦用的基底 + mipmap）的重建依据（PERF-06）。
///
/// 键只含「源画面的像素版本 + 采样范围 + 源尺寸／像素格式／色彩空间 + page 尺寸」。
/// `progress`、标题比例、透明度、preset 都不在里面：它们只影响呈现，不影响 page 的内容，
/// 所以同一张源画面播 120 个变化帧，page 与 mipmap 也只建一次。
///
/// 反面做法（不许）：把 CVPixelBuffer 的指针或含 `progress` 的总 revision 当键——前者每次可能
/// 复用同一块内存，后者会让静态画面每帧都重建。
struct FoldPageKey: Equatable {
  /// 源像素的版本号。实时帧用「代际 + 帧号」，静图用换入序号；源一变就必须重建。
  let sourceVersion: UInt64
  let sourceWidth: Int
  let sourceHeight: Int
  /// 只用来分辨像素格式；存原始值，比较时不依赖枚举的字符串。
  let pixelFormatRawValue: UInt
  let colorSpace: String
  /// 采样范围（归一化 UV）。同一张源换一块区域也是新画面。
  let content: CGRect
  let pageWidth: Int
  let pageHeight: Int

  /// 实时捕获帧的源版本：同代际内按帧号走，跨代际也绝不撞号。
  static func liveSourceVersion(frameGeneration: UInt64, frameID: UInt64) -> UInt64 {
    (frameGeneration &* 1_000_003 &+ frameID) & 0x7FFF_FFFF_FFFF_FFFF
  }

  /// 静图（换入一张新的位图）的源版本。最高位是「静图」标记，和实时帧不会混。
  static func stillSourceVersion(swapCount: UInt64) -> UInt64 {
    0x8000_0000_0000_0000 | (swapCount & 0x7FFF_FFFF_FFFF_FFFF)
  }
}

/// 记录「上一份已经被 GPU 证实可用的 page 金字塔」。
///
/// 只有 `confirm` 过的键才作数：这一帧的 page 渲染和消费它的光学通道在同一个命令缓冲里，
/// 命令真的成功完成后才算建成；失败或会话作废时 `invalidate`，下一帧必定重建，绝不拿
/// 一张没画完的 page 去离焦。
struct FoldPagePyramidState {
  private(set) var key: FoldPageKey?

  func needsRebuild(for next: FoldPageKey) -> Bool { key != next }

  mutating func confirm(_ next: FoldPageKey) { key = next }

  mutating func invalidate() { key = nil }
}
