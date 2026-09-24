> 历史归档：记录的是 2026-09-13 的判断与进度，不代表当前缺陷或执行指令。后续实现以 Git 历史、现行文档和 [1.0.15 发布说明](../../../releases/v1.0.15.md) 为准。

# WindowShade 设计规范 v1 — 完成检查点

目标：按用户提供的 Claude artifact 规范完成全部设计实现、真实界面验收及 README 明暗截图。用户授权推进到做完，未要求提交或发布。规范基线 ae65fcd，工作 HEAD 21ea91f。2026-09-13 完成。

## 交付

完整实现与逐项证据见 [设计规范 v1 落地](../design-v1.md)。中英文 README 已使用 assets/windowshade-settings.png 和 assets/windowshade-settings-dark.png，并按主题切换。开发指南已加入隔离验收入口和组件回归命令。

签名验证包：`.build/duo-validation/WindowShade.app`。最后构建 session85687，2026-09-13 00:59:25，50 Swift 文件，原 Apple Development 身份 / Team FVGLY6W6S4。仅保留既有 stopCapture 异步 API 建议警告。原应用 bundle 未替换，未提交或发布。

## 验收证据

- 四页、原生 sidebar 键盘选择与折叠恢复、默认/最小/宽窗口及浅深外观均已检查。
- 最终无尺寸覆盖启动日志为 900×680；CUA 实际把窗口右下角往更小尺寸拖动，session90372 的 windowDidEndLiveResize 明确报告 820×580；一次滚动到达效果页末尾。之前仅用程序设置580但实际拖动下限600的验收结论已作废。修复通过按实际工具栏高度换算窗口 minSize 与内容 fitting 下限，另明确初始化根视图尺寸。
- `bash tests/run-duo-tests.sh` session61793 全通过（核心/恢复、帧元数据、集成边界、Metal），之后仅修改 UI，核心实现未变。
- `bash tests/run-paper-tests.sh` session16055 全通过，macOS14部署目标：跟踪区域边界、默认隐藏、移入显示、标题区域点击穿透、移出隐藏、缩放。
- 原生窗口阴影生命周期 PASS：父几何、鼠标穿透、显示隐藏、移动缩放、透明度层级、回收清理。报告 `.build/design-review/shadow-check.txt`。
- 悬停验收发现并修复标准标题栏提前吞掉 mouseExited、NSView 默认不裁切导致跟踪区域扩张；深色提示对比度已修正。通过实际组件状态入口查看了移入/移出画面，并在可见标题上用 CUA 点击，日志确认传到内容回调。
- CUA普通点击没有生成系统 tracking enter/exit。此项采用真实组件回调回归和状态快照验收，不声称完成物理鼠标悬停测试。此前请求的用户手动补验不再作为完成阻塞。
- `git diff --check` 通过，所有新交付文件已在工作区；.gitignore 明确允许两张README截图。

## 运行与后续

QA实例 session90372 已结束，原应用 PID41590保持运行。不要再对已退出的 CUA app 调 getAXState：它可能自动重启验证包且不带隔离参数。此前一次自动重启的 stage 进程已明确终止，未影响原应用进程。

无剩余实现或验收项。若用户继续提出修改，沿用现有成果；不要重开完整审计或重复已通过且未受影响的测试。AGENTS.md、CLAUDE.md 的未跟踪状态为工作区既有内容，本任务未改动。

## 2026-09-13 用户截图纠正

此前“完成”不代表整体视觉已获用户认可。用户指出设置侧栏与右侧背景割裂，以及自身设置窗口原貌卷帘裁切过短。当前修正：移除 detail 的 underPageBackground 材质，窗口统一使用自适应 textBackgroundColor；分组保留轻微灰色填充；原生侧栏不改造。自身窗口使用主线程 AppKit contentLayoutRect 计算真实顶部高度，批量 AX 预热前快照该值，避免 AX 漏报自身工具栏导致 28pt 截断。另为置顶菜单补齐与折叠菜单共用的 16pt App 图标。

编译检查通过；离屏原生统一工具栏几何检查通过（测试配置实测 66pt，生产设置此前 contentLayoutRect 显示顶部 52pt，均不应硬编码）。浅色实际截图确认背景交界的灰色块消失。真实折叠截图尚待更新版本验证，不能宣称裁切视觉验收已通过。

