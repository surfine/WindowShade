# WindowShade 2 · round2 part7

第七份交付已从增加零散核心改为接通一条实际调用链。本地只读助手流程有生产候选调用者和原生界面源码，测试通过真实本机子进程执行；**未运行 Mac SDK、真实 Codex、真实登录或设备**。

先读 [入口](00-先读-第七份.md)、[变更](CHANGELOG.md)、[验证记录](VALIDATION.md)、[完成条件](COMPLETION-CONTRACT.md)。连续阅读用 `第七份-背景与收尾总册.md`。`sources/code-map.md` 定位本次全部源码变更，`overlay/` 是精确增量。

## 从统一包运行

以下命令不启动真实 CLI，不访问真实用户的 Codex 配置。测试里的临时可执行文件有明确 FAKE 标记。需要 Swift 6、C 编译器和 Python 3；schema 检查另需已经安装的 `jsonschema`，本包不自动安装依赖。

```sh
cd WindowShade2-round2-handoff-v7
python3 -S part7/tests/run.py --repo candidate-repo --suite core
python3 -S part7/tests/run.py --repo candidate-repo --suite native
python3 -S part7/tests/run.py --repo candidate-repo --suite flow
python3 part7/tests/check-schema.py --repo candidate-repo   --messages part7/validation/flow-outbound.ndjson --report part7/validation/schema.json
python3 -S part7/tests/check-build.py --repo candidate-repo
python3 -S part7/tests/regressions.py --repo candidate-repo --history . --batch foundation
python3 -S part7/tests/regressions.py --repo candidate-repo --history . --batch process
python3 -S part7/tests/test-tools.py
bash part7/tests/run-mac-check.sh candidate-repo
```

最后一条在非 Mac 返回 78，表示未运行。其余失败返回非零并保留 stdout/stderr。每次运行会更新这份包自己的 `validation/`；历史 part1 至 part6 不被改写。`flow-outbound.ndjson` 是真实候选发给合成后端的字节内容，不是从真实账号截获的流量。

## 只拿增量时

```sh
python3 -S tools/stage.py --base /确切v6/candidate-repo --out /不存在的新目录/candidate-repo
```

工具检查全部基线和 overlay 哈希，拒绝覆盖已有输出、基线内部路径、符号链接和版本漂移。实际工作区已经有用户新改动时，使用 `manifest.json` 的 baseSHA 做三方合并，不强行运行 stage。统一包不需要这一步。

## 目录

`docs/`：实际调用链、监督与退出、配置及授权边界、界面与能耗。
`workorders/`：Mac/真实 CLI 操作验收、其余产品目标的剩余施工。
`tests/` 和 `fixtures/`：可重复测试与隔离后端。
`validation/`：实际输出、开发阶段失败、版本、schema 和构建边界。
`sources/`：固定输入、代码定位、外部一手资料、隐私新增登记。
`COMPLETION-CONTRACT.md`：完成标准，不给虚构百分比或工期。
