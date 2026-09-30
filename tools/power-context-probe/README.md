# power-context-probe（macOS 电源上下文诊断）

只读诊断工具：查看当前**供电来源类型**，以及公开 API 是否能返回电源适配器详情。

## 用法

```sh
tools/power-context-probe/run.sh           # 默认：电源类型 + 详情可用性
tools/power-context-probe/run.sh --keys    # 仅输出排序后的字典键名
tools/power-context-probe/run.sh --help    # 帮助
```

无参数 / `--keys` / `--help`；其它或多参数会报错并退出码 1。
正常查询即使结果为 unknown 也退出码 0。

## 实际输出的数据

- 供电来源类型（AC / Battery / UPS / unknown）
- 适配器详情是否可用（yes / unknown）
- 可用时且仅限公开可选键：
  - `Watts` = 系统报告的适配器瓦数（非实时功耗，也不保证等于外壳额定最大值）
  - `Current` = 系统报告的适配器电流 mA（非电池电流）
  - `FamilyCode` = 家族编码（非品牌名）
- 缺失或类型不符一律记为 unknown，绝不写成 0 或 false。

`--keys` 模式**只**打印排序后的键名，用于研究字典形状，不输出任何取值。

## 缺失的溯源信息（本工具无法提供）

- 品牌 / 型号 / 物理 USB 端口映射：本工具不作推测；可选序列号字段不输出。
- `IOPSCopyExternalPowerAdapterDetails()` 返回 NULL 既可能是“无适配器”，也可能是查询错误；
  两者无法区分，因此保持为 **unknown**，不当作确定缺失。不输出 AdapterID/SerialNumber，也不 dump 字典。

本工具**不**声称能提供安全身份标识，也**不**声称能给出物理 USB 端口映射。

`run.sh` 使用 `set -euo pipefail`，从脚本路径推导根目录，在
`.build/power-context-probe/` 下用 `swiftc -O` 编译并 `exec` 运行。
仅链接 Foundation 与 IOKit；仅用官方 `IOKit.ps` 公开调用，无 IORegistry 私有调用、不启动传感器、不修改任何设备设置。

本机实际运行：AC 供电，系统报告 94 W、4700 mA、FamilyCode -536854518。
公开字典未给出本工具可核定的品牌或左右端口映射；数值只代表当次系统报告。
