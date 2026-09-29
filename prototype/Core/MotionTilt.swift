import Foundation

/// 随设备倾斜的低通与基线。纯逻辑：传感器队列上逐份喂读数，得到给画面用的偏移。
///
/// 原来这段算在主线程上，传感器每报一次（62 次/秒）就要叫醒一次主线程，而桌面没合上的时候
/// 根本没人用这个值。现在在传感器自己的队列上算好、只存最新一个，画面要用时来读。
/// 算法与原来的 DuoController.receiveMotion 逐位一致（测试里对照过）。
struct MotionTiltFilter {
  /// 80 毫秒低通。
  static let timeConstant = 0.08
  /// 传感器报的是 g；画面只要一点点、有上限的偏移。
  static let gain = 0.7
  static let limit = 0.45

  private var filtered = SIMD3<Double>.zero
  private var baseline = SIMD3<Double>.zero
  private var time = 0.0

  /// 第一份读数只记下基线（开关打开时的静止姿势，重力不会让桌面一直偏着），返回 nil，画面保持 0。
  mutating func update(_ acceleration: SIMD3<Double>, at now: Double) -> SIMD2<Double>? {
    if time == 0 {
      time = now
      filtered = acceleration
      baseline = acceleration
      return nil
    }
    let dt = time > 0 ? now - time : 0
    time = now
    let alpha = dt > 0 && dt < 1 ? 1 - exp(-dt / Self.timeConstant) : 0.35
    filtered += (acceleration - filtered) * alpha
    let delta = filtered - baseline
    return SIMD2(
      min(Self.limit, max(-Self.limit, delta.x * Self.gain)),
      min(Self.limit, max(-Self.limit, delta.y * Self.gain)))
  }
}

/// 交给渲染器的倾斜值。传感器噪声让偏移每帧都差一点点，于是桌面合到一半停住时也会每帧整屏重画；
/// 变化折算到屏幕上不到 maxShift 像素（远小于一个像素）就沿用上一帧的值，不算画面变了。
/// 超过就当帧跟上，所以看得见的动作一点不晚；“有没有在动”的判断（渲染器和着色器都用 1e-4）
/// 跨过门槛时也当帧跟上，走哪条渲染路径和原来一样。
struct TiltHold {
  /// 与 Duo.metal 里 `motion * float2(0.055, 0.040)` 的位移系数一致。
  static let shaderShift = SIMD2<Float>(0.055, 0.040)
  /// 与 FoldRenderer / Duo.metal 里判断“在动”的门槛一致。
  static let movingThreshold: Float = 0.0001
  /// 沿用旧值时允许的最大位移，单位是输出像素。
  static let maxShift: Float = 0.05

  private(set) var value = SIMD2<Float>.zero
  private var primed = false

  /// 某个输出尺寸下，每个轴允许沿用旧值的最大变化量。
  static func threshold(pixelWidth: Double, pixelHeight: Double) -> SIMD2<Float> {
    let pixels = SIMD2<Float>(Float(max(1, pixelWidth)), Float(max(1, pixelHeight)))
    return maxShift / (shaderShift * pixels)
  }

  static func isMoving(_ v: SIMD2<Float>) -> Bool { hypot(v.x, v.y) > movingThreshold }

  mutating func reset() {
    value = .zero
    primed = false
  }

  mutating func update(_ next: SIMD2<Float>, threshold: SIMD2<Float>) -> SIMD2<Float> {
    if !primed || next == .zero || Self.isMoving(next) != Self.isMoving(value)
      || abs(next.x - value.x) >= threshold.x || abs(next.y - value.y) >= threshold.y
    {
      value = next
      primed = true
    }
    return value
  }
}
