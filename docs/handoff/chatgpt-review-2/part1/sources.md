# 来源与证据范围

本轮使用用户上传的 `WindowShade2-review-round2.zip`；没有以实时GitHub替换上传基线。以下源码相对路径从该ZIP的repo/计算。`validation/source-sha256.json` 固定关键源文件；全部Schema另有 `validation/schema-input-sha256.json`。具体接口行号见 `contracts/existing-symbols.md`，逐协议字段见 `validation/schema-evidence.json`。

## 用户提供的一手材料

|材料|使用范围|证据限制|
|---|---|---|
|根目录00-先读我-第二轮.md|交付范围、顺序、允许分批|本份只覆盖contracts与首批pure packages|
|docs/handoff/chatgpt-review-1-verdict.md|R01–R53裁决、Swift方向、许可边界、发布前非阻断项|主模型决定；不冒充本轮外部实测|
|docs/handoff/reference/mac-facts-2026-10-03.md:4–13|Mac/SDK/Swift/CLI版本|采集于交接方机器；不是本轮容器|
|同文件:40–81|GameController签名、可用性、后台属性|SDK声明不等于已试过设备|
|同文件:84–100|14个MultitouchSupport导出存在|不证明结构体布局、返回值、内存归属、数据单位|
|同文件:102–155|CLI帮助与本机指定hook配置|不推导全部项目层/插件层都无hook|
|codex-app-server-schema-0.153.0/ 304份JSON|固定版本协议方向、字段、枚举与对象|不证明联网/授权/重试/进程控制成功|
|docs/blueprint.md、design-system.md、copy-guide.md|六层仲裁、命名、动效令牌|产品规范；WORKORDER标明的额外阈值是本轮建议|
|docs/conductor-v2.md、input-devices.md、pomodoro.md、dynamic-lock.md、agents-in-notch.md|状态与交互要求|与第一轮裁决冲突的旧字段按裁决纠正，不倒退采用旧Rust指令|
|prototype/Core/ConductorGesture.swift|复用原识别器与阈值|baseline/是用户原文件的逐字节副本，明确不属于本轮原创实现|
|NotchActivities/NotchActivityController/Notch源码|现有宿主符号及行号|只有接口草案，没有在此轮伪报App接线成功|
|AuthorizationService/Ledger/Models|既有一次授权消费边界|新纯核只发意图；不是重新实现Touch ID或OS unlock|
|DeviceAuthorizationKey.swift:4–10,44–55,72–83,86–126|本机包裹句柄、公钥、指纹集合状态摘要的真实文件去向|历史-34018注释仍是源码报告，未重新运行；现有文件权限漏洞不由日志补丁一并修复|
|Support/Diagnostics.swift及log-replacements.json列出的五份标题日志源文件|旧路径/队列/窗口标题写入|原字节校验后只生成新目录；输入源码未动|

## 已阅读的外部一手资料

核对日期为2026-10-03。仅用于POSIX/Darwin接口含义，没有复制其实现代码。

**E01. Apple Libc sys/acl.h。** 核对 `acl_init`、`acl_free`、`acl_get_fd`、`acl_set_fd`、`acl_get_entry`、extended ACL类型与entry常量。文件URL指向可变化的main；这里只把它当本轮阅读证据，不假定与SDK27导入结果逐字相同。Darwin代码仍需本机编译。

https://raw.githubusercontent.com/apple-oss-distributions/Libc/main/include/sys/acl.h

**E02. Apple Documentation Archive，open(2)。** 核对O_NOFOLLOW、O_APPEND、O_CREAT及权限创建行为。逐层路径处理为本轮设计；O_NOFOLLOW本身不证明整条父路径安全。

https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/open.2.html

**E03. Apple Documentation Archive，acl_set_fd(3)。** 核对描述符上的ACL写入接口、返回值与extended ACL。Linux通过不构成Darwin ACL验证。

https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/acl_set_fd.3.html

**E04. Apple Documentation Archive，acl_get_entry(3)。** 核对枚举结果与错误条件；测试不能把所有非成功返回一概当作无额外条目。

https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/acl_get_entry.3.html

## 本轮原创与可复现证据

contracts/Contracts.swift、12份纯核及测试、SecureLogFile及测试、Python/Shell辅助工具为本轮原创。没有从GPL、非商业或许可未知项目拷实现；没有导入itsytv-core、遥控私有协议或人脸模型。用户原ConductorGesture.swift按上表标明复用。交付包不含字体、macOS SDK、Sparkle二进制或商业音视频。

数值依据只分规格值、代码已有值和本轮建议。没有真机采样依据的点按窗口、保守容量、超时和弹簧映射不得写成实验最优参数。实验的真实输入、输出、编译器和退出码放在各包VALIDATION.txt及validation/目录；未来Mac重跑结果必须另记。
