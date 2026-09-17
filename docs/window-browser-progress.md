# WindowShade 窗口浏览功能进度

任务书：《WindowShade 独立开发任务书》（2026-09-17），要求按阶段 0–7 实现
Dock 悬停窗口面板与独立快捷键窗口选择面板。

## 基线

- 仓库 `surfine/WindowShade`，实际工作区 `/Users/aaron/Documents/WindowShade`。
- 设计核对基线 `2e107cf841f153c9f07de02d0ec554f5da36aa8e`；本工作区 HEAD
  `2abd49b`（`main`，比 origin/main 落后 1 个站点提交）。`prototype/`、`tests/`、
  `docs/` 与该基线一致，未回退。
- 开始前工作区干净，没有其他会话的未提交修改。
- 任务相关既有入口已确认：`App/HoverPreview.swift` 的只读预览与
  `presentPreview`/`hidePreview` 单槽不变量；`App/FoldExit.swift` 的
  `unshadeReturningElement(_:playSound:pinAfterRestore:onVerified:)` 恢复与验证
  回调；`App/FoldTransaction.swift` 的 `verifyRestoredWindow`、
  `pinRestoredWindow`、`stopPreviewBeforeFoldCapture` 调用点；`PinnedPreview.swift`
  的 `startPreview(for:id:)`（私有，按焦点解析）与单槽 `mirrorLayer`；
  `Capture/WindowSnapshotCache.swift` 折叠路径专用短 TTL 缓存；
  `Window/WindowRegistry.swift` 只是 PID→应用元数据缓存，不是窗口目录。
- 构建方式：`prototype/build.sh --check` 做 swiftc 类型检查，不签名、不改
  bundle；默认构建会停止正在运行的 WindowShade，本任务不运行。

## 阶段

- 阶段 0：完成入口与基线核对，开始建立进度记录（本文件）。
- 阶段 1：身份模型、值类型快照、已管理窗口目录合并与 fake 测试。
- 阶段 2：明确目标动作适配器、按目标置顶入口、恢复真实终态回传与防重入。
- 阶段 3：独立可交互面板、卡片/列表、布局、临时预览仲裁、fixture。
- 阶段 4：Dock 悬停目标检测、通知失效处理、鼠标过渡区域与开关。
- 阶段 5：普通窗口发现、受控缩略图、按应用排除、关闭/最小化能力。
- 阶段 6：搜索、键盘面板、独立快捷键与可访问性。
- 阶段 7：置顶镜像 owner 租约、默认关闭的普通窗口实时预览、回归。

## 真实修改与验证记录

（每阶段完成后在这里追加：真实修改、实际运行的命令、测试结果、未验证项、
下一步具体文件或符号。）

### 阶段 0

- 修改：仅新增本文件。
- 运行：`git status --short --branch`、`git log --oneline -5`、
  `git diff --stat 2e107cf HEAD -- prototype tests docs`（输出为空，确认基线
  内容一致）、阅读 `DEVELOPMENT.md` 与 `prototype/build.sh`。
- 结果：工作区干净，无需保留的未提交修改；未回退工作区。
- 未验证项：尚无。
- 下一步：`prototype/WindowBrowser/WindowBrowserModels.swift` 与
  `WindowBrowserGeometry.swift` 的纯逻辑及 `tests/run-window-browser-tests.sh`
  阶段 1 测试。

### 阶段 1：身份与目录

- 新增 `WindowBrowser/WindowBrowserModels.swift`：`ApplicationInstanceKey`、
  `WindowKey`（应用实例 + 原窗口 ID + 会话窗口代数）、请求/目标令牌、值类型
  `WindowRecord`、`WindowIdentityAllocator`、稳定列表与选择 `WindowBrowserListState`、
  搜索规范化。
- 新增 `WindowBrowser/WindowCatalog.swift`：合并折叠/置顶只读快照与普通发现结果；
  已管理状态优先；成功空结果只清普通发现记录；失败/超时保留旧记录并标注待刷新；
  只有确证销毁或应用终止才移除。`WindowBrowser/WindowBrowserDiscoveryFilter.swift`
  集中过滤自身进程、代理条/效果窗、非 layer-0、桌面组件、排除清单与桌面小组件。
- 新增 `WindowBrowser/WindowBrowserGeometry.swift`：左/右/底部 Dock 的面板矩形、
  有限梯形过渡区域、列数与列表切换；全部使用 Cocoa 全局 point 坐标。
- 测试：`tests/run-window-browser-tests.sh` → `PASS: 104 window-browser pure-logic checks`
  （含同窗口去重、同标题独立身份、多 PID 不合并、PID/窗口 ID 复用代数、折叠离屏
  保留、超时/空/失败分支、A→B→A 令牌、稳定顺序与按身份选择、搜索折叠、三种 Dock
  方向、负坐标屏幕、过渡区域不放大会导致常驻、代理条与非窗口角色过滤；另有
  缺 bundle ID 时不重复分配应用实例、按钮点击不冒泡成主体激活、`canBecomeKey`
  模式语义与镜像 owner 租约）。

### 阶段 2：明确目标动作与恢复终态

- 新增 `WindowBrowser/WindowBrowserActions.swift`：`WindowBrowserActionCoordinator`
  统一动作入口，按 PID 串行、同义请求合并、异义请求回 `busy`、超时回 `uncertain`
  但继续占额度直到真实的同步调用返回；`WindowBrowserActionPolicy` 做能力/权限预检。
- `WindowBrowser/WindowBrowserAppDelegate.swift`：`windowBrowserManagedSnapshots()`
  只读快照；`windowBrowserBeginFold(key:element:completion:)` 进入原有 `shade`
  事务；`windowBrowserResolveElement(key:)` 按 PID + 原窗口 ID 重新核对；
  `register/settleWindowBrowserFoldWaiter` 回传折叠真实终态。
- 原有折叠路径接入：`App/ShadeController.swift` 的中止/回滚与
  `App/FoldTransaction.swift` 的 `revealOverlayAfterVerification` /
  `rollbackFoldTransaction` 在真实终态结算等待者；没有改隐藏策略、恢复日志或动画。
- `PinnedPreview.swift` 增加明确目标 `startPreview(targetWindowID:pid:axWindow:completion:)`
  与 `startingPreviewIDs` 防重入；启动成功的判定以对应捕获启动完成为准，启动中
  目标变化会停掉刚起来的流；新增 `WindowMirrorSlot` owner 租约，旧 owner 释放
  不会摘掉新 owner 的镜像。
- 测试：动作协调器覆盖同义合并、异义 busy、不可验证拒绝、权限缺失、超时后仍占
  额度且不启动相反动作、迟到完成记账、恢复验证失败不继续置顶；镜像 owner 测试
  覆盖旧 owner 释放不影响新 owner。

### 阶段 3–4：面板、Dock 与静态预览

- 新增 `WindowBrowser/WindowBrowserViews.swift`、`WindowBrowserPanel.swift`：
  卡片/紧凑列表、状态与按钮、搜索框、方向键/Return/Escape、输入法 marked text
  优先、可访问性标签；Dock 模式 `canBecomeKey == false` 且不抢焦点，键盘模式可
  成为 key window；两种模式共用同一套视图与动作。
- 新增 `WindowBrowser/WindowBrowserController.swift` 与
  `WindowBrowser/WindowBrowserAppDelegate.swift`：请求代数校验、元数据每 PID 单飞、
  合并刷新、面板显示/离开延迟、外部点击关闭、菜单优先于 Dock、键盘面板优先于
  Dock 面板；打开新面板时清掉原有只读临时预览。
- 新增 `WindowBrowser/DockHoverObserver.swift`：有界只读遍历 Dock AX 树、订阅
  选中子项变化与对象销毁、Dock 重启/实例变化失效重建、鼠标回退检测（≥100ms
  节流 + 命中测试，只在 Dock 条带或屏幕边缘候选区域执行）。通知与回退命中都会
  经过“鼠标必须在当前图标有效区域内”的校验；观察器不在中间过渡区域清除目标，
  面板是否隐藏由控制器结合面板矩形判断。不写 Dock 设置、不模拟点击、不启动
  未运行应用。
- 接线：`App/MenuBarController.swift` 菜单新增“选择窗口…”；`App/EventTap.swift`
  注册可选独立快捷键（默认不注册、失败保留旧组合）；设置新增“窗口浏览”页
  （Dock 开关、面板开关、实时预览开关、快捷键录制、按应用排除清单、权限入口），
  见 `App/Preferences.swift` 与 `Effects/DuoSettingsWindow.swift`。
- 缩略图：`WindowBrowser/WindowThumbnailService.swift` 有界缓存 24 MiB、同 key
  共享在途任务、订阅取消、最多两路真实截图、取消但未返回仍占额度、失败/排除/
  关闭后不投递；`WindowBrowserThumbnailBackend` 只调用 `captureWindow`（单窗
  过滤器），没有整屏截图回退。

### 阶段 5–7：普通窗口、实时预览与回归

- 普通窗口发现抽到 `WindowBrowser/WindowBrowserDiscovery.swift`，控制器与探针
  共用同一实现；AXWindows 读取失败与成功空结果分开返回，多应用失败互相隔离。
- 实时预览：普通窗口默认关闭，选中稳定约 0.4 秒后最多建立一路 8fps/≤640×400
  的 `WindowStreamCapture(preview: true)`；目标已置顶时改用 `WindowMirrorSlot`
  挂接既有流的镜像；启动成功后再次核对代数与面板会话，离开时停止自有流。
- fixture：`window-browser-fixture` 支持 mixed / many / empty / long 场景与
  自动退出环境变量，按钮只改 fake 状态；正常启动不会出现。

## 实际运行的命令与结果

- `bash tests/run-window-browser-tests.sh` → `PASS: 104 window-browser pure-logic checks`。
- `bash prototype/build.sh --check` → 65 个 Swift 文件类型检查通过（唯一输出是
  `ScreenCaptureBridge.swift:112` 既有的 `stopCapture` 异步 API 建议警告）。
- `bash tests/run-paper-tests.sh` → 通过（纸面组件范围/显示/点击穿透/缩放）。
- `bash tests/run-duo-tests.sh` → 4 组通过，含恢复意图先于隐藏、动画后验证、
  同步恢复契约与会话/捕获排除接线。
- `git diff --check` → 通过（无空白错误）。
- 隔离构建（未替换正在运行的应用）：
  `WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: …(G3TN2MBQ2Q)" bash prototype/build.sh --stage`
  → `.build/duo-validation/WindowShade.app` 签名验证通过；运行中的 WindowShade
  进程保持运行。
- 真实只读 Dock 探针
  `.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade --window-browser-dock-probe`
  → 本机 Dock AX 树为 `AXApplication → AXList（31 子项，25 个可解析应用项）→ AXDockItem`，
  `AXSelectedChildrenChanged` 注册 `result=0`，观察器创建/拆除配对；没有鼠标移动时
  2 秒内 0 条通知。
- 真实只读窗口发现探针 `--window-browser-catalog-probe` → 8 个 regular 应用、
  6 个窗口、0 失败；样本包含 Safari 2 窗口（1 最小化、1 屏外）、Finder、Codex、
  Telegram、QQ，证明非在屏/最小化窗口不会被误删。
- fixture 启动（`--window-browser-fixture`，自动退出）→ mixed 9 条、many 20 条
  （自动切列表）、empty 0 条；面板 720×560、键盘模式 `canBecomeKey=true`、
  搜索框可见。上述 stage 构建与 fixture 在最后一轮改动后重新执行过一次，
  结果一致；运行中的 WindowShade（检查时 pid 3342）全程保持运行，
  `prototype/WindowShade.app` 的 Mach-O 未被替换。

## 未验证项（需要真人或 macOS 实机继续确认）

- Dock 选中子项通知是否跟随真实鼠标悬停变化：本机只在无鼠标移动的 2 秒窗口内
  观察到 0 条通知，未移动用户指针做悬停验证。回退路径（节流命中测试）已实现但
  同样未在真实悬停中验证。
- 从真实菜单/快捷键打开面板、在面板中点击折叠/展开/置顶/关闭的端到端流程：
  类型检查、纯逻辑测试与隔离 fixture 通过；没有在正常启动的 AppDelegate 中做
  这一步，以避免停止或干扰正在运行的 WindowShade。
- 多显示器不同缩放、Space 切换、全屏、Mission Control、Dock 自动隐藏/放大、
  Dock 重启、睡眠唤醒、锁屏、权限撤销与重新授权、连续 100 次打开关闭的资源计数
  与性能对照：未运行。
- 普通窗口实时预览的真实帧率/资源占用、镜像在第 15 帧后的稳定性：未运行。
- Dock 位于左/右/底部时的真实面板位置：仅在纯几何测试与底部 Dock 探针中核对。

## 下一步的具体文件或符号

### 开发/验收探针命令（都用隔离 stage 构建运行，不会替换正在使用的应用）

```sh
cd prototype && WINDOWSHADE_CODESIGN_IDENTITY="<你的 Apple Development 身份>" bash build.sh --stage
APP=../.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade
$APP --window-browser-dock-probe        # Dock AX 树 + 选中属性 + 通知注册/拆除
$APP --window-browser-hover-probe       # 回退命中：命中图标产出目标 / 非图标清除目标
$APP --window-browser-catalog-probe     # 普通窗口发现与逐应用 AX 耗时
$APP --window-browser-capture-probe     # 只捕获自己窗口：像素上限/长宽比/内容/延迟
$APP --window-browser-thumbnail-probe   # 生产缩略图服务 + 真实截图：共享/缓存/失效
$APP --window-browser-stream-probe      # 8fps 预览流：首帧/镜像帧/停止确认
$APP --window-browser-panel-probe       # Dock 面板不激活、不抢 key；键盘面板可编辑
$APP --window-browser-fixture           # fixture 面板（mixed/many/empty/long/small）
```

`WINDOWSHADE_BROWSER_FIXTURE` 选择场景，`WINDOWSHADE_BROWSER_FIXTURE_AUTOEXIT=<秒>`
自动退出，`WINDOWSHADE_BROWSER_FIXTURE_SIZE=small` 用小屏尺寸。

1. 真人验证并修正 `DockHoverObserver.refreshFromSelection` 的悬停通知路径；
   若通知不跟随，确认 `mouseMoved()` 回退在真实 Dock 上的命中。
2. 从正常启动的应用菜单执行一次折叠/展开/置顶/关闭，核对
   `WindowBrowserController.performFold/performUnfold/performPinPreview/performClose`
   的终态与 `windowBrowser-progress` 记录。
3. 在多显示器/Space 环境复测 `WindowBrowserGeometry.panelGeometry` 与
   `WindowBrowserController.screensDidChange/spaceDidChange`。
4. 若要开启普通窗口实时预览，先在设置中打开并记录
   `WindowBrowserController.updateLivePreview` 的流数量与 CPU。

## 补充轮次：折叠前停流、缓存优先、列表预览与生命周期

以下改动在上一轮之后追加，均已重新通过类型检查与纯逻辑测试。

### 真实修改

- `ScreenCaptureBridge.swift` 新增 `stop(completion:)`：停止系统捕获并在真实返回后
  回调一次，供折叠前等待自有流停妥。
