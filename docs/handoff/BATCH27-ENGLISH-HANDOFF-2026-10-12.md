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
4. **打包资源路径实测 + 全目录检查**：`xcstringstool` 编译产物逐键实测（本批 `check-english-bundle-path.swift` 模式）；`checks` 扩到能防"手尾"——建议给 `tests/check-localizable.py` 加一条：扫 `prototype/` 用户可见代码里的中文字符串字面量，命中不在白名单（语义身份表/QA 探针/内部键/系统权限名）就失败。没有这条"防漏网"检查，"不留手尾"只能靠人肉。**第28批已落地（2026-10-12）**：实现为全仓扫描 + `tests/localizable-ratchet.json` 基线棘轮（3406，只许降不许升），不是逐条白名单硬失败；身份表/QA 探针/权限名占位在基线数内逐批消化（见 §12）。
5. **每批验收用轻量档（用户 2026-10-12 定案）**：该表面关键逻辑的纯测试 + 全目录检查 + §9.4 防漏网扫描 + 少量实际帧抽查（2–4 帧）+ 图片实看 + 证据记录；未覆盖项如实写 not_run。仅当布局风险轻量档覆盖不了才升档，且证据里写明升档理由（不要主动回到"每表面全套夹具"）。

**语言扩展口径（定案 6）**：本次不做繁体（zh-Hant），但解析、语言行、目录按可扩展写。将来加繁体时要做的事：`InterfaceLanguagePreference.resolve` 里把"zh 开头即中文"拆成按文字系统的 zh-Hans/zh-Hant 判定（现有一个注脚说明这个扩展点）、语言行加一项、目录补译文。不要为它预制界面或提前改数据模型。

**剩余表面粗扫清单**（行数 = 含中文的字符串字面量行数近似值，排除了同一行有 `WSL10n.` 的行）。**扫出来的数不是全是剩余工作**，迁移前先按三类甄别：①语义身份表（`WS2SettingsInfo` 的 short/symbol 表，故意保持中文；`WS2SilentCopy` 的 zh 表——它已本地化，扫描只是把它算进去了）；②QA 探针（`SilentMilestoneProbe.swift`(53)、`*Probe.swift` 一族、`SettingsDesignPreview.swift`(19)、`WindowBrowserShotProbe`(43) 等，非用户可见）；③内部键/服务名/系统权限名（权限名沿 macOS 官方英文）。真正的剩余面如下：

| 表面 | 主要文件（≈行数） |
|---|---|
| 隐私 | `App/WS2PrivacyData.swift`(599)、`App/WS2PrivacyPane.swift`(33)、`App/WS2PrivacyModel.swift`(31)、`App/AuthorizationCopy.swift`(23，权限名沿 macOS 官方英文)、`App/WS2PrivacyExport.swift` |
| 设置其它页 | `App/Preferences.swift`(176，卷帘页已迁移；剩快捷键/隐私/鼠标触控板/遥控/窗口浏览设置等页)、`App/WS2InputSettingsPane.swift`(66)、`Effects/DuoSettingsWindow.swift`(33，效果页)、`Effects/SettingsDesignPreview.swift`(19)、`App/PrivateAppListSettings.swift`(12) |
| 静音操作 | **已本地化**：`Core/WS2SilentCopy.swift`(143 行) 是 zh 表、`WS2SilentCopy.line` 已走 `WSL10n.text("silent.<id>")`，目录里 143 个 `silent.*` 键齐全——**不是剩余工作**。流程散句与状态词（列于下）**已由第28批全部迁出**（见 §12）：`Core/WS2SilentGates.swift`(≈100 短状态词"已收起/已到左半/结果未确认…")、`App/WS2SilentHost.swift`(≈40，对话包装如"？点头或点一下确认"、"第 N 列"、页标题)、`App/WS2SilentApply.swift`、`Core/WS2SilentExecution.swift`、`Core/WS2SilentSecurity.swift`(12) 等；`App/SilentCoverProbe.swift`(7) 属 QA 探针，按类别②豁免。 |
| 菜单/状态栏/更新提示 | `App/StandardMenu.swift`(51)、`App/UpdaterCopy.swift`(58)、`App/MenuBarController.swift`(41)、`App/GlobalShortcuts.swift`(41)、`WindowShade.swift`(24) |
| 刘海与实时活动 | `App/Notch.swift`(60)、`Core/NotchRow.swift`(35)、`Core/NotchActivities.swift`(22)、`App/NotchActivityController.swift`(18)、`App/DeviceBatteryCopy.swift`(19)、`App/CountdownTimerCard.swift`(15)、`Core/CalendarPresentation.swift`(15)、`App/NowPlayingCard.swift`(13)、`App/FocusTimerCard.swift`(12)、`App/FileShelfView.swift`(9)、`Core/AwaySummary.swift`(7)、`Core/NotchSentence.swift`(6)、`Core/UsageReading.swift`(6) 等 |
| 窗口浏览 | `WindowBrowser/WindowBrowserController.swift`(85)、`WindowBrowserActionPresentation.swift`(45)、`WindowPlacement.swift`(21)、`WindowBrowserActions.swift`(19)、`WindowBrowserContentView.swift`(15)、`WindowBrowserSettings.swift`(9)、`WindowBrowserCardView.swift`(6)、`WindowBrowserActionBar.swift`(5) 等 |
| 指挥/会话/遥控 | `Core/ConductorSession.swift`(63)、`App/WS2OwnedLaunchController.swift`(51)、`App/WS2OwnedSessionView.swift`(36)、`App/WS2ConductorPage.swift`(36)、`App/WS2ConductorView.swift`(16)、`App/WS2ModelPickerView.swift`(15)、`Core/AgentSessions.swift`(13)、`App/WS2RemoteHost.swift`(14) 等 |
| 启动台 | `App/LaunchpadUninstall.swift`(38)、`App/LaunchpadView.swift`(31)、`App/LaunchpadController.swift`(10)、`App/LaunchpadActivities.swift`(9)、`App/LaunchpadOpenWith.swift`(5)、`LaunchpadFolders/Today/Library` |
| 欢迎与上手 | `App/Welcome.swift`(15)、`App/WelcomeFlow.swift`(11)、`App/NotchCoach.swift`(2)、`Core/SwitcherOrigin.swift` |
| 手势/卷轴/覆盖层 | `Overlay/GestureHUD.swift`(39)、`App/TrackpadGestures.swift`(22)、`Core/GestureCoach.swift`(24)、`Overlay/ShadeStrip.swift`(8)、`App/ScrollStripOverview.swift`(6)、`Overlay/GlancePanel.swift`(4) 等 |
| 窗口动作与其它 | `App/Carry.swift`(17)、`App/HabitContext.swift`、`App/PictureInPicture(+Views)`(13)、`App/MagicTilingRun.swift`(7)、`App/SlideOver.swift`(9)、`App/SplitView.swift`、`App/PresenceLockRiskSheet.swift`(7)、`Recovery/Rescue.swift`(4)、`Core/RescueAnnounce.swift`(2)、`Support/Diagnostics.swift`(6) 等 |

