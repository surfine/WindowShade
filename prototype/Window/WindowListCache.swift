// WindowServer 窗口列表：全量列表短 TTL 缓存与单窗口实时查询。

import Cocoa

// 全量窗口列表的短 TTL 缓存。
// 折叠/展开事务内部会多次触发 CGWindowListCopyWindowInfo 全量枚举（AX→CGWindowID
// 匹配、在屏 ID 集合、app 窗口计数、标题栏带预过滤……），同一事务里它们读到的
// 应该是同一份列表，只需向 WindowServer 要一次。TTL 150ms 覆盖单次事务内的全部
// 重复读取。windowID(of:) 优先读取元素自身的 ID；这些快照仅用于发现和兼容匹配，
// 不作为动作提交、移动或隐藏完成的实时证明。
// 单窗口查询 cgWindowInfo(id:) 不经过这里：watchdog 和折叠验证必须看到实时值。
// 线程安全：PinnedPreview 的后台 AX 队列也会走 windowID(of:)，缓存读写用锁保护。
final class WindowListCache {
    static let shared = WindowListCache()

    private struct Snapshot {
        let windows: [[String: Any]]
        let byID: [CGWindowID: [String: Any]]
        let byPID: [pid_t: [[String: Any]]]
    }

    private struct Entry {
        let snapshot: Snapshot
        let at: CFAbsoluteTime
    }

    private enum Kind {
        case onScreen   // [.optionOnScreenOnly, .excludeDesktopElements]
        case all        // [.optionAll, .excludeDesktopElements]
    }

    private let lock = NSLock()
    private let ttl: TimeInterval = 0.15
    private var onScreenEntry: Entry?
    private var allEntry: Entry?
    // 多个 AX/缩略图队列可能在同一 TTL 边界同时 miss。只允许每种快照有一个
    // WindowServer 枚举，其余调用等待同一结果，避免高峰期重复做昂贵 IPC。
    private var onScreenRefresh: DispatchSemaphore?
    private var allRefresh: DispatchSemaphore?

    func onScreenWindows() -> [[String: Any]] {
        snapshot(.onScreen).windows
    }

    func onScreenWindows(ofPID pid: pid_t) -> [[String: Any]] {
        snapshot(.onScreen).byPID[pid] ?? []
    }

    func allWindows() -> [[String: Any]] {
        snapshot(.all).windows
    }

    func allWindows(ofPID pid: pid_t) -> [[String: Any]] {
        snapshot(.all).byPID[pid] ?? []
    }

    // 拥有至少一个窗口的进程集合。用于在昂贵的 AX 枚举之前筛掉纯后台进程：
    // 一个窗口都没有的进程，appWindows(pid:) 只可能返回空数组，却要为此付一次
    // 同步 AX 往返——目标进程无响应时最坏会卡满 2s 消息超时。
    func pidsWithWindows() -> Set<pid_t> {
        Set(snapshot(.all).byPID.keys)
    }

    func onScreenIDs() -> Set<CGWindowID> {
        let snapshot = snapshot(.onScreen)
        var ids = Set<CGWindowID>()
        ids.reserveCapacity(snapshot.windows.count)
        for info in snapshot.windows {
            if let n = info[kCGWindowNumber as String] as? NSNumber {
                ids.insert(CGWindowID(n.uint32Value))
            }
        }
        return ids
    }

    func isOnScreen(_ id: CGWindowID) -> Bool {
        snapshot(.onScreen).byID[id] != nil
    }

    private func snapshot(_ kind: Kind) -> Snapshot {
        while true {
            let now = CFAbsoluteTimeGetCurrent()
            lock.lock()
            let entry = kind == .onScreen ? onScreenEntry : allEntry
            if let entry, now - entry.at < ttl {
                let hit = entry.snapshot
                lock.unlock()
                return hit
            }

            let refresh = kind == .onScreen ? onScreenRefresh : allRefresh
            if let refresh {
                lock.unlock()
                // 另一个调用正在锁外访问 WindowServer；拿到结果后重新检查 TTL。
                refresh.wait()
                continue
            }

            let gate = DispatchSemaphore(value: 0)
            if kind == .onScreen {
                onScreenRefresh = gate
            } else {
                allRefresh = gate
            }
            lock.unlock()

            // 锁外取数：WindowServer 枚举可能耗时，不阻塞缓存读写锁。
            let options: CGWindowListOption = kind == .onScreen
                ? [.optionOnScreenOnly, .excludeDesktopElements]
                : [.optionAll, .excludeDesktopElements]
            let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
            let fresh = build(windows)

            lock.lock()
            let finishedAt = CFAbsoluteTimeGetCurrent()
            if kind == .onScreen {
                onScreenEntry = Entry(snapshot: fresh, at: finishedAt)
                onScreenRefresh = nil
            } else {
                allEntry = Entry(snapshot: fresh, at: finishedAt)
                allRefresh = nil
            }
            lock.unlock()
            gate.signal()
            return fresh
        }
    }

    private func build(_ windows: [[String: Any]]) -> Snapshot {
        var byID: [CGWindowID: [String: Any]] = [:]
        var byPID: [pid_t: [[String: Any]]] = [:]
        for info in windows {
            if let n = info[kCGWindowNumber as String] as? NSNumber {
                byID[CGWindowID(n.uint32Value)] = info
            }
            if let p = info[kCGWindowOwnerPID as String] as? NSNumber {
                byPID[pid_t(p.int32Value), default: []].append(info)
            }
        }
        return Snapshot(windows: windows, byID: byID, byPID: byPID)
    }
}

func cgWindowInfo(_ id: CGWindowID) -> [String: Any]? {
    // 单窗口直连查询，不走 WindowListCache：watchdog 追踪窗口移动、折叠验证、
    // SLS alpha 读回都需要实时值，且这里每次只取一个窗口，本来就很廉价。
    let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]]
    return info?.first
}

func cgWindowLayer(_ id: CGWindowID) -> Int32? {
    guard let raw = cgWindowInfo(id)?[kCGWindowLayer as String] else { return nil }
    if let number = raw as? NSNumber { return number.int32Value }
    if let int = raw as? Int { return Int32(int) }
    return nil
}

func isDesktopWidgetWindow(id: CGWindowID) -> Bool {
    let desktopWidgetLayer: Int32 = -2147483601
    let layer = cgWindowLayer(id)
    return layer == desktopWidgetLayer
}
