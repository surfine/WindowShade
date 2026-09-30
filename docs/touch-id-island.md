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

## 能接入哪里

入口是菜单项「验证 Touch ID…」，当前验证本次 WindowShade 应用请求，不顺带修改保护设置。控制器提供成功／失败回调，后续敏感设置与随机指纹确认可使用同一入口。它不解锁 macOS，不接管 Apple Pay、钥匙串或其他 App 的认证提示。没有公开的全局 Touch ID 成功通知可供本应用可靠区分所有系统解锁方式；观察到会话恢复，最多做通用的「已解锁」反馈，不能无证据画成 Touch ID 成功。

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

`bash tests/run-notch-authentication-tests.sh` 用 Swift 6 编译实际认证控制器，以简化的界面绑定检查重复取消只回调一次、取消后旧成功不生效、旧成功不清除新请求、移除宿主后撤销，以及超时任务尚未运行时也拒绝过期成功。它不读取指纹，不发起生物认证。

早期普通预览窗口中曾观察到用户完成系统认证，但这不能算主 App 刘海流程已通过现场验收。主 App 的真指纹成功、失败、取消、是否出现额外弹窗，以及物理键盘／外接 Touch ID 仍需现场检查。

依据：[Apple LAAuthenticationView](https://developer.apple.com/documentation/localauthenticationembeddedui/laauthenticationview)、[纯生物认证策略](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometrics)、[LAContext evaluatePolicy](https://developer.apple.com/documentation/localauthentication/lacontext/evaluatepolicy(_:localizedreason:reply:))，以及本机 SDK 的 `LAAuthenticationView.h`。正式产品与小样的状态区分以实际接线为准。
