import Dispatch

/// 双击标题栏的第二下按下被吞掉之后，配对的松开也要吞：
/// macOS 26 的“双击缩放”发生在第二次松开时，只拦按下会让窗口先放大，
/// 卷帘条截到的是放大后的窗口。
///
/// 只在 tap 线程上按顺序使用。给一个短窗口，避免漏掉的松开事件把后续点击吞掉。
struct MouseUpSwallow {
    static let lifetime: DispatchTimeInterval = .seconds(1)

    private var deadline: DispatchTime?

    mutating func arm(now: DispatchTime = .now()) {
        deadline = now + Self.lifetime
    }

    /// 到了配对的松开：返回 true 表示这一下要吞，并清掉状态。
    mutating func consume(now: DispatchTime = .now()) -> Bool {
        guard let deadline else { return false }
        self.deadline = nil
        return now <= deadline
    }

    mutating func reset() {
        deadline = nil
    }
}