- `WindowBrowserController.prepareForFold(target:completion:)`：折叠前先取消展示
  任务、释放借用镜像、停止自有流；1.5 秒内无法确认停妥就拒绝本次折叠并保留真实
  窗口，不进入 `shade`。
- 新增 `WindowBrowserThumbnailPolicy.swift`：把缩略图读取顺序做成纯决策
  （排除/权限 → 已保存折叠快照 → 运行中的置顶镜像 → 单窗截图 → 图标与说明）。
  控制器据此对折叠窗口直接复用 `ShadeState.previewImage`（不新截图、不展开），
  对最小化/暂停置顶会话显示图标和原因。
- `WindowBrowserViews.swift`：列表风格新增右侧选中项预览栏（较大静态图或唯一一路
  实时画面），修复了“列表风格下实时预览视图无处挂载”的真实缺口；状态文字带符号
  （◫/📌/⏸ 等），不只依赖颜色；键盘面板重新计算 key view loop 支持 Tab。
- `WindowBrowserPanel.performClose(_:)` 回到控制器，避免 ⌘W 关闭面板后控制器仍
  以为面板可见。
- `WindowBrowserController` 接入与项目一致的会话/睡眠/锁屏通知：进入不可交互阶段
  关闭临时面板、清图像缓存、停自有流、停用 Dock 入口；唤醒/解锁后按设置重建。
- Quick Look：`performUnfold` 遇到 `hide == .quickLookClosed` 时按“重新打开”处理，
  旧 `WindowKey` 立即失效并提示用户重新选择；`performPinPreview`/`performMinimize`
  对这种窗口返回 `unsupported`，不自动接到新窗口。
- `WindowBrowserSettings.keyName` 改用当前输入源键盘布局（`UCKeyTranslate`）翻译
  键码，取不到布局时才回退内置 US 表；`MenuBarController` 的“选择窗口…”入口在
  设置关闭时置灰。
- fixture 支持 `WINDOWSHADE_BROWSER_FIXTURE_SIZE=small` 小屏场景。

### 新增真实运行证据

- `bash tests/run-window-browser-tests.sh` → `PASS: 114 window-browser pure-logic checks`
  （新增缩略图读取顺序的 8 条断言）。
- `bash prototype/build.sh --check` → 67 个 Swift 文件类型检查通过。
- Dock 只读探针（不移动指针）：
  `AXList children=31 appItems=25 selectedAttrReadable=true frame=(40,1027 1630x70)`；
  对第一个图标矩形内坐标 (74,1067) 的系统命中测试
  `synthetic-hit=appItem bundle=com.apple.finder depth=0`；
  `AXSelectedChildrenChanged` 注册 `result=0`，观察器创建/拆除配对完成。
  这证明鼠标回退路径在本机 Dock 上能直接解析出应用项，即使悬停通知不触发也
  可用。
- 窗口发现探针（真实 8 个 regular 应用）：`windows=5 empty=4 failed=0
  total=458ms slowestApp=173ms`，逐应用耗时
  Safari 147–173ms、Finder 35ms、Codex 82ms、Telegram 35ms、空结果 28–59ms。
  这是新增 AX 查询的实测基线，可作为后续性能对照的参照。
- fixture：`small 460x341`、`mixed 720x561` 均正常构建，列表风格含选中项预览栏。

### 仍未验证

- Dock 悬停通知是否随真实鼠标移动触发（需要移动用户指针，未做）；回退命中路径
  已在真实 Dock 上验证。
- 从正常启动的菜单/快捷键打开面板并执行折叠/展开/置顶/关闭的真实端到端流程。
- 列表选中项预览栏与一路实时流的真实画面、性能与资源占用。
- 多显示器缩放、Space、全屏、Mission Control、睡眠/锁屏/唤醒、权限撤销重授权、
  连续 100 次开关的资源计数。

## 补充轮次 2：交互细节与完成门

### 真实修改

- Dock 面板已经可见时切换到另一个图标：`presentDockPanelIfNeeded` 立即更新几何与
  内容，不再重新走 250ms 显示延迟；旧目标的图像按 `WindowKey` 隔离，不会冒充新
  应用。
- Dock 观察器无法建立/恢复时只停用 Dock 入口：`DockHoverObserver.onUnavailable`
  → `WindowBrowserController.handleDockObserverUnavailable` 提示一次；菜单与快捷键
  入口继续可用，收到新目标后自动清除不可用标记。
- 卡片与列表行提供可访问性动作（激活/展开、折叠、置顶、关闭窗口）；
  `content.onClose` 走同一个 `submit(.close:)` 动作入口。
- 快捷键保留组合策略纳入测试：⌘Q、无修饰单字母、仅 Shift 被拒绝，⌘⌥/⌃ 组合被
  接受，显示名包含修饰符与当前布局的键名。
- `WindowBrowserSingleShotCompletion` 单次完成门：`RestoreVerifier` 在 token 失效时
  会静默结束，浏览器适配层现在保证展开、展开后置顶、展开后最小化的桥接
  completion 恰好生效一次。
- 自有实时流的停止失败处理：`WindowStreamCapture.stop(completion:)` 回报真实错误；
  折叠前停止失败或 1.5 秒未确认 → 拒绝折叠并保留窗口；普通停止失败 → 5 秒内不再
  新建自有流。
- `WindowBrowserLivePreviewPolicy`：视频流在面板关闭/租约释放/目标消失之后才启动
  成功时，保留判断为假，调用方立即停掉刚建立的流（测试直接覆盖四种组合）。
- 修正动作协调器的真实缺陷：原实现下“同一 PID 的不同窗口”会被直接判 busy，
  `queueByPID` 实际不可达。现在按任务书语义改为：同窗口同义动作合并、同窗口
  相反动作直接 busy、同一 PID 的其他窗口进入最多 2 条的串行队列、队列满才 busy；
  面板关闭只取消排队请求（回 uncertain），已经开始的同步事务继续到真实终态。
- 新增 `WindowBrowserTargetIdentity`：目标身份只由“元素 PID + 原窗口 ID”决定，
  函数不读取当前焦点；`windowBrowserResolveElement` 与
  `PinnedPreviewController.startPreview(targetWindowID:pid:axWindow:)` 共用它。

### 新增真实运行证据

- `bash tests/run-window-browser-tests.sh` → `PASS: 138 window-browser pure-logic checks`
  （新增完成门、快捷键策略、可访问性动作、迟到流保留判断、面板关闭时“已开始事务
  不被取消/排队请求被取消”、PID+窗口 ID 身份判定等断言）。
- `bash prototype/build.sh --check` → 67 个 Swift 文件类型检查通过。
- 在最终修订上重新 stage 构建（未替换正在运行的应用）并重跑：Dock 探针
  `selectedAttrReadable=true`、`synthetic-hit=appItem bundle=com.apple.finder
  depth=0`、`AXSelectedChildrenChanged result=0`、观察器拆除完成；窗口发现探针
  `apps=9 windows=4 empty=7 failed=0 total=210ms slowestApp=38ms`；fixture
  `mixed 720x561` 与 `small 460x340` 均正常构建。

### 仍未验证

- 与上一轮相同的人类交互项：真实悬停通知、菜单/快捷键端到端动作、列表预览栏与
  实时画面、多显示器/Space/睡眠锁屏、性能与资源计数。

## 补充轮次 3：权限态按钮、动作预检与真实单窗截图

### 真实修改

- `WindowBrowserViews` 的卡片/列表行接收 `screenRecordingAvailable`：缺少屏幕录制
  时“创建置顶预览”按钮禁用并带原因提示；取消置顶属于本地清理，权限撤销后仍可用。
  控制器在每次渲染时传入真实的 `hasScreenRecordingPermission()`。
- 动作能力/权限预检纳入直接测试：折叠/展开/关闭/激活/置顶/取消置顶/最小化在
  能力缺失、权限缺失、已折叠、已展开、已最小化、恢复中、置顶暂停等情况下的结果。
- 新增只捕获 WindowShade 自己窗口的 `--window-browser-capture-probe`：走与
  `WindowBrowserThumbnailBackend` 相同的 `SCContentFilter(desktopIndependentWindow:)`
  + `SCScreenshotManager.captureImage` 路径，测量像素上限、长宽比与内容，并读取
  中心像素确认捕获的是目标窗口而不是整屏裁切。

### 新增真实运行证据

- `bash tests/run-window-browser-tests.sh` → `PASS: 153 window-browser pure-logic checks`。
- stage 构建后运行截图探针（只捕获本应用自己的探针窗口，不碰用户窗口）：
  - `profile=card pixels=461x320 source=840x584 took=131ms bytesPerRow=1920 center=(27,148,254)`
  - `profile=selectedLarge pixels=840x584 source=840x584 took=25ms bytesPerRow=3456 center=(27,148,254)`
  - 461/320 与 840/584 比例一致（长宽比保持）；中心像素是探针窗口的 systemBlue，
    说明单窗过滤器命中的就是目标窗口；首次捕获 131ms、热态 25ms 是本机实测基线。
- 运行中的 WindowShade 全程保持运行，`prototype/WindowShade.app` 未被替换。

### 仍未验证

- 真实用户窗口的截图延迟（探针只测了自己的窗口，避免读取用户内容）。
- 其余人类交互项与多显示器/Space/睡眠锁屏/资源计数同上一轮。

## 补充轮次 4：Dock 回退路径真实验证与残留目标修复

### 真实修改

- `DockHoverObserver` 增加 `simulatePointer(at:)` 测试/探针接缝（生产路径仍传
  `NSEvent.mouseLocation`），把指针位置改为显式参数贯穿候选区域判断、命中检测与
  图标区域校验，使回退路径可以在不移动系统指针的情况下被真实验证。
- 修复探针暴露的真实缺陷：指针停在 Dock 的非图标区域（例如分隔符）后不再移动时，
  旧目标会一直残留，因为清除只在“下一次指针移动”时判定。现在：
  超过 0.4 秒宽限期立即清除；否则按最后一次指针位置安排一次延迟复检；目标产生或
  清除时取消待执行的复检，观察器停止时一并取消。

### 新增真实运行证据

- 新增 `--window-browser-hover-probe`：使用生产 `DockHoverObserver`，以真实 Dock
  图标/分隔符坐标驱动回退命中路径（不移动用户指针）：
  - `hover-probe: icon-hit pid=3157 bundle=com.apple.finder expected=com.apple.finder match=true`
    —— 命中图标坐标后产出正确的应用实例目标。
  - `hover-probe: non-icon dock point (1193,39) target=cleared`
    —— 指针停在 Dock 上但不在任何图标（8pt 容差外）时，旧目标被清除。
  - `hover-probe: observer stopped` —— 观察器创建/停止配对完成。
- `bash prototype/build.sh --check` 通过；stage 构建后重跑上述探针与之前三项探针
  均正常；运行中的 WindowShade 未被停止或替换。

### 仍未验证

- 真实鼠标悬停时 AX 通知是否触发（回退路径已真实验证；通知路径仍无真机证据）。
- 其余人类交互项、多显示器/Space/睡眠锁屏与资源计数同前几轮。

## 补充轮次 5：缩略图服务真实端到端与 100 轮基线

### 真实修改

- 新增 `--window-browser-thumbnail-probe`：把生产 `WindowThumbnailService` 接上真实
  单窗截图后端（只捕获本应用自己的探针窗口），验证并发共享、缓存命中、失效重截与
  资源归零。
- 测试清单第 37 项落为直接测试：`hundredCyclesReturnToBaseline` 连续 100 轮
  缩略图请求/取消/失效，以及 100 轮动作提交，断言在途截图、缓存字节、活动/排队
  动作全部回到零。

### 新增真实运行证据

- 缩略图端到端探针输出：
  - `first delivered 461x320 captures=1 cachedBytes=675840`
  - `second delivered 461x320 captures=1 cachedBytes=675840`
  - `cached delivered 461x320 captures=1 cachedBytes=675840`
  - `after-invalidate delivered 461x320 captures=2 cachedBytes=675840`
  - `deliveries=4 captures=2 running=0 cachedBytes=675840`
  说明：两次并发只进行一次真实截图；缓存命中不新增截图；`invalidateAll` 后旧结果
  不复用、重新截图；结束无在途截图。`675840 = 1920 bytesPerRow × 320 × 1.1`，
  与生产成本模型一致。
- `bash tests/run-window-browser-tests.sh` → `PASS: 156 window-browser pure-logic checks`。

### 仍未验证

- 与上轮相同：真实悬停通知、菜单/快捷键端到端动作、列表预览栏与实时画面、
  多显示器/Space/睡眠锁屏，以及除上述探针以外的资源计数与性能对照。

## 补充轮次 6：实时预览真实流与布局选择修正

### 真实修改

- 修正布局选择缺陷：`WindowBrowserContentView.effectiveStyle()` 原会在窗口数超过
  阈值时无条件覆盖用户选择，与任务书“同时提供缩略图/列表选择”冲突。现在自动
  判定只在每个面板会话首次拿到记录时做一次；用户在分段控件显式选择后
  （`sessionAutoStyle`）不再被窗口数量或图像到达覆盖。规则只存在于控制器一处。
- `WindowStreamCapture` 增加只读诊断计数 `deliveredFrameCount` 与
  `configuredFrameRate`（同一把锁保护），用于性能对照与集成探针。
- 新增 `--window-browser-stream-probe`：只对 WindowShade 自己的探针窗口建立一路
  `WindowStreamCapture(preview: true)`，测量首帧延迟、实测帧率、停止返回与停止后
  是否还有帧。
- 离线 AppKit 回归：列表风格显示选中项预览栏，唯一一路实时视图挂到预览栏；
  切回缩略图风格后预览栏消失。

### 新增真实运行证据

- 实时预览流探针（自己的探针窗口，8fps 低分辨率配置）：
  `stream-probe: configuredFPS=8 firstFrame=186ms observedFPS=7.8`、
  `stream-probe: stopError=none framesAfterStop=9 framesNow=9 stable=true`
  —— 配置的 8fps 生效、首帧 186ms、停止方法真实返回且停止后不再有帧，折叠前的
  停流门有真机依据。
- `bash tests/run-window-browser-tests.sh` → `PASS: 159 window-browser pure-logic checks`
  （新增列表预览栏布局与实时视图挂载断言）。
- stage 构建后上述探针与之前五个探针全部正常；运行中的 WindowShade 未停止、
  `prototype/WindowShade.app` 未替换。

### 仍未验证

- 真实用户窗口上的实时预览画质/资源占用（探针只测了自己的窗口）。
- 与上轮相同：真实悬停通知、菜单/快捷键端到端动作、多显示器/Space/睡眠锁屏、
  其余资源计数与性能对照。

## 补充轮次 7：镜像投递与面板激活语义真实验证

### 真实修改

- `WindowStreamCapture` 增加镜像帧诊断计数 `mirroredFrameCount`（与投递计数同锁），
  用于验证镜像子集投递真实发生。
- 新增 `--window-browser-panel-probe`：用生产 `WindowBrowserPanel`/内容视图验证
  Dock 模式出现时是否改动前台应用或 key window，以及键盘模式是否按设计取得 key
  window 并把焦点给搜索框。
- 探针自身不再调用 `NSApp.activate`/`makeKeyAndOrderFront`：之前的“前台被改”
  观察已定位为探针自己的激活副作用，不是面板行为；现在所有探针都不改动用户前台。

