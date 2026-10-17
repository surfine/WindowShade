import Cocoa
@MainActor enum WS2SettingsCopy {
    nonisolated static let short: [String:String] = [
        "设置怎么收起窗口、收起后什么样、要不要提示音。": "窗口的收起方式与外观",
        "指针停在卷帘条上，窗口在原处出现，移开就收回": "停在卷帘条上看一眼",
        "朝刘海甩一下标题栏，窗口就收进刘海；指针停在刘海上，点一下放回": "甩进刘海，点一下放回",
        "收起的窗口标题变了，比如编译完成，刘海会短暂展开告诉你": "窗口标题变化时提醒",
        "在刘海和启动台负一屏查看音乐、耳机、隔空投送与路线": "音乐、外设、传送与路线",
        // #39：双击行的全文带修饰键出口，行内短句仍是"系统三击做什么"这一句（ⓘ 显示全文）。
        "三击标题栏会缩放窗口。按住 Option 双击不收起": "三击标题栏会缩放窗口",
        "三击标题栏会最小化窗口。按住 Option 双击不收起": "三击标题栏会最小化窗口",
        "在任意窗口的标题栏上双击。按住 Option 双击不收起": "在任意窗口的标题栏上双击",
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
        "窗口靠到屏幕边、浮在前面；再按一次收到屏幕边，或拉出来": "侧拉，再按收到屏幕边",
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

    /// 繁体短副标题表（第39批）：键是**繁体全文**，值是一行放得下的繁体短句——
    /// 与 short 表（键是简体全文）对称，因为简体与繁体的全文不同，键也必须各用各的。
    /// 由 tools/localize/short-hant.py 从 short 表 + 目录生成，不要手改。
    nonisolated static let shortHant: [String: String] = [
        "設定怎麼收起視窗、收起後什麼樣、要不要提示音。": "視窗的收起方式與外觀",
        "指標停在捲簾條上，視窗在原處出現，移開就收回": "停在捲簾條上看一眼",
        "朝瀏海甩一下標題列，視窗就收進瀏海；指標停在瀏海上，點一下放回": "甩進瀏海，點一下放回",
        "收起的視窗標題變了，比如編譯完成，瀏海會短暫展開告訴你": "視窗標題變化時提醒",
        "在瀏海和啟動台主畫面最左邊那一頁檢視音樂、耳機、AirDrop與路線": "音樂、周邊裝置、傳送與路線",
        "按三下標題列會縮放視窗。按住 Option 按兩下不收起": "按三下標題列會縮放視窗",
        "按三下標題列會最小化視窗。按住 Option 按兩下不收起": "按三下標題列會最小化視窗",
        "在任意視窗的標題列上按兩下。按住 Option 按兩下不收起": "在任意視窗的標題列上按兩下",
        "卡住時，瀏海按你原來的習慣提示 Mac 上怎麼做": "遇到操作困難時提示",
        "半螢幕、四角、網格、魔法並排、卷軸排好的視窗之間和螢幕邊留一道縫": "視窗與螢幕邊緣的間距",
        "兩扇視窗拼滿一塊螢幕時，中間出現一根小豎條：拖它兩扇一起變，推到螢幕邊那一扇進側拉": "拖中間豎條，同時調兩扇",
        "收起的視窗也不會被別的視窗擋住": "收起後也保持置頂",
        "找到、移動和回復視窗": "找到、移動和回復視窗",
        "擷取視窗畫面做預覽": "擷取視窗畫面做預覽",
        "在任何應用裡都能用。點“錄製…”再按下新的組合；“清除”會關掉這個快速鍵。": "錄製或清除全域性快速鍵",
        "一下讓開所有置頂的視窗，再按一下按原來的前後順序放回": "讓開置頂視窗，再按放回",
        "視窗留在原處，在別的桌面上也能看一眼": "在其他桌面看一眼",
        "視窗靠到螢幕邊、浮在前面；再按一次收到螢幕邊，或拉出來": "側拉，再按收到螢幕邊",
        "視窗縮成一張即時畫面浮在螢幕角落，再按一次回到原處；把標題列拖到螢幕角落停一下也行": "即時畫面懸在螢幕角落",
        "列出所有 App；把圖示拖到螢幕邊就側拉，拖到一邊就開在那一半": "拖 App 圖示來安排視窗",
        "捲簾條展開；原來大小的視窗鋪滿螢幕": "展開卷簾條或鋪滿視窗",
        "鋪滿的視窗回到原來大小；原來大小的視窗收起": "還原視窗大小或收起",
        "把這塊螢幕上的視窗一次排好：要地方多的佔大頭，聊天放側拉；捏合整批撤回": "按需要分配視窗位置",
        "按原來的排法放到下一塊螢幕上；上下襬的顯示器也行": "保留排法，移到另一螢幕",
        "這塊螢幕上的視窗全部收進瀏海，再按一下放回來": "整螢幕收進瀏海，再按放回",
        "只把當前視窗收進瀏海": "只收進當前視窗",
        "裝過 Rectangle 的照它現在的設定，沒裝過的用它推薦的那一套（⌃⌥ 加方向鍵和字母）。下面的名字和 Raycast 的視窗命令一一對應": "沿用 Rectangle 快速鍵",
        "變小一級、變大一級、左半螢幕、右半螢幕改用 ⌃⌥ 加字母，和 Swish 一樣。別的動作在用的組合不搶": "部分排列改用字母快速鍵",
        "左右不動，上下佔滿": "左右不動，上下佔滿",
        "大小不變，放到正中": "大小不變，放到正中",
        "四邊各往外 30 點": "四邊各往外 30 點",
        "四邊各往裡 30 點": "四邊各往裡 30 點",
        "回到排之前的位置和大小": "回到排列前的位置和大小",
        "和“移到另一塊螢幕”反著轉": "反向移到另一塊螢幕",
        "外觀選“統一標題列”時，改為專注當前 App；選“縮圖”時，把縮圖排到螢幕下邊，再按放回原位": "按外觀整理視窗或縮圖",
        "預設不設定。再按一次同一個組合會關掉面板。": "再按同一快速鍵關閉面板",
        "在 Dock 圖示上看這個應用的全部視窗，也可以用選單或快速鍵開啟。": "從 Dock 檢視應用視窗",
        "滑鼠停在 Dock 圖示上時顯示視窗面板。不會啟動沒在執行的應用。": "停留 Dock 圖示檢視視窗",
        "它已經在最前、視窗露著時才這樣（和 Windows 工作列一樣）；再點一下回來": "再點前台應用，讓開視窗",
        "往上滑看這個 App 的所有視窗，往下滑讓開這個 App": "上滑檢視，下滑讓開",
        "指標碰到別的螢幕的底邊時 Dock 不跟過去（只管放在底部的 Dock）；開啟時記下 Dock 現在在哪": "不讓底部 Dock 跟隨指標",
        "指標指著哪扇就關哪扇，⌘Q 退出它的 App；只在指揮中心開著時這樣，平時不動你的 ⌘W": "在指揮中心關閉所指視窗",
        "預設不佔用快速鍵，可以在“快速鍵”裡設定": "快速鍵預設留空",
        "按住連按 Tab 一扇一扇地挑，鬆手切過去；收著的視窗也在裡面。選 ⌘Tab 會換掉系統的 App 切換": "按 Tab 挑視窗，鬆手切換",
        "選中視窗 0.4 秒後開始播放即時畫面": "選中 0.4 秒後播放預覽",
        "開啟系統的“減少透明度”時，自動使用不透明背景。": "跟隨系統減少透明度",
        "自動：視窗多的時候用列表，少的時候用縮圖。面板裡的切換隻影響這一次。": "根據視窗數量自動切換",
        "在視窗右鍵選單裡選“排布”：左半、右半、四角、置中、鋪滿螢幕、移到另一塊螢幕。可以先看效果，移好之後還能還原。": "右鍵選單快速排布視窗",
        "識別 Dock 圖示，切換、收起、展開和關閉視窗": "識別 Dock 圖示並操作視窗",
        "視窗縮圖與即時預覽；缺失時顯示圖示和文字列表": "無錄螢幕權限時顯示列表",
        "WindowShade 會在登入後自動執行": "登入後自動執行",
        "需要在系統設定中批准登入項": "需在系統設定中批准",
        "開機後自動執行 WindowShade": "開機後自動執行",
        "當前 app bundle 不支援登入項": "此版本不支援登入項",
        "Swish 正在執行，標題列上的手勢交給它；在捲簾條上往下滑仍可展開": "Swish 接管標題列手勢",
        "在標題列上兩指滑動、捲動滾輪或拖著甩一下：往上收起，往下鋪滿": "標題列手勢：上收下鋪",
        "開始、暫停或繼續同一個番茄鍾；預設不佔用任何快速鍵": "預設不佔鍵，開始或暫停",
        "捲簾條跟原來一樣或用統一標題列，也可以在原處縮成縮圖": "跟原來一樣、統一標題列或縮圖",
        "讓它更透一些，能看到後面的內容": "更透，能看到後面",
        "WindowShade 讀到的每一樣都列在這裡。": "讀到的都列在這裡",
        "有新版本時在選單裡告訴你，不會自己裝。": "有新版時告訴你，不自動裝",
        "新版本用著不對，可以換回剛才那一版。": "可以換回剛才那一版",
        "合上或開啟蓋子時，桌面跟著動一下。": "合上或開啟時桌面跟著動",
        "回復預設值，或開啟診斷日誌排查問題。": "回復預設，或開啟診斷日誌",
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
        "computermouse", "arrow.up.arrow.down", "rectangle.2.swap", "hand.tap",
        "cursorarrow.and.square.on.square.dashed", "switch.2", "speaker.wave.2",
        "chevron.left.forwardslash.chevron.right", "terminal", "numbers", "character.bubble",
        "circle.lefthalf.filled", "power", "arrow.triangle.2.circlepath", "stethoscope",
        "arrow.counterclockwise", "menubar.rectangle",
        "dock.rectangle", "arrow.2.squarepath", "pause", "arrow.left.arrow.right",
        "eye.slash", "square.grid.2x2",
        "macwindow.on.rectangle", "paintbrush", "livephoto", "record.circle",
        "bell", "waveform", "hand.raised", "tray", "clock", "arrow.left.and.right",
        "square.on.square", "doc.on.doc", "arrow.down.circle", "plus.magnifyingglass",
        "minus.magnifyingglass", "display", "rectangle.bottomthird.inset.filled",
        "arrow.uturn.backward", "lock", "slider.horizontal.3",
    ]

    nonisolated static func tableSymbol(_ name: String?) -> String? {
        guard let name, tableSymbols.contains(name) else { return nil }
        return name
    }

    /// 一行里放得下的短句。全文更长时由气泡保留，不在这里截掉意思。
    nonisolated static func line(_ subtitle: String) -> String {
        if let mapped = short[subtitle] { return mapped }
        // 繁体：传进来的已经是繁体全文，查繁体短句表（键与 short 对称，用全文）。
        if WSL10n.language == .zhHant, let mapped = shortHant[subtitle] { return mapped }
        // 英文走这条老路的只有拼出来的页头（隐私页）：按英文预算在词边界截，隐私页头另有短句。
        if WSL10n.language == .en, WSL10n.englishBundle != nil {
            if subtitle == WS2PrivacyCopy.headerSubtitle() {
                return WSL10n.text("settings.privacy.headerShort", zh: "读到的都列在这里，不统计不上报")
            }
            return cutEnglish(subtitle)
        }
        if subtitle.count <= cjkLineBudget { return subtitle }
        if let range = subtitle.range(of: "个应用") {
            let head = String(subtitle[..<range.upperBound])
            if head.count <= cjkLineBudget { return head }
        }
        return cutAtBudget(subtitle)
    }

    /// 中文（简体、繁体）一行副标题的字数预算。规格 R24（Aaron 选 B）：原来的 16 字是拍脑袋的，
    /// 实际一行放得下的远不止——900×680 窗口里，只有开关的行约 35 字，带录制按钮的快捷键行约 13 到 25 字。
    /// 取 40 作兜底线：超过它的全文才收成「…」并出 ⓘ；40 以内的句子靠布局层省略（label 自己带「…」），
    /// 放不下的行在 short／shortHant／shortEn 里写短句。逐行的实测见 docs/handoff/R24-copy-proposal-2026-10-17.md。
    nonisolated static let cjkLineBudget = 48

    /// 兜底截到预算：被截就以省略号收尾，不留半个字（规格 R24）；全文仍在 ⓘ 与 tooltip 里。
    nonisolated private static func cutAtBudget(_ text: String) -> String {
        text.count <= cjkLineBudget ? text : String(text.prefix(cjkLineBudget)) + "…"
    }

    /// 英文一行里放得下的字符量级（第27批；R24 放宽）。34 是第27批的保守校准，
    /// 实测只有开关的行约 70 个拉丁字符能放下；放不下的带控件行写在 shortEn 里。
    nonisolated static let englishLineBudget = 90

    /// 英文超预算时在词边界截断并以「…」收尾，不把单词劈开。
    nonisolated private static func cutEnglish(_ shown: String) -> String {
        guard shown.count > englishLineBudget else { return shown }
        var head = String(shown.prefix(englishLineBudget))
        if let cut = head.lastIndex(of: " "), head.distance(from: head.startIndex, to: cut) >= englishLineBudget - 12 {
            head = String(head[..<cut])
        }
        return head + "…"
    }

    /// 迁移过的行的短副标题（第27批）：zh 时与老路径逐字节相同；en 先查 shortEn（按目录键，
    /// 语义身份），没有就在词边界截断——不把单词劈开。繁体（第39批）按繁体全文查 shortHant，
    /// 查不到就跟简体同口径按 16 字截。全文都在气泡与 tooltip 里。
    nonisolated static func line(_ subtitle: SettingsText) -> String {
        switch WSL10n.language {
        case .en where WSL10n.englishBundle != nil:
            if let mapped = shortEn[subtitle.key] { return mapped }
            return cutEnglish(subtitle.shown)
        case .zhHant:
            let shown = subtitle.shown
            if let mapped = shortHant[shown] { return mapped }
            return cutAtBudget(shown)
        default:
            return line(subtitle.zh)
        }
    }

    /// 英文短副标题表：目录键 → 一句能站住的英文短句。与中文 short 表同样的角色，
    /// 只给英文行长预算里放不下的行。用词与目录里的英文译文保持同一套词汇。
    nonisolated static let shortEn: [String: String] = [
        "settings.shade.sub": "How windows roll up, how a bar looks, and sound",
        "settings.shade.doubleClick.sub": "Double-click any title bar",
        "settings.shade.doubleClick.subZoom": "A triple-click zooms the window",
        "settings.shade.doubleClick.subMinimize": "A triple-click minimizes the window",
        "settings.shade.glance.sub": "Glance without unrolling",
        "settings.shade.tuckNotch.sub": "Flick to tuck, click to bring back",
        "settings.shade.notchAlerts.sub": "The notch opens when a title changes",
        "settings.shade.activities.sub": "Music, accessories, transfers, routes",
        "settings.shade.origin.sub": "Tips follow your old habits",
        "settings.shade.gap.sub": "A gap between windows and screen edges",
        "settings.shade.splitHandle.sub": "Drag the middle bar to resize both",
        "settings.shade.floating.sub": "Rolled-up windows stay in front",
        "settings.shade.fileShelf.sub": "Files you drop on the notch wait here",
        "settings.shade.downloads.sub": "Watch the Downloads folder",
        "settings.shade.copyProgress.sub": "Show copy progress at the notch",
        "settings.shade.carplay.sub": "Long-press the notch for full screen",
        "settings.shade.deviceBattery.sub": "The notch says when a device connects",
        "settings.shade.collapse.sub": "Keep, one consistent bar, or thumbnail",
        "settings.shade.calendar.subNotAsked": "Counts down before meetings; macOS asks once",
        "settings.shade.calendar.subGranted": "Counts down; join when there's a link",
        "settings.shade.focus.tuck": "Tuck chats while focusing",
        "settings.shade.focus.presetTooltip": "New lengths apply from the next round.",
        "settings.shade.focus.tuckTooltip": "Only windows from the private app list.",
        "settings.shade.focus.noteCounting": "For now it only counts time.",
        // R24：带录制按钮的快捷键行，预算放宽后仍放不下的两句。
        "settings.shortcuts.focusTimer.sub": "Starts, pauses or resumes the focus timer",
        "settings.shortcuts.countdownTimer.sub": "Pick minutes, then Return",
        "settings.advanced.sub": "Reset defaults, or open the diagnostics log",
        "settings.advanced.diagnostics.sub": "Open the diagnostics log",
        "settings.advanced.reduceMotionHint": "Turn on Reduce motion in System Settings",
        "settings.language.sub": "Takes effect immediately",
        "conductor.settings.intro": "Sessions, model slots and drafts",
        "conductor.settings.hookConfig.sub": "Paste it into Claude Code's settings",
    ]

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
            // 第34批补：此前这些行没有图标（鼠标与触控板、指挥、遥控、窗口浏览等页）。
            ("平滑滚动", "scroll"),
            ("鼠标滚动方向", "computermouse"),
            ("触控板滚动方向", "arrow.up.arrow.down"),
            ("精细", "arrow.up.arrow.down"),
            ("侧键", "rectangle.2.swap"),
            ("三指轻点", "hand.tap"),
            ("四指轻点", "hand.tap"),
            ("要避开的", "cursorarrow.and.square.on.square.dashed"),
            ("私人 App", "lock.shield"),
            ("指挥模式", "switch.2"),
            ("提示音", "speaker.wave.2"),
            ("编程会话", "chevron.left.forwardslash.chevron.right"),
            ("Claude Code 的配置", "terminal"),
            ("模型位置", "numbers"),
            ("遥控", "appletvremote.gen4"),
            ("界面语言", "character.bubble"),
            ("外观", "circle.lefthalf.filled"),
            ("开机自启", "power"),
            ("启动", "power"),
            ("更新", "arrow.triangle.2.circlepath"),
            ("诊断", "stethoscope"),
            ("重置", "arrow.counterclockwise"),
            ("暴露", "rectangle.inset.filled"),
            ("排列", "rectangle.grid.1x2"),
            ("菜单栏", "menubar.rectangle"),
            ("在菜单里", "menubar.rectangle"),
            ("键盘", "keyboard"),
            // 第35批补（同批离屏核对发现的缺口）：
            ("Dock 悬停", "dock.rectangle"),            ("再点一下 Dock", "dock.rectangle"),
            ("两指上下滑", "dock.rectangle"),
            ("Dock 留在", "dock.rectangle"),
            ("调度中心里按", "rectangle.expand.vertical"),
            ("按窗口切换", "arrow.left.arrow.right"),
            ("桌面开合", "arrow.2.squarepath"),
            ("暂停效果", "pause"),
            ("收起窗口时的动画", "rectangle.compress.vertical"),
            ("把当前窗口带到每张桌面", "arrow.left.arrow.right"),
            ("打开窗口浏览", "rectangle.on.rectangle"),
            ("按应用排除", "eye.slash"),
            ("面板背景", "circle.lefthalf.filled"),
            ("默认显示方式", "square.grid.2x2"),
            ("排布与撤销", "rectangle.grid.1x2"),
            // 第36批补（图标缺口清零）：
            ("预览对象", "macwindow.on.rectangle"),
            ("预览样式", "paintbrush"),
            ("实时预览", "livephoto"),
            ("屏幕录制权限", "record.circle"),
            ("恢复动态效果默认值", "arrow.counterclockwise"),
            ("标题栏手势", "hand.tap"),
            ("有变化时提醒", "bell"),
            ("回来时说一下", "bell"),
            ("实时活动", "waveform"),
            ("跟着声音跳", "waveform"),
            ("正在播放", "music.note"),
            ("计时器到时间响一声", "timer"),
            ("开始计时器", "timer"),
            ("浏览器下载", "arrow.down.circle"),
            ("合成一排", "rectangle.split.2x1"),
            ("悬停不误触", "hand.raised"),
            ("文件架", "tray"),
            ("之前常用", "clock"),
            ("窗口之间留缝", "arrow.left.and.right"),
            ("浮在其他窗口上面", "square.on.square"),
            ("收起和展开时播放音效", "speaker.wave.2"),
            ("收起音效", "speaker.wave.2"),
            ("展开音效", "speaker.wave.2"),
            ("拷贝进度", "doc.on.doc"),
            ("设备的电量", "battery.75percent"),
            ("方言", "character.bubble"),
            ("整理卷帘条", "rectangle.compress.vertical"),
            ("变大一级", "plus.magnifyingglass"),
            ("变小一级", "minus.magnifyingglass"),
            ("移到另一块屏幕", "display"),
            ("移到上一块屏幕", "display"),
            ("上半屏", "rectangle.topthird.inset.filled"),
            ("下半屏", "rectangle.bottomthird.inset.filled"),
            ("撤销上次排布", "arrow.uturn.backward"),
            ("并进左", "rectangle.grid.1x2"),
            ("并进右", "rectangle.grid.1x2"),
            ("离开就锁", "lock"),
            ("随身设备", "iphone"),
            ("检查频率", "clock"),
            ("当前版本", "info.circle"),
        ]
        for (needle, symbol) in pairs where name.contains(needle) {
            return symbol
        }
        return nil
    }

    /// 设置行左侧：圆角色块里的符号（有才放）、名字、至多一行副标题，说不完的进 info.circle。
    /// 跟着枚举留在主线程：这里建的是 AppKit 视图。调用方都是主线程类型。
    static func content(name: String?, subtitle: String?, symbol: String? = nil) -> (view: NSStackView, detail: NSTextField?) {
        content(name: name, subtitle: subtitle, shownLine: subtitle.map { line($0) },
                symbol: symbol ?? name.flatMap { Self.symbol(for: $0) })
    }

    /// 行内一句状态 + ⓘ 里另给一段解释的行（鼠标与触控板、遥控器页）：行内显示短句，
    /// ⓘ 与 tooltip 显示解释；两者都走同一张目录表，随语言切换。
    static func content(name: SettingsText?, subtitle: SettingsText?, detail: SettingsText?, symbol: String? = nil) -> NSStackView {
        // 行内只显示状态短句（subtitle 与 shownLine 相同 → 不触发自动 ⓘ），
        // 详情单独给一个 ⓘ，避免同一行出现两个 ⓘ。
        let short = subtitle.map { line($0) }
        let built = content(name: name?.shown, subtitle: short, shownLine: short,
                            symbol: symbol ?? name.flatMap { Self.symbol(for: $0.zh) })
        if let detail {
            let caption = (name?.shown.isEmpty == false ? name!.shown : WSL10n.text("settings.info.caption", zh: "说明"))
            built.view.addArrangedSubview(WS2SettingsInfoButton(text: detail.shown, name: caption))
            WS2SettingsCopy.pinInfoTrailing(built.view)
        }
        return built.view
    }

    /// 迁移过的行（第27批）：zh 是语义身份——图标按它查；显示文本与短副标题走当前语言。
    /// zh 模式下与本文件里的 String 版逐字节同输出（line 的 zh 分支就是老路径）。
    static func content(name: SettingsText?, subtitle: SettingsText?, symbol: String? = nil) -> (view: NSStackView, detail: NSTextField?) {
        content(name: name?.shown, subtitle: subtitle?.shown,
                shownLine: subtitle.map { line($0) },
                symbol: symbol ?? name.flatMap { Self.symbol(for: $0.zh) })
    }

    static func content(name: String?, subtitle: String?, shownLine: String?, symbol: String?) -> (view: NSStackView, detail: NSTextField?) {
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
        if let subtitle, let shown = shownLine {
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
        if let subtitle, let shown = shownLine, shown != subtitle {
            let caption = (name?.isEmpty == false ? name! : WSL10n.text("settings.info.caption", zh: "说明"))
            content.addArrangedSubview(WS2SettingsInfoButton(text: subtitle, name: caption))
        }
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return (content, detail)
    }

    /// 行容器里把 ⓘ 钉到内容列右端：标签列吸收多余宽度，ⓘ 落在内容列的右端。
    /// NSStackView 的 gravityAreas 不按 hugging 分余量，所以用显式约束。
    /// 只给设置行用；页头不是行，不调用（页头 ⓘ 保持贴文字）。
    static func pinInfoTrailing(_ content: NSStackView) {
        guard let button = content.arrangedSubviews.compactMap({ $0 as? WS2SettingsInfoButton }).first else { return }
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in content.arrangedSubviews where view is NSStackView {
            view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }
        content.trailingAnchor.constraint(equalTo: button.trailingAnchor).isActive = true
    }
}

