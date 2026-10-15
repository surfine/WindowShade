import CoreGraphics
import Foundation
import os

// 事件 tap 的登记表（规格 R1／R3）。
//
// 系统会在回调超时、输入洪泛、睡醒时把 tap 静默停掉：没有通知，只是从此不再送事件。各处自己的
// tapDisabledBy… 处理只在收到那两个事件时才管用。这里给所有 tap 一个共同的「体检」：
// 5 秒一次（WindowShade.swift 的 runEnvironmentCheck）、睡醒后三档（立即、0.2 秒、0.8 秒）。
//
// 只重开「登记了、端口有效、却被停掉」的 tap。功能关掉时各处是停用（有的不作废）端口，
// 所以 tap 的主人必须在想要它开着时 register、关掉时 unregister——体检绝不替用户打开关掉的功能。
// 正在退避（输入洪泛后故意等一会儿再开）的端口用 hold 标出来，退避期内不碰。

/// 纯逻辑：不碰系统，端口的有效与开关由调用方传进来，便于单测（tests/EventTapHealthTests.swift）。
struct TapHealthBook<Port: AnyObject> {
    struct Entry {
        let port: Port
        let label: String
        var holdUntil: ContinuousClock.Instant?
    }

    private(set) var entries: [ObjectIdentifier: Entry] = [:]

    /// 主人想要它开着。重复登记只更新名字，并清掉退避。
    mutating func register(_ port: Port, label: String) {
        entries[ObjectIdentifier(port)] = Entry(port: port, label: label, holdUntil: nil)
    }

    /// 主人把它关了或拆了。
    mutating func unregister(_ port: Port) {
        entries.removeValue(forKey: ObjectIdentifier(port))
    }

    /// 退避期内体检不碰它（主人自己会在到点时重开）。
    mutating func hold(_ port: Port, until: ContinuousClock.Instant) {
        entries[ObjectIdentifier(port)]?.holdUntil = until
    }

    /// 这一次要重开哪些；作废了的端口顺手移出登记表（返回在 dropped 里，供日志）。
    mutating func due(now: ContinuousClock.Instant,
                      isValid: (Port) -> Bool,
                      isEnabled: (Port) -> Bool) -> (reenable: [Entry], dropped: [String]) {
        var reenable: [Entry] = []
        var dropped: [String] = []
        for (key, entry) in entries {
            guard isValid(entry.port) else {
                entries.removeValue(forKey: key)
                dropped.append(entry.label)
                continue
            }
            if let until = entry.holdUntil {
                if now < until { continue }
                entries[key]?.holdUntil = nil
            }
            if !isEnabled(entry.port) { reenable.append(entry) }
        }
        return (reenable.sorted { $0.label < $1.label }, dropped.sorted())
    }
}

extension TapHealthBook: Sendable where Port: Sendable {}
extension TapHealthBook.Entry: Sendable where Port: Sendable {}

/// 全 App 共用的那一份。登记与体检可以在任意线程调；重开端口只用 CGEvent.tapEnable（见 SendableSystemHandles）。
final class EventTapHealth: Sendable {
    static let shared = EventTapHealth()

    private let book = OSAllocatedUnfairLock(initialState: TapHealthBook<CFMachPort>())

    func register(_ port: CFMachPort, label: String) {
        book.withLock { $0.register(port, label: label) }
    }

    func unregister(_ port: CFMachPort) {
        book.withLock { $0.unregister(port) }
    }

    func hold(_ port: CFMachPort, for seconds: Double) {
        let until = ContinuousClock.now.advanced(by: .milliseconds(Int(seconds * 1000)))
        book.withLock { $0.hold(port, until: until) }
    }

    /// 重开被静默停掉的 tap，返回重开了哪些（名字）。作废的端口移出登记表并记一行日志。
    @discardableResult
    func sweep(reason: String) -> [String] {
        let now = ContinuousClock.now
        let result = book.withLock {
            $0.due(now: now, isValid: { CFMachPortIsValid($0) }, isEnabled: { CGEvent.tapIsEnabled(tap: $0) })
        }
        for entry in result.reenable { CGEvent.tapEnable(tap: entry.port, enable: true) }
        if !result.dropped.isEmpty {
            wlog("event-tap-health: \(reason) dropped invalid taps \(result.dropped)")
            SystemLog.input.error("\(reason, privacy: .public) dropped invalid taps \(result.dropped.joined(separator: ","), privacy: .public)")
        }
        return result.reenable.map(\.label)
    }

    /// 诊断：现在登记了几支。
    var registeredCount: Int { book.withLock { $0.entries.count } }
}

/// 睡醒后的三档（对照 Wins 的 resume.immediate / resume.delayed.0.20 / resume.delayed.0.80）：
/// 系统各部分醒来有先后，一次不够，三档足够且有界。每档都先看「还需要吗」，所以重复执行无害。
enum WakeRecoveryPlan {
    static let delays: [Double] = [0, 0.2, 0.8]
}