后续 Codex 原貌卷帘截图仍显示工具栏裁切过短：自身窗口修正不足以覆盖通用问题。已在 toolbar-less 标准标题栏判断前检查顶部控件完整范围与 padding，超过标准高度则走已有控件测量路径。编译通过；CUA 明确禁止操作 com.openai.codex，未绕过限制，故该窗口真实折叠视觉仍待验证。

## 2026-09-13 原貌功能重新审视

用户明确反馈最近修正仍未解决，并要求全面审视原貌卷帘、扩大应用和窗口类型覆盖、增强互动。此轮不继续堆叠生产补丁，完成 `docs/reviews/native-shade-review-2026-09-13.md`。报告依据源码、最新运行日志及 Apple 官方资料，确认 Codex 最新记录仍走 32pt 标准标题栏；通用图像扫描无调用，精细扫描当前配置条件冲突。建议先建立失败案例回放、显式捕获几何、候选边界和可信度、轮廓隔离及手动校准，再做按能力预览／真实窗口接管／有限 AX 动作。报告含窗口类型矩阵、四路线比较及分阶段验收。裁切缺陷仍未通过实际验收，原貌升级尚未实施。

## 2026-09-13 整体体验审视

用户进一步要求审视整个 App 的现有功能体验，不复杂化且不损害性能。新增 `docs/reviews/app-experience-priorities-2026-09-13.md`，以可预测操作、正确恢复、减少打断和按需工作排序。确认外观影响快捷键含义、置顶列表点击名称即取消、效果文案与触发链路不符、mouseDown 先弹预览、1.4 秒菜单栏文字反馈、多置顶 30Hz 鼠标检查等具体入口。未修改功能、未运行新基准；文档中的交互风险与性能优化仍须对应场景验证。

## 2026-09-13 用户纠正：必须依据历史与立即收益

已核对 c4b4ef8 专注三阶段、e46d10e 置顶点击取消、011865c 120→30Hz、fc9484e 统一预览／Space-local、3be00d0 自适应捕获／共享 watchdog、52d03a9 菜单精简、edb98f5 窄范围应用裁切和 33bb290 静态设置停止空转。撤回将这些设计取舍一概视为缺陷的建议。新增 `docs/reviews/near-term-plan-after-history-2026-09-13.md` 为当前执行依据：①补回置顶“点击取消”提示；②准确说明窗口折叠动画与暂停范围；③对用户原貌失败例做原图→裁切→显示对照，再局部修复并实图验收。前三份审视中广泛架构／交互建议不作为近期授权实施目标。此次仅修改计划，未改生产功能。

## 实施中：2026-09-13 04:44

目标已激活：把修订计划落地，完成后交付；用户授权自行判断常规不确定事项。已改置顶标题为“已置顶窗口（点击取消）”，设置文案为窗口折叠动画／暂停效果／效果，README 中英同步区分合盖桌面效果与手动折叠动画。

已取得关键实图：QA `compareCropGeometry` 对同一个设置窗口比较 SCK 带 framing 与无 framing。`.build/design-review/crop/framed-crop.png` 顶部阴影占据内容坐标导致标题／按钮被截；`unframed-crop.png` 完整。生产 `captureWindow` 增加 `ignoreShadowsSingleWindow=true`。撤掉前轮未生效的 toolbar-less 额外控件扫描，保留自身窗口 contentLayoutRect 高度读取。实际生产捕获经镜像与 makeScreenshotOverlay 生成的 `actual-overlay.png` 也已查看，52pt 设置条完整。QA 只捕获自身设置窗口，不触碰受 CUA 禁止的 Codex。

重要：动画帧源 EffectFrameSource 本来已有 ignoreShadows=true，因此该修正不构成 Codex 最新动画路径缺陷已修好的证据。Codex 仍需对应图像验证，不得宣布完成。

通过：tests/run-duo-tests.sh（session88387）；已签名 stage 原生临时窗口事务测试（session55851，折叠、展开、反向取消、拖动恢复、同步恢复全通过）；当前正常 bundle 构建 session45904 成功，签名04:43:25。当前运行是正常 bundle 的 --duo-design-preview（TTY session9412），最小820×580新文案截图已查看无截断，真实用户普通模式暂未重新启动。不要 getAXState 自动拉起未带参数 app。

新增待构建改动：EffectWindowProbe 增加 --no-animation，验证关动画后仍正常折叠／还原（关闭动画时只跑前两项，不跑与动画阶段相关的反向测试）。还需实际菜单提示／取消检查、无动画事务、复杂工具栏对照、性能前后对照以及 Codex 失败例。没有调用 update_goal 完成。

## 实施补充：2026-09-13 04:50

