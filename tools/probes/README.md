# 真机探针：只读优先，Aaron 在场

这五个程序为新交付源码。此环境是 Linux，没有编译 macOS SDK、没有连接硬件，也没有生成设备通过记录。默认运行不会保存密码、抓取人脸或打开输入接管。不要把探针复制到 App 的源码收集目录。Swift 5 语言模式用于单独 CLI，不能据此宣布 App 的 Swift 6 并发检查通过。

|编号|命令（在本包根目录）|操作|输出与下一步|
|---|---|---|---|
|P-BLE|`bash probes/run-probe.sh BLEReadProbe`|给终端蓝牙权限，带着候选设备停留45秒；只记录发现|没有目标：不能选；发现不等于可读。记录 local identifier 仅用于下一次本机筛选，不提交公开仓库|
|P-BLE-read|`bash probes/run-probe.sh BLEReadProbe --target UUID --service UUID --characteristic UUID`|先用只指定target的同一程序枚举服务和特征，再把真实UUID填入；走开、关闭蓝牙、返回各跑一次|必须同时有read_requested与read_response_byte_count。退出0只证明一次读回；2不确定。读回不证明身份，仍不允许自动解锁|
|P-BLE-battery|`bash probes/run-probe.sh BLEReadProbe --role central --operation battery [--target UUID] [--notify 秒]`；不碰硬件的自检：`--self-test`|先在系统里让 iPhone 与这台 Mac 保持蓝牙连接。只取系统已连上、带电量服务 0x180F 的设备，不扫描、不广播；读一次电量 0x2A19 和型号 0x2A24，`--notify` 最多听 30 秒，然后断开|输出 `battery_percent`（0..100，其余记 unknown）、`model_number`、`no_connected_peripheral`。设备标识只以本次运行的加盐哈希 token 出现。读回不证明身份，不进解锁；App 侧代码等真机证据再写。解析测试：`bash tests/run-ble-battery-parsing-tests.sh`|
|P-HID|`bash probes/run-probe.sh RemoteHIDProbe VENDOR_DECIMAL PRODUCT_DECIMAL`|从系统设备列表确认目标VID/PID。依次单按中心/方向/返回、长按、触面左上右下、按麦克风。30秒；不按其他键|不同usage/cookie才可定映射。同一变化只代表一维，不能编出二维坐标；无麦克风数据就把microphone能力关掉。输出不含键盘usage page7|
|P-WHEEL|`bash probes/run-probe.sh WheelAssociationProbe`|只枚举本机鼠标／指针的 VID/PID，不装事件 tap|退出 0 只表示列到了设备。**不能**据此打开平滑滚动。逐事件关联仍缺（D14）|
|P-MT|`bash probes/run-probe.sh MultitouchSymbolProbe`|保持原系统手势设置，不注册回调|退出3和STOP_ABI_UNVERIFIED是预期的未准入结果。本探针只覆盖符号存在，**没有解决MTTouch布局**。必须由持有确切ABI头文件与目标版本记录的主模型继续，不能让DeepSeek猜stride|
|P-ID|`bash probes/run-probe.sh IdentityBoundaryProbe --authenticate`|Aaron亲自操作系统生物识别提示；成功、取消、不可用各记录|OS_BIOMETRICS_SUCCESS只证明这次LAContext身份验证。不证明摄像头认识Aaron，不解锁锁屏。模型另用`--model 文件 固定SHA256`；散列匹配也不证明活体与误识率|
|P-LOCK|`bash probes/run-probe.sh LockStateProbe`|60秒内用Apple菜单手动锁定再手动解锁，另做用户切换、睡眠恢复。不要远程输入密码|private key缺失记unknown而非false。真实操作与字段不一致时后端不可用。该只读探针**没有提供生产锁屏命令**|
|P-HABIT|`bash tools/probes/run-probe.sh HabitSignalProbe [--seconds 6]`；现场 `--live 60`|无交互部分只看能不能装上 Dock 的辅助功能观察、会话监听，旁听调度中心开合通知；`--live` 时 Aaron 三指上滑瞥一眼调度中心、按 🌐H、点 Dock、往上大幅滑动页面|iPad 习惯规则 i2/i5/i18 的信号。打印 SIGNAL（available / unavailable / pending-device）和 EVENT（时间戳 + 键码或名字，不记按了什么字）。拿不到信号的规则不做；pending-device 的规则留在 needsDeviceCheck 门后|
|P-FACE-FP|`bash tools/probes/run-probe.sh FaceFeaturePrintProbe [--backend vision\|arcface] [--frames 10] [--compare 40] [--camera UNIQUE_ID]`；不开相机的自检：`--self-test`|终端第一次会弹相机授权，Aaron 亲自点允许。见下面“刷脸阈值标定”的步骤|只打印余弦汇总（n/min/p5/median/p95/max）、当前阈值下的通过率和建议阈值；不存图像、不打印向量、不写文件。建议阈值只来自这一次的人和光线，改 `FaceScanModelProfile.table` 前至少要有两个不同的人、两种光线|

