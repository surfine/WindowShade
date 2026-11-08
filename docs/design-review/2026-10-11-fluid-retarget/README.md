# 第26批：刘海中途反向衔接 + 隐私登记行列对齐

[当前身份与限制](validation.json) · [流体重定向实现计划](../fluid-retarget-plan.md) · [第25批基线](../2026-10-11-privacy-composition-and-motion-baseline/README.md) · [隐私列设计稿](../../design-drafts/隐私内容列.md) · [Continuous 记录](../CONTINUE.md)。

本批改两处生产源码：刘海变形动画中途换目标（反向/再次改向）的方向与逐轴速度衔接，以及隐私登记行里按标题关键词偶发挂图标的旁支。两处都有真实组件探针与独立数值核对，但没有真机可见动画、签名 App 生命周期的验收。

身份与全部 SHA 见 [validation.json](validation.json)（`binding_sha256` = 对 `source_sha256` + `evidence_sha256` 两份字典做规范 JSON（键排序、紧凑分隔符）后取 SHA-256，公式记在文件里，可复现）。

## 生产改动（after SHA）

| 文件 | before | after |
|---|---|---|
| `prototype/Core/FlickMotion.swift` | `ddca64b4…`（见 `.statem/history-design-twentysixth-round/source/before-sha256.txt`） | `44404b5bc6cec700ddb6547d5c1af273ed9ca9191d7b629af023f304ebcee3f0` |
| `prototype/App/Notch.swift` | `c49701ac…` | `a031697bb416b41668eed28c7b4ab7685e8d1a2e37b38426ab5ef2cb25937890` |
| `prototype/App/WS2PrivacyPane.swift` | `6f81de16…` | `2e4c466f87c17e3b8a12b5f54f091ef7ad58dab28b9642db5f9d4a25fda5b437` |
| `prototype/App/Motion.swift` | `ce92dee8…` | `ce92dee8…`（未改；只在允许清单里） |

**动效（`FlickMotion.swift` + `Notch.swift`）**

- 新增 `MorphRetarget`（`FlickMotion.swift`）：按实际 `CASpringAnimation` 的 mass/stiffness/damping 与 `FlickSpring.state` 求**带符号**瞬时物理速度；`handoff` 把速度换算成逐轴的归一化 `initialVelocity = −v_物理/剩余行程`，没有在飞的旧动画时保留调用者初速度；剩余行程 ≤0.5 点但速度 >1 点/秒时生成**有界** kick 关键帧（同一弹簧解采样、时长 ≤1.3s、端点钉住，尺寸轴下界用速度二分削减幅度、保方向）；`limitingFloor` 对弹簧路径的尺寸/圆角轴同样限速。
- `Notch.swift`：`morphVelocity`（调用间平均速度、丢符号）删除。`performMorph` 在形状真正开始时重读 `island/clip/keyLine/keyMask` 的呈现层，`pendingExitMorph` 不再存旧 `presented`；五个标量 keyPath（position.x/y、bounds 宽/高、cornerRadius）各挂自己的加法弹簧或 kick，`beginTime` 用 `layer.convertTime(CACurrentMediaTime())` 显式对齐到同一刻；肩仍是自有路径（本批不动它的物理）；Reduce Motion 不挂形状动画、无空闲定时器。
- 第25批证据的缺陷（入向 −20.405 点/秒时新目标反向 +20.405 点/秒、`initialVelocity` 仍 +10.327）即本批修复对象。

**隐私（`WS2PrivacyPane.swift`）**

- `PrivacyRowView` 删掉 `WS2SettingsCopy.symbol(for: row.label)` 关键词挂图标的旁支（第25批实测 `focus-preferences` 因中文关键词多出的 38 点缩进）。字段、字体、值列省略、开关、授权按钮与只读/来源策略未动。

## 证据与核对

