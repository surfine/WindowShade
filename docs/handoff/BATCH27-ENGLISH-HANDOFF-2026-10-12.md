# 第27批交接：英语适配（设置外壳 + 卷帘页 + 高级页）— 2026-10-12

**总任务背景（别忘）**：本批是 [WindowShade 2 设计接手交接](DESIGN-TAKEOVER-2026-10-11.md) 的延续，不是替代。总目标仍是"从设计开始接手 WindowShade 2、贴近《Designing Fluid Interfaces》的动效质量、引入英语支持，直到品味与格调建立并验证"（active）。该文档里除英语外的其它未结线段同样继续有效：肩部/companion 的逐轴速度、富内容延迟收形状的真机路径、真机可见动效与帧率/输入延迟、VoiceOver、完整活动仲裁——不要把本批交接当成唯一待办。**英语一项经用户 2026-10-12 追加定案：全量完全适配、不留手尾**（标准与剩余表面清单见 §9）。

本交接覆盖的是英语适配**第一批**：设置窗口外壳 + 「卷帘」页 + 「高级」页（含语言开关）。实现已完成并通过大部分验收；**剩两处卡点**（见 §3、§4），验收流水线（§6、§7）未走完，英语剩余表面（§9）未开工。

**用户追加定案（2026-10-12，两轮问答，全部生效，优先于本文其他地方的旧口径）**：

1. **覆盖含官网与 README**：`site/`（中文首页 + `/en/`）与 `README.md`/`README_CN.md` 都在"全量适配"范围内，**随批滚动同步**——每批产品表面过门后，把该批新定的词与文案同步进 `site/scripts/content.mjs` 与 README 双份，并跑 `cd site && npm run build && npm run check`（官网只本地构建/检查，**不部署**、不动 wrangler）。
2. **验收强度全部轻量档**：不再为每个表面建全套原生夹具。轻量档 = 该表面关键逻辑的纯测试 + `check-localizable.py` 全目录检查 + §9.4 防漏网扫描 + 少量实际帧抽查（2–4 帧）+ 图片实看 + 证据记录。仅当"该表面存在具体布局风险、轻量档覆盖不了"才升档，且必须在证据里写明升档理由。（第27批自己这套全套夹具已建好，按原样收尾，不拆。）
3. **推进顺序**：按 §9 建议（① 静音散句+隐私 → ② 设置其余页+窗口浏览 → ③ 菜单/状态栏+更新提示+欢迎 → ④ 刘海实时活动 → ⑤ 指挥/会话 → ⑥ 启动台/手势/收尾）。
4. **卡点 B 授权修生产**：门 0 读出产品真实形态后，若观感不对（如滑杆右边留一截空），授权修 `makeCollapseSettingsRow` 一类行——但**改前先把修复前后对比图给用户看**，确认后再改；改动如实入证据（zh 视觉有意变化、该行几何期望同步更新）。
5. **英文大小写照 Apple 惯例**：菜单命令 Title Case（"Reset Defaults"），设置行/说明/提示 sentence case（"Reset defaults"）；已写进 copy-guide。
6. **繁体（zh-Hant）本次不做，但架构留余地**：解析、语言行、目录按可扩展写（`InterfaceLanguage.swift` 的 resolve 有注脚说明将来按 zh-Hans/zh-Hant 拆分）。不要为繁体过度设计。
7. **收尾方式：证据过即收尾**，不设统一的"亲自验收"环节；真机观感归用户自己的发版流程（门 5 照旧做，不含真实签名/安装）。

红线（必须继续有效）：不允许签名/安装/运行产品；不读真实资料/系统值/持久偏好/账户/网络；不做真实权限/窗口/输入/发布操作；不改其它用户文件/.zcode；main 经用户 2026-10-12 指示已并入本线（见下方推送状态），此后对 main 的操作以用户届时指示为准。QA 合成资料不写用户持久语言偏好、不触发权限弹窗；语言读取不得藏进静态 copy 初始化；本地化必须在语义身份或已选文案之后（不用英文显示串做路由身份）；不把结构 0 写成真机可见效果或"英语已支持"。当前分支 `codex/ws2-remote-gpt6-handoff-20261007`。契约全文在 `.statem/task.txt`（含允许改文件清单——已补 `prototype/WindowShade.swift`）。

