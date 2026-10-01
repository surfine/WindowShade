# 盖角推送探针

只为一个问题存在：**这台机器上的盖角设备（usage page `0x20` / usage `0x8A`，产品名 `las`）
会不会主动推送角度变化（input report）？**

## 为什么问

App 目前靠轮询 feature report 拿盖角：一次读实测 **0.914ms**（100 次平均，最大 1.71ms，
Mac17,4 / macOS 27.0）。静止时按 4Hz 问，就是常驻约 **0.37% 单核**——这是修掉「效果开着多出来的
CPU」之后，解锁状态下最大的一笔常驻开销。如果设备会推送，就能改成事件驱动、只留极低频兜底，
把这 0.37% 基本全部省掉，而且**不影响合盖动画的手感**（推送比 12Hz 轮询更快）。

设备属性里 `maxInputReportSize = 8`，说明它**支持**输入报告；但它到底会不会在角度变化时发，只能实测。

## 跑法

```sh
bash tests/run-lid-report-probe.sh              # 默认 15 秒
bash tests/run-lid-report-probe.sh --seconds 30
```

跑起来后**慢慢把屏幕合上再打开**（别合到底休眠）。探针会同时订阅推送、每 250ms 读一次 feature 对照，
结束时给结论。锁屏下也能跑，但那时没人动盖子，`input=0` 不算结论。

探针只读：不写设备、不改 `ReportInterval`、不碰 App 的设置，也不进 App 包。
