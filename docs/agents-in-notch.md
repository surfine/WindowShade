# 刘海里的编程会话（吸收 Open Island）

2026-10-03。Aaron：“指挥模式请你将 open-vibe-island 的功能给整合进来，但是不能变成大杂烩，要运用奥卡姆剃刀，只取有需要的部分，
并且保持整个 app 干练和简单易用，菜单栏的菜单也是，不可无节制扩张。”

- 设计稿：[看与指挥](https://claude.ai/artifact/9mbRLt1QGpsKLKip991Xe3)（同一页里还有菜单的改法）
- 菜单：[menu-bar.md](menu-bar.md)
- 指挥模式：[conductor-v2.md](conductor-v2.md)
- 用量：[usage.md](usage.md)

## Open Island 是什么

[Open Island](https://github.com/Octane0411/open-vibe-island)（GPL-3.0，Vibe Island 的开源版）把 AI 编程助手的会话放进刘海：

- 在跑、等你批准、完成；
- 在刘海里批准权限；
- 一点就跳回那个终端或 IDE。

它支持 13 种助手、15 种以上终端。数据来源是各助手的 hook：hook 调起一个小命令行，经 Unix socket 把事件交给 App；App 没在跑时 hook 照常放行（fail open）。
Codex 桌面版另外接了 app-server 的 JSON-RPC。它还有用量面板、通知模式、自己的设置窗口、自己的更新器。

**许可是 GPL-3.0，WindowShade 是 MIT，只借思路，一行代码都不拷。**

## 取什么，不取什么

| Open Island 有的 | 取 / 不取 | 为什么 |
| --- | --- | --- |
| 会话状态：在跑、等你、完成 | **取** | 这就是“看”；指挥模式是“指挥”，两半合起来才完整 |
| 在刘海里批准权限 | **取** | 和指挥模式的放行是同一套：普通点一下；高风险用 Touch ID |
| 一点跳回那个终端 | **取，但用 WindowShade 自己的本事** | 找窗口、去别的桌面、从刘海放回窗口，本来就是我们的本行；不为 15 种终端各写一套 |
| hook + 小命令行 + Unix socket，fail open | **取** | 最省事、最稳；App 没开时助手照常工作 |
| Codex app-server 实时轮次 | **取** | 指挥模式本来就要接 |
| 13 种助手 | **只取 Claude Code 和 Codex** | Aaron 在用的就这两个；Qoder、Qwen Code 这类和 Claude Code 同格式的，以后几行配置就能加 |
| 15 种终端的精确跳转 | **不取** | 先跳到窗口；终端 App 自己有标签页的，第二步再说 |
| 用量面板 | **取，但收窄成会话卡与恢复提醒** | 原先写「不是窗口的事」。2026-10-06 收窄成有界范围：只做现有会话里的用量卡与恢复提醒，不做独立统计软件，不另开宿主；见 [usage.md](usage.md) |
| 通知模式、单独的面板 | **不取** | 刘海就是面板 |
| 自己的设置窗口、更新器、多语言框架 | **不取** | 都已经有了 |
| 从对话记录文件里扫会话 | **暂不取** | hook 已经够用；扫文件要读你的对话内容 |

## 在刘海里长什么样

编程会话是一种**持续活动**，和音乐、番茄钟并排，最多三个，两指横扫切换。用符号加短句。

| 状态 | 紧凑 | 规则 |
| --- | --- | --- |
| 在跑 | 左：终端或 App 的图标；右：转圈 + 项目名 | 不抢位置；有别的活动时只是三个中的一个 |
| **等你** | 左：图标；右：琥珀色点 + **等你** | 这是唯一会主动展开的：短暂提醒，同时有提示音（和番茄钟共用开关） |
| 完成 | 短暂提醒：`checkmark.circle.fill` **WindowShade · 完成**，副句“改了 3 个文件” | 4 秒；那扇终端窗口如果收着或在别的桌面，提醒里带一个“过去” |
| 好几个会话 | 右边是个数 **3**，带状态点 | 展开是一排：项目 · 助手 · 状态 · 多久了 |

**展开（指针停在刘海上）**：一排会话卡片，每张写项目名、助手（Claude Code / Codex）、状态、最后一句（截成一行）。

- 点一下卡片：**过去**。WindowShade 找到那扇终端窗口；收着的、最小化的、别的桌面上的都能找回，并把它放到眼前。
- 卡片上停一下：**看一眼**那扇终端，和刘海那一排一样。

**等你批准**：刘海展开，写清楚四件事：哪个助手、哪个项目、要做什么（命令或文件，一行）、风险。

| 风险 | 怎么放行 |
| --- | --- |
| 普通（读文件、跑测试、改项目里的文件） | 点 **允许一次**；或点 **去看看**，跳到终端，在那里决定 |
| 高风险（推送、删除、联网、改项目外的文件） | 点 **用 Touch ID 允许**（坐在 Mac 前）；遥控器上照指挥模式：点一下再念短语 |

- 没有“总是允许”。键盘快捷键不能放行，防止手正在打字时误按。
- 超过 2 分钟没人管：退回到终端里原来的提示，助手照常问你；刘海收起，留一个琥珀点。

**和指挥模式的关系**：指挥模式里“选会话”的列表，就是这里看到的会话。用遥控器时，画手势、说话、发出去、停下都作用在选中的那个会话上。
坐在 Mac 前不用遥控器时，刘海也能看、能批准、能过去。

## 接上 Claude Code 和 Codex

设置 → 指挥模式 → “在刘海里看 Claude Code 和 Codex”，旁边一个 **连接** 按钮：

1. 点了先给你看会改哪个文件、加哪几行（`~/.claude/settings.json` 的 hooks、`~/.codex/config.toml`），确认后才写。写之前把原文件备份到旁边。
2. 写进去的只是调用 `WindowShade.app/Contents/MacOS/ws-hook` 的几行。这个小命令行只做一件事：把事件经本机 socket 交给 WindowShade；连不上就立刻退出，返回“放行给原来的流程”。
3. **断开** 按钮把加的那几行原样删掉。卸载 WindowShade 前，设置里也提醒先断开。
4. 等你批准的那种 hook 会等 WindowShade 的回答，最多 2 分钟，超时按“交回终端”处理。

## 隐私

- hook 送来的命令、文件路径、最后一句话，只在内存里，用来显示；不写日志，不存盘。
- 不读对话记录文件，不联网，进隐私一栏的登记表（“你同意后才读的”：你点了“连接”之后）。

## 能耗

- 没有会话时零开销：socket 只在有事件时唤醒；不轮询进程表。
- 在跑的转圈用 Core Animation；刘海不刷新文字，只有状态变化时才刷新。

## 做的顺序

| 步 | 做什么 | 谁 |
| --- | --- | --- |
| A1 | 纯逻辑：会话表（来自 hook 事件）、状态机（在跑 / 等你 / 完成 / 断了）、批准请求的一次性绑定与 2 分钟超时 | DeepSeek |
| A2 | `ws-hook` 小命令行 + 本机 socket 服务，fail open；“连接 / 断开”改配置文件（先给看差异、先备份） | DeepSeek 写，主模型复核（改用户配置文件，高风险） |
| A3 | 刘海里的编程会话活动：紧凑、展开、等你、完成；点一下“过去”接 WindowShade 的找窗口 | DeepSeek 写，主模型复核动效 |
| A4 | 批准接授权账：普通点一下，高风险 Touch ID | 主模型 |
| A5 | 和指挥模式共用会话列表 | 主模型 |
| A6 | 用量卡与恢复提醒（收窄范围见 [usage.md](usage.md)）。待出稿、待进词表后再排；不占 A1–A5 的顺序 | 待定 |

## 2026-10-19 App 拥有的 Claude 会话（只读起步）

`prototype/App/WS2OwnedClaudeSession.swift` 启动本地
`claude --print --input-format stream-json --output-format stream-json --verbose
--include-partial-messages --permission-mode plan --permission-prompts none`。
每次发送一行：

```json
{"type":"user","message":{"role":"user","content":"…"},"parent_tool_use_id":null}
```

按行解析 `system/init`、`stream_event` 的 `text_delta`、`assistant`、`result`、`permission_denied`
（`prototype/Core/ClaudeWire.swift`）。停止本轮＝停掉子进程；下一次发送用 `--resume <session_id>` 接回。
工具审批的 host 协议没有公开文档，本阶段不做；`permission-prompts none` 下会被拒的操作列在
result 的 `permission_denials` 里。假 CLI 的进程级验收在 `tests/run-claude-session-tests.sh`，不发真实模型请求。
页面级测试可用 `WINDOWSHADE_CLAUDE_EXECUTABLE=<可执行文件>` 覆盖发现路径（只影响该 App 进程，预览功能）。

## 2026-10-26 WS2/2.1 对照规格的缺口盘点（机器可做的部分已收口）

对照 Silent Identity Spec v2（~/Downloads/WindowShade-Silent-Identity-Spec-v2.zip）逐条核过：

- **142 条命令**：目录 WS2SilentCatalog 与规格逐条一致（id 集合零差异；effect/confirmation
  在 snake_case→camel 归一后零差异）；每条在 WS2SilentProductPort/WS2SilentApply 都有执行路径。
- **237 条验收**：规格自己也标 not_run，且除 16 条（手机批准扩展，Aaron 已决定不做）外，
  given 全部含「真实 App 构建」前置——都要真机+真人，机器无法代验。
- **口型链路完整**：录制探针（tools/probes/MouthRecordingProbe + run-mouth-recording.sh）、
  模板/合并工具（MouthProfileTool + mouth-profile.sh）、App 侧消费
  （WINDOWSHADE_MOUTH_PROFILE + WINDOWSHADE_MOUTH_CAMERA 两个环境变量）都在，
  只差 Aaron 本人对着镜头录个人词、生成 profile。
- 本轮新增的两件产品功能（此前规格有画面、代码没有）：「认你」指示（f688fe9e）、补光圈（cbeedf0f）。
- r00–r04 静音集成全 PASS；build --check 退 0。

**结论：WS2/2.1 里不依赖 Aaron 硬件/本人的软件件已经收口。** 剩下的每一项都卡在：
真机锁屏（认你/锁屏开合）、真人录词与真人攻击测试（PAD/重放）、真手机/手表（F1 蓝牙身份）、
Aaron 拍板放开的系统解锁与代填（D11）。没有可以再「抢先做完」的隐藏件。

## 2026-10-26 A2「连接／断开」兑现（写 ~/.claude/settings.json 的完整流程）

「Claude Code 的配置」那一行从只给「拷贝配置」补齐成规格 A2 的样子：

- **连接**：先弹差异页——要改哪个文件、会先在旁边存一份带时间戳的备份（同秒撞名往后加序号，绝不覆盖）、
  将加入的每一行（六个事件、各自的 timeout）；点「连接」才写，取消什么都不动。
- 写入走保守合并（WS2HookConfiguration）：原子的、0600；**只增删自己的行**——配置里有别的工具的 hook、
  陌生的结构一律拒改（拒改时原文件一个字节不动，界面说明改走手动拷贝）。
- **断开**：把当初加的那几行原样删掉，别人的 hook 和其它设置原样保留；同样先备份。
- 连接着的时候副句提醒「卸载 WindowShade 前先在这里断开」。
- 「拷贝配置」保留，给不想让 App 碰配置文件的人。
- 状态判定按结构查（文件里有没有我们的命令），不比序列化字节——空文件不会误报已连接。

机器验收：`tests/run-hook-config-store-tests.sh`（临时 HOME：空文件连接、0600、断开清干净、
别人 hook 保留、断开只剩别人的、陌生结构拒改且原样，全 PASS）。
隐私登记补了读写点（agent-hooks），隐私页同步。
真实 Claude Code 对这份 settings.json 的接受度仍要一次真连接确认。

## 2026-10-28 F1-B 落地：HomePlay 桥（pair-verify 级在场信号）

- HomePlay 接收器（322e82b）：`CarPlaySession.phoneAuthenticated` 只读投影 + 每秒读内存投影、
  翻转才广播 `{"type":"phone-presence","verified":…,"generation":…}`；session-tests 仍全过。
- WindowShade：`WS2HomePlayPresenceSource`（本机回环 WebSocket，只读布尔，不存设备名/地址），
  与 IOBluetooth 轮询**双源并存**，都喂同一个 PresenceLock reducer；HomePlay 没跑时它沉默重连。
- 「离开就锁」从此拿到的是密码学级「那台手机在」的信号（F1 第 2 条的 B 路线），不再只是连接状态。
- 测试 `tests/run-homeplay-presence-tests.sh`（10 条：解析/去抖/事件序列/拒非法负载）全 PASS；
  隐私登记 presence-bridge 已入表；`build.sh --check` 退出 0。
- 需要你：HomePlay 接收器与 iPhone 保持配对状态下跑一次，观察 WindowShade 的「离开就锁」倒数
  是否随手机验证状态翻转（真机对照，5 分钟）。
