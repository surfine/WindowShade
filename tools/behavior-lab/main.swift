import Foundation
import CoreGraphics
import Carbon

// 明确选择 --observe 才短时监听；默认只查询权限。不读取字符，不操作输入或锁屏。
final class BehaviorObserver {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: CFRunLoopTimer?
    private var lastPoint: CGPoint?
    private var interrupted = false
    private let started = ProcessInfo.processInfo.systemUptime
    private let accumulator: TimingFeatureAccumulator

    init() {
        accumulator = TimingFeatureAccumulator(context: "unlabelled-input", startedAt: ProcessInfo.processInfo.systemUptime)
    }

    func receive(_ type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            interrupted = true
            CFRunLoopStop(CFRunLoopGetCurrent())
            return
        }
        let time = Double(event.timestamp) / 1_000_000_000
        switch type {
        case .keyDown:
            accumulator.keyDown(code: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                                at: time, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        case .keyUp:
            accumulator.keyUp(code: UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)), at: time)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let point = event.location
            if let previous = lastPoint {
                accumulator.pointerMoved(dx: point.x - previous.x, dy: point.y - previous.y, at: time)
            }
            lastPoint = point
        default: break
        }
    }

    func run() -> Int32 {
        guard CGPreflightListenEventAccess(), !IsSecureEventInputEnabled() else {
            print("观察不可用：需要输入监控权限，且当前不能处于安全输入。未请求权限、未开始监听。")
            return 1
        }
        let types: [CGEventType] = [.keyDown, .keyUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                         options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
            if let context {
                Unmanaged<BehaviorObserver>.fromOpaque(context).takeUnretainedValue().receive(type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            print("观察不可用：系统未建立只读事件监听。")
            return 1
        }
        tap = port; source = runLoopSource
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop, runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + 0.25, 0.25, 0, 0) { [weak self] _ in
            guard let self else { return }
            if IsSecureEventInputEnabled() {
                self.interrupted = true
                CFRunLoopStop(loop)
            } else if ProcessInfo.processInfo.systemUptime - self.started >= 30 {
                CFRunLoopStop(loop)
            }
        }
        if let timer { CFRunLoopAddTimer(loop, timer, .commonModes) }
        print("观察 30 秒，仅在内存中计算时序和指针变化。输入照常传递；结束后只输出统计，不保存文件。")
        CFRunLoopRun()
        if let timer { CFRunLoopTimerInvalidate(timer) }
        CFRunLoopRemoveSource(loop, runLoopSource, .commonModes)
        CFMachPortInvalidate(port)
        tap = nil; source = nil; timer = nil; lastPoint = nil
        guard !interrupted else {
            accumulator.reset(context: "unknown", at: ProcessInfo.processInfo.systemUptime)
            print("观察中断，样本丢弃，不能据此判断行为。")
            return 2
        }
        let window = accumulator.snapshot(endedAt: ProcessInfo.processInfo.systemUptime)
        print("有效样本：按住 \(window.holds.count)，击键间隔 \(window.downGaps.count)，指针速度 \(window.pointerSpeeds.count)，转向 \(window.pointerTurns.count)。")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for modality in [BehaviorVector.Modality.keyboard, .pointer] {
            if let vector = BehaviorVector.extract(window, modality: modality), let data = try? encoder.encode(vector) {
                print(String(decoding: data, as: UTF8.self))
            } else { print("\(modality.rawValue): 样本不足/未知") }
        }
        print("样本未核定本人归属，不能用于自动训练或授权。未触发认证、拒绝或锁机。")
        return 0
    }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args {
case [], ["--capabilities"]:
    print("Input Monitoring available: \(CGPreflightListenEventAccess())")
    print("Secure Input active: \(IsSecureEventInputEnabled())")
    print("仅查询状态；未监听、未请求权限、未保存数据。")
case ["--observe"]:
    let observer = BehaviorObserver()
    exit(observer.run())
case ["--help"]:
    print("用法：BehaviorLab [--capabilities|--observe|--help]。--observe 明确启动 30 秒只读小样。")
default:
    print("一次选择一种模式：--capabilities、--observe 或 --help。")
    exit(1)
}