### 新增真实运行证据

- 面板激活语义（连续两次干净复现）：
  - Dock 模式：`before-present appActive=false`、`after-present appActive=false
    key=false visible=true`、`dock frontmostBefore=com.apple.Safari
    frontmostAfter=com.apple.Safari unchanged=true canBecomeKey=false`
    —— 面板出现但不激活 WindowShade、不抢 key、不改前台应用。
  - 键盘模式：`keyboard key=true searchFocused=true canBecomeKey=true`
    —— 用户明确打开时按设计取得键盘焦点并可编辑搜索。
- 实时预览流（自己的探针窗口，8fps 上限配置）：
  `configuredFPS=8 firstFrame=125–658ms framesInWindow=1/1000ms`
  `mirroredFrames=1 tickerFires=28 visible=true onScreen=true`、
  `stopError=none framesAfterStop=2 framesNow=2 stable=true`。
  结论：启动、首帧、镜像子集投递、停止返回与停止后无帧均已在真机成立；同时确认
  ScreenCaptureKit 对后台/无实质变化的窗口按“内容变化才出帧”工作（实测约 1fps，
  探针窗口强制 15–28Hz damage 也未提升），因此配置的 8fps 是上限而非保证值。
- stage 构建后八个探针（dock / catalog / capture / hover / thumbnail / stream /
  panel / fixture）均可运行；运行中的 WindowShade 未被停止或替换。

### 仍未验证

- 前台用户可见窗口（有真实内容变化）下的普通窗口实时预览帧率与资源占用。
- 与上轮相同：真实悬停通知、菜单/快捷键端到端动作、多显示器/Space/睡眠锁屏、
  其余资源计数与性能对照。

## 补充轮次 8：首屏延迟实测与两处性能修复

### 真实修改

- 新增首屏延迟测试：已管理快照 → 目录发布 → 稳定排序 → 面板几何，50 个窗口
  的全部同步工作必须远小于任务书的 50ms 开发目标，并打印实测值。
- 首次实测 **69.83ms**，超目标。定位到两处真实开销并修复：
  1. `WindowCatalog.publish()` 的读路径（`records(forPID:)` / `record(for:)`）每次
     都重新做全量合并与排序；现在发布结果按需缓存，所有写路径先失效缓存。
  2. 排序比较器每次比较都调用 `WindowBrowserSearch.normalize`（大小写/宽度/变音
     折叠）；现在每条记录只算一次规范化键（`WindowCatalog.publish()` 与
     `WindowBrowserListState.reconcile` 都改掉）。
- 修复后同一测量 **2.82ms（50 窗口）**，另一次完整套件运行实测 6.72ms，均在
  50ms 目标内。

### 新增真实运行证据

- `window-browser: first-content latency windows=50 took=2.82ms`（修复前 69.83ms）。
- `bash tests/run-window-browser-tests.sh` → `PASS: 161 window-browser pure-logic checks`。
- 对照：同一台机器上真实普通窗口发现 8 个应用约 210–468ms（逐应用 AX 读取），
  说明“标题与已有缓存先行”确实不等待系统发现与截图。

### 仍未验证

- 真实面板里的端到端首屏时间（含视图构建与权限查询）需要真实悬停才能测。
- 与上轮相同的人类交互项与其余资源计数。

## 补充轮次 9：真实双显示器几何与环境记录

### 真实修改

- Dock 探针记录运行环境（macOS 版本、显示器数量、每屏分辨率与缩放），并用本机
  真实的 `NSScreen.frame`/`visibleFrame` 复核左/右/底部三个方向的面板归属、
  是否完整落在可用区域、过渡区域是否包含图标与面板之间的空隙。
- 搜索过滤复用已规范化的查询串，不再为每条记录重复折叠查询（面板刷新热路径）。

### 新增真实运行证据

- 环境：`dock-probe: macOS=27.0.0 screens=2 [1710x1107@2.0,2560x1440@2.0]`
  —— 本机确实是双显示器、不同分辨率、含负原点副屏。
- 真实屏幕几何（逐屏三方向，均 `contained=true side=true transition=true
  columns=3`）：
  - `screen[0] bottom panel=(497,87 716x572)`
  - `screen[0] left panel=(66,267 716x572)` / `right panel=(928,267 716x572)`
  - `screen[1] bottom panel=(487,1173 716x572)`
  - `screen[1] left panel=(-369,1541 716x572)` / `right panel=(1343,1541 716x572)`
  —— 负原点副屏、不同分辨率下没有坐标翻转，面板始终在图标正确一侧并完整落在
  该屏可用区域内。
- 同一次探针仍输出 `synthetic-hit=appItem bundle=com.apple.finder depth=0` 与
  观察器注册/拆除配对完成。

### 仍未验证

- 系统 Dock 实际位于左/右时的真实悬停（本机 Dock 在底部；左/右仅用真实屏幕
  frame 验证了几何归属）。
- 与上轮相同：真实悬停通知、菜单/快捷键端到端动作、睡眠锁屏，以及真实面板内
  的端到端首屏时间。

## 补充轮次 10：真实入口（设置页 + 菜单项）接线验证

### 真实修改

- 新增 `--window-browser-ui-probe`：直接构造真实设置页与状态栏菜单，但**不运行**
  AppDelegate 的启动序列（不启动传感器、不写 Dock 偏好、不触发救援、不装 event
  tap）。探针会原样恢复被临时改动的设置。

### 新增真实运行证据

- 设置页真实构建：
  `ui-probe: settingsPage switches=3 buttons=6 fields=24 hotKeyRecorders=1
  fittingHeight=601`
  —— Dock 开关、键盘面板开关、实时预览开关、快捷键记录器（恰好 1 个）、打开面板与
  编辑排除清单按钮、权限入口都在页面里，601pt 高度可放进设置窗口。
- 菜单入口真实构建与开关联动：
  `menuItem present=true enabled=true hasAction=true`、
  `menuItemWhenDisabled present=true enabled=false`、
  `menuItemRestored enabled=true settingsRestored=true`
  —— “选择窗口…”入口接入真实菜单，按设置启用/置灰，探针退出后用户偏好完全恢复。

### 仍未验证

- 真人点击设置页控件与菜单项后的完整动作链（需要真实会话；纯逻辑与动作适配层
  已有测试，UI 构建已在上方验证）。
- 与上轮相同：真实悬停通知、真实折叠/展开/置顶/关闭端到端、睡眠锁屏、真实面板
  端到端首屏时间。

## 补充轮次 11：异步结果接收条件与部分失败说明

### 真实修改

- 新增纯函数 `WindowBrowserRequestValidity.accepts(...)` 并接入
  `WindowBrowserController.scheduleMetadataRefresh` 的结果回调：结果回来时必须同时
  满足「功能仍开启」「仍是同一个面板请求代数」「目标应用实例没有被终止后复用」，
  否则丢弃并记录 `stale metadata dropped`。此前只核对了 running 与请求代数，
  缺少功能开关与 PID 复用两项。
- “展开成功但置顶失败”现在返回明确的部分失败说明
  （`展开已成功，但置顶预览失败：<原因>`），窗口保持展开，不再只报通用失败。
- 测试补充：已置顶窗口折叠仍然通过原有折叠路径（由原折叠流程负责停掉置顶流）。

### 新增真实运行证据

- `bash tests/run-window-browser-tests.sh` → `PASS: 168 window-browser pure-logic checks`
  （新增功能关闭丢弃、A→B→A 丢弃、PID 复用丢弃、键盘会话面向所有当前实例、
  已置顶窗口折叠等断言）。
- `bash prototype/build.sh --check` 通过。

### 仍未验证

- 与上轮相同：真实悬停通知、真人菜单/快捷键端到端动作、睡眠锁屏、真实面板端到端
  首屏时间。

## 补充轮次 12：按真实视口请求缩略图

### 真实修改

- 补上规格缺口：此前缩略图只请求记录列表的“前 8 条”，长列表滚动进入视口的窗口
  不会补图，也不符合“只有视口中的卡片、选中项和少量即将滚入的项目可以请求截图”。
  现在 `WindowBrowserContentView` 监听 clip view 的 bounds 变化，按真实
  `documentVisibleRect`（额外向下预取一行）计算可见键集合并通知控制器；
  滚动时不再需要的订阅立即取消，布局尚未完成时退回前 8 条兜底。
- 修正顺带发现的副作用：`refreshPanel` 原会用固定“前 8 条”覆盖用户已滚动到的
  位置，现改为一律以内容视图的真实可见集合为准。
- 新增 `scrollDocument(toY:)` 诊断/测试接缝，用于在离屏回归里验证视口集合随滚动
  变化。

### 新增真实运行证据（离屏 AppKit 回归）

- `bash tests/run-window-browser-tests.sh` → `PASS: 172 window-browser pure-logic checks`
  （新增：长列表只请求有界视口子集、首行在视口内、滚动后集合变化、视口变化会上报
  给控制器）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 全部通过。
- 首屏延迟复测 1.60ms（50 窗口）。

### 仍未验证

- 真实鼠标滚动长列表时的补图时序与真实图片出现时间（需要真实面板会话）。
- 与上轮相同：真实悬停通知、真人菜单/快捷键端到端动作、睡眠锁屏。

## 补充轮次 13：同步 AX 读取移出主线程 + 捕获几何取最新值

### 真实修改

- 修正与任务书第 9 节冲突的真实问题：缩略图与动作路径此前在**主线程**做同步 AX
  读取（解析元素、枚举应用窗口、查询按钮能力、读几何），忙应用会卡住 UI。
  现在新增 `WindowBrowserTargetResolver` 与控制器专用串行队列
  `axResolverQueue`：
  - 主线程只读取折叠/置顶会话里已有的廉价值（无 IPC）；
  - 身份核对、应用窗口枚举、按钮能力、几何读取全部在 `axResolverQueue` 执行；
  - `resolveBrowserTarget` 回到主线程交付结果，解析不唯一或身份不匹配一律返回 nil。
  `validate`、`perform`（含激活/关闭/最小化/置顶前复核）、实时预览启动、缩略图
  后端全部改走该入口；旧的同步 `windowBrowserResolveElement`/能力查询已删除。
- 缩略图捕获改为使用目标窗口**最新**的 AX 位置与尺寸计算缩放和像素上限（此前用
  目录里可能过期的逻辑位置，窗口跨不同缩放的显示器移动后会算错）。
- 捕获所需的能力与几何在同一次后台读取里返回（`WindowBrowserResolvedTarget`），
  避免多次往返与主线程阻塞。

### 新增真实运行证据

- 目录发现探针增加主线程心跳：真实发现 10 个应用（AX 读取合计 277ms、最慢单应用
  60ms）期间，主线程**最大间隔 6ms** —— 证明新增同步 AX 读取不再阻塞主线程。
  `catalog-probe: apps=10 windows=5 empty=6 failed=0 total=277ms slowestApp=60ms
  mainThreadMaxGap=6ms`
- `bash tests/run-window-browser-tests.sh` → `PASS: 172 window-browser pure-logic checks`；
  `bash prototype/build.sh --check` 通过（只剩既有 stopCapture 建议警告）。

### 仍未验证

- 忙应用（AX 超时 2s）下动作路径的主线程表现：探针机器上当前没有无响应应用。
- 与上轮相同：真实悬停通知、真实滚动补图时序、真人端到端动作、睡眠锁屏。

## 补充轮次 14：按用途收敛单次 AX 读取预算

### 真实修改

- `WindowBrowserTargetResolver.inspect` 增加 `Options`（`geometry` / `capabilities`）：
  身份核对总是执行，几何与按钮能力按用途按需读取，避免一次解析在无响应应用上叠加
  多次 2 秒 AX 超时。各调用点的用途：
  - `validate`：仅身份（动作前核对，不读几何/能力）
  - `perform`（激活/关闭/最小化/置顶前）：身份 + 能力（含 isMinimized/canClose/canMinimize）
  - 实时预览启动、缩略图捕获：身份 + 几何（按目标窗口“现在”所在屏幕算缩放）
  - 展开后复核、激活后复核：仅身份
- 缩略图后端在控制器已释放时显式失败返回，避免服务端在途槽位因缺少 completion 而
  永远占用。

### 新增真实运行证据

- 真实窗口（普通响应式应用）解析耗时中位数：
  `catalog-probe: resolve identity=0ms geometry=0ms capabilities=1ms`
  —— 动作前核对走身份-only 后，单次解析在毫秒以内。
- 同一次探针：`apps=10 windows=5 empty=6 failed=0 total=265ms slowestApp=39ms
  mainThreadMaxGap=7ms`（AX 读取全部在后台队列，主线程最大间隔 7ms）。
- `bash tests/run-window-browser-tests.sh` → `PASS: 172 window-browser pure-logic checks`；
  `bash prototype/build.sh --check` 通过。

### 仍未验证

- 无响应应用（单次 AX 调用打满 2 秒）下各动作路径的实际表现与退避：本机当前没有
  可复现的卡死应用。
- 与上轮相同：真实悬停通知、真实滚动补图时序、真人端到端动作、睡眠锁屏。

## 补充轮次 15：会话状态泄漏修复与“无权限”fixture

### 真实修改

- 修复真实状态泄漏：键盘面板每次都是新建的（搜索框为空），但控制器可能保留上一次
  会话的查询串，出现“搜索框是空的、列表却被旧查询过滤”的错误状态。现在
  打开键盘面板时显式清空 `searchText`，并在关闭面板时统一复位全部会话级状态
  （查询、布局自动判定、选中项、缩略图订阅、几何）。
- 补上任务书点名的 fixture 场景“无权限”：
  `WINDOWSHADE_BROWSER_FIXTURE=nopermission` 会渲染缺少屏幕录制权限的列表
  （应用图标 + 标题 + 状态、图像相关按钮禁用、页脚说明）。

### 新增真实运行证据

- 隔离 fixture 三种场景均正常构建并退出：
  - `nopermission`：`records=2 panel=720x560 canBecomeKey=true searchVisible=true`
  - `many`：`records=20 panel=720x560 style=list`
  - `empty`：`records=0`
- `bash prototype/build.sh --check` 通过；`bash tests/run-window-browser-tests.sh`
  → `PASS: 172 window-browser pure-logic checks`。

### 仍未验证

- 与上轮相同：真实悬停通知、真实滚动补图时序、真人端到端动作、无响应应用、
  睡眠锁屏。

## 补充轮次 16：跨入口状态一致性与折叠前订阅解除

### 真实修改

- 跨入口一致性：面板打开期间若用户通过原有菜单/快捷键折叠、展开或置顶窗口，
  面板此前不会更新。现在 `rebuildMenu()`（原有路径改变折叠/置顶状态后必然触发）
  调用 `WindowBrowserController.managedWindowsDidChange()` 刷新投影；面板未打开时
  是空操作，不产生常驻开销。原有菜单与快捷键入口本身行为不变。
- 折叠前清理补全：除了释放自有实时流与借用镜像，`prepareForFold` 还会取消该窗口的
  临时缩略图订阅并让服务作废在途截图，避免自己的面板/捕获标识与折叠截图竞争
  （折叠后的画面仍由 `ShadeState.previewImage` 提供）。
- 面板被设置关闭或处于锁定/挂起状态时，打开请求给出明确提示，而不是静默失败。

