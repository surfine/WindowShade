# 隔离运行验证：2026-09-22

环境为 macOS 27.0（26A428）、arm64、Apple Swift 6.3.3。历史性能记录基于 macOS 26.5，不用作本轮前后速度对照。

本轮用与日常应用相同的 Apple Development 身份执行 `bash prototype/build.sh --stage`，产物为 `.build/duo-validation/WindowShade.app`，版本 1.0.14。签名严格验证通过。日常 `prototype/WindowShade.app` 主程序前后 SHA-256 一致，没有替换或重启它。

首轮隔离主程序 SHA-256：`866b7d3437ad0b56bf8db86613ec7aa70464f523c18fca5d8430715ae222459f`。
Swift/Metal 源码清单与组合哈希保存在 `.build/quality-validation/source-manifest.json`，组合哈希为 `89f02739fc849dce9d7045ff9c67164017472ce724a54d5963d8225de18c1adc`。

## 实际结果

下列参数均传给隔离应用的 `Contents/MacOS/WindowShade`；原始输出保存在 `.build/quality-validation/`。

| 参数 | 结果 | 证据范围 |
| --- | --- | --- |
| `--window-browser-identity-probe` | 25 项通过 | 真实 AX 元素、错误 ID/PID、伪造身份、关闭窗口与旧代数拒绝；不是用户窗口动作测试 |
| `--window-browser-capture-probe` | 单窗口捕获通过 | 蓝色测试窗口被红色窗口遮挡后仍捕获蓝色；card 461×320、318ms，selectedLarge 840×584、103ms。每档只有一次样本，不能推出 p95 或稳定提速 |
| `--duo-window-test --no-animation` | 通过 | 独立测试进程窗口的隐藏、卷帘条显示、恢复验证 |
| `--duo-window-test` | 通过 | 动画收起/展开、准备阶段反转、拖动卷帘条后按新位置恢复、同步恢复取消动画 |
| `--duo-window-test --edge` | 两次均失败 | 收起动画成功；恢复封面没有及时呈现，触发无动画回退 |

## 边缘失败定位

首次日志 `fold-edge-native.log`：07:16:06.801 显示恢复封面，06.846 GPU ready，07.321 visible presentation timeout。随后回退展开，实际和目标几何均为 `(0,435 1710×452)`，07.488 清除恢复记录。失败是没有完成要求的动画呈现，不是这次窗口没有找回或几何丢失。

复跑结果相同，详细日志为 `fold-edge-retry-native.log`。探针当前把几何不匹配和动画回退合并成一条错误；判断失败原因必须结合原生日志，不能仅凭最终一句推断窗口恢复失败。

## 首帧呈现修复与复验

未改代码的诊断复跑曾成功一次，日志 `edge-before-diagnostic-native.log`，因此此前两次失败属于间歇现象，不能解释成边缘几何必然失效。

代码检查发现恢复封面使用静态图：透明状态下 GPU 完成后，只在变为可见时补一次 invalidate；如未得到有效呈现，此后没有新内容使 renderer 再变为 dirty。修改为：GPU 就绪且需要展示、但尚未确认首帧时，每个现有显示时钟 tick 继续 invalidate；收到呈现回调后即回到原来的按需绘制。没有新增计时器、提高帧率或延长 500ms 预算。

修复后的隔离二进制 SHA-256 为 `98ff87ba11f10ab9b6d2589ef220713dd861685d76f2ec15e9250823e80f5b2e`，完整优化构建和签名验证通过。真实 `--duo-window-test --edge` 连续两次通过，恢复封面从 show 到可见回调分别约 126ms、135ms；日志为 `edge-represent-1-native.log`、`edge-represent-2-native.log`。普通 `--duo-window-test` 也通过收起/展开、准备反转、拖动恢复与同步恢复取消动画，日志为 `ordinary-represent-native.log`。

这组结果支持“静态图首帧未再次提交”的修复方向，但样本不足以证明所有设备、Space 和负载下的失败率归零。后续继续观察真实使用与压力场景。探针现在分别报告几何不匹配和动画回退，失败日志包含 panel 可见性、alpha、occlusion 及渲染指标，方便复现后定位。

尚未完成真实三击/四击输入、SCK 迟到压力、VoiceOver、能耗和性能分位数验收。上述事务探针直接调用生产方法，不注入标题栏点击，因此不能证明新的连击接线已经端到端通过。

## 最小宽度设置布局

