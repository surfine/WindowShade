// M03：私人 App 名单的增删、去重、通知，以及空名单时三个消费方读到空。
import Foundation

@main
struct PrivateAppListTests {
    nonisolated(unsafe) static var failures = 0
    static func expect(_ ok: Bool, _ message: String) {
        if ok { print("ok   \(message)") } else { failures += 1; print("FAIL \(message)") }
    }
    final class Counter: @unchecked Sendable { var n = 0 }
    struct W { let id: Int; let bundle: String? }

    static func main() {
        let suite = "PrivateAppListTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let center = NotificationCenter()
        let list = PrivateAppList(defaults: defaults, center: center)
        let counter = Counter()
        let token = center.addObserver(forName: PrivateAppList.didChange, object: nil, queue: nil) { _ in counter.n += 1 }
        defer { center.removeObserver(token) }

        // 空名单：三个消费方（有人在看、离开就锁、专注）读到的都是空。
        let windows = [W(id: 1, bundle: "com.apple.mail"), W(id: 2, bundle: nil)]
        expect(list.isEmpty && list.bundleIDs.isEmpty, "默认名单为空")
        expect(!list.contains(bundleID: "com.apple.mail") && !list.contains(bundleID: nil), "空名单不包含任何 App")
        for consumer in ["有人在看", "离开就锁", "专注"] {
            expect(list.filterPrivate(windows, bundleID: { $0.bundle }).isEmpty, "空名单时「\(consumer)」读到空")
        }
        expect(defaults.object(forKey: PrivateAppList.defaultsKey) == nil, "读取不写入任何值")

        // 增加、去重、通知。
        expect(list.add(bundleID: "com.apple.mail"), "加入邮件")
        expect(counter.n == 1, "加入发一次通知")
        expect(!list.add(bundleID: "  COM.apple.Mail "), "大小写和空白不同也算重复")
        expect(counter.n == 1, "重复加入不发通知")
        expect(!list.add(bundleID: "   "), "空串不加入")
        expect(list.add(bundleID: " com.tencent.xinWeChat "), "加入微信（去掉空白）")
        expect(list.bundleIDs == ["com.apple.mail", "com.tencent.xinWeChat"], "按加入顺序保存 \(list.bundleIDs)")
        expect(list.contains(bundleID: "COM.TENCENT.XINWECHAT"), "contains 不分大小写")
        expect(counter.n == 2, "通知总数 2")

        // 过滤。
        let kept = list.filterPrivate(windows, bundleID: { $0.bundle })
        expect(kept.map(\.id) == [1], "只留名单内且有 bundle ID 的窗口")

        // 持久化：另一个实例读到同一份。
        let other = PrivateAppList(defaults: defaults, center: center)
        expect(other.bundleIDs == list.bundleIDs, "重新读取得到同一份名单")

        // 移除。
        expect(list.remove(bundleID: "COM.APPLE.MAIL"), "移除邮件")
        expect(!list.remove(bundleID: "com.apple.mail"), "再移除返回 false")
        expect(!list.remove(bundleID: ""), "移除空串返回 false")
        expect(counter.n == 3, "移除发一次通知，未命中不发（\(counter.n)）")
        expect(list.bundleIDs == ["com.tencent.xinWeChat"], "剩下微信")
        _ = list.remove(bundleID: "com.tencent.xinWeChat")
        expect(list.isEmpty && list.filterPrivate(windows, bundleID: { $0.bundle }).isEmpty, "删空后回到空")

        // 手写入脏数据：读取时去重去空。
        defaults.set(["a.b", "A.B", "", " c.d "], forKey: PrivateAppList.defaultsKey)
        expect(list.bundleIDs == ["a.b", "c.d"], "脏数据读取时规整 \(list.bundleIDs)")

        if failures > 0 { print("\(failures) 项失败"); exit(1) }
        print("全部通过")
    }
}