- **纯数学核对**（`math/`）：`MorphRetargetMathPreview.swift` 只链接 `FlickMotion.swift`，用独立 RK4 数值积分对照解析解；20 组名/69 条记录，含反向符号、零行程 kick、下界削减（clipped −33.49 ≥ −33.5、unclipped −39.69 且方向保留）、maxVelocity 上限、`liveVelocity` 一致性。`run.log` = `PASS`；`math.json` 与探针二进制 SHA 记录在同一目录（复跑逐字节相同）；首跑失败原件在 `math/failure.txt`（判据差 2 处，修前留档）。
- **组合原生 QA**（`native/`）：一个入口（`tools/design-qa/Batch26CombinedEntry.swift`，SHAs 见 `Batch26CombinedEntry.inputs.json`）在同一 `NSApp.run` 里顺序跑隐私页 12 帧与动效 62 条记录，Swift 6 / strict / warnings-as-errors 编译生产全源（`sources.json` 518 项逐文件 SHA 当前）。
  - **隐私**：12 帧（2 外观 × 收起/展开 × 3 滚动位）41 登记行/4 组/展开 9 个自制开关；`focus-preferences` 的 header x = −2，与其它 40 行一致（第25批为 36）；详情列 x 全为 61。
  - **动效**：62 条记录全部隐藏宿主/主线程/零动作。反向与再次改向的起点、速度都对照独立 RK4：位置差与速度差全部在容差内（速度差实测 0.000，位置差 ≤1.144 点 = 4.0ms 读取偏差 × 瞬时速度）；"只改宽度"一跳宽度轴 nv=2.4301 ≠ 其它轴 12.408；停稳后再起跳保留调用者初速度（0）；kick 为关键帧、全程曲线与 RK4 最大差 0.19 点；取消不重放旧退场回调（聚合计数 23 键全为 1，`regular-cancel-close` = 0）、新内容保留；富内容延迟形状实际晚 0.1566s 开始且分段预测与实测吻合（最大 0.648 点）；reduced 模式零形状动画、呈现层恒等于模型。
  - **分段解析预测**：6 条轨迹对实测呈现层的最大差 0.327 / 0.146 / 0.062 / 0.145 / 0.648 / 0.239 点；这是"位置与速度连续、富内容延迟起点从实际位置开始"的直接证据。
- **消费者首跑失败原件**：`native/consumer-first-failure.txt`（9 条判据错误，产品配置经原始数据核对正确；修正判据后 `PASS`，见 `native.log` 与 `native-exit.txt` = `exit=0`）。
- **图像**：12 张 PNG 累计 2.61MiB；主模型实际查看浅色收起中段/底帧、浅色展开底帧与深色展开底帧（`light-collapsed-middle`、`light-collapsed-bottom`、`light-expanded-bottom`、`dark-expanded-bottom`），确认 `focus-preferences` 行纯文字、与上下行同列、详情子行对齐。

## 完整优化构建

`bash prototype/build.sh --check`（Swift 6 / strict / warnings-as-errors / `-O -whole-module-optimization`，不签名）在本批 3 个生产文件改完后**新跑**（非复用）：`exit=0`、519 项输入构建前后零漂移、0 错误、256 条既有并发/诊断警告保留。见 `native/build-check-exit.json`（含 UTC 与前后输入对比）与 `native/build-check.log`（首条诊断为 `ArrangeController.swift` 的既有 Sendable 警告）。

## 未覆盖 / 不成立的声明

- 没有签名安装运行产品、没有真机刘海动画、没有帧率/输入延迟/合成可见性；隐藏窗口与层配置只证明配置与呈现层数值。
- 肩部（shoulders）与 companion 仍是各自路径，本批未同步其逐轴速度。
- 英语未启用（沿用整体目标）。
- 隐私页是自有宿主中的真实 Row 组件，不是真实 Settings Page；没有真实权限/资料/偏好读写。
- 数学、配置、静态帧、消费者检查各自只覆盖自身范围，不合并成"Apple 级流畅"。
