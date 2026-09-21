# WindowShade 1.0.14 复检 + 细化设计稿：交接与提示词

本文给更高智能的模型（Claude 等）使用，委托两件事：**复检**已发布的 1.0.14，并**产出
一份可直接落地的细化设计稿**。**§0 是可以直接粘贴的提示词**，§1 起是交接材料：需求全量
清单（含来源与状态）、当前实现与证据、已知缺口、冲突消解记录、复检命令；**§7 是设计稿
的验收口径与可引用的现状参数**。

---

## 0. 提示词（可直接粘贴；复检 + 细化设计稿）

> 你是资深 macOS/AppKit 工程师、HIG 评审兼界面设计师。请对
> `/Users/aaron/Documents/WindowShade` 当前 `main`（`4a0eca1`）上已发布的 WindowShade
> 1.0.14（tag `v1.0.14` → `480a7fd`）做**两件事**：
>
> **任务一 · 复检**：找出真实缺陷、HIG 违背、自相矛盾与证据不足，不重写功能。
> **任务二 · 细化设计稿**：在复检结论的基础上，产出一份可直接落地的设计规格
> （写明分层、材质、尺寸、间距、圆角、状态、交互、时序、可访问性与回退，
> 并给出每条数值落在哪个文件/常量、哪些属系统提供不可自定）。设计稿的验收口径与
> 可引用的现状参数见本文 **§7**。
>
> 先按顺序读：`AGENTS.md`、`DEVELOPMENT.md`、`docs/review-handoff.md`（本文，§1–§6 是
> 需求与现状）、`docs/system-integration-polish.md`、`docs/design-v1.md`、
> `docs/window-browser-polish.md`、`docs/window-browser-performance.md`、
> `docs/window-browser-visual-qa.md`、`docs/window-browser-progress.md`、
> `docs/releases/v1.0.14.md`。再读实现：`prototype/WindowBrowser/`（尤其
> `WindowBrowserMaterial.swift`、`WindowBrowserViews.swift`、`WindowBrowserController.swift`、
> `WindowBrowserGeometry.swift`、`WindowThumbnailService.swift`、`WindowBrowserPanel.swift`）、
> `prototype/Overlay/SystemAppearance.swift`、`prototype/WindowShade.swift`。
>
> 复检重点，按顺序：
> 1. **HIG / Liquid Glass**：玻璃是否只出现在功能层、是否只有一层、变体（regular/clear）
>    是否用对、是否上色、`contentView` 是否按 Apple 的说明使用、回退（减少透明度、提高
>    对比度、减少动态效果）是否完整。**判断必须以 Apple 官方文档为准**
>    （<https://developer.apple.com/design/human-interface-guidelines/materials>、
>    <https://developer.apple.com/documentation/appkit/nsglasseffectview>、
>    <https://developer.apple.com/documentation/appkit/nsglasseffectcontainerview>、
>    <https://developer.apple.com/videos/play/wwdc2025/310/>、
>    <https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass>），
>    以及本机 SDK（`xcrun --show-sdk-path --sdk macosx` 下的 AppKit 头文件）。
>    **不要自创对 Liquid Glass 的理解**：HIG 没写的效果不要加，也不要拿模糊/渐变/私有
>    图层冒充玻璃。
> 2. **正确性与所有权**：截图任务记账、订阅终态、视图与闭包持有、实时预览唯一挂载点、
>    旧任务只清理自己的资源（见 §2.B/§2.D 的清单）。
> 3. **与任务书的偏差**：任务书《WindowShade：窗口浏览效率、原生界面与窗口管理成熟化
>    任务书》的逐条要求在 §2 列出并标注状态，请**逐条核对状态是否属实**，尤其 §3「已知
>    缺口」里我自己列出的项。
> 4. **证据可信度**：哪些结论只有离屏截图、哪些只有纯逻辑断言、哪些从未实机验证（§4）。
> 5. **文档与实现是否一致**（包括数字：面板尺寸、圆角、性能、测试条数）。
>
> 硬约束：不要回退到研究基线 `05e5472`；不要动 `WindowCatalog`、完整 `WindowKey`、事务式
> 隐藏/恢复与恢复验证、`WindowMirrorSlot` 的镜像租约；不要用另一套简化的隐藏/恢复系统；
> 不要提交、推送、打 tag、发版、部署或替换你机器上正在运行的 WindowShade（除非用户明确
> 要求）；日常构建只用 `cd prototype && ./build.sh --stage`（隔离构建，不动已安装应用）。
>
> 输出格式（中文，先结论后证据；任务一与任务二分开成节）：
>
> **任务一 · 复检**
> 1) 结论摘要：整体是否可以发布 / 需要修什么；
> 2) 问题清单：每条给 **严重度（P0/P1/P2）+ 文件:行号 + 现象 + 依据（HIG 原文或代码路径）
>    + 建议改法 + 复现/验证命令**；
> 3) 需求核对表：§2 里你认为状态标错的行；
> 4) 我未验证的项：你认为必须实机验证才能下结论的；
> 5) 你**没有**做的验证（诚实标注），不要用推测冒充验证。
>
> **任务二 · 细化设计稿**（建议新建 `docs/design-proposal-<你的名字>.md`，按 §7 的目录组织）
> 1) 规格正文：分层 / 材质 / 尺寸 / 间距 / 圆角 / 排版 / 状态 / 交互 / 时序 / 可访问性 / 回退；
> 2) 参数表：每个数值给“当前值 / 建议值 / 依据 / 落点（文件:常量）”；
> 3) 状态矩阵：卡片、列表行、操作条、搜索、页脚、详情、大图预览在
>    默认/悬停/选中/按下/禁用/忙碌/失败下的规格；
> 4) 线框或示意图：至少给出 Dock 面板（单窗口、三窗口）、键盘面板（列表、搜索）、
>    排布预览四张，标注尺寸；可用 SVG/HTML 或 ASCII 线框，不必做实机截图；
> 5) 与现状的差异清单：保留 / 修改 / 新增，各自影响面、需要更新的断言与归档截图；
> 6) 明确不做：与 §7.4 的“禁止项”一致。
>
---

