import Foundation

/// F12：人脸观察流水线复用 Vision 请求与连续帧 handler。
/// 会话内同一实例反复用；退回系统预设（pinned 变 false）时重建一次；换会话 reset 后重建。
private final class RequestDouble { let pinned: Bool; init(pinned: Bool) { self.pinned = pinned } }
private final class HandlerDouble {}
private final class Tally { var made: [Bool] = []; var handlers = 0 }

@main struct FaceObservationPipelineTests {
    static func main() {
        let tally = Tally()
        var slot = FaceLandmarkRequestSlot<RequestDouble, HandlerDouble>(
            makeRequest: { pinned in tally.made.append(pinned); return RequestDouble(pinned: pinned) },
            makeHandler: { tally.handlers += 1; return HandlerDouble() })

        precondition(slot.builds == 0 && tally.made.isEmpty, "没用到之前不建请求")

        let (firstRequest, firstHandler) = slot.acquire(pinned: true)
        for _ in 0..<50 {
            let (request, handler) = slot.acquire(pinned: true)
            precondition(request === firstRequest && handler === firstHandler, "连续帧复用同一个请求与 handler")
        }
        precondition(slot.builds == 1 && tally.made == [true] && tally.handlers == 1,
                     "50 帧只建一次，computeDevice 只设一次")
        precondition(firstRequest.pinned, "第一次建的请求钉在神经引擎上")

        // 退回系统预设：pinned 变 false，重建一次，之后照样复用。
        let (fallbackRequest, fallbackHandler) = slot.acquire(pinned: false)
        precondition(fallbackRequest !== firstRequest && fallbackHandler !== firstHandler, "退路时请求与 handler 都重建")
        precondition(!fallbackRequest.pinned, "退路后的请求不再钉神经引擎")
        for _ in 0..<10 {
            let (request, _) = slot.acquire(pinned: false)
            precondition(request === fallbackRequest, "退路后继续复用新请求")
        }
        precondition(slot.builds == 2 && tally.made == [true, false] && tally.handlers == 2, "退路只多建一次")

        // 换会话或拆掉：reset 后下一帧重建，新会话重新钉神经引擎。
        slot.reset()
        let (sessionRequest, _) = slot.acquire(pinned: true)
        precondition(sessionRequest !== firstRequest && sessionRequest.pinned, "新会话用新的、钉住的请求")
        precondition(slot.builds == 3 && tally.made == [true, false, true] && tally.handlers == 3, "reset 后只重建一次")

        print("PASS: face pipeline reuses one landmarks request and sequence handler; rebuilds only on fallback or new session")
    }
}