**建议推进顺序**（每批独立验收，先拣用户最常看的）：① 静音流程散句（Gates/Host/Apply/Execution 的状态词与对话包装，先给这批短句定英文口径，扩充 copy-guide 英文表——**第28批已完成，见 §12**）+ 隐私（量最大，下一批）；② 设置其余页 + 窗口浏览；③ 菜单/状态栏 + 更新提示 + 欢迎；④ 刘海实时活动一串（卡片与句子）；⑤ 指挥/会话/遥控；⑥ 启动台/手势/覆盖层/窗口动作与错误态；⑦ 收尾：全仓防漏网检查（§9.4 的 checker 扩展）+ 检查"跟随系统"下其它界面的重建路径覆盖。顺序可调，但每批必须过 §9.1-9.5 的对应项。

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

---

## 11. 卡点收尾补记（2026-10-12 晚，后继 session；§7 门 0–门 5 已全部走完）

§3、§4 两个卡点已在 [docs/design-review/2026-10-12-english-settings-shade/README.md](../design-review/2026-10-12-english-settings-shade/README.md) 关闭并留证，本节只记结论与口径变化：

1. **卡点 A（切换落「效果」页）已修生产**：根因确认为 §3 的最强嫌疑——`refreshLocalizedCopy` 的 `reloadData` 在 `allowsEmptySelection=false` 的 sourceList 上同步触发 `tableViewSelectionDidChange` 把选中打回第 0 行（诊断日志 `.statem/history-design-twentyseventh-round/qa/gate0/switch-tests-debug-run1.log` 实测）。修复：重建期间 `isRebuildingLocalCopy` 哨兵挂起选择处理（`DuoSettingsWindow.swift`），`select(section:)` 原有的选中行拨回复位。诊断已删，切换测试 **33 ok / 0 FAIL**。
2. **卡点 B（滑杆两形态）不改生产**：门 0 用产品真窗口帧（夹具新增 `product-zh-aqua-900-shade`）实测产品落**形态 L**（控件自然宽 194、读数贴右缘，观感正常）——定案 4 的"修生产先看图"未触发。夹具复刻 `allowHorizontalExpansion` 后仍漂，按 §4 方案 1 在夹具里把 labels hugging 压一档（249）钉住；两跑四帧稳定。**消费者新增门 0 判据**（夹具滑杆行 span 必须等于产品实测 612/476）。生产行几何未动。
3. **顺手修的漏网**（本批范围外发现、属 §9.4 防漏网精神）：设置外壳两处硬编码中文（侧栏 ax 标签「设置侧边栏」、工具栏标签「切换侧边栏」）迁目录（目录 371→**373 键**）；侧栏 ax 标签原来建表时设一次、语言切换不更新，已随重建刷新。隐私登记表补登 `InterfaceLanguage.swift` 的 4 处 `UserDefaults` 字样（门 4 首跑红过）。
4. **基线重建方式变更**：`run-batch27-before-tree.sh` 不再用 15 文件快照拼接（缺其余生产源、必编不过），改为 `git archive 2003e53^` 完整检出（该父提交与快照 15 文件逐字节一致，已核对）；脚本还修了 cp 路径与 modulemap/header 两个 bug。重跑的 before 基线与 after 同夹具版本。
5. **判据放宽记录**（护栏要求逐条）：两条 wrappingLabel（「需要已绑定身份的蓝牙读回来源」「名单里还没有 App」）的几何对比跳过——基线同一 run 内自身漂移，见 [gate2-geometry-drift.md](../design-review/2026-10-12-english-settings-shade/gate2-geometry-drift.md)。连同 §4 滑杆行，全批共三条布局歧义，均改动前已存在。
6. **门 3 图像口径**：高级页与产品窗 PNG 在离屏渲染下黑屏（sourceList/材质视图不渲染，run2 起即如此），图像证据记 inconclusive，验收以帧数据为准（`windowSubtitle` 高级→Advanced→高级、产品窗 subtitle「卷帘」）。zh/en 卷帘页 PNG 已实看无事故。
7. **门 4/门 5**：`build.sh --check` PASS（514 文件、373 键、隐私登记 PASS、文案检查 PASS）；证据目录与 `validation.json`（binding `b332ab69a03e41c6`）、`CONTINUE.md` 第二十七检查点、StateM run `20261012-english-settings-shade` 推进到 handoff、README 双版「开发中」各加英文界面条目；site 无词可同步（本批英文词与官网一致），build+check PASS 未部署。
8. **改动均未提交**（按"未得指示时不提交不推送"）。**下一 session 优先顺序不变**：① 等用户真机 Phase 1–3 → 1.0.16 发布收尾；② §9 英语下一表面（按建议顺序 ①静音散句+隐私，轻量档）。本批的修复不属于 1.0.16 基线（82681b0），不阻塞发布。

---

## 12. 第28批补记（2026-10-12 深夜，本 session；按用户指示暂停收尾）

第28批（§9 顺序 ① 的静音散句，轻量档）**实现与验收主体已完成**；门 5 的收尾件未走完，按用户指示停在这里。新 session 从本节接：

1. **迁移完成**：静音线 7 个文件（`WS2SilentGates`/`Host`/`Apply`/`Execution`/`Security`/`Draft`/`ProductPort`）去重中文字面量 137 条全部出表：125 条直迁 + 9 条活动/用量读回复用既有 `lines` 表 id（`activity.*`/`usage.*`，无新键）+ 3 处插值并为 2 条 `saying2` 模板（第 %@ 列/页）；`WS2SilentCopy.sayings` 新增 **127 条**（`say.*`），目录 373→**500 键**。7 文件代码行零中文残留（身份表除外）；旧 `silent.*` 6 条英文按 copy-guide 对齐（只改 en，中文身份不动）；`docs/copy-guide.md` 追加第二批英文表 10 行。
2. **测试与检查全过**：静音纯测试 2117 ok；本地化 52 ok（500 键逐键）；集成 `--case r01`（12 ok）/`--case r03`（5 ok）PASS；`check-localizable.py` 规则 3 拆 lines/sayings 两块 + **§9.4 防漏网棘轮**落地（`tests/localizable-ratchet.json` 基线 **3406**，只许降不许升；下一批迁完重跑并把基线调低，上涨会被拦）。
3. **门 3/门 4 完成**：`SilentPageLanguagePreview.swift` 4 帧夹具（zh/en × 初始/结果句）PASS、4 张 PNG 实看（Launchpad 贴边=既有密度，记观察项）；`bash prototype/build.sh --check` **EXIT=0**（514 文件、500 键、全优化编译、隐私登记 PASS、文案检查 PASS）。首跑曾红：4 条迁入原文超 copy-lint 主句 8 字形簇上限，经 git diff 对照 `2003e53^` 确认为改动前逐字节原文（本批中文不许动），`tests/copy-lint.py` 加 `LEGACY_SAYINGS` 逐条豁免（日志有逐条记录）。
4. **证据**：`docs/design-review/2026-10-12-english-silent-lines/`（README + native/：4 PNG、frames/renderer/sources、夹具日志、集成 r01/r03 日志、build-check.log，均已归档）。
5. **未走完（下一 session 先收尾，再开新表面）**：① `validation.json`（binding 照第26批公式）；② `CONTINUE.md` 第二十八检查点；③ `.statem` 本批 contract/self-review + StateM run（`active_run` 仍是第27批 `20261012-english-settings-shade`）；④ site/README 同步检查（`cd site && npm run build && npm run check`，不部署；预计无词可同步——静音句只出现在刘海/面板，官网未涉及）。**【已收尾，见 §13】**
6. **改动均未提交**（第27批门 5 起 + 第28批全部；未得指示不提交不推送）。本批不在 1.0.16 基线（82681b0）内，不阻塞发布。

