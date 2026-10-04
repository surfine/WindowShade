import Cocoa
@MainActor enum WS2SettingsCopy {
    nonisolated static let short: [String:String] = [
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
        "看当前会话、改模型、写草稿。不会发送，也不会连接。": "看会话、改模型、写草稿",
        "列出所有 App；把图标拖到屏幕边就侧拉，拖到一边就开在那一半": "拖 App 图标来安排窗口",
        "卷帘条展开；原来大小的窗口铺满屏幕": "展开卷帘条或铺满窗口",
        "铺满的窗口回到原来大小；原来大小的窗口收起": "还原窗口大小或收起",
        "把这块屏上的窗口一次排好：要地方多的占大头，聊天放侧拉；捏合整批撤回": "按需要分配窗口位置",
        "按原来的排法放到下一块屏幕上；上下摆的显示器也行": "保留排法，移到另一屏",
        "这块屏上的窗口全部收进刘海，再按一下放回来": "整屏收进刘海，再按放回",
        "只把当前窗口收进刘海": "只收进当前窗口",
        "装过 Rectangle 的照它现在的设置，没装过的用它推荐的那一套（⌃⌥ 加方向键和字母）。下面的名字和 Raycast 的窗口命令一一对应": "沿用 Rectangle 快捷键",
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
        "开始、暂停或继续同一个番茄钟；默认不占用任何快捷键": "默认不占键，开始或暂停",
        "卷帘条跟原来一样或用统一标题栏，也可以在原处缩成缩略图": "跟原来一样、统一标题栏或缩略图",
        "让它更透一些，能看到后面的内容": "更透，能看到后面",
        "WindowShade 读到的每一样都列在这里。": "读到的都列在这里",
        "这里列出 WindowShade 读到的每一样，以及为什么读、去了哪里。值和开关都来自原来的设置。": "读到的、为什么、去了哪里",
        "有新版本时在菜单里告诉你，不会自己装。": "有新版时告诉你，不自动装",
        "新版本用着不对，可以换回刚才那一版。": "可以换回刚才那一版",
        "合上或打开盖子时，桌面跟着动一下。": "合上或打开时桌面跟着动",
        "恢复默认值，或打开诊断日志排查问题。": "恢复默认，或打开诊断日志",
    ]

    /// design-system §4.11 里出现过的符号。页头只许用这份里的名字。
    nonisolated static let tableSymbols: Set<String> = [
        "rectangle.compress.vertical", "rectangle.expand.vertical",
        "rectangle.topthird.inset.filled", "macwindow.on.rectangle",
        "eye", "pin", "pin.slash",
        "rectangle.lefthalf.inset.filled", "rectangle.righthalf.inset.filled",
        "rectangle.inset.filled", "rectangle.split.2x1", "rectangle.split.3x3",
        "wand.and.stars", "scroll", "sidebar.right", "pip",
        "square.grid.3x3", "rectangle.3.group", "rectangle.on.rectangle",
        "command", "lightbulb", "music.note", "airpods", "waveform",
        "timer", "cup.and.saucer", "magicmouse", "rectangle.and.hand.point.up.left",
        "keyboard", "appletvremote.gen4", "gamecontroller", "iphone",
        "battery.75percent", "viewfinder", "touchid", "lock.shield", "mic.fill", "info.circle",
    ]

    nonisolated static func tableSymbol(_ name: String?) -> String? {
        guard let name, tableSymbols.contains(name) else { return nil }
        return name
    }

    /// 一行里放得下的短句。全文更长时由气泡保留，不在这里截掉意思。
    nonisolated static func line(_ subtitle: String) -> String {
        if let mapped = short[subtitle] { return mapped }
        if subtitle.count <= 16 { return subtitle }
        if let range = subtitle.range(of: "个应用") {
            let head = String(subtitle[..<range.upperBound])
            if head.count <= 16 { return head }
        }
        return String(subtitle.prefix(16))
    }