### 验证

- `bash prototype/build.sh --check`、`bash tests/run-window-browser-tests.sh`
  （`PASS: 172 window-browser pure-logic checks`）、`bash tests/run-paper-tests.sh`、
  `git diff --check` 全部通过；首屏延迟 1.44ms。

### 仍未验证

- 真人从原有菜单折叠另一个窗口时，新面板在同一屏内实时反映状态（需要真实面板会话）。
- 与上轮相同：真实悬停通知、真实滚动补图时序、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 17：单窗捕获非整屏裁切的真机证明 + 缓存隔离断言

### 真实修改

- 截图探针升级为“遮挡实验”：先在屏幕中央放蓝色探针窗口，再在其上方压一个偏移的
  红色窗口盖住蓝窗中心。若实现退回成“整屏截图后按坐标裁切”，中心会拍到红色；
  只有真正的单窗过滤器才会返回蓝窗自己的内容。
- 测试清单第 29 项落为可执行断言：把折叠路径的 `WindowSnapshotCache` 编进测试
  程序，验证新缩略图服务既不会写入/登记折叠缓存，也不会把折叠缓存里的图当成
  自己的缓存复用。

### 新增真实运行证据

- 遮挡实验（真机，stage 构建）：
  `capture-probe: profile=card pixels=461x320 source=840x584 took=919ms
  bytesPerRow=1920 center=(27,148,254) blue=true`
  —— 被红窗完全盖住中心的蓝窗，单窗捕获中心仍是 systemBlue
  `(27,148,254)`，证明没有整屏截图回退；`selectedLarge` 中心同样是蓝色。
  （首次 919ms 含双窗搭建与首次 SCK 冷启动，第二次 136ms。）
- `bash tests/run-window-browser-tests.sh` → `PASS: 176 window-browser pure-logic checks`
  （新增 4 条缓存隔离断言）。

### 仍未验证

- 与上轮相同：真实悬停通知、真实滚动补图时序、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 19：排版跟随系统字号

### 真实修改

- 新增 `WindowBrowserTypography`：字号取自 `NSFont.systemFontSize`（系统文本尺寸
  设置会改变它），正文字号用于标题/表头，`bodySize - 2`（下限 9pt）用于次要说明与
  控件字体，并提供行高计算。
- 面板字体不再写死 11/12/13pt：卡片标题与状态、列表行标题与状态、面板表头/刷新
  说明、选中项预览栏标题与状态、快捷键记录器都改用统一排版；卡片标题高度、
  状态高度、行标题/状态高度、行控件高度、表头/页脚高度都按真实行高派生，字号变大时
  自动长高，配合原有“列数收缩 + 滚动”避免文字被裁切。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 179 window-browser pure-logic checks`
  （布局断言在新派生尺寸下仍成立：按钮 ≥28pt、按钮在卡片内、图像区不超上限）。
- `bash prototype/build.sh --check` 通过；stage 构建后 fixture `mixed 9 / many 20(list)`
  面板尺寸仍为 720×560，布局正常。

### 仍未验证

- 把 macOS 系统文本尺寸调大后的真实排版效果（需要你手动调整系统设置后回来看面板；
  当前实现按行高派生，未实测超大字号）。
- 与上轮相同：真实悬停通知、真实滚动补图时序、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 20：镜像只挂在真正运行的源流上 + 解除镜像不停流

### 真实修改

- `WindowStreamCapture` 新增只读 `isRunning`（`stream != nil && !_isStopped`）。
- `PinnedPreviewController.attachMirror` 现在要求源流确实在运行：暂停、已停止或异常
  终止后不再挂接镜像，避免得到一个永远空白的预览（对应任务书“仅在源流确实运行、
  没有暂停且目标仍有效时挂接镜像”）。
- 配套重试：选中项未变但当前没有实时画面时（例如置顶流刚启动、挂接时源流尚未运行），
  面板刷新会再尝试一次，不必重新选择才能看到画面。

### 新增真实运行证据

- 流探针新增“解除镜像”阶段（等价于 `releaseMirror`：只摘掉镜像层，不停止源流）：
  `stream-probe: afterMirrorRelease running=true mirrorFrames=1->1 frames=2->2`
  —— 解除镜像后源流仍在运行、镜像不再收到帧；持久置顶流没有被关闭临时面板停掉。
- 同次输出：`configuredFPS=8 firstFrame=127ms mirroredFrames=1`、
  `stopError=none framesAfterStop=2 framesNow=2 stable=true`。
- `bash tests/run-window-browser-tests.sh` → `PASS: 179 window-browser pure-logic checks`；
  `bash prototype/build.sh --check` 通过。

### 仍未验证

- 真实置顶会话（用户点“置顶当前窗口”后）在面板关闭/重开时的镜像挂接与暂停/恢复
  组合，需要在真实会话里点一次置顶才能覆盖。
- 与上轮相同：真实悬停通知、真实滚动补图时序、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 21：镜像层共享状态纳入同一把锁

### 真实修改

- 任务书要求“更换镜像层涉及主线程和帧队列时，新增共享属性必须受同一锁或队列约束”。
  `WindowStreamCapture.mirrorLayer` 原本是主线程挂接/解除、帧队列读取的裸弱引用，
  存在数据竞争；现在改为 `stateLock` 保护的读写属性（内部 `_mirrorLayer`），与帧
  投递、代数、帧率共用同一把锁。锁只在帧回调释放之后获取，没有嵌套加锁。

### 验证

- `bash prototype/build.sh --check`、`bash tests/run-window-browser-tests.sh`
  （`PASS: 179 window-browser pure-logic checks`）、`bash tests/run-duo-tests.sh` 通过。
- stage 构建后重跑两个真实探针确认锁没有破坏帧路径：
  - 流探针：`configuredFPS=8 firstFrame=136ms mirroredFrames=1`、
    `afterMirrorRelease running=true mirrorFrames=1->1`、
    `stopError=none framesAfterStop=2 framesNow=2 stable=true`（镜像仍能收到帧，
    解除镜像后源流继续运行）。
  - 缩略图探针：`deliveries=4 captures=2 running=0 cachedBytes=675840`（不变）。

### 仍未验证

- 与上轮相同：真实置顶会话下的镜像/暂停组合、真实悬停通知、真实滚动补图时序、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 22：视图侧缩略图内存边界

### 真实修改

- 复查内存时发现真实问题：内容视图的缩略图字典会随会话累积——滚动过的每一屏都
  一直留在内存里，不受任何预算约束（服务的 24 MiB 缓存只管它自己的那份）。
  现在 `notifyVisibleKeys()` 会把视图持有的图像裁剪到“视口 + 向下预取 + 选中项”，
  滚出视口的卡片图像立即释放；滚动回来时由服务缓存命中或重新请求。
  这样形成两层有界内存：视图 ≤ 一屏 + 1 行，服务 ≤ 24 MiB。
- 新增只读 `cachedThumbnailCount` 供内存边界回归与诊断使用。

### 新增真实运行证据

- `bash tests/run-window-browser-tests.sh` → `PASS: 182 window-browser pure-logic checks`
  （新增：可以为每条记录应用缩略图、滚出视口的图像会被释放、视图保留量
  ≤ 视口 + 1）。
- `bash prototype/build.sh --check` 通过；stage 构建后 fixture `many`（20 条列表）
  仍正常。

### 仍未验证

- 真实滚动长列表时视图内存峰值的实测（需要真实面板会话与长列表）。
- 与上轮相同：真实置顶会话下的镜像/暂停组合、真实悬停通知、真人端到端动作、
  无响应应用、睡眠锁屏。

## 补充轮次 23：AX 与 WindowServer 窗口来源交叉核对（实测限制）

### 真实修改

- 目录探针增加交叉核对列 `cgLayer0=`：对每个 regular 应用同时统计
  `WindowBrowserDiscovery` 得到的记录数与 `WindowListCache` 里该进程的 layer-0、
  可见 alpha、有几何、非桌面组件的窗口数。

### 实测结果与结论

- 本机一次运行：`Safari windows=4 cgLayer0=18`、`Drafts windows=1 cgLayer0=9`，
  其余应用两者一致（多为 0 或 1）；`apps=10 windows=5 empty=8 failed=0
  total=254ms slowestApp=51ms mainThreadMaxGap=6ms`。
- 结论：两种来源差异显著，多出来的通常是应用未作为窗口暴露的辅助/帮助窗口。
  当前实现以应用自报的辅助功能窗口列表作为窗口身份来源（CG 只补可见性与能力），
  因此这些多出来的项不会获得窗口级写操作；这也正是任务书要求的“不能声称两种来源
  可以发现所有应用、所有 Space 的每个窗口”。该限制已写入用户文档
  （`docs/window-browser.md` 的兼容限制一节）。

### 仍未验证

- 同一应用在多个 Space 同时有窗口时的 AX/CG 覆盖差异（需要多 Space 会话）。
- 与上轮相同：真实滚动内存峰值、真实置顶会话镜像组合、真实悬停通知、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 25：临时面板显式状态机

### 真实修改

- 任务书要求“实现可测试的临时面板状态，不用多个互相独立的 Bool 拼凑。可采用
  hidden、pendingShow、visible、pendingHide、interacting，并让每个状态携带对应
  请求 token”。此前只定义了枚举，控制器仍靠独立工作项判断；现在新增纯状态机
  `WindowBrowserPanelStateMachine` 并真正接入：
  - `presentDockPanelIfNeeded`：`beginShow(request:)`，过期 token 的延迟显示任务
    直接失效，面板真正出现后 `confirmShow`；
  - 键盘面板打开：`beginShow` + `confirmShow`；
  - 鼠标离开：`beginHide`（延迟内重新进入会 `cancelHide`）；指针在面板内：
    `beginInteraction`，交互期间禁止自动隐藏，离开后 `endInteraction`；
  - 关闭面板：`reset()`，下一次打开不会继承旧 token。
  状态机同时提供 `accepts(request)`，作为延迟工作项的第二道过期校验。

### 新增真实运行证据

- `bash tests/run-window-browser-tests.sh` → `PASS: 201 window-browser pure-logic checks`
  （新增 19 条状态机断言：隐藏起始无 token、pendingShow 携带 token、过期 token 不能
  confirmShow/beginHide、cancelHide 回到 visible、interaction 阻止自动隐藏、endInteraction
  回到 visible、reset 丢弃 token、Dock 图标切换替换待显示 token）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过；stage 构建后 fixture `mixed` 仍正常。

### 仍未验证

- 真实悬停下的完整状态迁移（进入图标 → 延迟显示 → 进入面板 → 离开 → 关闭）需要
  真实鼠标会话；离屏测试覆盖的是状态机本身与控制器接线点。
- 与上轮相同：真实滚动内存峰值、真实置顶会话镜像组合、真实悬停通知、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 26：实时不可用回退到快照/图标

### 真实修改

- 复查实时预览失败路径时发现真实回退缺陷：挂接实时画面时会把卡片已缓存的静态图
  一并清掉，一旦流启动失败或随后停止，卡片只剩占位符，而不是任务书要求的
  “实时不可用就回到快照或图标”。
- 现在改为“静态图在下、实时视图覆盖在上”：挂接实时视图时不再清除静态缩略图，
  解除/失败/停止时实时视图被移除，下面的快照自动重新可见；没有快照时仍是
  图标 + 说明。

### 新增真实运行证据

- `bash tests/run-window-browser-tests.sh` → `PASS: 204 window-browser pure-logic checks`
  （新增：实时视图挂到卡片之上、解除后从父视图移除、缓存的静态快照仍可作为回退）。
- 该回归还确认了一个设计细节：列表风格下只有选中项会承载实时视图，非选中项不会
  被挂接（测试用缩略图风格验证卡片路径）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过；stage 构建后 fixture `many` 正常。

### 仍未验证

- 真实置顶流启动失败/停止后的画面回退观感（需要真实面板会话）。
- 与上轮相同：真实滚动内存峰值、真实悬停通知、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 27：死代码清理 + 观察器诊断落地

### 真实修改

- 用“定义/引用计数”审计整个新模块，删除只被定义、没有任何调用点的 API：
  `WindowBrowserFetchResult.value`/`isPublishable`、`WindowBrowserActionOutcome.isTerminal`、
  `WindowBrowserTemporaryPanelState.isOnScreenOrPending`、`WindowBrowserListState.selectAdjacent`、
  `WindowBrowserListState.newItemOrdering`、`WindowIdentityAllocator.noteApplicationRelaunched`、
  `AppDelegate.cancelWindowBrowserFoldWaiter`、控制器的 `isPanelVisible`/`isDockObserverRunning`/
  `currentSessionID`、内容视图的 `selectedKey()`/`setStatus(_:)`、缩略图服务的
  `currentCaptureVersion`，以及 `PinnedPreviewSessionSnapshot.isInteracting`。
  保留 `controlTextDidChange`（AppKit 代理回调，框架调用）。
- 把原本孤立无引用的观察器诊断 `usesNotifications`/`observerGeneration` 真正用于回退探针
  输出；`WindowThumbnailService.startedCount`/`deliveredCount` 也已进入缩略图探针输出。

### 新增真实运行证据

- 回退探针复测：
  `hover-probe: icon-hit pid=3157 bundle=com.apple.finder expected=com.apple.finder match=true`、
  `hover-probe: non-icon dock point (1157,39) target=cleared`、
  `hover-probe: diagnostics notificationsReliable=false generation=1`
  —— 再次确认当前这台机器上成功路径来自回退命中，AX 通知仍未观察到（与未验证项一致）。
- `bash tests/run-window-browser-tests.sh` → `PASS: 204 window-browser pure-logic checks`；
  `bash prototype/build.sh --check` 通过。

### 仍未验证

- 与上轮相同：真实悬停通知、真实置顶会话镜像组合、真实滚动内存峰值、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 28：对齐项目既有纸面外观

### 真实修改

- 任务书要求“保留现有原生外观和纸张组件，使用现有颜色、阴影、字体及浅深色规则”。
  浏览面板此前用通用圆角与系统窗口阴影；现在改为与置顶预览面板完全相同的纸面处理：
  `PaperSurfaceStyle.installShadow(on: self)`（子阴影面板随窗口生命周期自动清理），
  面板内容与选中项预览栏圆角统一为项目纸面圆角 10pt，卡片/缩略图仍为 6–10pt。
  面板颜色继续使用系统动态色（`windowBackgroundColor`/`controlBackgroundColor`/
  `separatorColor`/`labelColor`），浅深色自动跟随，不引入新主题或网页视图。
- 测试程序同步纳入 `PaperSurfaceStyle.swift`（面板现在引用它）。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 204 window-browser pure-logic checks`；
  `bash tests/run-paper-tests.sh` 通过（纸面组件回归未受影响）。
- `bash prototype/build.sh --check` 通过；stage 构建后 fixture `mixed/many/nopermission`
  三个场景仍正常渲染。

### 仍未验证

- 纸面阴影与圆角在浅色/深色下的实际观感（需要你打开面板目视确认；实现与置顶预览
  面板同一套参数）。
- 与上轮相同：真实悬停通知、真实置顶会话镜像组合、真实滚动内存峰值、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 29：面板激活语义决定性验证 + 键盘焦点加固

### 真实修改

