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