`results-template.csv` 是空白记录格式。禁止把预期值写进 observed。每次保存机器/系统/SDK、命令、退出码、操作时间和终端原输出；设备姓名/完整UUID保留在本机私有证据里，分享时删掉。

## 刷脸阈值标定（P-FACE-FP）

刷脸实验（App 里默认关）的特征来自 Apple Vision 的图像特征，不是人脸身份模型，阈值 0.92 是**未标定**的占位值。标定在真机上按这个顺序做：

1. `bash tools/probes/run-probe.sh FaceFeaturePrintProbe --self-test` 先过（不开相机，含一次合成图上的 Vision 真跑）。
2. `bash tools/probes/run-probe.sh FaceFeaturePrintProbe --backend vision`。Aaron 正对内建相机、正常距离、画面里只有一张脸：先录 10 帧当模板（只在内存里），接着采 40 帧同一个人，打印第 1 轮统计。
3. 提示出现后输入 `same` 回车：换光线（关灯/背光）或戴上眼镜再采一轮同一个人。
4. 输入 `other` 回车：换另一个人坐到相机前再采一轮；有条件就多做几个 `other`（不同的人）。也可以用照片或屏幕上的 Aaron 照片做一轮 `other`，看攻击样本的分数（结果只说明这一张照片）。
5. 空回车结束，看汇总：`same person` 的 p5 和 `other person` 的 max。只有前者明显高于后者（建议里的 margin 为正）才把建议阈值写进 `prototype/Core/FaceScanGuard.swift` 里 `FaceScanModelProfile` 的表，同时把 `calibrated` 改成 true，并在提交说明里附上这次的汇总行。margin 为负就说明这条管线分不开这些人，阈值不改，实验保持关闭。
6. ArcFace 后端接上后用 `--backend arcface` 重做 2–5，两份汇总并排比较。这份源码里没有 ArcFace，选它会退出 3。

分数是“和平均模板的余弦”与“和最近一次录入的余弦”中较小的那个，因为守卫要求两者都过阈值。模板按模型版本串（例如 `vision-featureprint-r2-crop1.3-224`）分开，换修订或换裁切都要重新录入。

## 决策树

编译失败 → 保存诊断与SDK号；先检查框架链接、方法签名、Swift隔离注解；不得用unsafeBitCast把公开API改成猜测签名。权限拒绝 → 停止该源、设置显示“未授权”，由用户决定是否授予。无设备/特征/数据 → 能力为unknown并关闭，不改为模拟成功。得到候选数据 → 重复断连、取消、锁屏测试，再由主模型把确切数据与能力登记绑定。只有数据通道通过、身份通道通过、生命周期撤销通过三项都各有证据，才允许接到执行入口。

P-MT、P-ID与P-LOCK是边界探针，不是完成所有私有API、活体识别和OS解锁研究的替代品。它们阻止把第一轮的猜测继续传给执行模型；尚缺哪一项已明确写出。
