# 卡住时刘海开口：旧习惯规则表

2026-09-29。方向见 [direction.md](direction.md)：刘海只在他卡住时开口，教 Mac 的做法，不把旧系统搬过来。
Aaron 给的出处：Apple《Mac 鍵盤上的 Windows 鍵》（cpmh0152）、《Mac 上的詞彙說法？》（cpmh0038）、《Mac 鍵盤快速鍵》（102650），
并要求把 iPad 的手势习惯一起充分调研。两部分都先由几组分别起草，再由专门找误报的复核逐条反驳，最后合成。

## 一页看完

- **只在两件事都有证据时开口**：刚才那一下在这里没反应（或做了别的、而且他马上撤回、又去找），而刘海要教的那一下在这里一定管用。说的只有“Mac 上按哪一下 / 点哪里”。
- **来处决定开哪几条**：欢迎窗口问一句“之前常用哪个”。答 Windows 开 Windows 那一半；答 iPad 开 iPad 那一半；
  没答的只开几条不会误报的；从习惯推断出来的来处不直接开规则，只在刘海上问一句要不要按那边的习惯提示（推断的依据就是这些习惯，会自己证实自己）。
- **永远不说的地方**：终端、IDE 和自带 ⌃ 快捷键的编辑器、Office、设计软件、虚拟机和远程桌面（包括网页版）、游戏、改过键的人、密码框、正在组字、VoiceOver、演示和共享屏幕。
- **节奏和手势提示共用一本账**：同一条最多三次；他自己用过 Mac 那一下，这条永远不再说；任意两条提示之间至少隔五分钟；点一下不再提示。
- **iPad 那一半最要紧的是“做了别的”**：⌘H 把 App 藏起来（iPad 上是回主屏幕）、🌐H 变成显示桌面、三指上滑变成调度中心、三指横滑换了桌面、绿色按钮把 App 关进单独的全屏空间、从 Dock 拖出图标会把它移除。屏幕变了，他不会以为自己按错，而是以为 Mac 坏了。
- **还要先上真机确认的**：系统吃掉的键和手势（🌐 组合、三指四指滑动）WindowShade 能不能先看到；PC 键盘的 Print Screen 到 Mac 上是不是 F13；苹果拼音单按 ⇧ 是否确实没反应。确认之前，这些规则不开。

## 第一部分：Windows 的快捷键

### 1. 原则，以及刘海什么时候说话

**一句话原则**：只在两件事都有证据时说一句：刚才按的那一下在这里什么都没做，而刘海要教的那一下在这里一定管用。说的内容只有“Mac 上按哪一下”。

**什么时候说**

- **默认在第一次按下后说。** 按键后等约 0.8 秒宽限（W）。这段时间里如果他自己按了 Mac 的那一下，就不说，并把这条记成“会了”。没按的话，再看事后检查（P）：约 300ms 后剪贴板、前台 App、窗口数、屏幕上的新窗口都没有变化，就开口。第一次说的理由是：Windows 用户按一下没反应，接着就去找鼠标或菜单了；等他按第二次，常常已经错过卡住的那一刻。只有在“没反应”有硬证据时才用这条路，例如剪贴板没变、菜单里没有这个组合、Cocoa 也没绑定这个键。
- **证据弱时，要在 4 秒内再按一次同一组合（R）才说。** 适用于浏览器和网页 App、Electron/CEF 应用、到达的组合在别处有 Mac 含义的情况。网页可以自己处理 ctrlKey，菜单里看不出来；用户连按两次仍然没反应，才算真卡住。“⌃C 没生效，60 秒内又按 ⌃V”这一对也算作第二次。
- **只对欢迎窗口里答“Windows”的人说（仅 Windows）。** 适用于到达的组合本身就是 Mac 老用户的正常动作，例如单按 ⌘、单按 ⇧、F11、⌘L、⌘.。
- **来历决定开哪几条。** 答 Windows 的人：全部开。没答的人：只开标“任何来历”的几条。答“一直用 Mac”或 iPad 的人：这一类全部关掉，因为 iPad 外接键盘的按法和 Mac 一样。

**表里用到的缩写**

| 缩写 | 含义 |
| --- | --- |
| G | 公共门：刘海和“在刘海上教”都开着；App 不在第 3 节的名单里；这个组合没被 WindowShade 占用；修饰键完全一致（屏蔽 fn、numericPad、capsLock 位）；不是自动重复 |
| M | 菜单证据：前台 App 菜单里有 Mac 那一下，而且没有到达的这个组合；菜单读不到就不说 |
| P | 事后检查：约 300ms 后前台、焦点窗口和标题、窗口数、layer>0 的窗口都没变 |
| W | 宽限期：0.8 秒内他自己按了 Mac 那一下，就不说，并记成“会了” |
| R | 4 秒内又按一次同一组合 |
| 文本 | 焦点是可编辑文本 |
| 非文本 | 焦点**明确**是列表、表格、访达图标视图、桌面或网页正文。报成粗元素（AXWindow、AXGroup、Chromium 的 AXWebArea）时当作“不知道”，不说 |

### 2. 规则表

所有行都默认满足 G、W、P，表里不再重复。“刘海说的话”一栏里，加粗的是主句，下一行是副句。

#### 第一批（先上）

| 旧习惯 | 按下去实际收到 | Mac 上的做法 | 刘海说的话 | 什么时候才说 | 出处 |
| --- | --- | --- | --- | --- | --- |
| Ctrl+C 复制 | ⌃C（Mac 键盘和 PC 键盘都一样） | ⌘C | **Mac 上复制按 ⌘C**<br>常用快捷键把 ⌃ 换成 ⌘ | M，300ms 内剪贴板 changeCount 没变，第一次；浏览器和网页 App 要 R。任何来历 | 102650；cpmh0152 |
| Ctrl+V 粘贴 | ⌃V | ⌘V | **Mac 上粘贴按 ⌘V**<br>常用快捷键把 ⌃ 换成 ⌘（光标翻了一页时改成“⌃V 在 Mac 上是往下翻页”） | 文本 + M + 有前因：60 秒内有一次没生效的 ⌃C/⌃X，或者剪贴板 2 分钟内变过、期间没按过 ⌘C/⌘X（说明是右键菜单拷贝的） | 102650；cpmh0152 |
| Ctrl+Z 撤销 | ⌃Z | ⌘Z；重做 ⇧⌘Z | **Mac 上撤销按 ⌘Z**<br>重做是 ⇧⌘Z | 原生 App：文本 + M，第一次。浏览器：R，并且两次按完后 AXNumberOfCharacters 都没变 | 102650；cpmh0152 |
| Ctrl+S 保存 | ⌃S | ⌘S | **Mac 上保存按 ⌘S**<br>常用快捷键把 ⌃ 换成 ⌘ | 只在原生 App：M（菜单里有 ⌘S），第一次。第一批不在浏览器里做。任何来历 | 102650；cpmh0152 |
| 单按 Shift 切换中英文（微软拼音） | 单独一下 ⇧ | 开了“用大写锁定键切换 ABC”时轻按 Caps Lock；否则 ⌃空格 | **切换中英文：轻按 Caps Lock**<br>按住它才是大写锁定（另两种主句：“切换中英文按 ⌃空格”“……按一下 🌐”，按用户设置选） | 仅 Windows。输入源是苹果拼音、双拼或五笔；从按下到松开，keyDown、鼠标、滚轮、系统定义事件的计数都没变；前后没有紧接着打字；200ms 后输入源没变；20 秒内第二次才说。**上线前要实机确认苹果拼音单按 ⇧ 确实没反应** | mchl84525d76；102650 |
| Ctrl+W 关标签页 | ⌃W | ⌘W；退出按 ⌘Q | **关标签页按 ⌘W**（用菜单里 ⌘W 那一项的标题）<br>App 不会跟着退出，退出按 ⌘Q（前台是访达时不说这句：访达没有退出） | 非文本，或者焦点是浏览器地址栏；M；原生 App 第一次，浏览器要 R。前台是访达时不说“退出按 ⌘Q”这半句：访达不能退出 | 102650；cpmh0152 |
| Ctrl+X 剪切 | ⌃X | ⌘X | **Mac 上剪切按 ⌘X**<br>常用快捷键把 ⌃ 换成 ⌘ | 条件同 ⌃C，另外要求有选中内容（选区长度 >0，或访达里有选中项）。任何来历 | 102650；cpmh0152 |
| 资源管理器里选中文件按 Delete | Mac 键盘是 ⌫；PC 键盘的 Del 是 ⌦，Backspace 是 ⌫ | ⌘⌫ | **移到废纸篓按 ⌘⌫**<br>废纸篓就是回收站 | 在访达里；焦点是文件列表，不是改名框或搜索框；有选中项；前 1 秒内没按字母（排除按名字选文件）；第一次。任何来历 | 102650；cpmh0038 |
| Home / End 到行首、行尾 | PC 键盘是 Home/End；Mac 键盘上 fn← / fn→ 发的是同一个键码 | ⌘← / ⌘→ | **到行首、行尾按 ⌘← ⌘→**<br>Home、End 在 Mac 上只滚动页面 | 文本；按之前 1 秒内没有 fn 键按下（排除 Apple 键盘的 fn←）；120ms 后光标没到行首或行尾，而且可见范围也没滚动；带参属性读不到就不说 | cpmh0152；102650 |
| Ctrl+Shift+Esc、Ctrl+Alt+Del | ⌃⇧esc；PC 键盘 ⌃⌥⌦；Mac 键盘 ⌃⌥⌫ | ⌥⌘esc；看占用用活动监视器 | **强制退出 App 按 ⌥⌘esc**<br>看谁占资源，打开“活动监视器” | 第一次。⌃⌥⌫ 只在非文本时说。VoiceOver 开着时不说。任何来历 | 102650；cpmh0038 |
| Alt+F4 关窗 | PC 键盘 ⌥F4；Mac 键盘 ⌥fn F4 | ⌘W；⌘Q | **关掉窗口按 ⌘W**（用菜单里 ⌘W 那一项的标题）<br>退出整个 App 按 ⌘Q（前台是访达时不说这句：访达没有退出） | 菜单里没有这个组合（读不到也照说，因为它在 Mac 上没有含义）；第一次。任何来历。前台是访达时不说“退出按 ⌘Q”这半句：访达不能退出 | 102650；cpmh0152 |
| Print Screen | PC 键盘上是 F13；Alt+PrtSc 是 ⌥F13（**要实机确认**） | ⇧⌘4 / ⇧⌘3 / ⇧⌘5 | **截一块屏幕按 ⇧⌘4**<br>整屏按 ⇧⌘3；加按 ⌃ 存进剪贴板（⌥F13 时主句改成“截这扇窗口：⇧⌘4 再按空格”） | 仅 Windows；接着非 Apple、非 Karabiner 的外接键盘；系统、菜单、WindowShade 都没占用 F13；Stream Deck、OBS、Discord 没在运行；第一次 | cpmh0152；cpmh0038；102646 |
| 按住 Alt 打小键盘编码出符号 | 按住 ⌥ 再按小键盘数字 | ⌃⌘空格（表情与符号） | **打特殊符号按 ⌃⌘空格**<br>在“表情与符号”里搜名字 | 文本；按住 ⌥ 期间按了 ≥2 个小键盘数字，松开后字数多了同样多；“鼠标键”没开；输入源不是 Unicode 十六进制；第一次 | cpmh0152；102650 |

