# WindowShade 2 · 第二回合第六份

日期：2026-10-03。入口：`00-交给执行模型.md`。本包包含真实代码增量、10 份背景说明、7 份施工单、44 项决策和可复现检查。它不是功能全部完工或可发布声明。

## 文件与使用

统一包已经合成 `candidate-repo/`；单独增量使用精确第五份候选：

```sh
python3 tools/stage.py --base /第五份/candidate-repo --out /全新目录/candidate-repo
```

输出必须是不存在、且不包含输入也不在输入内部的目录。实际工作区更晚时使用 manifest 内的 baseSHA 做三方合并。只向用户明确选择的隔离工作区应用，不执行发布或改 home 配置。

```sh
C=/全新目录/candidate-repo
bash tests/run-core.sh "$C"
bash tests/run-process.sh "$C"
bash tests/run-wire.sh "$C"
bash tests/check-foundation.sh "$C"
python3 tests/test-readiness.py
python3 tools/check-source-map.py --candidate "$C"
```

需要 Swift 6、Python 3；wire schema 检查另需 Python `jsonschema`。没有自动安装依赖或调用外部模型。旧回归还需前五份统一材料：

```sh
bash tests/run-regressions.sh "$C" /统一包根目录
```

已知退出通知缺口单独运行，不应要求它当前必然返回零：

```sh
bash tests/run-exit-probe.sh "$C"
# 当前 Linux 记录为 BLOCKED / exit 2；保留完整结果。
bash tests/run-mac-check.sh "$C"
# 非 macOS 明确 NOT RUN / exit 78。
python3 tools/readiness.py --input fixtures/readiness-current.json \
  --evidence-root . --candidate "$C" --report validation/readiness-current.json
# 当前能力证据不齐，预期 BLOCKED / exit 2，不是功能测试通过。
```

readiness 只检查提供的记录、环境声明、日志哈希与候选版本是否完整一致，不能鉴别日志真实性或审阅者身份，也不是自动安全认证。`EVIDENCE_COMPLETE` 只适用于输入列出的能力，不会赋予任何发布权限。

## 依赖与许可证

本轮 Swift 增量和 Python/shell 工具均为原创实现；没有打包外部文章、SRP/OPACK 源码或新外部依赖。候选中原有工程和历史包的许可证保持原样。研究只保存出处、定位和简短应用说明。外部 SRP 的构建与准入仍按第五份隔离目录处理。

## 范围

详见 `VALIDATION.md` 和 `REMAINING.md`。Linux 类型检查不加载 AppKit/Network/CryptoKit 等 Mac SDK；没有真实 CLI、Touch ID、手柄、Remote、AX、能耗或发行验收。源码地图校验和压缩包完整性只证明文件处理，不证明应用可运行。

候选里继承的 `WS2-STAGING.json` 是早期接线记录，不代表第六份全量清单；当前增量看本包 `manifest.json`，全包完整性看统一包根的 `MANIFEST.sha256.json`。
