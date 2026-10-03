# 第3份实际验证

运行环境为Linux、Swift6.2.1；`validation/environment.json`保留编译器原始输出。没有macOS SDK，没有连接Mac，没有运行真实Codex/Claude，没有接触真实home配置。本报告不将语法解析、合成事件或上传的Mac记录称为本次真机结果。

## 新代码

在本份根运行 `bash tests/run-core.sh`，使用Swift6语言模式、完整严格并发检查、warnings-as-errors，退出0。实际55个场景、147个断言通过，原始stdout在`validation/core-tests.txt`，逐例结果在`core-results.json`和`tests/TEST-CASES.md`。

测试使用真实临时目录/文件、Unix socket、stdin管道和Python假后端子进程，覆盖权限/过期/分帧/上限/拒绝改写/备份回滚/断连及协议乱序。网络助手、硬件身份、加密互操作不在这些测试中。PIN测试覆盖取消重开仍保留失败次数；配置事务没有声称对不合作的外部写入者提供文件系统级比较交换保证。

独立ws-hook编译通过，见`helper-build.json`；无效JSON、非支持provider、缺少session、大于上限四种输入均退出0并只返回`{}`，见四份`helper-*.json`。这些fixture在访问home前就被拒绝，未安装hook。当前helper只观测或拒绝，没有allow路径。

## 跨份兼容和原有回归

用本份CodexWire替换第二份依赖，重新编译并跑第二份测试，22个场景、86个断言通过。记录为`part2-compat-compile.json`、`part2-compat.json`，实际出站fixture另存；不把22个旧场景算作新场景。

原ConductorGesture源码/原测试在新临时目录编译运行；本份暂存后的NotchActivities与原NotchActivityTests编译运行，均退出0。见`gesture-regression*.json`、`notch-regression*.json`。没有为了测试向原repo建立.build。

三份新增Foundation核心、支持层、唯一合同、原ConductorGesture、InteractionCoordinator和FocusTimerHost同一次类型检查通过，见`combined-foundation-typecheck.json`。这证明所列文件在Linux能一起检查，不能推广到整App。第一份完整377个断言本轮未逐包重跑。

本份实际生成的thread/resume请求params通过原包0.153.0的ThreadResumeParams schema。固定schema目录共304个JSON，结果及schema哈希见`resume-schema.json`。该检查不证明真实服务端时序、授权或resume可用。

## App 与探针

25个文件逐一 `swiftc -frontend -parse` 退出0，见`syntax-only.json`。包含合并后的12个原文件、App候选新文件和旧探针。这里只是语法解析；没有加载macOS SDK、没有AppKit类型检查、更没有运行界面或探针。Darwin peer凭证/ACL/实际锁态等保持未测试。

## 三份组合与输入完整性

`tools/stage-all.py`实际向全新目录组成完整候选repo。校验1079个源文件，修改12个原文件，共31次跨份替换，放入38份新增Swift文件，并独立放置helper。`stage-all.json`记录每个新增文件来源；其中多数来自前两份，38不是本次新文件数。共享合同只有一份，CodexWire使用本份版本。

已有输出、改动后的基线两个负例均以退出2拒绝，未覆盖原目录或创建错误输出，见`stage-negative.json`。再次将原repo逐文件与用户原ZIP比对，1079个文件字节一致，见`input-integrity.json`。这不等于整App功能验收。

## 影片最终门禁

`python3 film/release-gate.py --film /第2份/film --report validation/film-gate.json`实际输出BLOCKED、77项缺证据，退出2。包括17项素材的审核/文件证据和9类最终构建、声音、画面检查记录缺失。这是正确阻止最终发布的负例，不是77项影片测试通过。

没有生成新影片、没有Remotion正式编译、没有配音/音乐/响度检查。第二份的两条无声动态分镜仍是先前产物。

## 整轮未完成

仍欠的生产源码详见`integration/MAC-ACCEPTANCE.md`。没有本次整App构建、CLI端到端、设备配对、真实锁/解锁、输入监控、蓝牙身份、多触点ABI、声纹/人脸模型、能耗、签名或发布结果。本次记录不以“默认关闭”证明新源码不会导致编译或运行回归。
