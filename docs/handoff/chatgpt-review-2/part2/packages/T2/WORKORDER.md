# T2：番茄钟宿主与卡片

## 本次交付状态

host Swift6类型检查通过；card只语法检查。尚未给NotchActivityKind加focus及全部switch，尚未在AppDelegate创建唯一实例，因此不是已接通App功能。

源码与记录：FocusTimerHost.swift、FocusTimerCard.swift。下面只授权在审查分支施工，不授权修改真实home、设备配对或生产用户配置。

## 可写文件

- `prototype/App/FocusTimerHost.swift`
- `prototype/App/FocusTimerCard.swift`

## 已有符号

prototype/App/NotchActivityController.swift:51 configure；:103 publish；prototype/Core/NotchActivities.swift:135 upsert(_:,now:)；prototype/App/Notch.swift:1440 setActivities(_:selected:)。行号对应上传快照。先核实际签名；不为了穿透private改成public。

## 决定表

|情况|动作|原因|
|---|---|---|
|本包明确规则|同一轮所有视图共享一个host；Task取消后检查代次；锁屏/睡眠交T1事件；副作用只交T3闭包；card不创建窗口。|避免执行模型补出隐含行为|
|锁态未知、锁屏、睡眠、失去会话|先撤代次和输入，再清私密视图|不等动画结束才停|
|同一事件重复、异步晚回调|核上下文/序号/租约，过期丢弃|不能复活旧操作|
|SDK签名或私有ABI对不上|保留诊断，停该包，不unsafeBitCast猜签名|类型检查与设备证据分开|
|表外情形|停止该动作并报告输入、当前状态、缺失条件|不自主扩展产品|

## 常量与文案

日期样本必须由主模型的统一时钟/日历提供。1个一次性唤醒；rest呼吸2秒为推荐，需要与设计令牌统一后接入。 符号/文案以源码和对照表为准；默认不安装设备钩子，不发布系统动作。

## 验收

本包根目录 `bash tests/run-core.sh` 预期0，末行含`PASS part2 core`。它覆盖L2/D5a/D6和共享租约；**不覆盖S1/T2的AppKit行为**。T2 host单独Swift6 typecheck记录在validation/focus-host-typecheck.txt。

`python tools/stage.py --repo 原repo绝对路径 --out 全新目录` 预期0且含`PASS STAGED_NEW_DIRECTORY`。不能把out选为原repo或已存在目录。AppKit包在审查分支合入、补齐明确列出的宿主接点后执行 `cd prototype && ./build.sh --check`；本轮没有跑过。失败先核文件收集路径、framework、MainActor回调、enum新增case的穷尽switch。不得把编译失败简单改成@unchecked Sendable。

## 不要做

不把探针塞进App源码收集路径；不新建第二个@main进App；不为演示伪造后端成功；不把本包未实现项勾成完成。运行前保留输入哈希；暂存和编译输出不是生产验收。