#### 第二批（检测代码和第一批相同，真机验证后再开）

| 旧习惯 | 按下去实际收到 | Mac 上的做法 | 刘海说的话 | 什么时候才说 | 出处 |
| --- | --- | --- | --- | --- | --- |
| Ctrl+A 全选 | ⌃A | ⌘A | **Mac 上全选按 ⌘A** | 非文本（列表类）；M；浏览器里只在 Safari 正文 | 102650；cpmh0152 |
| Ctrl+F 查找 | ⌃F | ⌘F | **Mac 上查找按 ⌘F** | 非文本；M；浏览器里只在 Safari，要 R，并且 300ms 内页面没滚动 | 102650；cpmh0152 |
| Ctrl+T 新建标签页 | ⌃T | ⌘T | **新建标签页按 ⌘T** | 只在浏览器或访达；非文本；M；浏览器要 R | 102650；cpmh0152 |
| Ctrl+R 刷新网页 | ⌃R | ⌘R | **刷新网页按 ⌘R** | 只在浏览器；非文本；M；R | 102650 |
| Ctrl+Home / End | PC 键盘 ⌃Home / ⌃End | ⌘↑ / ⌘↓ | **到开头、结尾按 ⌘↑ ⌘↓** | 文本且有字；fn 判断同 Home；光标没到开头或结尾 | 102650 |
| Win+D 显示桌面 | PC 键盘 ⌘D | 系统“显示桌面”的实际键（默认 F11） | **显示桌面按 F11**<br>苹果键盘上按 fn F11 | 仅 Windows；标准窗口、没有表单；不在网页、Electron 或 CEF 里；100ms 后菜单读得到，而且没有可用的 ⌘D | 102650 |
| Win+E 打开资源管理器 | PC 键盘 ⌘E | ⌥⌘空格 | **找文件按 ⌥⌘空格**<br>也可以点 Dock 最左边的访达 | 同 Win+D；焦点不在文本 | 102650；cpmh0038 |
| Win+L 锁屏 | PC 键盘 ⌘L | ⌃⌘Q | **锁屏按 ⌃⌘Q**<br>刚才屏幕没锁上 | 仅 Windows；条件同 Win+D；等他离开再回来、有输入时才说 | 102650 |
| Win+Shift+S 框选截图 | PC 键盘 ⇧⌘S | ⇧⌘4；⇧⌘5 | **截一块屏幕按 ⇧⌘4**<br>要更多选项按 ⇧⌘5 | 仅 Windows；原生 App、标准窗口；菜单读得到而且没有可用的 ⇧⌘S；P 里没有出现截图框 | cpmh0038；cpmh0152 |
| 单按 Win 键找程序 | PC 键盘单按一下 ⌘ | ⌘空格 | **找 App、文件按 ⌘空格**<br>也可以点一下刘海回到主屏幕 | 仅 Windows；PC 键盘；期间没有别的键、点击或系统定义事件；不是连按两下；输入源没变；接着至少 2 个字母落在非文本处；30 秒内第二次 | cpmh0152；cpmh0038 |
| Win+. 表情面板 | PC 键盘 ⌘. | ⌃⌘空格 | **输入表情按 ⌃⌘空格**<br>苹果键盘上按 fn E 也行 | 仅 Windows；文本、标准窗口；不在网页或 Electron 里；菜单里没有 ⌘.；20 秒内第二次 | 102650 |
| Alt+Shift / Ctrl+Shift 切换输入法 | 只按两个修饰键 ⌥⇧ / ⌃⇧ | ⌃空格 | **切换输入法按 ⌃空格**<br>有 🌐 键的话，按一下 🌐 | 仅 Windows；至少两个输入源；各种计数都不变；没有菜单在跟踪；输入源没变；20 秒内第二次 | 102650 |
| Alt+Tab（“按窗口切换”改掉或关掉时） | ⌥Tab | ⌘Tab；⌘` | **切换 App 按 ⌘Tab**<br>同一个 App 的窗口按 ⌘` | 只在“按窗口切换”的触发键不是 ⌥ 时；仅 Windows；AltTab、Witch 等没在运行；焦点不在文本 | cpmh0038；102650 |
| F11 全屏 | F11 触发了系统的“显示桌面” | ⌃⌘F | **全屏按 ⌃⌘F**<br>刚才那下是显示桌面，再按一次回来 | 仅 Windows；“显示桌面”仍是 F11；前台窗口能全屏，而且不是访达。这是本类唯一一条“出了别的事”的情况，因为窗口全飞走了，同样是卡住 | 102650；cpmh0038 |
| 访达里按 Enter 打开 | return 进入改名 | ⌘↓ | **打开文件按 ⌘↓**<br>return 在 Mac 上是改名 | 按 return 出现改名框，1.5 秒内又按 return 或 esc，中间没打字；并且 5 秒内用双击或 ⌘O 打开了同一项，或者一小时内第二次出现这个顺序。只要他曾经按 return 后打字改过名，这条永远不说 | 102650；mchlp1144 |
| F2 改名 | PC 键盘 F2；Mac 键盘 fn F2 | 选中后按 return | **改名：选中后按 return** | 在访达里；恰好选中一项；仅 Windows 或非 Apple 键盘；1.5 秒内没有亮度键事件 | mchlp1144 |
| Ctrl+Shift+N 新建文件夹 | ⌃⇧N | ⇧⌘N | **新建文件夹按 ⇧⌘N** | 在访达里；非文本；M | 102650 |

### 3. 永远不说的地方

