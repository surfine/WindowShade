# Touch ID 与刘海动画

认证已接入已有的刘海面板（`NotchPanel`），不另开普通预览窗口。真正的摄像头缺口没有可绘制像素，控件放在刘海下方展开的黑色区域。指纹提示与认证由系统负责，我们控制外形的展开、结果和收回。不读取指纹、不模拟扫描进度、不使用私有认证界面。

有刘海时按 `NSScreen` 的真实几何展开；没有刘海时，在菜单栏下方留八点空隙，显示完全圆角的独立胶囊。不按机型名字猜测，外接显示器和盒盖模式同样走这套规则。只在发起操作所在的屏幕显示一次。

macOS 12 起，官方 `LocalAuthenticationEmbeddedUI.LAAuthenticationView` 可与同一个 `LAContext` 配对。在 `evaluatePolicy` 之前先把控件挂进刘海并让它可见，系统就用这个控件替代本次请求的标准认证弹窗；只要在请求前挂好官方嵌入视图，就应替代本请求的标准 `authalert`，不出现两套指纹提示。控件只显示图标，周围必须清楚说明为何认证，例如「确认关闭离位保护」，不能只写含糊的「验证身份」。Touch Bar 的系统提示仍由系统管理。

## 正式接入时的交互

1. 用户主动执行需要确认的 WindowShade 操作（菜单项「验证 Touch ID…」），刘海沿现有圆角和弹簧展开一格，显示系统指纹控件、一句具体用途与取消入口。展开不增加等待时间，不读取指纹扫描进度，不持续闪烁。
2. 系统返回成功后立即执行本次获准操作；同一位置显示白色勾约 0.8 秒，轻轻收回。只有本次请求的原生成功回调才算成功，动画不延迟授权和使用。取消、超时（30 秒）、退出／按 Esc、锁屏、睡眠、能力被关闭以及旧请求回调都不显示成功。
3. 认证期间独占这一块岛的内容：原有音乐和其他活动保留在状态里，其他工具先隐藏，暂停横扫、悬停展开和窗口落点。结束后恢复原选中项，不将认证塞进三项实时活动队列。认证进行中不接受第二次请求；撤场会使 `LAContext` 失效，并用事务代次挡住过期回调。

控件挂到可见窗口、应用激活后才调用一次 `evaluatePolicy`，不做全局拦截。动画沿用项目的 AppKit 与 Core Animation 外形、裁切和弹簧，展开约 0.28 秒、小幅回弹。减少动态效果时使用项目已有的短过渡。不加音效、烟花、全屏闪光或需要完成一圈的等待动画。30 秒截止时间也在成功回调中复查，不能因主线程延迟让过期成功越过超时。

当前 Touch ID 不可用时只显示「Touch ID 暂时不可用」，不发起认证。布局保留认证用途与取消按钮；本次请求只使用嵌入式界面，不同时再发标准弹窗。

## 成功是什么意思（2026-10-01 起）

“系统说认证通过”不再算成功。现在一次确认是一笔绑定好的交易（v4 交接的 A1）：

1. 本进程先在账本（`Core/AuthorizationLedger.swift`）里发出一个请求：具体用途（`AuthPurpose`）、具体目标的摘要（`AuthTarget`，没有自由文本）、32 字节随机挑战、30 秒期限、会话代次和本次启动的随机代号。
2. 刘海里挂原生 `LAAuthenticationView`，调用一次 `evaluatePolicy`。
3. 通过后，用**同一个** `LAContext`、并禁止它再弹任何界面，让 Secure Enclave 里一把只认当前这组指纹的密钥（`App/DeviceAuthorizationKey.swift`，访问控制 `privateKeyUsage + biometryCurrentSet`，不含设备密码）给请求的规范字节签名。
4. 账本用公钥验签，再核对期限、代次和锁态（读不到锁态当作锁着），通过才发一张一次性授权；这时才显示对勾。
5. 调用方执行前按**此刻的实际状态**重算目标并消费授权：用途或目标对不上、过期、锁屏、已用过，都不执行，而且这张授权当场作废。锁屏、睡眠、屏幕睡眠、会话切走会让所有未完成的请求和未用的授权失效（`App/AuthorizationService.swift`）。

为什么能这样做：`tools/secure-enclave-probe/run.sh --check` 在本机实测，WindowShade 这种签名方式（开发证书、无 entitlements）下 Secure Enclave 可用；受指纹保护的密钥只保存 Secure Enclave 包裹过的句柄（`~/Library/Application Support/WindowShade/Authorization/`，0600），私钥不离开 Secure Enclave；没经过认证的 context 签名会被拒绝。钥匙串里的永久密钥会得到 -34018，所以不走那条路。真指纹实测（2026-10-01，本机）：`--sign=policy`（先 evaluatePolicy 再用同一 context 签名，App 用的就是这种）、`--sign=acl`（evaluateAccessControl 后签名）、`--sign=direct`（签名本身驱动内嵌控件）三种都签名并验签通过，都没有出现第二个系统认证窗口（按窗口列表检测）。指纹增删后密钥失效：确认是指纹集合真的变了才删掉，提示「Touch ID 指纹有变化，下次确认时会重新设置」，下次确认时重建。

