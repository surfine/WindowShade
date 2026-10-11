// 卸载扫描计划（Core/WS2AppUninstallPlan.swift）：内存假文件系统，全离线。
import Foundation

// 内存假 FS：路径→条目。目录=有子路径记录；文件=有数据记录。
final class FakeFS: WS2AppUninstallFileSystem, @unchecked Sendable {
    private(set) var dirs = Set<String>()
    private(set) var files = [String: Data]()
    private var dirBytes: [String: Int64] = [:]

    private func ancestors(of path: String) -> [String] {
        var parts = path.split(separator: "/").map(String.init)
        parts.removeLast()
        var out: [String] = []
        var prefix = ""
        for part in parts {
            prefix += "/" + part
            out.append(prefix)
        }
        return out
    }
    func mkdir(_ path: String) {
        dirs.insert(path)
        for ancestor in ancestors(of: path) { dirs.insert(ancestor) }
    }
    func mkfile(_ path: String, bytes: Int64, content: String = "x") {
        files[path] = Data(content.utf8)
        dirBytes[path] = bytes
        for ancestor in ancestors(of: path) { dirs.insert(ancestor) }
    }
    func isDirectory(_ path: String) -> Bool { dirs.contains(path) }
    func fileExists(_ path: String) -> Bool { files[path] != nil || dirs.contains(path) }
    func namesInDirectory(_ path: String) -> [String] {
        dirs.union(files.keys).compactMap { full in
            guard full.hasPrefix(path + "/") else { return nil }
            let rest = String(full.dropFirst(path.count + 1))
            return rest.contains("/") ? nil : rest
        }.sorted()
    }
    func dataOfFile(_ path: String) -> Data? { files[path] }
    func bytes(_ path: String) -> Int64 {
        if let file = files[path] { return dirBytes[path] ?? Int64(file.count) }
        guard dirs.contains(path) else { return 0 }
        let direct = dirBytes[path] ?? 0
        let prefix = path + "/"
        let directChildren = (Set(files.keys).union(dirs)).filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }
        return direct + directChildren.reduce(Int64(0)) { $0 + bytes($1) }
    }
}