- 面板探针升级为三阶段并带对照实验：
  1. `WINDOWSHADE_PANEL_PROBE_SKIP_PRESENT=1`：完全不显示窗口，只看进程本身是否被激活；
  2. 首次显示 Dock 面板 → 键盘面板；
  3. 同一进程稍后再次显示 Dock 面板（稳态）。
- `presentKeyboardPanel` 加固：显式 `activate(ignoringOtherApps: true)` 后，在
  0.12/0.3/0.6s 做有限重试（再次激活 + makeKeyAndOrderFront + 聚焦搜索框），
  解决“激活完成晚于 makeKeyAndOrderFront”导致的键盘焦点丢失。
- `PaperSurfaceStyle` 的纸面阴影子窗口改为不可成为 key/main（`PaperShadowPanel`），
  影子窗口本身不该抢键盘焦点（对置顶预览/覆盖层同样受益）。纸面阴影本身保留：
  对照实验证明它不是激活原因。

### 实测结论（重要）

- 对照实验：不显示任何窗口时 `frontmostBefore=frontmostAfter=com.openai.codex
  unchanged=true appActiveAfter=false` —— 进程本身不会被激活。
- 首次显示 Dock 面板会激活所属 app
  （`unchanged=false appActiveAfter=true`），但同一进程**稍后第二次**显示时：
  `frontmostBefore=com.openai.codex → frontmostAfter=com.openai.codex unchanged=true
  appActiveAfter=false key=false`。
  恢复纸面阴影后再次复测（前台为 Safari）：
  `frontmostBefore=com.apple.Safari frontmostAfter=com.apple.Safari unchanged=true
  appActiveBefore=false appActiveAfter=false key=false`
  —— 稳态悬停面板在别的应用前台时不激活 WindowShade、不成为 key window，
  且纸面阴影保留。
  结论：首次激活是“从当前前台应用启动的新进程首次出窗”的探针启动假象；长期运行的
  WindowShade（真实情况）显示悬停面板时不会激活自己，也不会成为 key window。
- 键盘面板连续 3 次运行均为 `key=true searchFocused=true canBecomeKey=true`。

### 仍未验证

- 真人在其他应用前台时悬停 Dock 图标的面板激活行为（探针已用稳态对照证明；
  真实会话仍建议目视确认一次）。
- 与上轮相同：真实悬停通知、真实置顶会话镜像组合、真实滚动内存峰值、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 30：键盘面板关闭时归还焦点

### 真实修改

- 补上任务书要求但此前缺失的一环：“用户在键盘面板中取消时，不激活任何候选窗口；
  避免在关闭时无条件重新激活打开前的应用……只有确实由本面板暂时取得焦点且没有
  新的用户目标时，才按 AppKit 正常流程归还焦点。”
  现在打开键盘面板前记录当前前台应用；关闭时若「面板曾是 key window」
  「我们仍是前台（用户没有点击别处）」「记录的确实是别的应用」三条同时成立，
  才调用现有 `activateApp(pid:)` 归还焦点，否则不打扰。
- 判定抽成纯函数 `WindowBrowserFocusReturnPolicy.shouldReturnFocus(...)`。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 210 window-browser pure-logic checks`
  （新增 6 条：仍持有时归还、用户已切走时不抢回、Dock 面板从不归还、面板未成为 key
  时不归还、没有记录不归还、不把焦点“归还”给自己）。
- `bash prototype/build.sh --check` 通过。

### 仍未验证

- 真实会话里“快捷键打开面板 → Escape 关闭 → 焦点回到原应用”的端到端观感
  （策略有测试、控制器接线经代码复核；需要真实快捷键会话确认）。
- 与上轮相同：真实悬停通知、真实置顶会话镜像组合、真实滚动内存峰值、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 31：重复打开面板不再叠加

### 真实修改

- 修复真实入口缺陷：菜单“选择窗口…”每次点击都会调用 `openKeyboardPanel()`，
  而该函数此前无条件新建面板——连续点击会**叠加多个面板**（旧面板无人引用、
  资源泄漏且堆在后面）；Dock 面板开着时打开键盘面板也会覆盖引用。
  现在：键盘面板已打开时只把它带到前台并聚焦搜索框；存在 Dock 面板时先按正常流程
  收掉旧面板（含会话状态复位与资源释放），再创建键盘面板。
- 焦点归还策略补一个边界：应用退出（`stop`）时不归还焦点，其余情况仍按策略判断。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 214 window-browser pure-logic checks`
  （新增 4 条 `WindowBrowserOpenPolicy` 断言：无面板→新建、键盘面板已开→聚焦、
  Dock 面板→替换、面板已关→新建）；`bash prototype/build.sh --check` 通过；
  stage 构建后 fixture `mixed` 正常。

### 仍未验证

- 真实会话里连续点击菜单多次、以及 Dock 面板与键盘面板之间切换的实际观感
  （入口逻辑已修复，需要真实菜单/悬停会话确认不会出现两个面板）。
- 与上轮相同：真实悬停通知、真实置顶会话镜像组合、真实滚动内存峰值、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 32：选中项滚入视口

### 真实修改

- 补上键盘操作的真实体验缺陷：方向键把选中项移出视口后列表不滚动，用户看不到
  当前选中项，视口缩略图请求也停留在旧位置。现在 `WindowBrowserContentView.select`
  在选中项变化时用 `documentView.scrollToVisible(...)` 把它滚入可见区域，并重新
  计算可见键集合，让控制器只对真正可见的项目请求缩略图。

### 新增真实运行证据

- `bash tests/run-window-browser-tests.sh` → `PASS: 216 window-browser pure-logic checks`
  （新增：最后一行初始不在视口内；选中它之后 `visibleWindowKeys` 包含它）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过；stage 构建后 fixture `many` 正常。

### 仍未验证

- 真实面板里连续按方向键滚动的观感与滚动惯性（离屏测试覆盖布局与视口集合）。
- 与上轮相同：真实悬停通知、真实置顶会话镜像组合、真实滚动内存峰值、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 33：面板窗口的可访问性名称

### 真实修改

- 无边框面板默认没有窗口标题，VoiceOver 会读成无名窗口。现在按用途设置窗口标题/
  可访问性名称（Dock 悬停 = “窗口浏览”，键盘面板 = “窗口选择”），并把临时面板
  排除在窗口菜单之外，避免污染 app 的窗口列表。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 218 window-browser pure-logic checks`
  （新增：两种模式的面板都有可访问性窗口标题；临时面板不在窗口菜单中）。
- `bash prototype/build.sh --check` 通过。

### 仍未验证

- VoiceOver 实际朗读效果（需要开启读屏器逐项确认卡片标题、状态与动作名称）。
- 与上轮相同：真实悬停通知、真实置顶会话镜像组合、真实滚动内存峰值、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 34：开发验收入口写入 DEVELOPMENT.md

### 真实修改

- 按仓库既有惯例（`docs/design-v1.md` 有“开发验收入口”一节），在 `DEVELOPMENT.md`
  的调试章节新增“窗口浏览”小节：纯逻辑与离屏 AppKit 回归命令、隔离 fixture 的
  运行方式（场景与自动退出/小屏环境变量）、以及八个只读真机探针的清单，
  并指向用户向说明 `docs/window-browser.md` 与进度记录。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 218 window-browser pure-logic checks`；
  `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 全部通过。

### 仍未验证

- 与上轮相同：VoiceOver 实测、真实悬停通知、真实置顶会话镜像组合、
  真实滚动内存峰值、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 35：排除清单即时生效 + 选中档位替换

### 真实修改

- 排除清单边界：用户把当前 Dock 目标应用加入排除清单时，立即关闭面板，
  而不是留下一个被过滤成空的面板（键盘面板仍按过滤后列表正常刷新）。
- 缩略图档位替换：选中项从卡片档升到“选中大图档”时，此前已有订阅会挡住重新请求，
  选中预览一直停留在 512×320。现在记录每个 key 当前档位，档位变化时替换订阅
  （`WindowBrowserThumbnailSubscriptionPolicy.needsReplace`），同档位继续复用。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 221 window-browser pure-logic checks`
  （新增：同档位复用、卡片档→选中大图档替换、档位未知时替换）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过；stage 构建后 fixture `many` 正常。

### 仍未验证

- 真机观察选中大图档的清晰度与占用（离屏测试覆盖订阅替换逻辑）。
- 与上轮相同：VoiceOver 实测、真实悬停通知、真实置顶会话镜像组合、
  真实滚动内存峰值、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 36：状态机滞留漏洞修复

### 真实修改

- 复核实测状态机接线时发现真实漏洞：一次隐藏检查若判定“鼠标仍在内”，状态会停在
  `pendingHide`；之后 `beginHide` 对 `pendingHide` 返回 false，导致再也排不出隐藏，
  面板可能滞留（只剩外点击/切前台等路径能关）。现在：
  - `beginHide` 对 `visible / pendingShow / pendingHide` 都接受并幂等回到
    `pendingHide`（重复排程安全）；
  - `confirmShow` 允许从 `pendingHide` 回到 `visible`（面板确实出现时状态更准确，
    待执行的隐藏工作项仍按鼠标位置决定是否关闭）；
  - `scheduleHideCheck` 不再单开一条绕过状态机的路径，统一走 `scheduleHide`。
- 顺带删除卡片视图里从未被使用（没有 `mouseEntered/Exited` 回调）的 tracking area。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 225 window-browser pure-logic checks`
  （新增：pendingHide 重复排程幂等、pendingHide → visible 保住 token）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过；stage 构建后 fixture `many` 正常。

### 仍未验证

- 真实悬停里的完整“出现 → 留在面板 → 离开 → 关闭”迁移（状态机与接线有测试，
  仍需真实鼠标会话确认观感）。
- 与上轮相同：VoiceOver 实测、真实悬停通知、真实置顶会话镜像组合、
  真实滚动内存峰值、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 37：规模回归（面板与首屏数据路径）

### 真实修改

- 面板规模回归：新增 200 个窗口的列表布局断言——视口子集仍然有界
  （`visibleWindowKeys.count < 记录数`），视图侧缩略图数量仍 ≤ 视口 + 1。
- 首屏数据路径规模对照：同一“已管理快照 → 发布 → 稳定排序”路径测 50 与 200 个
  窗口，都必须在任务书的 50ms 开发预算内，并打印实测值。

### 新增真实运行证据

- `window-browser: first-content latency windows=50 took=0.66ms`
- `window-browser: first-content latency windows=200 took=2.28ms`
- `bash tests/run-window-browser-tests.sh` → `PASS: 229 window-browser pure-logic checks`
  （新增 4 条规模断言：200 条全部发布、首屏仍在预算内、视口有界、视图图像有界）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过；stage 构建后 fixture `many` 正常。

### 仍未验证

- 真实 200 个已管理窗口的场景（需要大量折叠窗口；离屏规模回归覆盖数据与布局）。
- 与上轮相同：VoiceOver 实测、真实悬停通知、真实置顶会话镜像组合、
  真实滚动内存峰值、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 38：刷新时跳过无变化的卡片重建

### 真实修改

- 面板每次收到元数据都会重配所有可见卡片（重建可访问性动作、重设图层/文本），
  即使该卡片内容未变。现在卡片与列表行分别记录“内容签名”
  （metadataRevision + 应用名 + 标题 + 选中态 + 忙碌态 + 录屏权限），签名不变时
  直接跳过重配；标题/状态/能力/选中态变化时才重建。这样多应用并发刷新时
  主线程只处理真正变化的项。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 231 window-browser pure-logic checks`
  （新增：无变化记录跳过重配——用“手工改写按钮标题后再次 configure 仍保留”验证；
  记录变化后确实重建）。
- 首屏延迟复测：50 窗口 0.68ms、200 窗口 2.28ms。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过；stage 构建后 fixture `mixed/many` 正常。

### 仍未验证

- 多应用并发刷新下主线程耗时的真机对照（需要真实面板会话与多个忙碌应用）。
- 与上轮相同：VoiceOver 实测、真实悬停通知、真实置顶会话镜像组合、
  真实滚动内存峰值、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 39：列表行可访问性对齐

### 真实修改

- 列表行的操作按钮现在带窗口名（VoiceOver 读作“折叠：<窗口标题>”等），应用图标
  不作为独立可访问性元素——与卡片视图的行为保持一致，避免读屏器逐个朗读装饰图标。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 234 window-browser pure-logic checks`
  （新增：列表行有两个操作按钮、按钮名称含目标窗口标题、图标不是独立可访问性元素）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过；stage 构建后 fixture `mixed` 正常。
- 首屏延迟同轮复测：50 窗口 2.77ms、200 窗口 8.70ms（仍在 50ms 预算内）。

### 仍未验证

- 开启 VoiceOver 的实际朗读顺序与措辞（需要人工逐项确认）。
- 与上轮相同：真实悬停通知、真实置顶会话镜像组合、真实滚动内存峰值、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 40：设置页两个真实交互缺陷

### 真实修改

- 排除清单编辑器此前用单行 `NSTextField` 承载“每行一个 bundle ID”，实际无法正常
  多行编辑；改为 `NSScrollView + NSTextView`（带滚动条、等宽字体），保存时仍支持
  换行/逗号/分号分隔。
- 快捷键记录器此前会把“只按修饰键”（如单按 ⌘）记成一个组合，随后注册必然失败；
  现在修饰键单独按下时保持录制状态，等真正的键。判定抽成
  `WindowBrowserSettings.isModifierOnlyKeyCode` 并加断言。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 236 window-browser pure-logic checks`
  （新增：⌘ / 右⌥ 视为修饰键、普通按键可以录制）。
- UI 路由探针在最新构建上复测：`settingsPage switches=3 buttons=6 fields=24
  hotKeyRecorders=1 fittingHeight=601`、菜单项启用/置灰联动与设置还原均正常。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过。

### 仍未验证

- 真人打开“编辑排除清单…”对话框做一次多行输入（需要真实设置窗口交互）。
- 与上轮相同：VoiceOver 实测、真实悬停通知、真实置顶会话镜像组合、
  真实滚动内存峰值、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 41：全局快捷键不再抢占系统编辑组合

### 真实修改