最新设置源码经完整 AppKit 测试编译与导航回归通过；820pt 内容宽度、浅深色模式下，快捷键、菜单入口与外观行的标签上下至少留 8pt，标签与控件间至少留 14pt（测试容差 0.5pt）。离屏截图核对了卡片内容，但材质与侧栏未完整合成，不用作完整 HIG、对比度或 VoiceOver 验收。日志：`.build/quality-validation/settings-layout-test.log`。隔离应用尚未重新打包本次设置改动。

## 标题栏输入控件回归

独立进程的原生标题栏加入文本输入 accessory，裁剪 profile 仍为 `standardTitleBarOnly=true`。修复前生产双击处理函数消费了该输入（14.0ms 单样本）。删除不可靠缓存捷径并修正三击拒绝分支后，实际 AX 命中确认是文本框，双击与三击均返回不消费，也未排入收起意图；耗时为 20.1ms/2.3ms（各一次）。只证明这个错误被修复，不支持整体提速或 p95/p99 结论；没有注入全局鼠标事件。

命令：隔离签名应用 `--duo-window-test --input-test`；随后 `--duo-window-test` 的完整普通动画事务回归通过。构建 SHA256：`08a091a86721e6e2f002ad6ab2298624a80c2224cb8698d0f6cef8b9203937ee`。该版本已经包含最小宽度设置布局修复。严格签名验证通过，日常应用哈希仍未变。日志位于 `.build/quality-validation/input-before.log`、`input-after.log`、`input-change-fold-regression.log`。

## AX 首次成本与几何回退优化

扩展原只读基准，以两种调用顺序区分首次 AX 列表读取与后续过滤。九个应用：生产枚举先行时首次 20.9–36.4ms、紧邻重复中位数 0.6–1.6ms；原始 AXWindows 先行时原始读取 9.5–26.9ms、后续生产枚举 0.5–3.9ms。新建/复用 AX 应用句柄的热查询接近。日志 `ax-latency-breakdown.log` / `ax-latency-raw-first.log` 在 `.build/quality-validation/`。样本不支持 p95/p99、冷启动或忙应用结论。

优化后的几何回退可直接采用 ID/PID 与最上层普通窗口匹配、实时几何也包含点击点的聚焦窗口。真实 fixture 集成检查确认目标 ID 正确、未枚举 AXWindows，单次 1.7ms；输入框双击/三击仍不被消费。命令 `--duo-window-test --input-test`，日志 `.build/quality-validation/focused-lookup-input.log`。此处未注入系统事件。最终构建 SHA256 `b0d00b2c57f0c4a525a404f10d1b3531b66b74253f372afcfa688311b463bf81`；严格签名与日常二进制未变检查通过。

## 重叠同名窗口的身份

在真实 AppKit 中创建两扇完全同名、同位置、同尺寸的窗口。修复前映射 `{50182: 50182, 50181: 50182}`，证实几何优先解析会把两个 AX 元素归为同一个目标。探针 29 项中 11 项失败，部分是源窗口无法解析后的连带失败，不能解释成 11 个独立问题。

修复为元素直接 ID 优先，公开几何回退只接受全量候选中的唯一匹配、拒绝歧义；失效/无法通信不猜替代窗口。修复后的 29 项身份探针通过，包含原窗口关闭后不替换成仍在场的同名窗口。普通动画完整事务和蓝色源窗口捕获正确性均通过。捕获单样本为 771/152ms，不支持性能改善结论。

输入探针两次前置条件失败已保留；改为实际等待目标 AX 命中，并显式激活/核对临时窗口前台，结束时有条件恢复原应用。最终 `--duo-window-test --input-test` 通过，双击/三击不吞输入，聚焦查找不枚举应用窗口。一次先前复验中双击达 101ms，仍是未解决的同步 AX 长尾证据。

日志均在 `.build/quality-validation/`：`twin-before.log`、`twin-after.log`、`twin-fold-regression.log`、`twin-capture-regression.log`、`twin-input-regression.log`、`twin-input-final.log`、`twin-input-ready.log`。最终 SHA256 `f99d80ed8c8e30d2ef6d395152cac7ad35406fd6f2ebc4f1358cc14feed53d04`，签名校验通过，日常应用未替换。身份/动画/捕获检查对应同一生产源码；最后一次重建仅修正输入探针的准备与恢复，最终输入复验通过。

## 严格身份校验与首帧补交（当前源码）

`WindowBrowserTargetResolver.inspect` 现在把 WindowServer owner PID 作为硬门槛：AX 元素的公开窗口 ID 不存在、记录已消失或 owner 不是目标应用时立即拒绝。解锁会话中的同名同框双窗口探针通过 30 项检查，包含源窗口关闭后陈旧 AX 句柄不能替换成仍在场的孪生窗口；证据为 `.build/quality-validation/strict-id-identity.log`。

