# WindowShade 2 设计接手交接（2026-10-11）

## 接手目标

用户要求当前主模型从设计开始接手 WindowShade 2，纠正既有实现中的粗糙问题；动画也必须纳入产品设计，目标是贴近 Apple《[Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/)》强调的即时响应、可打断与改向、空间连续和速度连续；同时引入英语支持。这里记录已核实状态和下一步，不代表产品已达到高级感、动效已流畅或英语已全面完成。

## 先读与当前入口

继续前依次读：

1. [总设计蓝图](../blueprint.md)：产品目标、刘海仲裁、阶段顺序与硬要求。
2. [正式最终交接入口](FINAL-HANDOFF.md)：历史工单和项目收尾上下文；较早日期的状态只作为历史证据。
3. [第十份并入后的复核交接](round2-part10/REVIEW-HANDOFF.md)：W00 构建结论及真实机器限制。
4. [设计持续记录](../design-review/CONTINUE.md)：第1至25批的最新设计证据与待办。
5. 当前 StateM 契约 `.statem/task.txt` 和进度 `.statem/progress.md`。

当前分支为 `codex/ws2-remote-gpt6-handoff-20261007`，不要转到 `main`。当前执行批次为第26批，StateM 在 `solve`。范围是修复刘海中途反向衔接、统一隐私登记行列对齐；英语是整体目标，本批不启用。当前没有第26批产品代码补丁。

## 已知状态与证据边界

第25批把真实隐私行组件、Canvas 动画配置与 Core Animation 弹簧行为带入了合成探针：41条默认登记、4组、9个模拟开关；隐私页12张组合静帧及结构消费者通过。实际组合里，只有 `focus-preferences` 因标题中文关键词额外显示图标，导致说明列比其它行多缩进38点；设计稿是纯文字登记表。拟在 `PrivacyRowView` 移除这项偶发图标分支，保持字段、字体、开关与权限/读取策略不变。详见[第25批基线](../design-review/2026-10-11-privacy-composition-and-motion-baseline/README.md)和[隐私列设计稿](../design-drafts/隐私内容列.md)。

同批刘海探针发现明确的方向缺陷：形状向展开移动时中点变化为 −20.405，目标改为反向时为 +20.405，但传给 `CASpringAnimation.initialVelocity` 的值仍是 +10.327。`morphVelocity` 依据调用间位移长度估速，丢掉方向，也没有为位置、宽高、圆角分别传递速度。独立 Cocoa 探针用实际弹簧配置采样180次、比较46组，确认同一物理速度下把剩余行程翻倍会把归一化初速度减半。以上证明配置/速度映射错误，不证明真机可见卡顿，也不等同于流畅度通过。

另有待测源码风险：丰富内容先淡出文字，等待0.10秒并间隔0.04秒后再收形状；待执行请求保存了更早的 presentation 值。若期间旧形状仍在动，后续动画可能从过期位置开始。第25批空内容样例没有触发这段延迟，必须新增真实 Canvas 富内容合成阶段验证。

英语方面，现有 `WSL10n`、`en.lproj` 和 `Localizable.xcstrings` 有206个键。纯 Foundation 运行检查加载英文资源通过，但真实 App 没有语言选择/启用入口，整个菜单、设置、隐私页和其它产品表面没有完成英文覆盖。`WS2SettingsCopy.short` 和 `symbol(for:)` 仍有按中文显示文字分派的逻辑；翻译显示名称不能改变语义身份、快捷文案或图标。`WS2PrivacyData.rows/groups` 是静态值，不能假定语言变化会自动重建。

## 第26批建议实现

实施边界与设计决策详见[流体重定向实现计划](../design-review/fluid-retarget-plan.md)。关键要求：

- 对实际动画的每个 layer/keyPath 记录独立轨迹，使用实际 `CASpringAnimation` 参数、明确的动画时钟和 `FlickSpring.state` 求带符号的瞬时物理速度；反向时不得取绝对值或调用间平均速度。
- 分别处理 position.x/y、bounds 宽/高和 cornerRadius。按各自剩余行程将物理速度换算为 Core Animation 归一化 `initialVelocity`；没有仍在运行的旧动画时保留手势调用方传入的初速度。
- 零或极小剩余行程但仍有速度时，采用有界、有限时长的物理 kick 方案，避免除零、无穷初速度与惯性突失；宽高和圆角保持合法下界，边界速度处理单独验证。
- 在形状动画真正开始时重新读取呈现层位置，避免复用富内容淡出前缓存值；保留 generation/cancel 防护，防止过期退场清除新内容。
- Reduce Motion 路径不增加形状飞移；不增加空闲 Timer、轮询或常驻 DisplayLink。
- 隐私行只删除偶发关键词图标，保留实际生产的行顺序、文本、值列省略、开关、授权和来源策略。