**推送状态（2026-10-12）**：按用户指示，当前状态已提交（`2003e53`「第23–27批入库」）并推送到 `codex/ws2-remote-gpt6-handoff-20261007`（远端 `4accf31→2003e53`），供 GPT-6 审阅；`main` 未动、`.zcode/` 未入库、构建产物按 `.gitignore` 排除。推送经本机代理一次性完成（直连 GitHub 不通时用 `https_proxy=http://127.0.0.1:7890 git push` 可复现）。同日又按用户指示并入两条 grok 分支：`grok/g8-site-motion`（合并 `a38590c`，唯一冲突 Root.tsx 按双方内容联合保留）与 `grok/g8-opus`（合并 `08df5a4`；12 处 add/add 冲突逐一核对后全取本分支版本——本分支影片线即对方线的延续与精修，对方树无我们缺失的文件，合并零内容变化；处理清单在该提交信息里），并推送至 `08df5a4`。安全标签 `safety-before-g8-merge`（= `d04116e`）留在本地备查。**并入 main（2026-10-12 用户指示）**：本线已 fast-forward 合入 `main` 并推送；此后本分支与 `main` 同步推进——分支再有新提交时，`git checkout main && git merge --ff-only codex/ws2-remote-gpt6-handoff-20261007 && git push origin main` 即可保持 main 最新。此后是否继续推送由用户届时指示；未得指示时恢复"不提交不推送"。

---

## 1. 已定案的机制（已实现，勿重新设计）

- **默认语言**：跟随系统——首选语言以小写 `zh` 开头→中文，否则→英文（`InterfaceLanguagePreference.resolve`，纯函数可注入）。设置覆盖值存 `UserDefaults` 键 `WindowShade.InterfaceLanguage`（跟随系统=删键）。
- **切换立即生效**（不重启，显式重建）：`InterfaceLanguagePreference.set` 写偏好 → 设 `WSL10n.language` → 主线程发 `didChangeNotification`；`DuoSettingsWindow` 观察者异步重建（标题/副标题/侧栏/`pages` 整批作废/当前页重装）；`AppDelegate` 观察者 `rebuildMenu()`。已显示的刘海句子不回溯改写。
- **语义身份路由（第27批迁移边界）**：`WSL10n.setting(key, zh:) -> SettingsText`（zh 源句=稳定身份）；`WS2SettingsInfo.content/line` 的 SettingsText 重载——显示走 `.shown`、图标按 `symbol(for: .zh)`、短副标题 zh 仍查旧 `short` 表、英文查新 `shortEn`（按 key）、英文截断预算 `englishLineBudget = 34`（词边界截断）。
- 语言行在「高级」页：`NSPopUpButton`「跟随系统 / 简体中文 / English」（语言名常量字面量，不进目录表）；`changeInterfaceLanguage` 走 `InterfaceLanguagePreference.set`（写 standard 域）。

## 2. 已完成且 PASS 的部分（有产物）

- **实现**：上面机制 + 卷帘页全部行（约 60 行）+ 窗口标题/9 个侧栏分节名 + 高级页全部字符串 + 补充面板 + 番茄钟设置行 + 目录新增 165 键（共 **371 键**）。中文输出逐字节不变（`check-localizable.py` 保证代码源句==表内中文，纯测试端到端验证）。
- **纯测试 PASS**：`bash tests/run-localization-tests.sh`（先跑 `tests/check-localizable.py`；接口语言 resolve 表驱动 + 偏好存取 + 通知；371 键经编译后的 `Localizable.strings` 逐键走 `WSL10n` 英文解析、无汉字）。
- **资源路径实测 PASS**：`tools/design-qa/check-english-bundle-path.swift`（当时 12 项全 ok：真 `Bundle(url: en.lproj)` 路径命中新键、占位符语义替换、缺键回退、zh 不看 bundle、无 bundle 降级；原始日志未存档，重跑命令：`xcrun xcstringstool compile prototype/Resources/Localizable.xcstrings -o /tmp/s && swiftc -parse-as-library prototype/Core/WSL10n.swift tools/design-qa/check-english-bundle-path.swift -o /tmp/c && /tmp/c /tmp/s`）。
- **夹具与消费者建成**：`tools/design-qa/SettingsShadeLanguagePreview.swift`（9 帧：卷帘页 6 帧——zh/en × 浅/深 × 696 宽 + zh × 浅/深 × 560 宽；高级页 3 帧——zh 初始 + zh→en 重建 + 切回 zh 重建；**当前含诊断探针** `probeShade`/`appendProbe`/`probe.txt`，门 2 才删）+ `run-settings-shade-language-preview.sh` + 消费者 `check-settings-shade-language-preview.py`（zh 回归 vs 基线：文本/ax ⊇、几何 x/w ≤0.5、白名单；en 无汉字（除"简体中文"）、锚点、语言弹窗项；重建 zh 与初始 zh 一致；renderer/sources 身份）。
- **AppKit 切换测试已写**：`tests/InterfaceLanguageSwitchTests.swift` + `run-appkit-tests.sh` 白名单/运行参数（编译目录表并把 `en.lproj` 传给该套）。中文侧断言全过、卷帘页切英文全过、zh 往返全过——**仅剩 §3 的 7 条**。

