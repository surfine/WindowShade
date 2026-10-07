# 日常体验复核与两处修复

2026-10-07。沿用设计稿索引及《一颗岛》音量连按画面、copy-guide；没有扩展界面、重写来源或修改 Runtime。

## 本轮实际修复

1. `prototype/Core/NotchActivities.swift` 原先直接取优先级前三并清掉被挤出的选择；第四个高优先持续活动到来，会把用户正在看的音乐赶走。现在仍存在的选择保留一个名额，其余按原优先级排序，总数最多三条；结束/过期才撤掉选择。新增用例覆盖第四项、进度更新和结束后补位。
2. `prototype/Core/DeviceBattery.swift` 原先在检查新鲜度之前根据充电/回升重新武装提醒。陈旧的充电或高电量采样会清掉已提醒档位，下一次新低电读数于是重复提醒。现在先检查新鲜度，旧事实不能重新武装。新增两条回归，分别覆盖陈旧 charging 和陈旧电量回升。

## 已有能力与实际边界

| 项目 | 源码事实 | 本轮结论 |
| --- | --- | --- |
| 媒体原子结果与旧回调 | `NotchActivitySources.poll` 先收集 snapshots，再在主线程检查 epoch/running 后一次 onSnapshot；stop 取消 workToken、增加 epoch、清媒体缓存 | 已有来源级隔离，未另造状态流；真实播放器控制回执仍需真机 |
| HUD 状态与计时 | `NotchPanel.presentLevel` 整体赋值 `Level(kind,value)`，主线程撤销旧 levelTimer 后建一次性 1.2s timer；认证时不呈现，有 Alcove/MediaMate 则让位 | 未发现与 Atoll 逐字段 didSet 相同的问题，不为对齐源码而重写。系统双提示、显示器及锁屏退路仍未真机验收 |
| 三活动 | Store 原有 startedAt/priority/id 稳定排序，不按 updatedAt 排序，代次与墓碑阻止旧活动复活 | 本轮补第四项保留当前选择；不扩展活动中心 |
| 电量组件与未知 | DeviceBatteryBook 对耳机固定 left/right/case；nil 不显示成0；盒子只用盒子读数；freshness 不由 lastSeen 续期；身份与显示名分开 | 模型已具备，但 **AirPods 三组件真实电量来源仍 unproven**。当前 NotchActivitySources 通过 CoreAudio 设备名显示耳机活动，不等于读到电量 |
| 妙控身份 | PeripheralBatterySource 从 DeviceAddress/SerialNumber 建来源命名空间身份，缺可靠标识拒绝建档；IOKit通知连接，120s电量采样 | 不能将这份设备覆盖宣传为全部 Apple 配件 |

## 隐私盘点交给主模型统一登记

`WS2PrivacyData.swift` 标明由 `tools/privacy/registry.json` 生成，本轮没有手改生成文件。已有 music 行登记曲目、用途、系统自动化权限和不写标题日志。

发现两处需补齐：NotchLevelObserver 实际有 CoreAudio 音量监听和 DisplayServices 私有亮度读取（0.2s）；登记表未搜到对应类/接口。battery 行只写“内存”，但 DeviceBatteryController 将低电提醒档位保存到 `DeviceBattery.alerted.v1`；独立开关实际为 `Notch.deviceBattery.enabled`。主模型已统一修改 registry、重新生成页面并通过同步检查；详情与当前摘要见 verification.json。

## 验证

运行既有 `tests/run-notch-activity-tests.sh` 与 `tests/run-device-battery-tests.sh`，通过。首次因默认 clang 缓存目录不可写未进入编译；设置 `CLANG_MODULE_CACHE_PATH` 和 `SWIFT_MODULECACHE_PATH` 到 `$PWD/.build/module-cache` 后重跑。未运行全 App 构建，未操作真机播放器、系统音量或配件。`git diff --check` 通过。
