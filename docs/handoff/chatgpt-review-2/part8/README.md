# WindowShade 2 · 第二回合第八份

实际候选增量：手柄到原生模型列表，原Notch收起到实际事务观察。包含6份背景、5份工单、28项決策、源码overlay、修改前原文、测试和原始输出。总册是这些材料的阅读合并，不另计一份新增研究或功能。

统一包使用 candidate-repo，历史 part1…part7 只供追溯，不再逐份叠加。单独增量仅适用于精确v7候选。已在更晚工作区修改的文件请按base-sources/overlay/当前版本三方合并；stage拒绝不匹配输入，不能作为强制覆盖工具。

## 当前可重复命令

从统一包的part8目录运行，要求Swift6、C编译器、Python3。测试不会登录、连接模型或运行用户选择的工具。临时测试后端只在测试目录生成。

```sh
python3 tests/run.py --repo ../candidate-repo --suite input
python3 tests/run.py --repo ../candidate-repo --suite fold
python3 tests/run.py --repo ../candidate-repo --suite flow
python3 tests/check-build.py --repo ../candidate-repo
python3 tests/test-tools.py
python3 tests/check-wiring.py --repo ../candidate-repo
python3 ../candidate-repo/tests/duo-integration-check.py
```

Mac整App构建另运行：

```sh
bash tests/run-mac-check.sh ../candidate-repo
```

此脚本Linux明确退出78；Mac会复制到临时目录运行真实build.sh --check，不启动App、不签名、不发布。本轮没有Mac成功结果。

旧用例在新候选上重跑，输出必须另放，不能覆盖历史证据：

```sh
python3 ../part7/tests/run.py --repo ../candidate-repo --suite core --report-dir validation/regressions/part7
python3 ../part7/tests/run.py --repo ../candidate-repo --suite flow --report-dir validation/regressions/part7
python3 ../part7/tests/run.py --repo ../candidate-repo --suite native --report-dir validation/regressions/part7
python3 ../part7/tests/regressions.py --repo ../candidate-repo --history .. --batch foundation --report-dir validation/regressions/legacy
python3 ../part7/tests/regressions.py --repo ../candidate-repo --history .. --batch process --report-dir validation/regressions/legacy
```

独立增量的暂存命令（输出不存在且父目录已存在）：

```sh
python3 tools/stage.py --base /绝对路径/v7/candidate-repo --out /绝对路径/新候选
```

## 先读什么

00-交给执行模型.md给出入口，CHANGELOG列实际差异，VALIDATION区分实际测试与未运行，REMAINING保留全项目缺口。背景和工单在docs/workorders；源码定位在sources/code-map.md与JSON，manifest带每个旧/新哈希，base-files列完整1157文件基线。没有自动安装、GitHub提交、更新源改动或真实账号操作。
