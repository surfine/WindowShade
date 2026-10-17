import CoreGraphics
import Foundation

/// 台前调度的左（或右）侧条（规格 R19）。台前调度开着时，对窗口下 AX 最小化不会进程序坞：
/// WindowManager 把它缩成侧条里的一张小卡片——窗口服务器报的外框变成卡片那么大、贴着屏幕边，
/// AXMinimized 仍是 false，AX 位置与尺寸仍是原来的（VM 实测 2026-10-17：AX 320x232 @ (900,448)，
/// 外框 82x100 @ (16,427)）。这里只做几何判断，不读系统状态；台前调度开没开由调用方先判。
enum StageStrip {
    /// 外框每一边都不超过 AX 尺寸的这个比例，才算“被缩成了卡片”。用户自己把窗口拖小，
    /// AX 尺寸会跟着变小，比例不会掉到这里。
    static let maximumThumbnailScale: CGFloat = 0.7
    /// 卡片要贴着所在屏幕的左缘或右缘：离边不超过屏宽的这个比例。
    static let edgeBandFraction: CGFloat = 0.2

    /// 窗口服务器外框（左上原点的全局坐标）相对 AX 尺寸缩成了侧条卡片吗。
    /// displays 用同一套坐标（CGDisplayBounds）。读数不全或不合法一律 false：判不出就按原来的判据走。
    static func looksParked(windowServerBounds cg: CGRect, axSize: CGSize, displays: [CGRect]) -> Bool {
        guard [cg.minX, cg.minY, cg.width, cg.height, axSize.width, axSize.height].allSatisfy(\.isFinite),
              cg.width > 0, cg.height > 0, axSize.width > 0, axSize.height > 0 else { return false }
        guard cg.width <= axSize.width * maximumThumbnailScale,
              cg.height <= axSize.height * maximumThumbnailScale else { return false }
        let center = CGPoint(x: cg.midX, y: cg.midY)
        guard let display = displays.first(where: { $0.contains(center) }), display.width > 0 else { return false }
        let band = display.width * edgeBandFraction
        return cg.minX - display.minX <= band || display.maxX - cg.maxX <= band
    }

    /// 展开后把窗口从侧条请回来：每一档检查之后做什么。
    enum RestoreStep: Equatable { case done, nudge(escalated: Bool), giveUp }

    /// 检查时刻（展开后秒数）。最后一档要早于展开验证的 1.5 s 上限（RestoreVerifier），
    /// 请回来了验证还来得及看到；请不回来就由验证照实报“没恢复”、保留恢复记录。
    static let restoreCheckDelays: [TimeInterval] = [0.15, 0.45, 0.85, 1.2]

    /// 已不在侧条 → 结束；还在且不是最后一档 → 再请一次（第一档只 raise/聚焦，之后升级为重新激活）；
    /// 最后一档仍在 → 放弃（只记日志，不再动窗口）。
    static func restoreStep(parked: Bool, attempt: Int, attempts: Int = restoreCheckDelays.count) -> RestoreStep {
        guard parked else { return .done }
        guard attempt < attempts - 1 else { return .giveUp }
        return .nudge(escalated: attempt >= 1)
    }
}
