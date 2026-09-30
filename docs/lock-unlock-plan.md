# 锁屏翻盖、注视与多因素解锁

2026-09-30。Glance 源码基线 `b97f521397ec1197ba17768ba797cae1e628848d`；WindowShade
`27880b5`，工作树 `.claude/worktrees/windowshade-marvin-discussion-15d18f`。
Aaron 要求先求有再求好，优先原生框架与官方 API，允许私有 API；Apple Watch 和 iPhone 都在手边。
本轮交付研究、独立认证/配件探针和活体时序小样，尚未交付完整解锁功能。保持不发布的既有边界。
后续新增的键鼠节奏、数天学习与防误伤，见 [行为论文与实现记录](behavior-risk-research.md)。
声纹、健康、外观、离位与恢复边界见 [使用者边界](authentication-boundaries.md)；
Pixel Class 3、Apple 2026 研究与三星防窥的核对见 [厂商研究](vendor-biometric-research.md)。
Mac mini / Studio、Studio Display 与盒盖外屏要求见 [多屏认证](multidisplay-authentication.md)。

## Glance 带来的改变

| 可以借鉴 | WindowShade 的改变 |
| --- | --- |
| [NotchSkyLight](https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/glance/NotchOverlay/NotchSkyLight.swift) 私有空间配方 | 给真锁屏上的安全翻盖层提供技术入口；仍需核定 ABI 和生命周期 |
| CameraManager / FaceDetector / FaceRecognitionPipeline | 用 AVFoundation、Vision、Core ML 做短时本地面部检查 |
| FaceEnrollmentStore / SecureFaceStore | 同一用户录入不同外观并加密模板 |
| Liveness / FaceLab | 活体线索和调试指标，可重放测试，但授权规则要重做 |
| 紧凑刘海反馈 | 沿用 WindowShade 的刘海形状与光学，把扫描、确认与翻盖接起来 |

