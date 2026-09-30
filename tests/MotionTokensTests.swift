// 设计系统 §4.6 的弹簧令牌（§6-5 收拢）：把现在用的参数一条条收进 Motion.Spring。
// 收拢不改数值：这里逐字对照令牌的 response / dampingRatio / bounce 和收拢之前那些字面量；
// 阻尼比必须等于 1 − bounce。纯计算，不碰窗口（不访问 NSWorkspace）。
import CoreGraphics
import Foundation

@main
struct MotionTokensTests {
  static var failures = 0
  static func expect(_ condition: Bool, _ message: String) {
    if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
  }

  /// 一个令牌：逐字对照三个字面量，并检查阻尼比 = 1 − bounce。
  static func expect(_ name: String, _ token: Motion.Spring,
                     response: Double, dampingRatio: Double, bounce: CGFloat) {
    let got = "response \(token.response), dampingRatio \(token.dampingRatio), bounce \(token.bounce)"
    expect(token.response == response && token.dampingRatio == dampingRatio && token.bounce == bounce,
           "\(name) is response \(response), dampingRatio \(dampingRatio), bounce \(bounce) exactly (got \(got))")
    expect(abs(token.dampingRatio - (1 - Double(token.bounce))) < 1e-9,
           "\(name): dampingRatio \(token.dampingRatio) is 1 − bounce \(token.bounce)")
  }

  static func main() {
    // 令牌表（和 Notch.swift / FlickMotion.swift 收拢前用的数字逐字相同）。
    expect("calm", Motion.Spring.calm, response: 0.34, dampingRatio: 1, bounce: 0)
    expect("settle", Motion.Spring.settle, response: 0.38, dampingRatio: 1, bounce: 0)
    expect("expand", Motion.Spring.expand, response: 0.4, dampingRatio: 0.92, bounce: 0.08)
    expect("bloom", Motion.Spring.bloom, response: 0.42, dampingRatio: 0.84, bounce: 0.16)
    expect("catchDrop", Motion.Spring.catchDrop, response: 0.4, dampingRatio: 0.8, bounce: 0.2)
    expect("glide", Motion.Spring.glide, response: 0.42, dampingRatio: 0.88, bounce: 0.12)
    expect("flyOut", Motion.Spring.flyOut, response: 0.38, dampingRatio: 0.9, bounce: 0.1)
    expect("pull", Motion.Spring.pull, response: 0.36, dampingRatio: 0.86, bounce: 0.14)
    expect("pop", Motion.Spring.pop, response: 0.3, dampingRatio: 0.75, bounce: 0.25)
    expect("reducedNotch", Motion.Spring.reducedNotch, response: 0.25, dampingRatio: 1, bounce: 0)
    expect("reducedWindow", Motion.Spring.reducedWindow, response: 0.3, dampingRatio: 1, bounce: 0)

    // 甩一下标题栏的窗口滑行：三个静态值改成引用令牌后，数值和收拢之前的字面量一样。
    let position = FlickSpring.position
    expect(position.dampingRatio == 0.88 && position.response == 0.42,
           "FlickSpring.position is (dampingRatio 0.88, response 0.42) exactly \(position.dampingRatio), \(position.response))")
    let size = FlickSpring.size
    expect(size.dampingRatio == 1 && size.response == 0.38,
           "FlickSpring.size is (dampingRatio 1, response 0.38) exactly \(size.dampingRatio), \(size.response))")
    let calm = FlickSpring.calm
    expect(calm.dampingRatio == 1 && calm.response == 0.3,
           "FlickSpring.calm is (dampingRatio 1, response 0.3) exactly \(calm.dampingRatio), \(calm.response))")

    expect(position.dampingRatio == Motion.Spring.glide.dampingRatio && position.response == Motion.Spring.glide.response,
           "FlickSpring.position is the glide token")
    expect(size.dampingRatio == Motion.Spring.settle.dampingRatio && size.response == Motion.Spring.settle.response,
           "FlickSpring.size is the settle token")
    expect(calm.dampingRatio == Motion.Spring.reducedWindow.dampingRatio && calm.response == Motion.Spring.reducedWindow.response,
           "FlickSpring.calm is the reducedWindow token")

    if failures == 0 {
      print("PASS: motion tokens match the values they were collected from")
    } else {
      print("FAILED \(failures)")
      exit(1)
    }
  }
}