**新 session 优先顺序（更新版）**：① 等用户真机 Phase 1–3 → 1.0.16 发布收尾（§10 第 4 条 runbook）；② 收尾第28批门 5 剩余件（上条第 5 项）；③ §9 下一表面：**隐私**（`WS2PrivacyData` 是生成文件——迁移点在生成器 `tools/privacy/make-privacy-page-source.py` 与 `tools/privacy/registry.json`，先读生成链再动，生成器改完重生成并核对中文逐字节）或设置其余页，仍轻量档。

---

## 13. 第28批门5收尾完成（2026-10-12 深夜，后继 session；§12 第 5 条已清）

§12 第 5 条四件收尾全部完成，改动仍**未提交**（未得指示不提交不推送）：

1. **复跑留档**：`silent-prep-tests.log`（2117 ok / 0 FAIL）、`localization-tests.log`（52 ok）、`site-build.log`/`site-check.log`（42 项 exit 0，本地构建检查、**未部署**）——归档到 `docs/design-review/2026-10-12-english-silent-lines/native/`；此前纯测试只有口头记录，按"/tmp 不过夜"护栏补的。批内已归档的 build-check/fixture/integration 日志未重跑，按原档引用。
2. **`validation.json`**（同目录）：binding `5abf775956f990ac`，17 源 + 16 证据；公式 `sha256(canonical_json({source_sha256, evidence_sha256}))` 先复算第27批 `b332ab69a03e41c6` 对上后才套用；evidence 表**不含 validation.json 自身**（第27批表内自引用哈希是绑定时的草稿快照，属既有惯例，本批不沿用）。证据 README 加了「门 5 收尾附记」节。
3. **`CONTINUE.md` 第二十八检查点**已追加；`.statem` 已换成**本批**契约 `task.txt`（第27批契约归档至 `history-design-twentyseventh-round/task.txt`）+ 本批 `contract.json`/`self-review.json`（receipt 校验通过，不沿用第27批身份），新建 StateM run **`20261012-english-silent-lines`** 推进 solve → contract_check → self_review → **handoff**；`.statem/progress.md` 追加本批收尾记录；第28批契约与回执快照留档 `.statem/history-design-twentyeighth-round/`。
4. **site/README 同步检查**：确认无词可同步（静音句只出现在刘海/面板；`site/scripts/content.mjs` 与 README 双版「开发中」小节在本批无新增词条），build+check PASS 未部署。

**新 session 优先顺序（再更新）**：① 等用户真机 Phase 1–3 → 1.0.16 发布收尾（§10 第 4 条 runbook）；② §9 下一表面：**隐私**——`WS2PrivacyData.swift` 是生成文件，迁移点在生成器 `tools/privacy/make-privacy-page-source.py` 与 `tools/privacy/registry.json`，**先读生成链再动**，生成器改完重生成并核对中文逐字节；轻量档。第28批全部改动（含本批门5收尾）不在 1.0.16 基线（82681b0）内，不阻塞发布。

---

## 14. 1.0.16 发布关 Phase 1–3 Computer Use 代跑完成（2026-10-12 晚，本 session）

用户明确选择"Computer Use 全代跑"（解除"真机观察由用户完成"边界，仅限本次发布关）。隔离 VM（/Volumes/TiPlus 7100/WindowShade-QA，wsqa-manual）内按 Computer Use 验收手册执行：

1. **环境恢复**：来宾 SSH 公钥补装（lume/lume 默认凭据经 `lume ssh` 引导）、CuaDriver 以 GUI 会话重启（权限沿已配置状态）、doctor PASS。候选包（2c3b39ca…，源 82681b0）部署来宾，二进制 2d9a6e8b…/Team FVGLY6W6S4/1.0.16(16) 与 Phase 0 门禁一致。
2. **结果**（证据表 [docs/releases/v1.0.16-acceptance/phase123-results.md](../releases/v1.0.16-acceptance/phase123-results.md)，八场景 review/verify/cleanup/report 齐，report 副本同目录）：
   - Phase 1：单文档收/展、**同 App 两文档（历史雷未复现）**、菜单路径、深色模式全 **pass**（截图+AX+journal 三源互证）；「收起后的样子」两档对比与动画时序 **inconclusive**。
   - Phase 2：欢迎三步 **pass**；「欢迎使用随时重开」**inconclusive**（基线实现里入口在设置卷帘页补充面板，不在状态菜单——runbook 口径与 82681b0 代码不一致，代码注释 MenuBarController.swift:193「欢迎使用只在设置里」）；减少动态效果 **not_run**。
   - Phase 3：更新器自动检查（SULastCheckTime 置旧强制触发）**pass**——无崩溃、无假版本、无错误；⌥ 菜单「检查更新…」交互 **inconclusive**（CGEvent 修饰键时序够不到，真机 5 秒可验）。
   - **判定：无 fail，核心路径全过**；inconclusive/not_run 四条带入发布说明与用户真机复验清单（动画手感建议用户亲验）。
3. **过程留痕**：三次 run 因工具时效护栏 HALTED（截图 50 秒时效、press_key 参数缺失），全部按手册保留 CLOSED 记录未删标记；权限弹窗（shd-keygen，由我误触 osascript 引起）当场 Deny 留证。QA VM 外观停在深色（AppleScript 无授权），下次使用前可 UI 复原；VM 保留运行，测试文档与证据按手册保留。
4. **发布日流程解锁**：门条件（Phase 1 全 PASS + Phase 2 全过 + Phase 3 简验无双异常）在代跑口径下满足；是否按此收尾发布由用户裁定——若要求真人复核 inconclusive 项后再发布，清单见 phase123-results.md 判定节。

---

## 15. #39/#40 收进 1.0.16（2026-10-12 晚，本 session；发布基线切 0-B）

用户把两个 GitHub issue 交给本 session，并选定：**#40 走方案 A（英语进 1.0.16，基线切 main）**、**#39 加码多道防线**。