## 3. 卡点 A：语言切换后设置窗口落到「效果」页（当前 7 条测试 + 7 条消费者检查因此失败）

**症状**（可复现，两个入口都现）：窗口在「高级」页时切换语言（通知触发 `refreshLocalizedCopy`），重建后窗口停在**「效果」分节**：副标题变 "Effects"/"效果"，页面内容是效果页。卷帘页/高级页本身的重建没问题——只要显式 `select(section:)` 一切正常。

**证据**：
- 夹具最新帧（`.build/design-qa/settings-shade-language/frames.json` 与 `.statem/history-design-twentyseventh-round/qa/after-run2-frames.json`）：`zh-aqua-900-advanced`（切换前）title='WindowShade 设置' subtitle='高级'、页面含"界面语言" ✓；`rebuild-en-advanced` title='WindowShade Settings'（✓ 标题会变）但 **subtitle='Effects'**、页面=效果页英文侧栏+中文效果页内容；`rebuild-zh-advanced` subtitle='效果'（切回 zh 也仍在效果页）。
- 消费者输出（`.statem/history-design-twentyseventh-round/qa/consumer-run2-check.txt`，重跑命令见 §6，当时 9 条失败）：`rebuild-en-advanced` Han 文本 6 条、`en advanced anchors` 5 条、`language popup item` 3 条、`zh rebuild must match the initial zh window`、`zh rebuild geometry must match`——全部是这一个根因。
- 切换测试失败清单（原始日志随 /tmp 清空丢失，此为当时输出的如实转抄）：`FAIL en window subtitle after switch`、`FAIL en advanced shows Language`、`FAIL en advanced shows Interface language`、`FAIL en advanced shows Takes effect immediately`、`FAIL en advanced shows Follow the system`、`FAIL en advanced shows Reset defaults`、`FAIL en advanced shows Open diagnostics log`；同跑其余断言全过（含中文侧、卷帘页切英文、zh 往返复原）。

**已排查**：语言通知只有两个订阅者（`WindowShade.swift:429` AppDelegate→只 rebuildMenu；`DuoSettingsWindow.swift:132`→`interfaceLanguageDidChange`→异步 `refreshLocalizedCopy`），无第三方订阅；`select(section:)` 调用者只有 153/246/361/475/1120 五处，246 在 `build()`（设计预览走 `.effects`）不在刷新路径；`DuoSettingsWindow.currentSection` 是存储属性（109 行，默认 .effects）。**关键推论**：`refreshLocalizedCopy`（`DuoSettingsWindow.swift:145-155`）第 147 行 `window?.subtitle = currentSection.title` 之后观察到的副标题已是 'Effects'——说明进函数时 `currentSection` 已不是 .advanced。当前最强嫌疑：`sidebarTable.reloadData()`（148/154 行）在 `allowsEmptySelection=false` + `style=.sourceList` 的表格上有选中侧效（重置/触发 `tableViewSelectionDidChange`，358 行的处理里 `rawValue(selectedRow)` 得到 .effects 就会 `select` 掉当前节）。

**下一步（一次运行就能定位）**：给 `refreshLocalizedCopy` 加临时诊断（环境变量 `WS2_LANGUAGE_DEBUG` 开关，打印每步 `currentSection` 与 `sidebarTable.selectedRow`；诊断用、跑完删）→ 跑 `bash tests/run-appkit-tests.sh InterfaceLanguageSwitchTests`（约 15–25 分钟）→ 看在哪一步翻到 .effects → 修（候选：刷新用一个 `isRebuilding` 哨兵让 358 行处理忽略重建期间的选择事件；或先 reloadData 再恢复 `selectRowIndexes`，或把 147 行挪到重建之后）→ 删诊断。修好后消费者里与这 7 项对应的检查应自然转绿（Han 文本 1 + anchors 1 + 语言弹窗 3 + zh 重建对比 2）。

## 4. 卡点 B：滑杆行「0%」读数两个形态（560 宽帧互换；2 条消费者几何检查）

