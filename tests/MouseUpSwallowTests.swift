import Dispatch

// 第二次按下被吞后，配对的松开只吞一次；漏掉的松开不能影响后续点击。

@main
struct MouseUpSwallowTests {
    static func main() {
        var gate = MouseUpSwallow()

        // 没装填时松开照常放行
        precondition(gate.consume(now: .now()) == false)

        // 装填后只吞一次
        gate.arm(now: .now())
        precondition(gate.consume(now: .now()) == true)
        precondition(gate.consume(now: .now()) == false)

        // 超过有效期：不吞，并且把状态清掉
        let t = DispatchTime.now()
        gate.arm(now: t)
        precondition(gate.consume(now: t + .milliseconds(1500)) == false)
        precondition(gate.consume(now: t) == false)

        // reset 之后不吞
        gate.arm()
        gate.reset()
        precondition(gate.consume() == false)

        // 重新装填仍然有效（新的一次双击）
        gate.arm()
        precondition(gate.consume() == true)

        print("MouseUpSwallowTests ok")
    }
}