- 复查全局热键安全性时发现真实风险：`RegisterEventHotKey` 注册的是**全局**热键，
  而此前只拒绝了少量保留组合，用户可能录出 ⌘C/⌘V/⌘A/⌘S 这类系统级编辑快捷键，
  导致全系统对应功能失效。现在要求组合必须包含 Control 或 Option（项目自身的
  ⌃⌘ 系列即符合此约定）：单字母无修饰键、仅 Shift、纯 ⌘ 与 ⌘⇧ 组合都会被拒绝。
  设置页副标题与 `docs/window-browser.md` 已同步说明。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 238 window-browser pure-logic checks`
  （新增：纯 ⌘ 组合被拒绝、⌘⇧ 组合被拒绝；⌘⌥ 与 ⌃ 组合仍被接受）。
- UI 路由探针复测：设置页与菜单联动正常（`menuItemRestored enabled=true
  settingsRestored=true`）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过。

### 仍未验证

- 真人录制一个含 ⌃ 或 ⌥ 的组合并实际触发（需要真实快捷键会话）。
- 与上轮相同：排除清单多行输入实测、VoiceOver 实测、真实悬停通知、
  真实置顶会话镜像组合、真实滚动内存峰值、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 42：运行中权限变化的入口联动

### 真实修改

- 权限可能在运行中才被授予或撤销，此前没有联动：Dock 入口在启动时无辅助功能权限
  就不会启动观察器，之后授权也不会自动生效（要重启应用）。现在
  `permissionsDidChange` 会按当前设置与权限重新裁决：
  - 有权限且 Dock 开关开启 → 若观察器未运行则启动；
  - 无权限或开关关闭 → 停用观察器，并关闭正在显示的 Dock 面板（避免留下无法操作
    的窗口）；
  屏幕录制变化仍会清空图像缓存并释放自有实时流。
- 顺带清理：若旧版本存下的快捷键现在属于被拒绝组合，启动时清掉该存储值并只提示
  一次，不再每次启动都弹提示。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 238 window-browser pure-logic checks`；
  `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过。
- stage 构建后 fixture `mixed` 正常。

### 仍未验证

- 真实“运行中授予辅助功能权限后立刻悬停 Dock”的联动（需要真机改系统设置；
  代码路径已按权限状态重新裁决）。
- 与上轮相同：快捷键实录、排除清单多行输入、VoiceOver 实测、真实悬停通知、
  真实置顶会话镜像组合、真实滚动内存峰值、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 43：回退解析稳定性复测 + 防御性复查

### 复测与复查

- Dock 回退探针连续 3 次运行结果一致：
  `icon-hit pid=3157 bundle=com.apple.finder expected=com.apple.finder match=true`、
  `non-icon dock point (1157,39) target=cleared`
  —— 命中图标产出正确应用实例、非图标位置清除旧目标，均非偶然成功。
- 防御性复查新模块：强制解包、`try!`、`as!` 与下标访问逐处核对。`as! AXUIElement`
  前都有 `CFGetTypeID == AXUIElementGetTypeID()` 守卫；`parts[0]`、`records[0]`、
  `queued[index]`、`matches[0]`、`keys[min(...)]` 等全部有前置 guard/空集合检查；
  未发现未受保护的下标或强制解包。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 238 window-browser pure-logic checks`；
  `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 全部通过。

### 仍未验证

- 与上轮相同的人类交互项（真实悬停通知、真人端到端动作、权限/睡眠锁屏、
  VoiceOver、排除清单多行输入、快捷键实录）。

## 补充轮次 44：Dock 观察器的 AX 读取真正移出主线程

### 真实修改

- 死代码审计发现 `DockHoverObserver.workQueue` 从未使用——也就是说 Dock 悬停路径的
  AX 命中与解析（`AXUIElementCopyElementAtPosition`、父链遍历、`AXURL`/几何读取、
  选中子项读取、Dock 树遍历）其实仍跑在**主线程**，鼠标每次靠近 Dock 都会做同步
  IPC，违反任务书第 9 节。现在：
  - Dock 树发现移到 `workQueue`，只把 AX 矩形带回主线程换算 Cocoa 区域；
  - 鼠标命中与解析移到 `workQueue`，结果回主线程后再 `emit`/清除；
  - 通知路径（选中子项）同样移到 `workQueue`；
  - `NSScreen`/坐标基准的换算一律在主线程算好后传入（不把主线程 API 带到后台）。
  - 回调都核对观察器代数，过期结果直接丢弃。
- 探针改为轮询等待异步结果（最多约 1.5s，必要时重发一次指针事件），不再依赖固定
  0.3s。

### 验证

- 回退探针 3/3 次一致：
  `icon-hit pid=3157 bundle=com.apple.finder expected=com.apple.finder match=true`、
  `non-icon dock point (1157,39) target=cleared`、
  `diagnostics notificationsReliable=false generation=1`。
- `bash tests/run-window-browser-tests.sh` → `PASS: 238 window-browser pure-logic checks`；
  `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过。

### 仍未验证

- 真实鼠标悬停下主线程间隔的实测（探针已证明 AX 不再在主线程执行；真实会话可再
  用日志里的 `main-thread stall` 观察）。
- 与上轮相同的人类交互项。

## 补充轮次 45：折叠入口的冗余主线程 AX 读取

### 真实修改

- 扫查新代码剩余的 AX 调用点后发现：`AppDelegate.windowBrowserBeginFold` 在折叠前
  又做了一次 `windowID(of:)`（可能触发 CG 列表枚举 + AX 属性读取），而调用方刚刚在
  `WindowBrowserTargetResolver.inspect`（专用队列）里核对过同一身份。现在这里只保留
  廉价的 PID 复核，主线程不再重复 AX 读取。
- 复查其余调用点：新功能里的 AX **读取**都已在后台队列（解析/发现/Dock 命中）；
  留在主线程的是动作写入（`setAXMinimized`/`raiseAXWindow`/`focusAXWindow`/
  `pressAXButton`）与既有折叠/恢复事务——与任务书“只移动确认为独立的读取工作”一致；
  `axPosition(fromCocoaFrame:)` 是纯坐标换算，不涉及 AX。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 238 window-browser pure-logic checks`
  （首屏 200 窗口 4.34ms）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 通过。
- stage 构建后回退探针 `icon-hit ... match=true` / `non-icon ... target=cleared`，
  fixture `mixed` 正常。

### 仍未验证

- 与上轮相同的人类交互项（真实悬停通知、真人端到端动作、权限/睡眠锁屏、
  VoiceOver、排除清单多行输入、快捷键实录、真实主线程间隔观察）。

## 补充轮次 46：Dock 目标的元数据查询走独立高优先级队列

### 真实修改

- 任务书要求“Dock 实例的识别工作不能排在几十个普通应用查询之后”。此前单目标
  （Dock 悬停）与整批（键盘面板全局发现）共用同一条串行队列：若上一会话的全局
  发现仍在跑，Dock 目标的查询会排在最多十几个应用之后。现在单目标请求走
  `targetMetadataQueue`（userInitiated），批量走原 `metadataQueue`（utility）。
  两条队列共享 `metadataInFlight`/`lastMetadataRequest` 记账，仍然保证“每个应用
  实例只有一个在途任务”；同时最多只有 1 个目标查询 + 1 个批量查询并发，
  符合任务书“初始最多同时处理两个应用实例”的上限。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 238 window-browser pure-logic checks`
  （首屏 200 窗口 4.50ms）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 通过。

### 仍未验证

- 真实“全局发现进行中同时悬停 Dock 图标”的先后顺序与耗时（需要真实面板会话；
  队列拓扑已按上限拆分）。
- 与上轮相同的人类交互项。

## 补充轮次 47：异步记账清理与恢复中状态文案

### 真实修改

- 异步记账残留：过期元数据结果被丢弃时未清除该 PID 的“需要补刷”标记；现在一并
  清掉，避免记账长期残留。
- `stop()` 现在同时清空 `metadataInFlight`/`metadataQueued`/`lastMetadataRequest`
  三份记账（此前只清目录与会话状态）。
- 状态文案缺陷：恢复中的窗口此前落到默认文案“打开”，现在明确显示“◌ 正在展开”。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 239 window-browser pure-logic checks`
  （新增：恢复中记录显示“正在展开”）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh` 通过；stage 构建后 fixture `mixed` 正常；
  首屏 200 窗口 5.25ms。

### 仍未验证

- 与上轮相同的人类交互项（真实悬停通知、真人端到端动作、权限/睡眠锁屏、
  VoiceOver、排除清单多行输入、快捷键实录、全局发现与 Dock 悬停并发顺序）。

## 补充轮次 48：实时不可用时的用户可见说明

### 真实修改

- 实时预览启动失败（找不到 SCWindow 或 startCapture 抛错）此前只写日志，用户没有
  任何说明，只会看到画面停在快照。现在面板页脚会显示“实时预览不可用，已回到快照”，
  并且选中项变化或重新开始实时预览时自动清除该说明。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 239 window-browser pure-logic checks`；
  `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 通过。
- stage 构建后 fixture `mixed` 正常；首屏 200 窗口 3.18ms。

### 仍未验证

- 真机看到“实时预览不可用，已回到快照”的实际时机（需要真实面板会话来制造捕获失败，
  例如目标窗口受保护内容或权限撤销）。
- 与上轮相同的人类交互项。

## 补充轮次 49：右键菜单期间的关闭请求延后执行

### 真实修改

- `NSMenu.popUp` 使用嵌套事件循环；此间若其它路径要求关闭面板（切前台、切 Space、
  点外部等），直接释放面板会把正在作为菜单锚点的视图一起带走，存在崩溃风险。
  现在菜单跟踪期间收到的关闭请求先记入 `pendingCloseReason`，菜单结束后再执行。
- 复用同一标记：菜单打开时已有的自动隐藏抑制（`contextMenuOpen`）保持不变。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 239 window-browser pure-logic checks`；
  `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 通过。
- stage 构建后 fixture `nopermission` 正常；首屏 200 窗口 2.90ms。

### 仍未验证

- 真人右键打开卡片菜单、期间切换应用或点击外部，确认菜单关闭后父面板才关闭
  （需要真实面板交互）。
- 与上轮相同的人类交互项。

## 补充轮次 50：全探针冒烟（最新构建）

### 运行

在最新 stage 构建上顺序运行全部只读探针与 fixture：
`dock / hover / catalog / capture / thumbnail / stream / panel / ui / fixture`。

### 结果（全部通过，用户 WindowShade 全程保持运行）

```text
dock-probe:      selected-children notifications in 2s = 0 / observer teardown complete
hover-probe:     icon-hit ... match=true / non-icon ... target=cleared /
                 diagnostics notificationsReliable=false generation=1
catalog-probe:   resolve identity=0ms geometry=0ms capabilities=0ms
                 apps=10 windows=6 empty=5 failed=0 total=210ms slowestApp=50ms
                 mainThreadMaxGap=6ms
capture-probe:   card pixels=461x320 center=(27,148,254) blue=true（遮挡实验仍成立）
                 selectedLarge pixels=840x584 took=42ms
thumbnail-probe: deliveries=4 captures=2 serviceStarted=2 serviceDelivered=3
                 running=0 cachedBytes=675840
stream-probe:    afterMirrorRelease running=true mirrorFrames=1->1 frames=2->2
                 stopError=none framesAfterStop=2 framesNow=2 stable=true
panel-probe:     keyboard key=true searchFocused=true canBecomeKey=true
                 dock-second unchanged=true key=false
ui-probe:        menuItemWhenDisabled enabled=false / menuItemRestored
                 enabled=true settingsRestored=true
fixture:         records=9 panel=720x560 canBecomeKey=true searchVisible=true
```

这轮冒烟覆盖了最近几轮的异步化改造（Dock 观察器后台队列、目标元数据高优先级队列、
模型/缓存清理），确认没有回归。

### 仍未验证

- 与上轮相同的人类交互项（真实鼠标悬停通知、真人端到端窗口动作、权限/睡眠锁屏、
  VoiceOver、排除清单多行输入、快捷键实录）。

## 补充轮次 51：面板与搜索框的可访问性标签

### 真实修改

- 搜索框此前只有 placeholder 供 VoiceOver 推断用途；现在显式设置
  `accessibilityLabel = "搜索窗口"`。面板内容视图也设置组角色与名称
  “窗口浏览面板”，便于读屏器说明当前位置。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 241 window-browser pure-logic checks`
  （新增：内容视图与搜索框都有可访问性标签）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 通过；stage 构建后 fixture
  `mixed` 正常。

### 仍未验证

- VoiceOver 实际朗读整体顺序（需要开启读屏器人工确认）。
- 与上轮相同的人类交互项。

## 补充轮次 52：“功能关闭时新增常驻查询为零”实测

### 真实修改

- 控制器新增只读计数 `axQueryCount`（元数据发现 + 目标解析各计一次），用于把任务书
  “关闭新功能时新增常驻系统查询为零”从代码复核升级为实测。
- 新增 `--window-browser-idle-probe`：临时把 Dock 开关置为关闭，构造 AppDelegate 与
  窗口浏览控制器并 `start()`，观察一秒后读计数，然后 `stop()` 并**原样恢复**用户的
  Dock 开关设置。探针不启动传感器、不触发救援、不写 Dock 偏好。

### 实测结果

```text
idle-probe: dockEnabled=false axQueries=0 thumbnailsInFlight=0 thumbnailBytes=0
idle-probe: afterStop axQueries=0 thumbnailsInFlight=0 thumbnailBytes=0 settingsRestored=true
```

即：Dock 入口关闭时，新功能在启动一秒后没有发起任何 AX 查询、没有在途截图、没有
新增缓存字节；停止后依然为零，用户设置被完整恢复。

### 验证

- `bash prototype/build.sh --check` 通过；`bash tests/run-window-browser-tests.sh`
  → `PASS: 241 window-browser pure-logic checks`。

### 仍未验证

- 与上轮相同的人类交互项（真实悬停通知、真人端到端动作、权限/睡眠锁屏、VoiceOver、
  排除清单多行输入、快捷键实录）。

## 补充轮次 53：过期最后画面作为快照展示

### 真实修改

- 任务书要求“折叠及最小化窗口优先使用已保存的最后有效画面，明确标为快照”，此前这类
  记录在没有折叠快照时直接显示图标。现在：
  - `WindowThumbnailService.snapshotImage(windowKey:purpose:)` 提供“过期但合法”的
    最后画面（不触发新截图、不改变 `cachedImage` 的新鲜度判定）；
  - 面板在“图标回退”分支优先使用该快照并标注“已保存的快照”，没有才显示图标与说明；
- 用户文档补充了这条行为说明。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 244 window-browser pure-logic checks`
  （新增：新鲜缓存可读、超过新鲜期后 `cachedImage` 返回 nil、`snapshotImage` 仍返回
  最后画面——用注入时钟推进，无真实 sleep）。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 通过；stage 构建后
  fixture `mixed`（9 条）与 `nopermission`（2 条）正常。

### 仍未验证

- 真机上最小化窗口显示“已保存的快照”的实际观感（需要真实面板会话）。
- 与上轮相同的人类交互项。

## 补充轮次 54：视图侧图像内存可观测 + 一次偶发测试崩溃的记录

### 真实修改