**症状**：行「卷帘条半透明」右侧控件（`sliderGroup` = NSSlider 150 + 8 + 读数 36）在 696/560 两档上稳定落在**两种形态之一**：
- 形态 L（labels 撑开、控件自然宽右对齐）：`group.w=194`，696 → 读数 x≈586（右缘 624），560 → 读数 x≈450；
- 形态 C（labels 自然宽、控件被拉宽、内容左重力）：696 `group.w=481` 读数 x≈299，560 `group.w=345` 读数 x≈299，右侧留一大段空。

**探针实测**（`.statem/history-design-twentyseventh-round/qa/probe-after-run2.txt`，42 行）：同一次运行里 6 趟 layout 数值完全不变（**不是"没跑完布局"**）：run2 的 zh 四帧 = L(light560)/C(light696)/C(dark696)/C(dark560)……而首跑基线（`before-shade-first-run-frames.json`）是 L(dark560)、C(其余三帧)——**两棵树跨运行都会出现两种形态，且每帧用哪一种不稳定**。结论：这是**改动前就存在的布局歧义**（`makeCollapseSettingsRow`：显式 pin `control.trailing==row.trailing` + `labels==low hugging` + `control==required hugging` 与 NSStackView 内部 gravityAreas 约束叠加），不是本批引入；同款结构还在 `makeUnifiedControlRow/makeUnifiedToggleRow`（`Preferences.swift:697-760`），那些行暂时没观察到翻转。

**为什么现在必处理**：消费者对 zh 帧做逐标签几何 0.5pt 对比，基线帧与当前帧恰好取到不同形态就会红（当前 2 条：zh 560 两帧的 `0%` 互换）。**基线快照本身有歧义**，所以"逐字节比对基线"这个判据在歧义行上不成立。

**建议处置（择一，都要求两棵树用同一夹具重跑；另有一步前置。用户已授权必要时修生产，但"改前先看图"，见开头定案 4）**：
0. **先定"产品真实形态"，别自己发明**：加一帧"真窗口卷帘页"（照高级页的写法学：真 `DuoSettingsWindow` + `settings.select(section: .shade)`——它走产品自己的 `allowHorizontalExpansion(in: page)`，把页内所有 NSStackView 的 hugging 设为 low），用探针读产品路径下 `sliderGroup` 落在哪个形态。产品路径的落点就是目标形态；注意 `allowHorizontalExpansion` 会把 `sliderGroup` 的 hugging 从 required 降为 low，所以**产品真实形态未必是夹具现在常出现的那个**——先读到事实再选方案。（两个实现细节：夹具现在的 `DuoController()` 没有 owner，卷帘页在 `rebuildAllPages` 里取 `controller.owner?.makeShadeSettingsPage()`，所以要照 `InterfaceLanguageSwitchTests` 的写法给上 `owner`，否则 `pages[.shade]` 为空、`select` 直接返回；探针匹配的"两子视图且首个子视图是 NSSlider"这个条件在产品窗口下同样适用。）
1. **夹具层中和（推荐先试）**：夹具是自建宿主、**没有**产品 `select()` 的 `allowHorizontalExpansion` 这一步，布局环境和产品不一致。按第 0 步读到的事实，把夹具的布局环境对齐产品（复刻 `allowHorizontalExpansion` 或在夹具里把该行钉到目标形态），确认两棵树、复跑两次都稳定同一个形态后再进下一步。
2. **生产层消除歧义**：在 `makeCollapseSettingsRow`（及同款行）把 row 的 `distribution` 或控件宽约束写死，使形态不依赖环境。注意：改生产会改 zh 视觉——证据里写清选的是哪个形态及依据（以第 0 步的产品实测为准；若产品实测就是"被拉宽带空段"的形态，也要照实记录并检查观感，不能拿夹具的另一种当"正确"）；"迁移前基线"里出现另一形态的帧无法再对齐，需如实记录为预先存在的歧义（探针数据为证）。
3. **消费者降级**：只对 `0%` 这一行放行两种已知位置并写进证据——不推荐单用，可与 2 并用作兜底。

## 5. 现场恢复（重要：/tmp 已被系统清空）

- **丢失**：`/tmp/batch27-before`（before 源码树+render）、全部 `/tmp/batch27-*.log`（含首跑日志）。运行日志只此一份，重跑才有。
- **已存进仓库**（别再丢）：`.statem/history-design-twentyseventh-round/qa/`——首跑两棵树 frames（`before-shade-first-run-frames.json`、`after-shade-language-first-run-frames.json`）、消费者首次失败输出（`consumer-first-failure-exp1-frames.txt`、`consumer-run2-check.txt`）、run2 帧与探针（`after-run2-frames.json`、`probe-after-run2.txt`）。切换测试的原始日志**没来得及保存**（如实说明，勿伪造；失败清单见 §3）。`.build/design-qa/settings-shade-language/` 是 run2 输出（当前源码+探针夹具）。
- **重建 before 树**：新脚本 `bash tools/design-qa/run-batch27-before-tree.sh`（默认建到 `/tmp/batch27-before`，从 `.statem/history-design-twentyseventh-round/source` 快照复制，≈15–25 分钟）。**注意**：它用仓库里当前那版夹具——若按 §4 改了夹具，基线和 after 帧都要用改后夹具重跑。