@main struct WS2AppUninstallPlanTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        if condition { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }

    static let home = "/Users/tester"
    static let appPath = "/Applications/Demo.app"
    static let bid = "com.demo.app"

    static func makeFS() -> FakeFS {
        let fs = FakeFS()
        fs.mkdir(appPath)
        fs.mkfile("\(appPath)/Contents/MacOS/Demo", bytes: 4_000_000)
        fs.mkfile("\(home)/Library/Preferences/\(bid).plist", bytes: 512)
        fs.mkdir("\(home)/Library/Application Support/\(bid)")
        fs.mkfile("\(home)/Library/Application Support/\(bid)/data.db", bytes: 900_000)
        fs.mkdir("\(home)/Library/Caches/\(bid)")
        fs.mkfile("\(home)/Library/Saved Application State/\(bid).savedState/window.data", bytes: 4096)
        fs.mkfile("\(home)/Library/Cookies/\(bid).binarycookies", bytes: 128)
        fs.mkdir("\(home)/Library/HTTPStorages/\(bid)")
        fs.mkdir("\(home)/Library/Containers/\(bid)")
        fs.mkdir("\(home)/Library/Group Containers/group.\(bid)")
        fs.mkdir("\(home)/Library/LaunchAgents")
        return fs
    }

    static func main() {
        let selfPath = "/Applications/WindowShade.app"

        // 正常扫描：各处关联都进计划，App 本体置顶
        do {
            let fs = makeFS()
            fs.mkfile("\(home)/Library/LaunchAgents/com.demo.app.agent.plist", bytes: 64,
                      content: "<string>/Applications/Demo.app/Contents/MacOS/Demo</string>")
            let r = WS2AppUninstallPlan.scan(bundleID: bid, appPath: appPath, home: home,
                                             otherBundleIDs: [], selfBundlePath: selfPath, fs: fs)
            expect(r.block == .none, "clean app is not blocked")
            expect(r.items.contains { $0.isAppBundle && $0.path == appPath }, "app bundle included")
            expect(r.items.contains { $0.group == .preferences && $0.path.hasSuffix(".plist") }, "preferences included")
            expect(r.items.contains { $0.group == .appSupport }, "app support included")
            expect(r.items.contains { $0.group == .savedState }, "saved state included")
            expect(r.items.contains { $0.group == .cookies }, "cookies included")
            expect(r.items.contains { $0.group == .container }, "container included")
            expect(r.items.contains { $0.group == .groupContainer }, "group container included when not shared")
            expect(r.items.contains { $0.group == .launchAgent }, "launch agent with matching content included")
            expect(r.appItem != nil && r.totalBytes > 4_000_000, "totals computed")
        }

        // 共用保护：他 App 的 bundleID 是本 ID 前缀时，Group Containers 排除
        do {
            let fs = makeFS()
            let r = WS2AppUninstallPlan.scan(bundleID: bid, appPath: appPath, home: home,
                                             otherBundleIDs: ["com.demo"], selfBundlePath: selfPath, fs: fs)
            expect(r.items.contains { $0.group == .container }, "own container stays")
            expect(!r.items.contains { $0.group == .groupContainer }, "shared group container excluded")
        }
        // 前缀按段比：com.demox 不是 com.demo.app 的前缀
        do {
            let fs = makeFS()
            let r = WS2AppUninstallPlan.scan(bundleID: bid, appPath: appPath, home: home,
                                             otherBundleIDs: ["com.demox"], selfBundlePath: selfPath, fs: fs)
            expect(r.items.contains { $0.group == .groupContainer }, "non-prefix lookalike does not exclude group container")
        }

        // LaunchAgents：内容不含本 bundleID 的不收
        do {
            let fs = makeFS()
            fs.mkfile("\(home)/Library/LaunchAgents/other.plist", bytes: 32, content: "<string>com.other</string>")
            let r = WS2AppUninstallPlan.scan(bundleID: bid, appPath: appPath, home: home,
                                             otherBundleIDs: [], selfBundlePath: selfPath, fs: fs)
            expect(!r.items.contains { $0.group == .launchAgent && $0.path.hasSuffix("other.plist") },
                   "unrelated launch agent excluded")
        }

        // LaunchAgents：文件名带 bundleID 也收（脚本式 agent 惯例，内容不一定是 plist）
        do {
            let fs = makeFS()
            fs.mkfile("\(home)/Library/LaunchAgents/\(bid).agent.plist", bytes: 16, content: "agent")
            let r = WS2AppUninstallPlan.scan(bundleID: bid, appPath: appPath, home: home,
                                             otherBundleIDs: [], selfBundlePath: selfPath, fs: fs)
            expect(r.items.contains { $0.group == .launchAgent && $0.path.hasSuffix("\(bid).agent.plist") },
                   "agent named after bundleID included even with non-plist content")
        }

        // 红线路径：系统域、自己、非 App
        do {
            expect(WS2AppUninstallPlan.isBlocked(appPath: "/System/Applications/Calculator.app", selfBundlePath: selfPath) == .systemPath,
                   "system domain blocked")
            expect(WS2AppUninstallPlan.isBlocked(appPath: selfPath, selfBundlePath: selfPath) == .selfApp,
                   "self blocked")
            expect(WS2AppUninstallPlan.isBlocked(appPath: "/Applications/Demo", selfBundlePath: selfPath) == .notAnApp,
                   "non-.app blocked")
            expect(WS2AppUninstallPlan.isBlocked(appPath: "", selfBundlePath: selfPath) == .notAnApp, "empty blocked")
            var r = WS2AppUninstallPlan.scan(bundleID: bid, appPath: selfPath, home: home,
                                             otherBundleIDs: [], selfBundlePath: selfPath, fs: makeFS())
            expect(r.block == .selfApp && r.items.isEmpty, "blocked scan returns no items")
            r = WS2AppUninstallPlan.scan(bundleID: bid, appPath: appPath, home: home,
                                         otherBundleIDs: [], selfBundlePath: selfPath, fs: FakeFS())
            expect(r.block == .notAnApp, "missing app on disk blocked as notAnApp")
        }

        if failures > 0 { print("\(failures) FAILED"); exit(1) }
        print("PASS app uninstall plan")
    }
}
