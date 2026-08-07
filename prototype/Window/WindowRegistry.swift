// 窗口元数据短 TTL 缓存：pid -> (app 名, bundleID)。
// app 名与 bundleID 在会话内不会变化，缓存 1s 即可；高频路径（windowPolicy
// 解析、日志、菜单、置顶预览）不再反复构造 NSRunningApplication。
// 窗口帧与标题分别由 WindowListCache / ShadeState 覆盖，这里不重复缓存。

import Cocoa

final class WindowRegistry {
    static let shared = WindowRegistry()

    private struct AppEntry {
        let name: String
        let bundleID: String
        let at: CFAbsoluteTime
    }

    private let lock = NSLock()
    private let ttl: TimeInterval = 1.0
    private var apps: [pid_t: AppEntry] = [:]

    func appInfo(pid: pid_t) -> (name: String, bundleID: String)? {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        defer { lock.unlock() }
        guard let entry = apps[pid], now - entry.at < ttl else {
            if apps[pid] != nil { apps.removeValue(forKey: pid) }
            return nil
        }
        return (entry.name, entry.bundleID)
    }

    func cacheAppInfo(pid: pid_t, name: String, bundleID: String) {
        lock.lock()
        apps[pid] = AppEntry(name: name, bundleID: bundleID, at: CFAbsoluteTimeGetCurrent())
        if apps.count > 128 {
            let now = CFAbsoluteTimeGetCurrent()
            apps = apps.filter { now - $0.value.at < ttl }
        }
        lock.unlock()
    }
}
