// 弹簧令牌到 CASpringAnimation（C05）：令牌自洽（dampingRatio = 1 − bounce）、
// Motion.spring 只做 keyPath 与 duration 的装配、duration 就是 settlingDuration。
// 需要 Core Animation；不启动 app、不读窗口。
import Cocoa

@main
struct MotionSpringTests {
    static func main() {
        var t = TestSuite("C05")
        typealias S = Motion.Spring

        let tokens: [(String, S)] = [
            ("calm", .calm), ("settle", .settle), ("expand", .expand), ("bloom", .bloom),
            ("catchDrop", .catchDrop), ("glide", .glide), ("flyOut", .flyOut), ("pull", .pull),
            ("pop", .pop), ("reducedNotch", .reducedNotch), ("reducedWindow", .reducedWindow),
            ("islandPrompt", .islandPrompt), ("islandSizing", .islandSizing), ("islandHidden", .islandHidden),
        ]

        t.section("C05-01", "令牌自洽：response > 0，dampingRatio = 1 − bounce（岛令牌的舍入也在容差内）")
        for (name, token) in tokens {
            t.expect(token.response > 0, "\(name) response > 0")
            t.expect(abs(token.dampingRatio - (1 - Double(token.bounce))) < 1e-9,
                     "\(name) dampingRatio = 1 − bounce")
            t.expect(token.dampingRatio > 0 && token.dampingRatio <= 1, "\(name) dampingRatio 在 (0,1]")
        }

        t.section("C05-02", "岛令牌就是 27.3 的两组值")
        t.expect(S.islandPrompt.response == 0.408 && S.islandPrompt.dampingRatio == 0.27, "islandPrompt 0.408/0.27")
        t.expect(abs(S.islandSizing.response - 0.3571428536916519) < 1e-15, "islandSizing response")
        t.expect(abs(S.islandSizing.dampingRatio - 0.7500006097576885) < 1e-15, "islandSizing dampingRatio")
        t.expect(S.islandHidden.response == 0.3 && S.islandHidden.dampingRatio == 0.8
                 && S.islandHidden.bounce == 0.2,
                 "islandHidden 0.3 / 0.8 / bounce 0.2")

        t.section("C05-03", "Motion.spring：keyPath 原样，duration = settlingDuration")
        let animation = Motion.spring(.islandSizing, keyPath: "bounds.size.width")
        t.expect(animation.keyPath == "bounds.size.width", "keyPath 原样")
        t.expect(animation.duration == animation.settlingDuration, "duration = settlingDuration")
        t.expect(animation.duration > S.islandSizing.response, "落定时间比感知时长长")

        t.section("C05-04", "CASpringAnimation 由令牌造出正的 mass/stiffness/damping")
        let prompt = Motion.spring(.islandPrompt, keyPath: "bounds.size.height")
        t.expect(prompt.mass > 0 && prompt.stiffness > 0 && prompt.damping > 0, "物理量都是正的")
        t.expect(prompt.duration > S.islandPrompt.response, "prompt 也会多走一点才停")

        t.finish()
    }
}
