import Foundation

/// 私人 App 名单：三处共用的一份名单（有人在看时收起、离开就锁、专注时收进刘海）。
/// 只存用户自己选的 bundle ID，默认空；不读别的。变化时发 `didChange` 通知。
/// 本类型不执行任何收起动作，只回答“这个 App 在不在名单里”。
final class PrivateAppList: @unchecked Sendable {
    static let defaultsKey = "PrivateApps.bundleIDs"
    static let didChange = Notification.Name("WindowShade.PrivateAppList.didChange")
    static let shared = PrivateAppList()

    private let defaults: UserDefaults
    private let center: NotificationCenter
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, center: NotificationCenter = .default) {
        self.defaults = defaults
        self.center = center
    }

    /// 当前名单（按加入顺序，已去重）。
    var bundleIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return Self.normalized(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    var isEmpty: Bool { bundleIDs.isEmpty }

    func contains(bundleID: String?) -> Bool {
        guard let key = Self.canonical(bundleID) else { return false }
        return bundleIDs.contains { $0.lowercased() == key }
    }

    /// 只留下名单里的 App 的窗口。名单为空或取不到 bundle ID 时，不留。
    func filterPrivate<T>(_ windows: [T], bundleID: (T) -> String?) -> [T] {
        let ids = Set(bundleIDs.map { $0.lowercased() })
        if ids.isEmpty { return [] }
        return windows.filter { window in
            guard let key = Self.canonical(bundleID(window)) else { return false }
            return ids.contains(key)
        }
    }

    /// 加入一个 App；已在名单里或为空串返回 false，不发通知。
    @discardableResult
    func add(bundleID: String) -> Bool {
        guard let trimmed = Self.trimmed(bundleID) else { return false }
        lock.lock()
        let current = Self.normalized(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
        if current.contains(where: { $0.lowercased() == trimmed.lowercased() }) {
            lock.unlock(); return false
        }
        defaults.set(current + [trimmed], forKey: Self.defaultsKey)
        lock.unlock()
        center.post(name: Self.didChange, object: nil)
        return true
    }

    /// 移出一个 App；不在名单里返回 false，不发通知。
    @discardableResult
    func remove(bundleID: String) -> Bool {
        guard let key = Self.canonical(bundleID) else { return false }
        lock.lock()
        let current = Self.normalized(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
        let next = current.filter { $0.lowercased() != key }
        if next.count == current.count { lock.unlock(); return false }
        defaults.set(next, forKey: Self.defaultsKey)
        lock.unlock()
        center.post(name: Self.didChange, object: nil)
        return true
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private static func canonical(_ raw: String?) -> String? { trimmed(raw)?.lowercased() }

    private static func normalized(_ raw: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for item in raw {
            guard let value = trimmed(item), seen.insert(value.lowercased()).inserted else { continue }
            out.append(value)
        }
        return out
    }
}