## 1. 当前状态（事实）

| 项目 | 值 |
| --- | --- |
| 仓库 / 分支 | `/Users/aaron/Documents/WindowShade`，`main` |
| HEAD | `868d215`（`ca3f295` 面板贴合内容 → `ac648cf` 液态玻璃单层 → `480a7fd` README → `868d215` 重发记录） |
| 发布 | tag `v1.0.14` → `480a7fd`；附件 `WindowShade-v1.0.14.zip`（3,715,311 字节，sha256 `ed82d3a6d3f7f3fc28c1a5e09b0754f03a86f6b3d9e68353656479dbdfcd160e`） |
| 本机运行 | `prototype/WindowShade.app`，bundle 1.0.14 / build 14，pid 20707，签名 `Apple Development: openkams@gmail.com (G3TN2MBQ2Q)`，TeamIdentifier `FVGLY6W6S4`（复核用 `codesign -dv --verbose=2 prototype/WindowShade.app`） |
| 工作区 | 干净（`git status --short` 为空） |
| 基线 | 研究基线 `05e5472`，**只用于对照，不回退** |
| 构建环境 | macOS 27.0（26A428）、Xcode 26.6、macOS SDK 26.5、arm64、2x |
| 站点 | `site/` 文案与 1.0.14 不冲突（不写死版本号，下载按钮指向 latest），本轮未改动、未部署 |

已验证的数字（本文写作时最新一轮）：窗口浏览 **608 项断言**通过；`tests/run-paper-tests.sh`、
`tests/run-duo-tests.sh` 通过；`scripts/check-settings-appearance.sh` 五页通过（侧栏 alpha 1.000）；
`scripts/check-standard-menu.sh` 通过；`--window-browser-shots` 的 `classic-strip-palette PASS`；
`--window-browser-idle-probe`/`hover-probe`/`thumbnail-probe` 干净；性能对照见
`docs/window-browser-performance.md`（120 窗口冷启动 271.8/342.8 → 24.2/30.4 ms，暖刷新
p95 0.95–2.82 ms，预算 4 ms）。

---

## 2. 需求全量清单（来源 + 状态）

状态含义：✅ 已实现且有自动化/截图证据；🟡 已实现但证据有限或需复检；❌ 未实现/未验证；
🔒 约束（不是功能，核对是否被破坏）。

### A. 交付范围、开工规则与禁止事项（任务书 §1/§16/§23，用户追加）

| # | 要求 | 状态 |
| --- | --- | --- |
| A1 | 读 `AGENTS.md`/`DEVELOPMENT.md`，检查分支、HEAD、未提交修改；不因基线提交回退更新的工作区 | ✅（本批次全程在 HEAD 之上推进） |
| A2 | 只用本仓库实现、任务书、Apple 官方文档、本机 SDK 与本机观察；不引入第三方依赖、不抄同类产品源码/文案/图标 | ✅（无新依赖；git 历史可查） |
| A3 | 交付四项：截图调度/所有权/实时预览修复、真实 AppKit 面板视觉与交互改版（Dock + 键盘入口）、真正的系统玻璃路径 + 完整回退、在前三项之后加排布与撤销 | ✅（见 B–K） |
| A4 | 不动系统 Dock、不接管 Command-Tab、不新增屏幕顶部常驻装饰、不加 AI 配置/媒体播放器/日历/小组件市场 | 🔒✅ |
| A5 | 保持 Swift/AppKit 主体与 macOS 14 最低目标；不迁移网页容器；不重写整个 AppDelegate | 🔒✅（Info.plist `LSMinimumSystemVersion 14.0`） |
| A6 | 保留现有卷帘、固定预览、合盖效果、专注排布、异常恢复与权限规则 | 🔒✅（`tests/run-duo-tests.sh` 覆盖） |
| A7 | 不擅自提交/推送/发版/部署/替换已安装应用/改签名身份/停止用户程序 | 🔒→ 见 §5 冲突消解：用户在 2026-09-18 明确「时机成熟」「同一版本重新发布」后，才执行提交/推送/tag/Release/本机替换 |
| A8 | 排布优先左右半、居中与撤销，不用未接线菜单冒充完成 | ✅ |
| A9 | 工作区分组/跨重启恢复只留接口，不先建复杂插件平台；未实现的能力不许写进发布说明 | ✅（发布说明未宣称工作区/跨重启） |

### B. 截图调度、订阅、图像与视图所有权（任务书 §4/§5，T01–T20）

| # | 要求 | 状态 |
| --- | --- | --- |
| B1 | 区分逻辑请求、运行任务、消费者订阅、完成缓存；不可复用 `JobID`；`queued/running/finished` + 失效代数 | ✅ |
| B2 | 只有一个 `drainQueue()` 能把任务变为 running；立即启动也走同一入口 | ✅ |
| B3 | 持有 `runningJobs` 强引用直到物理完成；缓存失效不删除结算所需任务对象 | ✅ |
| B4 | 完成时按 JobID 结算一次；重复完成/重入/重复取消不二次减计数；过期任务仍结算只是不发布 | ✅ |
| B5 | 不用把 `runningCount` 清零绕过泄漏；活动数量从 `runningJobs` 派生 | ✅ |
| B6 | 后端契约：已开始的物理任务必须回传终态；不回调时停止投放并给出可理解失败 | ✅ |
| B7 | 订阅不得自我持有（`cancelAction` 不持有 subscription）；终态清空回调 | ✅ |
| B8 | 控制器维护需求集合，不把「字典里还有 subscription」当作仍在跑 | ✅ |
| B9 | 独立缩略图缓存（不动折叠截图缓存用途）；24 MiB 起点；先合法缓存后刷新 | ✅ |
| B10 | 失败保留合法旧图并标记快照；权限撤销/排除应用/身份失效立即清除 | ✅ |
| B11 | 请求像素数由可见区域 × 目标缩放率推导并向档位归并；选中才升档 | ✅ |
| B12 | 源窗口逻辑尺寸 >4096 不自动拒绝小缩略图；分别校验源几何与输出分配（防溢出/负值/超大分配） | ✅ |
| B13 | 不新增整屏截图裁切回退；不为取图展开/激活源窗口 | ✅ |
| B14 | 网格用 `NSCollectionView` 复用、列表用 view-based `NSTableView`；ID 差异更新 | ✅ |
| B15 | `prepareForReuse` 清理图片/contents/身份/回调/tooltip/可访问性动作/旧订阅/实时挂载/选择外观 | ✅ |
| B16 | 出视口释放重图（可见 + 少量预取 + 选中详情）；复用池空壳可留、截图不留 | ✅ |
| B17 | 三组独立诊断（服务缓存字节、视图图像引用、运行流与图层数）；不把引用和冒充物理分配 | ✅ |
| B18 | weak 断言验证单元/面板/实时视图释放；100 次开关 + 120 条滚动后对象数不线性增长 | ✅ |
| B19 | 右键闭包不保活卡片/行；不机械给所有闭包加 `[weak self]` | ✅ |