1. **#39 实现**（按住 ⌥ 双击不收起）：`EventTapCallback` tap 线程读修饰键即放行（不吞/不折叠/不建三击 pending）+ `EventTap.clearPendingTitlebarTripleClickForModifierSkip()` 清意图（防"普通双击→⌥第三击→普通第四击"误配）+ 三种系统双击动作的副标题各加"按住 Option 双击不收起"（代码源句与 xcstrings 同步）+ copy-guide 加行 + 新纯测试 `TitlebarModifierSkipTests`（pass）。既有防线（控件角色拒绝、标题栏带校验、0.65s/96pt 三击意图窗）保持不动。
2. **发布基线 0-B**：工作区 = main(5624b68) + 第28批 + #39。`build.sh --stage` 重建候选 → `WindowShade-v1.0.16.zip` **9,858,449 字节 sha256 `47930319…7876f`**、二进制 `784ec4b6…0eed4`、Team FVGLY6W6S4、1.0.16(16)；**包级门禁九步全 PASS**（`gate-0B.log`；0-A 包与 `gate.log` 存 `phase0-archive/`）。
3. **Phase 1–3 复验**（Computer Use 代跑，[gate-0B-verification.md](../releases/v1.0.16-acceptance/gate-0B-verification.md)）：单文档收/展 pass、菜单路径 pass、**#39 ⌥ 判据 pass**；0-B 加验：**设置语言切换立即生效且停在当前页 pass**（第27批卡点 A 在候选上成立）、#39 文案 pass；更新器自动检查 pass；欢迎沿用 0-A（`Welcome.swift` 两基线零改动，已 git diff 核对）+ 0-B 第 1 页实见。
   **勘误（重要）**：0-A 轮"两文档历史雷未复现"的判读**不成立**（那张有改名浮层、证据不足）；0-B 直测折叠后台文档→窗口离屏、原位置无条，与缺陷描述形态一致，但策略 `hiddenIfSingleWindowElseMinimized` 表明多窗走最小化可能是**有意设计**（最小化窗口归刘海排）；工具驱动不了刘海排，故 **inconclusive**，与"滑杆读数位置"一起进用户真机清单（各约 5 秒）。**勿再把两文档场景写成"已验证通过"。**
4. **#40/#39 回复草稿**：[issue-replies.md](../releases/v1.0.16-acceptance/issue-replies.md)（英文+中文，未发布——外发动作留给用户）。发布说明 `v1.0.16.md` 中英双份加了「界面语言（#40）」与「收起不那么容易误触了（#39）」两节。
5. **过程记录（如实）**：本 session 我误用 `git checkout` 撤掉 `Localizable.xcstrings` 的第28批改动（127 条 `say.*` + 6 条 en 对齐），随即用 `.build/localization-tests/strings/` 的编译产物（zh/en 各 500 键）**逐键恢复并核对零差异**（500 键、棘轮 3406、check-localizable/copy-lint 全过），仅 3 条副标题为有意变化；其余第28批文件未被波及（git status 可查）。另：`#39` 首次工具测试因参数形态错误（`modifier` 需数组 + 需 foreground）判为无效并重测；三次 run 因工具护栏 HALTED，均按手册留档未删标记。
6. **未提交未推送**：本批改动（#39 全部 + 第28批 + 文档）仍在工作区。**发布日打包前必须先提交**（标签=源码=包=证据 一致），提交与否听用户指示。

---

## 16. 1.0.16 已发布（2026-10-13，本 session 执行发布日流程）

用户指示"先发布 1.0.16"。按 DEVELOPMENT.md §4–§8 与 runbook 走完：

1. **提交与标签**：`5f6429b`「1.0.16 发布（第23–29批入库）」已提交并推送分支与 `main`（同步推进）；标签 **`v1.0.16` → `5f6429b`** 已推。发布说明去掉草稿标记。
2. **包级门禁**：在待发 zip 上重跑九步全 PASS。**发布关发现**：`ditto` 容器字节不可复现（同 app 树两次打包哈希不同）；解包后 app 树逐文件 sha256 完全一致 → 以**最终上传件** `f28c967764b9c2a8aedec9584a3cad07199397d52a799a269f5ed4e44509f743`（9,858,449B）为准，并记入 [gate-0B-verification.md](../releases/v1.0.16-acceptance/gate-0B-verification.md)（"app 树哈希才是身份，zip 哈希不是"）。
3. **GitHub Release**：`gh release create v1.0.16`（zip + `.sha256` + 说明），**回下载核对哈希逐字一致**。
4. **appcast（首个）**：从官方发布页取 Sparkle 2.10.0 工具并核对 SHA-256（`c2bf58aa…da0c`，逐字一致）；`sign_update`（account `windowshade`）签 zip 得 `edSignature`；新建 `site/public/appcast.xml`（1.0.16 条目，`sparkle:version 16`、minimumSystemVersion 14.0.0、hardwareRequirements arm64、enclosure 指向 Release 附件）并**给清单本身签名**（`SURequireSignedFeed`）；`site/scripts/build.mjs` 给 `_headers` 加 `/appcast.xml → Cache-Control: public, max-age=300`；站点 build+check（43 资产）→ `wrangler pages deploy` → **线上核对**：`/appcast.xml` HTTP 200、`application/xml`、Cache-Control 生效、`sign_update --verify` 退出 0、包 URL 200。
5. **README 双版 + 官网**：下载数字改 1.0.16（ZIP 9.86 MB / 解压 24.57 MB，包里多了更新器）；"开发中"节改口径（1.0.16 已是当前下载版，实时活动/欢迎/隐私页/语言开关在列；未进的只剩英文其余表面、Touch ID、启动台手势、实验项）；官网 `content.mjs` facts 改 `1.0.16 · ZIP 9.86 MB`，`releases/latest` 已解析到 v1.0.16。
6. **未做（等用户）**：beta 频道自用一天与分批推送（`phasedRolloutInterval`）——本版是第一个带更新器的版本，**现有用户不会自动收到**（1.0.15 不联网）；用户真机清单（gate-0B-verification.md 末节 5 项）仍建议在自用时过一遍；#39/#40 的 issue 回复草稿在 [issue-replies.md](../releases/v1.0.16-acceptance/issue-replies.md)，待用户发布。

---

## 17. 第30批：设置面板全量英文化 + 收拾（2026-10-13，用户两次追加"全量迁移至英文"）

用户先把设置面板交来"收拾和整顿"，再追加"请你全量迁移至英文"。按 skill-desk 路由到 `emil-design-eng`（原生面板打磨归它；
`design-taste-frontend` 只管网页、`minimalist-ui`/`high-end-visual-design` 要点名、`hig-*` 本机没装）。

1. **副标题被截的根因与修复**：#39 加长的句子在中文侧没有短句条目，`line()` 会**硬截前 16 字**（"按住 Op"）。
   修法照既有机制：全文留在目录里，行内由 `short` 表给回原短句，多一个 ⓘ 承载修饰键出口。
2. **防漏网判据修正**（`tests/check-localizable.py`）：旧口径把 `WSL10n(zh:)` 的**身份源句**也算漏网，
   于是"把行迁进目录"反而让计数上涨（本页实测裸字面量 66→5，旧口径总数却 +38）。新口径只数**没走目录的裸中文字面量**，
   判据是收紧；基线同口径批前≈3200 → 本批 2317。