    /// 只返回 §4.11 对得上的符号。对不上返回 nil，不另造一个。
    /// 更具体的名字放前面，避免「取消置顶」被「置顶」先截走。
    nonisolated static func symbol(for name: String) -> String? {
        // 「暂时取消全部置顶」是另一个动作，§4.11 没有单独的符号，不用「置顶」顶上。
        if name.contains("暂时取消") { return nil }
        let pairs: [(String, String)] = [
            ("看一眼", "eye"),
            ("全部收进刘海", "rectangle.topthird.inset.filled"),
            ("收进刘海", "rectangle.topthird.inset.filled"),
            ("专注时把聊天收进刘海", "rectangle.topthird.inset.filled"),
            ("打开启动台", "square.grid.3x3"),
            ("启动台", "square.grid.3x3"),
            ("选择窗口", "rectangle.on.rectangle"),
            ("窗口浏览", "rectangle.on.rectangle"),
            ("置顶或取消", "pin"),
            ("取消置顶", "pin.slash"),
            ("置顶", "pin"),
            ("侧拉", "sidebar.right"),
            ("画中画", "pip"),
            ("魔法平铺", "wand.and.stars"),
            ("开始或暂停番茄钟", "timer"),
            ("番茄钟", "timer"),
            ("专注时长", "timer"),
            ("左半屏", "rectangle.lefthalf.inset.filled"),
            ("右半屏", "rectangle.righthalf.inset.filled"),
            ("铺满屏幕", "rectangle.inset.filled"),
            ("分屏把手", "rectangle.split.2x1"),
            ("双击标题栏收起窗口", "rectangle.compress.vertical"),
            ("收起后的样子", "rectangle.compress.vertical"),
            ("收起或展开", "rectangle.compress.vertical"),
            ("收起窗口", "rectangle.compress.vertical"),
            ("按编号展开", "rectangle.expand.vertical"),
            ("快捷键", "command"),
            ("隐私", "lock.shield"),
        ]
        for (needle, symbol) in pairs where name.contains(needle) {
            return symbol
        }
        return nil
    }

    /// 设置行左侧：圆角色块里的符号（有才放）、名字、至多一行副标题，说不完的进 info.circle。
    /// 跟着枚举留在主线程：这里建的是 AppKit 视图。调用方都是主线程类型。
    static func content(name: String?, subtitle: String?, symbol: String? = nil) -> (view: NSStackView, detail: NSTextField?) {
        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        if let name, !name.isEmpty {
            let title = NSTextField(labelWithString: name)
            title.font = SystemAppearancePolicy.font(relativeToBody: 0)
            labels.addArrangedSubview(title)
        }
        var detail: NSTextField?
        if let subtitle {
            let shown = line(subtitle)
            let field = NSTextField(labelWithString: shown)
            field.font = SystemAppearancePolicy.font(relativeToBody: -2)
            field.textColor = .secondaryLabelColor
            field.lineBreakMode = .byTruncatingTail
            field.maximumNumberOfLines = 1
            field.toolTip = subtitle
            labels.addArrangedSubview(field)
            detail = field
        }
        var views: [NSView] = []
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: name) {
            let icon = NSImageView(image: image)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: .controlAccentColor)
            icon.wantsLayer = true
            icon.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
            icon.layer?.cornerRadius = 7
            icon.imageScaling = .scaleProportionallyDown
            icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 28).isActive = true
            icon.setContentHuggingPriority(.required, for: .horizontal)
            views.append(icon)
        }
        views.append(labels)
        let content = NSStackView(views: views)
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 10
        if let subtitle, line(subtitle) != subtitle {
            let caption = (name?.isEmpty == false ? name! : "说明")
            content.addArrangedSubview(WS2SettingsInfoButton(text: subtitle, name: caption))
        }
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return (content, detail)
    }
}
final class WS2SettingsInfoButton: NSButton {
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
