import Cocoa
@MainActor enum WS2SettingsCopy {
    static let short: [String:String] = [
        "设置怎么收起窗口、收起后什么样、要不要提示音。": "窗口的收起方式与外观",
        "指针停在卷帘条上，窗口在原处出现，移开就收回": "停在卷帘条上看一眼",
        "朝刘海甩一下标题栏，窗口就收进刘海；指针停在刘海上，点一下放回": "甩进刘海，点一下放回",
        "收起的窗口标题变了，比如编译完成，刘海会短暂展开告诉你": "窗口标题变化时提醒",
        "在刘海和启动台负一屏查看音乐、耳机、隔空投送与路线": "音乐、外设、传送与路线",
        "卡住时，刘海按你原来的习惯提示 Mac 上怎么做": "遇到操作困难时提示",
        "半屏、四角、网格、魔法平铺、卷轴排好的窗口之间和屏幕边留一道缝": "窗口与屏幕边缘的间距",
        "两扇窗口拼满一块屏时，中间出现一根小竖条：拖它两扇一起变，推到屏幕边那一扇进侧拉": "拖中间竖条，同时调两扇",
        "收起的窗口也不会被别的窗口挡住": "收起后也保持置顶",
        "WindowShade 只在需要时使用系统权限。": "只在需要时使用权限",
        "找到、移动和恢复窗口": "找到、移动和恢复窗口",
        "截取窗口画面做预览": "截取窗口画面做预览",
        "在任何应用里都能用。点“录制…”再按下新的组合；“清除”会关掉这个快捷键。": "录制或清除全局快捷键",
        "一下让开所有置顶的窗口，再按一下按原来的前后顺序放回": "让开置顶窗口，再按放回",
        "窗口留在原处，在别的桌面上也能看一眼": "在其他桌面看一眼",
        "窗口靠到屏幕边、浮在前面；再按一次收到屏幕边，或拉出来": "靠边悬浮，再按收进屏边",
        "窗口缩成一张实时画面浮在屏幕角落，再按一次回到原处；把标题栏拖到屏幕角落停一下也行": "实时画面悬在屏幕角落",
        "列出所有 App；把图标拖到屏幕边就侧拉，拖到一边就开在那一半": "拖 App 图标来安排窗口",
        "卷帘条展开；原来大小的窗口铺满屏幕": "展开卷帘条或铺满窗口",
        "铺满的窗口回到原来大小；原来大小的窗口收起": "还原窗口大小或收起",
        "把这块屏上的窗口一次排好：要地方多的占大头，聊天放侧拉；捏合整批撤回": "按需要分配窗口位置",
        "按原来的排法放到下一块屏幕上；上下摆的显示器也行": "保留排法，移到另一屏",
        "这块屏上的窗口全部收进刘海，再按一下放回来": "整屏收进刘海，再按放回",
        "只把当前窗口收进刘海": "只收进当前窗口",
        "装过 Rectangle 的照它现在的设置，没装过的用它推荐的那一套（⌃⌥ 加方向键和字母）。下面的名字和 Raycast 的窗口命令一一对应": "沿用 Rectangle 的快捷键",
        "变小一级、变大一级、左半屏、右半屏改用 ⌃⌥ 加字母，和 Swish 一样。别的动作在用的组合不抢": "部分排列改用字母快捷键",
        "左右不动，上下占满": "左右不动，上下占满",
        "大小不变，放到正中": "大小不变，放到正中",
        "四边各往外 30 点": "四边各往外 30 点",
        "四边各往里 30 点": "四边各往里 30 点",
        "回到排之前的位置和大小": "回到排列前的位置和大小",
        "和“移到另一块屏幕”反着转": "反向移到另一块屏幕",
        "外观选“统一标题栏”时，改为专注当前 App；选“缩略图”时，把缩略图排到屏幕下边，再按放回原位": "按外观整理窗口或缩略图",
        "默认不设置。再按一次同一个组合会关掉面板。": "再按同一快捷键关闭面板",
        "在 Dock 图标上看这个应用的全部窗口，也可以用菜单或快捷键打开。": "从 Dock 查看应用窗口",
        "鼠标停在 Dock 图标上时显示窗口面板。不会启动没在运行的应用。": "悬停 Dock 图标查看窗口",
        "它已经在最前、窗口露着时才这样（和 Windows 任务栏一样）；再点一下回来": "再点前台应用，让开窗口",
        "往上滑看这个 App 的所有窗口，往下滑让开这个 App": "上滑查看，下滑让开",
        "指针碰到别的屏的底边时 Dock 不跟过去（只管放在底部的 Dock）；打开时记下 Dock 现在在哪": "不让底部 Dock 跟随指针",
        "指针指着哪扇就关哪扇，⌘Q 退出它的 App；只在调度中心开着时这样，平时不动你的 ⌘W": "在调度中心关闭所指窗口",
        "默认不占用快捷键，可以在“快捷键”里设置": "快捷键默认留空",
        "按住连按 Tab 一扇一扇地挑，松手切过去；收着的窗口也在里面。选 ⌘Tab 会换掉系统的 App 切换": "按 Tab 挑窗口，松手切换",
        "选中窗口 0.4 秒后开始播放实时画面": "选中 0.4 秒后播放预览",
        "开启系统的“减少透明度”时，自动使用不透明背景。": "跟随系统减少透明度",
        "自动：窗口多的时候用列表，少的时候用缩略图。面板里的切换只影响这一次。": "根据窗口数量自动切换",
        "在窗口右键菜单里选“排布”：左半、右半、四角、居中、铺满屏幕、移到另一块屏幕。可以先看效果，移好之后还能撤销。": "右键菜单快速排布窗口",
        "识别 Dock 图标，切换、收起、展开和关闭窗口": "识别 Dock 图标并操作窗口",
        "窗口缩略图与实时预览；缺失时显示图标和文字列表": "无录屏权限时显示列表",
        // 动态副标题：原文由运行时状态拼出，短句无法写进对照表，由主模型逐条核定。
        "在任意窗口的标题栏上双击": "双击任意窗口标题栏",
        "三击标题栏会缩放窗口": "三击标题栏缩放窗口",
        "三击标题栏会最小化窗口": "三击标题栏最小化窗口",
        "WindowShade 会在登录后自动运行": "登录后自动运行",
        "需要在系统设置中批准登录项": "需在系统设置中批准",
        "开机后自动运行 WindowShade": "开机后自动运行",
        "当前 app bundle 不支持登录项": "此版本不支持登录项",
        "Swish 正在运行，标题栏上的手势交给它；在卷帘条上往下滑仍可展开": "Swish 接管标题栏手势",
        "在标题栏上两指滑动、滚动滚轮或拖着甩一下：往上收起，往下铺满": "标题栏手势：上收下铺",
        "⌃⌘1…9 对应菜单里的前 9 个窗口": "⌃⌘1…9：前 9 个窗口",
    ]
    static func symbol(for name:String) -> String {
        if name.contains("刘海") { return "rectangle.topthird.inset.filled" }
        if name.contains("窗口") || name.contains("排列") { return "macwindow" }
        if name.contains("快捷键") { return "keyboard" }
        if name.contains("外观") { return "paintpalette" }
        if name.contains("权限") { return "lock.shield" }
        return "slider.horizontal.3"
    }
}
@MainActor final class WS2SettingsInfoButton: NSButton {
    private let fullText: String
    private var popover: NSPopover?
    init(text:String,name:String) {
        fullText = text; super.init(frame:.zero)
        image = NSImage(systemSymbolName:"info.circle",accessibilityDescription:"\(name)的说明")
        isBordered = false; imagePosition = .imageOnly
        target = self; action = #selector(showInfo); toolTip = text
        setAccessibilityLabel("\(name)的说明")
    }
    required init?(coder:NSCoder) { nil }
    @objc private func showInfo() {
        if let p = popover,p.isShown { p.close(); return }
        let label = NSTextField(wrappingLabelWithString:fullText)
        label.translatesAutoresizingMaskIntoConstraints = false
        let host = NSViewController(); host.view = NSView()
        host.view.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:host.view.leadingAnchor,constant:16),
            label.trailingAnchor.constraint(equalTo:host.view.trailingAnchor,constant:-16),
            label.topAnchor.constraint(equalTo:host.view.topAnchor,constant:16),
            label.bottomAnchor.constraint(equalTo:host.view.bottomAnchor,constant:-16),
            label.widthAnchor.constraint(equalToConstant:300)])
        let p = NSPopover(); p.behavior = .transient; p.contentViewController = host
        popover = p; p.show(relativeTo:bounds,of:self,preferredEdge:.maxY)
    }
}