### C. Dock 检测与目录刷新（任务书 §6/§7.1，T21–T34）

| # | 要求 | 状态 |
| --- | --- | --- |
| C1 | 候选矩形同时限定 x/y，使用各屏全局 frame（含负坐标、上下排列） | ✅ |
| C2 | 只对真正包含鼠标的屏幕判断边缘；Dock 区域按实际矩形，不合成大框 | ✅ |
| C3 | 自动隐藏 Dock 的预探测只在真实边缘带；离开边缘即不再发 AX 请求 | ✅ |
| C4 | 所有入口共用排队器：一个在途 + 一个最新待处理；后来的位置覆盖旧位置 | ✅ |
| C5 | 每次检测记录观察器代数/PointerRequestID/拓扑版本，回主线程核对并复查命中区域 | ✅ |
| C6 | 0.1 s 只是回退节流起点；同步 AX 放有界后台队列；不在事件 tap 里做同步 AX/枚举 | ✅ |
| C7 | Dock 重启撤销旧观察器，旧结果不覆盖新实例 | ✅ |
| C8 | 拆开身份与锚点：换应用开新会话；同应用图标矩形变化只更新锚点 | ✅ |
| C9 | 拓扑变化关闭临时面板，下次交互重算 | ✅ |
| C10 | 图标到面板的有限走廊过渡区，不闪退也不永久停留 | ✅ |
| C11 | 元数据：每应用一个在途槽 + 最新需求；旧任务结束必须推进新需求 | ✅ |
| C12 | stop/start 后旧回调不能删新任务；槽内有独立 JobID/实例代数/上下文 | ✅ |
| C13 | UI 刷新按变更合并（一个 run-loop/短窗口）提交一份快照，不全量重排重拍 | ✅ |
| C14 | 诊断计数线程安全，区分逻辑发现次数与真实 AX 调用 | ✅ |

### D. 实时预览与租约（任务书 §7.2，T37–T45）

| # | 要求 | 状态 |
| --- | --- | --- |
| D1 | 明确挂载目标（`card(WindowKey)` / `selectionDetail(WindowKey)`），同一 NSView 只有一个可见父视图 | ✅ |
| D2 | 父视图与租约未变则保留，禁止 metadata 更新 remove/add | ✅ |
| D3 | 样式切换只迁移视图，不新开流；列表详情隐藏时不挂视频 | ✅ |
| D4 | 借用既有固定预览，不停止用户固定预览；普通实时预览最多新增一路，默认关闭 | ✅ |
| D5 | 每个分支检查租约身份与 SessionID；旧任务只释放自己的资源 | ✅ |
| D6 | 失败按窗口/会话/原因退避，本会话最多自动重试两次；权限拒绝/源消失直接停 | ✅ |
| D7 | 绘制/错误提示不触发无限重试 | ✅ |
| D8 | 复用可共享内容缓存，按窗口 ID 请求；不在每次选择/布局/重绘枚举 `SCShareableContent` | ✅ |
| D9 | 实时约 8–12 fps 调优起点，按显示尺寸配置输出；保留采样帧显示层 | 🟡（默认关闭，未做长时间实机功耗测量） |
| D10 | 无有效首帧时继续显示静态图；结束回到最后合法快照；不用全黑像素统计判定无效 | ✅ |

### E. 统一布局与尺寸（任务书 §8，T46–T48）

| # | 要求 | 状态 |
| --- | --- | --- |
| E1 | `WindowBrowserGeometry` 返回完整布局结果（面板/内容/模式/列数/单元/详情/滚动范围/锚点/过渡区），所有消费者共用 | ✅ |
| E2 | `desiredSize` 只表达理想尺寸，不是 520×460 强制下限；列表宽度不占满屏幕 | ✅ |
| E3 | 单窗口 Dock 面板自然宽度约 300–336 pt、无理由不超过约 320 pt 高 | ✅（实测 312×236 pt；有状态 312×253） |
| E4 | 两窗口两列约 600–640 pt；3–6 窗口最多三列、宽度受上限约束、放不下滚动或切列表 | ✅ |
| E5 | 左右 Dock 用纵向列表或 1–2 列，不挡工作区 | ✅（列数上限 2） |
| E6 | 键盘面板约 800×560，受安全区约束 | ✅ |
| E7 | 紧凑列表行高约 48–56 pt | ✅（52 pt） |
| E8 | 普通卡片理想宽约 288 pt，图片按比例完整展示 | ✅ |
| E9 | 大字号/窄屏/异常纵横比优先可读性，再减列数/隐藏详情/滚动 | ✅ |
| E10 | 冷启动可先小面板显示加载；首次完整数据允许一次平顺尺寸调整；缩略图陆续到达不改尺寸 | ✅ |
| E11 | 同一会话显式选择网格/列表不被后台数量覆盖；自动判定不能用首条结果永久误判 | ✅ |

### F. 视觉规则（任务书 §9/§10）

