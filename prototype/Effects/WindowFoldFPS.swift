// PERF-13：窗口折叠会话的采集帧率分档（纯逻辑，独立成文件便于无头测试）。

import Foundation
// 跟手/动画进行中 60；盖板追平定住（手指停住、或卷完等待 hide 确认）降到 15——
// 与桌面会话的静止档一致（DuoController 走 PowerPolicyRules.lidDesktopFPS，resting 恒 15）。
// EffectFrameSource.updateFPS 自带生成号守卫与串行 updateConfiguration，档位抖动不会打爆流配置；
// 降的是 WindowServer 采集与逐帧合成重绘的上限，Apple Silicon / Intel 同收益。

/// 窗口折叠会话的采集帧率分档。
enum WindowFoldFPS {
  /// 手指在动、动画在播、首帧还没出来。
  static let active = 60
  /// 盖板静止：跟手追平、动画 settled、hiding 阶段等确认。A/B 钩子
  /// `WINDOWSHADE_FOLD_IDLE_FPS`（默认 15；设 60 即关掉分档，供 soak 对照）。
  static let idle: Int = {
    if let raw = ProcessInfo.processInfo.environment["WINDOWSHADE_FOLD_IDLE_FPS"],
      let value = Int(raw), value > 0, value <= 60
    { return value }
    return 15
  }()
  /// 跟手判定阈值：显示值离手指目标不到 0.1% 就算追平（与 startFollowing 的收敛阈值一致量级）。
  static let stillDelta = 0.001

  /// tracking：`fingerDelta` 是「手指目标 − 显示值」的绝对值；追平即算停。
  static func wanted(fingerDelta: Double) -> Int {
    abs(fingerDelta) >= stillDelta ? active : idle
  }

  /// animate：`transitionSettled` 即盖板定住（之后只等呈现确认与 hide 验证）。
  static func wanted(transitionSettled: Bool) -> Int {
    transitionSettled ? idle : active
  }
}
