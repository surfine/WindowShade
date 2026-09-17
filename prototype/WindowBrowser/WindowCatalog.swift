// 窗口目录：把已管理窗口（折叠会话、置顶会话）与普通窗口发现结果按原窗口身份
// 合并成只读投影。目录不是状态所有者：折叠仍归原控制器，置顶仍归
// PinnedPreviewController。
//
// 合并/去重/失败保留全部是纯逻辑，可直接被测试；系统查询通过描述值输入。

import Foundation
import CoreGraphics

final class WindowCatalog {
    private let allocator: WindowIdentityAllocator

    private var managedByKey: [WindowKey: ManagedWindowDescriptor] = [:]
    private var discoveredByKey: [WindowKey: DiscoveredWindowDescriptor] = [:]
    private var bundleIdentifierByKey: [WindowKey: String] = [:]
    private var appNameByKey: [WindowKey: String] = [:]
    private var revisionByKey: [WindowKey: UInt64] = [:]
    private var revisionCounter: UInt64 = 1
    /// 发布结果缓存：读路径（records(forPID:)、record(for:)）不重复做全量合并与排序。
    private var publishedCache: [WindowRecord]?

    /// 最近一次普通窗口查询失败/超时的应用：保留已有记录，但标注待刷新。
    private(set) var refreshPendingPIDs: Set<pid_t> = []

    init(allocator: WindowIdentityAllocator = WindowIdentityAllocator()) {
        self.allocator = allocator
    }

    var identityAllocator: WindowIdentityAllocator { allocator }

    // MARK: 写入

    /// 已管理窗口的全局快照。快照是权威的：不在快照里的窗口不再算“已管理”，
    /// 但如果普通发现仍能看到它，会作为普通窗口继续保留。
    @discardableResult
    func applyManaged(_ descriptors: [ManagedWindowDescriptor]) -> [WindowRecord] {
        publishedCache = nil
        var next: [WindowKey: ManagedWindowDescriptor] = [:]
        for descriptor in descriptors {
            let key = allocator.windowKey(pid: descriptor.pid,
                                          bundleIdentifier: descriptor.bundleIdentifier,
                                          originalWindowID: descriptor.originalWindowID)
            bundleIdentifierByKey[key] = descriptor.bundleIdentifier
            if !descriptor.appName.isEmpty { appNameByKey[key] = descriptor.appName }
            next[key] = descriptor
        }
        managedByKey = next
        return publish()
    }

    /// 普通窗口查询结果。失败与超时保留旧记录；成功空结果会清掉该应用的
    /// 普通发现记录（已管理记录保留）。
    @discardableResult
    func applyDiscovery(_ result: WindowBrowserFetchResult<[DiscoveredWindowDescriptor]>,
                        pid: pid_t) -> [WindowRecord] {
        publishedCache = nil
        switch result {
        case .failure, .timedOut:
            refreshPendingPIDs.insert(pid)
            return publish()
        case .success, .empty:
            refreshPendingPIDs.remove(pid)
        case .partial(_, let failures):
            refreshPendingPIDs.remove(pid)
            refreshPendingPIDs.formUnion(failures)
        }

        let existingKeys = discoveredByKey.keys.filter { $0.application.pid == pid }
        for key in existingKeys { discoveredByKey.removeValue(forKey: key) }

        let descriptors: [DiscoveredWindowDescriptor]
        switch result {
        case .success(let value), .partial(let value, _): descriptors = value
        case .empty: descriptors = []
        case .failure, .timedOut: descriptors = []
        }

        for descriptor in descriptors {
            let bundleIdentifier = descriptor.bundleIdentifier
                ?? bundleIdentifierByKey.first(where: { $0.key.application.pid == pid })?.value
                ?? ""
            let key = allocator.windowKey(pid: descriptor.pid,
                                          bundleIdentifier: bundleIdentifier,
                                          originalWindowID: descriptor.originalWindowID)
            if !bundleIdentifier.isEmpty {
                bundleIdentifierByKey[key] = bundleIdentifier
            }
            if let appName = descriptor.appName, !appName.isEmpty {
                appNameByKey[key] = appName
            }
            discoveredByKey[key] = descriptor
        }
        return publish()
    }

    /// 应用终止：清理其全部元数据。调用方负责同时清图像与 AX 引用。
    @discardableResult
    func removeApplication(pid: pid_t) -> [WindowRecord] {
        publishedCache = nil
        allocator.noteApplicationTerminated(pid: pid)
        for key in managedByKey.keys.filter({ $0.application.pid == pid }) {
            managedByKey.removeValue(forKey: key)
        }
        for key in discoveredByKey.keys.filter({ $0.application.pid == pid }) {
            discoveredByKey.removeValue(forKey: key)
        }
        for key in bundleIdentifierByKey.keys.filter({ $0.application.pid == pid }) {
            bundleIdentifierByKey.removeValue(forKey: key)
            appNameByKey.removeValue(forKey: key)
            revisionByKey.removeValue(forKey: key)
        }
        refreshPendingPIDs.remove(pid)
        return publish()
    }

    /// 只在一件事被确证时调用：窗口销毁通知、应用终止、成功重新核验。
    /// 一次扫描失败/暂时缺失不得调用它，否则会删除恢复记录或让旧图像泄漏给新窗口。
    @discardableResult
    func confirmWindowDestroyed(_ key: WindowKey) -> [WindowRecord] {
        publishedCache = nil
        allocator.confirmWindowDestroyed(key)
        managedByKey.removeValue(forKey: key)
        discoveredByKey.removeValue(forKey: key)
        bundleIdentifierByKey.removeValue(forKey: key)
        appNameByKey.removeValue(forKey: key)
        revisionByKey.removeValue(forKey: key)
        return publish()
    }

