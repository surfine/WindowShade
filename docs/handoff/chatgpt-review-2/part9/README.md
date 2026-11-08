# WindowShade 2：第二回合第九份

本份修复旧收起路径的未知状态误报、完成通知归属、巡检与 AX 旧回调，并修复泛型首帧等待的严格 Swift 6 隔离。包含实际源码增量、6 篇背景、4 份施工单、22 项决策、26 份源码索引和可重复测试。

直接使用统一包 `candidate-repo/`，已经组合好九份，不要再从 part1 顺次叠加。增量包的 `overlay/` 是完整文件，`base-sources/` 是本次修改前的原文，`patches.patch` 供审阅。manifest 校验精确 v8 基线的 1164 个文件，输出候选 1168 个文件：修改 11、新增 4；其中修改 10 个既有 Swift、新增 2 个 Swift，另修改一个 Python 文本检查并新增两份接线/隐私文档。

## 可重复命令

在统一 v9 根目录运行。命令只使用容器/本机临时目录与候选测试，不自动启动真实 CLI、操作真实窗口、签名或发布。实际 Mac UI/AX 验收另由工单规定。

```sh
P=part9
R=candidate-repo
python3 -B "$P/tests/run.py" --repo "$R" --suite regression
python3 -B "$P/tests/run.py" --repo "$R" --suite frame
python3 -B "$P/tests/check-build.py" --repo "$R"
python3 -B "$P/tests/check-wiring.py" --repo "$R"
python3 -B "$P/tests/test-tools.py"
```

旧回归每条独立运行，失败保留原输出。脚本复制旧测试到临时目录或指定本份 report-dir，不改历史报告；运行新测试会重写 part9/validation 对应记录，复核归档应先复制一份。

```sh
python3 -B "$P/tests/run-previous.py" --repo "$R" --history . --suite duo
python3 -B "$P/tests/run-previous.py" --repo "$R" --history . --suite part8-input
python3 -B "$P/tests/run-previous.py" --repo "$R" --history . --suite part8-fold
python3 -B "$P/tests/run-previous.py" --repo "$R" --history . --suite part8-flow
python3 -B "$P/tests/run-previous.py" --repo "$R" --history . --suite part7-core
python3 -B "$P/tests/run-previous.py" --repo "$R" --history . --suite part7-native
python3 -B "$P/tests/run-previous.py" --repo "$R" --history . --suite part7-flow
python3 -B "$P/tests/run-previous.py" --repo "$R" --history . --suite legacy-foundation
python3 -B "$P/tests/run-previous.py" --repo "$R" --history . --suite legacy-process
```

Mac 整应用检查使用已有完整工程。Linux 上明确退出 78 表示未运行。

```sh
bash "$P/tests/run-mac-check.sh" "$R"
```

仅在需要从精确 v8 重建时，在已包含 v8/v9 目录的父目录运行：

```sh
python3 -B WindowShade2-round2-handoff-v9/part9/tools/stage.py   --base WindowShade2-round2-handoff-v8/candidate-repo   --out candidate-r9-staged
python3 -B WindowShade2-round2-handoff-v9/part9/tests/reproduce-v8.py   --base WindowShade2-round2-handoff-v8/candidate-repo
```

第二条刻意运行旧缺陷复现，不代表新候选仍失败。stage 只支持精确干净基线，拒绝已有输出、路径重叠、链接和错误哈希；它不是给任意更晚工作区做三方合并的工具，也不是抵御同 UID 恶意竞争的文件沙盒。

## 证据

新 Swift 为 57 场景、108 断言。旧回归、18 项文件工具测试、24 项文本检查、40 份组合类型检查和 12 份语法解析分别记账。完整层级、原始命令、开发失败和 Mac 缺口见 VALIDATION。完整项目状态见 REMAINING 与 COMPLETION-CONTRACT。
