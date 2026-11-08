# WindowShade 2 · 第十份最终交接

先读 [第十份总册](第十份-最终交接与收尾路线.md)，再从 [执行入口](00-交给执行模型.md) 进入W00/W01。12个工单、6篇背景、18项裁决和85份实际代码/规格索引都在本包。原七条产品目标完整保留。

统一v10的candidate-repo已合成为1169个文件；不重复叠前九份。真正的生产修复只有build.sh与Journal.swift，另更新入口与台账。五个替换、一个新增文档，原v9不改。manifest.json、base-sources、overlay与patches.patch提供精确合并依据。

## 直接运行

从统一包根目录执行。报告必须位于包外一个新目录，不能覆盖历史结果。

```sh
REPORT_ROOT="$(mktemp -d /tmp/ws2-final-evidence.XXXXXX)"
python3 -B part10/tools/run-final.py --candidate candidate-repo --handoff . --suite window-core --report "$REPORT_ROOT/window-core"
python3 -B part10/tools/run-final.py --candidate candidate-repo --handoff . --suite foundation --report "$REPORT_ROOT/foundation"
python3 -B part10/tools/run-final.py --candidate candidate-repo --handoff . --suite mac-build --report "$REPORT_ROOT/mac-build"
```

Mac缺少框架时为最后一条显式添加 `--sparkle /本机真实2.10.0框架路径/Sparkle.framework`。其余suite是frame、duo、input、flow、native、legacy-foundation、legacy-process。详细命令和限制见docs/05。Mac分支没有本轮实测；Linux明确退出78。

## 复跑第十份自己的检查

下面的脚本会写本份validation，保留归档时先复制part10，再运行。baseline可以使用本包base-sources，足以复现两个实际修改文件，不需要下载旧仓库。

```sh
python3 -B part10/tests/test-journal-id.py --candidate candidate-repo --baseline part10/base-sources
python3 -B part10/tests/test-build-entry.py --candidate candidate-repo --baseline part10/base-sources
python3 -B part10/tests/test-handoff-tools.py --candidate candidate-repo
python3 -B part10/tests/test-stage.py
```

编号测试包含原函数的短命合成崩溃复现，关闭core dump，不读用户恢复文件。shell测试使用假工具，不是Mac编译。

仅持有精确干净v9时，可在全新输出目录重建：

```sh
python3 -B part10/tools/stage.py --base /实际v9候选 --out /不存在的新候选目录
```

实际较新工作区须三方合并，stage不会替你解决语义冲突。不要用删除未提交改动获得干净通过。

## 完成边界

新增编号25例、构建入口12项、交接工具16项有独立证据；旧套件与18个沿用stage工具测试分别记账。Mac整应用/设备/真实CLI/身份/能耗/影片/签名发布未执行。最终范围见COMPLETION-CONTRACT和REMAINING，不按篇数或测试数计算进度。