## 6. 复跑命令与期望

| 命令 | 耗时 | 期望 |
|---|---|---|
| `bash tools/design-qa/run-settings-shade-language-preview.sh` | 15–25 min | PASS 9 帧（探针到门 2 才删；顺序见 §7） |
| `bash tools/design-qa/run-batch27-before-tree.sh` | 15–25 min | PASS 9 帧到 `/tmp/batch27-before/out` |
| `python3 tools/design-qa/check-settings-shade-language-preview.py .build/design-qa/settings-shade-language --baseline /tmp/batch27-before/out` | 秒 | 0 失败（当前 9 条：§3 七条 + §4 两条） |
| `bash tests/run-appkit-tests.sh InterfaceLanguageSwitchTests` | 15–25 min | PASS（当前 FAILED 7，全属 §3） |
| `bash tests/run-localization-tests.sh` | 分钟级 | PASS（当前 PASS） |
| `bash prototype/build.sh --check` | 15–25 min | exit 0；输入数 = 519 + 本批新增源（首次跑时确认实际数），零漂移 |

## 7. 执行顺序与护栏（防跑偏：按门走，未过门不进下一步）

- **门 0（§4 关闭）**：按 §4 第 0 步先读"产品真实形态"（真窗口卷帘页帧 + 探针）→ 选处置：若形态不像样、决定走"修生产"，**先把修复前后对比图给用户确认**（定案 4），确认后改；否则按夹具层中和 → **两棵树用同一版夹具各重跑一次** → 探针确认复跑两次都稳定同一形态。
- **门 1（§3 关闭）**：加 `WS2_LANGUAGE_DEBUG` 诊断 → 跑切换测试定位 → 修 → 删诊断 → `bash tests/run-appkit-tests.sh InterfaceLanguageSwitchTests` 全 PASS。
- **门 2（消费者过关）**：删夹具探针（`probeShade`/`appendProbe`/`probeURL`、pass1..6 调用；探针输出先留档到证据附件）→ 最终 after + before 重跑 → `python3 tools/design-qa/check-settings-shade-language-preview.py .build/design-qa/settings-shade-language --baseline /tmp/batch27-before/out` 0 失败。
- **门 3（图片实看）**：≥2 张 PNG 实际查看（`zh-light-696-shade.png`、`en-light-696-shade.png`；注意 PNG 只截页顶 720pt，滑杆行在折叠线下——这一行以帧数据+探针为准，图片只能证版面无事故）。
- **门 4（全优化构建）**：`bash prototype/build.sh --check`，exit 0，记录输入数与前后零漂移比对。
- **门 5（证据与回执）**：证据目录 `docs/design-review/2026-10-12-english-settings-shade/`（已建）写 README（照 `docs/design-review/2026-10-11-fluid-retarget/README.md` 结构：改动表 + 证据 + 未覆盖声明）+ `validation.json`（binding 照第26批公式 `sha256(canonical_json({source_sha256, evidence_sha256}))`）+ 失败样件（已存于 `.statem/.../qa/`）+ 两棵树的 frames/renderer/sources；**随批滚动同步官网与 README**（定案 1）：把本批词/文案同步进 `site/scripts/content.mjs` 与 `README.md`/`README_CN.md`，跑 `cd site && npm run build && npm run check`（不部署）；`docs/design-review/CONTINUE.md` 追加第二十七检查点；`.statem` 写**本批** `contract.json`/`self-review.json`（不沿用第26批身份）；StateM run `20261012-english-settings-shade`（现 `solve`，`current_entry_id=20261011T202355Z-84c3e991`）推进 solve → contract_check → self_review → handoff。
- **门 6（进入 §9 下一表面）**：每批重复门 2–5 的模式；未迁移表面在产出里如实写漏译原因，但**不得**写"英语已支持"，总目标以 §9 清单清完为准。

