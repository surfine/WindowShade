# WindowShade × Loupe × Glance：整合路径

2026-10-03。Aaron：“请你提出 WindowShade 和 Loupe、Glance 的整合路径，驭繁为简。”

| 项目 | 是什么 | 许可 | 对 WindowShade 的意义 |
| --- | --- | --- | --- |
| [jonnyoo/glance](https://github.com/jonnyoo/glance) | Mac 上的刘海面容解锁：锁屏时刘海里出现扫描动画，认出你就替你输入登录密码（`com.jonathan.glance`，macOS 15+） | MIT | “认”：锁屏上的刘海交互、锁屏状态判断、按显示器选摄像头、活体线索、Touch ID 保护的会话 |
| [mysk-research/loupe](https://github.com/mysk-research/loupe) | iOS / iPadOS（Mac 版未完成）隐私科普 App：把任何 App 不用问就能读到的设备信号原样摊开，分“不用问 / 要你同意 / 进阶”三层，每条写清为什么能认出你 | 代码 MIT；名字、图标、图片、设计源文件保留权利 | “明”：让人看清 WindowShade 自己读了什么、为什么读、去了哪里 |

## 一句话

**一个刘海、四本账，不并第三套代码。**WindowShade 已经有刘海宿主、活动协调和一次性授权账本；再加一本“读到了什么”的信号账。
Glance 的东西只往授权账和刘海宿主里接，Loupe 的东西只往信号账里接。凡是读数据的，都在信号账里登记；凡是放行的，都走授权账。

## 三步

### 第一步：并存（先做，1–2 天）

Glance 管锁屏，WindowShade 管解锁后的桌面，两边不抢同一个刘海。

- 检测到 Glance 在运行（`com.jonathan.glance`）时，锁屏期间 WindowShade 不画锁屏开合效果、不开面部动作检测，刘海让给 Glance。
  两边的刘海面板都在 `.mainMenu + 3` 附近，锁屏时 Glance 还会把面板抬进 SkyLight 的高层空间，同时画就会叠在一起。
- 解锁后 WindowShade 接手：桌面开合效果照常从刘海那里展开。
- 只改检测和让位两处，不引入 Glance 的代码。你今天就能用 Glance 解锁，同时用 WindowShade 管窗口。
- 要实验确认的：Glance 在没锁屏时刘海里是否常驻一颗胶囊、悬停时是否有触感反馈（会和我们刘海的悬停打架）；若常驻，就按显示器协调谁画。

### 第二步：“WindowShade 读到的”透明页（照 Loupe 的做法）

> 设计稿和接手要求见 [privacy-page.md](privacy-page.md)（2026-10-03）。

设置里新加一页，把 WindowShade 读的每一样东西原样摊开，照 Loupe 分三层：

| 层 | WindowShade 里的例子 |
| --- | --- |
| 不用问 | 屏幕和刘海的形状、电池与电源、铰链角度、加速度（倾斜效果）、Dock 位置 |
| 要你同意 | 辅助功能（窗口标题、位置）、屏幕录制（窗口画面）、摄像头（只取几何，不存图）、蓝牙配件电量、播放器（自动化） |
| 进阶 | 系统私有接口：`NSScreen.bezelPath`、SkyLight 的空间、`CGSHWCaptureWindowList`（最小化窗口的画面） |

- 每一行写三件事：现在读到的值（打开这一页时才读）、为什么读、去了哪里（只有检查更新会联网，其余都不离开这台 Mac）；能关的给开关。
- 代码层面借 Loupe 的结构：一个 `SignalProvider` 协议加 `Sensitivity` 三层，每条带一句理由。Loupe 的代码是 MIT，带版权声明可以借；它的名字、图标、图片不能用。
- 为什么值得做：v4 规格要求按用途分别申请权限、数据不出本机；Newlearner 这样的人推荐一个要辅助功能和屏幕录制的工具之前，最想知道的就是这一页上的内容；也合 SSC 的“隐私是基本人权”。

### 第三步：把“认”接进授权账（照 v4 的闸门）

从 Glance 吸收做法，不照搬它的解锁方式：

| Glance 的做法 | 怎么接 |
| --- | --- |
| `LockMonitor`：锁屏状态只认 `CGSessionCopyCurrentDictionary`，通知只当触发；`screenIsLocked` 比系统真正挂起早约 150 毫秒 | 对照我们的 `SessionLockState`，补上它记下的几个坑 |
| 锁屏上用 SkyLight 空间把刘海面板抬到锁屏之上 | 我们的 `LockSpaceBridge` 已经是同一种做法，对照它的降级处理 |
| 内建屏和外接屏分别选摄像头 | 我们的面部动作检测已有选摄像头，补上按显示器记忆 |
| 活体：否决线索（屏幕反光、手机边框）一票否决，确认线索（3D 几何、鼻子视差、眨眼）任一即可 | 进 v4 的 A3 研究通道，作为结构参考 |
| Touch ID 保护的会话，空闲一段时间自动重新上锁 | 并进我们的一次性授权账：用途、目标、时限、到期失效 |
| Face Lab 调试台 | 做成我们的探针 |

**两件不默认照搬**（v4 已定的边界）：

- **存登录密码、在锁屏上替你打字。**Glance 自己也写明这是“便利，不是安全升级”，挡不住你的视频。v4 要求后端没核实前不这样凑出“已解锁”。
- **ArcFace 人脸特征当身份闸门。**先按 v4 的 A0 核对 Apple 协议里 Face Data 的用途限制。

## Aaron 定的（2026-10-03）

**吸收**：刷脸解锁做进 WindowShade 自己的刘海，照 Glance 的方式真正解锁（开启前写明风险），每次都要手机或手表这第二个因素。逐项决定见 [direction.md](direction.md)“刷脸解锁：吸收 Glance”。下面第一步“并存”改为过渡：WindowShade 的刷脸解锁上线前，检测到 Glance 就让开。

## 原来要 Aaron 定的（已定，见上）

1. **解锁这件事：并存，还是吸收？**并存就是让 Glance 管锁屏、WindowShade 不重复做面容解锁（推荐，最简单）；吸收就是把面容解锁做进 WindowShade 自己的刘海。
2. **“便利解锁”（存密码、代打字）能不能作为明说风险、默认关的选项？**v4 默认不做；若可以，照 Glance 那样把风险写在开启之前。