3. **设置面板全量英文化**（本轮主体）：
   - 鼠标与触控板页、遥控器页：72 键；两页行构建器从自建（16 字硬截、只有 tooltip）换成共享机制（行内一句 + ⓘ 详情）。
   - 快捷键页、窗口浏览页、效果页、私人 App、有人在看、更新段（`UpdaterCopy` 58 条）全部进目录。
   - **行构建器统一**：`GlobalShortcut.titleText`（逐 case 目录键）让行的**名**也走 `SettingsText`；
     权限行加 `SettingsText` 重载——此前英文副标题被旧 String 路径的 16 字硬截（实拍 "Unpin every pin…"）。
   - **隐私页整体**：面板/模型/值串进目录；**生成链**（`registry.json` 加条目级 `en`，生成器出 `WSL10n`，缺 en 逐字节回退）
     译出 65 条登记项的 8 个字段 + 4 个分组标题，共 **520 条**。
   - **看护也随语言**（用户要求不留缺口）：`build.sh` 把 `WSL10n.swift`/`InterfaceLanguage.swift` 加进看护源集合（都只依赖 Foundation），
     编译好的 `Localization/en.lproj` 一并拷进看护包，看护入口按同一规则解析语言；新读的偏好已登记
     `tools/privacy/registry.json`（隐私检查 730 处 PASS）。
4. **结果**：目录 **1408 键**（中英齐全）、防漏网 **2317 行**、`--check`/`--stage` 编译全 PASS、
   隐私登记与生成件同步 PASS、文案检查 PASS。VM 实拍（改前/改后）：鼠标与触控板页、快捷键页、
   隐私页（含展开详情）全部英文，见 `docs/design-review/2026-10-13-settings-panel/`。
5. **仍未覆盖（属 §9 其余表面，不在设置面板内）**：刘海通知 66 处 `quietNotice` 句子 + 按中文句子判语气的
   `noticeTone`/`contains("权限")`（英文模式下会判错，需按语义改判据）；欢迎窗口的标题/授权页/进度行（~15 条）。
   改动未提交未推送（未得指示不提交）。

---

## 18. 第31批：通知面 + 欢迎流程英文（2026-10-13，本 session；§17 第 5 条的两项清完，但有 not_run）

用户："全量英文，谢谢"→"请你接着做完，谢谢"。§17 列的剩余两项（刘海通知 66 处 + 欢迎窗口）都做了，
并在隔离 VM 里用 Computer Use 实拍英文。**注意：§9 的其它表面（菜单栏/状态菜单、刘海实时活动、
窗口浏览面板、启动台、手势提示）仍是中文，本批没有碰；不写"英语已支持"。**

### 18.1 通知面（本轮先做的部分）

1. `quietNotice` 的语气不再**按中文句子猜**：新增 `NoticeKind { info, done, problem, needsPermission }`，
   由调用点显式传（原来 `noticeTone(_:)` 判 `contains("权限")`，英文模式下必然判错，已删除）。
2. 66 处调用点分 16 个文件迁进目录（`notice.*`：`fold/hotkey/carry/slideOver/launchpad/arrange/shade/
   browser/focus/notch/rescue/loginAtLaunch/probe/foldGuard`…），拼接符 `notice.joiner` 单独给键
   （en 是 `"; "`，不是 `"；"`）。
3. 间接来源一并迁：`WindowBrowserSettings.firstRunHintText`、`WindowBrowserActionPresentation`
   （`browser.action.*` / `browser.outcome.*` / `browser.status.*` / `browser.quicklook.*`）、
   `Notch.foldStatus`、`Rescue`、`UpdaterCopy` 复用键。

### 18.2 欢迎流程（本 session 补齐的部分）

`WelcomeFlow.swift` 原来**整份是中文常量**，`Welcome.swift` 的按钮/插画全是中文裸字面量（上一批只迁了窗口标题与授权行）：

- 文案改**核算属性**（`static var` + `WSL10n.text`）：语言切换时还开着的欢迎窗口能跟着重出；
  `WelcomeView.pages` 也从 `static let` 改核算属性。
- 按钮 `welcome.button.*`（Skip / Back / Continue / Get Started / Not Now）、舞台说明书 `welcome.flow.picture.*`。
- 插画：菜单栏 `welcome.art.menubar`（`%@    文件    编辑    窗口` → `%@    File    Edit    Window`）、
  应用名 `welcome.art.appName`（备忘录 → Notes）、迷你窗口标题 `welcome.art.memoTitle`/`mailTitle`
  （购物清单 → Shopping List、邮件 → Mail）。
- 刘海那两行**复用真提示的键**（`habit.copy.title` + `habit.fallback.copy`、`habit.controlFamily`）：
  舞台演的就是刘海真会说的，两处不许分头写（改动前的注释就是这么要求的）。
- 来处显示名统一：新增 `SwitcherOrigin.titleText`（逐 case 目录键 `origin.windows/ipad/mac`），
  欢迎选项、设置分段、刘海问来处共用；`title` 仍返回中文源句（身份，单测照旧）。
- 刘海问来处提示：`habit.askOrigin.title/sub/hint`（`之前常用 %@？` 等），`HabitCloseButton` 的
  读屏标签/帮助 `habit.close.*`（帮助里的两个名字从各自目录键取，改一处两处一起变）。
- 顺手补批 30 漏的：`shead.browser` 分组标题 `触发`/`外观`/`权限`（原来 3 处裸中文），
  "已排除 %@ 个应用：%@%@" 的 `、` 与 ` 等` 连接词，`@unknown default` 的中文串；
  **并删掉两处畸形嵌套** `WSL10n.text(键, zh: WSL10n.text(键, zh: …))`（批 30 合并时留下的）。

目录 **1524 → 1554 键**；防漏网棘轮 **2180 → 2150 行**（`tests/localizable-ratchet.json`，只降不升）。
校验：`check-localizable` PASS；`run-localization-tests`（1554 键逐键英文解析、无汉字）PASS；
welcome-flow / switcher-origin / release-defaults / quiet-defaults / origin-guess / habit-rules 全过；
`build.sh --check` EXIT=0；`--stage` EXIT=0。

### 18.3 VM 实拍与**修掉的缺陷**（证据：[design-review/2026-10-13-welcome-and-notices](../design-review/2026-10-13-welcome-and-notices/README.md)）

构建 `4872143f4a5037938055fa97620d23a91cf0e66bceaafbe2258a9799dad5f918`（签名 Apple Development G3TN2MBQ2Q），
run `20261013T120624-adae7826`（早期构建 `b04a991c…`、run `20261013T120005-7ffee488` 留作缺陷记录）。

- 欢迎第 1/2/3 步 + `Get Started` 走完：全英文，插画（`Notes File Edit Window`、`Shopping List`、`Mail`、
  岛上两行 `On a Mac, Copy is ⌘C` / `Most shortcuts use ⌘ where Windows uses Ctrl`）完整可读。
- **缺陷**：第三个选项英文名 `Always used a Mac` 比卡片留的宽度长，被裁成 `Always used a M…`（BEFORE 图留档）。
  名字统一改短为 **`Always Mac`**（设置里"之前常用"分段同一个名字），修后完整。
- 通知面：把受控窗口"带到每张桌面"后，岛上说 **`Carried to every desktop`**（绿勾，`.done`）。
- 恢复：受控窗口卷起后从菜单展开，回到 prepare 记录帧 (437,131 673×439)。

### 18.4 未验 / 未做（别当通过）

- **拒绝类通知两句没拍到**：`先展开这个窗口，再带到每张桌面`（卷起后 carry）与 `没有可以带着的窗口`
  （没有前台窗口时 carry）。两次尝试都没复现条件——卷起受控窗口后焦点落到另一扇 TextEdit 窗口
  （日志 `carry: start id=731`），想点桌面却抬起了 Finder 窗口。这两句只有目录级校验。
