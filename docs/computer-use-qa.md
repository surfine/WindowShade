# Computer Use 验收

这份手册是 WindowShade 原生界面验收的入口。模型负责观察、选择下一步和判断画面；CLI 负责隔离运行、身份、取证、禁止盲操作与报告。它不调用模型 API，不是无人值守服务。网页浏览器自动化不能代替 AppKit、窗口服务器和系统权限的实际行为。

## 每次任务怎么做

界面行为改动必须选择下表场景，先看[设计稿目录](design-drafts/README.md)中对应稿，再记录预期和构建身份。只修改工具或文档时，不要求全产品回归。现有单元测试和 `tests/run-glance-probe.sh` 仍保留各自职责；探针失败不能靠删断言或换静态展示变绿。

1. **观察**：新截图与当前 AX 信息一起看。确认应用、窗口、标题、前台焦点、菜单/弹窗、显示尺度和测试资料。桌面截图能看见并不代表 AX 已就绪；空树和截断树不当完整证据。
2. **确认目标**：优先使用当前 AX 元素 token。自绘卷帘条、状态菜单等用本次截图定位；截图像素、屏幕点和 Retina 原始像素不能混算。点击将 capture ID 交给驱动；move_cursor 0.34.0 不接受该字段，只能用同会话最新桌面观察。CLI 限观察 50 秒内、每个动作后重拍；不复制旧坐标作为永久脚本。
3. **单步操作**：每张观察最多支撑一个动作。窗口变化、菜单出现、焦点改变或收到新用户操作后，重新观察。不要把一串坐标点击预先排队。
4. **等实际变化**：看内容消失、卷帘条出现、数字变化或菜单关闭；必要时再 `capture`，不要把固定睡眠当成功。有限等待到期即留证，不无限重试。
5. **核对结果**：截图说明用户看到什么；AX 核对身份、几何和内容；产品日志说明内部路径。`effect=unverifiable` 只是输入已发送。任一相互矛盾，就写 fail 或 inconclusive。
6. **恢复**：通过产品本身展开受控窗口，核对原位置、尺寸和内容，再运行 cleanup。恢复失败保留窗口、日志和证据，不强杀应用、不删除恢复日志。cleanup 自己不猜产品恢复操作；先由执行模型观察并使用 WindowShade 恢复，再提交视觉复核给工具核对。实时预览也可能使原窗口临时可见，所以 AX 可见不等于已经展开。

动画要用连续帧或真实录屏核对过程、时间与首帧，单张截图不能证明跟手或流畅。系统通知挡住目标时先留证，再处理通知、重拍；不要忽略遮挡作结论。看不懂或证据不足就明确写出，不让另一个模型重复一句“通过”替代观察。

## 工具入口与环境

Python 3.9+ 标准库即可运行，源码位于 `tools/computer-use-qa/`。使用专用 Lume VM；本轮验证组合为 macOS 26.6.2 / Lume 0.6.1 / CuaDriver 0.34.0，并非未来版本兼容保证。权限在来宾正常系统界面配置，SIP 保持开启，不改 TCC 数据库。驱动与 WindowShade 都要有自己的权限。SSH 使用已建立的本机连接，不把密码写进配置或命令。

复制 `config.example.json` 到本机非仓库路径，填写 VM、驱动、应用、证据目录和源码目录。先正常启动唯一 VM、驱动和隔离 WindowShade；检查 nvram 的实际占用者。Lume 显示 stopped 但进程仍占文件时，先核对旧实例并正常停止，不删除锁或再启动一个实例。CLI 不擅自启动、关闭 VM 或替换应用。

```sh
python3 tools/computer-use-qa/qa.py --help
python3 tools/computer-use-qa/qa.py prepare --config /absolute/qa-config.json --companion
```

`prepare` 创建独立会话、永久保留的测试文本和 Finder 伴随窗口，读取实际窗口身份与内容，保存基线截图。去掉 `--companion` 不会自动关闭已有窗口；跑单窗口场景前先检查隔离桌面确实只有受控目标。不得操作私人窗口来凑条件。prepare 输出本次绝对 `run` 路径；后面的 `$QA_RUN` 设为该路径。

`doctor --config … --session …` 只读检查已存在会话、权限、OS、VM 进程及 nvram 占用。截图和缩放还须由 capture 确认。`build_source=historical` 表示历史二进制；`candidate` 也不会自动证明源码对应。必须同时有构建命令、对应源码快照与载荷哈希，才可声称“当前源码已测”。工具保存 git 提交、差异及未跟踪文件哈希、实际应用哈希和签名，不自动编译或签名产品。

```sh
python3 tools/computer-use-qa/qa.py capture --run "$QA_RUN" --label before-menu
python3 tools/computer-use-qa/qa.py observe --run "$QA_RUN" --label windows --tool list_windows
# 阅读 before-menu 的 PNG，坐标按当前画面填写，绝不能照抄示例坐标。
python3 tools/computer-use-qa/qa.py act --run "$QA_RUN" --label open-menu \
  --basis before-menu --tool click --args '{"scope":"desktop","x":实际横坐标,"y":实际纵坐标}'
```

`act` 支持 click、move_cursor、press_key、type_text、bring_to_front、set_window_frame、invoke_menu；只允许新鲜观察，点击绑定 capture ID，元素 token 必须来自对应 AX 快照。每个动作后自动截图；重新定位再继续。请先用驱动 `describe <tool>` 确认参数，不能猜 API。程序检查不能判断某个桌面像素是不是私人按钮，操作者仍须核对语义。