| # | 要求 | 状态 |
| --- | --- | --- |
| F1 | 保留卷起后仍占原位、原窗口辨识、展开动作与空间关系；Classic 只体现在薄标题条/细线/纸面边缘 | ✅ |
| F2 | 不用全界面灰块、像素字体、厚黑边、emoji、假交通灯、过量凹凸框表达怀旧 | ✅ |
| F3 | 三层结构：容器（阴影+玻璃）→ 控制区 → 内容区（截图与标题，不叠模糊折射） | 🟡 见 §3-G1（玻璃 contentView） |
| F4 | 纸面靠色彩层次/留白/细边表达，不铺纹理图；玻璃与纸面共用同一布局与组件 | ✅ |
| F5 | Classic 标题条细横线不穿文字；非激活降对比；选中才强调 | ✅ |
| F6 | 系统字体与中文回退；13 pt 主标题、14–15 pt 应用名、11–12 pt 次级 | ✅ |
| F7 | 卡片标题最多两行；列表单行截断 + tooltip + 可访问性标签 | ✅ |
| F8 | 搜索框放键盘面板顶部；Dock 面板不常驻空搜索框 | ✅ |
| F9 | 不打包来源不明的经典字体；SF Symbols 走系统 API | ✅ |
| F10 | 4/8/12/16/24 间距序列；容器内边距 12–16；卡片间距约 12 | ✅ |
| F11 | 圆角：面板约 16 / 卡片 10–12 / 图片约 8 作为**起点**，嵌套按实际间距协调 | ✅→ 后续按用户要求与实测改为 13/12/6 + 同心 4（见 §5 冲突 5） |
| F12 | 只保留必要边界；细线按 backing scale 对齐；1x/2x 都检查 | 🟡（2x 有截图；1x 未实机） |
| F13 | 阴影只服务浮动层级；审计 `PaperSurfaceStyle.installShadow` 与原生阴影分工，不重复阴影、不给静态卡片建 NSWindow | ✅ |
| F14 | 语义颜色 + `viewDidChangeEffectiveAppearance` 集中刷新；不在 init 缓存 CGColor | ✅ |
| F15 | 状态由逻辑状态 + 画面可用性生成；折叠且屏外是正常状态不用警告色 | ✅ |
| F16 | 状态表（普通/已折叠/固定/暂停/最小化/无画面/进行中/错误）按 §9.4 表达 | ✅ |
| F17 | 系统符号统一 point size/weight/基线；缺失时用原创矢量；不用 Unicode 几何字符当图标 | ✅ |
| F18 | Dock 卡片默认只显示缩略图/标题/必要状态；应用名与图标在头部一次 | ✅ |
| F19 | 取消常驻长文字按钮；保留稳定“更多”入口；悬停/选中显示紧凑操作条且不挤动标题 | ✅ |
| F20 | 操作条单色符号 + tooltip + 可访问性名称 + 上下文菜单；首次可一次性说明 | ✅ |
| F21 | 点卡片激活真实窗口（折叠先恢复验证），成功后关闭面板；管理动作留在面板并局部更新 | ✅ |
| F22 | 关闭真实窗口放上下文菜单/低 prominence；不混淆关闭卡片/预览/窗口 | ✅ |
| F23 | 列表以图标+标题+状态为主，不塞固定宽文字按钮；详情只在空间足够时出现且对应同一 WindowKey | ✅ |
| F24 | 网格/列表/菜单/可访问性动作共用同一份能力结果（enabled/原因/危险/执行中） | ✅ |
| F25 | 区分悬停/键盘选择/按下/激活；拖出取消；悬停不改变源窗口 | ✅ |
| F26 | 方向键按真实列数；Home/End/PageUp/PageDown；Tab 焦点；Return 激活；Escape 取消 | ✅ |
| F27 | 输入法 marked text 优先；搜索框文本操作不被抢；键盘移动后静止指针不抢选择 | ✅ |
| F28 | Space 只读大图预览（不激活/不展开/不移动），Escape 分层（大图 → 排布预览 → 关面板） | ✅ |

### G. Liquid Glass 与回退（任务书 §11，T51–T52，用户追加强调）

| # | 要求 | 状态 |
| --- | --- | --- |
| G1 | 用 `NSGlassEffectView`，**把实际控制内容设为它的 `contentView`**，不要当成与文字并列的透明背景兄弟视图 | ✅（2026-09-19 落实：面板根视图是唯一玻璃，界面在其 contentView 内；见 `docs/design-proposal-claude.md`） |
| G2 | 邻近同组玻璃用 `NSGlassEffectContainerView` 协调；少量完整控制组，不为每张卡片/按钮单独加效果 | ✅（现在只有一层玻璃，容器不创建；代码保留并在两个以上形状时才启用） |
| G3 | 截图与长列表保持普通内容；不在截图上叠玻璃、不自行采样背景色 | ✅ |
| G4 | 编辑与运行条件分别检查：SDK 有 API 才编译玻璃分支，macOS 26+ 才运行；旧 SDK 明确只包含回退 | ✅（`WINDOWSHADE_SDK_HAS_GLASS` + `#available(macOS 26.0, *)`） |
| G5 | 禁止私有 CALayer filter、未公开 backdrop 类、KVC、动态 selector、整屏截图伪折射 | 🔒✅ |
| G6 | 外观设置只给“跟随系统/纸面”等少量明确选择；不可用系统不显示假玻璃开关 | ✅ |
| G7 | 跟随系统：有玻璃且辅助功能允许 → 玻璃；旧系统 → `NSVisualEffectView`/纸面；减少透明度 → 不透明语义底 | ✅ |
| G8 | 旧系统模糊不得标成 Liquid Glass | ✅（文案与文档均如此写） |
| G9 | 减少动态效果移除平移/缩放/弹性；提高对比度增加边界与选中指示且不只靠颜色 | ✅ |
| G10 | 切换外观不关闭固定预览、不取消恢复、不重新枚举所有窗口；按 AppearanceRevision 局部更新 | ✅ |
| G11（用户追加） | 要有液态玻璃的感觉、不要只是毛玻璃；符合 macOS 27 的 HIG 与通用设计准则 | 🟡 已按 HIG 改成“单层玻璃 + 内容层标准材质 + regular 变体 + 不上色”，但 G1 未落实，观感受此影响 |
| G12（用户强调） | 不能玻璃叠玻璃；不能自创对 Liquid Glass 的理解 | ✅（控制层那层玻璃已删除；`clear` + 自造薄纱方案已按 HIG 删除） |