- **菜单栏兜底通知**没拍到：`Notch.enabled` 出厂默认关（`ReleaseDefaults` 里 `deviceVerified: false`），
  关着时通知落在状态栏标题、只亮 1.4 秒，两次都被自动截图错过。为拍岛上那句，VM 里用产品自己的
  "卷帘页 → 收进刘海"开关临时打开、拍完已关回（`Notch.enabled` → 0）。
- **刘海问来处提示**没有触发路径（要等来处推断跑出来），只有编译与目录校验。
- **§9 其它表面仍中文**：菜单栏与状态菜单、刘海实时活动、窗口浏览面板、启动台、手势提示等
  （棘轮 2150 行里绝大部分是它们；本批只消化了 30 行）。
- 改动**未提交未推送**。

---

## 19. 第32批：§9 剩余用户可见表面全量英文（2026-10-13，本 session；"全量英文，兑现承诺"）

§9 表面清单至此清完（用户可见范围）：菜单栏/状态菜单、刘海全部、窗口浏览面板、启动台、手势、
置顶预览、计时器/媒体卡、授权确认、电量——全部进目录。**目录 2120 键；防漏网棘轮 2150 → 1429 行**
（剩的主要是日志串、多语言菜单匹配词表、QA 探针——不是用户可见文案）。

### 19.1 迁移范围（按面）

1. **菜单**：`StandardMenu`（关于面板 credits、应用/编辑/窗口菜单、卷轴概览）、`MenuBarController`
   （顶层九项、整理▸、已收起的窗口▸、置顶行、Touch ID/面部、退出）。`StatusMenuLayout.fixedTopLevel`
   改核算属性（单测同步）；顶层结构断言照旧。
2. **刘海**：`Notch`（批量收起/放回、切换 App 提示、拖放落点、筛选读屏、折叠数读屏、动作动词与去处、
   等你徽章、收起时的画面）、`NotchRow`（ join/在等你/在跑/额度、13 种活动名、文件架格与右键菜单）、
   `NotchSentence`（有变化/还有 N 件/拷好了/没拷完…）、`NotchActivities`（番茄钟今天第 N 个、会话
   等你/在跑/额度快用完、文件架、用量低、正在进行）、`NotchActivityController`（隔空投送、路线对话框
   与结果）、`NotchActivityView`（播放/暂停/跳过/结束/地图/过去按钮与无障碍）、`NotchLevelSetting`
   （音量亮度三态说明）。
3. **窗口浏览**：Controller（40+ 动作原因句）、Placement（方位名 + 排布结果句）、Actions、ContentView
   （搜索、空态、权限按钮、计数）、CardView、ActionBar、MorePolicy 的键名、Settings（样式名 + 键码）、
   Material、ThumbnailService、Panel、QuickLook、ActionPresentation。
4. **启动台**：View（右键菜单、卸载确认对话框、jiggle 无障碍标签）、Uninstall（面板全程 24 条）、
   Controller（番茄钟/计时器入口卡）、Activities、OpenWith、Library、Today（打开日历、实时活动、
   周日—周六）、Folders、Model（App 资料库 14 个分类名，改 `title(for:)` 逐键目录）。
5. **手势**：GestureHUD（33 个落点档名）、GestureCoach（12 对教学短句/长句）、TrackpadGestures
   （改大小失败、别的 App 占手势、选项表）、DirectionKeyPresets（方向键/按编号展开/已用于/被占用…）、
   MagicTiling(+Run)（铺满/侧拉/收进刘海/别的 N 扇/只有一块屏）、ScrollStrip(Overview/Run)、DockSwipe、
   WindowSwitcher。
6. **其它**：PinnedPreview（9 种失败原因、菜单双态、老板键、面板标题、未命名窗口）、Carry（条与更多
   窗口菜单）、AuthorizationCopy（全部确认/拒绝句）、CountdownTimer(Card/Host)、FocusTimerCard、
   NowPlayingCard、DeviceBatteryCopy（设备名、电量句、耳机分耳）、LidAngleSource（传感器状态）。
7. `NotchSentence.headlineLimit` 首次按语言拆：zh 仍 8 字，en 暂 24/40——**占位，待真机在刘海实看定死**。

### 19.2 语义路由修复（第31批同类，本批四处）

菜单收起/置顶项的图标和提示不再按中文串判（`foldToggleState()` / `currentTargetPinState()` /
`ws2CachedMenuCaption() -> String?`）；`DuoController` 新增 `sensorPhase` 枚举（原按
`case "传感器未启动"` 判）；隔空投送结果改 `ShareOutcome`（原 `text == "已送出"`）；番茄钟
`isRest` 与来源同查 `notch.focus.rest`。

### 19.3 校验与 VM 实拍

- `check-localizable` PASS（2120 键）、copy-lint PASS、隐私登记/隐私页同步 PASS、
  `--check`/`--stage` EXIT=0，bin `86da9f96…`（G3TN2MBQ2Q）。
- **49 个受影响测试 runner 补编 `prototype/Core/WSL10n.swift`**；受影响 53 套件全 PASS
  （含 MenuStructure、Launchpad 全家、WindowBrowser、NotchSentence/Row/Activity/Level、
  PowerFlash、PrivacyPane、AppKit、Localization）。
- 顺手修两个 HEAD 上就有的问题：① 启动台 view/visual-fixture/perf 三个 runner 漏编
  `WS2AppUninstallPlan/Scanner`（编不过）；② `PrivacyPaneTests` 断言 subtitle ≤16 字，
  `app-uninstall` 17 字在 1.0.16 基线就崩——按生成链三处同步缩短为"删 App 连文件进废纸篓"。
- **VM 实拍**（run `20261013T133637-53bbeeb8`、`…134207-d1b76be8`）：状态菜单九项与整理▸子菜单
  全英文（证据 [2026-10-13-english-remaining-surfaces](../design-review/2026-10-13-english-remaining-surfaces/README.md)，
  binding `465dd2e2…`）。

### 19.4 not_run

- **启动台面板实拍**：菜单项标题已实拍为 "Launchpad"，但点击链路三次没把面板打开（CU 会话内
  50 秒截图新鲜度反复 HALT；点击未到菜单，App 日志无记录）——面板内英文（78 键）只有目录级校验。
- 刘海活动、音量亮度条、电量闪现、手势教学、授权卡：句子走目录并过逐键英文解析，触发路径未逐个演。
- 刘海句长英文档（24/40）待真机。
- **英文整体目标**：用户可见表面已全量走目录；未迁移的剩 Conductor/Owned 会话页等**未上线功能**
  与诊断串。改动未提交未推送。


---

## 20. 1.0.16 同版本号重发（2026-10-13 晚，本 session；用户裁定以相同版本号发布）

第30–32批以 `1205a03` 提交入库（159 文件；.zcode 不入库）。用户裁定重发 **1.0.16 原版本号**（只是一个小修复），偏离 DEVELOPMENT.md 第 1 条（不移动已发布 tag / 换包升小版本）——执行记录与已知偏差写在 gate-0B-verification.md 追记：