- 任务书要求“仍被视图、折叠状态或置顶流持有的内存也要另外观测”。内容视图新增
  `cachedThumbnailBytes`（按 `bytesPerRow × height` 求和，防溢出），与服务的
  `cachedCostBytes` 分开报告；fixture 自动退出时一并打印
  `viewThumbnails=`/`viewImageBytes=`。规模回归断言视图侧字节 > 0 且 < 20 MiB。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 245 window-browser pure-logic checks`。
- stage 构建后 fixture 输出：
  `records=9 ... viewThumbnails=0 viewImageBytes=0`（fixture 不加载真实图片，符合预期）、
  `records=20 ... viewThumbnails=0 viewImageBytes=0`。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、`git diff --check` 通过。

### 偶发失败记录（诚实记录，未复现）

- 在“stage 构建 → 多个 fixture → duo 测试 → paper 测试”连跑的那一次，
  `tests/run-paper-tests.sh` 以 `Trace/BPT trap: 5` 退出。
- 随后单独重跑 1 次、在 fixture 之后连跑 2 次、再单独连跑 3 次，全部通过
  （共 6 次通过）；本轮改动的文件都不在该脚本的编译清单内
  （`PaperSurfaceStyle.swift`、`PinnedPreviewPanel.swift` 本轮未改）。
- 结论：按“一次偶发、未能复现”记录；若后续再出现，需要抓取 stderr 的
  precondition 信息定位。

### 仍未验证

- 真实长列表滚动时的视图侧字节峰值（离屏断言为 < 20 MiB）。
- 与上轮相同的人类交互项。

## 补充轮次 55：paper 回归加固 + 选中滚动的完整覆盖

### 真实修改

- paper 回归加固：`PaperSurfaceTests` 在窗口尚未真正上屏时就断言 `visibleRect`，
  紧跟多个 GUI 探针进程之后可能因 WindowServer 尚未提交窗口而假失败（此前记录过
  一次 `Trace/BPT trap: 5`）。现在测试先 `orderFrontRegardless()` 并短暂跑一次
  RunLoop，再断言。
- 选中滚动覆盖所有来源：`WindowBrowserContentView.update` 在选中项发生变化时
  （搜索过滤、窗口关闭后的回退选择）同样把选中项滚入视口；用户自己滚走且选中项
  未变时，刷新不会把视图强行拉回（保留用户滚动位置）。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 247 window-browser pure-logic checks`
  （新增：update 路径的选中项滚入视口；同一选中项下手动滚走不被刷新拉回）。
- `bash tests/run-paper-tests.sh` 单独连跑 3 次、并在“3 个 fixture → duo → paper”
  完整序列连跑 2 轮，均通过，此前的偶发 trap 未再出现。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、`git diff --check`
  通过；stage 构建后 fixture `many` 正常。

### 仍未验证

- 真实鼠标滚轮操作下手动滚走与选中项变化的行为观感（离屏断言覆盖两条规则）。
- 与上轮相同的人类交互项。

## 最终验收快照（当前修订 2abd49b + 未提交改动）

### 交付清单

- 新增源码：`prototype/WindowBrowser/`（17 个文件，约 7,160 行）——
  模型/目录/动作协调器/面板状态机/几何/缩略图服务与策略/镜像槽/目标解析/发现与过滤/
  排版/Dock 观察器/面板与视图/控制器/设置/AppDelegate 适配/fixture/9 个只读探针。
- 接线改动：`App/MenuBarController.swift`（菜单“选择窗口…”）、
  `App/Preferences.swift`（窗口浏览设置页 + 快捷键记录器）、`App/EventTap.swift`
  （可选全局快捷键，默认不注册）、`WindowShade.swift`（控制器接线与折叠等待者）、
  `App/ShadeController.swift` / `App/FoldTransaction.swift`（折叠终态结算）、
  `PinnedPreview.swift`（明确目标置顶 + 镜像租约）、`ScreenCaptureBridge.swift`
  （预览配置、帧计数、镜像层加锁）、`Overlay/PaperSurfaceStyle.swift`（阴影子窗口
  不可成为 key）、`Effects/DuoSettingsWindow.swift`（新设置分页）、`main.swift`
  （fixture 与探针入口）。
- 测试：`tests/WindowBrowserTests.swift`（1,539 行）、
  `tests/run-window-browser-tests.sh`；`tests/PaperSurfaceTests.swift` 增加了
  “先上屏再断言”的稳健性处理。
- 文档：`docs/window-browser.md`（用户向入口/权限/兼容限制）、
  `DEVELOPMENT.md`（开发验收入口与 9 个探针）、本文件（阶段记录与实测证据）。

### 本轮全套验证（全部通过）

```text
bash tests/run-window-browser-tests.sh   PASS: 247 window-browser pure-logic checks
bash prototype/build.sh --check          编译验证通过（仅既有 stopCapture 建议警告）
bash tests/run-duo-tests.sh              4 组通过
bash tests/run-paper-tests.sh            通过
git diff --check                         干净
```

9 个只读探针 + fixture（最新 stage 构建）：

```text
dock       observer teardown complete
hover      icon-hit match=true / non-icon target=cleared / notificationsReliable=false
catalog    apps=11 windows=7 empty=5 failed=0 total=313ms slowestApp=50ms
           mainThreadMaxGap=6ms / resolve identity=0ms geometry=0ms capabilities=0ms
capture    card 461x320 center=(27,148,254) blue=true（遮挡实验）/ selectedLarge 27ms
thumbnail  deliveries=4 captures=2 running=0 cachedBytes=675840
stream     afterMirrorRelease running=true / stopError=none / framesAfterStop 稳定
panel      keyboard key=true searchFocused=true / dock-second unchanged=true key=false
ui         menuItem 启用/置灰/恢复正确
idle       axQueries=0 thumbnailsInFlight=0 thumbnailBytes=0 settingsRestored=true
fixture    records=9 panel=720x560 viewThumbnails=0 viewImageBytes=0
```

### 已验证（真机或离屏证据）

身份代数与去重、目录合并与失败保留、稳定顺序与按身份选择、A→B→A/关闭后回调/PID 复用
丢弃、标注目标动作与防重入、恢复真实终态、明确目标置顶与镜像 owner 租约、单窗截图
（遮挡实验证明不退回整屏裁切）、缩略图服务并发/缓存/失效/快照/内存预算、实时预览启动与
停流（解除镜像不停持久流）、面板非激活语义与键盘焦点、多显示器真实屏幕几何、菜单与设置
入口构建、快捷键保留组合策略、排除清单、空闲零查询、fixture 五场景。

### 未验证（必须由真人在 macOS 会话确认）

1. 新面板触发的真实窗口动作（折叠/展开/置顶/关闭）在真实窗口上的完整端到端结果。
2. 睡眠/锁屏/唤醒、运行中权限撤销与重授、多 Space、Mission Control、全屏。
3. VoiceOver 朗读顺序、排除清单多行输入、快捷键实录与触发、真实滚动内存峰值、
   无响应应用下的动作表现。

（真实鼠标悬停通知原为第 1 项，已在补充轮次 57 用真机探针验证并修复，见下。）

以上未验证项同时保留在本文件各阶段小节中，代码不会把它们标为已完成。

## 补充轮次 57：真实悬停通知验证 + 通知选中滞后缺陷修复

### 真机操作说明

新增 `--window-browser-hover-live-probe`：保存当前指针位置 → 把系统指针移到 Dock 上
第一个应用图标约 1.2 秒 → 再移到分隔符位置 → **原样放回**指针。只悬停，不点击、
不激活任何应用、不打开任何东西；全程约 2 秒。

### 第一次运行暴露的真实缺陷

首次运行得到 `notificationsReliable=true target=com.apple.Safari expected=com.apple.finder
match=false`（第二次 `target=none`）：通知路径确实会被真实悬停触发，但 Dock 上报的
选中子项可能滞后于指针（放大/切换动画期间），此时：

1. 旧实现只按“鼠标必须在选中图标内”拒绝过期目标，然后**清除**；
2. 用户把指针停在图标上不动时不会再有鼠标移动事件，回退命中路径就不会补上正确目标
   —— 面板可能不出现或闪烁。

### 真实修改

- `DockHoverObserver.fallbackHitTestAfterNotification(reason:)`：通知没有可用选中项、
  或选中项被判定过期时，立即用**最后一次指针位置**做一次兜底命中检测（不受 100ms
  节流限制），命中失败才走原有清除逻辑。

### 修复后实测（3/3 一致）

```text
hover-live: icon notificationsReliable=true target=com.apple.finder
            expected=com.apple.finder match=true
            point=(68,1069) expectedFrame=(43,1036 49x65) targetFrame=(43,1036 49x65)
hover-live: non-icon target=cleared
hover-live: pointerRestored=true
```

即：真实悬停触发通知 → 解析出正确应用实例与图标矩形；移到 Dock 上非图标位置
（分隔符）后旧目标被清除；指针已恢复原位。

### 验证

- `bash tests/run-window-browser-tests.sh` → `PASS: 247 window-browser pure-logic checks`；
  `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 通过。

### 仍未验证

- 与真人拖拽/输入同时进行时的悬停表现（探针已尽量缩短指针占用并恢复）。
- 剩余人类交互项：真实窗口动作端到端、睡眠/锁屏/权限、VoiceOver、排除清单、
  快捷键实录、真实滚动内存峰值、无响应应用。

## 补充轮次 56：fixture 支持强制浅色/深色

### 真实修改

- 任务书要求隔离演示“支持浅色、深色”。fixture 新增
  `WINDOWSHADE_BROWSER_FIXTURE_APPEARANCE=dark|light`，在隔离入口里设置
  `NSApp.appearance`，不修改系统外观设置、不影响正常启动；
  `DEVELOPMENT.md` 的环境变量清单已补充该选项。

### 验证

- stage 构建后分别以深色与浅色运行 fixture：两次输出一致
  （`records=9 panel=720x560 canBecomeKey=true ... viewThumbnails=0 viewImageBytes=0`），
  未出现异常。
- `bash prototype/build.sh --check` 通过；`bash tests/run-window-browser-tests.sh`
  → `PASS: 247 window-browser pure-logic checks`。

### 仍未验证

- 浅色/深色的实际观感（需要人眼看截图或运行 fixture；实现与置顶预览面板同一套
  动态系统色与纸面阴影）。
- 与上轮相同的人类交互项。

## 补充轮次 24：交叉核对细分（“像真实窗口”的子集）

### 真实修改

- 目录探针在 `cgLayer0=` 之外增加 `cgWindowLike=`：WindowServer 里大尺寸（>300×200）
  且有标题的 layer-0 窗口数，用来分辨“真实窗口”与辅助/帮助窗口。

### 实测结果与结论

- `com.apple.Safari windows=4 cgLayer0=18 cgWindowLike=3`、
  `com.agiletortoise.Drafts-OSX windows=1 cgLayer0=9 cgWindowLike=1`；
  其余应用三者一致（多为 0 或 1）。
- 结论修正：Safari 的 18 个 layer-0 项里只有 3 个“像真实窗口”，而应用报告的 4 个
  包含 1 个最小化窗口（最小化后几何很小，因此不计入 `cgWindowLike`）。也就是说
  发现路径没有漏掉真实窗口，差异来自无法映射的辅助窗口。
  `docs/window-browser.md` 的兼容限制已按实测数字改写，避免反向夸大问题。
- 性能同轮：`apps=10 total=244ms slowestApp=41ms mainThreadMaxGap=6ms`。

### 仍未验证

- 同一应用在多个 Space 同时有窗口时的 AX/CG 覆盖差异（需要多 Space 会话）。
- 与上轮相同：真实滚动内存峰值、真实置顶会话镜像组合、真实悬停通知、
  真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 18：布局尺寸集中化

### 真实修改

- 落实任务书“所有尺寸集中在布局参数中，不能散落为几十个 magic number”：
  `WindowBrowserLayoutParams` 新增卡片/行/预览栏内部尺寸（`cardPadding`、
  `cardTitleHeight`、`cardStatusHeight`、`cardTitleIconGap`、`rowHorizontalPadding`、
  `rowIconLeading`、`rowTrailingControlsWidth`、`rowControlWidth`、`rowControlHeight`、
  `rowTitleHeight`、`rowStatusHeight`、`selectionPanePadding`、
  `selectionPaneMinimumWidth/MaximumWidth/MinimumContentWidth`），卡片、列表行与
  选中项预览栏的布局全部改为读这些参数，布局结果不变。

### 新增真实运行证据

- `bash tests/run-window-browser-tests.sh` → `PASS: 179 window-browser pure-logic checks`
  （新增：动作按钮保持 ≥28pt 命中区、按钮不越出卡片、卡片图像区不超过配置上限）。
- stage 构建后 fixture 三场景仍正常：`mixed 9 / many 20(list) / nopermission 2`。
- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 全部通过。

### 仍未验证

- 与上轮相同：真实悬停通知、真实滚动补图时序、真人端到端动作、无响应应用、睡眠锁屏。

## 补充轮次 58：真实 AX 上的身份拒绝链验证探针

### 真实修改

- 新增 `prototype/WindowBrowser/WindowBrowserIdentityProbe.swift` 与入口
  `--window-browser-identity-probe`（在 `prototype/main.swift` 注册）。
  探针不写任何窗口状态，只做两件事：
  1. 用生产 `WindowBrowserTargetResolver.enumerate/inspect` 读取自己创建的探针窗口
     和一个其他应用的真实窗口，核对正向解析与全部拒绝分支（换窗口 ID、换 PID、
     从未分配过的窗口 ID）；
  2. 把只记录调用的 `IdentityProbeBackend` 接到生产
     `WindowBrowserActionCoordinator` 上，`validate` 复用生产判定顺序
     （`WindowIdentityAllocator.isCurrent` → `WindowBrowserTargetResolver.enumerate`
     → `inspect`），用来证明被拒绝的提交一次都到不了 `perform`，而允许执行时传给
     `perform` 的 key 与提交的 key 逐字段相同（不会换成别的窗口）。
- 探针只在自身进程里短暂显示一个小窗口（`.floating` + `orderFrontRegardless()`，
  不激活、不抢 key），结束时随进程退出；不移动指针、不捕获用户窗口内容。
- `DEVELOPMENT.md` 的探针清单已补上该入口。

### 实际运行的命令与结果

- 隔离 stage 构建（未替换正在使用的应用）：
  `WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: openkams@gmail.com (G3TN2MBQ2Q)" bash prototype/build.sh --stage`
  → 签名验证通过。
- `.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade --window-browser-identity-probe`
  连续两次运行，均为 `checks=25 failures=0 result=pass`：

```text
identity-probe: ownWindow element=true inspected=true geometryMatch=true canClose=true wrongWindowID=rejected wrongPID=rejected fabricated=rejected
identity-probe: foreignWindow bundle=com.apple.Safari id=1568 wrongWindowID=rejected wrongPID=rejected
identity-probe: coordinator fabricatedKey outcome=targetGone performCalls=0
identity-probe: coordinator liveKey outcome=completed performCalls=1 keyUnchanged=true
identity-probe: closedWindow gone=true enumerate=none allocatorStillCurrent=true
identity-probe: coordinator goneWindow outcome=uncertain(reason: "目标无法确认：无法按完整身份解析窗口") performCalls=0
identity-probe: coordinator staleGeneration outcome=targetGone performCalls=0
identity-probe: coordinator regeneratedKey outcome=uncertain(reason: "目标无法确认：无法按完整身份解析窗口") performCalls=0
identity-probe: checks=25 failures=0 result=pass
```

  其中 `closedWindow gone=true allocatorStillCurrent=true` 是关键：真实窗口已经关闭、
  目录代数还没结算时，`validate` 仍在真实 AX 上重新核对并拒绝，不会凭旧记录继续
  执行。`staleGeneration` 与 `regeneratedKey` 两行覆盖同一数字窗口 ID 复用
  （A→B→A）后旧代数与新代数都必须重新核对、都到不了 `perform`。
- `bash prototype/build.sh --check`（70 个源文件）通过；
  `bash tests/run-window-browser-tests.sh` → `PASS: 247 window-browser pure-logic checks`；
  `bash tests/run-duo-tests.sh`、`bash tests/run-paper-tests.sh`、`git diff --check` 通过。
- 用户正在运行的 WindowShade（pid 3342）全程保持运行，`prototype/WindowShade.app`
  的 Mach-O 未被替换（mtime 仍为 Sep 13 04:59）。