| 场合 | 名单（bundle id 写进代码前先在本机核实） | 怎么认 |
| --- | --- | --- |
| WindowShade 自己 | 设置里正在录快捷键；按窗口切换面板；调度中心；窗口浏览 | 目标 pid 等于自己；`WindowSwitcherKeys.isActive`；`MissionControlPick.isActive`；`announce()` 返回 false |
| 虚拟机、远程桌面、Windows 兼容层 | com.microsoft.rdc.macos、com.microsoft.rdc.mac、com.parallels.*（含 winapp.*）、com.vmware.fusion、com.vmware.proxyApp.*、com.utmapp.UTM、org.virtualbox.app.VirtualBoxVM、com.citrix.receiver.*、com.omnissa.horizon.client.mac、com.vmware.horizon、com.amazon.workspaces、com.apple.ScreenSharing、com.apple.RemoteDesktop、com.realvnc.vncviewer、com.teamviewer.TeamViewer、com.philandro.anydesk、com.p5sys.jump.mac.viewer、com.carriez.rustdesk、com.splashtop.*、com.edovia.screens.*、tv.parsec.www、com.moonlight-stream.Moonlight、com.codeweavers.CrossOver、com.isaacmarovitz.Whisky、com.apple.iphonesimulator | 按 bundle id 前缀；前台进程没有 bundle id（Wine、qemu、裸 Java 进程），或可执行路径里含 wine 时也不说 |
| 网页里的远程桌面和网页 IDE | remotedesktop.google.com、windows365.microsoft.com、client.wvd.microsoft.com、shell.cloud.google.com 等 Cloud Shell、vscode.dev、github.dev、replit.com、codesandbox.io、stackblitz.com、colab、Jupyter、overleaf.com | 能读到 AXURL 时比对网址；PWA（com.google.Chrome.app.*、com.microsoft.edgemac.app.*、com.brave.Browser.app.*、com.apple.Safari.WebApp.*）按浏览器处理 |
| 终端，包括网页终端 | com.apple.Terminal、com.googlecode.iterm2、com.mitchellh.ghostty、dev.warp.Warp-Stable、net.kovidgoyal.kitty、org.alacritty、com.github.wez.wezterm、co.zeit.hyper、org.tabby、com.termius-dmg.mac、com.vandyke.SecureCRT、com.lemonmojo.RoyalTSX.App，以及 Prompt 3、Rio、Wave | 只能靠 bundle id，因为终端内容区的角色也是 AXTextArea。网页终端看焦点的 AXDescription 是否为 “Terminal input”（xterm.js） |
| 自己绑定 ⌃ 键或 Home/End 的编辑器、IDE | com.microsoft.VSCode(Insiders)、com.vscodium、Cursor（com.todesktop.230313mzl4w4u92）、com.exafunction.windsurf、dev.zed.Zed、com.sublimetext.*、com.jetbrains.*、com.google.android.studio、com.apple.dt.Xcode、org.gnu.Emacs、org.vim.MacVim、com.qvacua.VimR、com.neovide.neovide、com.barebones.bbedit、com.panic.Nova | bundle id；VS Code 系的分支看 App 包里有没有 `Contents/Resources/app/product.json`；Electron 编辑器（例如 Obsidian）在文本焦点下，整个 ⌃ 家族都不说 |
| 自己认 ⌃ 快捷键的 Office | com.microsoft.Excel、Word、Powerpoint、Outlook、onenote.mac、com.kingsoft.wpsoffice.mac | bundle id。Excel 已由微软文档确认，其余保险起见一起排除 |
| 设计和 3D 软件 | com.figma.Desktop（⌃C 是取色）、Sketch、org.blenderfoundation.blender、com.maxon.cinema4d、com.autodesk.*、com.sketchup.* | bundle id；网页版 figma.com 按网址 |
| 游戏 | Info.plist 的 LSApplicationCategoryType 含 games；Steam 目录下的程序；全屏、隐藏菜单栏、没有 AXMenuBar 的前台 App | 分类字段 + 可执行路径 + M。游戏没有“编辑”菜单，M 本身就是游戏最主要的护栏 |
| 安全输入、锁屏 | 密码框；开了“安全键盘输入”的终端；com.apple.loginwindow | `IsSecureEventInputEnabled()`。这时本来也收不到按键 |
| 用户自己改过键 | ~/Library/KeyBindings/DefaultKeyBinding.dict；修饰键对调（-currentHost 的 com.apple.keyboard.modifiermapping.*）；Karabiner、BetterTouchTool、Hammerspoon、Keyboard Maestro、cmd-eikana、Input Source Pro 在运行 | 启动时和文件改动后读 dict：里面绑定过的 ⌃ 组合当作已占用。先按对调映射还原组合再匹配。有映射工具在运行时，关掉单按修饰键的几条和 F13 |
| 第三方全局热键 | Raycast、Alfred、Keyboard Maestro、BetterTouchTool、Stream Deck、OBS、Discord 一键通话 | 菜单和 CopySymbolicHotKeys 都查不到，全靠 P：前台、窗口、layer>0 窗口有任何变化就不说 |
| 正在组字、辅助功能开着 | 输入法有待确认文字；VoiceOver（⌃⌥ 是 VO 键）；粘滞键、鼠标键、慢速键；全键盘控制 | 读焦点的 AXMarkedTextRange；`NSWorkspace.isVoiceOverEnabled`；com.apple.universalaccess。慢速键开着时，R 和 W 的时间窗按比例放宽 |
| 演示和共享屏幕 | 正在共享或录制屏幕、Keynote 或 PowerPoint 在播放、全屏视频 | 录屏指示状态、前台全屏窗口 |
| 已经是 Mac 老手 | 欢迎窗口答“一直用 Mac”或 iPad；在文本里用 ⌃A/E/K/N/P 并且光标变化证明生效了；已经用过 3 个不同的 ⌘ 版本 | 整个 ⌃ 家族永久不说 |

### 4. 怎么认“没反应”：落到这个代码库

**现状**：`EventTapCallback.swift`（由 `WindowShade.swift:858` 的 `setupEventTap()` 创建）只收 leftMouseDown。`EventTap.swift` 的键盘部分是 Carbon `RegisterEventHotKey`，不是按键监听。现在能看到按键的钩子只有两个：`WindowSwitcher.swift` 里的 `WindowSwitcherKeys`（headInsert，吞 ⌥Tab，旁听 ⌘Tab）和 `MissionControlKeys.swift`，而且都依赖各自的设置。所以需要新加一个观察者。

1. **只听、不吞**（新文件 `prototype/App/HabitKeys.swift`）
   - 钩子：`CGEvent.tapCreate(.cgSessionEventTap, .tailAppendEventTap, .defaultTap)`，收 keyDown 和 flagsChanged，回调永远原样放行，在自己的线程上跑，写法照 `MissionControlKeys`。不用 `.listenOnly`，因为它要额外申请“输入监控”授权。可以先用 `CGPreflightListenEventAccess()` 实测，已经授权的话就直接用 `.listenOnly`。
   - 放在 tail 的好处：被 WindowShade 吞掉的键（默认的 ⌥Tab、调度中心里的 ⌘W/⌘Q）根本到不了它。
   - 回调里只做 O(1) 的事：按键码和四个修饰位查表，跳过 `kCGKeyboardEventAutorepeat`，记下事件时间戳。同一张表里也有 Mac 那一下（⌘C、⌘⌫、⇧⌘4……），用来实现 W 和“会了”。
   - 目标 App：用 `kCGEventTargetUnixProcessID`，拿不到时读 system-wide 的 `AXFocusedApplication`。Spotlight、Raycast 的面板收键时，frontmostApplication 是底下那个 App，不准。
   - 隐私：不记字符，不读 AXValue；wlog 只写规则 id、bundle id 和判定结果。
2. **菜单证据 M**（新文件 `prototype/App/HabitContext.swift`）
   - 放在自己的串行队列上，`AXUIElementSetMessagingTimeout` 设 0.3s。读取方式照 `WindowBrowserNewWindow.swift`：用 `AXUIElementCopyMultipleAttributeValues` 读 CmdChar、CmdModifiers、CmdVirtualKey、Enabled，每个菜单最多 60 项。
   - 某个 pid 第一次命中候选按键时才扫一次，按 pid 缓存 `{(字符或虚拟键, 修饰) → 标题}`；App 退出或重启时作废。
   - 修饰编码：0 表示只有 ⌘，1 ⇧，2 ⌥，4 ⌃，8 表示不带 ⌘。例如 ⌃C 是 (C,12)，⌘C 是 (C,0)。
   - 平时不信缓存里的启用状态。只有 Win+D/E/L/⇧S 这几条，在按键后约 100ms 单独重读那一项的 AXEnabled。
3. **焦点**
   - 读 system-wide `kAXFocusedUIElement` 的 role 和 subrole，看有没有 AXEditableAncestor；再读焦点窗口的 subrole，看上面有没有 AXSheet。
   - 粗元素一律当作“不知道”。Electron、CEF、QtWebEngine 的判断看包里的 Frameworks。
   - 不为这个功能去设 AXManualAccessibility 或 AXEnhancedUserInterface，那会拖慢对方 App。
4. **事后检查 P**
   - 300ms 后比较：前台 pid、焦点窗口号和标题、这个 App 的窗口数、CGWindowList 里 layer>0 的新窗口、`NSPasteboard.changeCount`。
   - 个别规则还要看 AXSelectedTextRange、AXNumberOfCharacters、AXVisibleCharacterRange。
   - 这些都是元数据，不需要录屏权限。
5. **纯逻辑**（新文件 `prototype/Core/HabitRules.swift`，测试放 `tests/HabitRulesTests.swift` 并配运行脚本）
   - 内容：规则表，R/W/配对（⌃C→⌃V）的状态机，来历开关，已占用组合，⌃ 家族整体静音。
   - 测试只测判定边界：修饰键精确匹配、自动重复、时间窗、占用集合、来历开关。
6. **已占用组合**
   - `EventTap.swift` 的 `registerGlobalShortcuts()` 结束时重新算一遍：所有 GlobalShortcut 的当前组合（去掉注册失败的）、开着时的 ⌃⌘1…9、`WindowBrowserSettings.hotKey`、`WindowSwitcherKeys.trigger`，再加上 DefaultKeyBinding.dict 里绑定过的 ⌃ 组合。
   - 要教的 Mac 组合被用户录给了 WindowShade 时，这一条也不说。
7. **教学节奏：和手势提示共用一份记录**（改 `prototype/Core/GestureCoach.swift`）
   - 加 `habitShown`、`habitUsed`、`habitDismissed`，和手势提示共用 `lastShownAt`。
   - 每条最多 3 次；点一下这条永远不再出；用户自己用过 Mac 那一下，这条永远不再教；任意两条提示之间（包括手势提示）至少隔 5 分钟。
   - ⌃C 之后紧接着卡在 ⌃V 也不再说，因为副句“常用快捷键把 ⌃ 换成 ⌘”已经一次教了整个家族。
8. **显示**
   - 在 `prototype/App/Notch.swift` 新增 `teachHabit(_:)`，照 `teach()` 写（tone `.tip`，点击后 dismiss）。
   - 副句占用 subtitle，“点一下，不再提示这一条”改到第二次显示时才出现。
   - 在 `prototype/App/NotchCoach.swift` 的 `NotchDemoView` 里加一种键帽演示，例如“⌃C → ⌘C”。
9. **接线**
   - `prototype/WindowShade.swift`：跟着 `Notch.isEnabled && Notch.teachEnabled` 装上或拆掉 `HabitKeys`。
   - `prototype/App/Preferences.swift`：加“之前常用”设置（Windows / iPad / 一直用 Mac / 没答）。
   - `prototype/App/Welcome.swift`：加那一问（direction.md 里的第 2 项）。
   - `prototype/App/ProbeEntries.swift` 和新的 `HabitProbe.swift`：做下面的实机探针。
