# 实物遥控器能力探针

`bash tools/probes/game-controller/run.sh --build-only` 只编译。

由主代理协调设备测试时，运行 `.build/game-controller-probe/GameControllerProbe --list` 枚举当前由 GameController 暴露的设备；运行同一二进制 `--observe 60` 观察 60 秒。输出 JSONL：设备 vendor/productCategory、extended/micro profile、元素名和变化值，最多 2000 次变化。观察为 20 ms 轮询，短促变化可能漏采，不能作为延迟或完整按下/松开验收。

不调用设备发现或配对，不替换输入回调，不注入按键、不路由 WindowShade。观察模式只在此独立进程临时开启 GameController 后台事件，结束恢复。枚举为 0 只表示本次系统接口没有返回控制器，不证明设备没有配对。现有 `WS2GameControllerBridge` 只接纳 extendedGamepad；如果 Siri Remote 仅暴露 microGamepad，还缺产品桥接。

编译已通过 Swift 6。此文件建立时未运行设备会话，物理设备结果由主代理记录。