任何失败设置 `HALTED.json`，后续输入拒绝；继续取证仍可用。不要删标记后重试，先恢复现场，再开新 run。恢复时可先 `capture --run "$QA_RUN" --label recovery --recovery-view`，该画面只能用于恢复，不能解锁普通输入。确认本次标题条后，运行 `cleanup --run "$QA_RUN" --restore-basis recovery --restore-x 实际横坐标 --restore-y 实际纵坐标`；它仅允许在原窗口标题条范围内双击，输出 needs_visual_review 和新画面，不关闭窗口。查看恢复画面、填写 restore 复核后，再运行 cleanup --review。若标题条已移动、被遮挡或无法确认，不猜坐标；保留现场给后续受控恢复。不能声称原失败从未发生。标签不可重复，所有尝试追加保存。记录中 `ok` 只表示调用/采集成功。

## 场景与判断标准

| ID | 条件与必需观察 | 不可替代的检查 |
| --- | --- | --- |
| fold-companion | 目标＋其他应用的伴随窗口；从产品菜单收起 | 内容消失、卷帘条出现、焦点交接；不能仅看菜单计数 |
| fold-solo | 仅目标普通窗口；覆盖最小化分支 | 记录系统标题栏双击设置；收起后条仍可操作 |
| peek-static | 收起后悬停 | 内容正确，明确静态快照标记，不抢焦点 |
| peek-live | 动态计数夹具收起后悬停 | 同一预览连续两次计数不同、无静态标记、不抢焦点；图片哈希不同只是必要条件 |
| peek-cancel | 已显示预览，指针移出 | 预览消失、条保留、原窗口没有展开 |
| restore | 从收起状态展开 | AX 身份、位置、尺寸、文本等于基线，画面可见 |
| target-change | 操作前关闭目标或改变焦点 | 重新观察；不存在的目标拒绝；其他窗口没有收到输入 |
| observation-failure | 结束驱动会话后尝试采集，再尝试输入 | 真实采集失败＋CLI 拒绝记录；未再发送输入 |

提供 `CounterFixture.swift` 作为持久动态计数夹具：每秒变一次，不采用旧夹具 90 秒自动退出。它是独立测试程序，不连接 WindowShade 内部接口。运行 `prepare --config /absolute/qa-config.json --fixture counter --companion`，工具使用本机 Swift 严格编译为 macOS 14+ 可运行包，复制到本次来宾目录并校验哈希；窗口标题和基线绑定本次 run。需要本机 Swift 工具链。默认 prepare 是静态文本夹具，不能把 TextEdit 的窗口 ID 换掉后复用旧 run。实时复核还要在 attempt 的 measurements 填写实际读到的 counter_before / counter_after 两个不同整数。

每个场景结束后把 `review-template.json` 复制为新的复核 JSON，填写 reviewer、每项 status、reason 和事件 label 引用。`before`/`after` 必须是本次不同时间的成功截图。视觉复核是具名结论，不是自动像素分类器；必须真正打开原始 PNG。

```sh
python3 tools/computer-use-qa/qa.py verify --run "$QA_RUN" --review /absolute/review.json
python3 tools/computer-use-qa/qa.py cleanup --run "$QA_RUN" --review /absolute/review.json
python3 tools/computer-use-qa/qa.py report --run "$QA_RUN" --review /absolute/review.json
```

退出码 0：该命令完成；verify/report 只有全部场景和清理通过才为 0。退出码 2：失败、阻塞、未测或证据不足，须看报告具体项；不是 CLI 崩溃。记录 fail 不会被工具改成 pass；缺证据的 pass 会降为 inconclusive。首次失败与重试都列出，失败不能被后续成功抹掉。清理必须先通过 restore 的视觉复核与当前 AX 核对；只关闭本次精确身份的测试文档和 Finder 文件夹，结束本次驱动会话；不删除测试文件和证据，不关闭其他应用，不关闭 VM。

原始截图、AX、操作返回与每项 SHA256 在 events 下；仅恢复用的 recovery_view 不能作为普通场景通过证据。review、verification、report 和 manifest 均独立编号。历史 review 中的失败会合并展示，不能用新复核覆盖。产品日志另外保留原字节并注明来源/采集时间。报告时链接失败前后画面、构建身份和最短复现步骤。发现产品缺陷另建缺陷记录，本工具任务不顺手改产品。

## 七条产品线的覆盖账

| 产品线 | 场景依据/已有入口 | 本次实现的工具范围 | 当前源码已测 |
| --- | --- | --- | --- |
| 窗口 | 本手册八场景；原 glance 探针 | 受控文本、截图/AX、输入与证据报告；计数夹具 | 不据历史构建填写通过 |
| 实时活动 | 设计稿“一颗岛”“实时活动晋级”及已有探针 | 通用取证入口；抢占/关闭/恢复待逐项建立场景 | not_run |
| 电量 | 设备来源与电量探针 | 通用截图；真实设备、未知值与断连另测 | not_run |
| CarPlay | 进入/退出、音视频、桌面恢复规格 | 通用取证；真实接收端与设备另测 | not_run |
| 指挥模式 | 设计稿“指挥模式”与会话测试 | 通用取证；真实授权链不得用替身验收 | not_run |
| 刷脸解锁 | face-unlock 规格及真机实验 | 不用 VM 证明摄像头、活体或系统解锁 | not_run |
| 隐私 | “WindowShade 读到的”及隐私核对 | 通用界面证据；实际读取、落盘、关闭清理另核 | not_run |

硬件矩阵另列多屏、不同缩放、120Hz、睡眠/锁屏、相机、蓝牙、遥控器；VM 通过不勾选这些格。每次改动只跑受影响行为及必要恢复路径，不以固定循环次数冒充覆盖。版本发布仍须按项目规则同步 README 和官网，本次工具交付不是发布。
