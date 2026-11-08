# 厂商研究：Pixel 强认证、视频防伪与三星防窥

检索与核对日期：2026-09-30。优先官方研究页、论文原文、系统规范与厂商支持文档。
本记录区分论文、产品说明与工程推断；不把宣传页叫作论文，也不把旧论文标成最新。
尚未找到公开可复现的 Pixel 8 完整面部认证模型、权重与训练/攻击评估配方。
Samsung 本轮找到的直接相关认证论文较早，未找到公开的 S26 面部认证完整实现论文。

## Pixel 8 的例子成立，目标需要修正

[Google Tensor G3 官方说明，2023-10-04](https://blog.google/products-and-platforms/devices/pixel/google-tensor-g3-pixel-8/)
明确写 Pixel 8 的 Face Unlock 达到 Android 最强生物认证等级，可用于银行登录和 Google Wallet；
官方将提升归于机器学习进展，同时说明 Tensor security core 与 Titan M2 的安全架构。
[官方硬件规格](https://support.google.com/pixelphone/answer/7158570) 列出 10.5 MP Dual PD 前摄。
它不是 Face ID 式专用 TrueDepth 系统；不能仅因缺少专用 3D 模组，就断言 RGB 路线不可能成为强认证。

但官方声明没有公开说明每一种 Dual PD 原始信号怎样参与认证；不采用“必定从双像素还原深度”这类推测。
单目估计出的深度也不等同于可信测距，照片中的三维脸同样可能被模型预测出深度。
Mac 摄像头是否给第三方提供同样输入、可否建立可信采集与认证链路，都必须单独核定。

[AOSP Measure biometric unlock security](https://source.android.com/docs/security/features/biometric/measure)
按安全架构、防伪及错误接受等指标分级。Class 3 是完整实现的等级，要求 secure pipeline、攻击测试与 BCR；
不是“用了某个网络”便达标，也不是单张照片识别准确率高便达标。
FAR、FRR 与 SAR 不能混用：相似陌生人、本人失败与伪造攻击的统计对象不同。
不能把某次基准的 AUC 换算成 Class 3，不能说 Class 3 等于永不被破解。

[Google 面部解锁支持文档](https://support.google.com/pixelphone/answer/9517039)
列有光线不足等使用限制。最新 [Pixel 11 Pro 官方页](https://store.google.com/product/pixel_11_pro?hl=en-US)
又说明低光识别提升；这是当前产品声明，仍不是可以直接复制到 Mac 的公开算法论文。
因此 WindowShade 应把 RGB 强认证视为可研究的方向，以真实攻击与本人误拒评估决定上线条件。

## 找到的研究及可迁移内容

| 公司/来源 | 日期与真实范围 | 对 WindowShade 的作用 |
| --- | --- | --- |
| [Apple，Multi-Frequency Fusion for Robust Video Face Forgery Detection](https://machinelearning.apple.com/research/multi-frequency-fusion) | 2026-03；视频伪造检测，将低频 wavelet 特征与相位或 LBP 线索融合；Xception 基础模型仍有约 21.9M 参数，新增融合块 292 参数 | 作为图像防伪候选研究；不能把“仅多 292 参数”说成整个模型只有 292 参数。报告 AUC 提升，不是身份认证或 Class 3 证据，也不覆盖所有实物面具/相机注入 |
| [Google Research，Anchored diffusion for video face reenactment，WACV 2025](https://research.google/pubs/anchored-diffusion-for-video-face-reenactment/) | 2025；生成连续、较长的人脸视频，属于生成研究 | 帮我们构建表情/转头合成攻击测试集；它不是 Pixel 防伪模型。说明“会动的脸”不够，应核定当次挑战与来源 |
| [Google Research，Evaluating Login Challenges as a Defense Against Account Takeover](https://research.google/pubs/evaluating-login-challenges-as-a-defense-against-account-takeover/) | 2019，较早但直接讨论设备因素与用户摩擦；真实账号劫持场景，不是本地面部认证基准 | 借鉴按风险追加持有设备确认与恢复设计；不将云账号防钓鱼成功率套到 Mac 解锁 |
| [Samsung，Behavior-based user authentication on mobile devices in various usage contexts](https://link.springer.com/article/10.1186/s13635-022-00132-x) | 2022-09-16；BehaviorID 的情境依赖 A-RNN 多模态行为研究，公开/内部移动数据集 | 借鉴短时事件触发、情境分组、低负担与长期漂移；不照搬“习惯不同即使密码正确仍锁着”的策略，否则违背用户的恢复要求 |
| [Samsung，IronMask，CVPR 2021](https://research.samsung.com/research-papers/IronMask-Modular-Architecture-for-Protecting-Deep-Face-Template) | 2021；保护深度面部模板的模块化编码，非活体检测 | 模板保护作为后续候选；论文指标是模板方案实验，不证明相机链路、防伪或人群覆盖。首版先做本地加密和删除 |

上述 Apple 2026 与 Google 2025 论文较新；Samsung 两篇是本轮查到且与需求直接相关的较早论文。
未对三家全部论文建立穷尽索引，不声称它们是各公司绝对最新的一篇。没有找到的内部实现不补编成公开事实。
Samsung 官方 [BehaviorID 研究说明](https://research.samsung.com/blog/Towards-Next-Gen-Authentication-context-adaptive-behavior-based-device-unlocking)
也提醒情境、体力活动、持续采集与隐私/电量会影响部署；“信号更多”不是独立因素更多。

## Galaxy S26 Ultra 防偷窥属于屏幕能力

[Samsung 2026-03-16 说明](https://www.samsung.com/ae/support/mobile-devices/when-i-turn-on-privacy-display-the-ppi-clarity-and-brightness-decrease-on-my-galaxy-s26-ultra-why-does-this-happen/)
区分 Wide Pixels 与 Narrow Pixels；Privacy Display 主要使用窄角像素。
[官方使用指南](https://www.samsung.com/us/support/answer/ANS10010349/)
允许按应用、输入锁屏凭据与通知等条件开启。这里核定的是 **S26 Ultra**，不是所有 S26 系列机型。
它能限制侧面视角，并不依赖每次先识别人脸、判断谁正在偷看，也不是面部认证等级证明。

Mac 的普通屏幕不能由一层软件改变像素出光角度。WindowShade 可借鉴用户自选场景、
刘海轻提示、暂停/恢复与隐藏自己能控制的敏感内容，但画面遮罩对正面本人也生效。
旁人检测可做本地可选提示，不把多人检出直接锁机；视频会议、家人、镜面、海报都需要测。
摄像头视野外的旁人无法检测；不能承诺软件已实现 Samsung 那样的光学防窥。

## 下一步的可验证目标

1. 原生 AVFoundation/Vision 提供质量、脸与注意力候选；Core ML 跑许可明确的身份与防伪候选模型。
   安全链路可达到什么级别单独记录，不能拿 Apple silicon 或 Secure Enclave 签名替整个相机链路背书。
2. 本机数据按日期、相机与环境留出测试，加入打印、屏幕重放、四动作预录选片、合成嘴形/转头、
   多人、相似人、虚拟/被篡改采集输入及设备转发。同步、动作和深度推断各自有假阳性。
3. 分别报告身份 FAR/FRR、PAD 的 APCER/BPCER、攻击覆盖、未知比例、p50/p95、CPU/功耗与恢复时间。
   攻击类别和操作者不能只用训练集里已见过的类型；产品原型不能仅通过合成状态单测即上线自动解锁。
4. 强认证仍依靠经过验证的系统/配套设备交易；弱环境与习惯只建议追加验证，始终保留系统恢复。
   真锁屏后恢复桌面由系统状态决定，等待推理不重启动画、不卡每帧渲染。

目前交付研究与独立小样，不宣称已达到 Android Class 3 或 Face ID 等级，也未实现支付认证。
完整产品与安全边界的剩余接线见 [锁屏方案](lock-unlock-plan.md) 和 [使用者边界](authentication-boundaries.md)。
