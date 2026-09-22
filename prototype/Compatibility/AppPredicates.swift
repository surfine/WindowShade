// 按应用区分的判断：隐藏策略、特殊外框高度与各应用识别。

import Cocoa

func shadePolicy(for pid: pid_t) -> ShadePolicy {
    windowPolicy(for: pid).hidingStrategy.shadePolicy
}

func isElpass(pid: pid_t) -> Bool {
    windowPolicy(for: pid).kind == .elpass
}

func isAdobeApp(pid: pid_t) -> Bool {
    windowPolicy(for: pid).kind == .adobe
}

func usesStandardTitleBarOnly(pid: pid_t) -> Bool {
    windowPolicy(for: pid).usesStandardTitleBarOnly
}

func extendsTitlebarHitToApplicationFrame(pid: pid_t) -> Bool {
    windowPolicy(for: pid).extendsTitlebarHitToApplicationFrame
}

func isStickies(pid: pid_t) -> Bool {
    windowPolicy(for: pid).delegatesNativeShade
}

func needsControlPaddedChrome(pid: pid_t) -> Bool {
    fixedNonstandardChromeHeight(pid: pid) != nil
}

// WeChat / Elpass 这类非标准窗口的诀窍是按“第一层可操作 chrome band”裁，
// 只保留交通灯、搜索框、标题/工具按钮和它们自己的上下 padding。
// 下面的列表行、选中条、账号卡即使只露一点，也会让折叠条失去标题栏语义。
func fixedNonstandardChromeHeight(pid: pid_t) -> CGFloat? {
    windowPolicy(for: pid).fixedChromeHeight
}

func fallbackControlPaddedChromeHeight(pid: pid_t, minimum _: CGFloat) -> CGFloat? {
    if let fixed = fixedNonstandardChromeHeight(pid: pid) { return max(titleBarHeight, fixed) }
    return nil
}
