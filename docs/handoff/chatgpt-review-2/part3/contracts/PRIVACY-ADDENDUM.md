# 第三份隐私增量

原第1份登记表与12处日志替换继续有效。本份没有启用下列读取的生产服务；仅列候选源码与实际测试范围。

|来源|数据|内存去向|落盘/出站|撤销与限制|
|---|---|---|---|---|
|WindowServer后台标题缓存|目标窗口名称/所属App|PinnedPreviewTarget，最多80字符/3秒|不写日志，不出站|pid不符或过期显示泛称；AX目标执行仍重新核实|
|Claude helper stdin|session、event、cwd、当前工具及参数|有界JSON，最多64KiB|仅用户私有Unix socket；不读取transcript|结束清空；错误输出{}不打印载荷|
|Unix socket peer|UID，Darwin需getpeereid|连接准入比较|不记录用户名|不同UID拒绝，同UID仍不能批准助手|
|配置编辑器|用户选定JSON文件|生成预览原文与新文|同目录0600备份/临时文件|写前复核，外部变动拒绝；Mac ACL待验|
|Codex进程stdout|JSON-RPC事件与审批请求|有界wire与请求表|候选owned进程pipe；测试仅Python假后端|断连清缓存，不自动重发，不写提示词|
|手柄/遥控器/MT|本份只有合成输入及旧探针|纯核|无生产硬件采集|桥未实现或未准入时保持关闭|

普通测试fixture仅含虚构标识。`core-tests.txt`不含真实用户内容。不要把真实home配置、授权grant、设备密钥、PIN或转写加入验证日志。