最终当前 bundle 签名时间04:46:32，Team FVGLY6W6S4；新增无动画事务验证 session8345 exit0，真实隐藏、卷帘显示及原位置恢复通过。QA session85892 已退出，普通版 PID12654 已启动，未留下QA进程。git diff --check 通过。

同一900×680、2x设置窗口六组交错捕获：带framing中位73.19ms，无framing中位67.98ms；无framing一次122.96ms离群。只是单次截图API的小样本，不能据此宣称整体折叠加速或主线程无回归。修复不增加常驻流、轮询或AX扫描。最新actual-overlay.png已查看，完整52pt顶部。

普通模式菜单的实际点击验收尚未完成：Finder快捷键未形成置顶记录，CUA未暴露状态图标，SystemUIServer查询超时；没有为了验收改用户菜单交互。用户正常操作期间日志显示Codex已出现46pt裁切并完成恢复，但没有相同窗口正常顶部与折叠图的对照，不能认定解决。已通过异步问题告知工具禁止操作Codex自身，需要用户正常折叠后的反馈。目标仍未完成；剩余实际菜单验收、复杂窗口对照和Codex实图确认。

## 用户再验失败：04:50截图

用户明确回答“还是没有解决问题”，并提供04:50:10折叠图。对应日志04:50:03.675/713：standardTitleBarOnly=true、toolbarlessStandard=true、axBarH=32、finalBarH=32、cropPxH=64。此前04:49:31的46pt不是这张图的结果，不能混用为改善证据。

续查历史：windowLooksToolbarlessStandardTitleBar 的“无AXToolbar且交通灯推算高度<=40便当成标准标题栏”在641f162初始公开提交已存在。不能称为这次设置改版新引入的算法回退；现有启发式对用户当前自绘工具栏不成立。既往扩大控件扫描补丁未获有效证据，仍不重新叠加。下一步需要用户已被请求的同窗口展开顶部图（含工具栏下缘），确定缺失范围；CUA禁止操作Codex自身，不用其他自动化绕过。截图路径修正与自身设置contentLayoutRect修正保留，但不构成Codex修复。

## 用户成功样例：04:52:40截图

用户反馈“现在似乎可以了”，新截图显示顶部控件完整。对应04:52:35日志：同一id18627、3420×1996捕获，standardTitleBarOnly=false、toolbarlessStandard=false、axBarH=46、finalBarH=46、cropPxH=92、boundary=AX；恢复几何通过。相对于04:50的32pt失败，46pt是目前有实图支持的成功样例，但这期间没有新代码构建，不能归因于新修复或认定已稳定。后续诊断应解释同窗口32/46分类差异，不再要求用户重复提供同样的折叠图，也不把46硬编码为所有窗口高度。

## 稳定性修复实施：动画前测量

新证据：04:50失败在duo-session覆盖窗口已显示后才解析chrome；04:52成功没有前置fold动画，直接解析得到46pt。因此当前最小修正是在WindowFoldEffects.interceptFold内、启动覆盖窗口之前解析preparedProfile，onVisible调用shade时传入该结果，复用现有批量折叠参数。没有新增扫描算法、固定应用高度或常驻工作；测量从动画后移到动画前。焦点变化导致高度变化仍是待实测假设，不能宣布Codex稳定修好。

build --check session47294通过；Duo相关测试session96549全通过。签名stage构建session4439正在运行，下一步等待同一handle完成，然后跑真实临时窗口动画事务验证。普通版仍是04:46:32版本，未更新新修正。

Stage构建session4439于04:57:50完成，原Team签名保留。真实动画事务session78342 exit0：折叠、还原、准备期反向取消、拖动恢复、同步恢复取消全部通过。普通版构建session9280已启动，待同handle完成后重新open普通bundle；Codex稳定视觉尚需新版本实际验证。

普通版session9280于04:59:28签名构建成功，已open重新启动；git diff --check通过。新版包含动画前preparedProfile传递。所有自动测试已通过，但不把临时原生窗口的结果泛化成Codex已稳定；仍需用户正常操作下确认。

## 新版用户验收：05:03

用户反馈“暂时是正常的”。新版日志05:03:40与05:03:44两次Codex折叠均46pt/92px，05:03:46恢复验证成功，原位置一致。这支持当前已报告案例通过，不能扩大为所有应用长期稳定。保留当前裁切实现，不再加补丁。普通版CUA菜单访问再次超时；已向用户发出单项菜单显示／图标／对应取消的验收问题。
