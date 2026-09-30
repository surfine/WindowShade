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
}
