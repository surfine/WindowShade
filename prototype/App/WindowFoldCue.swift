// 收起动画的描边代理（整合计划第 14 步；第 19 条“收起动画默认开”）。
//
// 卷帘动画（WindowFoldEffects）要窗口的画面，没有屏幕录制时放不了；减少动态效果、暂停效果时也不放。
// 这时“收起窗口时的动画”开着，就用第 13 步的描边代理：窗口圆角的一圈描边从窗口外框卷到顶上一条
// （`fold`，约 0.25 秒落定、不过冲），真窗口照常收起。减少动态效果：描边在原处淡出，不卷、不缩。
// 卷到一半又展开（双击卷帘条、往下拉）：描边从此刻的位置和速度掉头回去（ProxyMotion.retargeted）。

import Cocoa

@MainActor
enum WindowFoldCue {
    private static var stages: [CGWindowID: (stage: WindowProxyStage, home: CGRect)] = [:]
    /// 卷到顶上那一条有多高（点）：和卷帘条差不多高。
    static let stripHeight: CGFloat = 28
    /// 诊断与探针：最近一次描边代理是怎么走的。
    private(set) static var lastPresentation: ProxyPresentation?
    private(set) static var lastPlayedAt: CFTimeInterval = 0

    static var isPlaying: Bool { !stages.isEmpty }

    /// 收起动画的终点：窗口顶上一条，和窗口一样宽。
    static func strip(of frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(frame.height, stripHeight))
    }

    /// frame：真窗口收起前的外框（AX 坐标）。
    static func play(id: CGWindowID, frame: CGRect) {
        stages.removeValue(forKey: id)?.stage.finish(fade: false)
        let stage = WindowProxyStage(frame: frame, look: .outline, snapshot: nil, cornerRadius: SystemCornerRadius.window)
        stages[id] = (stage, frame)
        let presentation = ProxyPresentation.choose(reduceMotion: Motion.reduced)
        lastPresentation = presentation
        lastPlayedAt = CACurrentMediaTime()
        switch presentation {
        case .dissolve:
            // 原处淡出：不卷、不缩。
            stages.removeValue(forKey: id)
            stage.finish(fade: true, duration: MotionSpring.reducedNotch.response)
        case .slide:
            let spring = FlickSpring(dampingRatio: MotionSpring.fold.dampingRatio, response: MotionSpring.fold.response)
            let motion = ProxyMotion(from: frame, to: strip(of: frame), velocity: .zero, at: CACurrentMediaTime(),
                                     position: spring, size: spring, limitOvershoot: nil)
            stage.play(motion) { done(id, stage) }
        }
        wlog("shade: fold cue id=\(id) \(presentation == .slide ? "outline rolls up" : "outline fades in place")")
    }

    /// 卷到一半被叫回去（展开）：从此刻的位置和速度掉头回到原来的外框，再淡出。
    static func reverse(id: CGWindowID) {
        guard let entry = stages[id], let motion = entry.stage.motion else { return }
        let back = motion.retargeted(to: entry.home, at: CACurrentMediaTime())
        entry.stage.play(back) { done(id, entry.stage) }
        wlog("shade: fold cue id=\(id) turned back mid-way")
    }

    private static func done(_ id: CGWindowID, _ stage: WindowProxyStage) {
        if stages[id]?.stage === stage { stages.removeValue(forKey: id) }
        stage.finish()
    }
}