[Glance README](https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/README.md)
承认不能可靠抵御录像；实际解锁是识别后输入已保存的系统密码。会话密钥授权后留在应用内存，
不是每次人脸匹配都由系统 Secure Enclave 完成生物认证。
[Apple Face ID](https://support.apple.com/en-ca/guide/security/sec067eb0c9e/web)
包含 TrueDepth、红外深度、注意力、防伪与受保护传感器链路。
普通摄像头加注视和动作可以改善风险与体验，不能据此宣称达到 Face ID 的安全等级。

复制模型前还要核对权重：Glance `tools/convert_arcface.py` 取 InsightFace `buffalo_s/w600k_mbf`。
[InsightFace](https://github.com/deepinsight/insightface#license) 区分 MIT 代码与非商业研究权重，
不能拿 Glance 的 MIT 标签覆盖模型授权；发布前取得适用授权或换用用途明确的模型。

## 源码中的改造点

1. [LivenessCues](https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/glance/Liveness/LivenessCues.swift)
   的 Light 模式三帧无否定线索便通过；Heavy 只需某个确认线索。未发现伪造不是充分活体证据。
2. [LivenessFeatures](https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/glance/Liveness/LivenessFeatures.swift)
   用眼睛睁开比例和瞳孔点，但瞳孔只辅助鼻子视差计算，没有屏幕注视校准。
3. [FaceUnlockCoordinator](https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/glance/FaceUnlockCoordinator.swift)
   的 `livenessConfirmed` 在无脸/匹配失败时不清空；缺少活体与同一 face track 的绑定。
   这是源码缺口，尚未复现攻击，不能声称已证明可利用。
4. 推理 `await` 回来后，提交认证副作用前需再次检查取消、scan generation、帧新鲜度、身份与锁屏代次。
5. [POCController](https://github.com/jonnyoo/glance/blob/b97f521397ec1197ba17768ba797cae1e628848d/glance/POCController.swift)
   不返回系统解锁结果；上层调用输入密码后直接 `.matched`。识别通过、输入送出、系统真正解锁必须分开。
6. 本项目 `EffectEnvironment.refresh()` 读 Bool 型 `EffectSecurityBoundary.isLocked`；查询缺失被当 false，
   所以 refresh 会丢失 unknown。生产接线前必须保留未知状态，未知不得恢复桌面显示。此项尚未修改。

## 注视与 Persona 式主动活体

注视同时检查睁眼、瞳孔相对眼眶的位置、头部姿态、图像质量与连续时间。
首次短校准覆盖自然坐姿、眼镜、距离和屏幕位置；头朝前不等于眼睛看屏幕。
[Vision 瞳孔点](https://developer.apple.com/documentation/vision/vnfacelandmarks2d/leftpupil)
可缺失且眨眼时不准确；不足判未知，不能自动放行。先用几何小样测误差，再决定是否需专用注视模型。

借鉴 [Persona 主动活体](https://withpersona.com/blog/what-is-facial-liveness-detection) 的短动作思路，
不接 Persona 云端、不上传相机帧。我们的验证必须有自己的证据：

- 用 Security 随机数为每次交易选择动作与次序；记录指令真正呈现的时刻。
- 普通路径只做一个短动作：眨眼、轻点头、向左或向右转头后回正；可疑输入再增加检查。
- 只接受指令出现后的采集帧，用 CMSampleBuffer 采集时间与单调时钟核对顺序、幅度和时长。
  不用处理时间冒充采集时间，不重复累计同一帧。
- 身份、注视与动作绑定同一脸、相机、显示目标/校准与 scan generation；换人、丢脸、切相机、睡眠、取消即撤销。
- 动作完成后恢复注视再提交；必要设备认证条件不能因 AirPods 信号好而减少。
- 眨眼或转头不便的人使用系统认证，保留同样动画。

随机动作提高预录视频成本，不能保证抵御实时合成/转发或被控制的采集进程。
仅四种动作也可能被四段预录片段按指令选择攻击，所以短动作不能单独承担防录像保证。
支持已登记的内置或外接摄像头，包括 Studio Display；每个相机/目标屏幕组合单独校准与评估。
设备 ID/类型不是帧来源的密码学证明；相机变化不能沿用已完成证据。
身份阈值、注视持续时间和动作幅度由实测决定，不复制数字冒充安全保证。
测试分别报错误接受、错误拒绝、攻击通过率、p50/p95 与 CPU；零次攻击成功不是零风险。

## 手表、手机和随身配件

| 来源 | 官方入口 | 角色 |
| --- | --- | --- |
| 系统 Apple Watch Auto Unlock | 系统设置开启，观察会话实际解锁 | 跑通完整系统解锁与动画联动 |
| 当次手表确认 | LocalAuthentication only-companion policy | 认证这次应用请求；真锁屏可用性待测 |
| 配对 iPhone 签名回应 | CoreBluetooth、CryptoKit、Security、iPhone 配套 App | 当次设备持有因素；明确确认模式可加手机 Face ID/密码 |
| 手机 RSSI/连接 | CoreBluetooth | 粗略附近信号，不单独授权 |
| 用户选定的 AirPods | IOBluetooth 已配对/连接状态，可用时 RSSI | 辅助信号，不抢音频连接、不作解锁钥匙 |
| AirTag | 暂无本轮查到的可靠所有者认证接口 | 待研究，不列入首版必需因素 |

[系统 Auto Unlock](https://support.apple.com/en-gb/guide/mac-help/mchl4f800a42/26/mac/26)
自行完成，公开 API 不能给它加“先等 WindowShade 的脸和注视通过”的门禁。
所以系统联动模式不是我们强制的 AND 多因素。

macOS 15+ 用 [only-companion](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithcompanion)，
旧系统用 `.deviceOwnerAuthenticationWithWatch`；两者是同一策略值的新旧名称。
不能用 `WithBiometricsOrCompanion` 冒充“手表必需”。`canEvaluatePolicy` 查能力，
`evaluatePolicy` 认证应用请求，均不是 macOS 会话解锁 API。
[WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity?changes=la) 是 iPhone 与 Watch 通信，
不是 Mac 直接控制手表的通用接口。

手机作为真实因素时，首次面对面确认配对公钥；每次签名包括协议版本、用途、Mac 标识、
锁屏代次和随机 nonce。Mac 以本地单调时钟限时，验证公钥与交易上下文、一次性消费结果。
断连、取消、代次变化即撤销。硬件可用时私钥留在 Secure Enclave；Mac 不接手机密码或 Face ID 模板。
静默设备持有与手机本人明确确认是两种模式。签名证明密钥持有，不单独证明距离，也不保证抗实时中继。
高风险的手机明确确认必须只接受系统生物认证，不能把手机密码回退标成 Face ID；
普通持有模式与允许密码的系统确认模式需要分别命名，不能混淆保证。

Near Lock 式体验需要手机配套 App，不能只按设备名或蓝牙广播识别本人。
首个验证版让手机 App 前台；随后测 Mac 外围端 + iPhone central 已建立 BLE 通道与状态恢复。
[iPhone 外围后台广播](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)
存在 UUID overflow 等限制，不能假设 Mac 能一直扫描到后台 iPhone。

[IOBluetooth.isConnected](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/isconnected%28%29)
只说明 baseband 连接；AirPods 自动切换/入盒会丢信号，不能立即锁屏或放宽认证。
AirTag 广播标识会轮换（[Apple 说明](https://support.apple.com/en-kw/119874)）；
[Find My 开发入口](https://developer.apple.com/find-my/) 是 MFi 配件接入，未提供本轮所需的任意应用
读取本账户 AirTag 并认证所有权能力。私有接口允许研究，但先取得证据再承诺支持。

支持头部跟踪的 AirPods 还能通过
[CMHeadphoneMotionManager](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager)
提供姿态、旋转率与加速度，macOS 14+ 有官方入口。先查能力、取得运动权限再开始；
相机与耳机动作时间一致可作为附加线索。耳机不证明佩戴者身份，不能替代注视或当次设备认证。

## 先求有的两条路径

**第一条：系统手表解锁 + 安全翻盖层 + 解锁后新桌面首帧。** 无需 WindowShade 保存系统密码。
脸和注视可以给界面短反馈，但不声称控制系统 Auto Unlock。

**第二条：严格实验模式。** 同一人的身份 AND 注视 AND 当次随机活体 AND
（当次手表确认 OR 已配对手机签名）。只有用户选两个设备都必需时才用双设备 AND。
系统 Auto Unlock 如仍开启，可以先行解锁，不能对整台 Mac 宣称强制 AND。

严格模式还缺已验证的系统会话解锁通道。先测官方应用认证在真锁屏是否可用。
若最后仍借用 Glance 密码代输，须作为独立实验后端，重做凭据生命周期、一次性授权、提交前
状态/焦点复查、超时与真实解锁确认；当前证据不能证明锁屏检查与 CGEvent 全局输入之间是原子操作。
这不是多加几个阈值能解决的。密码后端不随本轮探针启用。

## 随机指纹、补光与防盗抢

借鉴的是两种不同机制：
[Android Theft Detection Lock](https://support.google.com/pixelphone/answer/15146908?hl=en)
在已解锁时根据运动、Wi-Fi、蓝牙等线索判断抢夺并锁屏；
[Apple Stolen Device Protection](https://support.apple.com/en-my/120340)
对敏感操作增加生物认证和安全延迟。WindowShade 分别设计快速撤销与设置保护，不把它们混成一个识别分数。

### 随机 Touch ID

- 在正常交易中用 Security 随机抽取少量追加认证，选择结果固定在当次交易中；取消、重试不能重新抽签来避开。
  用最大间隔/次数兜底，避免一直没抽到；概率与间隔先经过真实使用标定，不先写生产承诺。
- 连续失败、异常移动、设备持有证明异常、重新录脸/换设备、关闭防护时强制检查，不依赖随机运气。
- 用 [LocalAuthentication 的纯生物认证策略](https://developer.apple.com/documentation/localauthentication/logging-a-user-into-your-app-with-face-id-or-touch-id)
  `.deviceOwnerAuthenticationWithBiometrics`，新建 LAContext、复用时长设 0；失败/取消不改走 Watch OR 密码后记成指纹通过。
  无 Touch ID 时用已配对 iPhone 的当次纯生物确认，或停止本应用快速授权；系统登录入口仍由系统负责。
- 指纹样本留在系统内。本应用只接收结果，不知道用了哪根手指、不能读取模板。
  应用指纹请求不是会话解锁 API，也无法给系统 Auto Unlock 强加抽查。

### 开盖习惯与环境

`LidAngleSource` 已有角度与单调时间，可提取开盖起止角度、速度曲线、停顿和回合盖。
这些特征可提高风险等级，不能凭惯用角度判断本人。只在强认证成功后更新本地基线；
未验证或失败交易不参与学习，防止逐步污染。桌面扩展坞、站立办公、单手开盖也应覆盖。

用 CoreLocation 的粗略位置与 CoreWLAN 的连接/缓存信息判断环境变化；SSID/BSSID
需要位置授权，缺权限、无网、扫描失败标为未知。默认用当前连接与低频缓存，主动扫描只在必要时进行。
SSID/BSSID 可仿冒，位置可能陈旧；“熟悉地点”只影响提示频率，不取消必要因素。
环境摘要在本机保存，不上传附近网络清单；不把网络名称当秘密或身份。

充电、姿态与声音也属于这个层级。它们与位置/Wi-Fi 往往相关，不能把“工位的网 + 充电器 + 音乐”
按三份独立身份保证累加。策略根据证据质量、时间和相关性选是否追加认证，保留可解释的理由。

| 新信号 | 原生读取与可实现范围 | 风险判断限制 |
| --- | --- | --- |
| 接电/拔电 | IOKit Power Sources 状态与变化通知 | 拔电后拿起不直接等于抢夺 |
| 适配器功率 | `IOPSCopyExternalPowerAdapterDetails` 的可选 `Watts` | 报告的适配器功率不等于插座实际功耗、当前充电功率；多口分流/PD 重协商会变化 |
| 适配器电流/家族 | 同一字典可选 `Current`、`FamilyCode` | FamilyCode 不等于品牌；字段缺失为未知，不写 0 |
| 品牌、型号、端口上下左右 | 核定 USB/PD/IORegistry 的机型相关路径后单独接线 | 字符串/描述符不能证明是真品；系统端口号不能无映射就叫左上/右下；仅供风险上下文 |
| 站姿/坐姿 | 复用相机，Vision 人体/脸部姿态与关键点 | 只有脸肩画面时通常不足以判断全身站坐；关键点不足就未知 |
| 背景声音 | AVAudioEngine + SoundAnalysis，短时本地分类 | 麦克风权限与可用性独立；音乐可重放、咖啡馆声场多变，不作身份依据 |

Power Sources 的外部适配器字典返回 nil 可能是没插适配器，也可能是查询错误，
必须保留歧义并结合电源状态，不能当成已拔电。先用公开字段做探针，品牌/物理端口等私有数据
待各机型插拔对照后再映射，不为填满表格推测数值。

[Vision 人体姿态](https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest)
首先用于改善取景与标定：不同坐姿/站姿、屏幕角度和摄像头位置分别处理。
不要因站起来就提高身份误拒，也不要为了识别姿态长期打开相机。
行为基线只从强认证后的合格样本更新，维护多个常用情境而不是单一“标准姿势”。

[SoundAnalysis](https://developer.apple.com/videos/play/wwdc2021/10036/) 可做本地环境声音分类。
该辅助项默认关闭；用户开启并授予麦克风权限后，在必要时短采样，只留音量/频谱或粗类别摘要，
不保存原始录音、不做语音转写，不识别具体歌曲或谈话内容。无权限、耳机切换、音源不明时为未知。
声音与网络变化只追加检查；不会为了等音频分类延迟每次开盖，也不会用熟悉音乐放宽身份阈值。

### 面部补光

[Edge Light](https://support.apple.com/en-us/125934) 确实通过屏幕边缘补光，Apple Silicon + macOS 26.2 起支持。
当前 SDK 的 `AVCaptureDevice.isEdgeLightEnabled/isEdgeLightActive` 与格式支持字段均只读；
查到的是状态查询入口，不能据此承诺可由我们打开，也未验证锁屏可用性。

先用安全翻盖层自己的柔和边缘光：根据面部区域曝光质量缓慢调整宽度与亮度，
避免突然闪白，不改系统亮度、不遮密码区域，超时/取消即淡出。摄像头自动曝光稳定后再计入活体帧，
不能把补光造成的明暗变化算成动作。补光改善画质，不是已验证的防伪信号。
随机光照响应可作为后续实验，须单独测照片/屏幕重放和真实曝光时延后决定是否有收益。

### 已解锁时的防盗抢

项目已有 `AppleSPUAccelerometer`，经 IOKit 读取 Apple Silicon 传感器的未文档化 HID 报告；
这是一条私有硬件协议路径，不保证所有 MacBook 或后续系统可用。macOS SDK 的 `CMMotionManager`
整类标为不可用于 macOS，不能把 iPhone 示例直接搬过来。手机配套 App 可用 Core Motion，
但手机运动不是 Mac 运动；AirPods 运动也是独立来源。

现有加速度源只发布低通、减基线、限幅后的二维倾斜，不能直接拿来判断抢夺。
需要在同一条传感器队列保留短时三轴原始样本、时间与健康状态，去除重力后提取加速度、jerk 和运动持续时间。
优先复用一个传感器订阅，别开启第二个高频读取者；原始报告格式、采样间隔、丢包与唤醒后基线先核定。

| 情况 | 设计动作 |
| --- | --- |
| 正常移动、仅 Wi-Fi 切换或 AirPods 断连 | 不立即锁屏；环境记为变化/未知，后续交易增加验证 |
| 急加速/急转向并伴随持有设备丢失等独立线索 | 进入短时警戒；标定后达到抢夺判据才请求系统锁屏 |
| 已配对手机明确发出当次签名“锁定”指令 | 校验用途、nonce、代次与过期，撤销快速授权并请求系统锁屏 |
| 离线且持有证明持续丢失 | 按单独的离开锁定策略处理；普通断网不等于被偷 |
| 传感器掉线/权限不足 | 报告防盗抢不可用；不伪装成仍在监控 |

锁定触发后立即撤销相机结果、动作证据、设备交易与快速授权，不等翻盖播完。
系统确认锁屏才记成锁定成功；WindowShade 画的遮罩不等于安全锁。
锁屏请求后端需独立核定私有 ABI、结果和超时，本轮未实现自动锁机。
多信号组合、滞回和冷却用于减少公交颠簸、拿起电脑、会议移动的误报；
冷却不得让新的一次强风险默默绕过。性能采样与动画呈现隔离，不能为了监控常驻满速渲染或相机。

重新录脸、换配对密钥、修改可信环境、关闭防护、改变凭据后端，都要求当次强认证。
异常环境下修改敏感配置可增加延迟并在结束时再次确认；旧配置在此期间仍生效，取消不生效。
手机强认证签名可绑定 `biometryCurrentSet`，生物录入变更使旧密钥不可用后必须重新受控配对，不能静默重建。
这保护本应用配置，不能接管系统 Apple Account、FileVault、登录密码或苹果的失窃保护开关。
普通用户进程还能被退出/终止，不能宣称具有系统级不可绕过防盗能力。

## 保持 Mark View 式连续动画

按 Aaron 的描述，合盖、开盖、看见本人、确认、回桌面应像一个连续动作。
复用 `FoldRenderer`、`Duo.metal` 光学与现有 `FoldSpring`，不复制另一套预设。
参考 [Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/) 的即时反馈与可中断运动。
以下是实现标准，尚非已完成表现：

- 合盖早期跟随铰链；锁屏时独立 `LockOverlaySession` 接进度与速度，不接桌面纹理。
  当前 EffectSession 绑定 ScreenCaptureKit，不能直接拿来当锁屏层。
- 新窗口非 key、鼠标穿透，只画程序生成的纸面、边缘与光影；从创建起不接触真实桌面。
- 开盖立刻有反馈，相机和推理并行准备；锁屏扫描只占刘海的短状态，不遮认证入口。
- 识别、蓝牙、认证异步进行，只留最新结果；呈现循环不做同步 IPC 或推理。
- 当前 EffectDisplayClock 限 60 Hz，不能声称已有 120 Hz。新层根据实际刷新率给节拍、按时间算位置，
  先量帧预算，交接时保留速度。认证等候期间不维持全屏高帧率渲染。
- 识别通过只是反馈，系统确认解锁才收尾；解锁后接新鲜桌面首帧，不提前展示旧桌面。
- 睡眠/熄屏立即撤场，不阻止系统睡眠来播完；输入密码、再合盖、取消都能中断。
- 短扫描到期停相机与推理；减少动态效果用短淡入淡出。

分别记录唤醒、相机首帧、动作、设备确认、系统解锁和真实呈现时间。
速度目标需要真机测量，不能用 GPU 完成回调冒充画面呈现或系统认证完成。

## 可运行证据与下一步

已有本机记录：macOS 27.0 / 26A428 / arm64 十个 SkyLight 符号存在，只证明导出。
`tools/lock-probe` 真锁屏实验未跑；前任 29 runner 通过是历史记录，不代表新增能力通过。

本轮新增 [companion-probe](../tools/companion-probe/README.md)，独立编译、ad-hoc 签名、不进主 App：

```sh
bash tools/companion-probe/run.sh --capabilities
bash tools/companion-probe/run.sh --authenticate
```

默认只查能力；后者明确发起应用认证，30 秒超时，无密码与系统解锁动作。
诊断退出 0 不等于手表认证通过。本机 macOS 27.0 返回 companion 不可用（LAError -11），
纯生物认证能力可用、类型 Touch ID；未发起交互认证，真锁屏仍需实际验证。

新增 [配件探针](../tools/accessory-probe/README.md)：官方 IOBluetooth 配对/连接查询已编译运行，
实测 11 台配对、3 台连接、其中 1 台音视频类；未将其冒充 AirPods 身份或人员在场证明。
新增 [活体时序小样](../tools/liveness-lab/README.md)：四种动作、注视回正、交易绑定、一次性证据；
131 条合成检查通过。尚未接摄像头、真实身份与注视模型，不代表真人/录像测试通过。
新增 [电源探针](../tools/power-context-probe/README.md)：官方 Power Sources 接口实测 AC、报告 94 W / 4700 mA；
这些不是插座实时功耗，也未核定品牌和物理端口。新增 [行为小样](../tools/behavior-lab/README.md)，
有原生短时只读入口、摘要模型与影子门槛，尚未接数天学习和产品授权。

推进顺序：保留 unknown → 真锁屏小窗口与撤场 → 安全 Metal 翻盖小样 → 系统手表联动 →
本地注视/随机活体实验室 → 当次手表/手机交易 → 实验解锁后端。
AirPods 辅助信号可独立加入，AirTag 不阻塞首版。Touch ID 抽查与本应用敏感配置保护先接，
原始运动采样与误报标定后再启用自动防盗抢锁定。
验收覆盖换人、取消后迟到结果、过期/重复帧、通知丢失、录像重放、眼镜/光照、设备切换、
手机后台/被杀、手表摘下、睡眠/唤醒、新系统构建；真实锁屏需本人观察并用系统认证解锁。
