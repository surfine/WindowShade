// 启动台单测 / 夹具不编进 App 的 `Motion.swift`（那份会读系统减少动态效果）。
import Cocoa

enum Motion {
    static var reduced = false
    typealias Spring = MotionSpring
    static var fadeDuration: CFTimeInterval {
        reduced ? Spring.reducedNotch.response : Spring.calm.response
    }
    static func spring(_ token: Spring, keyPath: String) -> CASpringAnimation {
        let animation = CASpringAnimation(perceptualDuration: token.response, bounce: token.bounce)
        animation.keyPath = keyPath
        animation.duration = animation.settlingDuration
        return animation
    }
}