### H. 动画、手感与刷新率（任务书 §12）

| # | 要求 | 状态 |
| --- | --- | --- |
| H1 | 面板出现约 140–180 ms、消失 100–120 ms、选择强调 80–120 ms、首图替换约 80 ms；参数集中；不锁输入 | ✅（实现 160/110/100/80 ms；出现时长在任务书区间内） |
| H2 | 首次 Dock 悬停保留约 200–250 ms 意图延迟；已打开后横向切换不重付完整延迟 | ✅（`showDelay 0.25`） |
| H3 | 高频动画走 AppKit/Core Animation；静止时不跑自定义显示循环 | ✅ |
| H4 | 60/120 Hz 分别检查；截图帧率与屏幕刷新率分离 | 🟡（仅 60 Hz 实机；120 Hz 未验证） |
| H5 | Classic 折叠动画保留既有实现；默认悬停不发声 | ✅ |

### I. 原生行为与可访问性（任务书 §13，T53–T57）

| # | 要求 | 状态 |
| --- | --- | --- |
| I1 | Dock 悬停面板不获得焦点、不激活 app、不改源窗口 z-order；键盘面板由用户明确打开后获得焦点 | ✅ |
| I2 | 键盘面板延迟激活重试带打开请求代数，用户切走后不抢回焦点 | ✅ |
| I3 | 取消键盘面板只在仍拥有焦点时归还；成功选择后焦点留在目标 | ✅ |
| I4 | VoiceOver 读出应用名/标题/状态/选择/禁用原因/操作结果；装饰图不入可访问性树；不每次刷新播报列表 | ✅ |
| I5 | 右键菜单/按钮/自定义动作映射到同一动作模型；键盘可达全部操作 | ✅ |
| I6 | 中英文、长路径、无标题、同名窗口可区分；不用标题匹配决定操作目标 | ✅ |
| I7 | 权限提示走现有页面；悬停不弹授权框；未授权不重复通知；录屏撤销清除该权限下的画面，仅需辅助功能的窗口选择仍可用 | ✅ |

### J. 设置与首次体验（任务书 §14）

| # | 要求 | 状态 |
| --- | --- | --- |
| J1 | 窗口浏览入口/外观/预览/快捷键/排除应用分组清楚，不都塞进“高级” | ✅ |
| J2 | 排除应用用应用选择器（图标+名称），不要求手填 bundle ID | ✅ |
| J3 | 诊断参数/并发数/AX 超时/缓存预算留在开发诊断，不塞进普通设置 | ✅ |
| J4 | 保留现有 UserDefaults 键与用户选择；新增配置做版本化迁移；按影响范围失效 | ✅ |
| J5 | 首次打开说明入口 + 明显标为示例的模拟记录预览；取消后不再弹 | ✅ |
| J6 | 设置预览复用真实生产 AppKit 组件，不做“网页图 + 另一套实现” | ✅ |

### K. 排布与撤销（任务书 §15，T58–T59）

| # | 要求 | 状态 |
| --- | --- | --- |
| K1 | 复用既有 `ArrangeController`/`FocusSession`/几何辅助，不复制第二套定位系统 | ✅ |
| K2 | 左半/右半/四角/居中/填满工作区/移到另一显示器 + 撤销最近一次本工具排布 | ✅ |
| K3 | 填满工作区 ≠ 系统全屏；不自动进全屏、不搬 Space | ✅ |
| K4 | `WindowPlacementPlan` 纯数据（目标 key/显示器/旧 frame/目标 frame/原因/能力） | ✅ |
| K5 | 预览只画轮廓不移动窗口；用户确认后才执行 | ✅ |
| K6 | 步骤：重验证身份 → 检查能力/恢复中/全屏 → 读原 frame → 计算 → 执行 → 验证 → 登记撤销 | ✅ |
| K7 | 接受系统合理结果并说明；不无限强制重试 | ✅ |
| K8 | 折叠窗口先走展开验证；Quick Look 新身份不接到猜测的新窗口 | ✅ |
| K9 | 撤销只针对本工具记录，带完整会话身份与实际前后 frame；用户手动移动后拒绝或提示 | ✅ |
| K10 | 多显示器用明确选择与受约束归一化位置；处理分辨率/缩放/拔出/菜单栏与 Dock 占用 | ✅ |
| K11 | 动作同时提供上下文菜单与可配置快捷键入口 | ✅ |

### L. 测试、验收与效率纪律（任务书 §17–§20，T01–T60）

