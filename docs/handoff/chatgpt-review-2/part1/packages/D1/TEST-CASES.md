# D1 输入与预期结果

测试时钟由sec()注入。fixture值全部是测试专用合成ID/摘要/文字，不会请求真实助手或操作系统。下表行范围包含完整输入序列；同一用例内每个expect都是必须保留的行为约束。

|用例|输入情景|预期状态与效果|可执行输入位置|
|---|---|---|---|
|D1-01|总开关关闭，或尚无后端快照|不接管、不提交；默认关闭；连接不等于后端空闲|`tests/ConductorSessionTests.swift:91–95`|
|D1-02|五拍画到第四拍|只有预览；完整抬手才成为费用候选；前缀不修改档位；应显示轨迹；完整五拍仍需点确认|`tests/ConductorSessionTests.swift:96–102`|
|D1-03|候选前已按下的中心键后松开|无效；新的一按才确认；旧按压不能确认；新按压生效|`tests/ConductorSessionTests.swift:103–106`|
|D1-04|费用确认后改草稿|旧票失效，再确认才发最终草稿；票绑定实际草稿摘要；不能借旧票发新草稿；确认后按最终配置和文本提交|`tests/ConductorSessionTests.swift:107–112`|
|D1-05|不支持 xhigh 的模型收到四声|明确拒绝，保留 high；不降档、不猜近似值|`tests/ConductorSessionTests.swift:113–115`|
|D1-06|四个声调与六拍|前四档直接下一轮，六拍候选 ultra；声调 \(n)；六拍不提前放行|`tests/ConductorSessionTests.swift:116–120`|
|D1-07|切模型域，五拍/空槽/第一槽|拒绝、不可用、稳定选择；模型域不认五六档；空位置不移位补足；按稳定 ID|`tests/ConductorSessionTests.swift:121–125`|
|D1-08|电视按住0.5秒、上下选、松开、中心确认|只请求切会话，不换域；列表未打开；长按 release 不切域|`tests/ConductorSessionTests.swift:126–132`|
|D1-09|只有 click 的电视键|350ms 内双击开列表，单击延迟后切域；双击列表；双击不能先切域；单击期满才切域|`tests/ConductorSessionTests.swift:133–138`|
|D1-10|侧键无源、有源但无样本、有样本、松开转写|不画假波形，不自动提交；无源不伪装在听；等待真实采样；收到样本后显示来源；松手停止；转写只成草稿|`tests/ConductorSessionTests.swift:139–149`|
|D1-11|音源丢失后晚到转写|停止、不自动换源，原草稿保留；源断开停止；不覆盖或换源|`tests/ConductorSessionTests.swift:150–155`|
|D1-12|clickOnly 开始采集到60秒|自动停止一次，仍只等转写；最长60秒，不提交；只停一次；正确采集令牌|`tests/ConductorSessionTests.swift:156–162`|
|D1-13|录音期间手动编辑，旧转写随后完成|不覆盖手动内容；草稿版本防旧结果覆盖|`tests/ConductorSessionTests.swift:163–167`|
|D1-14|提交、实际接受、轮次开始|三段独立状态，重复按键不重发；先只说发出去了；在途不重发；接受后读回值；真正运行才显示|`tests/ConductorSessionTests.swift:168–173`|
|D1-15|后端接受但没有实际配置|明说未知，后续读回差异照实显示；不拿请求值冒充读回；后端改档位如实显示|`tests/ConductorSessionTests.swift:174–178`|
|D1-16|turnStarted 先于应答、运行中改下一轮|不退回接受态，不混淆本轮请求；乱序接受不倒放状态；改的是下一轮；本轮对比本轮请求，不拿 next 比|`tests/ConductorSessionTests.swift:179–184`|
|D1-17|运行中有新草稿再播放|带当前 turnID 的 steer，收到对应回执才说补进去了；带期望轮次；错轮回执不清草稿；确认之后才更新|`tests/ConductorSessionTests.swift:185–189`|
|D1-18|运行中无草稿播放|正在停止，只有真实终止通知才已停止；不提前谎报停止；RPC接收不等于已停；明确终止|`tests/ConductorSessionTests.swift:190–194`|
|D1-19|命令15秒无回执|查询状态、不重发；证实未执行后仍要人工再按；未知不当失败重发；未知期拒绝二次发送；查询证明不自动发送；新的人为提交另建 commandID|`tests/ConductorSessionTests.swift:195–202`|
|D1-20|后端明确拒绝|保留草稿，没有自动重试；拒绝后保留草稿|`tests/ConductorSessionTests.swift:203–205`|
|D1-21|锁屏、解锁、旧 epoch 回调|清敏感展示，必须新代次和新快照；锁屏清空；解锁不自动恢复控制；旧回调不能复活内容|`tests/ConductorSessionTests.swift:206–213`|
|D1-22|断开/撤销/电源退出|不发 interrupt，后端任务照跑；退出不是停止任务；准确退出文案；断线保留未发草稿；重连先查询|`tests/ConductorSessionTests.swift:214–220`|
|D1-23|返回两次丢草稿、先候选后草稿|严格按眼前对象取消；先取消候选；第一次仅提示；第二次才丢|`tests/ConductorSessionTests.swift:221–225`|
|D1-24|普通审批前按下、之后松开|不确认；新点按只发给 A1 的授权意图；旧输入不放行；只提出确认请求；确认在途不重复；现有服务通知后更新|`tests/ConductorSessionTests.swift:226–232`|
|D1-25|高风险正确挑战/错摘要/失败声纹|只给授权服务附加证据，失败走主认证；错摘要拒绝；附加证据不等于 allow；失败转唯一服务要求 Touch ID|`tests/ConductorSessionTests.swift:233–239`|
|D1-26|未知风险、挑战超时、审批期限|不降级自动批准，交回或主认证；挑战超时请求主认证；审批到期交回宿主|`tests/ConductorSessionTests.swift:240–244`|
|D1-27|审批期间后端接受/运行通知|不盖掉正在确认的目标；审批视图优先|`tests/ConductorSessionTests.swift:245–248`|
|D1-28|播放长按后松开、相同 up 重发、模式切换取消|不发草稿；长按抑制短按；重复 up 幂等；切模式只撤交互|`tests/ConductorSessionTests.swift:249–254`|
|D1-29|非法坐标、超过2048点、6秒未抬手|拒识，不提交或改档；NaN 不改档；固定输入容量；超时释放笔画|`tests/ConductorSessionTests.swift:255–262`|
|D1-30|草稿跨会话重连|不把旧项目草稿直接发到新会话；跨会话保护；明确编辑之后才能绑定新会话|`tests/ConductorSessionTests.swift:263–267`|
|D1-31|另一台设备试图接管、能力列表为空|拒绝，不改变有效会话配置；同时间只有一台；空能力不启用任意值|`tests/ConductorSessionTests.swift:268–272`|
|D1-32|错误 capture、challenge、command、turn 关联号|不影响当前运行和草稿；错命令不接受；错轮次不结束|`tests/ConductorSessionTests.swift:273–278`|

## 重复执行

`bash tests/run-conductor-session-tests.sh`；可从任意cwd调用完整路径。脚本通过自身路径定位根。FAIL会退出1，编译错误保留非零退出码。当前完整Linux结果见VALIDATION。