/// 设置行：内容列（图标 + 标题副标题 + ⓘ）与右边的控件列。
/// 不变式在这里强制：行构造时就把 ⓘ 钉在自己控件的左侧（间距 spacing）——
/// 调用方拼行时不需要记得调 pinInfoTrailing，谁用这个行容器都不会漏。
/// 控件同宽的卡（整卡开关）ⓘ 自然连成一条竖线；宽窄不一的卡一行一个位置，紧跟控件。
final class WS2SettingsRow: NSStackView {
    private let content: NSStackView
    private let control: NSView?

    init(content: NSStackView, control: NSView?, leadingInset: CGFloat = 0, trailingInset: CGFloat = 0, spacing: CGFloat = 14) {
        self.content = content
        self.control = control
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        self.spacing = spacing
        addArrangedSubview(content)
        content.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset).isActive = true
        if let control {
            (control as? NSControl)?.sizeToFit()
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            addArrangedSubview(control)
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingInset).isActive = true
            content.trailingAnchor.constraint(equalTo: control.leadingAnchor, constant: -spacing).isActive = true
            WS2SettingsCopy.pinInfoTrailing(content)
        } else {
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -trailingInset).isActive = true
        }
    }
    required init?(coder: NSCoder) { nil }
}
final class WS2SettingsInfoButton: NSButton {
    private let fullText: String
    private var popover: NSPopover?
    init(text:String,name:String) {
        fullText = text; super.init(frame:.zero)
        let described = WSL10n.text("settings.info.label", zh: "%@的说明", name)
        image = NSImage(systemSymbolName:"info.circle",accessibilityDescription: described)
        isBordered = false; imagePosition = .imageOnly
        target = self; action = #selector(showInfo); toolTip = text
        setAccessibilityLabel(described)
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