| # | 要求 | 状态 |
| --- | --- | --- |
| L1 | 复用现有测试框架与可推进时钟；后端替身可控完成顺序/失败/重复回调/取消失效/永不返回 | ✅ |
| L2 | 至少覆盖 T01–T60 的断言集合（可按模块组织、固定种子） | ✅（`docs/window-browser-test-coverage.md` 逐条映射；当前 608 项断言） |
| L3 | 性能分“本次实测 / 设计预算 / 仍未验证”，不把预算写成宣传数据 | ✅ |
| L4 | 记录输入到达→意图延迟→首个面板→首次目录→首图→实时首帧→动作提交/验证→资源清理 | ✅ |
| L5 | 记录取消率、过期丢弃率、单帧耗时、AX 排队、截图活动数、实时重启次数、可见单元与保留图像 | ✅ |
| L6 | 观察自身与 WindowServer 的 CPU/内存/能耗 | ❌ 未做（需要 Instruments/长时间会话） |
| L7 | 预算：功能关闭无新增截图/流/周期 AX/持续绘制；物理截图 ≤2；普通实时 ≤1 路；首个可操作面板 p95 <50 ms；局部 UI p95 <4 ms；60/120 Hz 掉帧；缓存 24 MiB 起 | 🟡（多数有离屏与逻辑证据；端到端悬停延迟、120 Hz、能耗未实测） |
| L8 | 真实视觉验收：生产组件截图（单窗/三窗/八窗列表/键盘搜索/纸面浅深/系统玻璃浅深/减少透明度+提高对比度/无图像与失败），注明 OS/SDK/缩放率 | ✅（`docs/visual-qa/**`；玻璃的折射另用屏幕截图） |
| L9 | 真实面板短视频：首次悬停、跨图标、斜移、网格/列表切换、键盘选择、取消、折叠展开、失败重试 | 🟡（组件帧序列 GIF 有；需要授权的实机录像未运行） |
| L10 | 模拟数据截图不能冒充 AX/身份/焦点验证；两类分开 | ✅ |
| L11 | 缺环境时明确写未实测，不伪造通过 | ✅（§4） |
| L12 | 快速测试组与完整回归分开，不删旧恢复测试，不用桩冒充编译通过 | ✅ |
| L13 | 不自建几十个空 service/factory；`WindowBrowserController` 可在测试到位后拆分 | 🟡（未拆分，仍较大；测试已到位） |
| L14 | 阶段 0–7 顺序推进、每阶段自证后进入下一阶段 | ✅（进度见 `docs/window-browser-progress.md`） |

### M. 文档与交付格式（任务书 §22/§24）

| # | 要求 | 状态 |
| --- | --- | --- |
| M1 | 行为/样式/材质回退/操作/兼容限制文档 | ✅ `docs/window-browser-polish.md` |
| M2 | 性能文档：环境、样本、前后对照、指标定义、预算与未达项 | ✅ `docs/window-browser-performance.md`（原始输出指向 `.build/`，该目录被 git 忽略——见 §3-G4） |
| M3 | 视觉验收文档：截图、录像位置与检查结果 | ✅ `docs/window-browser-visual-qa.md` |
| M4 | 新增生产代码测试与运行入口 | ✅ `tests/run-*.sh`、`scripts/check-*.sh` |
| M5 | 进度记录简短追加，不堆大段重复日志 | ✅ `docs/window-browser-progress.md` |
| M6 | 报告区分“已实现/自动化验证/实机验证/仍未验证” | ✅（发布说明与本文 §4） |

---

## 3. 已知缺口与风险（复检优先看这些）

| 编号 | 内容 | 严重度（自评） |
| --- | --- | --- |
| G1 | **玻璃 `contentView` 未按任务书落实**：`WindowBrowserGlassBackdrop` 只把 `NSGlassEffectView` 作为子视图，内容不在玻璃内；`WindowBrowserMaterialView.contentHost` 空置。任务书 §11.2 与 AppKit 头文件都写明应把实际控制内容设为 `contentView` | P1（功能观感 + 明确要求） |
| G2 | 玻璃的实机观感只在“合成对照板 + 屏幕截图”下取证；真实桌面上不同壁纸/窗口背景下的可读性未逐场景检查；Dock 面板是 non-key 面板，玻璃是否渲染为非激活变体未验证 | P1 |
| G3 | 性能：端到端悬停延迟、WindowServer 能耗、120 Hz 掉帧、长会话 `phys_footprint` 未实测 | P1 |
| G4 | 文档引用的原始日志在 `.build/`（被 git 忽略），外部读者拿不到原始输出；表格数字可复核但缺少原始文件 | P2 |
| G5 | 快速单窗预览仍依赖已弃用的 `CGWindowListCreateImage`（符号消失时降级并记录一次） | P2 |
| G6 | 设置页归档截图由整窗截图生成，左上角红绿灯随抓取时的窗口焦点状态变化（非确定性小区域） | P2 |
| G7 | 交互 GIF 是组件帧序列，不是实机录像；实机录像需要辅助功能 + 屏幕录制授权 | P2 |
| G8 | `WindowBrowserShotProbe` 的诊断环境变量（`WINDOWSHADE_GLASS_RIG`/`WINDOWSHADE_SHOTS_HOLD*`/`WINDOWSHADE_CARD_SURFACE`）随应用二进制发布，只影响探针入口；复检可评估是否需要改为独立目标 | P2 |
| G9 | 1x 屏幕、多显示器与混合缩放只有纯几何测试，没有实机样本 | P2 |
| G10 | 卡片在玻璃面板下改用 `.contentBackground` 标准材质，但卡片文字仍在材质上方（不是材质内部），未获得系统文字的“活力”处理；HIG 只要求内容层用标准材质，这一点满足，但复检可判断是否应把文字放进材质内部 | P2 |
| G11 | ~~紧凑操作条按钮高约 24–25 pt~~ **已解决**：操作条改为浮在画面右上角，命中区 28 × 28、间距 4 pt，不再是 24–25 pt 的行内按钮（`WindowBrowserActionBar.layout()`，断言“spinner 占一个 28 pt 槽位”） | 已关闭 |
| G12 | **底 Dock 的 38 pt 标签带依赖系统应用名气泡的落点**：气泡高度/位置是按用户截图推算的常量（`dockCaptionHeight`、`dockBottomGap`），系统版本、Dock 缩放或字号变化都可能让气泡落在带外，重新出现“两个应用名”或带里空着。真机对齐待确认 | P1 |
| G13 | 列表行固定 52 pt（+4 pt 行距），单行标题的行也按两行预留；18 个窗口时首屏约 8 行。密度是有意取舍还是缺陷，复检可判定 | P2 |

---

## 4. 仍未验证（不要在发布文案里写成已完成）

- 真实 Dock 悬停/斜向移动、真实键盘焦点、真实折叠与排布：需要授权构建 + 人工操作。
- 玻璃在真实桌面上的折射/高光观感（只能屏幕截图看，且随背景变化）。
- 1x、多显示器、混合缩放、120 Hz、睡眠/锁屏/权限撤销/显示器拔出等边界。
- WindowServer 能耗、长时间会话内存与稳定 footprint。
- 以上在 `docs/window-browser-visual-qa.md` 与 `docs/releases/v1.0.14.md` 都标注为未验证。