**护栏**（都是从本批真实翻车总结的，别再犯）：
- **换源码必须重跑再对比**：本批曾把排查实验态的帧当基准，得出 40 条假"图标丢失"；旧帧只配旧源码。
- **判据不许私放宽**：要放宽只允许逐条、写入证据、并说明原判据为何不成立（§4 的基线歧义是唯一已记录的例子）；不许把"两种形态都放行"当默认正解。
- **探针/诊断是临时的**：过门即删；输出先留档（`.statem/history-design-twentyseventh-round/qa/` 或证据附件）。
- **/tmp 会被系统清空**：要留的产物当场复制进 `.statem` 或证据目录，别放 /tmp 过夜（本批已丢过一整棵 before 树）。
- **声称"通过"前自问**：这是结构/隐藏窗口证据还是真机可见效果？后者没验就写 not_run/inconclusive。
- 红线段（开头）任何情况下不放松；不动 main、不提交、不推送。

## 8. 改动文件清单（都未提交）

生产：`prototype/Core/InterfaceLanguage.swift`（新）、`prototype/Core/WSL10n.swift`、`prototype/main.swift`、`prototype/WindowShade.swift`、`prototype/App/Preferences.swift`、`prototype/App/CollapseAppearanceSettings.swift`、`prototype/App/WS2FocusSettings.swift`、`prototype/App/WS2SupplementPane.swift`、`prototype/App/WS2SettingsInfo.swift`、`prototype/Effects/DuoSettingsWindow.swift`、`prototype/Resources/Localizable.xcstrings`。
测试：`tests/InterfaceLanguageTests.swift`（新）、`tests/InterfaceLanguageSwitchTests.swift`（新）、`tests/LocalizationTests.swift`、`tests/check-localizable.py`、`tests/run-localization-tests.sh`、`tests/run-appkit-tests.sh`。
QA：`tools/design-qa/SettingsShadeLanguagePreview.swift`（新）、`tools/design-qa/run-settings-shade-language-preview.sh`（新）、`tools/design-qa/check-settings-shade-language-preview.py`（新）、`tools/design-qa/check-english-bundle-path.swift`（新）、`tools/design-qa/run-batch27-before-tree.sh`（新）。
快照：`.statem/history-design-twentyseventh-round/source/`（before 版 15 个文件 + `before-sha256.txt`）。

## 9. 英语完全适配：定案与剩余表面清单（2026-10-12 用户追加）

**定案**：英语不是"做个样件"——要**全量完全适配、不留手尾**。下列完成标准全部满足才算完成，满足前整体目标保持 active，任何文档/汇报不得写"英语已支持"：

1. **用户可见字符串零遗漏**：菜单/状态栏、设置全部页、欢迎流程、刘海与实时活动、窗口浏览、卷轴与覆盖层、错误/空状态/权限说明、更新提示、辅助功能标签（ax label/tooltip 也算）——全部经 `WSL10n` 出当前语言；en 译文完整、无汉字（语言名等常量除外）。
2. **切换立即生效覆盖全部驻留界面**：不止设置窗口——菜单、刘海提示、已打开的欢迎/面板等各自定义显式重建或声明"下一句起新语言"并在证据里写清（已显示的刘海句子不回溯改写是本批已定口径）。
3. **语义身份不动**：`symbol(for:)`/`short` 表/静音 id 等仍以中文源句或 key 为身份路由；迁移不得用英文显示串反查行为（本批 `SettingsText` 机制可复用）。
4. **打包资源路径实测 + 全目录检查**：`xcstringstool` 编译产物逐键实测（本批 `check-english-bundle-path.swift` 模式）；`checks` 扩到能防"手尾"——建议给 `tests/check-localizable.py` 加一条：扫 `prototype/` 用户可见代码里的中文字符串字面量，命中不在白名单（语义身份表/QA 探针/内部键/系统权限名）就失败。没有这条"防漏网"检查，"不留手尾"只能靠人肉。
5. **每批验收用轻量档（用户 2026-10-12 定案）**：该表面关键逻辑的纯测试 + 全目录检查 + §9.4 防漏网扫描 + 少量实际帧抽查（2–4 帧）+ 图片实看 + 证据记录；未覆盖项如实写 not_run。仅当布局风险轻量档覆盖不了才升档，且证据里写明升档理由（不要主动回到"每表面全套夹具"）。

**语言扩展口径（定案 6）**：本次不做繁体（zh-Hant），但解析、语言行、目录按可扩展写。将来加繁体时要做的事：`InterfaceLanguagePreference.resolve` 里把"zh 开头即中文"拆成按文字系统的 zh-Hans/zh-Hant 判定（现有一个注脚说明这个扩展点）、语言行加一项、目录补译文。不要为它预制界面或提前改数据模型。

