# 上游取舍与归属

本轮主应用新增代码为独立实现；没有把 GPL/AGPL 代码、品牌素材、受限制模型权重或认证材料混入 MIT 发行。第三方实验 checkout 和工具链留在忽略的 `.build`。协议格式向量的具体来源另见 [remote.md](remote.md)。许可判断不等于真实设备能力验收。

| 上游固定版本 | 本轮采用或保留 | 边界 |
|---|---|---|
| [Atoll 903d1ed](https://github.com/Ebullioscopic/Atoll/tree/903d1ed3f8afb2a672bdf6d3b57704d3a07603a0) | 核对HUD状态更新、取消旧计时、活动保持；独立修当前选择被挤走 | GPL-3.0；只研究行为，不拷源码/素材 |
| [Hyprland 5a78b5e](https://github.com/hyprwm/Hyprland/tree/5a78b5e927345860a27e2893bf894f97ee620c48) | 活动驱动调度、按所有者合并更新；现有性能修改保留 | BSD-3-Clause；未移植Wayland执行器，未声称当前性能达标 |
| [atv-core 8a4ada2](https://github.com/corvofeng/atv-core/tree/8a4ada29bb7cad31e0315c3387b277eb9ab8c988) | 遥控协议参照 | Cargo声明MIT，根LICENSE缺失；未复制代码；M3未验签的结论不采用 |
| [pyatv 0.18.0 / b277a4c](https://github.com/postlund/pyatv/tree/b277a4c8222ecdcbaab8a24e3e713ca44765adb4) | OPACK/握手格式和独立编码向量 | MIT，Copyright (c) 2020 Pierre Ståhl；本轮Swift格式实现原创 |
| [Loupe 2262efd](https://github.com/mysk-research/loupe/tree/2262efd4456ecba802e1c69f6012859b92eec969) | 读取来源/用途/保存去向登记；修现有隐私遗漏 | MIT代码，品牌素材另限；隐私页不额外采集 |
| [Glance b97f521](https://github.com/jonnyoo/glance/tree/b97f521397ec1197ba17768ba797cae1e628848d) | 录入/对齐/锁态工程参照 | MIT代码不等于ArcFace权重可商用；录像活体缺口、焦点输入路径不采用 |
| [AirBattery 134e02f](https://github.com/lihaoyun6/AirBattery/tree/134e02f2861f933b862b2b6a9562a7f55e505e97) | 多组件、来源与未知状态参照 | AGPL-3.0，只研究不拷代码；本轮未新增AirPods真实读取 |
| [Lipflow e37453b](https://github.com/amywork777/lipflow/tree/e37453b1e1e125ca7130e4abf2635117635f6e0b) | 真实帧时间、个人数据留出；独立几何模板实验 | MIT代码，NOTICE列LRS3模型非商业研究；未下载英语权重、未调用云端 |
| [QuietGlass 6025c4d](https://github.com/clintonimaroo/quietglass/tree/6025c4d29a2d2e797feb1e53be77b6915da8e431) | 共享物理相机/最后消费者停止/代次作废 | MIT；独立实现在既有FaceObservationSource内，未移植身份权重 |
| [Alcove](https://github.com/henrikruscon/alcove-releases) | 连续操作体验参照 | 官方明确非开源；不是源码复用对象 |
| [PlayPort 9a0882d](https://github.com/youcci/playport/tree/9a0882dd0ffe48e467b59d58b12d81391df55ade) | 独立构建及无凭据合成测试 | GPL-3.0；独立实验，无认证身份、未进MIT App |
| [LIVI 9b6abb4](https://github.com/f-io/LIVI/tree/9b6abb401537ce747c176a25900cdedad3253c59) | 后续原生媒体与硬件后端参考 | GPL-3.0+；未购买、刷写或移植 |
| [DiPlay 4ab5337](https://github.com/shihabal3amri/DiPlay/tree/4ab5337c097ad9e3a786959bff10999234b4154b) | 恢复/缓冲/失败用例参考 | 接收栈、UI、素材分别许可；不提取APK实验私钥 |

模型许可另外见 [identity-and-mouth.md](identity-and-mouth.md)。固定版本是本轮研究与验证对象，不暗示未来上游版本延续这些结论。

补充：BLEUnlock 固定 `2eeb35dcaa4e34ac994380e5dc9c0a692a6f7394`，仅研究接近采样与代填路线，未复制其代码；许可未裁定，不作为可直接分发来源。隔离 SRP 探针参考 Apple HomeKitADK `fb201f98f5fdc7fef6a455054f08b59cca5d1ec8` 的 Apache-2.0 实现，保留许可证和修改说明；测试 oracle 为 srptools 1.0.1。该 C/OpenSSL 探针不属于主 App 的可发行依赖，详见工具目录 README。
