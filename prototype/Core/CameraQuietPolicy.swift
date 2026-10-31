import Foundation

/// 摄像头正被任何 App 使用时（视频通话），刘海不自己长大：不弹提醒、不自己展开一排，只留点和紧凑。
/// 你自己点一下、长按，照常打开（Aaron 2026-10-31 第 40 条）。
enum CameraQuietPolicy {
    /// 这一次“自己长大”能不能出来。`userInitiated`：是你点、长按这类动作引起的。
    static func allowsAutoGrowth(cameraInUse: Bool, userInitiated: Bool) -> Bool {
        userInitiated || !cameraInUse
    }

    /// 摄像头状态读一次管多久（秒）：提醒一阵一阵来时不重复读。
    static let cacheSeconds: Double = 1.0
}