**剩余表面粗扫清单**（行数 = 含中文的字符串字面量行数近似值，排除了同一行有 `WSL10n.` 的行）。**扫出来的数不是全是剩余工作**，迁移前先按三类甄别：①语义身份表（`WS2SettingsInfo` 的 short/symbol 表，故意保持中文；`WS2SilentCopy` 的 zh 表——它已本地化，扫描只是把它算进去了）；②QA 探针（`SilentMilestoneProbe.swift`(53)、`*Probe.swift` 一族、`SettingsDesignPreview.swift`(19)、`WindowBrowserShotProbe`(43) 等，非用户可见）；③内部键/服务名/系统权限名（权限名沿 macOS 官方英文）。真正的剩余面如下：

| 表面 | 主要文件（≈行数） |
|---|---|
| 隐私 | `App/WS2PrivacyData.swift`(599)、`App/WS2PrivacyPane.swift`(33)、`App/WS2PrivacyModel.swift`(31)、`App/AuthorizationCopy.swift`(23，权限名沿 macOS 官方英文)、`App/WS2PrivacyExport.swift` |
| 设置其它页 | `App/Preferences.swift`(176，卷帘页已迁移；剩快捷键/隐私/鼠标触控板/遥控/窗口浏览设置等页)、`App/WS2InputSettingsPane.swift`(66)、`Effects/DuoSettingsWindow.swift`(33，效果页)、`Effects/SettingsDesignPreview.swift`(19)、`App/PrivateAppListSettings.swift`(12) |
| 静音操作 | **已本地化**：`Core/WS2SilentCopy.swift`(143 行) 是 zh 表、`WS2SilentCopy.line` 已走 `WSL10n.text("silent.<id>")`，目录里 143 个 `silent.*` 键齐全——**不是剩余工作**。剩余的是流程散句与状态词：`Core/WS2SilentGates.swift`(≈100 短状态词"已收起/已到左半/结果未确认…")、`App/WS2SilentHost.swift`(≈40，对话包装如"？点头或点一下确认"、"第 N 列"、页标题)、`App/WS2SilentApply.swift`、`Core/WS2SilentExecution.swift`、`Core/WS2SilentSecurity.swift`(12)、`App/SilentCoverProbe.swift`(7) |
| 菜单/状态栏/更新提示 | `App/StandardMenu.swift`(51)、`App/UpdaterCopy.swift`(58)、`App/MenuBarController.swift`(41)、`App/GlobalShortcuts.swift`(41)、`WindowShade.swift`(24) |
| 刘海与实时活动 | `App/Notch.swift`(60)、`Core/NotchRow.swift`(35)、`Core/NotchActivities.swift`(22)、`App/NotchActivityController.swift`(18)、`App/DeviceBatteryCopy.swift`(19)、`App/CountdownTimerCard.swift`(15)、`Core/CalendarPresentation.swift`(15)、`App/NowPlayingCard.swift`(13)、`App/FocusTimerCard.swift`(12)、`App/FileShelfView.swift`(9)、`Core/AwaySummary.swift`(7)、`Core/NotchSentence.swift`(6)、`Core/UsageReading.swift`(6) 等 |
| 窗口浏览 | `WindowBrowser/WindowBrowserController.swift`(85)、`WindowBrowserActionPresentation.swift`(45)、`WindowPlacement.swift`(21)、`WindowBrowserActions.swift`(19)、`WindowBrowserContentView.swift`(15)、`WindowBrowserSettings.swift`(9)、`WindowBrowserCardView.swift`(6)、`WindowBrowserActionBar.swift`(5) 等 |
| 指挥/会话/遥控 | `Core/ConductorSession.swift`(63)、`App/WS2OwnedLaunchController.swift`(51)、`App/WS2OwnedSessionView.swift`(36)、`App/WS2ConductorPage.swift`(36)、`App/WS2ConductorView.swift`(16)、`App/WS2ModelPickerView.swift`(15)、`Core/AgentSessions.swift`(13)、`App/WS2RemoteHost.swift`(14) 等 |
| 启动台 | `App/LaunchpadUninstall.swift`(38)、`App/LaunchpadView.swift`(31)、`App/LaunchpadController.swift`(10)、`App/LaunchpadActivities.swift`(9)、`App/LaunchpadOpenWith.swift`(5)、`LaunchpadFolders/Today/Library` |
| 欢迎与上手 | `App/Welcome.swift`(15)、`App/WelcomeFlow.swift`(11)、`App/NotchCoach.swift`(2)、`Core/SwitcherOrigin.swift` |
| 手势/卷轴/覆盖层 | `Overlay/GestureHUD.swift`(39)、`App/TrackpadGestures.swift`(22)、`Core/GestureCoach.swift`(24)、`Overlay/ShadeStrip.swift`(8)、`App/ScrollStripOverview.swift`(6)、`Overlay/GlancePanel.swift`(4) 等 |
| 窗口动作与其它 | `App/Carry.swift`(17)、`App/HabitContext.swift`、`App/PictureInPicture(+Views)`(13)、`App/MagicTilingRun.swift`(7)、`App/SlideOver.swift`(9)、`App/SplitView.swift`、`App/PresenceLockRiskSheet.swift`(7)、`Recovery/Rescue.swift`(4)、`Core/RescueAnnounce.swift`(2)、`Support/Diagnostics.swift`(6) 等 |

