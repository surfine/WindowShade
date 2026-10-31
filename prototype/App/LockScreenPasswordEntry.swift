import Carbon
import Cocoa

/// 在系统锁屏的密码框里替你打登录密码（D11 第 6 步，face-unlock 硬要求 2、5、7）。
///
/// 做法照 Glance（MIT，jonnyoo/glance）与 BLEUnlock 的思路：锁屏时 loginwindow 的密码框拿着键盘焦点，
/// 往 HID 层发合成的按键事件（每个字一次 keyDown/keyUp，`keyboardSetUnicodeString`），最后一下回车。
/// 这里是照思路自写，没有拷两边的代码（BLEUnlock 没有许可证）。需要辅助功能权限（AXIsProcessTrusted）。
///
/// 只在闸门（`FaceAutofill.decide`）给出 `.autofill` 之后、由 `FaceAutofillController` 调用；每打一个字之前都再查一次
/// `stillValid`（锁着、还是这一次锁屏、密码框还收），任何一项不成立就停，回车不发。
/// 密码只在 `UnlockSecret.withBytes` 的闭包里解成 UTF-16，打完把这份覆写清零；不写日志、不拼成 String。
@MainActor protocol LockScreenPasswordTyping: AnyObject {
    /// 能不能打（有没有辅助功能权限）。
    var canType: Bool { get }
    /// 打完返回 true；中途 `stillValid` 不成立、或解码失败返回 false（回车没发）。
    func type(_ secret: UnlockSecret, stillValid: @escaping @MainActor () -> Bool) async -> Bool
}

/// 系统锁屏此刻能不能收密码。
@MainActor enum LockScreenPasswordField {
    /// 只认确知锁着、主屏亮着、并且有进程开着安全输入（loginwindow 的密码框拿到焦点时会开）。
    /// 安全输入是旁证：别的 App 的密码框也会开它，所以一定和「确知锁着」一起用。真机上要实测（见 F4 清单）。
    static func state(lock: SessionLockState) -> FaceAutofill.LockUI {
        guard lock.isReallyLocked else { return .notReady }
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return .notReady }
        return IsSecureEventInputEnabled() ? .acceptsPassword : .notReady
    }
}

@MainActor final class CGEventPasswordTyper: LockScreenPasswordTyping {
    /// 两个字之间隔一点，免得 loginwindow 丢字。
    static let keySpacing: Duration = .milliseconds(12)

    var canType: Bool { AXIsProcessTrusted() }

    func type(_ secret: UnlockSecret, stillValid: @escaping @MainActor () -> Bool) async -> Bool {
        guard canType, stillValid() else { return false }
        var units: [UInt16] = secret.withBytes { buffer in
            var iterator = buffer.makeIterator()
            var codec = UTF8()
            var out: [UInt16] = []
            out.reserveCapacity(buffer.count)
            while true {
                switch codec.decode(&iterator) {
                case .scalarValue(let scalar): UTF16.encode(scalar) { out.append($0) }
                case .emptyInput: return out
                case .error: return []
                }
            }
        }
        defer {
            units.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress { _ = memset_s(base, raw.count, 0, raw.count) }
            }
            units.removeAll()
        }
        guard !units.isEmpty, let source = CGEventSource(stateID: .hidSystemState) else { return false }
        var index = 0
        while index < units.count {
            guard stillValid() else { return false }
            // 代理对（emoji 等）两个单元一起发。
            let width = UTF16.isLeadSurrogate(units[index]) && index + 1 < units.count ? 2 : 1
            var chunk = Array(units[index..<(index + width)])
            postUnicode(&chunk, source: source)
            chunk.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress { _ = memset_s(base, raw.count, 0, raw.count) }
            }
            index += width
            try? await Task.sleep(for: Self.keySpacing)
        }
        guard stillValid() else { return false }
        postKey(CGKeyCode(kVK_Return), source: source)
        return true
    }

    private func postUnicode(_ chunk: inout [UInt16], source: CGEventSource) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            chunk.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            event.post(tap: .cghidEventTap)
        }
    }

    private func postKey(_ key: CGKeyCode, source: CGEventSource) {
        CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
    }
}
