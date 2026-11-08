# L1 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|L1-01|成功读取后超过两秒未新读|仍在场；新读超时才离开；两秒是请求超时，不是 lastSeen 超时；请求未超时；请求两秒后进入宽限|`tests/PresenceLockTests.swift:22–27`|
|L1-02|明确断开后 1.5+10 秒|先准备，commit 才依序收起/暂停/请求锁；静默宽限截止；十秒倒数；准备不冒充已锁；固定动作顺序；真实回执才归属自动锁|`tests/PresenceLockTests.swift:28–35`|
|L1-03|宽限内新代次重连，旧代次断线晚到|取消且不被旧事件复活；重连取消；旧代次丢弃；新读证实存活|`tests/PresenceLockTests.swift:36–42`|
|L1-04|倒数到点与用户输入同批|输入先取消；其后每次输入重置60秒静默期；同批输入优先；连续60秒从最后输入算；再从宽限开始，不立即锁|`tests/PresenceLockTests.swift:43–49`|
|L1-05|手机+手表，另一个未知或在场|不锁；两者明确离开才倒数；未知手表不等于离开；两者都 away|`tests/PresenceLockTests.swift:50–55`|
|L1-06|极弱 RSSI 或蓝牙不可用|不据此判人离开；RSSI 不锁；失能后的旧断线不触发|`tests/PresenceLockTests.swift:56–60`|
|L1-07|摄像头无首个健康有人帧或回调停了|不算人已离开；初始空画面不武断离开；健康连续缺人十秒才宽限；摄像头回调失效取消倒数|`tests/PresenceLockTests.swift:61–68`|
|L1-08|锁屏请求无实际回执或错误编号|不认定已锁，不建立返回资格；错编号不成立；三秒无回执只能未知|`tests/PresenceLockTests.swift:69–73`|
|L1-09|自己的锁+新连接读取+连续强RSSI|仅请求现有身份授权，最多三次；三次不同请求编号，无解锁动作；只恢复本次锁归属的媒体；解锁回执幂等|`tests/PresenceLockTests.swift:74–89`|
|L1-10|手动锁|不产生返回授权请求；手动锁无资格；手机单因素不开放|`tests/PresenceLockTests.swift:90–95`|
|L1-11|prepare后同批取消与commit、关闭后晚到锁回执|不锁或不授予归属；提交前最后取消点；关闭后不能新获归属|`tests/PresenceLockTests.swift:96–102`|
|L1-12|时钟倒流、睡眠后旧回调|拒绝；唤醒等待真实锁态；倒流拒绝；睡醒不能用旧证据锁或开|`tests/PresenceLockTests.swift:103–107`|
|L1-13|自己的锁但仍是旧连接、刷脸关闭或RSSI恰为-60|都不产生返回授权；旧连接即便强信号也没有返回资格；等于阈值不算大于阈值；确实有本次锁归属和新连接，但不开放手机单因素|`tests/PresenceLockTests.swift:108–126`|
|L1-14|强RSSI中途出现NaN|连续时长重算，不沿用坏样本前的积累；无效样本打断两秒连续性；重新连续两秒后才形成候选|`tests/PresenceLockTests.swift:127–134`|

## 重复执行

`bash tests/run-presence-lock-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