刘海里那一行和系统认证理由只能由用途和目标生成（`App/AuthorizationCopy.swift`），例如「关闭自动检查更新」，所以写在界面上的和实际要放行的是同一件事。

## 能接入哪里

- **关闭「自动检查更新」**（设置 → 权限与启动 → 更新）：第一个受保护的动作。关掉它会让这台 Mac 收不到安全更新，所以要用 Touch ID 确认；开关先保持“开”，消费授权成功才真的关掉；重新打开不需要确认。这台 Mac 没法确认时（没有 Touch ID、刘海关着）直接改，因为没有可以用来确认的东西。局限要说清：同一用户下的其他程序仍能直接改偏好文件；这里挡的是“有人站在没锁的 Mac 前从设置里把它关掉”。
- **菜单项「验证 Touch ID…」**：自检。没有本机授权密钥就建一把，用 Touch ID 签一次、验签通过才显示对勾。它是检查，不是保护。

后续敏感设置、设备登记、遥控器审批与随机指纹确认都走同一入口，各用自己的用途，一种用途的授权不能用在另一种上。它不解锁 macOS，不接管 Apple Pay、钥匙串或其他 App 的认证提示。没有公开的全局 Touch ID 成功通知可供本应用可靠区分所有系统解锁方式；观察到会话恢复，最多做通用的「已解锁」反馈，不能无证据画成 Touch ID 成功。

真实锁屏时的第三方图层与系统会话解锁通道仍按原认证方案单独验证。当前不保存或输入系统密码，不改变系统登录入口，不声称实现了锁屏 Touch ID 灵动岛。

## 历史小样与验收

`tools/touch-id-island` 是早期独立 AppKit 小样，放在普通预览窗口内以免与运行中的 WindowShade 或系统刘海内容重叠。它只作为历史调试手段保留，不是用户要的交付物：正式形态是上面的 `NotchPanel` 内嵌方案，认证发生在真实刘海里，不再依赖这个预览窗口。

```sh
# 默认只查能力并构造／移除系统控件；不发起认证
bash tools/touch-id-island/run.sh --check
# 打开小样，点击按钮后才请求真实 Touch ID
bash tools/touch-id-island/run.sh --ui
```

构建使用现有 WindowShade 的 Apple Development 证书，也可通过 `WINDOWSHADE_CODESIGN_IDENTITY` 指定。

## 检查与待验收

- 有刘海机器：认证内容出现在真实刘海内；无刘海机器（iMac、Studio Display 等）：出现在项目虚拟顶部小岛几何内。两者都不额外弹窗、不出现第二个窗口。
- 在挂好 `LAAuthenticationView` 后再 `evaluatePolicy`：本次请求不出现系统标准 `authalert`，只有刘海内一套指纹提示。
- 成功只在当前请求的原生回调里发生，并执行本次获准操作；取消、Esc、30 秒超时、锁屏、睡眠、能力关闭、旧代次回调都不算成功。
- 认证期间其他刘海工具隐藏、原有活动选择保留，结果收回后恢复原选中项；同一次请求只有一次 `evaluatePolicy`，无全局拦截。

已通过 `bash tests/run-appkit-tests.sh all` 的七组回归，包括直接调用生产 `NotchPanel` 检查真实刘海／虚拟胶囊几何、摄像头留空、认证独占、动画收尾不移除系统控件、Esc 接线及恢复原活动选择。几何测试使用屏幕坐标与原生控件，未调用 `evaluatePolicy`，不能替代所有外接显示器和物理输入验收。

`bash tests/run-notch-authentication-tests.sh` 用 Swift 6 编译实际认证控制器和真实的授权链（账本、密钥封装、服务），只把界面宿主换成薄绑定、把 Secure Enclave 换成软件密钥：验签通过才有授权和对勾（KEY-01）、签名失败即撤回请求（KEY-02）、系统认证失败不碰密钥（KEY-03）、密钥不允许退回设备密码（KEY-04）、签名用的就是原生控件认证过的那个 context 且不会再弹界面（KEY-05），以及重复取消只回调一次、取消后旧成功不生效、旧成功不清除新请求、移除宿主后撤销、过期成功被拒、锁着时不发授权。`bash tests/run-authorization-tests.sh` 覆盖账本本身（TXN-01…08，规范编码有独立算出的固定向量）。两者都不读取指纹。

早期普通预览窗口中曾观察到用户完成系统认证，但这不能算主 App 刘海流程已通过现场验收。主 App 的真指纹成功、失败、取消、是否出现额外弹窗，以及物理键盘／外接 Touch ID 仍需现场检查。

依据：[Apple LAAuthenticationView](https://developer.apple.com/documentation/localauthenticationembeddedui/laauthenticationview)、[纯生物认证策略](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometrics)、[LAContext evaluatePolicy](https://developer.apple.com/documentation/localauthentication/lacontext/evaluatepolicy(_:localizedreason:reply:))，以及本机 SDK 的 `LAAuthenticationView.h`。正式产品与小样的状态区分以实际接线为准。