10. **开工前要在真机上确认**
    1. PC 键盘的 PrtSc 是否到达为 F13。
    2. 苹果拼音单按 ⇧ 是否确实没反应（包括组字途中）。
    3. 放在 tail 的钩子能不能看到 F11、⌘空格，以及第三方 Carbon 热键吃掉的键；同时和 `NSEvent.addGlobalMonitorForEvents` 对照。
    4. 按键约 100ms 后读到的 AXEnabled 是不是新的。
    5. PC 键盘直接按 Home 时，确实不产生 fn 的 flagsChanged。
    6. 按键被别的钩子吞掉时，HID 计数是否照样增加。
    7. Chrome 在不开无障碍时，焦点能报到多细。

### 5. 被复核否掉的规则

- **Ctrl+Y 重做**：⌃Y 是 Cocoa 的 yank，Emacs 派在用；⌃Z 的副句已经教了 ⇧⌘Z。
- **Ctrl+Shift+Z 重做**：用得少，⌃Z 的副句已经覆盖。
- **Ctrl+O 打开**：在文本里会插入换行，属于“出了别的事”。
- **Ctrl+P 打印、Ctrl+N 新建**：在文本里是上移、下移一行，在 Spotlight、Raycast 的列表里是上一项、下一项，Emacs 派天天用。
- **Ctrl+Backspace、Ctrl+←/→ 按词操作**：按了有反应（删一个字、切换桌面），留给“按了但结果不对”那一类。
- **Ctrl+Delete 向后删一个词**：只有 PC 键盘能按出来，也没有便宜的办法验证有没有生效。
- **Delete 向后删**：按下去是正常的退格，没有卡住的信号，只能在欢迎窗口里讲。
- **F5 刷新**：没有权威来源说明各浏览器在 Mac 上响不响应 F5；判断页面有没有重新载入又得给 Chrome 挂 AXObserver，代价太高。先核实。
- **Ctrl+滚轮缩放**：可能是系统的整屏缩放，也可能是网页画布的缩放，而且不是键盘快捷键。
- **Win+Tab、Win+V、Win+I、Win+S、Win+R、Win+方向键**：到达的 ⌘ 组合在 Mac 上处处有用，判断不了“没反应”。
- **Ctrl+Tab**：在 Mac 上照样能切换标签页。
- **Ctrl+空格开关输入法**：在 Mac 上也是切换输入法，按了有用。
- **单按 Alt 或 F10 激活菜单栏**：误报太多，教 ⌃F2 对多数人帮助也不大。
- **Ctrl+Insert / Shift+Insert**：几乎只在终端里用，而终端已经整类排除；等第一批跑顺了再说。
- **Num Lock、Scroll Lock、Pause**：小键盘本来就能打数字，F14/F15 按了屏幕会变亮变暗，不算卡住。
- **Mac 顶排当 F 键用**：和日常调亮度、调音量分不开。
- **AltGr 打符号**：要按每种布局维护对照表，先面向中文用户。
- **Ctrl+点击多选、Caps Lock 打大写、Win+空格切输入法**：按了有反应，只是反应不对，放到下一类。
- **触控板右下角当右键**：不是快捷键。
- **留给下一类，没有在这里评估**：
  - 按位置按到 fn/🌐：例如 fn+C 打开控制中心。
  - 按位置按成 ⌥ 加字母：打出 ´、®、∂。
  - 微信截图 Alt+A 到达为 ⌥A。
  - Win+Ctrl+←/→ 到达为 ⌃⌘←/→，正好撞上 WindowShade 的左半屏、右半屏。
  - Alt+Enter 看属性（Mac 上是 ⌘I）。

## 第二部分：iPad 的手势和快捷键

结论先放前面：iPad 用户带来的习惯里，最后留下 **22 条要开口的规则**。其中 8 条是按键，14 条是触控板、指针或窗口动作，另有 5 组查过但不开口。

最该先做的是这几条：“做了别的事”里最常见的 ⌘H、🌐H、三指上滑、三指横滑，以及 WindowShade 自己造成的撞车：双击标题栏、往上甩标题栏、点刘海想回到页面顶部。

所有规则有两个共同前提。一是只对欢迎窗口里明确选了 iPad 的人启用。二是凡依赖“系统吃掉的键或手势还能不能先到 WindowShade”的规则，要等探针确认后才上线（探针清单见第 5 节）。

---

### 1. 调研了什么

#### iPad 这一侧

现行版本是 iPadOS 27，引用时逐页对比了 26 和 27 两版。

| 来源 | 版本 | 用到的内容 |
| --- | --- | --- |
| [Learn iPad keyboard shortcuts（102393）][ipad-kb] | 2025-09-15 版（iPadOS 26）起改成 🌐 系列；2026-09-14 版按 27 / 26 / 18 及更早分节，快捷键表没变 | 🌐H/A/⇧A/C/N/M/F/E/D、⌃🌐 加方向键、⌃⇧🌐 加方向键、⌘空格、⌘Tab、⌘W、⌘M、⇧⌘3/4 |
| [同一篇的存档][ipad-kb-2024] | 2024-11-22 版（iPadOS 17/18） | ⌘H 回主屏幕、⌘⌥D 显示 Dock、按住 ⌘ 看快捷键。26 版起这三条都从文档删了 |
| [Multitask on iPad（125309）][ipad-multitask] | iPadOS 26 及以后，2026-09-14 更新；侧拉从 26.2 起 | 🌐↑ 打开 Exposé、窗口控件、甩一下贴半屏、菜单栏、侧拉 |
| [触控板手势][ipad-tp]、[鼠标操作与手势][ipad-mouse] | 18、26、27 三版逐字相同，仍沿用“App 切换器”“指针推过右边缘开侧拉”的旧说法 | 三指上滑、横滑，四指捏合，指针推边、推角，两指下滑搜索，两指右滑看今天视图 |
| [导航手势][ipad-nav]、[多窗口][ipad-windows]、[改变窗口布局][ipad-layout]、[台前调度][ipad-stage] | 26、27 | 底边上滑、Exposé、双击顶部铺满、往上甩铺满、从 Dock 拖图标、侧拉 |
| [菜单栏 26][ipad-menubar-26] / [菜单栏 27][ipad-menubar-27] | 26 写“从顶部正中下滑”，27 改成“点状态栏里的 App 名，或指针停在上面” | 🌐M、顶边 |
| [通知 26][ipad-notif-26] / [通知 27][ipad-notif-27] | 26 写“从顶部正中下滑”，27 改成“从左上角下滑” | 左上角、顶边正中 |
| [使用快捷键][ipad-shortcuts]、[切换键盘][ipad-switch-kb]、[全键盘控制][ipad-fkc] | 26、27 | 按住 ⌘ 或 🌐 看快捷键表、单按 🌐、⌃空格、Caps Lock 切换中英文 |
| [快捷操作][ipad-quick]、[退出 App][ipad-quit]、[Safari][ipad-safari]、[编辑文字][ipad-text]、[触控板设置][ipad-tp-settings] | 27 | 按住出菜单、在 Exposé 里往上甩退出、点顶边回页首、三指编辑、轻点来点按 |
| [iPadOS 26 新闻稿][newsroom-26]、[2026-09 发布新闻稿][newsroom-27] | 2025-06 / 2026-09 | 窗口系统；27 没有新的指针或窗口手势 |

#### Mac 这一侧

本机是 macOS 27.0，引用的页面都是 26 和 27 两版。

| 来源 | 用到的内容 |
| --- | --- |
| [Mac 键盘快捷键（102650）][mac-kb]，2026-09-14 | fn-H 显示桌面、fn-A、fn-⇧A（App）、fn-C、fn-N、fn-Q、fn-E、fn-D、⌘H、⌃↑、fn-⌃F 填充 |
| [触控板手势（102482）][mac-tp]，2026-05-06 | 调度中心写四指，注明“某些版本用三指” |
| [三指拖移（102341）][mac-3fdrag] | 打开后，三指滑动都移到四指 |
| [调度中心][mac-mc]、[多个桌面空间][mac-spaces]、[全屏][mac-fullscreen]、[App][mac-apps] | 使用手册写三指上滑；空间页、全屏页写“三指或四指，看设置” |
| [平铺窗口][mac-tile]、[平铺快捷键][mac-tile-keys]、[窗口][mac-windows]、[桌面与程序坞设置][mac-dock-settings]、[Dock][mac-dock] | 拖到边上平铺、绿色按钮菜单、连按标题栏的设置、“拖到顶部进入调度中心”、拖出 Dock 会移除 |
| [菜单栏][mac-menubar]、[通知][mac-notif]、[控制中心][mac-cc]、[触发角][mac-corners]、[小组件][mac-widgets]、[聚焦搜索][mac-spotlight] | 左上角是苹果菜单，通知中心和控制中心都在右上角；右下角默认触发角是快速备忘录 |
| [键盘设置][mac-kbd-settings]、[输入法][mac-input]、[辅助点按][mac-rightclick]、[触控板设置][mac-tp-settings]、[截屏（102646）][mac-shot]、[macOS 27 新功能][mac-new27]、[Safari 快捷键][safari-keys] | 按下 🌐 键时、Caps Lock 切换 ABC、两指点按、轻点来点按、⇧⌘4 十字线、下拉刷新、⌘↑ |

本机设置是用只读 `defaults` 读出来的，不是出厂值：

- 三指拖移开，三指滑动关，四指上滑是调度中心、四指横滑切空间；
- 轻点来点按开；
- Dock 不自动隐藏，右下角触发角是快速备忘录；
- 台前调度关；
- `com.apple.HIToolbox` 里没有 `AppleFnUsageType`。

所以在这台机器上，iPad 的三指动作会变成拖动，而不是打开调度中心。

#### 代码这一侧

