# 卡顿账

`scripts/perf-report.sh` 每跑一次 `--hitch` 追加一行（只报不挡：数字对照 Apple 卡顿预算，不过线也不拦发布）。完整数据在 `.build/perf/<日期时间>-<build>.json`（kind、n、ratio、worst、p95、刷新率、档位）。

- 预算：真机 ratio < 5 ms/s 且 worst < 100 ms；虚拟机图形是半虚拟化的，只看 worst < 500 ms，ratio 仅供参考。
- 末列每类写作 `类 ratio(ms/s)/worst(ms)`；类有 fold、unfold、browser-open、browser-close、glance-show、glance-hide。
- 跑法：主机 `scripts/perf-report.sh --host`（先 `cd prototype && ./build.sh --stage`，本机闲置 20 秒以上）；虚拟机 `scripts/perf-report.sh --vm lume@<ip>`。
- `scripts/release-gate.sh` 会打印候选包 build 号对应的最近一行（INFO）。

| 日期 | 版本 (build) 提交 | 机器 | 刷新率 | 对照预算 | 各类 ratio/worst |
| --- | --- | --- | --- | --- | --- |
| 2026-10-18 | 1.0.18 (build 18) 752769708 | VM wsqa-manual · macOS 26.6.2 · 2 vCPU | 60 Hz | 超预算：browser-open（虚拟机仅 worst 判） | fold 402.3/326; unfold 606.1/350; browser-open 187.6/539; browser-close 87.9/204; glance-show 4.3/51; glance-hide 0.0/17 |
