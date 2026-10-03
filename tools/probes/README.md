# 真机探针：只读优先，Aaron 在场

这五个程序为新交付源码。此环境是 Linux，没有编译 macOS SDK、没有连接硬件，也没有生成设备通过记录。默认运行不会保存密码、抓取人脸或打开输入接管。不要把探针复制到 App 的源码收集目录。Swift 5 语言模式用于单独 CLI，不能据此宣布 App 的 Swift 6 并发检查通过。

|编号|命令（在本包根目录）|操作|输出与下一步|
|---|---|---|---|
|P-BLE|`bash probes/run-probe.sh BLEReadProbe`|给终端蓝牙权限，带着候选设备停留45秒；只记录发现|没有目标：不能选；发现不等于可读。记录 local identifier 仅用于下一次本机筛选，不提交公开仓库|
|P-BLE-read|`bash probes/run-probe.sh BLEReadProbe --target UUID --service UUID --characteristic UUID`|先用只指定target的同一程序枚举服务和特征，再把真实UUID填入；走开、关闭蓝牙、返回各跑一次|必须同时有read_requested与read_response_byte_count。退出0只证明一次读回；2不确定。读回不证明身份，仍不允许自动解锁|
|P-HID|`bash probes/run-probe.sh RemoteHIDProbe VENDOR_DECIMAL PRODUCT_DECIMAL`|从系统设备列表确认目标VID/PID。依次单按中心/方向/返回、长按、触面左上右下、按麦克风。30秒；不按其他键|不同usage/cookie才可定映射。同一变化只代表一维，不能编出二维坐标；无麦克风数据就把microphone能力关掉。输出不含键盘usage page7|
|P-MT|`bash probes/run-probe.sh MultitouchSymbolProbe`|保持原系统手势设置，不注册回调|退出3和STOP_ABI_UNVERIFIED是预期的未准入结果。本探针只覆盖符号存在，**没有解决MTTouch布局**。必须由持有确切ABI头文件与目标版本记录的主模型继续，不能让DeepSeek猜stride|
|P-ID|`bash probes/run-probe.sh IdentityBoundaryProbe --authenticate`|Aaron亲自操作系统生物识别提示；成功、取消、不可用各记录|OS_BIOMETRICS_SUCCESS只证明这次LAContext身份验证。不证明摄像头认识Aaron，不解锁锁屏。模型另用`--model 文件 固定SHA256`；散列匹配也不证明活体与误识率|
|P-LOCK|`bash probes/run-probe.sh LockStateProbe`|60秒内用Apple菜单手动锁定再手动解锁，另做用户切换、睡眠恢复。不要远程输入密码|private key缺失记unknown而非false。真实操作与字段不一致时后端不可用。该只读探针**没有提供生产锁屏命令**|

`results-template.csv` 是空白记录格式。禁止把预期值写进 observed。每次保存机器/系统/SDK、命令、退出码、操作时间和终端原输出；设备姓名/完整UUID保留在本机私有证据里，分享时删掉。

## 决策树

编译失败 → 保存诊断与SDK号；先检查框架链接、方法签名、Swift隔离注解；不得用unsafeBitCast把公开API改成猜测签名。权限拒绝 → 停止该源、设置显示“未授权”，由用户决定是否授予。无设备/特征/数据 → 能力为unknown并关闭，不改为模拟成功。得到候选数据 → 重复断连、取消、锁屏测试，再由主模型把确切数据与能力登记绑定。只有数据通道通过、身份通道通过、生命周期撤销通过三项都各有证据，才允许接到执行入口。

P-MT、P-ID与P-LOCK是边界探针，不是完成所有私有API、活体识别和OS解锁研究的替代品。它们阻止把第一轮的猜测继续传给执行模型；尚缺哪一项已明确写出。