只读看过的文件：`Notch.swift`、`TrackpadGestures.swift`（PinchEventTap，CGEvent 类型 29；flickMonitor）、`EventTap.swift`、`WindowShade.swift:859`（mouseDown tap）、`MissionControlKeys.swift`、`WindowSwitcher.swift`、`Core/MissionControlPick.swift`（ExposeShieldWindow）、`DockLock` / `DockHoverObserver` / `DockClickHide`、`GestureCoach.swift`、`GlobalShortcuts.swift`、`Welcome.swift`。

#### 没能核实的

1. **⌘H 和 ⌘⌥D 在 iPadOS 26/27 上还有没有用。** 文档已经删了，这两个习惯只来自 18 及更早的用户。
2. **按住 ⌘ 看快捷键，两份官方文档说法冲突。** 使用手册 26/27 版仍写按住 ⌘ 看快捷键；102393 把它归到“18 及更早”，并说 26/27 要在菜单栏里看。
3. **双击顶部铺满、往上甩铺满的原文要回源再核一次。** 这两条在 [多窗口][ipad-windows] 页里。
4. **Mac 上 fn-M、fn-F 的实际效果。** Apple 的 Mac 列表里都没有；全屏的官方快捷键是 ⌃⌘F。
5. **几个 Mac 默认值 Apple 没写。** 包括“按下 🌐 键时”、轻点来点按、Caps Lock 切换 ABC 的出厂状态，以及按住 🌐 再松开会不会触发它的动作。
6. **只见于第三方资料的 iPad 手势，没列入。** 包括 🌐← / 🌐→ 切 App、三指轻点弹出编辑条、三指捏合回主屏幕；四指或五指捏合回主屏幕只出现在 iPadOS 26 之前的归档文章里。
7. **iPadOS 15–18 窗口顶部正中的“···”多任务按钮没查。** Mac 上点标题栏正中，在访达和文稿类 App 里会弹出路径或重命名菜单，可能属于“做了别的”，待补查。
8. **Mac 桌面平铺后的两扇窗口能不能一起改大小，官方没写。** 系统的分屏浏览（在全屏空间里）能一起改。

### 2. iPad 习惯落到 Mac 上的三种结果

- **没反应。** 例子：按住 ⌘ 等快捷键表、🌐M、指针再往下推一次回主屏幕、在桌面上两指下滑找搜索、推右边缘找侧拉。用户会再试一次或去搜索，不算坏事，只是慢。
- **做了别的。** 例子：⌘H 把整个 App 藏起来；🌐H 变成显示桌面；🌐↑ 变成向上翻页；三指上滑变成调度中心，开了三指拖移时变成拖动；三指横滑变成换桌面；绿色按钮把 App 关进单独的全屏空间；从 Dock 拖出图标会把它移除；点左上角打开的是苹果菜单。
- **一样。** 例子：编辑用的 ⌘ 键、⌘Tab、⌘空格、⌘W、⌘M、⇧⌘3、⌃空格、🌐A/⇧A/C/N/Q/E/D、⌃🌐 加方向键、两指点按、滚动和缩放、拖窗口、拖边角。WindowShade 默认打开标题栏手势后，甩一下贴半屏也算一样。这类刘海永远不开口。

**“做了别的”最让人困惑**，原因有三：

- **看起来像成功或坏了。** 屏幕确实变了，用户不会以为自己按错，而是以为 Mac 坏了或窗口丢了。
- **要自己撤回。** 被隐藏的 App、被换走的桌面、被移除的 Dock 图标，都得先知道 Mac 的做法才能还原；“没反应”至少不用收拾。
- **结果是正当的 Mac 功能。** 同一个结果，Mac 老用户每天有意在用，所以最难判断是不是卡住，第 4 节的误报条件主要就是为这一类写的。

### 3. 规则表

#### 所有规则共用的前提

1. **只认明确选了 iPad 的人。** 欢迎窗口里目前没有这个问题（`Welcome.swift` 只有七页介绍），需要新加一个“来源”偏好。根据习惯推断的结果不能直接打开规则：推断的依据就是这些习惯，第一次出现就会自己证实自己，只能用来建议他去设置里改（见第 7 节）。
2. **沿用 GestureCoach 的限制。** 同一条最多说三次，全局冷却 5 分钟。卡住提示要优先于普通提示（悬停刘海的 `.notchHome`、收起后的 `.shade` / `.shake`），否则会被抢掉。每条规则都要新加一个 `CoachTip` case，因为每个 case 只有一句固定文字（`GestureCoach.swift:37-51`）。教“回到主屏幕”的四条（三指上滑、🌐H、⌘H、指针往下推）共用一个“已学会”分组：他自己点过一次刘海回到主屏幕，四条一起闭嘴。
3. **提示被点时的行为要改。** 现在点一下提示等于“不再提示这一条”（`Notch.swift:545-550`）。用户照着“点一下刘海”去点，拿到的是提示被永久关掉，而不是主屏幕。见第 7 节。
4. **没有刘海的屏幕要换教法。** 隐形刘海空着时不在屏上（`Notch.swift:1095` 会 `orderOut`），“点一下刘海”点不到。开口时靠 `alertInfo` 让它露面，教法改成读启动台快捷键的实际绑定。⌃⌘L（启动台）和 ⌃⌘S（侧拉）都是 1.0.16 才加的默认键（`GlobalShortcuts.swift:223`），这一版还没发布；升级时如果和用户已有的快捷键冲突，会被关掉。所以文案一律读当前实际绑定，没绑定就不提快捷键。
5. **按键只建一个共用的会话级 tap。** 用 `.cgSessionEventTap`、`.headInsertEventTap`、`.defaultTap`，回调原样放行，写法照 `MissionControlKeys.swift:100`。不复用 `WindowSwitcher` 的 tap，因为它跟着切换器的开关走。不会被系统吃掉的键，也可以用 `NSEvent` 全局 keyDown 监听，`WindowBrowserController.swift:2327` 有先例。
6. **设置一律读出来再判断，不写死。** 要读的有：
   - 触控板：`com.apple.AppleMultitouchTrackpad`，外接妙控板是 `com.apple.driver.AppleBluetoothMultitouch.trackpad`。键包括 `TrackpadThreeFingerDrag`、三指和四指的竖滑与横滑、`TrackpadFourFingerPinchGesture`、`Clicking`；全局的 `com.apple.mouse.tapBehavior` 也要读。
   - Dock：`com.apple.dock` 的 `autohide`、Dock 方向、`wvous-*` 触发角、`showMissionControlGestureEnabled`。
   - 滚动方向：`isDirectionInvertedFromDevice`。
   - 多显示器：相邻的是哪条边。
   - 输入法：启用了几个。
7. **刘海文字按 [`docs/copy-guide.md`](copy-guide.md) 写。** 用到的固定词汇有：回到主屏幕、调度中心、收起窗口、铺满屏幕、侧拉、调度中心里按 ⌘W 关窗、已隐藏。通知中心、控制中心、聚焦搜索、填充这四个词表里还没有，沿用 Apple 的叫法，建议补进词汇表。

#### 规则

按频率排，常见的在前。表中的“探针”编号见第 5 节。

