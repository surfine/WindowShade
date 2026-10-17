// 设置搜索的同义词表（1.0.18 新表面稿第 2 节）。来源是 docs/copy-guide.md 固定词汇表三张表的「不要用」那一列：
// 用户会打的说法（我们不用的词）→ 它在产品里的名字。copy-guide 加一行「不要用」，这里跟着加一组；
// tests/SettingsSearchTests.swift 逐词核对「不要用」里的每个词都在这张表里（不在就失败）。
//
// 每组是目录里的一句（键 settings.search.synonym.<组>），格式「用户会打的、… → 产品里的名字、…」：
// 简体源句里也写英文词（中文界面打英文也找得到），英文、繁体列各自写那门语言的人会打的说法，
// 繁体列由 tools/localize/zh-hant.py 的同一套转换生成。搜索时三门语言的说法都认（见 SettingsSearchIndex）。
// 不显示给用户，只用来找行。
//
// 设计稿第 2 节的同义词表另外补了几组（隐藏、任务栏、热键、权限、声音、动画、音乐、下载、录屏），一并放在这里。

import Foundation

enum SettingsSearchSynonyms {
    /// 计算属性：SettingsText 带格式参数，不是 Sendable，不能做成全局常量。
    static var table: [SettingsText] {
        [
            WSL10n.setting("settings.search.synonym.rollUp", zh: "折叠、卷起、卷成、隐藏、最小化、collapse、collapsed、expand、expanded、fold、shade、hide、minimize → 收起、展开"),
            WSL10n.setting("settings.search.synonym.bar", zh: "标题条、细杠、strip、bar alone、bar → 卷帘条、收起"),
            WSL10n.setting("settings.search.synonym.thumbnail", zh: "小窗、小图、占位窗口、缩略、thumbnail、roll-up style、collapsed look → 缩略图、收起后的样子"),
            WSL10n.setting("settings.search.synonym.pin", zh: "钉住、悬浮、总在最前、pin、float、keep on top、always on top → 置顶、浮在其他窗口上面"),
            WSL10n.setting("settings.search.synonym.unpinAll", zh: "暂停置顶、隐藏置顶、老板键、boss key → 暂时取消全部置顶、恢复全部置顶"),
            WSL10n.setting("settings.search.synonym.deviceBattery", zh: "电池电量、剩余电量、还能用 N 分钟、正在充电、蓝牙设备已配对 → 设备的电量、电量"),
            WSL10n.setting("settings.search.synonym.deviceNames", zh: "Magic Mouse、巧控滑鼠、鼠标 2 代 → 妙控鼠标、妙控键盘、妙控板、蓝牙配件"),
            WSL10n.setting("settings.search.synonym.thisMac", zh: "能耗、还能用多久、InternalBattery → 这台 Mac"),
            WSL10n.setting("settings.search.synonym.touchID", zh: "验证身份、认证成功、安全验证 → 用 Touch ID 确认、Touch ID"),
            WSL10n.setting("settings.search.synonym.permissions", zh: "权限、授权、permission、permissions → 辅助功能、屏幕录制"),
            WSL10n.setting("settings.search.synonym.windowBrowsing", zh: "窗口选择面板、Dock 悬停面板、任务栏、Dock 预览、窗口选择、taskbar、dock preview、window picker、window browser panel、Dock hover panel → 窗口浏览、Dock 悬停、Dock 图标"),
            WSL10n.setting("settings.search.synonym.chooseWindow", zh: "打开窗口浏览器 → 选择窗口"),
            WSL10n.setting("settings.search.synonym.bigPreview", zh: "Quick Look 预览、Space 预览 → 大图预览"),
            WSL10n.setting("settings.search.synonym.glance", zh: "偷看、悬停展开、临时展开、预览、peek、hover preview → 看一眼"),
            WSL10n.setting("settings.search.synonym.frozenPicture", zh: "快照、缓存画面、过期截图 → 收起时的画面、不是实时画面"),
            WSL10n.setting("settings.search.synonym.allSpaces", zh: "跨桌面、随身、跟随、pin to all spaces → 带到每张桌面"),
            WSL10n.setting("settings.search.synonym.titleBarGestures", zh: "触控板手势、触摸板手势、手势操作 → 标题栏手势"),
            WSL10n.setting("settings.search.synonym.sizeStep", zh: "最大化、最小化、放大、缩小 → 变大一级、变小一级"),
            WSL10n.setting("settings.search.synonym.screenSide", zh: "跨屏、甩到副屏、下一个显示器 → 移到左边的屏幕、移到右边的屏幕、移到另一块屏幕"),
            WSL10n.setting("settings.search.synonym.thirds", zh: "1/3、2/3、三等分 → 三分之一、三分之二"),
            WSL10n.setting("settings.search.synonym.grid", zh: "网格单元、3×2、sixth → 六分之一、三分之二"),
            WSL10n.setting("settings.search.synonym.magicTiling", zh: "自动平铺、智能布局、平铺、自动排列、auto tile、tile、tiling → 魔法平铺"),
            WSL10n.setting("settings.search.synonym.strip", zh: "卷动平铺、无限画布、滚动工作区、scrolling、strip、strip position N、page N of M → 卷轴"),
            WSL10n.setting("settings.search.synonym.stripOverview", zh: "概述、总览、overview、Exposé、调度中心 → 卷轴概览"),
            WSL10n.setting("settings.search.synonym.origin", zh: "来源、背景、迁移自、老用户类型、source、migration → 之前常用"),
            WSL10n.setting("settings.search.synonym.byWindow", zh: "Cmd-Tab Plus、窗口切换器、Alt-Tab、切换窗口、alt tab、switcher、window switcher → 按窗口切换"),
            WSL10n.setting("settings.search.synonym.keyNames", zh: "Ctrl、Cmd、Alt、热键、快捷方式、键位、hotkey、keybinding、keyboard shortcut → 快捷键"),
            WSL10n.setting("settings.search.synonym.tuckAll", zh: "隐藏全部、最小化全部、显示桌面 → 全部收进刘海"),
            WSL10n.setting("settings.search.synonym.moveDisplay", zh: "移到另一显示器、跨屏、下一个显示器 → 移到另一块屏幕、移到上一块屏幕"),
            WSL10n.setting("settings.search.synonym.halves", zh: "顶部一半、Top Half → 上半屏、下半屏"),
            WSL10n.setting("settings.search.synonym.largerSmaller", zh: "放大、缩小、Make Larger → 大一点、小一点"),
            WSL10n.setting("settings.search.synonym.heightCenter", zh: "最大化高度、Maximize Height → 高度占满、居中"),
            WSL10n.setting("settings.search.synonym.rectangle", zh: "导入 Rectangle、迁移、兼容模式 → 用 Rectangle 的快捷键、更多排法"),
            WSL10n.setting("settings.search.synonym.welcome", zh: "使用说明、新手教程、Onboarding、导览 → 欢迎使用 WindowShade"),
            WSL10n.setting("settings.search.synonym.pip", zh: "小窗、悬浮窗、PiP、迷你模式 → 画中画"),
            WSL10n.setting("settings.search.synonym.splitHandle", zh: "分隔条、divider、Split View、分割线 → 分屏把手、分屏"),
            WSL10n.setting("settings.search.synonym.dropSplit", zh: "拖拽分屏、合并窗口、吸附、分屏、snap、split → 拖到窗口上并排、标题栏手势、魔法平铺"),
            WSL10n.setting("settings.search.synonym.frame", zh: "边框、grabber、resize handle → 玻璃边框、把手"),
            WSL10n.setting("settings.search.synonym.gap", zh: "间距、边距、缝隙、gap、spacing、margin → 窗口之间留缝"),
            WSL10n.setting("settings.search.synonym.moveAside", zh: "Dock 反转、隐藏窗口、隐藏应用、最小化 App、Hide → 让开这个 App"),
            WSL10n.setting("settings.search.synonym.dropIsland", zh: "分屏岛、Snap Island、布局面板 → 落点小岛"),
            WSL10n.setting("settings.search.synonym.shake", zh: "摇一摇、Aero Shake、甩开 → 晃一晃"),
            WSL10n.setting("settings.search.synonym.notchTaps", zh: "Home 键、主屏幕按钮、Exposé → 回到主屏幕、调度中心"),
            WSL10n.setting("settings.search.synonym.minimizedHidden", zh: "最小化窗口仓、隐藏区 → 已最小化、已隐藏"),
            WSL10n.setting("settings.search.synonym.otherSpaces", zh: "其他空间、Space 3、跨桌面窗口、远程窗口 → 桌面"),
            WSL10n.setting("settings.search.synonym.openWith", zh: "打开方式、Open With → 用哪个 App 打开"),
            WSL10n.setting("settings.search.synonym.ninths", zh: "3×3、ninth、九宫格 → 九分之一"),
            WSL10n.setting("settings.search.synonym.flick", zh: "抛窗口、flick、快速拖拽 → 甩一下标题栏"),
            WSL10n.setting("settings.search.synonym.slideOver", zh: "滑过、侧滑、Slide Over、抽屉 → 侧拉"),
            WSL10n.setting("settings.search.synonym.fullScreen", zh: "最大化、全屏模式、Full Screen → 进入全屏、铺满屏幕"),
            WSL10n.setting("settings.search.synonym.quitApp", zh: "结束进程、杀死、Force Quit、退出应用 → 退出 App"),
            WSL10n.setting("settings.search.synonym.missionControlClose", zh: "调度中心 Pro、Mission Control 增强、关窗助手 → 调度中心里按 ⌘W 关窗"),
            WSL10n.setting("settings.search.synonym.tuck", zh: "塞进刘海、刘海收纳、灵动岛、刘海屏、notch、dynamic island、notch area、put in the notch、hide in the notch、hidden、restored to notch → 收进刘海、刘海"),
            WSL10n.setting("settings.search.synonym.alerts", zh: "实时活动、通知、动态、Live Activity → 有变化时提醒"),
            WSL10n.setting("settings.search.synonym.activities", zh: "小组件、Widgets、通知、widgets、notifications → 实时活动"),
            WSL10n.setting("settings.search.synonym.looks", zh: "原貌卷帘、标准标题栏 → 跟原来一样、统一标题栏"),
            WSL10n.setting("settings.search.synonym.systemLook", zh: "系统玻璃、原生材质 → 跟随系统外观"),
            WSL10n.setting("settings.search.synonym.unavailable", zh: "材质回退、权限缺失 → 画面暂时看不到"),
            WSL10n.setting("settings.search.synonym.focusTimer", zh: "番茄时钟、Pomodoro、计时器、工作模式 → 番茄钟"),
            WSL10n.setting("settings.search.synonym.timer", zh: "倒计时器、闹钟、定时器、番茄钟、timer alarm → 计时器"),
            WSL10n.setting("settings.search.synonym.calendar", zh: "会议、事件、日历提醒、入会、参会 → 日程"),
            WSL10n.setting("settings.search.synonym.shelf", zh: "货架、托盘、收藏夹、删除、暂存、Shelf、Tray → 文件架"),
            WSL10n.setting("settings.search.synonym.stripColumns", zh: "合并列、堆叠、consume、expel、吸入、弹出 → 并进、拆成一列"),
            WSL10n.setting("settings.search.synonym.launchpad", zh: "Launchpad、启动器、应用启动台 → 启动台"),
            WSL10n.setting("settings.search.synonym.homeScreen", zh: "桌面、主页、首屏 → 主屏幕"),
            WSL10n.setting("settings.search.synonym.library", zh: "应用库、所有应用、图书馆 → App 资料库"),
            WSL10n.setting("settings.search.synonym.folder", zh: "分组、文件夹组、cluster → 文件夹"),
            WSL10n.setting("settings.search.synonym.removeHome", zh: "删除、卸载、移除应用 → 从主屏幕移除"),
            WSL10n.setting("settings.search.synonym.uninstall", zh: "删除应用、永久删除、彻底清除 → 卸载"),
            WSL10n.setting("settings.search.synonym.addHome", zh: "添加应用、恢复图标 → 添加到主屏幕"),
            WSL10n.setting("settings.search.synonym.editHome", zh: "编辑模式、抖动模式、整理模式 → 编辑主屏幕"),
            WSL10n.setting("settings.search.synonym.smoothScroll", zh: "惯性滚动、丝滑滚动 → 平滑滚动"),
            WSL10n.setting("settings.search.synonym.scrollDirection", zh: "自然滚动、反向滚动 → 滚动方向"),
            WSL10n.setting("settings.search.synonym.middleButton", zh: "滚轮按下、中键点击 → 中键"),
            WSL10n.setting("settings.search.synonym.remote", zh: "远程模式、遥控控制 → 遥控模式、遥控器"),
            WSL10n.setting("settings.search.synonym.siriRemote", zh: "Apple TV 遥控器、电视遥控器 → Siri 遥控器"),
            WSL10n.setting("settings.search.synonym.iphoneRemote", zh: "iPhone 遥控、手机遥控器 → iPhone 上的遥控器"),
            WSL10n.setting("settings.search.synonym.conductor", zh: "远程控制、指挥控制 → 指挥模式"),
            WSL10n.setting("settings.search.synonym.silent", zh: "静音控制、无声模式、failed、error、operation aborted、pending、ack timeout、verify your identity、confirm the action、mismatch error、stale proposal、draft is local、not uploaded、privacy on、mask applied、cannot unlock、filling disabled → 静音操作、方言"),
            WSL10n.setting("settings.search.synonym.skipModifier", zh: "bypass、disable、temporary off → 双击标题栏收起窗口"),
            WSL10n.setting("settings.search.synonym.bystander", zh: "偷看、防窥、窥屏、隐私模式 → 有人在看"),
            WSL10n.setting("settings.search.synonym.tooClose", zh: "距离警告、太近了 → 离屏幕近了"),
            WSL10n.setting("settings.search.synonym.headDown", zh: "坐姿警告、颈椎 → 头低久了"),
            WSL10n.setting("settings.search.synonym.nearHeadDown", zh: "综合提醒 → 近了，头低久了"),
            WSL10n.setting("settings.search.synonym.language", zh: "语言、UI language、Requires restart → 界面语言"),
            WSL10n.setting("settings.search.synonym.followSystem", zh: "Auto、System default → 跟随系统"),
            WSL10n.setting("settings.search.synonym.resetDiagnostics", zh: "factory reset、debug log、重置、日志 → 恢复动态效果默认值、诊断日志"),
            WSL10n.setting("settings.search.synonym.mergedHover", zh: "merge row、hover protection → 合成一排、悬停不误触"),
            WSL10n.setting("settings.search.synonym.sound", zh: "声音、音效、sound、audio、chime → 音效、响一声、提示音"),
            WSL10n.setting("settings.search.synonym.animation", zh: "动画、动效、animation、motion → 动画、动态效果"),
            WSL10n.setting("settings.search.synonym.music", zh: "音乐、歌、媒体、music、media、song → 正在播放、实时活动、跟着声音跳"),
            WSL10n.setting("settings.search.synonym.download", zh: "下载、download、downloads → 浏览器下载"),
            WSL10n.setting("settings.search.synonym.capture", zh: "录屏、截屏、screen capture、recording → 屏幕录制"),
        ]
    }

    /// 只用简体源句建组（纯逻辑测试、没有译文目录时）。App 里由 SettingsSearchIndex 再并上英文与繁体两列。
    static var sourceGroups: [SettingsSynonymGroup] {
        table.map { SettingsSynonymGroup(id: $0.key, values: [$0.zh]) }
    }
}
