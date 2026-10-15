// 窗口元数据短 TTL 缓存：pid -> (app 名, bundleID)。
// app 名与 bundleID 在会话内不会变化，缓存 1s 即可；高频路径（windowPolicy
// 解析、日志、菜单、置顶预览）不再反复构造 NSRunningApplication。
// 窗口帧与标题分别由 WindowListCache / ShadeState 覆盖，这里不重复缓存。

import Cocoa
import Synchronization

/// `apps` 放在 Mutex 里，可以从任意线程调用。
// 规格 M3：去掉 @unchecked Sendable。
final class WindowRegistry: Sendable {
    static let shared = WindowRegistry()

    private struct AppEntry {
        let name: String
        let bundleID: String
        let at: CFAbsoluteTime
    }

    private let ttl: TimeInterval = 1.0
    private let apps = Mutex<[pid_t: AppEntry]>([:])

    func appInfo(pid: pid_t) -> (name: String, bundleID: String)? {
        let now = CFAbsoluteTimeGetCurrent()
        return apps.withLock { apps in
            guard let entry = apps[pid], now - entry.at < ttl else {
                if apps[pid] != nil { apps.removeValue(forKey: pid) }
                return nil
            }
            return (entry.name, entry.bundleID)
        }
    }

    func cacheAppInfo(pid: pid_t, name: String, bundleID: String) {
        apps.withLock { apps in
            apps[pid] = AppEntry(name: name, bundleID: bundleID, at: CFAbsoluteTimeGetCurrent())
            if apps.count > 128 {
                let now = CFAbsoluteTimeGetCurrent()
                apps = apps.filter { now - $0.value.at < ttl }
            }
        }
    }
}