| # | 旧习惯 | Mac 收到的 | Mac 默认会怎样 | Mac 上的做法 | 刘海说的话 | 什么时候才说 | 出处 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 单按一下 🌐 切换中英文 | flagsChanged 键码 63，0.3 秒内松开，中间没有别的键 | 执行“按下 🌐 键时”的设置：切换输入法、表情与符号、听写或不操作。设成切换输入法以外的动作时属于“做了别的” | ⌃空格（⌃⌥空格切到下一个）；或把“按下 🌐 键时”改成“更改输入法” | 切换输入法按 ⌃空格 | 启用的输入法至少两个。单按 🌐 后 1 秒内没有输入法切换通知（`kTISNotifySelectedKeyboardInputSourceChanged`），10 秒内他又用 ⌃空格、菜单栏的输入法菜单或 Caps Lock 换成功了；出现两次。不读设置，只看结果 | [切换键盘][ipad-switch-kb] · [键盘设置][mac-kbd-settings] |
| 2 | 触控板三指上滑回主屏幕 | 三指竖滑开着时，这是系统的调度中心手势（App 收不到）；开了三指拖移时是拖动。PinchEventTap 只能看到手指数变化 | 打开调度中心，窗口铺开；开了三指拖移时拖动指针下的东西 | 回到主屏幕：点一下刘海。系统的全部 App：拇指加三指捏合，或 🌐⇧A | 回到主屏幕：点一下刘海 | 调度中心在手指数达到设置里的滑动指数后 0.5 秒内打开（按需轮询 ExposeShieldWindow），而且不是按键、触发角或刘海打开的；3 秒内关掉，最前面的窗口没变。关掉后 8 秒内他去点 Dock 上别的 App、打开聚焦搜索或“App”、或停到刘海上：一次就说。没有这些后续：10 秒内两次才说。三指拖移开着时不启用，交给第 11 条 | [触控板手势][ipad-tp] · [调度中心][mac-mc] · [102482][mac-tp] · [102341][mac-3fdrag] |
| 3 | 三、四、五指左右滑切换 App | 系统的切换空间手势；开了三指拖移时是拖动 | 在桌面空间和全屏 App 之间切换；只有一张桌面时画面弹一下 | ⌘Tab；按窗口切换用 ⌥Tab | 切换 App 按 ⌘Tab，和 iPad 一样 | 只认“没切成”：PinchEventTap 加了横向位置跟踪后，横向走过触控板宽度 30% 以上，却没有 `activeSpaceDidChange`。5 秒内他用 ⌘Tab 或 Dock 切了 App：一次就说；否则 1 分钟内两次。等探针 3 | [触控板手势][ipad-tp] · [台前调度][ipad-stage] · [空间][mac-spaces] |
| 4 | 按住一个东西不放，等快捷菜单 | leftMouseDown 后 0.8 秒以上不动也不松 | 大多数地方没反应；用力按是查询或快速查看 | 两指点按，或按住 Control 点按 | 菜单要两指点按，和 iPad 一样 | 按在链接、图片、访达文件或桌面空白处（看 AX 角色）。排除文本输入区和可编辑文字、按钮类、Dock、标题栏、滚动条，也排除用力按（stage 2）。按住 0.8 秒以上、移动不到 4 点，松开后 0.3 秒内没出现弹出菜单窗口（layer 101）；1 分钟内两次。他自己用过一次两指点按，就永久闭嘴 | [快捷操作][ipad-quick] · [辅助点按][mac-rightclick] |
| 5 | 按 🌐H 回主屏幕（iPadOS 26/27） | 键码 63，再键码 4 带 fn。系统会吃掉这个组合，只有会话 tap 可能看到 | 显示桌面 | 回到主屏幕：点一下刘海；全部 App：🌐⇧A | 这是显示桌面；回到主屏幕点一下刘海 | 只在选了 iPad 后 30 天内、而且他还没自己点过刘海回主屏幕时生效。🌐H 后 3 秒内又按 🌐H 把窗口叫回来，期间指针移动不到 50 点、没点桌面；随后 10 秒内他从 Dock、聚焦搜索或“App”去开别的 App；出现两次。等探针 1 | [102393][ipad-kb] · [102650][mac-kb] |
| 6 | 按 ⌘H 回主屏幕（iPadOS 17/18 的老习惯） | 键码 4，修饰键只有 ⌘；交给前台 App 的“隐藏”菜单项 | 隐藏前台 App，它的窗口全部消失 | 回到主屏幕：点一下刘海。找回被隐藏的 App：点 Dock 图标、⌘Tab，或点刘海一排里的“已隐藏” | ⌘H 是隐藏 App；回到主屏幕点一下刘海 | ⌘H 后 0.5 秒内同一个 pid 收到 `didHideApplication`，而且它隐藏前有屏上窗口。之后满足任一种：(a) 隐藏期间他没在别的 App 里按键或点按，8 秒内又把它找回来；(b) 3 秒内连按两次 ⌘H，藏掉两个不同的 App。第一次就说。排除 ⌥⌘H、卷帘条转发的 ⌘H、DockClickHide 做的隐藏 | [102393（2024 存档）][ipad-kb-2024] · [102650][mac-kb] |
| 7 | 双击窗口顶部，让窗口铺满（WindowShade 造成的撞车） | 标题栏双击，被 WindowShade 的 mouseDown tap 接走 | 装了 WindowShade：收起窗口；只有系统时：按“连按窗口标题栏”的设置 | 往下甩一下标题栏，或在标题栏上两指轻点两下：铺满屏幕；系统的填充是 🌐⌃F | 双击是收起窗口；往下甩是铺满屏幕 | 只对还没用会卷帘的人：累计收起不到 3 次，也从没有收起后停过 10 秒以上。双击收起后 3 秒内又展开同一扇，10 秒内又试着放大它（点绿色按钮、拖边角、按 🌐⌃F、在标题栏上往下拉）：说一次。之后只要他有一次收起停过 10 秒，就永久闭嘴。同时压住 `.shade` / `.shake` 提示 | [多窗口][ipad-windows] · [桌面与程序坞设置][mac-dock-settings] · `docs/gestures.md` |
| 8 | Dock 出来后，把指针再往下推一次回主屏幕 | 指针在底边，仍有向下的位移 | 什么也不发生 | 回到主屏幕：点一下刘海 | 回到主屏幕：点一下刘海 | 只在 Dock 自动隐藏、Dock 在底部、这块屏下面没有别的屏时启用。出现两段分开的向下推（每段原始 deltaY 累计 80 点以上，中间停 0.3 秒以上，不算惯性），没点 Dock 就离开；30 秒内两次。去掉“点底部横条”那一半。等探针 4 | [触控板手势][ipad-tp] · [鼠标][ipad-mouse] · [Dock 设置][mac-dock-settings] |
| 9 | 点左上角的时间日期看通知 | leftMouseDown 落在苹果菜单上 | 打开苹果菜单 | 点菜单栏最右边的日期和时间；或两指从触控板右边缘往左划；🌐N | 通知中心：点右上角的日期和时间 | 指针快速冲到左上角（x < 40、贴着顶边）按下，苹果菜单打开，2 秒内没选任何项就关掉；2 分钟内两次，期间没打开过通知中心。不看刘海和顶边正中 | [触控板手势][ipad-tp] · [通知 27][ipad-notif-27] · [通知][mac-notif] |
| 10 | 点绿色的全屏按钮，想让窗口铺满 | 点在 `AXFullScreenButton` 上 | 进入 macOS 全屏：App 进到单独的空间，菜单栏和 Dock 藏起来 | 按 🌐⌃F，或指针停在绿色按钮上选“填充”；WindowShade 里往下甩标题栏 | 只想铺满屏幕：按 🌐⌃F | 进入全屏后 15 秒内又退出，退出后 10 秒内手动拖边角放大，或把指针停到绿色按钮上找菜单：说一次。只看绿色按钮的点击，不看 🌐F | [多窗口][ipad-windows] · [全屏][mac-fullscreen] · [平铺][mac-tile] |
| 11 | 往上甩窗口顶部让窗口铺满；或开了三指拖移时，三指上滑正好落在标题栏上 | 标题栏向上快甩，由 flickMonitor 接住 | 装了 WindowShade：收起窗口，甩向刘海会收进刘海；只有系统时：拖过顶边会打开调度中心 | 往下甩一下标题栏是铺满屏幕 | 往上甩是收起窗口，往下甩是铺满屏幕 | 前提同第 7 条（还没用会卷帘）。甩上去 3 秒内撤回，10 秒内又试着放大。手指数是 3 且开了三指拖移时，改说第 2 条那句，并要求撤回后 8 秒内有找 App 的动作 | [多窗口][ipad-windows] · [平铺][mac-tile] · `docs/gestures.md` |
| 12 | 按 ⇧⌘4，想截屏后马上标记 | 键码 21，修饰键正好是 ⇧⌘；这是系统的截屏热键 | 指针变成十字线，要拖出一块区域才截 | ⇧⌘3 截整屏后点角落的缩略图；或 ⇧⌘5 | 截整屏按 ⇧⌘3，再点缩略图标记 | ⇧⌘4 后 5 秒内按 Esc，或没按空格就原地单击、没拖动；60 秒内两次，中间没按过 ⇧⌘3 或 ⇧⌘5。不看截图目录。热键和 Esc 能不能先到 tap，都等探针 1 | [102393][ipad-kb] · [102646][mac-shot] |
| 13 | 按住 ⌘ 不放，想看快捷键表 | flagsChanged ⌘ 按下，1 秒以上没有别的键，然后松开 | 什么都不出现 | 点开菜单栏的菜单，快捷键写在每一项右边；⇧⌘/ 可以搜命令 | 快捷键写在菜单里每项右边 | 单独按住 ⌘ 1.5 秒以上后松开，期间没有按键、滚动或鼠标按下，指针移动不到 20 点；2 分钟内两次。CheatSheet、KeyClu 这类快捷键表 App 在运行时不启用。上线前先用小样量一周 Mac 老用户的误报 | [使用快捷键][ipad-shortcuts] · [102393][ipad-kb] |
| 14 | 在“主屏幕”（到了 Mac 就是桌面）两指下滑，找搜索 | 两指 scrollWheel，指针下没有 App 窗口 | 什么也不发生 | ⌘空格，和 iPad 键盘上一样 | 搜索按 ⌘空格，和 iPad 一样 | 指针下没有 layer 0 窗口，也不在桌面小组件上。一次完整的两指手势（began 到 ended，不算惯性），按滚动方向设置换算回手指方向后，向下 80 点以上；10 秒内两次。刘海的主屏幕里下滑本来就会打开聚焦搜索 | [触控板手势][ipad-tp] · [聚焦搜索][mac-spotlight] |
| 15 | 四指捏合后停住，找 App 切换器 | 系统把它当成拇指加三指捏合 | 打开“App”，列出全部 App，不是正在运行的 | 看打开的窗口用调度中心：连点两下刘海，或 ⌃↑ | 看打开的窗口：连点两下刘海 | 手指数到 4 以上后 1 秒内“App”打开（怎么认出它还没实测），接触保持 0.4 秒以上，3 秒内关掉，没开任何 App。关掉后 5 秒内他打开调度中心或按了 ⌘Tab：一次就说；否则 2 分钟内两次 | [触控板手势][ipad-tp] · [App][mac-apps] |
| 16 | 按 🌐↑，想看最近的 App（Exposé） | 先看到键码 63，再看到键码 116（Page Up） | 向上翻一页 | ⌃↑ 或调度中心键；连点两下刘海是调度中心，点三下是这个 App 的所有窗口 | 调度中心：按 ⌃↑，或连点两下刘海 | 只在焦点位于访达桌面、或前台焦点区域根本没有 `AXScrollArea` 时判断。3 秒内按两次以上，1 秒内调度中心没打开。焦点在任何能滚动的区域里，包括已经滚到顶的，一律不说。放第二批 | [125309][ipad-multitask] · [102650][mac-kb] |
| 17 | 把 App 图标从 Dock 拖到屏幕边或正中，想分屏或开窗口 | Dock 图标上按下，拖出 Dock，在远处松手 | 显示“移除”，松手后图标从 Dock 上拿掉；不分屏，也不开窗口 | 并排：🌐⌃← / 🌐⌃→。新窗口：⌘N。拿回图标：打开这个 App，Control 点它的 Dock 图标，选“选项 › 在程序坞中保留” | 图标从 Dock 移除了；并排按 🌐⌃← | 在屏幕左右 15% 以内或正中区域松手（离 Dock 200 点以上），松手 1 秒后 `com.apple.dock` 的 `persistent-apps` 里少了这个 bundle：说一次。这个判断对正在运行的 App 也成立，AX 列表不行。60 秒内他又从别处打开这个 App，补说拿回的办法 | [改变布局][ipad-layout] · [Dock][mac-dock] |
| 18 | 点屏幕顶边正中，让长页面回到顶部（WindowShade 造成的撞车） | 点在刘海上 | 打开刘海的主屏幕，页面不动 | ⌘↑ | 回到页面顶部按 ⌘↑ | 只在有硬件刘海的屏上。点之前前台是浏览器或阅读类 App，页面不在顶部（AX 滚动条的值大于 0.1）；主屏幕 1.5 秒内（扣掉双击等待时间）没点任何图标就关掉；关掉后 5 秒内他又往上大幅滚动（400 点以上），或按了 ⌘↑ / Home；出现两次 | [Safari][ipad-safari] · [Safari 快捷键][safari-keys] |
| 19 | 单指轻点触控板当点按 | 一根手指落下又抬起，不到 0.2 秒，后面没有 leftMouseDown | “轻点来点按”关着时什么也不发生 | 按下去点按；或在系统设置 › 触控板里打开“轻点来点按” | 轻点来点按要在触控板设置里打开 | 三个存储位置都关着才启用（本机开着，所以不会启用）。轻触时指针在可点的元素上、不在文本输入区，前后 1 秒没有按键；10 秒内对同一个元素轻触两次以上，随后 5 秒内在它上面真正按下点按了。等探针 6 | [iPad 触控板设置][ipad-tp-settings] · [Mac 触控板设置][mac-tp-settings] |
| 20 | 把指针推过右边缘，调出侧拉 | 指针在右边缘，仍有向右的位移 | 没有动作 | 侧拉：把标题栏拖到屏幕边正中停一下（1.0.16 发布后，还可以读侧拉快捷键的实际绑定） | 侧拉：把标题栏拖到屏幕边停一下 | 右边是硬边：右侧没有屏、Dock 不在右边、右侧两个角都没有触发角、右边没有收着的侧拉。两段分开的向右推（原始 deltaX 各 80 点以上），10 秒内两次。去掉拖窗口那一半。等探针 4 | [触控板手势][ipad-tp] · [125309][ipad-multitask] |
| 21 | 在桌面上两指右滑，看小组件（今天视图） | 两指横向 scrollWheel，指针下没有 App 窗口 | 桌面上没反应 | 小组件在通知中心：点日期和时间；刘海的主屏幕里往右滑就是今天视图 | 小组件在通知中心：点日期和时间 | 通知中心开着、或刚关不到 1 秒时不算；前 2 秒内有过“从右边缘往左划”也不算。其余同第 14 条，只是方向改成横向 | [触控板手势][ipad-tp] · [小组件][mac-widgets] |
| 22 | 按 🌐M 调出菜单栏（iPadOS 26 起） | 先看到键码 63，再看到键码 46 | 大概没反应（未上机核实） | 菜单栏一直在屏幕最上面；用键盘走到菜单栏按 ⌃F2 | 菜单栏一直在屏幕最上面 | 3 秒内没有菜单打开（看 layer 101 或 `AXMenuOpened`）：一次就说。如果文本框里多出一个 m，先说这一点。等探针 1 | [102393][ipad-kb] · [菜单栏 26][ipad-menubar-26] |
| 23 | 在 Exposé 里把 App 往上一甩来退出 | 调度中心开着时，从窗口缩略图往上拖进空间栏 | 窗口被送到另一张桌面，或和全屏 App 组成分屏；没有关掉 | 调度中心里按 ⌘W 关窗、⌘Q 退出它的 App；平时用 ⌘Q | 调度中心里按 ⌘W 关窗 | 从按下到松手不到 0.4 秒，速度超过甩一下的门槛（沿用 FlickClassifier），在空间栏上方或屏幕顶边外松手，松手前没在任何桌面缩略图上停过：说一次。等探针 5 | [退出 App][ipad-quit] · [空间][mac-spaces] |

