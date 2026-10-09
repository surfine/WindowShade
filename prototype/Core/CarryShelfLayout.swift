import CoreGraphics

/// 跨桌面卷帘条只占一行；放不下的仍能从系统菜单访问。
enum CarryShelfLayout {
    static let stripSize = CGSize(width: 260, height: 30)
    static let gap: CGFloat = 8

    struct Result {
        var strips: [(id: CGWindowID, frame: CGRect)] = []
        var overflow: [CGWindowID] = []
        var moreFrame: CGRect?
    }

    static func compute(ids: [CGWindowID], visibleFrame: CGRect,
                        promotedID: CGWindowID? = nil) -> Result {
        guard !ids.isEmpty, visibleFrame.width.isFinite, visibleFrame.height.isFinite,
              visibleFrame.width > 0, visibleFrame.height >= stripSize.height else { return Result() }
        var ordered = ids
        if let promotedID, let index = ordered.firstIndex(of: promotedID) {
            ordered.remove(at: index)
            ordered.insert(promotedID, at: 0)
        }
        let side = min(10, visibleFrame.width / 10)
        let available = visibleFrame.width - 2 * side
        let right = visibleFrame.maxX - side
        let y = visibleFrame.maxY - min(8, visibleFrame.height - stripSize.height) - stripSize.height
        let needed = CGFloat(ids.count) * stripSize.width + CGFloat(ids.count - 1) * gap
        var count = ids.count
        var width = stripSize.width
        var moreWidth: CGFloat = 0
        if needed > available {
            if ids.count == 1 {
                width = available
            } else if available >= 128 { // 一条最窄 80，加 40 的菜单入口与 8 的缝。
                moreWidth = min(84, available - 80 - gap)
                let room = available - moreWidth - gap
                count = max(1, Int((room + gap) / (stripSize.width + gap)))
                width = min(stripSize.width, room)
            } else {
                // 极端小的可见区域：至少保留菜单，不能让项目在屏幕外或彼此覆盖。
                return Result(overflow: ordered,
                              moreFrame: CGRect(x: visibleFrame.minX + side, y: y,
                                                width: available, height: stripSize.height))
            }
        }
        let strips = ordered.prefix(count).enumerated().map { index, id in
            (id: id, frame: CGRect(x: right - width - CGFloat(index) * (width + gap), y: y,
                                  width: width, height: stripSize.height))
        }
        let overflow = Array(ordered.dropFirst(count))
        let more = moreWidth > 0 ? CGRect(x: (strips.last?.frame.minX ?? right) - gap - moreWidth,
                                         y: y, width: moreWidth, height: stripSize.height) : nil
        return Result(strips: strips, overflow: overflow, moreFrame: more)
    }
}

/// 刘海上几处小行为的判定和时序常量（纯函数，方便单独测）。
enum NotchSmallBehaviour {
    /// 窗口读不到最小尺寸时按这个算。
    static let fallbackMinimumSize = CGSize(width: 200, height: 150)
    /// 放不下的格子灰到这个透明度。
    static let disabledAlpha: CGFloat = 0.35
    /// 落点上的原因（文案过 copy-guide）。
    static let disabledReason = "屏幕太小，放不下"

    /// 目标格里窗口会有多大，放不下（比窗口的最小尺寸还小）就灰掉。target 为 nil（收进刘海这类不改大小的去处）永远可用。
    static func isDisabled(target: CGSize?, minimum: CGSize?) -> Bool {
        guard let target else { return false }
        let floor = sanitized(minimum) ?? fallbackMinimumSize
        return target.width < floor.width || target.height < floor.height
    }

    private static func sanitized(_ size: CGSize?) -> CGSize? {
        guard let size, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return size
    }

    /// 从提醒图标起飞：有图标位置就用它，没有才退回调用方的默认起点。
    static func flightOrigin(icon: CGRect?) -> CGRect? {
        guard let icon, !icon.isEmpty, icon.minX.isFinite, icon.minY.isFinite else { return nil }
        return icon
    }

    /// 点格子放回时，窗口起飞后这一排再等这么久才开始收。
    static let rowCollapseLag: Double = 0.04
    /// 展开时格子淡入：从形状开始后多久起，以及相邻两格错开多久。
    static let tileFadeStart: Double = 0.09
    static let tileFadeStep: Double = 0.04

    /// 错开最多数到第 4 格：格子再多，最后一格也在 0.25 秒内出现，不拖成一长串。
    static let tileFadeMaxIndex = 4

    static func tileFadeDelay(index: Int) -> Double {
        tileFadeStart + tileFadeStep * Double(min(tileFadeMaxIndex, max(0, index)))
    }

    /// 边线渐变：从岛的顶边往下 `keyLineHiddenDepth` 点还看不见，到 `keyLineFullDepth` 点完全显出。
    static let keyLineHiddenDepth: CGFloat = 3
    static let keyLineFullDepth: CGFloat = 20

    /// 距顶边 depth 点处边线的可见度（0...1）。
    static func keyLineVisibility(atDepth depth: CGFloat) -> CGFloat {
        guard depth > keyLineHiddenDepth else { return 0 }
        guard depth < keyLineFullDepth else { return 1 }
        return (depth - keyLineHiddenDepth) / (keyLineFullDepth - keyLineHiddenDepth)
    }

    /// 渐变停点（从图层顶到底，0 在顶）：图层顶上有 overscan 点被岛裁掉。
    static func keyLineLocations(layerHeight: CGFloat, overscan: CGFloat) -> [Double] {
        guard layerHeight > 0 else { return [0, 0, 1, 1] }
        let hidden = Double(min(1, (overscan + keyLineHiddenDepth) / layerHeight))
        let full = Double(min(1, (overscan + keyLineFullDepth) / layerHeight))
        return [0, hidden, max(hidden, full), 1]
    }
}