1. **中途打过一版 1.0.17**（tag/Release 齐全），按用户裁定撤销：Release 删除、远端/本地 tag 删除、版本 bump 提交 revert（`85bfec0`）。
2. **重发**：build 16 重建（bin `a9d7df55…`，DR 与原 1.0.16 逐字相同），包 `e3ab987b…`（10,041,404B）走完 9 步门禁全 PASS；`gh release upload --clobber` 覆盖资产；tag `v1.0.16` 强推到 `85bfec0`；发布说明更新（英文覆盖面口径）；回下载哈希逐字一致。
3. **appcast**：条目重签（`sign_update --account windowshade`，新 edSignature/length，pubDate 2026-10-13），清单签名 verify PASS；wrangler 部署后线上 `/appcast.xml` 与本地逐字节一致、Cache-Control 生效、包 URL content-length 10041404。
4. **顺手修站点构建**：第30批把隐私页生成器改成 `WSL10n.text(...)` 后，`site/scripts/privacy.mjs` 的逐字对照器（只认裸字面量）全部读 undefined、构建中止；已教它拆 zh 源句。README/官网数字同步 ZIP 10.04 MB / 解压 25.25 MB，线上核对通过。
5. **已知偏差（用户裁定接受）**：build 号与已装的 1.0.16 相同，**Sparkle 不会主动提示已装用户更新**；新装和手动检查更新会拿到新包。要主动推就得再按规则升 build。


---

## 21. 第33批：未上线功能的英文适配（2026-10-13，本 session；用户追加）

用户追加"还没上线的功能也做一下英文的适配"。指挥（ConductorSession/Page/View/Settings/Capabilities/ModelPicker）、
静音操作与编程会话（WS2OwnedLaunchController 53 句、OwnedSessionView/OwnedCodexSession/OwnedProtocolHost/
AgentSessionView/CodexApprovalHost/AgentSessions）、遥控与 CarPlay（WS2RemoteHost/CameraChoice/CarPlaySurfaceModel）、
文件架与拖拽（FileDragSensor/FileShelfView/Model/Store）、画中画、日历卡（CalendarPresentation）、
在场与私人窗口（PresenceLockRiskSheet/AwaySummary/NotchFaceObservations）、输入资格
（WS2InputEligibility/InputDeviceKind/ScrollInstallPolicy）全部进目录。

- 目录 **2120 → 2500 键**；防漏网棘轮 **1429 → 1034 行**。剩余占位：诊断与日志串、QA 探针与设计夹具、
  历史迁移对照表（StandardMenu.legacyLocations）、文件架磁盘目录名（改名会动用户已有文件）。
- 两处按中文串判逻辑改掉：提示音令牌（`ConductorSoundToken` 出 `toneN`/`beatN`，播放器优先按令牌取拍数，
  历史中文标签兜底）；`ConductorCapabilities`/`ConductorSession` 的句子全走目录。
- 校验：`check-localizable` PASS（2500 键）、`--check` EXIT=0（隐私登记 730 处、文案检查均过）；
  **15 个新涉及的测试 runner 补编 `WSL10n.swift` 后全 PASS**。
- **未验**：这些功能出厂默认关，VM 里没有触发路径——只有目录级与编译级校验，无屏幕证据；
  等它们各自上线前的那一批再实拍（与 §19 同口径）。提交 `1ee2684`，已推分支与 `main`；
  **没有跟着重发 1.0.16**（这些串在出厂默认关的功能里，对已发布包的用户可见行为没有影响）。

---

## 22. 第34批：英文适配收尾复核（2026-10-13，本 session；用户指出"都没做完"）

上一批说"完成"是**说早了**：用户指出还有可见中文。复核后补迁了两类东西：
(a) 上一批漏掉的用户可见串——卷帘条（双击提示、三个自定义操作、VoiceOver 帮助与计数、条窗口标题）、
媒体卡（正在下载/正在拷贝/时长与剩余读屏）、用量句（剩 N%、恢复时间、周几、N 分钟后）、
面部与倾斜传感器提示、系统提示音名、看一眼面板、私人 App 默认名、离开就锁倒计时、Rectangle 迁移提示、
语音备忘录活动行、Duo 预览与状态行、折叠效果失败原因、Touch ID 面板、侧拉菜单与读屏、番茄钟休息句、
CarPlay 重连与解码错误、分割/侧拉把手读屏等；
(b) **纠正自己的误判**——`InputStatusCopy`/`WS2InputEligibility`/`InputDeviceKind` 的句子是给设置面板
按身份查目录的**语义身份**，上一批套 WSL10n 会让面板映射不上，已还原并补上"开着"分支。

**现在的判据（可复核）**：`prototype/` 里"像界面文案、又还写着裸中文"的行 **只剩 2 行**——
`NotchActivitySources` 匹配语音备忘录按钮标题的多语言列表（要同时含中英，因为系统 App 的语言与产品语言无关）。

棘轮 1034 → **892**，剩余构成写进 `tests/localizable-ratchet.json` 的 note：身份表 472、QA 探针与设计夹具 230、
日志与诊断 31、磁盘目录名 17、数据匹配表 10、其它约 150（多行 WSL10n 调用的续行被行判据计入）。

校验：目录 **2627 键**（`run-localization-tests` 逐键英文解析 + 无汉字）、`--check` EXIT=0、
受影响 49 个 runner 补编 `WSL10n.swift` 后全 PASS（`run-part4-core-tests` 在 HEAD 上就编不过，属既有问题）。
**仍未做**：这些未上线功能在 VM 里没有触发路径，只有目录级/编译级/单测证据，没有屏幕截图；
已发布的 1.0.16 包里没有这些串（要不要为此再切一版由用户定）。

---

## 23. 第35–37批：设置面板收尾与三、四次同版本号重发（2026-10-13 夜 – 10-14 凌晨）

**第35批**（提交 `2bd6284`）：撤回第34批 `content()` 里的 hugging 实验残迹；新增 `WS2SettingsCopy.pinInfoTrailing`
把 ⓘ 钉在内容列右端（覆盖全部行构建器与页头豁免）；Conductor 页行从 String 路径迁到 `SettingsText`
目录路径（修掉英文 16 字硬截与整页无图标）；`symbol(for:)` 词表 +17。

**第36批**（提交 `c395338`）：`symbol(for:)` 词表再 +38（Effects 预览卡四行、Roll up 十五行、Shortcuts 排列区、
Privacy/Updater 零散行），全部 `NSImage(systemSymbolName:)` 实测；`DuoSettingsWindow.makeRow` 补
edgeInsets/行高 ≥48（Effects 页分隔线贴文字的根因）；21 条文案通俗化（zh 双写逐字同步、en 只改表、
超预算走 shortEn）；棘轮 932 → 969。

**重发第 3、4 次**（提交 `9a1c479`、`c4a2516`）：均以同版本号 1.0.16 覆盖——
重建包 → 9 步包级门禁（DR 与原 1.0.16 逐字一致）→ `gh release upload --clobber` → `git tag -f` 强推
→ appcast 条目重签 + 清单重签 → wrangler 部署 → README 双版数字同步 → 回下载哈希核对。
第 3 次包 sha256 `10a85c6f…`（9,765,838B）、第 4 次 `852501c7…`（9,771,300B）。已知偏差同 §20：
build 号不变，Sparkle 不主动提示已装的 1.0.16 用户。`sign_update` 工具在临时目录里丢过一次，
用 `docs/update.md` 记的 Sparkle 2.10.0 发布包（sha256 `c2bf58aa…`）重解即可，不依赖任何 worktree。

