import Foundation

// 启动台「卸载 App」的扫描计划（纯模型）。给定 bundleID 与注入的文件系统视图，
// 算出该 App 在用户域的关联文件清单——界面勾选、确认后由执行器逐条移废纸篓。
// 目录清单与"共用数据保护"思路参考 Mole（GPL-3.0，只借思路）；实现原创 Swift。
//
// 规矩：
// - 只扫用户域（~/Library 下的固定几处）；不动 /Library、系统域与任何需要管理员的路径。
// - 按 bundleID 精确匹配；Group Containers 只认 group.<bundleID>，他 App 共用的前缀自动排除。
// - 三条硬拦截：根/空路径、/System 域、WindowShade 自己。
// - 这里只算计划，不碰文件；删不删、删哪些由界面勾选决定。

enum WS2AppUninstallGroup: String, CaseIterable, Sendable {
    case app = "app"
    case preferences = "preferences"
    case appSupport = "appSupport"
    case caches = "caches"
    case savedState = "savedState"
    case webKit = "webkit"
    case cookies = "cookies"
    case logs = "logs"
    case appScripts = "appScripts"
    case httpStorage = "httpStorage"
    case container = "container"
    case groupContainer = "groupContainer"
    case launchAgent = "launchAgent"
}

struct WS2AppUninstallItem: Equatable, Sendable {
    let path: String
    let group: WS2AppUninstallGroup
    let bytes: Int64
    let isAppBundle: Bool
}

/// 文件系统视图：真实实现读磁盘，测试给内存假象。全部路径为绝对 POSIX 串。
protocol WS2AppUninstallFileSystem: Sendable {
    func isDirectory(_ path: String) -> Bool
    func fileExists(_ path: String) -> Bool
    func namesInDirectory(_ path: String) -> [String]
    func dataOfFile(_ path: String) -> Data?
    /// 文件或目录（递归）的字节数；拿不到给 0。
    func bytes(_ path: String) -> Int64
}

enum WS2AppUninstallPlan: Sendable {

    enum Block: Equatable, Sendable {
        case none
        case systemPath
        case selfApp
        case notAnApp
    }

    struct Result: Equatable, Sendable {
        /// 被拦截的原因（.none = 未拦截，可以走）。
        var block: Block
        var items: [WS2AppUninstallItem]
        /// App 本体那一条（方便界面置顶显示）。
        var appItem: WS2AppUninstallItem? { items.first { $0.isAppBundle } }
        var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    }

    static func isBlocked(appPath: String, selfBundlePath: String) -> Block {
        let trimmed = appPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1, trimmed.hasPrefix("/") else { return .notAnApp }
        if trimmed == "/" { return .systemPath }
        if trimmed.hasPrefix("/System/") || trimmed == "/System" { return .systemPath }
        if selfBundlePath.hasPrefix("/"),
           URL(fileURLWithPath: trimmed).standardizedFileURL.path == URL(fileURLWithPath: selfBundlePath).standardizedFileURL.path {
            return .selfApp
        }
        if !trimmed.hasSuffix(".app") { return .notAnApp }
        return .none
    }

    /// 算卸载计划。`home` 是用户家目录（真实接入传 ~ 展开值）；`otherBundleIDs` 是其余已安装 App 的
    /// bundleID（共用保护用）；`selfBundlePath` 是 WindowShade 自己（拦截自卸）。
    static func scan(bundleID: String, appPath: String, home: String,
                     otherBundleIDs: [String], selfBundlePath: String,
                     fs: any WS2AppUninstallFileSystem) -> Result {
        var result = Result(block: .none, items: [])
        guard !bundleID.isEmpty, !appPath.isEmpty else {
            result.block = .notAnApp
            return result
        }
        let block = isBlocked(appPath: appPath, selfBundlePath: selfBundlePath)
        guard block == .none else {
            result.block = block
            return result
        }
        guard fs.fileExists(appPath) else {
            result.block = .notAnApp
            return result
        }

        var items: [WS2AppUninstallItem] = []
        items.append(WS2AppUninstallItem(path: appPath, group: .app,
                                         bytes: fs.bytes(appPath), isAppBundle: true))

        let library = home + "/Library"
        func hasDir(_ group: String) -> Bool { fs.isDirectory(library + "/" + group) }
        func addFile(_ group: WS2AppUninstallGroup, _ path: String) {
            guard fs.fileExists(path) else { return }
            items.append(WS2AppUninstallItem(path: path, group: group, bytes: fs.bytes(path), isAppBundle: false))
        }
        func addDir(_ group: WS2AppUninstallGroup, _ path: String) {
            guard fs.isDirectory(path) else { return }
            items.append(WS2AppUninstallItem(path: path, group: group, bytes: fs.bytes(path), isAppBundle: false))
        }

        // 按名字精确匹配 bundleID 的常规几处。
        addFile(.preferences, "\(library)/Preferences/\(bundleID).plist")
        addDir(.appSupport, "\(library)/Application Support/\(bundleID)")
        addDir(.caches, "\(library)/Caches/\(bundleID)")
        addDir(.savedState, "\(library)/Saved Application State/\(bundleID).savedState")
        addDir(.webKit, "\(library)/WebKit/\(bundleID)")
        addFile(.cookies, "\(library)/Cookies/\(bundleID).binarycookies")
        addDir(.logs, "\(library)/Logs/\(bundleID)")
        if hasDir("Application Scripts") { addDir(.appScripts, "\(library)/Application Scripts/\(bundleID)") }
        addDir(.httpStorage, "\(library)/HTTPStorages/\(bundleID)")
        addDir(.container, "\(library)/Containers/\(bundleID)")

        // Group Containers：只认 group.<bundleID>；他 App 的 bundleID 是本 ID 的真前缀时视为共用，排除。
        let shared = otherBundleIDs.contains { other in
            other != bundleID && isPrefixBundle(other, of: bundleID)
        }
        if !shared { addDir(.groupContainer, "\(library)/Group Containers/group.\(bundleID)") }

        // 用户 Launch Agents：plist 内容提到 bundleID/App 路径，或文件名带 bundleID（脚本式 agent 的惯例）。
        let agentsDir = "\(library)/LaunchAgents"
        if fs.isDirectory(agentsDir) {
            for name in fs.namesInDirectory(agentsDir) where name.hasSuffix(".plist") {
                let path = "\(agentsDir)/\(name)"
                if name.contains(bundleID) { addFile(.launchAgent, path); continue }
                guard let data = fs.dataOfFile(path),
                      let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
                else { continue }
                if text.contains(bundleID) || (!appPath.isEmpty && text.contains(appPath)) {
                    addFile(.launchAgent, path)
                }
            }
        }

        result.items = items.sorted { $0.group == .app ? false : $1.group == .app ? true : $0.path < $1.path }
        return result
    }

    /// 反 DNS 前缀共用判定：`com.foo` 是 `com.foo.bar` 的前缀（按段），`com.foobar` 不是。
    static func isPrefixBundle(_ prefix: String, of bundleID: String) -> Bool {
        guard prefix != bundleID, !prefix.isEmpty else { return false }
        let a = prefix.split(separator: ".").map(String.init)
        let b = bundleID.split(separator: ".").map(String.init)
        guard a.count < b.count else { return false }
        return zip(a, b).allSatisfy { $0 == $1 }
    }
}