    func clear() {
        publishedCache = nil
        managedByKey.removeAll()
        discoveredByKey.removeAll()
        bundleIdentifierByKey.removeAll()
        appNameByKey.removeAll()
        revisionByKey.removeAll()
        refreshPendingPIDs.removeAll()
    }

    // MARK: 读取

    func records(forPID pid: pid_t) -> [WindowRecord] {
        publish().filter { $0.key.application.pid == pid }
    }

    func record(for key: WindowKey) -> WindowRecord? {
        publish().first { $0.key == key }
    }

    func windowKey(pid: pid_t, bundleIdentifier: String,
                   originalWindowID: CGWindowID) -> WindowKey {
        allocator.windowKey(pid: pid, bundleIdentifier: bundleIdentifier,
                            originalWindowID: originalWindowID)
    }

    func isRefreshPending(pid: pid_t) -> Bool { refreshPendingPIDs.contains(pid) }

    // MARK: 合并

    @discardableResult
    func publish() -> [WindowRecord] {
        if let publishedCache { return publishedCache }
        var records: [WindowRecord] = []
        let allKeys = Set(managedByKey.keys).union(discoveredByKey.keys)
        for key in allKeys {
            let managed = managedByKey[key]
            let discovered = discoveredByKey[key]
            let bundle = bundleIdentifierByKey[key] ?? ""
            let appName = appNameByKey[key] ?? bundle
            let title: String
            if let managed, !managed.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = managed.title
            } else if let discovered, let discoveredTitle = discovered.title,
                      !discoveredTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                title = discoveredTitle
            } else {
                title = managed?.title ?? ""
            }

            let logicalFrame = managed?.logicalFrame ?? discovered?.frame
            let placement: WindowBrowserPlacementSource
            if let managed {
                placement = managed.placementSource
            } else {
                placement = .liveDiscovery
            }
            let shade: WindowBrowserShadeState
            if let managed {
                shade = managed.shadeState
            } else {
                shade = .normal
            }
            let pin = managed?.pinState ?? .none
            let visibility: WindowBrowserSystemVisibility
            if let managed, managed.systemVisibility != .unknown {
                visibility = managed.systemVisibility
            } else if let discovered {
                if discovered.isMinimized { visibility = .minimized }
                else if discovered.isOnScreen { visibility = .onScreen }
                else { visibility = .offScreen }
            } else {
                visibility = .unknown
            }
            var capabilities: WindowBrowserCapabilities = []
            capabilities.formUnion(managed?.capabilities ?? [])
            capabilities.formUnion(discovered?.capabilities ?? [])
            if managed != nil {
                capabilities.formUnion(.activate)
                if shade == .folded { capabilities.formUnion(.unfold) }
            }
            let confidence = max(managed?.confidence ?? .provisional,
                                 discovered?.confidence ?? .provisional)
            let isMinimized = managed?.isMinimized ?? discovered?.isMinimized ?? false
            let isOnScreen = managed?.isOnScreen ?? discovered?.isOnScreen ?? false
            let isFoldedOffscreen = shade == .folded

            let signature = "\(title)|\(logicalFrame.map { "\($0)" } ?? "-")|\(visibility.rawValue)|\(shade.rawValue)|\(pin.rawValue)|\(capabilities.rawValue)|\(isMinimized)|\(isOnScreen)"
            let previousRevision = revisionByKey[key] ?? 0
            let metadataRevision: UInt64
            if revisionSignatureByKey[key] == signature, previousRevision != 0 {
                metadataRevision = previousRevision
            } else {
                metadataRevision = nextRevision()
            }
            revisionSignatureByKey[key] = signature
            revisionByKey[key] = metadataRevision

            records.append(WindowRecord(key: key,
                                        bundleIdentifier: bundle,
                                        appName: appName,
                                        title: title,
                                        logicalFrame: logicalFrame,
                                        placementSource: placement,
                                        systemVisibility: visibility,
                                        shadeState: shade,
                                        pinState: pin,
                                        capabilities: capabilities,
                                        confidence: confidence,
                                        metadataRevision: metadataRevision,
                                        isMinimized: isMinimized,
                                        isOnScreen: isOnScreen,
                                        isFoldedOffscreen: isFoldedOffscreen,
                                        isManaged: managed != nil))
        }
        // 规范化字符串（大小写/宽度/变音）只算一次，不让排序比较器反复做折叠。
        var sortKeys: [WindowKey: (app: String, title: String)] = [:]
        sortKeys.reserveCapacity(records.count)
        for record in records {
            sortKeys[record.key] = (record.sortAppName, record.sortTitle)
        }
        records.sort { lhs, rhs in
            let left = sortKeys[lhs.key] ?? ("", "")
            let right = sortKeys[rhs.key] ?? ("", "")
            if left.app != right.app { return left.app < right.app }
            if left.title != right.title { return left.title < right.title }
            return lhs.key < rhs.key
        }
        publishedCache = records
        return records
    }

    private var revisionSignatureByKey: [WindowKey: String] = [:]

    private func nextRevision() -> UInt64 {
        revisionCounter &+= 1
        return revisionCounter
    }
}