### 一次实现缺陷与结论

- 探针首版写成“先 `WindowBrowserTargetResolver.inspect(element, key:)`（默认选项）
  再要求 `axSize != nil`”，而默认选项按设计不读几何，导致真实的外部窗口被误判成
  “无合适目标”并跳过（输出 `foreignWindow skipped=no-suitable-target`）。改为
  `options: [.geometry]` 后命中 `com.apple.Safari id=1568`。
  结论：这是探针用法错误，生产代码“按用途按需读取几何”的行为正确。

### 仍未验证

- 生产 `WindowBrowserController.performFold/performUnfold/performPinPreview/performClose`
  对**其他应用真实窗口**的写行为仍未在真实会话里端到端跑过：要拿到目录里的记录，
  必须先由 Dock 悬停或键盘面板开启一次面板会话，探针照做就会在用户屏幕上开面板并
  抢焦点，因此没有自动化。现有证据是：身份拒绝链已在真实 AX 上验证；写路径复用既有
  折叠事务（`ShadeController.windowBrowserBeginFold`、`unshadeReturningElement`）
  与既有 AX 按钮投递，并由 `tests/run-duo-tests.sh` 与纯逻辑测试覆盖。
- 其余与上轮相同：睡眠/锁屏/运行中权限撤销、多 Space、Mission Control、全屏、
  VoiceOver 朗读顺序、无响应应用、真实滚动内存峰值、真人悬停与真人端到端动作。

### 下一步的具体文件或符号

- 真人闭环验证：`WindowBrowserController.performFold/performUnfold/performPinPreview/performClose`、
  `WindowBrowserSettings`（Dock/面板/实时预览开关与排除清单）、
  `EventTap.registerWindowBrowserHotKey`、`App/MenuBarController.swift` 的“选择窗口…”。
- 若要把真实写动作也自动化，需要给探针加一条受控入口（例如为指定 pid 建立一次性
  发现会话而不显示面板），这会改动生产代码，需先确认是否接受该测试缝。

## 补充轮次 59：真实安装部署 + 真实入口验证

### 真实修改

- 新增 `prototype/WindowBrowser/WindowBrowserLiveAppProbe.swift` 与入口
  `--window-browser-live-app-probe`（在 `prototype/main.swift` 注册）。
  它瞄准**另一个正在运行的 WindowShade 进程**（正常启动的应用，不是探针自己）：
  点开真实状态栏菜单 → 按“选择窗口…”→ 读面板里的真实窗口条目 → 按 Esc 关闭 →
  用 WindowServer 在屏窗口确认面板消失。除这两次菜单操作与一次 Esc 外不改任何状态。
- `DEVELOPMENT.md` 的探针清单补充该入口，并写明它会短暂占用菜单栏与屏幕。

### 真实部署（用户确认“现在是一个合适的时机”后执行）

- 命令：`cd prototype && WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: openkams@gmail.com (G3TN2MBQ2Q)" bash build.sh`
  （默认路径：`pkill -x WindowShade` → 优化整模块编译 → 原地替换 Mach-O → 同一身份签名）。
- 结果：`prototype/WindowShade.app/Contents/MacOS/WindowShade` 由
  `d41d0a35…`（2,178,752 B，Sep 13 04:59）换成 `a19255ac…`（3,152,592 B，06:47）；
  TeamIdentifier 仍为 `FVGLY6W6S4`，签名身份未变，TCC 授权未重置。
- 重启：`open prototype/WindowShade.app` → pid 3342 → **22802**。
  `/tmp/windowshade.log` 记录 `=== session start pid=22802 ===`、
  `status item visible=true`、`reconcile: timer started`、
  `dock: mineffect=scale verified reason=session-start`；`~/Library/Logs/DiagnosticReports`
  无 WindowShade 崩溃报告。

### 真实入口验证（首次运行，直接命中）

```text
live-app-probe: target pid=22802 bundle=com.windowshade.prototype frontmostBefore=66857
live-app-probe: statusItem role=AXMenuBarItem actions=AXPress
live-app-probe: statusItem axPress=err=-25204; falling back to a real click
live-app-probe: statusItem clicked at=(1201,17)
live-app-probe: statusMenu items=10 titles=铰链角度：0.0° | 当前窗口 | 折叠当前窗口 | 整理卷帘条 | 双击标题栏以折叠 | 置顶当前窗口 | 选择窗口… | 使用说明… | 设置… | 退出 WindowShade
live-app-probe: pointerRestored=true
live-app-probe: panel window title=窗口选择 appWindows=2
live-app-probe: panelLabels=75 cards=8 sample=[ChatGPT，ChatGPT / QQ，QQ / Safari，"闻音识" - Google 搜尋]
live-app-probe: crossCheck matchedTitle=I recreated the 1999 OS Classic Mac System 9 …
```

- 结论：真实状态栏菜单里有“选择窗口…”且可用；点它打开了键盘面板
  （WindowServer 在屏窗口名 `窗口选择`，640×520），面板里 8 张卡片，
  条目文本与外部真实窗口标题逐字对上（交叉核对命中一个 Safari 真实标签页标题）。
  这就是“可从真实菜单进入”的直接证据，不再只依赖本进程构造的菜单对象。

### 本轮发现（影响后续自动化）

1. 状态项**不响应 AXPress**（`AXUIElementPerformAction` 返回 -25204），自动化必须像真人
   一样在状态项位置点一下；探针已加该回退，并在面板出现前把指针原样放回
   （两次运行都打印 `pointerRestored=true`）。
2. 不能用应用 AXWindows 判断面板是否可见：面板关闭只是 orderOut，加上
   `isReleasedWhenClosed = false`，它仍留在 AX 窗口列表里。首次运行的
   “Esc 关闭失败”就是这个误报（随后用 WindowServer 在屏窗口确认面板其实已不在屏幕上）。
   正确判定是 `CGWindowListCopyWindowInfo([.optionOnScreenOnly])` 按窗口名匹配。
3. 同一条判定也不能只看“目标应用有没有大窗口”：用户自己打开着设置窗口时会假阳性。
4. 真人正在同一台机器上操作时（日志里 06:51–06:52 有 Space 切换与鼠标事件），
   第二次运行没有得到可信结论（用户在屏窗口与当前 Space 干扰了判定）。
   交互式探针不适合在真人正在用机时反复运行，本轮因此主动停止复跑。

### 仍未验证

- “按 Esc 关闭面板并把前台应用还回去”这一条，本轮自动化没有得到可信结论
  （首次判定用错、第二次被用户窗口与 Space 干扰）；需要真人按一次 Esc 确认，
  或在机器空闲时用修好的探针复跑。
- 与上轮相同：面板卡片动作对**其他应用真实窗口**的写行为、睡眠/锁屏/运行中权限撤销、
  多 Space、Mission Control、全屏、VoiceOver、无响应应用、真实滚动内存峰值。

### 下一步的具体文件或符号

- 机器空闲时复跑真实入口探针（判定已改为 WindowServer 在屏窗口）：
  `.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade --window-browser-live-app-probe`
- 真人确认 Esc 关闭与焦点归还：`WindowBrowserPanel.cancelOperation` →
  `WindowBrowserController.closePanel(reason: "cancel")` → 键盘面板焦点归还分支。
- 真人确认卡片动作：`WindowBrowserController.performFold/performUnfold/performPinPreview/performClose`。
- 工作区仍未提交（按原约定等你点头）；当前未提交内容见 `git status --short`。

## 补充轮次 60：修复“搜索框与窗口缩略图列表重叠”

### 真实修改

- 用户截图报告：键盘面板里搜索框被缩略图列表压住。定位到
  `WindowBrowserContentView.layout()`：搜索框画在 `footerHeight + 12` 到
  `footerHeight + 38`（34…60），而列表底边算的是 `footerHeight + 30`（52），
  两者重叠 8pt；更靠后加入 subviews 的滚动视图又正好画在搜索框之上，
  于是看起来是“列表盖住搜索框”。系统字号变大、底部状态行变高时错位还会加剧。
- 修复：搜索框位置与列表底边改为从同一份几何推出，新增布局参数
  `searchFieldHeight = 26`、`searchFieldBottomGap = 12`、`listTopGap = 6`，
  列表底边 = 搜索框顶边 + `listTopGap`。Dock 面板（没有搜索框）路径保持原样。
- 新增诊断属性 `WindowBrowserContentView.layoutFrameSummary`（搜索框与列表 frame），
  fixture 输出补充 `searchTop`、`listBottom`、`overlap` 三个字段，便于以后一眼看出回归。

### 新增与运行的测试

- `bash tests/run-window-browser-tests.sh` → `PASS: 266 window-browser pure-logic checks`
  （新增 19 项布局回归）：
  - 两种面板尺寸（640×520、460×340）× 两种风格（缩略图/列表）：搜索框与列表不相交、
    列表底边不低于搜索框顶边、搜索框不低于底部状态行；
  - 字号变大（`footerHeight + 10`、`headerHeight + 8`）后仍不相交；
  - Dock 面板搜索框 frame 为零、列表仍在状态行之上。
  断言方向先写反过一次（容器是左下原点，“下方”应为更小的 y），修正后全部通过。
- 真实 AppKit（隔离 stage 构建 + fixture）：

```text
window-browser-fixture: records=10 panel=720x560 style=grid … searchTop=60 listBottom=66 overlap=false
window-browser-fixture: records=20 panel=720x560 style=list … searchTop=60 listBottom=66 overlap=false
```

- `bash prototype/build.sh --check`、`bash tests/run-duo-tests.sh`、
  `bash tests/run-paper-tests.sh`、`git diff --check` 通过。

### 真实部署

- `bash prototype/build.sh`（同一签名身份）→ `prototype/WindowShade.app` 的 Mach-O
  `a19255ac…` → `d02b4a7d…`；`open prototype/WindowShade.app` 后 pid 22802 → 35907，
  `/tmp/windowshade.log` 记录 `=== session start pid=35907 ===`、`dock: mineffect=scale`
  正常，无崩溃。

### 仍未验证

- 视觉观感：`screencapture -l` 因调用方缺少屏幕录制授权失败，我没有为了截图去改动
  你的隐私授权设置，因此没有留下修复后的截图；数值证据（`overlap=false`、
  列表底边高于搜索框顶边 6pt）已足够，最终观感请你在面板里看一眼。
- 其余与上轮相同：卡片动作对其他应用真实窗口的写行为、Esc 关闭与焦点归还、
  睡眠/锁屏/权限撤销、多 Space、Mission Control、全屏、VoiceOver、无响应应用。

### 下一步的具体文件或符号

- 若觉得搜索框与列表的间距不合适，只调 `WindowBrowserLayoutParams.standard` 的
  `searchFieldBottomGap` / `listTopGap` 两个值即可，`WindowBrowserContentView.layout()`
  不需要再改。

## 补充轮次 61：修复“点列表仍是缩略图网格”+ paper 回归的环境依赖

### 真实修改

- 用户截图报告：分段控件已经高亮“列表”，内容却还是缩略图网格。定位到
  `WindowBrowserContentView.styleChanged` 只改了 `style` 变量并回调控制器，
  而控制器的 `onStyleChanged` 只把风格记进 `style` / `sessionAutoStyle`，
  两边都没有重排，所以要点列表后**再等一次别的刷新**才会变。
- 修复两处：
  - `WindowBrowserContentView.styleChanged`：改完样式立刻 `rebuildRows()` +
    `needsLayout = true`，视图自己当场换布局（真实 AppKit 已验证）；
  - `WindowBrowserController` 的 `onStyleChanged`：记下风格后调用 `refreshPanel()`，
    让选中项预览栏、缩略图视口请求与实时画面挂载点跟着新布局对齐。
- 新增诊断属性 `WindowBrowserContentView.renderedLayout`（当前渲染风格 + 行数/卡片数），
  fixture 增加 `WINDOWSHADE_BROWSER_FIXTURE_STYLE=list|grid`，会像用户一样点一次
  分段控件并打印 `clickedStyle / renderedStyle / renderedRows / renderedCards`；
  `DEVELOPMENT.md` 已补该环境变量。

### 新增与运行的测试

- `bash tests/run-window-browser-tests.sh` → `PASS: 272 window-browser pure-logic checks`
  （新增 6 项）：点击“列表”后 `renderedLayout` 立即变成 list、行数 = 窗口数、卡片数 = 0、
  控制器收到 `.list` 回调、列表模式下选中项预览栏出现；再点回“缩略图”立刻恢复卡片。
- 真实 AppKit（stage 构建 + fixture，走的是分段控件的真实 action）：

```text
… style=grid clickedStyle=list renderedStyle=list renderedRows=10 renderedCards=0 …
… style=list clickedStyle=grid renderedStyle=grid renderedRows=0 renderedCards=20 …
```

- 顺带修好一个此前记为“偶发”的 paper 回归失败：`enter did not reveal title`
  （`Trace/BPT trap: 5`）。这次它变成必现，于是查清了根因：**排查时屏幕已经锁定**
  （`CGSessionCopyCurrentDictionary` 实测 `CGSSessionScreenIsLocked = 1`，屏幕上出现了
  Display Shield），锁屏期间窗口不参与合成（实测 `occlusionState` 不含 `.visible`），
  材质视图不会自己变成 layer-backed，
  **没有 layer 时第一次 alpha 动画会被 AppKit 丢掉**，alpha 一直停在 0。
  对照实验：普通 layer-backed 视图动画正常、`withinWindow` 正常、显式
  `wantsLayer = true` 后 `behindWindow` 也正常。修的是测试而不是产品：
  `tests/PaperSurfaceTests.swift` 里显式开启 layer，混合模式仍保留生产用的
  `behindWindow`，断言覆盖的仍是 `mouseEntered → setTitleVisible` 这条真实路径；
  连续 3 次 `bash tests/run-paper-tests.sh` 全部通过。
- 由此得到的经验：**锁屏/无合成状态下不要相信与动画、可见性、截图有关的结论**，
  这类回归要么在解锁状态下跑，要么像上面这样把对合成器的依赖显式去掉。

### 真实部署

- `bash prototype/build.sh` + `open prototype/WindowShade.app`：
  Mach-O `d02b4a7d…` → `4e9ea1a2…`，`=== session start pid=38329 ===`（07:06:51）。
- 排查 paper 回归时临时停过一次应用（约 2 分钟，用于排除“WindowShade 在跑”这个变量，
  结论是无关），随后重新启动：pid 40843，`=== session start ===`（07:09:38），
  `dock: mineffect=scale verified`，无崩溃。

### 仍未验证

- 列表/缩略图切换后的目视效果与滚动手感需要真人看一眼（数值上已确认行/卡片数量与
  预览栏状态正确）。
- 其余与上轮相同：卡片动作对其他应用真实窗口的写行为、Esc 关闭与焦点归还、
  睡眠/锁屏/权限撤销、多 Space、Mission Control、全屏、VoiceOver、无响应应用。

### 下一步的具体文件或符号

- 若风格切换后仍看到旧布局，先看 `renderedLayout` 与 fixture 的
  `clickedStyle/renderedRows/renderedCards`，再查 `renderPanel()` 里
  `contentView.update(..., style: effectiveStyle)` 的 `effectiveStyle` 取值。
