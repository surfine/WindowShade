import Foundation

/// M02b：主句 ≤ 8 个字形簇、截断位置（名字中间、副句尾部）、私人 App 不露标题、0.6 秒合成一句。
@main struct NotchSentenceTests {
    static func main() {
        headlineLength()
        truncation()
        windowChange()
        burst()
        print("PASS: notch sentence rules")
    }

    static func headlineLength() {
        // 键帽符号各算 1 个。
        precondition(NotchSentence.compose(headline: "⌃⌘↓变小一级").headline == "⌃⌘↓变小一级")
        // 超过 8 个：在断点切开，剩下的去副句。
        let split = NotchSentence.compose(headline: "没有可以放进画中画的窗口", detail: "先点一下")
        precondition(split.headline.count <= 8, split.headline)
        precondition(split.detail.hasPrefix(String("没有可以放进画中画的窗口".dropFirst(split.headline.count))), split.detail)
        precondition(split.detail.hasSuffix("先点一下"))
        let comma = NotchSentence.compose(headline: "先展开这扇窗，再放进画中画")
        precondition(comma.headline == "先展开这扇窗" && comma.detail == "再放进画中画", "\(comma)")
        // emoji 簇（带肤色）算 1。
        precondition(NotchSentence.compose(headline: "👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽👍🏽").headline.count == 8)
        // 主句不被截断成省略号：只有副句会。
        let long = NotchSentence.compose(headline: "一二三四五六七八九十", detail: String(repeating: "长", count: 60))
        precondition(!long.headline.contains("…") && long.headline.count == 8)
        precondition(long.detail.hasSuffix("…") && long.detail.count == NotchSentence.detailLimit)
    }

    static func truncation() {
        precondition(NotchSentence.truncateMiddle("Aaron’s iPhone", limit: 12) == "Aaron’…Phone")
        precondition(NotchSentence.truncateMiddle("短名", limit: 5) == "短名")
        precondition(NotchSentence.truncateMiddle("ABCDEFGHIJ", limit: 6) == "ABC…IJ")
        precondition(NotchSentence.truncateTail("ABCDEFGHIJ", limit: 6) == "ABCDE…")
        // 设备名 + 已连接：整句 ≤ 8，名字在中间省略，后缀完整。
        let head = NotchSentence.headline(name: "Aaron的AirPods Pro", suffix: "已连接")
        precondition(head.count <= 8 && head.hasSuffix("已连接") && head.contains("…"), head)
        precondition(NotchSentence.headline(name: "妙控鼠标", suffix: "已连接") == "妙控鼠标已连接")
        precondition(NotchSentence.wasShortened(name: "Aaron的AirPods Pro", suffix: "已连接"))
        precondition(!NotchSentence.wasShortened(name: "妙控鼠标", suffix: "已连接"))
    }

    static func windowChange() {
        let normal = NotchSentence.windowChange(appName: "备忘录", windowTitle: "周五要交的东西", isPrivateApp: false)
        precondition(normal.headline == "备忘录有变化" && normal.detail == "周五要交的东西")
        let longName = NotchSentence.windowChange(appName: "Visual Studio Code", windowTitle: "main.swift", isPrivateApp: false)
        precondition(longName.headline.count <= 8 && longName.headline.hasSuffix("有变化") && longName.headline.contains("…"), longName.headline)
        let longTitle = NotchSentence.windowChange(appName: "备忘录", windowTitle: String(repeating: "标", count: 80), isPrivateApp: false)
        precondition(longTitle.detail.count == NotchSentence.detailLimit && longTitle.detail.hasSuffix("…"))
        // 私人 App：标题不出现在主句或副句里。
        let hidden = NotchSentence.windowChange(appName: "信息", windowTitle: "和老板的聊天", isPrivateApp: true)
        precondition(hidden.detail == "指针停上来就能找回来")
        precondition(!hidden.headline.contains("老板") && !hidden.detail.contains("老板"))
        let empty = NotchSentence.windowChange(appName: " ", windowTitle: "", isPrivateApp: false)
        precondition(empty.headline == "窗口有变化")
    }

    static func burst() {
        let battery = NotchSentence.Item(key: "battery.low.a", category: "battery", headline: "妙控鼠标电量低", detail: "还剩 10%，记得充电")
        let download = NotchSentence.Item(key: "download.1", category: "download", headline: "下载完成", detail: "")
        let away = NotchSentence.Item(key: "away.summary", category: "away", headline: "离开期间", detail: "2 个窗口有变化")
        var b = NotchSentence.Burst(first: battery, at: 100)
        // 只有一件：原样。
        precondition(b.line.headline == "妙控鼠标电量低" && b.line.detail == "还剩 10%，记得充电")
        precondition(b.accepts(at: 100.59) && !b.accepts(at: 100.61))
        // 同一类不多算。
        precondition(!b.add(NotchSentence.Item(key: "battery.low.b", category: "battery", headline: "x", detail: "")))
        precondition(b.extraCount == 0)
        // 不同类：主句用第一件，副句“还有 n 件”。
        precondition(b.add(download))
        precondition(b.line.headline == "妙控鼠标电量低" && b.line.detail == "还有 1 件")
        precondition(b.add(away))
        precondition(b.line.detail == "还有 2 件" && b.items.count == 3)
        // 停留时间不延长：从第一件开口算起说满 2.6 秒，且不会小于 0.4 秒。
        precondition(abs(b.remainingHold(now: 100.5, hold: 2.6) - 2.1) < 1e-9)
        precondition(b.remainingHold(now: 105, hold: 2.6) == 0.4)
        precondition(b.remainingHold(now: 99, hold: 2.6) == 2.6)
        // 第一件的同 key 更新到达：合并句与件数保持，Burst 里的文字同步。
        precondition(b.update(NotchSentence.Item(key: "battery.low.a", category: "battery", headline: "妙控鼠标电量更低", detail: "还剩 5%")))
        precondition(b.first.headline == "妙控鼠标电量更低" && b.items.count == 3)
        precondition(b.line.headline == "妙控鼠标电量更低" && b.line.detail == "还有 2 件")
        // 不在句子里的 key：不当更新。
        precondition(!b.update(NotchSentence.Item(key: "other.x", category: "other", headline: "x", detail: "")))
    }
}