编号从 1 到 23，其中第 9 条原本的“控制中心”规则已经删掉并入别处，实际要开口的是 22 条。

### 4. 看得到、但不该说的

下面这些是 Mac 上正当的用法，任何规则都不能因为它们开口。第 3 节里各条的条件就是为排除它们写的。

- **⌘H、⌥⌘H。** Mac 老用户藏一下 App、去别处做事，再回来。WindowShade 自己也会隐藏 App：DockClickHide 的“让开这个 App”，以及卷帘条转发的 ⌘H。另外 ⌃⌘H 是 WindowShade 的“全部收进刘海”，和 ⌘H 无关。
- **🌐H 瞄一眼桌面再收回；fn-↑ 在已经到顶的页面上连按；⇧⌘4 后改主意按 Esc。**
- **按住 ⌘ 犹豫、⌘ 点按、⌘ 拖动后台窗口。** 装了快捷键表类 App 的人，按住 ⌘ 本来就会弹出一张表。
- **打开表情与符号面板随便看看就关。** 只装了一个输入法时，单按 🌐 本来就不是想切换。
- **用三指或四指打开调度中心瞄一眼就关；在两张桌面之间来回看；打开“App”翻一翻就关。**
- **指针停在刘海上看一眼收着的窗口；点刘海打开主屏幕后没点图标就关。** 这是新方向下刘海最正常的用法。“顶边正中”那一半因此整个删掉了。
- **自动隐藏 Dock 时推到底边看一眼；触控板惯性让指针贴在边上；把指针停在右上角挪开。**
- **拖窗口到边上试一下平铺再拖回来（macOS 15 起）；看视频时进出全屏。**
- **两指从右边缘往左划打开通知中心，再两指往右划关掉。** 关的时候指针往往在桌面上。
- **收起窗口看一眼下面、再展开；往上甩收起再放回。** 这是卷帘本身的用法。
- **有意把不用的 App 从 Dock 拖走（在 Dock 附近松手）；在调度中心里把窗口慢慢拖到空间栏，送去别的桌面。**
- **打字时掌根擦到触控板；在文字里按住放光标；按住 Safari 后退按钮看历史；用力按查询。**
- **第 2 节所有“一样”的习惯。** 编辑用的 ⌘ 键、⌘Tab、⌘空格、⌘W、⌘M、⇧⌘3、⌃空格、🌐A/⇧A/C/N/Q/E/D、⌃🌐 加方向键、两指点按、滚动和缩放、拖窗口。其中 ⌃🌐 加方向键这类“在 Mac 上照样好用”的，适合在欢迎窗口里说一句。

### 5. 看不到的

**分不出来，也不打算判断：**

- **单指从底边往上滑回主屏幕，或调出 Dock。** 在触控板上和普通挪指针完全一样。
- **指针停在 App 名上看菜单栏（iPadOS 27）。** 悬停不算卡住，Mac 的菜单本来就在那里。
- **三指左右滑撤销重做、三指捏合拷贝粘贴。** 事件看得到，但和切 App、找切换器的手势是同一种形状，意图分不开，由第 3 条和第 15 条兜住。
- **双手拖放、拖着东西时用另一根手指叫 Dock。**

**现有代码看不到，要先探针的：**

1. **系统吃掉的组合键会不会先经过会话 tap。** 包括 fn-H、fn-M、fn-⌃F、⇧⌘4，以及截屏十字线出现后的 Esc。WindowSwitcher 能看到系统的 ⌘Tab，只能算旁证。同一个探针顺便确认苹果键盘上 fn+↑ 是否直接出键码 116。
2. **系统触控板手势走的是 Dock 手势（类型 30），不投递给 App，也不在 PinchEventTap 的 mask（1<<29）里。** 要试着把 1<<30 加进那个只听的 tap，看能不能拿到开始和结束；拿不到就只看结果（调度中心打开、空间切换、“App”打开）。
3. **系统接走手势以后，PinchEventTap 还收不收得到触摸流。** 它现在只在手指数变化时回调；要判断方向，得在监听线程上加位置跟踪。
4. **指针被屏幕边夹住以后，`mouseMoved` 的 delta 还给不给。**
5. **调度中心开着时，会话 tap 和全局监听还收不收得到拖动。**
6. **单指轻触会不会进类型 29。** 同时要实测三样东西在窗口表或 AX 里叫什么：表情与符号面板、通知中心、“App”。

**其他看不到的：**

- `NSEvent` 全局监听收不到发给 WindowShade 自己窗口的事件（刘海、主屏幕、侧拉把手），要用它们自己的本地监听。
- 调度中心开关没有通知，只能按需、有时限地轮询 ExposeShieldWindow，由三指以上接触、⌃↑ 或调度中心键触发。
- 公开接口拿不到空间 ID，“切回原桌面”只能用最前面的窗口去近似。
- 别的 App 里的用力按，现在只挂了本地 `.pressure` 监听。

**不能判断时的替代办法：在欢迎窗口选了 iPad 后，用一页“Mac 上不一样的地方”一次说完。** 这些不当作卡住提示：

- 通知中心和控制中心都在右上角，最右边的日期和时间是通知中心；
- 点红色按钮只关窗口，App 还开着，退出按 ⌘Q；
- ⇧⌘3 截的图存到桌面，不进“照片”；
- ⌃🌐 加方向键和 iPad 一样好用；
- 三指或四指的系统手势在这台 Mac 上分别是什么，按读到的设置来说。

### 6. 被否掉的

**整条不开口：**

