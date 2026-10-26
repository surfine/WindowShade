import Cocoa

/// 「暗时屏幕四周亮一圈补光」（face-unlock.md 的画面；只作画质辅助，不作活体判据——
/// 炫彩这一轮明确不用，这里是柔和白边光）。
///
/// 录脸取景一直报「光线太暗」时，在那一块屏的四边亮一圈很暗的白；提示不再是「光线太暗」、
/// 或者录脸一结束（存好、作废、取消），就熄。不闪、不换颜色、不追亮度读数逐帧调，
/// 以免跟自动曝光打架（身份线 §3.4 只保留稳定补光那一条）。
/// 面板与录脸卡同岛不同层：不抢刘海租约，不响应鼠标。
@MainActor final class FaceFillLightController {
    /// 连续多少帧的提示都是「太暗」才亮灯：单帧噪声不点灯。
    static let darkFramesBeforeOn = 3

    private var panel: EffectPanel?
    private var darkStreak = 0
    private var lit = false

    /// 录脸一帧的画质提示进来一次。nil = 这轮结束，熄灯归零。
    func enrollHint(_ hint: FaceQualityHint?) {
        guard let hint else { reset(); return }
        if case .tooDark = hint {
            darkStreak += 1
            if darkStreak >= Self.darkFramesBeforeOn, !lit { light() }
        } else {
            if lit { dim() }
            darkStreak = 0
        }
    }

    func reset() {
        dim()
        darkStreak = 0
    }

    private func light() {
        guard panel == nil else { return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let panel = EffectPanel(frame: screen.frame, desktop: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = FaceFillLightView(frame: NSRect(origin: .zero, size: screen.frame.size))
        self.panel = panel
        panel.orderFrontRegardless()
        lit = true
    }

    private func dim() {
        guard let panel else { return }
        panel.orderOut(nil)
        self.panel = nil
        lit = false
    }

    var probeLit: Bool { lit }
    var probeOnScreen: Bool { panel?.isVisible == true }
}

/// 四边的柔和白光：边缘最亮约 8%，向内 160 点淡出到没有。屏幕中央完全不动，
/// 不照脸、不挡任何内容（只是画面四周的暗光）。
@MainActor final class FaceFillLightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 160
        let edge = NSBezierPath(rect: bounds)
        edge.append(NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset)))
        edge.windingRule = .evenOdd
        guard let gradient = NSGradient(starting: NSColor(white: 1, alpha: 0.08),
                                        ending: NSColor(white: 1, alpha: 0)) else { return }
        gradient.draw(in: edge, angle: -90)
    }
}
