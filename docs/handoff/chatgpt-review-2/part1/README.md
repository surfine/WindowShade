# WindowShade 2 · 第二回合第1份

日期：2026-10-03。按委托顺序，本份交回四个共享前置和全部第一波纯逻辑包。**合同草案待主模型审定；输入repo没有改动，未合并、未部署。**

12个包均附完整Swift核心、@main测试、运行脚本、施工单、常量和文案、输入到预期结果的用例表、Linux实际输出。没有把第一轮骨架换一个标题再次交回。

## 主模型入口

先看 [answers.md](answers.md) 的已证实事实和剩余探针，再审 [Contracts.swift](contracts/Contracts.swift)、[InteractionLease.md](contracts/InteractionLease.md)、[PrivacyRegistry.md](contracts/PrivacyRegistry.md)、[BuildBaseline.md](contracts/BuildBaseline.md)。状态边界、推荐阈值及接口由主模型审定后才冻结。

原有意见的替代关系在 [CHANGELOG.md](CHANGELOG.md)。实跑证据在 [VALIDATION.md](VALIDATION.md)，全部来源在 [sources.md](sources.md)。I1a–f采用本份固定映射，旧review里另一套I1字母排序不再用于派工。

## 包索引

|包|完整实现|施工单|
|---|---|---|
|T1|专注/休息、暂停原因、日期、窗口归属|[WORKORDER](packages/T1/WORKORDER.md)|
|L1|在场、倒数、锁回执、返回身份候选|[WORKORDER](packages/L1/WORKORDER.md)|
|A1|助手会话、工具状态、审批与代次|[WORKORDER](packages/A1/WORKORDER.md)|
|D1|指挥状态机、语音草稿、请求回执与审批|[WORKORDER](packages/D1/WORKORDER.md)|
|D2|模型/effort能力、槽位、费用确认票|[WORKORDER](packages/D2/WORKORDER.md)|
|I1a|滚轮平滑|[WORKORDER](packages/I1a/WORKORDER.md)|
|I1b|可靠设备分类|[WORKORDER](packages/I1b/WORKORDER.md)|
|I1c|中键拖动|[WORKORDER](packages/I1c/WORKORDER.md)|
|I1d|多指接触组|[WORKORDER](packages/I1d/WORKORDER.md)|
|I1e|遥控器按钮归一|[WORKORDER](packages/I1e/WORKORDER.md)|
|I1f|遥控/指挥模式与按键取消|[WORKORDER](packages/I1f/WORKORDER.md)|
|I9|焦点几何导航|[WORKORDER](packages/I9/WORKORDER.md)|

每包的TEST-CASES.md与测试中的CASE对应。常量写明来自规格、现有代码还是本轮建议，不能把建议值写成真机最佳值。

## 主模型冻结后的安装方法

先在新目录产生可审查文件，不向原仓库写入。下面变量由主模型填入实际绝对路径；STAGE必须不存在且不在REPO之内。

```sh
export REPO='/实际路径/WindowShade'
export STAGE='/实际路径/ws2-part1-staged'
python3 tools/stage.py --repo "$REPO" --output "$STAGE"
```

退出0并显示PASS stage。工具核验原ConductorGesture字节；若当前仓库已有不同实现，停止交主模型合并，不自动覆盖。STAGE只有39个纯核与测试所需文件，不是完整App，也不应替换整个仓库。

主模型审定每个目标后，把相应文件合入原repo；DeepSeek只拿单包WORKORDER的可写路径。Contracts与tests/support只安装一次；D1依赖D2和原ConductorGesture，其余按施工单，不按目录顺序乱编。

```sh
# 在本交付包根，重新跑全部纯逻辑、合同、日志及组合/优化检查
bash tests/run-all.sh
# 或只跑一个包
bash packages/D1/tests/run-conductor-session-tests.sh
# 新暂存目录中，脚本自动使用repo形状的共享文件
bash "$STAGE/tests/run-conductor-session-tests.sh"
```

主模型再依BuildBaseline在Mac运行App构建。Linux通过不能代替这一步。不得让执行模型为修编译移除警告、权限边界、签名配置或断言。

日志修复是另一个需审定的前置，不随stage.py自动混入App：

```sh
python3 contracts/privacy/patch-logs.py --repo "$REPO"
# PATCH_STAGE同样必须不存在且在REPO之外
export PATCH_STAGE='/实际路径/ws2-log-patch-staged'
python3 contracts/privacy/patch-logs.py --repo "$REPO" --output "$PATCH_STAGE"
python3 contracts/privacy/check-registry.py --repo "$REPO"
python3 tools/check-pinned-schema.py --repo "$REPO"
```

日志补丁生成的是6份已改原文件与1份新增SecureLogFile，不会删除旧/tmp日志或修改授权句柄文件。Swift wrapper和Darwin ACL仍需Mac编译及P1验收。隐私登记最后加入了实际Secure Enclave/LAContext读取点，最终计453个词法命中；早期过程数字433不再是最终清单。

## 实际验证与范围

Swift6.2.1 Linux下，12包共 **121个独立场景、334个断言**通过。加Contracts和日志为 **138个场景、377个断言**。D1另做优化编译重复测试；原ConductorGesture和NotchActivity两组回归本轮也重新通过。次数、命令、退出码及负例详见VALIDATION，重复运行没有充作新场景。

本份没有App包接线，也没有真机探针或概念片F1–F5。交互租约提供状态表、接口与精确接线位置，但没有假称现有Notch已经采用它。剩余包继续受委托的优先级约束：film F1–F2位于本份之后，再是其余App包，最后film F3–F5。此处只记录委托顺序，不表示已经执行。

文件校验可运行 `python3 tools/verify-bundle.py`。SHA256清单用于检查交付文件完整性，不是代码签名或安全认证。
