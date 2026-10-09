import Foundation

/// A missing session dictionary is not an unlocked session. Only the caller's current,
/// logged-in console session may use unlocked desktop capture.
enum SessionLockState: Equatable {
    case unknown, unlocked, locked

    static func resolve(locked: Bool?, onConsole: Bool?, loginDone: Bool?, dictionaryPresent: Bool) -> Self {
        guard dictionaryPresent else { return .unknown }
        // On macOS the lock key can be absent when unlocked. Both positive public
        // session flags are required in that case; a partial dictionary is unknown.
        guard onConsole == true, loginDone == true else { return .unknown }
        if locked == true { return .locked }
        return .unlocked
    }

    /// 只有确知已锁才算锁着；未知不算。刷脸扫描每一帧都按这个重查。
    var isReallyLocked: Bool { self == .locked }
}
