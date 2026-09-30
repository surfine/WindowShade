# 配件探针

独立 Foundation + IOBluetooth 诊断，读取已配对设备和当前连接状态，不接主 App。

```sh
bash tools/accessory-probe/run.sh --summary
bash tools/accessory-probe/run.sh --list
bash tools/accessory-probe/run.sh --help
```

默认仅输出配对、连接、已连接音视频类设备的数量；`--list` 明确选择后输出名称与状态。
设备名称中的控制字符转义为单行，设备地址不输出。一次只接受一种模式。
查询不可用报未知并退出 1，不误报为 0 台；成功退出 0。

2026-09-30 官方接口已编译运行：本机 11 台配对、3 台连接、其中 1 台音视频类。
音视频类别不等于 AirPods；名字和连接也不证明是谁佩戴或用户是否在场。
AirPods 自动切换、入盒会改变连接状态，不能直接拿一次断连触发安全判断。

目标 macOS 14.0，输出 `.build/accessory-probe/AccessoryProbe`。
不扫描、连接/断开、请求 RSSI 或查询 AirTag/查找网络。