---

## 5. 冲突消解记录（先前的需求之间有冲突时以哪条为准）

| # | 旧表述 | 新表述 | 结论 |
| --- | --- | --- | --- |
| 1 | 任务书 §1：不要擅自提交/推送/发版/部署 | 用户在 2026-09-18 明确说“现在时机成熟了”“同一版本重新发布” | 以后者为准：只在用户明确要求时执行提交/推送/tag/Release/本机替换，并逐次记录（tag 与 sha256）。日常开发仍只用 `--stage` |
| 2 | 任务书 §1：不要停止用户正在运行的程序 | 重发流程第 3 步包含“原地替换本机应用” | 仅在“同一版本重新发布”被明确要求时执行；其余任何情况不动运行中的程序 |
| 3 | 任务书 §11.2：把实际控制内容设为玻璃的 `contentView` | 当前实现：玻璃是背景兄弟视图 | **未消解：以任务书为准，属于待修项（§3-G1）**，不得以“HIG 没写”为由跳过 |
| 4 | 用户：要有液态玻璃的感觉 | 用户：不能玻璃叠玻璃、不能自创理解 | 以后者约束前者：用系统材质 + HIG 写明的用法（单层、regular、内容层标准材质、不上色）；`clear` 只在媒体背景上，自造薄纱已删除 |
| 5 | 任务书 §9.3：面板圆角约 16 / 卡片 10–12 / 图片约 8（明确写了“是起点，需要校准”） | 用户：注意圆角、要跟 macOS 27 的 HIG 协调，并要求先检索 HIG | 以后者为准：实测本机 Finder/ChatGPT 窗口 26 px @2x = 13 pt 连续曲率 → 面板 13 / 卡片 12 / 控件 6 / 嵌套同心 4 |
| 6 | 任务书 §8：单窗口面板高度“通常不应无理由超过约 320 pt” | 用户：面板下方不能留“下巴” | 两者不冲突，取更严格者：实现为 274 pt（无状态文字时） |
| 7 | 任务书 §9.1：内容区不叠加模糊与折射 | 用户：要有液态玻璃 | 玻璃只在容器/功能层，内容层用标准材质；截图不叠玻璃、不采样背景色 |
| 8 | 任务书 §12：面板出现 140–180 ms | 实现 160 ms（在区间内）；消失 110 ms（区间 100–120 ms 内） | 无冲突，保留 |

---

## 6. 复检可执行命令

```sh
# 纯逻辑与组件回归
bash tests/run-window-browser-tests.sh     # 608 项断言
bash tests/run-paper-tests.sh
bash tests/run-duo-tests.sh

# 外观与 AppKit 契约
bash scripts/check-settings-appearance.sh  # 五页浅深色自适应 + 侧栏材质不透明
bash scripts/check-standard-menu.sh        # 主菜单 ⌘V 对照

# 编译与隔离构建（不动已安装应用）
cd prototype && ./build.sh --check
WINDOWSHADE_CODESIGN_IDENTITY="Apple Development: …" ./build.sh --stage

# 只读探针
.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade --window-browser-idle-probe
.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade --window-browser-hover-probe
.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade --window-browser-thumbnail-probe

# 生产组件截图（离屏；玻璃在其中不可见）
.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade \
  --window-browser-shots .build/window-browser-shots
.build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade \
  --settings-shots .build/settings-shots

# 玻璃的真实观感（屏幕截图；命令细节见 docs/window-browser-visual-qa.md）
WINDOWSHADE_GLASS_RIG=1 WINDOWSHADE_SHOTS_HOLD=16 \
  WINDOWSHADE_SHOTS_HOLD_NAME=dock-single \
  .build/duo-validation/WindowShade.app/Contents/MacOS/WindowShade \
  --window-browser-shots /tmp/shots-hold   # 面板停留期间另开终端 screencapture -x

# 性能对照（同一次会话内背靠背；脚本见 docs/window-browser-performance.md 的“复现方式”）
cd prototype && ./build.sh --stage        # 基线对照需要 worktree: git worktree add /tmp/ws-baseline 05e5472
```

复检时请**不要**：回退到 `05e5472`；替换/重启你机器上正在运行的 WindowShade；push/tag/发版；
把未验证项写成已验证；用模糊/渐变/私有 API 冒充系统玻璃。

---

## 7. 细化设计稿的验收口径与现状参数

### 7.1 设计稿的目录（建议）

1. **目标与边界**：这套界面服务什么任务、哪些层允许有声有色、哪些必须交给系统。
2. **分层与材质**：容器层 / 控制层 / 内容层各用什么材质、为什么；玻璃的变体与
   `contentView` 用法；`NSGlassEffectContainerView` 的启用条件；纸面与回退（减少透明度、
   提高对比度、减少动态效果）逐项。
3. **尺寸与几何**：面板在「单窗口 / 两窗口 / 3–6 窗口 / 左右 Dock / 键盘面板 / 列表模式」
   下的宽高、列数、行高、卡片尺寸；安全区域约束与滚动策略；冷启动与首次数据补全的尺寸
   变化规则。
4. **间距、圆角与边线**：基础序列、容器内边距、卡片间距；圆角刻度与嵌套同心公式；
   哪些边线保留、哪些删除；1x/2x 的细线处理。
5. **排版与图标**：字号、字重、行高、截断与 tooltip 规则；SF Symbols 的 point size/weight；
   中文与拉丁混排基线；大字号下的降级顺序。
6. **状态矩阵**：卡片、列表行、操作条、搜索框、页脚、详情区、大图预览在
   默认 / 悬停 / 键盘选中 / 按下 / 禁用 / 忙碌 / 失败 / 无画面下的表现（含文案与符号）。
7. **交互与时序**：悬停→意图延迟→出现；网格/列表切换；键盘路径（方向键、Home/End、
   Return、Escape 分层、Tab、⌘F）；输入法优先；焦点归还；Space 大图预览。