改动前先对将编辑的生产源文件复制原始字节并记录 SHA-256。构建期间冻结生产源、QA入口与wrapper。沿用 `prototype/build.sh --check` 的完整优化构建路径和 Swift 6 / strict concurrency / warnings-as-errors 参数，不用减参、库缓存捷径或旧构建代替当前验证。QA可将隐私与动画套件编成一个入口顺序运行以减少重复编译，但需记录组合前源文件身份及生成入口身份。

## 验收与未决限制

当前批次至少验证：同一真实 Canvas 层连续改目标时，呈现位置和各轴速度方向连续；反向、再次改向、取消与过期回调；富内容延迟收形状的实际起点；极小行程和尺寸下界；Reduce Motion；41行/4组/9开关与说明列对齐；当前源码完整优化 `--check`。数值积分、配置日志、静态帧和消费者检查各自只证明其覆盖面，不得合并成“Apple级流畅”。

尚未取得真实签名 App 启动、真机刘海可见动画、目标刷新率下的帧间隔/输入延迟、完整活动仲裁/肩部与 companion 动画路径、VoiceOver、真实隐私来源与权限流程验收。项目规定需要原生界面行为证据时按[Computer Use 验收手册](../computer-use-qa.md)选择场景；无设备证据写 `not_run` 或 `inconclusive`，不以工具退出码、隐藏层缓存、平均 FPS 或合成帧冒充可见效果。

英语支持作为后续完整设计目标：沿用现有本地化入口，不另造翻译系统；先贯通一个真实生产表面的选择/切换与中英布局，再按菜单、设置、欢迎流程、刘海、窗口浏览、错误/空状态、权限说明和辅助功能标签扩展。保持稳定语义身份，不从翻译后显示文本反查行为；检查长英文、窄宽、数字/日期/复数、静态数据重建和打包资源路径。具体边界见[英语支持验收契约](../design-review/english-support-acceptance.md)。206键检查通过不等于全产品支持英语。

发版前还须按项目规则同步 `README.md`、`README.zh-CN.md` 与官网，并用 `npm run site:check` 验证官网中英文；未发版阶段不要用文档改写掩盖产品缺项。此交接不是发布授权。不要签名、安装、替换日常 App、操作真实权限/窗口/输入或读取真实账户和资料；也不要提交或推送。

## 本批结束时的接续记录

完成实现和证据后，更新 `.statem/progress.md`、`docs/design-review/CONTINUE.md`，并在此文件或本批证据README补充实际产物、SHA、命令、结果、未覆盖风险及下一步。保留失败和partial样件，避免覆盖历史验证。整体目标保持 active，直到设计、动效和英语覆盖有足够的真实产品证据。

## 第26批完成记录（2026-10-11 主模型执行）

实现与证据已落地，入口保留在本文件；完整证据见 [第26批证据](../design-review/2026-10-11-fluid-retarget/README.md) 与 [validation.json](../design-review/2026-10-11-fluid-retarget/validation.json)（binding `1e672104…`）。

- **产物**：`Core/FlickMotion.swift` `44404b5b…`（新增 `MorphRetarget`：CASpring 实际系数 + `FlickSpring.state` 求带符号瞬时速度；逐标量 keyPath 归一化初速度；有界 kick；尺寸/圆角下界保方向）；`App/Notch.swift` `a031697b…`（删 `morphVelocity`；五轴各挂动画；`performMorph` 真正开始时重读呈现层；reduced 无形状动画）；`App/WS2PrivacyPane.swift` `2e4c466f…`（删关键词图标旁支）；`App/Motion.swift` 未改 `ce92dee8…`。
- **命令与结果**：数学探针（69 条/20 组）0 且复跑逐字节相同；组合原生入口（隐私 12 帧 + 动效 62 记录、Swift6 严格、518 当前源）0，消费者首跑 9 条判据错误作为原件保留、修正后 PASS；`bash prototype/build.sh --check` 本批新跑 0（519 输入零漂移、0 错误、256 条既有警告保留）。图像实地查看 4/12 张（12 张共 2.61MiB，≤48MiB）。
- **未覆盖风险**：真机可见刘海动画、签名 App 生命周期、帧率/输入延迟、肩部与 companion 逐轴速度、VoiceOver、真实隐私来源与权限；数学/配置/静态/消费者证据各自只覆盖自身范围。
- **下一步**：继续整体目标的其余动效路径（肩部/companion 与完整真机路径证据）与英语最小贯通表面；保持证据纪律（不回用旧回执、不把隐藏层证据当可见验收）。
