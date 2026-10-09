# 身份证据与动效：接入、整改、动效指点

2026-10-09。只读调研后的计划，没有改任何代码。行号按当天工作区；`App/Notch.swift` 当天正被并行改动，用前按函数名再定位一次。范围：刷脸实验（录脸、锁屏后认出你、随机转头）怎样借 Persona、国内实人认证、Glance、quietglass 的长处；今天代码里的缺陷；刘海动效怎样再上一档。

## 0. 先说结论

1. **能借的是“过程”，不是“底座”。** Persona 和实人认证强在三件事：拍之前先把画面质量管住（提示不算失败）、随机的主动挑战、把“证据”和“裁决”分开。它们的底座（证件、公安库、云端比对、视频留存）WindowShade 一样都不碰。
2. **今天最大的洞有三个，都在 P0：** 转头挑战不核对是不是同一个人（先拿照片过比对，再换真人转头就能拿到“通过”）；默认相机取“列表第一个”，外接、iPhone、虚拟相机都可能被选中；录脸只要写一个偏好键，不用 Touch ID。
3. **证据进授权账，只能加门槛，不能开门。** 新增 `IdentityEvidence`：账本收下、限时、按代次作废、只能用一次；任何用途都不能只凭它发授权。锁屏时账本本来就不发授权，所以本轮人脸证据不会、也不能接系统解锁。
4. **炫彩（屏幕变色）活体本轮不用。** Mac 上只能用刘海和屏幕四周那一圈当光源，离脸约 50 cm，信号弱、要跟自动曝光打架、还受闪光安全上限约束；只保留稿里“暗时四周亮一圈补光”，作为补光，不作活体判据。另开一个探针包测这台 Mac 上的信噪比，过线再议。
5. **AirPods 头动交叉核对是 Mac 独有的加分项。** 挑战时镜头里的转头和耳机陀螺仪的转头要同向、同时；虚拟相机和录像做不出耳机那一半。可选、只加不减。
6. **动效：骨架已对（形状先走、40% 进内容、叠加弹簧带速度），欠的是收尾的几处“瞬间出现”。** 授权对勾、倒数数字、错开上限、40% 门的采样频率、欢迎窗口的贝塞尔曲线，给了 8 条改前改后。

## 1. 读了什么（2026-10-09 读取）

“二手”= 只读到搜索摘要、转述或第三方文章，没读到原文；正文引用时同样标注。