8. **可访问性**：VoiceOver 朗读内容与顺序、自定义动作、目标尺寸、对比度、不只靠颜色。
9. **动效规格**：出现/消失/选择/首图替换的时长与曲线；减少动态效果下的替代；
   60/120 Hz 下的期望。
10. **边界场景**：无图像、缺权限、折叠且屏外、最小化、应用隐藏、操作失败与重试、
    搜索无结果、同名窗口、超长标题与路径、极窄屏、多显示器/负坐标、1x。
11. **落地映射**：每条规格给出「当前值 / 建议值 / 依据 / 落点（文件:常量）」。
12. **差异与影响**：保留 / 修改 / 新增；需要同步更新的断言、归档截图与文档。

### 7.2 设计稿的硬性验收口径

- **可落地**：每个数值是 pt（或明确的相对量），并指出落在哪个文件与常量；不能只写“更圆一些”。
- **有依据**：系统定的（玻璃变体、材质、控件尺寸、目标尺寸）必须引用 Apple 文档或 HIG；
  项目自定的（面板宽度、行高、时序）必须标注为“项目参数，需实测校准”。
- **可对照**：至少给出 Dock 面板（单窗口、三窗口）、键盘面板（列表、搜索）、排布预览的
  线框/示意图，标注尺寸；允许 SVG/HTML/ASCII，不要求实机截图。
- **状态齐**：第 6 项的每个状态都要有规定，不能只画“漂亮的那一帧”。
- **回退齐**：减少透明度、提高对比度、减少动态效果、旧系统（macOS 14/15）各有一条明确路径。
- **不越界**：不得改动 §0 硬约束里列出的受保护子系统；不得把玻璃放进内容层；不得玻璃叠玻璃；
  不得给玻璃上色或用模糊/渐变/私有 API 冒充系统玻璃。
- **诚实**：你们没有实机验证的结论要明确标注“未验证”，不要用设计稿替代实测。

### 7.3 现状参数速查（引用这些值即可，不要凭空改）

| 类别 | 当前值 | 落点 |
| --- | --- | --- |
| 圆角刻度 | 窗口/面板 13 pt（本机实测 Finder/ChatGPT 窗口 26 px @2x = 13 pt，连续曲率）；卡片 12；控件 6；嵌套同心 `max(4, 外 − 间距)`；画面 = 卡片 12 − 内边距 8 = 4 | `Overlay/SystemAppearance.swift`（`SystemCornerRadius`、`SystemCornerPath`）、`WindowBrowserGeometry.swift` |
| 卷帘条形状 | 上两角圆（=窗口圆角）、下边缘直切；纸面阴影同一轮廓 | `Overlay/ShadeStrip.swift`、`Overlay/PaperSurfaceStyle.swift` |
| 间距序列 | 4 / 8 / 12 / 16 / 24 pt | `WindowBrowserLayoutParams.spacingTight/Small/Medium/Large` |
| 面板尺寸 | 底 Dock 单窗口 312×236 pt（有状态 312×253，含 38 pt 标签带）；三窗口 912×286；菜单/快捷键键盘面板 800×560 且没有标签带；左右 Dock 最多 2 列、面板 ≤640 pt；Dock 列表宽 ≤544 pt | `WindowBrowserGeometry.swift`、`WindowBrowserPanel.swift` |
| 卡片与行 | 卡片 288 pt 宽、186 pt 高（单行标题、无状态）/203（有状态）；图片 144 pt；操作按钮 28×28 浮在画面右上角；行高 52 pt、行距 4 pt | `WindowBrowserGeometry.swift`（`make(...)`、`resized(forTitleLines:)`、`resized(cardStatusLine:header:dockHeader:)`） |
| 内边距 | 面板 12 pt；卡片 8 pt；卡片间距 12 pt；页脚 18 pt（有状态才占位）；底 Dock 标签带 38 pt | 同上 |
| 排版 | 正文 = 系统正文字号（默认 13 pt）；次级 = 正文 − 2（最小 9）；标题 medium、头部 semibold；行高按字体向上取整 | `WindowBrowserTypography.swift` |
| 时序 | 悬停意图延迟 0.25 s、隐藏 0.18 s、出现 0.16 s、消失 0.11 s、选择 0.10 s、首图 0.08 s；减少动态效果全部归零 | `WindowBrowserLayoutParams`（`showDelay` 等） |
| 材质 | 面板层：`NSGlassEffectView`（`regular`，唯一一层，未上色）；内容层：`NSVisualEffectView(.contentBackground, .withinWindow)`；纸面：`windowBackgroundColor` + 0.5/1 pt 边线；减少透明度 → 纸面 | `WindowBrowserMaterial.swift`、`WindowBrowserViews.swift` |
| 已知待修 | 任务书要求“把控制内容设为玻璃的 `contentView`”，当前仍是背景兄弟视图（§3-G1） | `WindowBrowserMaterial.swift`（`WindowBrowserGlassBackdrop`） |
| 状态文案 | 普通 / 已收起 / 置顶预览 / 预览暂停 / 最小化 / 应用隐藏 / 屏外 / 正在展开 / 无画面原因 | `WindowBrowserActionPresentation.swift`（`WindowBrowserStatusPresentationFactory`） |
| 可访问性 | 卡片/行：label + value + help + 自定义动作；卷帘条/预览：窗口名 + 展开动作 | `WindowBrowserViews.swift`、`Overlay/PaperSurfaceStyle.swift` |

### 7.4 设计稿里不要做的事

- 不要自创 Liquid Glass 效果：不加自定义模糊/渐变/高光/折射，不用私有 API、KVC 或动态
  selector 模仿系统玻璃。
- 不要在内容层（卡片、列表行、内容容器）放玻璃；不要玻璃叠玻璃；不要给玻璃加色。
- 不要改变受保护子系统（`WindowCatalog`、完整 `WindowKey`、事务式隐藏/恢复与恢复验证、
  镜像租约），也不要用另一套简化的隐藏/恢复系统替换它们。
- 不要把未验证的实机结论（真实悬停、真实焦点、120 Hz、能耗、长时间会话）写成已完成。
- 不要为了造型删掉既有的键盘路径、可访问性动作与回退。