**第37批**（提交 `8f09898`）：新增 `WS2SettingsRow` 统一拼设置行（内容列 + 控件列，八处行构建器全改走它）；
ⓘ 成列规则收敛为「同一张卡里按最宽的开关/按钮定一条竖线」——分段、弹窗、输入框和复合控件不参与定列，
否则开关行上会留出上百点空档（实测：参与定列时 Roll up 全页 ⓘ 被一个 423pt 的控件拖到 x=1039，
只认开关/按钮后全页回到 x=1560 且贴着开关）；侧栏 `Mouse & trackpad`（`computermouse`）与
`Conductor`（`switch.2`）补图标（`WindowShadeSettingsSection.symbolName` 里这两节此前写死空串，
用户截图点名的就是这个）；清掉上一批两条过期 shortEn。

**注意**：棘轮现在是 **969/969**（顶到上限），下一次再加裸中文字面量必须同时说明理由并上调。

**证据**：每批 `./prototype/build.sh --check` EXIT=0；离屏渲染逐页核对（`/tmp/shots-36c`、`/tmp/shots-44`）；
`run-settings-tests.sh`、`run-localization-tests.sh` PASS；各次重发的门禁输出与回下载哈希记在对应提交信息里。
本机 `/Applications/WindowShade.app` 已装 `8f09898` 的构建（就是第 4 次重发的那一份）。

**第38批与第 5 次重发（2026-10-14 凌晨）**：提交 `64d11a7`——`pinInfoTrailing` 收进
`WS2SettingsRow` 构造函数（行容器成为钉 ⓘ 的唯一所有者，调用方不可能漏）；DuoSettingsWindow
最后三个老行构建器（String 版 makeToggleRow、makeControlRow(labels:)、makeActionRow(labels:)）
迁入统一行容器——Advanced 页 Actions 卡 ⓘ 悬空即它们漏钉；Preferences 日历行与欢迎页日历行
同迁；Remote 页三处 `indent: true` 去掉（子行图标对齐）。教训记两条：①「ⓘ 固定成列」与
「ⓘ 贴控件」在控件宽窄不一的卡里不可兼得，终态规则是**永远贴控件**（同宽卡的列是自然结果
不是目标）；② 验收必须用**已装 app 的渲染**，构建目录渲染不作数（第37批前一直混用）。
第 5 次同版本号重发：tag v1.0.16 → `64d11a7`，包 sha256 `9676b485…`（9,767,275B），
9 步门禁全 PASS（DR 逐字一致），appcast 重签部署，README 数字同步（ZIP 9.77 MB /
解压 25.10 MB）。已知偏差不变：build 号 16，Sparkle 不主动提示已装用户。

**第39批：繁体（台湾用语）全量适配（2026-10-14 早）**，提交 `008bdca`（代码）+ `8aee55a`（重发记录）。

- **语言层**：`WSLanguage` 加 `.zhHant`；`InterfaceLanguage.language(forSystemTag:)` 按文字系统分流
  （`zh-Hant`/`zh-TW`/`zh-HK`/`zh-MO` → 繁体，其余 `zh*` → 简体，非中文 → 英文）；设置的语言行加
  「繁體中文」；`WSL10n` 的译文目录改成**按当前语言找**（`Localization/en.lproj` / `zh-Hant.lproj`），
  找不到就回落简体源句（与英文同构）。
- **文案**：2631 键全部补 `zh-Hant` 列，由仓库里的可复跑流水线生成：`tools/localize/zh-hant.py`
  （OpenCC `s2twp` + 台湾专名表）+ `tools/localize/short-hant.py`（繁体短副标题表，键是繁体全文，
  与 `short` 表对称）。专名表覆盖 Apple 台湾官方术语与我们的产品词（指揮中心/選單列/標題列/瀏海/
  視窗/子母畫面/輔助使用/快速鍵/按兩下/拖移/Finder/AirDrop/鎖定畫面/權限/工作階段/手把/這台 Mac/
  台而非臺……），写进 `docs/copy-guide.md` 新增的「台湾用词（繁体层）」一节，并说明两层词表的关系：
  **简体表的「不要用」清单只约束简体层**（例：简体禁「巧控滑鼠」，繁体层就该用它）。
- **校验**：`check-localizable.py` 新增 zh-Hant 规则（齐全、`%@` 一致、不得含简体专用字）；
  `InterfaceLanguageTests` 断言 zh-Hant/zh-TW → 繁体；`LocalizationTests` 逐键走真实目录出繁体。
  棘轮 969 → 1034（shortHant +64、「繁體中文」+1）。前置依赖：本机装了 `opencc`
  （brew；`s2twp` 配置），脚本走 CLI，没有它就跑不了流水线。
- **踩过的坑**：① 生成短句表的正则最初把 `tableSymbols` 整张表吞了（`[\n` 被吃进捕获组，
  收尾锚点 `\n    ]` 因而匹配到下一张表）——已修，并在脚本里注释；② 隐私登记检查会把**注释里**
  的 `UserDefaults` 当新调用点，注释措辞要避开。
- **README**：新增 `README_TW.md`（由 README_CN 经同一流水线转写 + 台湾用词），三版互链。

**第 6 次同版本号重发**：tag `v1.0.16` → `008bdca`，包 sha256 `20db409a…`（9,831,118B），
9 步门禁全 PASS（DR 逐字一致），appcast 重签部署，三版 README 与官网数字同步
（ZIP 9.83 MB / 解压 25.37 MB）。**未做**：官网的繁体页（`/tw/` 与繁体 history）——
`site/scripts/{content,chrome,history,build}.mjs` 目前是「中文/英文」二元的（到处用 `en` 布尔），
要加第三语言得把语言串透这几处；首页文案 148 条可照 App 的流水线转，history 那篇长文的繁体
版需要单独过一遍。这批先发 App。

**第40批：官网繁体页（2026-10-14）**，提交见上一条。站点原来只有中文/英文两套（脚本里到处
是 `en` 布尔），这次把语言串透 `chrome/history/content/build` 四个模块：`LANGS` 表统管路径与
切换标签，`/tw/` 与 `/tw/history/` 上线，hreflang 三条 + x-default，sitemap 补两条。
繁体文案由 `tools/localize/site-zh-hant.py` 从站点全部脚本的字面量 + `content.zh` 抽出
（465 条）走同一套 App 流水线，写成 `site/scripts/zh-hant.json`；繁体页面生成后再整页过一遍
对照表（兜住 `launchpad.mjs` 这类模块里直接写的串），并把同一张表注入 `window.WS_TW` 供
`history.js` 运行时用。核查：线上两页 `<html lang="zh-Hant">`、可见文案零简体残留
（`窗口` 0 处、`視窗` 51/133 处）。**注意**：页面里 `window.WS_TW` 那个 JSON 的**键**是简体
（对照表本来就是简→繁），扫描「是否还有简体」时要先把这个 blob 剔掉，别误报。
