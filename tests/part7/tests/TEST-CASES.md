# 本轮实际新增测试

源代码与结果文件配套。多个断言属于同一个场景，不把循环次数冒充新增用例。

|套件|场景|断言|结果|
|---|---|---:|---|
|core|JSON01 empty object|1|PASS|
|core|JSON02 nested|1|PASS|
|core|JSON03 duplicate|1|PASS|
|core|JSON04 escaped duplicate|1|PASS|
|core|JSON05 nested duplicate|1|PASS|
|core|JSON06 surrogate pair|1|PASS|
|core|JSON07 lone high surrogate|1|PASS|
|core|JSON08 lone low surrogate|1|PASS|
|core|JSON09 leading zero|1|PASS|
|core|JSON10 fraction exponent|1|PASS|
|core|JSON11 trailing data|1|PASS|
|core|JSON12 trailing comma|1|PASS|
|core|JSON13 invalid escape|1|PASS|
|core|JSON14 raw control|1|PASS|
|core|JSON15 unicode|1|PASS|
|core|JSON16 incomplete exponent|1|PASS|
|core|JSON17 deep|1|PASS|
|core|JSON18 whitespace|1|PASS|
|core|JSON19 size and node budgets|3|PASS|
|core|URL01 browser scheme and exact host|8|PASS|
|core|WIRE01 duplicate keys close before RPC interpretation|2|PASS|
|core|QUIT01 both owners must settle|3|PASS|
|core|QUIT02 updater alone cannot release child|3|PASS|
|core|WIRE02 ambiguous result/error envelope|2|PASS|
|core|QUIT03 veto and double begin|3|PASS|
|core|PROFILE01 creates private state without overwriting changes|6|PASS|
|core|PROFILE02 project configuration and linked state reject|3|PASS|
|native|NATIVE01 direct child ignores TERM then owned group KILL|6|PASS|
|native|NATIVE02 inherited descriptor descendant cannot delay direct exit|5|PASS|
|native|NATIVE03 unrelated descriptors do not reach child|3|PASS|
|flow|FLOW01 local launch and actual stream completion|21|PASS|
|flow|FLOW02 resume only the locally associated project|8|PASS|
|flow|FLOW03 different project cannot reuse old thread|6|PASS|
|flow|FLOW04 actual login response and exact login ID|10|PASS|
|flow|FLOW05 interrupt RPC is not final completion|12|PASS|
|flow|FLOW06 elevation always declined by local entry|9|PASS|
|flow|FLOW07 failed turn is not successful completion|7|PASS|
|flow|FLOW08 mismatched version|7|PASS|
|flow|FLOW09 effective config mismatch|7|PASS|
|flow|FLOW10 duplicate raw JSON|7|PASS|
|flow|FLOW11 reject arbitrary auth URL|7|PASS|
|flow|FLOW12 unrelated login completion cannot authenticate|6|PASS|
|flow|FLOW13 project replacement invalidates submission|6|PASS|
|flow|FLOW14 actual lock invalidation and no automatic restart|6|PASS|
|flow|FLOW15 diagnostics are opt-in and clearable|7|PASS|
|flow|FLOW16 version-probe cancellation still awaits reaping|6|PASS|
|flow|FLOW17 version timeout does not invent a reap receipt|5|PASS|
|flow|FLOW18 login cancellation requires fresh account verification|8|PASS|