| # | 来源 | 一手/二手 | 取到的 |
|---|---|---|---|
| P1 | [Persona Selfie Verification](https://help.withpersona.com/articles/1l0WTbR5UsfiggNDPWbnUp.md) | 一手 | 回答“这次操作时人在不在场”；默认拍正、左、右三张；与证件照“三点合成”比对并做活体；每项检查 passed / failed / 不适用，只有设成必需的检查决定总结果 |
| P2 | [Persona API：selfie verifications](https://docs.withpersona.com/api-reference/verifications/selfie-verifications) | 一手 | 检查分四类：画质（朝向、分辨率、光线、模糊、遮挡）、比对、活体、年龄；拍法“只拍正面”或“正 + 左右侧脸” |
| P3 | [Persona Inquiry 生命周期](https://docs.withpersona.com/model-lifecycle) | 一手 | inquiry 包住一次用户交互；completed / failed 只表示用户走到哪一屏，approved / declined / needs review 是另一层的业务裁决；默认 24 小时过期 |
| P4 | [Configuring Selfie Verification checks](https://help.withpersona.com/articles/1dsXklKVFkvpSdX90CTtNo/) | 一手 | 先决定更怕误放还是误拒，再定哪些检查必需；一次只改一项，看通过率 |
| P5 | [Understanding Selfie Verification results](https://help.withpersona.com/articles/4BTlLMW5TdKym0zoDzhVV9/) | 一手 | 检查分“欺诈类”和“用户行为类”（后者是画质不达标，API 里叫 user action required）；可关自动拍摄、可改成只拍正面、可允许上传 |
| P6 | [Persona 提示文案参考](https://help.withpersona.com/articles/2fF5jGgyrMGVyWzg0paKDX.md) | 一手 | 自拍提示：Center yourself / Move closer / Move further away / Look slightly left / right / multiple faces；证件提示含反光、太暗、拿稳 |
| P7 | Persona 帮助中心关于“提示不算失败”“一次只换一样”的文章 | 二手（搜索摘要） | 屏上提示不是结果，不计一次失败；重拍时一次只改光线、取景、晃动中的一样 |
| P8 | Persona 处理者隐私政策、2026-06-22 博客（Trail of Bits 代码审查） | 二手 | 默认处理完立即删扫描数据；客户可延长；代码里硬上限三年 |
| P9 | [Biometric Update 2026-06-24 转述 Persona 2026 H1 自拍欺诈报告](https://www.biometricupdate.com/202606/persona-sees-fraud-slop-pale-next-to-simple-presentation-attacks-in-2026-h1-report)（报告原页 403） | 二手 | 呈现攻击 86.2%，注入 10.3%；最常见的是举纸、翻拍屏幕、面具（66.2%）；注入里真人录像多于 AI 合成 |
| P10 | Persona 关于注入、虚拟相机、CEN/TS 18099 的营销与博客 | 二手（搜索摘要） | 设备完整性、Hook 检测、虚拟相机检测、多帧分析；对齐 CEN/TS 18099:2024 |
| C1 | [阿里云 InitFaceVerify](https://help.aliyun.com/zh/id-verification/financial-grade-id-verification/initfaceverify-2) | 一手 | `Model`：SILENT_LIVENESS 静默、LIVENESS 眨眼（默认）、PHOTINUS_LIVENESS 眨眼+炫彩、MULTI_ACTION 眨眼+摇头随机顺序、MOVE_ACTION 远近+眨眼、MULTI_PHOTINUS、MOVE_PHOTINUS；CertifyId 30 分钟内有效、只能提交一次；ID_PRO 只做活体、ID_PLUS 加拍身份证 |
| C2 | [阿里云 活体人脸验证方案](https://help.aliyun.com/zh/id-verification/financial-grade-id-verification/product-overview/face-liveness-verification-solution-for-financial-services) | 一手 | 端上活体 + 云上活体，再与业务留存照片比对 |
| C3 | [腾讯云 人脸核身 微信小程序接入总指引](https://cloud.tencent.com/document/product/1007/31071) | 一手 | 比对源二选一：权威库或上传照片；BizToken 一次有效、7200 秒；结果只留 3 天；“一闪活体”只对有资质行业开放 |
| C4 | 腾讯云开发者文章、工行案例新闻（[2429984](https://cloud.tencent.cn/developer/article/2429984)、[pedaily](https://news.pedaily.cn/20221227/48792.shtml)） | 二手 | 各渠道可用模式（App：光线、数字、动作；PC H5：眨眼）；光线活体＝手机屏按随机颜色序列打光，序列即一次性验证码 |
| C5 | [Face Flashing（arXiv 1801.01949）](https://arxiv.org/abs/1801.01949) | 一手（摘要） | 屏幕随机闪图案，看人脸反射的时序、纹理和三维形状；报告 98.8% |
| C6 | 微信 `wx.startFacialRecognitionVerify` | 二手 | 需姓名+身份证号；主体和类目受限、要资质审核 |
| C7 | [《人脸识别技术应用安全管理办法》全文（新华网 2025-03-21）](https://www.news.cn/politics/20250321/ea3d56716acd40c585bee9052a5c6a7b/c.html) | 一手 | 第六条单独同意、可撤回；第八条存在设备内、不通过互联网对外传输，保存期限取最短；第十条有其他方式时不得作为唯一验证方式；第九条事前影响评估 |
| C8 | 《国家网络身份认证公共服务管理办法》及解读 | 二手 | 2025-07-15 施行；网证基于 CTID；申领要 NFC 读证+人脸；平台只拿核验结果，不再要明文身份 |
| C9 | 《个人信息保护法》第二十八、二十九条 | **未读到**（npc.gov.cn TLS 握手失败） | 按通行文本引用：生物识别属敏感个人信息，处理要单独同意。待核 |
| A1 | [Alcove 首页](https://tryalcove.com/)、[更新记录](https://tryalcove.com/changelog)（内置浏览器展开全部条目读取） | 一手 | 1.7.9、$14.99、macOS 15；1.0.1–1.7.9 全部动效、性能条目，见 §2.4 |
| G1 | [Glance](https://github.com/jonnyoo/glance) b97f521（2026-09-30，MIT） | 一手（源码） | `Liveness/` 目录、录脸环、相机目录、README 风险声明 |
| Q1 | [quietglass](https://github.com/clintonimaroo/quietglass) 6025c4d（2026-09-22，MIT） | 一手（源码与文档） | `OwnerRecognitionPolicy`、`OwnerTemplateStore`、`CAMERA-PROTECTION.md` |
| X1 | [@AVIROK1 2026-08-17](https://fixupx.com/avirok1/status/2089400362382057796)：“FaceID on Mac onboarding” | 文字一手（fxtwitter API）；画面是我逐帧看的 10.9 秒视频 | 见 §2.4 |
| X2 | [@samkohl 2026-07-14](https://x.com/samkohl/status/2077137697840480641)：“If any Apple product has Face ID it should be the MacBook Pro” | 同上，5.7 秒视频 | 见 §2.4 |
| W1 | [WCAG 2.3.1](https://www.w3.org/WAI/WCAG22/Understanding/three-flashes-or-below-threshold.html) | 一手 | 任意 1 秒内不超过 3 次闪烁，或闪烁面积在阈值内 |
| AP1 | Apple `VNDetectFaceCaptureQualityRequest`（文档 JSON） | 一手 | 0–1，越接近 1 光线越好、越清晰、越居中；macOS 10.15 起 |
| AP2 | Apple `AVCaptureDevice.transportType`、`DeviceType.external`（文档 JSON） | 一手 | transportType 是 IOKit 传输类型常量；文档没写 `.external` 在 macOS 上是否含虚拟相机 |
| M1 | 本机相机枚举（只列设备、不开相机，2026-10-09） | 实测 | 内建镜头：`builtInWideAngleCamera` + `bltn`；Apple 外接显示器镜头：**也报 `builtInWideAngleCamera`**，传输是 `usb `；iPhone 连续互通：`external` + `othr`。本机没装虚拟相机，虚拟相机报什么未测 |

## 2. 调研

### 2.1 Persona 怎么做

| 环节 | 做法 | 出处 |
|---|---|---|
| 模型 | inquiry（一次会话，默认 24 h 过期）里挂若干 verification（一次检查，passed / failed）；每个 verification 由若干 check 组成，check 有必需与否；approved / declined / needs review 是会话之外的裁决层 | P1、P3 |
| 证件 | 实时引导防反光、模糊、尺寸不对；默认自动拍摄；建议关闭上传、要求正反面 | P5、P6；正反面与关上传为二手 |
| 自拍 | 正、左、右三张；画质（朝向、光线、模糊、遮挡）是一类检查，比对、活体是另一类 | P1、P2 |
| 活体 | 公开文档只写“检查欺骗迹象”，没写被动/主动、视频的细节；营销材料说多帧、设备与行为信号、虚拟相机和模拟器检测 | P2；P10 二手 |
| 风险信号 | 设备（越狱、模拟器、Hook）、行为、网络、群体分析；最新报告里呈现攻击仍占八成以上 | P9、P10 二手 |
| 重试 | 屏上提示不是结果、不计失败；失败后让用户一次只换一样；旧的 `requires_retry` 状态已废弃，改按 inquiry 内失败次数判断 | P7 二手；verification 生命周期为二手 |
| 无障碍 | 公开页只给了“电脑也能做”“换到手机拍”的入口，没读到具体无障碍做法 | 未核实 |
| 留存 | 默认处理完即删扫描数据，客户可延长，硬上限三年 | P8 二手 |

**对我们有用的三件事**：提示不是失败（画质不达标不扣次数）；检查分“画质类”和“欺诈类”，结果分“检查”与“裁决”两层；一次只给一条提示，且提示说用户能做的动作（靠近、居中、转一点），不说原因。

### 2.2 国内实人认证怎么做

| 环节 | 做法 | 出处 |
|---|---|---|
| 身份来源 | 身份证 OCR 或手输姓名+证件号 → 公安权威库取照片比对；或与业务留存照片比对 | C1、C3；公安专线为 C4 二手 |
| 活体模式 | 静默；眨眼；眨眼+摇头（顺序随机）；远近移动；炫彩/光线（屏幕按随机颜色序列打光，序列即验证码）及其组合；渠道越弱（PC H5）可选越少 | C1；C4 二手 |
| 一次性 | CertifyId 30 分钟、只能提交一次；BizToken 一次、7200 秒 | C1、C3 |
| 留存 | 核验结果只留 3 天 | C3 |
| 合规 | 单独同意、可撤回；人脸信息存在设备内、不通过互联网对外传输；期限最短；有替代方式时不能是唯一验证方式；事前影响评估 | C7；PIPL 条文待核（C9） |
| 网证 | 平台只拿“核验结果”，不再收明文身份 | C8 二手 |
| SDK 画面 | 圆形取景框、一次一个动作、进度提示——这是行业通行样子，本次**没读到**阿里或腾讯 SDK 的界面规格和时长，不写具体数字 | 未核实 |

### 2.3 放到 WindowShade 上：不做什么、借什么

约束（Aaron 已定，见记忆与 `docs/face-unlock.md`）：非商业爱好者应用、不上 App Store；身份只认 Apple 签发的身份；本轮不接真实系统解锁；声纹、脸只作辅助证据；放行只走授权账；系统认证永远是出路。

| 不做 | 理由 |
|---|---|
| 收身份证、读证件芯片、OCR | 我们要回答的是“是不是这台 Mac 的主人”，不是“这人在社会上是谁”；Apple 已经给了 Touch ID / 密码 |
| 接公安库、任何 KYC 数据库或第三方核验 | 同上；而且要资质，个人开发者拿不到（C3、C6） |
| 把脸、裁切图、特征向量发出这台 Mac | C7 第八条；我们的隐私承诺；模板只在钥匙串 |
| 录视频留证、留比对截图 | 不需要；留就成了要保护的东西 |
| 用脸代替 Touch ID / 密码 | C7 第十条；我们的硬要求 |

| 借 | 来自 | 落到哪 |
|---|---|---|
| 画质门 + 动作型提示，提示不扣次数 | Persona P5–P7 | §3.3、§3.8 |
| 随机主动挑战（方向随机、顺序随机），挑战只用一次 | 阿里 MULTI_ACTION、CertifyId 单次（C1）；quietglass | §3.4 |
| 检查与裁决分层 | Persona P3 | 证据（Core）与账本裁决（Ledger）分开，§3.7 |
| 一次性令牌、短有效期 | C1、C3 | 证据 10 s 有效、按代次作废、用一次 |
| 呈现攻击优先防 | P9（八成以上是举照片、翻拍屏幕） | Glance 的屏幕边框、反光否决线索，§3.4 |
| 注入思路：采集完整性 + 设备信号 | P10、CEN/TS 18099（二手） | 相机准入、帧链完整、进程完整、耳机交叉核对，§3.5 |
| 单独同意、可撤回、最短期限 | C7 | 录脸前一页、随时删除，§3.6 |

### 2.4 用户点名的成功体验

**Alcove（A1，更新记录逐条读）**。可直接学的做法，版本号即出处：

| 学到的 | 条目 |
|---|---|
| 一次横扫只算一个动作，门槛调高，展开后才允许切换 | 1.6.6 “Limited swipe to one action per swipe”“Increased swipe threshold for cycle”“Changed to only allow cycle once expanded” |
| 误触反向要专门治 | 1.6.9 “Improved false positive swipe reversals” |
| 空闲降帧、少唤醒，把 CPU 写进条目 | 1.3.4 “prefer lower frame rate while in idle”；1.7.3 “live waveform (0-1% Total CPU)”；1.7.9 “Optimized input monitoring to reduce wakes” |
| 到头时给“过冲”反馈，而且过冲时收得更快 | 1.6.6 “Added HUD overshoot”；1.7.3 “Improved HUD to close faster when overshooting”“Removed overshoot HDR glow” |
| 卡顿当缺陷逐个修，按交互点名 | 1.6.7 “Fixed cycle / collapse / expand / hud stutter”“Fixed race condition hover freeze”；1.6.10 “Fixed expand interaction delay” |
| 状态切换中途被打断不能卡住 | 1.3.6 “Fixed cancelling swipe if notch state changes”；1.2.1 “removed all situations where it could freeze in place” |
| 符号之间的过渡要专门做 | 1.7.9 “Improved transition between waveform and other symbols”；1.4.0 “Fixed transition on focus symbol”；1.7.3 “Improved artwork transitions” |
| 动画速度给档位（平滑 / 快 / 立即） | 1.2.3 “Added speed options for HUDs (smooth/fast/instant)” |

**Glance（G1）**。我们已借了扫描保护（见 `docs/handoff/oss-borrowing-2026-10-08.md:24`），还没借的：
- 活体分两种角色：**否决线索**（屏幕反光 `glossGlare`、手机/平板边框 `deviceDetected`）一触发就判失败、压过一切；**确认线索**（`flatVs3D`、鼻子视差 `depthPose`、眨眼）有一个就够，缺了不算失败。`Liveness/LivenessCues.swift:23-62`。
- 阈值（作者注明“首轮估计，未用真实素材验证”）：反光 0.04 × 3 帧；边框覆盖脸 ≥0.15 × 3 帧（作者说这是真机上唯一证明可靠的线索）；鼻子视差相关系数映射后 ≥0.8（即 r ≥0.6）× 2 帧，且转头幅度 ≥12° 才评；Light 模式至少等 3 帧再放行，让否决线索有机会先触发。`LivenessCues.swift:97-123`、`LivenessScoring.swift`、`DeviceBezelDetector.swift`。
- 鼻子视差：鼻子中心偏离两眼中点的比例应跟着 tan(yaw) 走，平面照片不会。我们的转头挑战正好产生这段转动，可以白拿这条确认线索。
- 录脸环：80 个刻度、8 个 45° 扇区，采到哪个方向哪个扇区亮，扇区内刻度错开亮起（`Onboarding/EnrollmentRingView.swift:5、35`）。
- README 先写“不如 Face ID 安全”“挡得住打印照片和手机屏照片（要开 Heavy），挡不住录像”。这种说实话的写法要学。
- 相机目录同样把 `.external`、`.continuityCamera` 列进来（`CameraDeviceCatalog.swift`），这一点不学。

**quietglass（Q1）**：
- 录脸前、读模板前、删除前都要 Touch ID 或密码（`CAMERA-PROTECTION.md` Privacy 一节）。
- 录脸时 5 个正脸向量，相隔 ≥0.25 s，每个都要和第一个相似度 ≥0.55，否则整轮重来（`OwnerRecognitionPolicy.swift` `OwnerEnrollment.observe`）——防止录到一半换人。
- 验证时**每一帧都要“认得出 + 姿态合格”**才计入转头的保持时间（`OwnerPresence.observe(matches:pose:…)`），丢脸超过 0.35 s 重来；连续性用框重叠 IoU ≥0.6。我们的转头挑战缺的就是这一条。
- 它自己写明“照片或视频能骗过、不提供 Face ID 级安全”；模板存登录钥匙串、可能进备份（我们用数据保护钥匙串、仅本机，更严）。

**X1（@AVIROK1，“FaceID on Mac onboarding”）**，我逐帧看的画面：窗口先空着约 4 秒（大概是录屏开头），面容符号先出现，再出标题“Welcome to FaceID”；约 1.3 秒后符号的嘴角变成蓝色、副标题“Unlock your MacBook by glance”和“Continue / Set Up Later”一起出现；之后一道横向扫描光在符号上从上往下反复扫。可学的是**先主角、后文字、再按钮**的分层，以及“正在看”的扫描环是一个循环、不打扰文字。副标题提到 glance，像是 Glance 的皮肤或概念稿，未核实。

**X2（@samkohl）**，同样是逐帧观察：锁屏上刘海从胶囊长成一个方块（约 0.5 s 内），方块里一团绿色光点收成一个绿环，再在环里画出对勾，停约 1.3 s；之后切到概念镜头。这是 iPhone 面容 ID 的语法搬到刘海：**同一个东西演变（光点→环→对勾），不是换图**。这是概念视频，不是产品。

## 3. 接入计划：录脸与锁屏后认出你

### 3.1 今天有什么（cite）

| 层 | 位置 | 现状 |
|---|---|---|
| 采集 | `App/FaceObservationSource.swift:114-285`（Hub）、`357-619`（Worker） | 一个进程一台相机；帧带 cameraID、generation、sequence、主机时钟 PTS；丢 0.5 s 预热帧和 ≥0.5 s 的陈帧（529、551）；identity 用途请求 10 fps（87）；只给最大那张脸算特征（612-618） |
| 特征 | `App/VisionFaceEmbedder.swift` | Vision 通用图像特征（第 2 版）、1.3 倍裁切、224 见方；偏头 >0.5 rad 不给（27-28）；裁切 <48 px 不给（30） |
| 判断 | `Core/FaceScanGuard.swift` | 每帧重查锁态和代次（133-137）；帧号去重（139）；宽 <0.18 不算（144）；平均模板和最近录入都过线（167-175）；连续 2 帧（69）；认错满 2 s 失败（67、159）；阈值 0.92 未标定（51） |
| 挑战 | `Core/FaceGestureTracker.swift:137-272`、`Core/FaceScanChallengeFlow.swift` | 看镜头 → 随机左/右 → 看回；每步保持 0.25 s、眼睛 ≥录入的 0.78、10 s 超时、丢关键点桥接 1.5 s；结果只写日志 |
| 模板 | `Core/FaceTemplateSet.swift`、`App/FaceTemplateKeychainStore.swift` | 按模型版本一条；≤20 条；数据保护钥匙串、仅本机、不同步；不存图 |
| 接线 | `App/FaceScanExperiment.swift` | 默认关；偏好键开、录、删；锁屏后亮屏开相机 6 s；证据只写一行日志，不进账本（18） |
| 账本 | `Core/AuthorizationLedger.swift`、`Core/AuthorizationModels.swift` | 一次性、绑定用途与目标、锁屏不发（109、137）；没有证据接口 |
| 有人在看 | `Core/BystanderPolicy.swift` | 只看几何，不认人 |
| 耳机头动 | `Core/WS2HeadMotionFeed.swift` | 按显示器的基线、头部手势识别；符号约定未上真机量（6-8） |

### 3.2 两个状态机

**录脸**（只在已解锁时；全程在刘海里，不开新窗口）：

```
off ──用户在设置里点「录下我的脸」──▶ consent（同意页）
consent ──「继续」──▶ framing（取景，只给画质提示，不计失败）
framing ──画质门连续 0.5 s 通过──▶ collecting（正脸 5 帧，相隔 ≥0.25 s，每帧与第一帧一致）
collecting ──一致性失败──▶ framing（整轮重来，提示「只留一张脸」或「稳住别动」）
collecting ──满 5 帧──▶ turnCheck（随机左/右转头，帧帧要像刚才这张脸）
turnCheck ──通过──▶ moreAngles（可选：上下左右再各补一帧，环上扇区点亮）
turnCheck/moreAngles ──完成──▶ confirming（Touch ID：目标是这组模板的摘要）
confirming ──授权消费成功──▶ saved（写钥匙串，回执「已录好」）
任何状态 ──Esc / 关掉 / 锁屏 / 睡眠 / 换相机──▶ off（内存里的帧和向量全部丢弃）
confirming ──没确认──▶ off（「没有确认，没有保存」）
```

**锁屏后认出你**（只产证据）：

```
idle ──亮屏或唤醒，真锁着，有模板，相机准入通过，本次锁屏尝试 <3──▶ framing
framing ──6 s 内没有一帧过画质门──▶ idle（不计失败；刘海说缺什么）
framing ──过画质门──▶ matching（FaceScanGuard，连续 2 帧）
matching ──认错满 2 s──▶ failed(attempt += 1)
matching ──认出──▶ challenging（同一个订阅，不重开相机；提示真正画出来那一刻起算）
challenging ──保持帧都要“认得出 + 框连续 IoU≥0.6 + 无否决线索”──▶ passed
challenging ──方向反了 / 超时 10 s / 丢脸 >1.5 s / 否决线索触发──▶ failed(attempt += 1)
challenging ──相机变了 / 锁态变了 / 睡眠──▶ idle（中断，不计失败）
passed ──▶ evidence（交给账本 record，10 s 有效）──▶ idle
attempt == 3 ──▶ lockedOut（这次锁屏不再看；刘海说「这次请用密码」）
```

### 3.3 画质门（拍之前先管住）

| 项 | 门槛 | 出处 / 状态 |
|---|---|---|
| 脸宽占画面 | ≥0.18；录脸时上限 0.6（太近畸变） | Glance、`FaceScanGuard.swift:66`；上限需真机标定 |
| 人数 | 录脸、挑战：恰好 1 张；扫描：取 ≥0.18 的最大脸 | quietglass；现有 `FaceGestureTracker.swift:238` |
| 朝向（录正脸） | \|yaw\| ≤0.14 rad，眼睛开度 0.14–0.6 | quietglass `OwnerEnrollment` |
| 朝向（比对） | \|yaw\|、\|pitch\| ≤0.5 rad | 现值 `VisionFaceEmbedder.swift:27-28`；建议收到 0.35，需标定 |
| 清晰、光线、居中 | `faceCaptureQuality` ≥ q_min | AP1；Apple 只说 0–1 越高越好，**q_min 需真机标定**，先用“本人录脸时的第 20 百分位”作起点 |
| 亮度 | 脸部裁切平均亮度 Y 在 [L_min, L_max] | 需标定；低于下限先开稿里的补光圈，仍不够才提示「光线太暗」 |
| 反光 | 近白、近灰像素占比 ≥0.04 连续 3 帧 = 否决 | Glance `GlareCueExtractor` 的取法；作者注明未验证 |
| 晃动 | 相邻帧框中心位移 > m（归一化） | 需标定 |
| 裁切像素 | ≥48 px | 现值 `VisionFaceEmbedder.swift:30`；640×480 下 0.18 宽约 115 px，足够 |

一次只给一条提示，按“能做的动作”排序：只留一张脸 → 靠近/离远 → 把脸放到中间 → 看向镜头 → 补光 → 稳住别动。提示变化要有 0.6 s 回滞，免得在两条之间跳（quietglass 文档同样写“短暂波动不换提示”）。

### 3.4 活体：主动挑战为主，被动线索作否决

1. **主动挑战（已有，补两条约束）**：沿用 `OwnerTurnChallenge` 的三步和全部数字，另加——
   - 每个计入保持时间的帧都要 `isOwner == true`，且与上一帧的框 IoU ≥0.6（quietglass）。认不出的帧当丢关键点处理：桥接 1.5 s 内可续，超出失败。
   - 挑战与比对用**同一个相机订阅**，不在中间关相机再开（今天会重开，`FaceScanExperiment.swift:205-209`）。
   - `presentedAt` = 提示真正画到刘海上的那一刻（`FaceGestureTracker.swift:203` 的注释本来就这么要求，今天用的是比对那一帧的时刻）。
   - 反应过快也可疑：提示出现后 <0.2 s 就已转到位，视为没看提示，判失败。0.2 s 是人类视觉反应时下限的常用估计，需真机看分布。
2. **被动否决线索（新增，Swift 重写 Glance 思路，MIT 声明）**：屏幕/手机边框覆盖脸 ≥0.15 × 3 帧、反光 ≥0.04 × 3 帧。任一触发即失败并计一次。边框检测是 `VNDetectRectanglesRequest`，只在 identity 订阅时、每 3 帧跑一次，控制能耗。
3. **确认线索（新增，记录不拦）**：转头段的鼻子视差 r ≥0.6（Glance）。本轮只写进证据的 `cues` 字段，不作门槛，先攒真机分布。
4. **AirPods 交叉核对（可选，只加不减）**：戴着支持头部追踪的 AirPods 时，挑战窗口里镜头 yaw 的变化和 `WS2HeadMotionFeed` 的 yaw 要同号，峰值时刻相差 ≤0.3 s（需标定）。通过就在证据里记 `crossModal = true`；没戴耳机不扣分。符号约定未上真机量（`WS2HeadMotionFeed.swift:6-8`、`FaceGestureTracker.swift:93`），先量再开。
5. **炫彩补光：本轮不作活体判据。**

| 维度 | 手机上的炫彩（C1、C4、C5） | 这台 Mac |
|---|---|---|
| 光源 | 整块屏贴脸 20–30 cm 打光 | 硬要求只有一个刘海宿主、不另起全屏浮层；能用的只有刘海和稿里“屏幕四周一圈”，离脸约 50 cm，照度小一个量级以上（估算，未测） |
| 相机 | SDK 可锁曝光和白平衡 | 网络摄像头自动曝光/白平衡会把颜色变化“补”回去；macOS 上能否锁定因设备而异，未测 |
| 节奏 | 序列很快 | WCAG 2.3.1：1 秒内不超过 3 次闪烁；identity 10 fps，每种颜色要 ≥3 帧，一串 4 色码要 ≥1.5 s，比转头还慢 |
| 收益 | 挡翻拍、挡部分注入 | 翻拍已有边框/反光否决；注入有相机准入和耳机交叉核对 |

结论：只保留稳定的白色补光圈（暗时打开、不闪），作画质辅助。另开探针包 ID-13：暗室里让补光圈在两三种颜色间缓慢切换（每秒 ≤1 次），量脸部裁切的 ΔRGB 与噪声之比；SNR 过线（门槛由探针结果定）再议是否作为确认线索。

### 3.5 防重放、防注入（macOS 上做得到的）

| 手段 | 做法 | 挡什么 | 局限 |
|---|---|---|---|
| 相机准入 | identity 用途只接受 `transportType == 'bltn'` 的内建镜头（M1 实测：外接 Apple 显示器镜头也报 `builtInWideAngleCamera`，只有传输类型能分开）；用户在设置里明确选了别的镜头，证据标 `cameraClass = .external`，策略可以不认 | 虚拟相机、手机当镜头、外接采集卡 | 虚拟相机报什么传输类型未测（本机没装）；需要 ID-03 装一个 OBS 虚拟相机实测 |
| 帧链完整 | 证据带 cameraID、Hub generation、首末 sequence、帧数；Hub 已拒绝乱序、重复、陈帧（`FaceObservationSource.swift:268-272`） | 拼接旧帧 | 不挡实时伪造 |
| 一次性挑战 | 方向用 `SecRandomCopyBytes`（已有）；挑战只在一次锁屏代次内、只用一次 | 录好的“转左”视频 | 实时换脸可应答 |
| 时钟 | 证据时间以账本收到时的单调时钟为准；帧时钟只用于帧间比较（今天两套时钟混用，§4 #8） | 跨域比较出错 | — |
| 进程完整 | 开 Hardened Runtime、不加 `disable-library-validation`；启动时有 `DYLD_INSERT_LIBRARIES` 或被调试（`P_TRACED`）就不开 identity | 往本进程注库改帧 | 有 root 的攻击者挡不住；写进风险说明 |
| 跨模态 | AirPods 头动核对（§3.4 第 4 条） | 虚拟相机、录像 | 要戴耳机 |
| 呈现攻击 | 边框、反光否决（§3.4 第 2 条） | 举照片、翻拍屏幕（P9：最常见） | 打印高清照片、面具挡不全 |

攻击矩阵（照片、手机屏、录像、换人、虚拟相机）全部 `not_run`；风险说明只写测过的（`docs/face-unlock.md:46`）。

### 3.6 模板、同意、留存

- **存放**：保持数据保护钥匙串、`WhenUnlockedThisDeviceOnly`、不同步、不进备份（已做到，比 quietglass 严）。模板记 `modelVersion`（已有）和录入序号（取代墙钟 `enrolledAt`）。
- **录脸要 Touch ID**：沿用账本，用途 `.enrollDevice`、新目标 `AuthTarget.faceTemplate(modelVersion:digest:)`，摘要是这组模板的字节。Touch ID 确认的就是“要存的这一组”，存的东西变了授权就用不上。没有 Touch ID 的 Mac 不提供录脸。
- **删除不加门**：一点就删，删前一句确认（C7 第六条要“便捷的撤回方式”）。删除同时清掉内存里的模板和未用的证据。
- **换模型**：版本不同的模板自动不参与（已有）；刘海在下次解锁后提示「重新录一次脸」；新版本录好后删旧版本那一条。
- **证据**：只在内存，10 s 过期；日志只记扫描序号和结果标签（已是这样）。
- **同意页**（单独一页，C7 第五、六条要的告知项都在；文案照 copy-guide，符号 + 一行）：

| 符号 | 一行 |
|---|---|
| `lock.shield` | 只存在这台 Mac 上 |
| `photo` | 不存照片 |
| `camera` | 锁屏后亮屏时看几秒 |
| `lock.open` | 认出你也不会替你解锁 |
| `trash` | 随时可以删掉 |

主句「录下你的脸」，按钮「继续」/「先不录」；最后一步按钮「用 Touch ID 保存」。功能名：本轮不解锁，叫“刷脸解锁”违反 copy-guide 规则 6，建议设置行暂叫「锁屏时认出你（实验）」——**待 Aaron 定**，定了进 copy-guide 词汇表。

### 3.7 证据怎样进授权账

```swift
// Core/IdentityEvidence.swift（新）
struct IdentityEvidence: Equatable, Sendable {
    enum CameraClass: Sendable { case builtIn, external }
    enum Cue: Sendable { case turnChallenge, depthParallax, crossModalHead }
    let scanID: UInt64
    let cameraClass: CameraClass
    let modelVersion: String
    let thresholdCalibrated: Bool
    let cues: Set<Cue>
    let frames: ClosedRange<UInt64>      // Hub sequence
}

// AuthorizationLedger 新增（只加不减）
func record(_ evidence: IdentityEvidence) -> EvidenceTicket    // 绑当前 sessionEpoch，10 s 后作废，用一次
func complete(_ request:, signature:, publicKey:, lock:, evidence: EvidenceTicket?) // 先做原有全部检查（签名一个不少），
                                                                                // 再看策略要不要证据；要而没有 → .missingEvidence
static func evidencePolicy(for purpose: AuthPurpose) -> EvidenceRequirement   // 默认全部 .none
```

规则：
1. 没有任何 API 从证据得到授权；`complete` 仍然必须有 Secure Enclave 签名。证据最多把某个用途的门槛从“Touch ID”提到“Touch ID + 认出你”。
2. 锁屏时账本不发授权（`AuthorizationLedger.swift:109`），所以锁屏上的证据本轮只能被“记下”，到解锁后已过期。`requestOSUnlock` 不接证据，不接系统解锁。
3. 所以照现在的守卫（只在真锁着时扫描，`FaceScanGuard.swift:121、135`），证据**本轮没有消费者**：记下、过期，只留日志。真要用，得另加“已解锁核验”模式——守卫的锁态条件按模式反过来（要求真的已解锁、会话代次不变），供两处可选使用：有人在看撤遮挡时要求认出你（只让撤遮挡更难，quietglass 的做法）；“改安全设置要 Touch ID + 认出你”的开关。两处默认关，列为 ID-15。
4. `advanceSessionEpoch` 一并作废所有证据票据。

### 3.8 失败与重试节奏

| 情况 | 计不计次数 | 刘海说什么（主句 / 副句） | 之后 |
|---|---|---|---|
| 画质不够 | 不计（Persona P7） | 「光线太暗」等一条提示 | 6 s 租约到就收；下一次亮屏再看 |
| 认错满 2 s | 计 1 | 「没认出」/「用 Touch ID 或密码」 | 停 `alert.hold` 2.6 s 后收，交回系统 |
| 挑战失败 | 计 1 | 「没认出」/「用 Touch ID 或密码」 | 同上；不说是哪一步错（不帮攻击者调参） |
| 否决线索 | 计 1 | 同上 | 同上；日志记 `deny(bezel)` 之类的标签 |
| 满 3 次 | — | 「这次请用密码」/「已试了 3 次」 | 本次锁屏不再开相机（`docs/face-unlock.md:36`） |
| 相机被挡、被别的 App 占用 | 不计 | 不出现（稿：摄像头被挡就不出现） | — |
| 再试一次 | 计入同一上限 | — | 锁屏上按空格重试（Glance `SpaceKeyMonitor` 已在借鉴表） |

### 3.9 无障碍

- 每一步提示同时发 VoiceOver 播报（照 `NotchAuthentication.swift:272-275` 的 `announcementRequested`）；方向说“向左转头”，指用户自己的左，取景画面镜像显示，箭头画在镜像里的同一侧。
- 不只靠颜色：录脸环的扇区点亮同时加粗，结果同时换符号。
- 减少动态效果：扇区直接点亮、不扫；提示交叉淡化 `reducedNotch`；扫描环不转，改成静止环 + 文字。
- 转头不便的人：不提供“更弱的替代挑战”，系统认证永远是出路；同意页和设置里写清。
- 键盘：Esc 取消；Return 继续；Space 重试。超时只是收起，不惩罚。

### 3.10 文件清单（加 / 改，函数级）

| 文件 | 加 / 改 | 内容 |
|---|---|---|
| `Core/FaceCaptureQuality.swift` | 新 | `struct FaceQualitySample`（宽、人数、yaw/pitch、眼开度、captureQuality、亮度、反光比、框位移）；`enum FaceQualityHint`；`struct FaceQualityGate { mutating func evaluate(_:at:) -> Verdict }`（含 0.6 s 提示回滞） |
| `Core/FaceLivenessCues.swift` | 新 | `bezelDeny`、`glossDeny`（计帧、锁存）、`depthParallax(window:) -> Double?`；纯函数，可单测；文件头写 Glance MIT 版权声明 |
| `Core/HeadMotionCrossCheck.swift` | 新 | `func agree(camera: [(t, yaw)], head: [(t, yaw)]) -> Bool?`（同号 + 峰值时差） |
| `Core/IdentityEvidence.swift` | 新 | §3.7 的类型与策略表 |
| `Core/FaceVerificationFlow.swift` | 新（取代 `FaceScanChallengeFlow`） | §3.2 第二张状态机；持有 `FaceScanGuard`、`OwnerTurnChallenge`、`FaceQualityGate`、否决线索、尝试计数；输出 `Phase` 与 `IdentityEvidence?` |
| `Core/FaceEnrollmentFlow.swift` | 新 | §3.2 第一张状态机；一致性检查（每帧对第一帧，门槛按模型标定；SFace 上是 0.55，我们的特征需 ID-11 定）；产出待保存模板与摘要 |
| `Core/FaceGestureTracker.swift` | 改 | `OwnerTurnChallenge.receive(_:identityMatched:)`；框连续 IoU；`minimumReaction` |
| `Core/FaceScanGuard.swift` | 改 | `FaceScanFrame` 加 `cameraID/generation/sequence`；`Evidence` 带上；均值模板在 `init` 里算一次 |
| `Core/AuthorizationModels.swift`、`Core/AuthorizationLedger.swift` | 改 | `AuthTarget.faceTemplate`；`AuthFailure.missingEvidence`；`record`、证据票据、`advanceSessionEpoch` 一并作废 |
| `App/FaceObservationSource.swift` | 改 | `FaceCameraDescriptor` 加 `transport`；identity 订阅时多跑 `VNDetectFaceCaptureQualityRequest`（与 landmarks 同一 handler）、算脸部亮度与反光、每 3 帧跑一次矩形检测；结果放进 `FaceIdentitySample` |
| `App/FaceScanExperiment.swift` | 改 | 相机准入；挑战不重开相机；录脸走 `FaceEnrollmentFlow` + Touch ID；证据交 `ledger.record` |
| `App/NotchFaceEnrollmentView.swift` | 新（刘海宿主内） | 取景、录脸环、提示行、同意页；全部长在 `NotchCanvasView` 里，不新开窗口 |
| `App/AuthorizationCopy.swift` | 改 | `faceTemplate` 的确认句「保存你的脸」与未确认句「没有确认，没有保存」 |
| `tools/privacy/registry.json` | 改 | §3.12 |
| `tools/probes/FaceFeaturePrintProbe.swift` | 改 | 标定模式：本人/他人相似度分布、captureQuality 与亮度分布、建议阈值 |

### 3.11 测试（只测有行为风险的）

| 测试 | 关键用例 |
|---|---|
| `tests/FaceVerificationFlowTests.swift` | 照片过比对后换另一张“脸”做转头 → 失败；挑战中相机 generation 变 → 中断不计次；第 3 次失败后同一代次不再开始；画质失败不计次；反应 <0.2 s → 失败；否决线索压过已完成的挑战 |
| `tests/FaceEnrollmentFlowTests.swift` | 5 帧里混入不一致向量 → 整轮重来；锁屏中断 → 全部丢弃；未授权 → 不保存 |
| `tests/IdentityEvidenceLedgerTests.swift` | 证据不能单独换授权；锁屏下 `complete` 仍失败；证据过期、换代次、重复使用都拒；策略 `.none` 时有无证据结果一致 |
| `tests/FaceCaptureQualityTests.swift` | 提示回滞；多人优先提示；NaN 与越界输入 |
| `tests/FaceLivenessCuesTests.swift` | 边框、反光 3 帧才触发并锁存；转幅 <12° 不评视差 |
| `tests/HeadMotionCrossCheckTests.swift` | 反号、时差超限、单边无数据 |
| 已有 `FaceScanGuardTests`、`FaceScanChallengeFlowTests`、`AuthorizationLedgerTests` | 更新到新签名；固定向量不变 |

单元测试不冒充真机；攻击矩阵、阈值、耳机符号都要 Aaron 在真机跑（`docs/face-unlock.md:52`）。

### 3.12 隐私登记表要改的行

| id | 改动 |
|---|---|
| `face-identity` | `reads` 补“录入时眼睛睁开程度、录入序号”；`purpose` 写“锁屏后认出是不是你，只留一条证据，不会解锁”（保持）；`activation` 改“默认关；打开后锁屏时屏幕亮起最多看 6 秒，每次锁屏最多 3 次”；`toggle` 加“录脸要用 Touch ID 保存；删除随时可用” |
| `camera-frame` | `activation` 里“每秒只看 2 帧”只对有人在看成立；补“认出你时每秒最多 10 帧、最多 6 秒（转头再加最多 12 秒）”——或者把 identity 降到 2 帧/秒，二选一，**待定**（设计稿也写 2 帧） |
| `face-quality`（新） | 读：脸部画面的清晰度、亮度、反光、有没有屏幕边框；用途：提示怎么拍得清，以及挡住举照片、举手机；去向：只在内存，不存；激活：同 `face-identity` |
| `head-motion-crosscheck`（新） | 读：AirPods 的头部转向；用途：转头时核对镜头和耳机是不是同一个动作；激活：认出你开着且戴着耳机时、只在转头那几秒；不存 |

改完跑 `tools/privacy/check-registry.py`，再生成隐私页。

### 3.13 工作包

| id | 标题 | 一句话 | 验收 | 模型 |
|---|---|---|---|---|
| ID-01 | 证据与账本 | `IdentityEvidence`、票据、`missingEvidence`、策略表 | §3.11 账本用例全过；`rg` 证明没有从证据到 `AuthorizationGrant` 的路径；固定向量不变 | Opus |
| ID-02 | 挑战绑定本人 | 保持帧要认得出 + IoU≥0.6；同一订阅；`presentedAt` 取提示画出时刻；反应下限 | “照片比对 + 换人转头”用例失败；`FaceScanExperiment` 不再在挑战前关相机 | Opus |
| ID-03 | 相机准入 | identity 只接 `bltn`；描述符带传输类型；证据带 `cameraClass` | 本机：外接显示器镜头、iPhone 被拒；装 OBS 虚拟相机实测并记录它的 deviceType/transport | Opus |
| ID-04 | 录脸流程 | `FaceEnrollmentFlow` + Touch ID 保存（目标 = 模板摘要） | 未确认不写钥匙串；一致性失败重来；锁屏/睡眠中断全部丢弃 | Opus |
| ID-05 | 画质门 | `FaceCaptureQuality` + captureQuality/亮度/反光采样 | 纯逻辑测试过；Instruments 下 identity 订阅 Vision 用时增加 ≤3 ms/帧（需实测） | Sonnet |
| ID-06 | 否决与确认线索 | 边框、反光、鼻子视差，Swift 重写 | 线索测试过；MIT 声明在文件头；矩形检测每 3 帧一次 | Sonnet |
| ID-07 | 耳机交叉核对 | `HeadMotionCrossCheck` + 先量符号约定 | 真机记录左/右转时镜头 yaw 与耳机 yaw 的符号；纯测试过 | Opus |
| ID-08 | 次数与节奏 | 每次锁屏 3 次、画质不计、空格重试 | §3.8 表逐行有测试 | Sonnet |
| ID-09 | 刘海录脸界面 | 取景、录脸环、同意页、提示、播报、减少动态效果 | 全在刘海宿主内；VoiceOver 每步有播报；减少动态效果下无旋转与扫动；文案过 copy-guide 自检 | Sonnet |
| ID-10 | 隐私登记 | §3.12 四行 | `check-registry.py` 通过；隐私页重新生成 | Haiku |
| ID-11 | 阈值标定探针 | 本人/他人/画质分布，给出建议阈值 | 探针输出分布与建议值；真机由 Aaron 跑，未跑写 `not_run` | Sonnet |
| ID-12 | 攻击矩阵 | 照片、手机屏、录像、换人、虚拟相机 | 每项有真机结果；风险说明只写测过的 | Opus（设计）+ Aaron（执行） |
| ID-13 | 补光颜色探针 | 暗室测补光圈换色时脸部 ΔRGB/噪声 | 给出 SNR；不达标就关闭此项研究 | Sonnet |
| ID-14 | 钥匙串可用性 | 未签名、ad-hoc、正式签名三种构建下读写模板 | 记录每种的 OSStatus；不可用时界面说「这台 Mac 现在存不了」，不退回文件 | Haiku |
| ID-15 | 已解锁核验模式 | 守卫按模式检查锁态；接有人在看撤遮挡、改安全设置两处（默认关） | 锁屏模式与解锁模式的证据互不通用；两处开关关着时行为与今天一致 | Opus |
| MO-01 | 授权对勾 | §5.3 第 1 条 | 只在授权消费成功后出现；减少动态效果下只淡入 | Sonnet |
| MO-02 | 40% 门 | §5.3 第 2 条 | 120 Hz 屏上内容进场时刻误差 ≤1 帧（探针量） | Sonnet |
| MO-03 | 错开上限 | §5.3 第 3 条 | 第 6 格起与第 5 格同时；单测 | Haiku |
| MO-04 | 倒数数字 | §5.3 第 4 条 | 等宽、原地换字；减少动态效果只交叉淡化 | Sonnet |
| MO-05 | 欢迎窗口高度 | §5.3 第 5 条 | 不再用贝塞尔；中途改高度速度连续 | Sonnet |
| MO-06 | 认出你的动效 | §5.3 第 6–8 条 | 每天那条路径总时长 ≤0.6 s、无回弹 | Sonnet |
| MO-07 | 帧节奏探针 | §5.4 | 输出每个转场的掉帧与最长帧间隔 | Sonnet |

依赖：ID-01 → ID-02/04/07/15；ID-03 先于 ID-12；ID-05/06 先于 ID-11；ID-09 依赖 ID-04、ID-05；MO-06 依赖 ID-09。

## 4. 整改计划（今天的代码）

| 级 | 位置 | 问题 | 为什么要紧 | 改法（包） |
|---|---|---|---|---|
| P0 | `App/FaceScanExperiment.swift:196-210`、`Core/FaceScanChallengeFlow.swift:59-72`、`Core/FaceGestureTracker.swift:225-270` | 比对通过后才开挑战，挑战帧不再核对是不是同一张脸；中间还关掉相机重开 | 照片过比对、真人做转头即可“通过”；重开留出约 0.5 s 预热空档 | 挑战帧要认得出 + 框连续；同一订阅（ID-02） |
| P0 | `App/FaceScanExperiment.swift:148-151`、`App/FaceObservationSource.swift:396-399` | 默认相机是列表第一个，列表含 `.external`、`.continuityCamera` | M1 实测：外接显示器镜头报成 `builtInWideAngleCamera`，iPhone 报 `external`；虚拟相机可能也在列表里——注入入口 | 只接 `bltn`（ID-03） |
| P0 | `App/FaceScanExperiment.swift:5-8、115-140、226-270` | 写一个偏好键就录脸，不要 Touch ID | 任何拿到解锁会话或能写偏好的进程都能换成自己的脸（含照片） | 录脸走 Touch ID，目标绑模板摘要（ID-04） |
| P1 | `App/FaceScanExperiment.swift:243-256` | 录脸只查宽度和单脸；5 帧间不查一致、不查朝向、不做挑战 | 可能录进两个人、侧脸、照片 | 一致性、正脸门、录时挑战（ID-04/05） |
| P1 | `Core/FaceScanGuard.swift:143-145`、`App/VisionFaceEmbedder.swift:27-30` | 只有宽度和朝向门，没有清晰度、亮度、反光门 | 暗光、糊帧、翻拍屏幕都会进比对，未标定阈值下误判更难讲清 | 画质门（ID-05） |
| P1 | `Core/FaceScanGuard.swift`（无计数） | 没有每次锁屏 3 次上限 | 违反 `docs/face-unlock.md:36` | ID-08 |
| P1 | `App/FaceScanExperiment.swift:168-175`、`Core/FaceScanGuard.swift:79-85` | 守卫用自己的帧计数；证据不带 cameraID、generation、sequence | 证据无法绑到哪台相机、哪段帧 | 透传 Hub 的三项（ID-01/03） |
| P1 | `App/FaceObservationSource.swift:545-546` 对 `Core/AuthorizationLedger.swift:55` | 帧用主机时钟（睡眠时不走），账本用 `CLOCK_MONOTONIC_RAW` | 两套时钟不可比；以后谁拿帧时间去比账本期限就会错 | 证据时间以账本收到时刻为准（ID-01） |
| P1 | `tools/privacy/registry.json` `face-identity`、`camera-frame` | 没登记眼睛开度和转头挑战；写“每秒 2 帧”，identity 实际请求 10 帧（`FaceObservationSource.swift:87`） | 硬要求 6：读什么都登记；说明与实际不符 | ID-10 |
| P1 | `App/FaceTemplateKeychainStore.swift:22` | `kSecUseDataProtectionKeychain` 通常要求签名与钥匙串分组权限；当前新构建未签名（`docs/handoff/round2-part10/REVIEW-HANDOFF.md`） | 实验可能一直“keychain unavailable”而没人发现 | ID-14 实测三种构建 |
| P2 | `Core/FaceScanGuard.swift:46-52` | 0.92 是占位值，通用图像特征不是身份特征 | 已标 uncalibrated；对外任何地方都不能叫刷脸解锁 | ID-11 标定；界面名待定（§3.6） |
| P2 | `Core/FaceGestureTracker.swift:93、158`，`Core/WS2HeadMotionFeed.swift:6-8` | 左右符号约定未上真机量 | “向左”可能判成“向右”，挑战全错 | ID-07 先量 |
| P2 | `Core/PresenceLock.swift:17` | `faceEnabled` 默认 `true`，注释说 Aaron 尚未决定；它只是开关，不代表有脸部证据 | 将来打开 `returnEnabled` 时会误以为脸已核过 | 默认 `false`，或改成由 `IdentityEvidence` 可用性推出 |
| P2 | `Core/FaceScanGuard.swift:167-175` | 每帧重算平均模板 | 10 fps × 20 条 × 768 维，白费的 CPU | 在 `init` 算一次（纯赚） |
| P2 | `App/FaceScanExperiment.swift:253` | `enrolledAt` 用墙钟 | 改系统时间能改变“最近一次录入”是谁 | 用递增序号 |
| P2 | `Core/FaceGestureTracker.swift:84-96、120-122` | 多处强制解包，靠 `usable()` 间接保证 | 以后改 `usable` 时容易引入崩溃 | 改成 `guard let` |
| P3 | `docs/design-drafts/从锁屏到窗口.html`（规格表）对 `App/Motion.swift:20-22` | 稿写减少动态效果 0.18 s 交叉淡化、摄像头 2 帧/秒；代码是 0.25 s、identity 10 帧/秒 | 稿与实现不一致 | 记入 `docs/design-grammar.md` 对照账，不顺手改设计系统 |

## 5. 动效指点

### 5.1 原则（各条注明从哪来）

1. **形状先走，内容在 40% 进场，第二层再晚 0.2 s。** 已是我们的规则（`docs/motion-direction.md` §2.3、`App/Motion.swift:44-55`）。X1 的录脸欢迎页也是“符号 → 标题 → 副标题和按钮”三层。罕见时刻（录脸）可以把层间拉到 0.3 s；每天的路径不拉。
2. **同一个东西演变，不换图。** X2：光点收成环，环里画出对勾。我们的认出你：扫描环 → 环收紧 → 对勾从环里画出来；没认出：环淡出，换成文字，不抖。
3. **可打断、带速度。** 叠加弹簧、换目标时位置和速度连续（`docs/design-system.md` §4.6 规则）。Alcove 用了两年修“半路卡住”（1.2.1、1.3.6、1.6.7），说明这条最容易漏。
4. **每天发生的不加戏。** `calm`/`settle` 不回弹；`pop` 只给小元素确认；认出你那条路径总长 ≤0.6 s（稿“天天用的不加戏”）。
5. **到头给过冲，过冲后收得更快。** Alcove 1.6.6、1.7.3。我们对应的是下拉橡皮筋（c = 0.55）和音量两耳；到顶后的收起用 `calm`，不等 `alert.hold`。
6. **错开最多 5 个、每个 40 ms**（`docs/motion-direction.md` §2.3），多的和第 5 个一起进。
7. **数字原地换，等宽字形。** 旧字淡出 0.10、下移 2 pt；新字从上方 2 pt 淡入、`pop` 0.9→1（`docs/motion-direction.md` §2.4 键帽规则推广到数字）。
8. **一次一条提示，提示是动作。** Persona P6、国内 SDK 都是一次一个动作；提示换句有 0.6 s 回滞。
9. **触感只给触控板上的直接操作。** Touch ID 在键盘上、录脸时手不在触控板上，都不加触感（`docs/design-system.md` §4.8）。
10. **闲时不画。** 循环动画（扫描环、录脸环的呼吸）设 `preferredFrameRateRange` 上限 30，看不见就停（Alcove 1.3.4；我们已有 `NowPlayingCard.swift:472` 的写法）。
11. **减少动态效果讲同一个故事。** 环不转、对勾直接出现（淡入）、扇区直接点亮；内容等形状停稳再淡入（`docs/motion-direction.md` §2.6）。

### 5.2 令牌怎么分给身份这条线

| 时刻 | 令牌 | 备注 |
|---|---|---|
| 刘海长成取景框（录脸） | `bloom` | 少见时刻，允许 0.16 回弹 |
| 锁屏上开始看（紧凑 → 两耳出现扫描环） | `settle` | 不回弹；环出现走 `fade` 0.18 |
| 提示换句 | `fade` 0.18 / 0.10 | 原地换，不位移 |
| 转头箭头 | `calm` | 位移 ≤6 pt，指向镜像里同一侧 |
| 扇区点亮 | `calm`，扇区内刻度错开 40 ms、最多 5 档 | Glance 是 80 刻度 8 扇区 |
| 认出你：对勾 | `pop`（0.30 / 0.75），缩放 0.9→1 + 描边 0→1 | 只在证据产生后；证据不进账本也照样只是“认出”，不写“已解锁” |
| 没认出 | `calm` 收环 + 文字 `fade` | 不抖、不变红闪 |
| 收回刘海 | `calm`，内容先淡出 0.10，`exit.gap` 0.04 后收形状 | 已有规则 |
| 减少动态效果 | `reducedNotch` 0.25 / 1.0 | 全部替换 |

### 5.3 改前 → 改后（8 条）

| # | 位置 | 改前 | 改后 |
|---|---|---|---|
| 1 | `App/NotchAuthentication.swift:264-267` `confirm()` | `check.isHidden = false`，对勾瞬间出现 | 对勾图层 `pop`：scale 0.9→1、opacity 0→1（0.18），同时 strokeEnd 0→1；减少动态效果只淡入 `reducedNotch`。仍只在授权验签后调用 |
| 2 | `App/Notch.swift:4777-4781`、`4835` | 40% 门只看宽度；用 60 Hz `Timer` 轮询呈现层 | 门看宽、高两者中较大的进度（下巴这类只变高的转场也能等形状）；改用面板所在屏的 `displayLink`（`ScrollStripRun.swift:237` 已有写法），120 Hz 屏不再晚一帧 |
| 3 | `Core/CarryShelfLayout.swift:87-91` `tileFadeDelay` | 0.09 + 0.04 × index，不设上限（12 格时最后一格 0.53 s 才出） | `index` 夹到 4：0.09 + 0.04 × min(index, 4)，最长 0.25 s |
| 4 | `App/Notch.swift:6728-6735` 倒数大数字 | 每秒整块重画，数字硬切 | 数字放进独立文字图层，按 §5.1 第 7 条原地换字；等宽圆体保留；减少动态效果只交叉淡化 0.18 |
| 5 | `App/Welcome.swift:315-320` | 窗口高度用贝塞尔 (0.2, 0.9, 0.3, 1) 模拟弹簧，打断时不带速度 | 用 `FlickSpring`（`calm` 参数）由显示链接逐帧驱动 `setFrame`，换目标时沿用当前速度；符合“位移不用贝塞尔曲线”（`docs/design-system.md` §4.6） |
| 6 | 新：锁屏上开始看 | 无 | 两耳 `settle` 长出，左耳扫描环 `fade` 0.18 进场；环旋转周期 1.2 s、`preferredFrameRateRange` 上限 30；6 s 租约到就 `calm` 收 |
| 7 | 新：认出你 | 无（只写日志） | 环在 0.15 s 内收紧到 0.85 倍（`calm`），对勾按第 1 条画出；整段 ≤0.6 s；稿要求的“手机”小圆点本轮不画（没有手机因素） |
| 8 | 新：录脸环 | 无 | 80 刻度 / 8 扇区；采到的扇区刻度 `calm` 点亮、错开 40 ms 最多 5 档；完成时整环 `pop` 一次；减少动态效果直接点亮 |

### 5.4 怎么量

| 量什么 | 工具 | 过线 |
|---|---|---|
| 掉帧、最长帧间隔 | Instruments「Animation Hitches」+「Core Animation FPS」，录刘海展开、收起、对勾、倒数各 10 次 | hitch 时间比 <5 ms/s（Apple 的“良好”档，需核对当前 Instruments 文档）；单帧不超过 2 个刷新周期 |
| 40% 门的实际时刻 | MO-07 探针：在内容开始淡入时读呈现层宽高进度，记录与 0.40 的偏差 | 偏差 ≤1 个刷新周期 |
| 打断连续性 | 探针在展开途中每 50 ms 发一次反向目标，读呈现层位置的二阶差分 | 无跳点（位置连续、速度连续） |
| Vision 额外开销 | `FacePipelineCounters.visionTotalMs / visionMaxMs / visionSlow`（`FaceObservationSource.swift:24-27`） | identity 订阅下平均增加 ≤3 ms/帧（需实测定） |
| 空闲能耗 | `docs/performance.md` 第七节的测法 | 不高于 1.0.15（硬要求 7） |
| 减少动态效果 | `Motion.reducedOverrideForProbe`（`App/Motion.swift:10-13`）打开后重录 | 无位移、无旋转、无回弹 |

## 6. 没能核实的

- Persona 的被动/主动活体细节、是否录视频、尝试次数上限、无障碍做法：公开文档没写，只有营销与转述。
- Persona 2026 H1 报告原页 403，数字来自 Biometric Update 转述。
- 阿里、腾讯 SDK 的界面规格（圆框尺寸、每步时长、提示文案）没读到原文；腾讯各渠道活体模式表来自开发者文章。
- “远近活体”只在阿里 `Model` 取值里见到，没读到原理说明。
- 《个人信息保护法》第二十八、二十九条：npc.gov.cn 打不开，按通行文本引用。
- X1、X2 只有一句话加视频；画面描述是我逐帧看的，作者意图（概念稿还是产品）未核实。
- 虚拟相机在 macOS 上报什么 deviceType / transportType：本机没装，未测。
- 数据保护钥匙串在未签名构建下是否可用：未测。
- Mac 网络摄像头能否锁定曝光和白平衡、补光圈能给脸多少照度：未测。
- Instruments hitch 比的“良好”档数值：凭记忆写，用前核对。