`FoldRenderer` 在 GPU 命令完成且仍需展示、但还没有首帧呈现回调时立即补交一次绘制，避免静态封面完成第一条命令后没有后续 drawable 提交。它保持原有显示时钟、按需绘制和 500ms 超时预算。源码 `--check`、优化签名构建和签名验证通过；包含本节可访问性改动的当前隔离二进制 SHA256 为 `39f30527c2b5c85d69f9e3f403f9e1c5f5ea223c0be08c663fac7df5d34b4678`。

此前一次验证处于锁屏环境，AXWindows 返回应用元素，因此不作为生产证据。当前桌面已解锁，最后源码版本已重新运行身份、无动画、动画、边缘动画、输入和捕获探针。

本阶段已通过：`bash tests/run-window-browser-tests.sh`（690 项，含预览启动取消）、`bash tests/run-duo-tests.sh`、`bash prototype/build.sh --check`、`git diff --check`、严格签名验证，以及最后源码版本的身份/动画/输入/捕获运行探针。日常 `prototype/WindowShade.app` 未替换，当前编译无警告。尚无真实全局事件 p95/p99、忙应用压力、VoiceOver 真机遍历和长期能耗证据。

## 经典条独立可访问控件（当前源码）

经典卷帘条新增三个独立的 `NSAccessibilityButton` 子元素，分别对应关闭、缩放和展开；父级“展开窗口 / 缩放窗口 / 关闭窗口”自定义动作仍保留，兼容 VoiceOver 转子操作。每个子元素按自己的命中框报告屏幕位置，按下时直接派发对应生产动作。`bash tests/run-appkit-tests.sh ClassicStripTests` 通过名称、三个按钮的键盘式按下、150/320/640pt 点击边界、跨按钮释放取消及浅深色渲染检查。它验证 AppKit 对象接线，不等同于 VoiceOver 真机或 Full Keyboard Access 系统设置下的人工验收。

## WindowServer 快照并发合并（当前源码）

`WindowListCache` 对 on-screen 与 all 两种快照分别维护刷新门；同一 TTL 边界的并发 miss 不再各自调用 `CGWindowListCopyWindowInfo`，等待者在刷新完成后重新检查 TTL 并共享结果。刷新仍在锁外执行，实时动作验证继续使用 `cgWindowInfo(id:)`，因此没有用过期批量快照替代身份证明。`bash prototype/build.sh --check` 通过；真实并发枚举计数和 p95/p99 仍待采样。

本节改动之后重新完成了隔离优化构建和严格签名验证；最新二进制 SHA256 为 `420ea45150e6af38c72cfe50f656d91dbab6e950f334159e5ed0e88fe0809d00`。此前首帧/可访问性段落中的哈希是对应当时构建的历史产物。

随后将 ScreenCaptureKit 的停流路径迁移到 async API，并改用明确的 `NSApplication.shared` 无障碍播报宿主；最新 `--check` 不再输出原有三条编译警告。

包含上述停流与播报修复的隔离构建随后再次通过；当前最新二进制 SHA256 为 `28ec24d4d0a4cd2814aea022acaf7975bab90636a046ee5734df26bd17c9c212`，严格签名验证和日常 bundle 未替换检查通过。

## 解锁后的最终运行复验

确认桌面已解锁后，最后源码版本重新运行：

- `--window-browser-identity-probe`：30 项身份检查全部通过，包含同名同框窗口、陈旧句柄、错误 PID/Window ID、伪造 key 和关闭窗口拒绝。
- `--duo-window-test --no-animation`、普通 `--duo-window-test`、`--duo-window-test --edge`：全部通过收起、恢复、准备阶段反转、拖动恢复和同步取消；边缘场景未再出现首帧呈现超时。
- `--duo-window-test --input-test`：标题栏文本框双击/三击均未被消费，聚焦几何快路径约 0.29ms；输入样本约 6.19ms/0.43ms。
- `--window-browser-capture-probe`：蓝色源窗口正确性通过；card 120ms、selectedLarge 27ms，各一轮样本。

日志为 `.build/quality-validation/current-identity.log`、`current-no-animation.log`、`current-animation.log`、`current-edge.log`、`current-input.log` 和 `current-capture.log`。这些是隔离 fixture 与单样本证据，不等同于全局事件 tap p95/p99、忙应用压力、VoiceOver 真机遍历或长期能耗测量。
