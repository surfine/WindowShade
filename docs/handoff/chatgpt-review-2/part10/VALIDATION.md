# 第十份实际验证记录

环境为Linux x86_64、Swift 6.2.1、Python 3.13.5，完整原始版本在 environment.json。本轮实际尝试Mac工作区连接失败；连接凭据未保存到交付。没有macOS SDK、真实CLI账号、窗口/设备、配对、生物数据、签名或发布操作。

## 本轮新验证

|项目|实际结果|能证明什么|原始证据|
|---|---|---|---|
|实际journalID/journalNumber函数提取测试|25个边界用例通过|生产函数在Foundation宿主中精确拒绝非法编号；不是完整AppDelegate/AX|journal-id-tests.json/txt|
|build.sh入口检查|12项通过，其中包括实际shell配假编译工具及四调用点的静态复核|check不source签名配置、参数覆盖、失败退出传递；不是SDK构建|build-entry-tests.json/txt|
|交接/证据路径检查|16项通过|外部报告目录拒绝规则、七轴/旧包覆盖、依赖无环、85份路径/哈希/行号|handoff-tool-tests.json/txt|

25个用例各有一项结果，不把四个旧缺陷样本或上述Python检查加成新的Swift场景。原函数测试使用CGWindowID=UInt32别名和Foundation/CoreFoundation宿主，生产函数文本逐字提取；未加载Cocoa。构建入口使用明确的MOCK工具和人工源文件，所有假输出都只在临时目录，未作为App二进制交付。

## 旧问题的对照复现

原journalID的NaN与2^32两例分别返回信号退出-4，是真实短命测试进程中的转换陷阱。true与1.5均返回Optional(1)。这是原函数对合成数据的行为，不能说用户真实日志已经损坏。

原build.sh在合成local-codesign.env里写marker并exit97，check确实执行了它；原脚本的显式swift-version计数为0。新脚本的对应行为由上述用例验证。没有执行普通签名构建。

## 旧套件在本轮候选重跑

|套件|实际结果|范围|
|---|---|---|
|part9 regression|42场景/93断言通过|真实核心与FoldCompletion测试宿主，无AX|
|part9 frame|15场景/15断言通过|实际首帧helper，无SCK|
|原DuoCoreTests|原程序通过，未重新发明统一计数|实际原Swift测试；另跑原文本级接线检查|
|part8 input|33场景/49断言通过|实际输入合同与模型，设备桥为替身|
|part7 flow|18场景/145断言通过|真实本地子进程/管道和受控后端，无模型服务|
|part7 native|3场景/14断言通过|Linux自有子进程/进程组测试，不推广到Mac/宿主崩溃/脱离组后代|
|Foundation组合检查|40份候选同次严格Swift6 typecheck通过|不包含Mac条件分支|
|Swift语法检查|13份相对旧快照变化的Swift逐一parse通过|包括本份Journal；不是Mac类型检查|

完整argv/退出码/stdout/stderr保留在runner-evidence各套目录。runner每次复制part9测试到临时位置，输出到全新外部目录，再把结果作为本轮证据复制入包。没有覆盖part1至part9历史报告。没有本轮重跑legacy-foundation、legacy-process全套或所有电量/身份/设备/加密测试，也没有将旧通过数累计成本轮成果。

报告中的candidate全树摘要对应运行时快照，完整对应表在tested-candidate-files.json。测试结束后仅在v1.0.16-ledger.md顶部补入本轮事实说明；所有生产Swift/C/build脚本与已测快照一致，见post-test-doc-only.json。不能把文档更新描述成新的行为验证。

## Mac结果

run-final.py --suite mac-build真实退出78，状态NOT_RUN，raw记录在runner-evidence/mac-build。Linux平台守卫先退出，没有执行真实framework检查或Mac构建。新版Mac runner的Darwin分支尚未实机执行，不能称其已验证过整个Mac工具链。真实输入法、Focus、窗口恢复、GameController、原生批准与Keychain等继续按工单验收。

## 文件和暂存

沿用的18个stage工具测试通过，属于旧工具保护回归，不是18项新产品测试。真实stage校验1168文件基线，替换5文件、新增1文档，输出1169文件与统一候选逐项相同；再次向已有输出尝试按预期退出2且未覆盖。

v9上传ZIP的2293个文件全部与提取输入相同，原part1至part9及history字节保持不变。原始输入完整性见input-integrity.json。每个新包自带SHA树；verify-package.py检查ZIP路径/CRC/文件哈希，只证明完整性，不证明发布身份或功能可用。

## 中止及开发过程

development/notes.md与对应原输出保留：首轮shell替身测试被外层限时中断；调整假工具的解释器启动方式后全套重跑，没有放宽断言。flow+foundation合批时外层45秒限时，flow完成而foundation无最终记录，已明确INTERRUPTED；foundation独立重跑通过。工单路径生成先拒绝了两个错目录，修为实际Window/AXHelpers与Core/NotchActivities后85份全部校验。内部打包核对误将全树哈希放在逐项循环导致超时，改为一次快照比较并完整重跑，比较标准不变。

没有用“预期失败”掩盖真实验收失败，也没有声称开发过程从未出错。

## 本轮没有完成的产品事项

完整T3、慢AX隔离/调度、真实允许路径、其余设备输入、SRP/Listener/OPACK/session、完整CarPlay、身份/锁后端、恢复标题迁移、真实能耗与新影片仍按REMAINING和12工单。新编号检查不自动修复其他journal字段；现有prune仍过滤非法编号，尚无损坏条目隔离机制。本轮没有新增后台读取源或网络监听，也没有开启任何额外生产能力。