**建议推进顺序**（每批独立验收，先拣用户最常看的）：① 静音流程散句（Gates/Host/Apply/Execution 的状态词与对话包装，先给这批短句定英文口径，建议扩充 copy-guide 英文表）+ 隐私（量最大）；② 设置其余页 + 窗口浏览；③ 菜单/状态栏 + 更新提示 + 欢迎；④ 刘海实时活动一串（卡片与句子）；⑤ 指挥/会话/遥控；⑥ 启动台/手势/覆盖层/窗口动作与错误态；⑦ 收尾：全仓防漏网检查（§9.4 的 checker 扩展）+ 检查"跟随系统"下其它界面的重建路径覆盖。顺序可调，但每批必须过 §9.1-9.5 的对应项。

**本批已铺好的可复用件**：`InterfaceLanguagePreference`（解析/存取/通知）、`WSL10n.setting`+`SettingsText`（语义身份路由）、`shortEn`+`englishLineBudget`（英文行预算）、夹具/消费者/切换测试三件套的写法与脚本、`check-english-bundle-path.swift`、`copy-guide.md` 英文用词表（新批只在表里加行）。


---

## 10. 交接后补记（2026-10-12 晚，本 session；新 session 从这里接上）

写完本文之后，同日又发生了这些（都已完成并推送），新 session 需要知道：

1. **分支整理与合并**：grok/g8-site-motion、grok/g8-opus 已并入本分支（a38590c/08df5a4 旧号；影片线确认本分支即对方延续，零内容变化）；salvage/worktree-stash/十几个陈旧 worktree 与分支全部清理，未提交内容先归档 tar（仓库外 `~/Documents/WindowShade*.tar.gz` 两份 + 4 个本地 `archive/*` 标签）。现在本地/远端都只剩 main + 本分支。
2. **并入 main + 全史重写两次**：经用户指示，本分支已 fast-forward 合入 main 并保持同步推进；随后 `git filter-repo` 把全部提交（作者+提交者）统一为 **`Aaron <12213433+surfine@users.noreply.github.com>`**（账号归因，名字仍显示 Aaron）。**旧 SHA 全部作废**——对照表在 `.statem/history-design-twentyseventh-round/qa/commit-map-final-2026-10-12.txt`（链式原始→最终），task.txt 里有文档引用过的 11 个旧 SHA 映射。重写前镜像备份 `~/Documents/WindowShade-pre-rewrite-mirror-2026-10-12.git`（228M，确认后可删）。
3. **README 双版重写**（更简洁清楚：EN -45% 词、CN -34% 字；未发布功能收进「In development / 开发中」小节）。
4. **1.0.16 发布关启动（当前最优先的活）**：runbook 在 [docs/releases/v1.0.16-release-gate.md](../releases/v1.0.16-release-gate.md)。**Phase 0 已完成**：从 `82681b0`（二十二波+崩溃修复；纯二十二波快照 e4db602 有 `reused!` 编译错误）重建 `--stage` EXIT=0，产出 `.build/release-acceptance-20261012/WindowShade-v1.0.16.zip`（9,484,290 字节，sha256 `f404884b…43cf`），**包级门禁九步全 PASS**（gate.log；DR 与官方 1.0.15 逐字相同，`codesign -R` 必须用纯路径形式——历史口径坑已修并记档）。**等用户真机跑 Phase 1–3**（核心窗口路径含同 App 两文档历史雷、欢迎三步、更新器简验）——全过即走 runbook 末尾的发布日流程（tag v1.0.16→82681b0、gh release、appcast 签名部署、README 数字）。
5. **第 27 批的两个卡点仍未修**（§3 切换落效果页、§4 滑杆两形态）——它们不阻塞 1.0.16（基线不含 23–27 批），1.0.17 再回头修。

**新 session 的优先顺序**：① 用户真机 Phase 1–3 结果 → 发布收尾；② 回到 §7 门 0/门 1 修第 27 批卡点；③ §9 英语下一表面（轻量档）。
