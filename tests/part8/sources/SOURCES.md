# 来源与适用范围（核对日期 2026-10-03）

本包的源码事实来自用户上传的 v7 ZIP 和本轮 candidate 差异；这不是公开 GitHub HEAD。实际文件 SHA256 与符号见 code-map。外部资料只支持明确列出的 API/设计背景，不保证本项目兼容、编译或安全。

## S01 · W3C Pointer Cancellation
https://www.w3.org/WAI/WCAG22/Understanding/pointer-cancellation.html
通过网页工具读到正文。可取消的释放阶段完成是参考原则；该说明面向网页指针内容，本包手柄规则属于类比设计，不能据此声称 WCAG 合规。没有复制全文。

## S02 · Apple WWDC20 Advancements in Game Controllers
https://developer.apple.com/videos/play/wwdc2020/10614/
通过官方网页读到 transcript。使用统一框架及实际存在的 profile，额外按钮不能成为所有设备的必需条件。其年份为2020，不能拿其中当年的设备名单充当2026支持列表或本次实测。没有按视频复制代码。

## S03 · Apple WWDC19 Supporting New Game Controllers
https://developer.apple.com/videos/play/wwdc2019/616/
读到官方 transcript。用于提醒语义按钮、物理符号及可选按键的区别，不把某一种设备的印字写成全平台事实。

## S04 · Apple GameController API 导航
https://developer.apple.com/documentation/gamecontroller/gccontroller/shouldmonitorbackgroundevents
https://developer.apple.com/documentation/gamecontroller/gcdevice/handlerqueue
https://developer.apple.com/documentation/gamecontroller/gcextendedgamepad/valuechangedhandler
本轮后台事件属性有官方搜索摘要，handler 文档页主要返回 JavaScript 外壳；没有将它们记为完整 SDK 正文已读取。相关候选方法存在于既有源码，最终签名必须由目标 Mac SDK 编译核验。本次具体安装/释放顺序属于自身源码设计。

## S05 · Apple NSTableView.scrollRowToVisible
https://developer.apple.com/documentation/appkit/nstableview/scrollrowtovisible(_:)
官方搜索摘要用于确认该入口的用途；真实滚动/焦点效果没有运行，不作已验证的可访问性承诺。

## S06 · Apple AXUIElementCopyAttributeValue
https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue
本轮网页为脚本外壳，附为执行者的官方 API 入口。未宣称读到当前 SDK 的完整返回契约。具体 CF/NSNumber/AX 类型与错误必须由 Mac 编译和实机验证；本包纯核测试不覆盖它们。

## 获取限制
容器直接抓取部分官方页面出现 DNS 失败，原始结果在 primary-fetch.json。Web 已读正文与容器可下载是两种不同事实。Mac 工作区连接本轮实际失败，validation/access-boundary.json 只保存去除端点凭据后的说明。没有下载新 SDK，没有运行真实设备、CLI账号或模型请求。