- **点右上角图标找控制中心**：点 Wi-Fi 或电池打开的菜单本来就有他要的开关，结果不坏；指针停在右上角又是常见的停放位置。改在欢迎窗口里说。
- **三指编辑手势（撤销、重做、拷贝、粘贴）**：意图分不出来，由第 3、15 条兜住。
- **和 iPad 一样的按键、和 iPad 一样的指针动作**：开口就是误报。
- **甩一下贴半屏**：WindowShade 默认已经补上，旧习惯直接好用。
- **单指底边上滑、悬停 App 名、红色按钮、⌘⌥D、台前调度、画中画手势、双手拖放、妙控鼠标单指滑动**：不算卡住，或看不出来。
- **🌐← / 🌐→、三指轻点、三指或四指捏合回主屏幕、把 Caps Lock 当 Esc**：没有 Apple 现行官方来源。

**规则保留，但删掉其中一半：**

- **通知规则的“顶边正中 / 刘海”那一半**：这正是刘海的设计入口，一定误报；iPad 上通知也是从左上角拉下来的。
- **侧拉规则的“拖窗口过边”那一半**：Mac 用户试平铺也是这个形状。
- **三指横滑规则的“切过去又切回”那一半**：用多个桌面的人每天都这样。
- **按住看快捷键规则的 🌐 那一半**：会和“按下 🌐 键时”的动作重叠，没法判断是不是没反应。
- **指针往下推规则的“点底部横条”那一半**：点到的是 Dock 图标，意图分不出来。
- **全屏规则的 🌐F 那一半和“滑回原桌面”那一半**：🌐F 在 Mac 上可能本来就是切全屏；在桌面间滑动是正常导航。
- **⇧⌘4 规则的“看截图目录”**：浮动缩略图要消失后才写入文件，存储位置也可以改成剪贴板等。
- **Dock 拖出规则的“看 AX 列表少了一项”**：正在运行的 App 被拖出后，图标要等它退出才消失。

## 已定（Aaron，2026-09-29）

1. **WindowShade 自己和 iPad 相反的三个动作**（双击标题栏、往上甩标题栏、点顶边正中）：保留我们的，他卡住时刘海教（iPad 第 7、11、18 条）。
2. **⌥Tab 按窗口切换**：保留，他卡住时顺带教 Mac 自己的 ⌘Tab、⌘`。
3. **点一下提示**：替他做成提示里那一下（比如回到主屏幕），记成已学会；关掉另给一个小叉。
4. **没答来处的人**：只开不会误报的几条（⌃C、⌃X、⌃S、访达里 Delete、强制退出、Alt+F4）；从习惯猜到来处时，刘海问一句要不要按那边的习惯提示，他点了才开。
5. **用词**（按惯例定，Aaron 可改）：说到某个菜单命令时，直接用前台 App 菜单里那一项的标题；读不到时用系统菜单的叫法（拷贝、粘贴、剪切）；键名照键帽写（return、delete、esc）。
6. **第一批范围**（按惯例定，Aaron 可改）：Windows 第一批 13 条；iPad 先上信号已经确认拿得到的 6 条（⌘H、🌐M、从 Dock 拖出图标、双击标题栏、往上甩、桌面两指下滑），其余等探针。

## 实现时补的几条（2026-09-29，第一批落地后）

- **访达里的 Delete 只在访达在前台时听。** 单按 ⌫ / ⌦ 只在访达是前台 App 时进按键表；在别的 App 里按删除键直接放过，不读辅助功能、不记日志。
  访达里也要焦点是文件列表、有选中项、没在输入、前 1 秒没按字母才看下去。
- **Alt+F4 的提示只找 ⌘W。** App 的菜单里没有 ⌘W 那一项时，提示说系统的叫法“关闭窗口按 ⌘W”，点提示是替他按 ⌘W，绝不去点“退出”。
- **点提示替他做时不会做两次。** 菜单项按下去超时的，按“可能已经做了”算，不再补发按键。
- **键帽照实物写两行**：⌃ 下面一行小字 control（⌘ 下面 command……）；读屏把符号读成 Control、Command。副句“常用快捷键把 ⌃ 换成 ⌘”不改。
- **桌面上两指下滑找搜索**（iPad 第一批里的一条）从第一次生效起 14 天后自己停：之后他早该用上 ⌘空格了。
- **双击收起后看他是不是想铺满**的那十几秒里，把收起后的 `.shade` / `.shake` 普通提示压住，最多压约 14 秒，到点自己放开。

[ipad-kb]: https://support.apple.com/en-us/102393
[ipad-kb-2024]: https://web.archive.org/web/20250903162827/https://support.apple.com/en-us/102393
[ipad-multitask]: https://support.apple.com/en-us/125309
[ipad-tp]: https://support.apple.com/guide/ipad/trackpad-gestures-ipad66ce6358/27/ipados/27
[ipad-mouse]: https://support.apple.com/guide/ipad/mouse-actions-and-gestures-ipada39e5184/27/ipados/27
[ipad-nav]: https://support.apple.com/guide/ipad/learn-gestures-to-navigate-ipad-ipadab6772b8/27/ipados/27
[ipad-windows]: https://support.apple.com/guide/ipad/work-with-multiple-windows-at-the-same-time-ipad08c9970c/27/ipados/27
[ipad-layout]: https://support.apple.com/guide/ipad/change-the-layout-of-windows-ipadfe7c65e9/27/ipados/27
[ipad-stage]: https://support.apple.com/guide/ipad/organize-windows-with-stage-manager-ipad1240f36f/27/ipados/27
[ipad-menubar-26]: https://support.apple.com/guide/ipad/use-the-menu-bar-ipadb4ede9db/26/ipados/26
[ipad-menubar-27]: https://support.apple.com/guide/ipad/use-the-menu-bar-ipadb4ede9db/27/ipados/27
[ipad-notif-26]: https://support.apple.com/guide/ipad/view-and-respond-to-notifications-ipad66f11759/26/ipados/26
[ipad-notif-27]: https://support.apple.com/guide/ipad/view-and-respond-to-notifications-ipad66f11759/27/ipados/27
[ipad-shortcuts]: https://support.apple.com/guide/ipad/use-shortcuts-ipaddf61a0c2/26/ipados/26
[ipad-switch-kb]: https://support.apple.com/guide/ipad/switch-between-keyboards-ipaddd28d7ed/26/ipados/26
[ipad-fkc]: https://support.apple.com/guide/ipad/control-ipad-with-an-external-keyboard-ipad5f765d6f/26/ipados/26
[ipad-quick]: https://support.apple.com/guide/ipad/perform-quick-actions-ipad701fcbdc/27/ipados/27
[ipad-quit]: https://support.apple.com/guide/ipad/quit-and-reopen-an-app-ipad79518d15/27/ipados/27
[ipad-safari]: https://support.apple.com/guide/ipad/browse-the-web-ipad957f972d/27/ipados/27
[ipad-text]: https://support.apple.com/guide/ipad/select-edit-and-move-text-ipadac2fea3c/27/ipados/27
[ipad-tp-settings]: https://support.apple.com/guide/ipad/change-trackpad-settings-ipada16646f4/27/ipados/27
[newsroom-26]: https://www.apple.com/newsroom/2025/06/ipados-26-introduces-powerful-new-features-that-push-ipad-even-further/
[newsroom-27]: https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/
[mac-kb]: https://support.apple.com/en-us/102650
[mac-tp]: https://support.apple.com/en-us/102482
[mac-3fdrag]: https://support.apple.com/en-us/102341
[mac-shot]: https://support.apple.com/en-us/102646
[mac-mc]: https://support.apple.com/guide/mac-help/view-open-windows-spaces-mission-control-mh35798/27/mac/27
[mac-spaces]: https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/27/mac/27
[mac-apps]: https://support.apple.com/guide/mac-help/open-apps-in-spotlight-mh35840/27/mac/27
[mac-fullscreen]: https://support.apple.com/guide/mac-help/use-apps-in-full-screen-mchl9c21d2be/mac
[mac-tile]: https://support.apple.com/guide/mac-help/tile-app-windows-mchlef287e5d/mac
[mac-tile-keys]: https://support.apple.com/guide/mac-help/mchl9674d0b0/27/mac/27
[mac-windows]: https://support.apple.com/guide/mac-help/work-with-app-windows-mchlp2469/mac
[mac-dock-settings]: https://support.apple.com/guide/mac-help/change-desktop-dock-settings-mchlp1119/27/mac/27
[mac-dock]: https://support.apple.com/guide/mac-help/open-apps-from-the-dock-mh35859/27/mac/27
[mac-menubar]: https://support.apple.com/guide/mac-help/mchlp1446/mac
[mac-notif]: https://support.apple.com/guide/mac-help/get-notifications-mchl2fb1258f/27/mac/27
[mac-cc]: https://support.apple.com/guide/mac-help/quickly-change-settings-with-control-center-mchlc9d0e1f2/mac
[mac-corners]: https://support.apple.com/guide/mac-help/perform-quick-actions-with-hot-corners-mchlp3000/mac
[mac-widgets]: https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac
[mac-spotlight]: https://support.apple.com/guide/mac-help/find-what-you-need-with-spotlight-mchlp1008/mac
[mac-kbd-settings]: https://support.apple.com/guide/mac-help/change-keyboard-settings-kbdm162/mac
[mac-input]: https://support.apple.com/guide/mac-help/change-input-sources-settings-mchl84525d76/mac
[mac-rightclick]: https://support.apple.com/guide/mac-help/right-click-mh35853/27/mac/27
[mac-tp-settings]: https://support.apple.com/guide/mac-help/change-trackpad-settings-mchlp1226/27/mac/27
[mac-new27]: https://support.apple.com/guide/mac-help/whats-new-in-macos-27-apd07d671600/mac
[safari-keys]: https://support.apple.com/guide/safari/keyboard-shortcuts-and-gestures-cpsh003/mac
