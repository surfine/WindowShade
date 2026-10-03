// WindowShade 2 审查包：原创边界骨架，非完整功能。
import CoreGraphics
// tap 回调 ABI。演示透传，不在这里创建任务、日志、AX 查询或阻塞锁。
let inputTapCallback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // 正式桥只设置一个受控故障标志，管理队列负责撤销，不能在回调中重装。
        return Unmanaged.passUnretained(event)
    }
    if event.getIntegerValueField(.eventSourceUserData) == 0x5753_4933 {
        return Unmanaged.passUnretained(event)
    }
    return Unmanaged.passUnretained(event)
}
