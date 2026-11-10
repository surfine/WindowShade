import Foundation

// 规格 R28：隐私与安全性里辅助功能那一栏在 macOS 27 改名；26 及以前原样。
@main
struct PrivacyPaneNameTests {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { if !ok { failures += 1; print("FAIL \(what)") } }
        let zh = "辅助功能被关掉了，收起和移动窗口暂时不生效"
        check(PrivacyPaneName.adjust(zh, renamed: false) == zh, "26 及以前原样不动")
        check(PrivacyPaneName.adjust(zh, renamed: true, from: "辅助功能", to: "设备控制和数据访问")
              == "设备控制和数据访问被关掉了，收起和移动窗口暂时不生效", "简体")
        check(PrivacyPaneName.adjust("需要輔助使用權限", renamed: true, from: "輔助使用", to: "裝置控制和資料取用")
              == "需要裝置控制和資料取用權限", "繁体")
        check(PrivacyPaneName.adjust("Turn On Accessibility…", renamed: true, from: "Accessibility", to: "Device Control and Data Access")
              == "Turn On Device Control and Data Access…", "英文")
        check(PrivacyPaneName.adjust("屏幕录制", renamed: true, from: "辅助功能", to: "设备控制和数据访问") == "屏幕录制", "不相干的句子不变")
        check(PrivacyPaneName.legacyName == "辅助功能" && PrivacyPaneName.renamedName == "设备控制和数据访问", "简体界面下取到的两个名字")
        check(PrivacyPaneName.screenCaptureName(renamed: false) == "屏幕录制", "26 的录屏栏仍叫屏幕录制")
        check(PrivacyPaneName.screenCaptureName(renamed: true) == "录屏与系统录音", "27 的录屏栏跟系统设置同一句")
        check(PrivacyPaneName.accessibilityName(renamed: false) == "辅助功能", "26 的辅助功能栏")
        check(PrivacyPaneName.accessibilityName(renamed: true) == "设备控制和数据访问", "27 的辅助功能栏")
        if failures > 0 { exit(1) }
        print("PASS privacy-pane-name: unchanged through macOS 26, renamed in all three languages on 27")
    }
}
