// iPhone 遥控器（Companion 协议）送来的按键和触控 → WindowShade 统一的按键与手势（工作包 1-4）。
// 键码、触控门槛、会话时限借 atv-core 的接收端（session.rs / server.rs，只借数值和思路，不抄代码）；
// 方向键 1–4、音量 8/9 和 pyatv 的 HidCommand 一致。键码还要在真机上核对（《iPhone 上的遥控器》验收第 6 步）。
//
// 规则：
// - `_hidC` 是键码，`_hBtS` 1 按下、2 松开，松开才算一次（按住不放、半路断线都不算按过）。
// - `_hidT` 的坐标在 1000×1000 的触控区里，`_tPh` 1 开始、2 移动、4 结束。
//   抬手时总位移不到 60 算点一下；竖着滑至少 160（16%）算一次上下滑，中间那一段两样都不算（宁可不动，不猜）。
//   横着滑边划边步进：一次触摸里横向累计位移每满 200（20% 宽）就发一步并重置起点，不用等抬手。
//   这些阈值都是暂定，待真机采样。
// - 认不出的键码、阶段、坐标都丢掉，不当成别的键。
// 纯逻辑，不碰网络和加密，接收端拿它翻译。

import Foundation

enum CompanionHID {
    // MARK: 按键

    /// 键码 → 按键。认不出的返回 nil。
    static func button(code: UInt64) -> WS2.Button? {
        switch code {
        case 1: return .up
        case 2: return .down
        case 3: return .left
        case 4: return .right
        case 5: return .back        // 返回（遥控器上的“菜单”）
        case 6: return .select      // 确认
        case 7: return .tv          // 电视键
        case 8: return .volumeUp
        case 9: return .volumeDown
        case 14: return .playPause
        case 18: return .mute       // iOS 26/27 控制中心的遥控器复用 18
        case 19: return .power      // 同上复用 19；电源在我们这里是“收工”，不是让显示器睡眠
        default: return nil
        }
    }

    enum ButtonState: UInt64 { case down = 1, up = 2 }

    /// 一个按键会话：按下记下来，同一个键松开才吐出一次按压。没按下就松开、重复按下都不算。
    struct Buttons: Sendable {
        private var held: Set<WS2.Button> = []

        /// 返回这次松开完成的按键；其它情况返回 nil。
        mutating func feed(code: UInt64, state: UInt64) -> WS2.Button? {
            guard let button = CompanionHID.button(code: code), let state = ButtonState(rawValue: state) else { return nil }
            switch state {
            case .down:
                held.insert(button)
                return nil
            case .up:
                return held.remove(button) == nil ? nil : button
            }
        }

        /// 断线、会话结束：按着的键都作废，不补发。
        mutating func cancelAll() { held.removeAll() }
    }

    // MARK: 触控

    static let touchSide: Double = 1000
    /// 抬手时总位移小于它算点一下（触控区坐标）。暂定，待真机采样。
    static let tapLimit: Double = 60
    /// 竖滑：总位移至少这么多才算一次上 / 下滑（16%）。暂定，待真机采样。
    static let swipeMinimum: Double = 160
    /// 横滑：累计位移每满这么多发一步（20% 宽）。暂定，待真机采样。
    static let stepDistance: Double = 200

    enum TouchPhase: UInt64 { case began = 1, moved = 2, ended = 4 }

    enum Gesture: Equatable, Sendable {
        case tap
        /// 方向按手指走的方向：触控区 y 向下，这里已经换成上下左右。横向每一步各发一次，竖向抬手时发一次。
        case swipe(FocusDirection)
    }

    enum FocusDirection: Equatable, Sendable { case up, down, left, right }

    struct Touch: Sendable {
        private var origin: (x: Double, y: Double)?
        /// 这次触摸里已经发过横向步进：抬手不再补点按或竖滑。
        private var stepped = false
        private var begin: (x: Double, y: Double)?

        /// 喂一个 `_hidT`。移动中横向每满一步就吐一步；抬手时吐点按或竖滑（发过步进就不吐）。
        /// 阶段乱了、坐标不对就放弃这一次触摸。
        mutating func feed(phase raw: UInt64, x: Double, y: Double) -> [Gesture] {
            guard let phase = TouchPhase(rawValue: raw),
                  x.isFinite, y.isFinite,
                  (0...CompanionHID.touchSide).contains(x), (0...CompanionHID.touchSide).contains(y) else {
                reset(); return []
            }
            switch phase {
            case .began:
                origin = (x, y); begin = (x, y); stepped = false
                return []
            case .moved:
                return steps(toX: x, y: y)
            case .ended:
                guard let begin else { return [] }
                let result = steps(toX: x, y: y)
                let didStep = stepped
                reset()
                if didStep { return result }
                return CompanionHID.classify(dx: x - begin.x, dy: y - begin.y).map { [$0] } ?? []
            }
        }

        /// 横向累计位移每满一步发一步，起点按步长前移（粗采样一次跳很远也不丢步）。
        private mutating func steps(toX x: Double, y: Double) -> [Gesture] {
            guard let start = origin else { return [] }
            let dx = x - start.x, dy = y - start.y
            guard abs(dx) >= CompanionHID.stepDistance, abs(dx) > abs(dy) else { return [] }
            let count = Int(abs(dx) / CompanionHID.stepDistance)
            let direction: FocusDirection = dx > 0 ? .right : .left
            origin = (start.x + (dx > 0 ? 1 : -1) * Double(count) * CompanionHID.stepDistance, y)
            stepped = true
            return Array(repeating: .swipe(direction), count: count)
        }

        mutating func reset() { origin = nil; begin = nil; stepped = false }
    }

    /// 整次触摸的总位移：点、竖滑、或者都不算。横滑不在这里分：它在移动中按步发出。
    static func classify(dx: Double, dy: Double) -> Gesture? {
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance < tapLimit { return .tap }
        guard abs(dy) >= swipeMinimum, abs(dy) > abs(dx) else { return nil }
        return .swipe(dy > 0 ? .down : .up)
    }

    // MARK: 会话

    /// 连上之后多久没动静就断：手机后台探测（`_x` 高位置位）1 秒；验过签却不开会话 3 秒；其余 2.5 秒。
    static func idleLimit(backgroundProbe: Bool, verifiedWithoutSession: Bool) -> TimeInterval {
        if backgroundProbe { return 1 }
        if verifiedWithoutSession { return 3 }
        return 2.5
    }

    /// 生产路径通告的媒体控制标志：0x0100 让 iPhone 的音量键能调这台 Mac 的音量。
    static let volumeControlFlag: UInt64 = 0x0100
}
