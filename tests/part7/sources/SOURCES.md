# 本轮核对的一手来源

核对日期：2026-10-03。下面资料用于解释系统概念和检查风险。项目实际协议输入仍是候选 `docs/handoff/reference/codex-app-server-schema-0.153.0/`。当前网站、固定 schema 和本机观察是不同来源；不能互相替代。本包不附整篇外部资料，不附未经授权的媒体。

## S1
Linux man-pages，wait/waitid：
https://man7.org/linux/man-pages/man2/waitid.2.html
适用：WNOHANG、WNOWAIT、直属子进程等待及回收事实。不能证明 Mac 的运行行为或所有子孙清理。

## S2
Apple 归档系统手册，posix_spawnattr_setpgroup：
https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/posix_spawnattr_setpgroup.3.html
POSIX 同主题：
https://pubs.opengroup.org/onlinepubs/009695199/functions/posix_spawnattr_getpgroup.html
适用：在创建时明确建立进程组。归档文档不是当前 SDK 编译证据。

## S3
OpenAI 官方 App Server 文档：
https://developers.openai.com/codex/app-server/
本次实际转至 https://learn.chatgpt.com/docs/app-server
适用：thread、turn、RPC/通知和账号生命周期概念。正文中的接口采用上传的 0.153.0 schema，实际账号和服务端均未运行。不要从网页较新示例偷换固定字段。

## S4
OpenAI 官方配置参考：
https://developers.openai.com/codex/config-reference/
本次实际转至 https://learn.chatgpt.com/docs/config-file/config-reference
适用：独立 CODEX_HOME、凭据存储选项、工具和配置字段解释。字段被程序写出不证明真实沙盒行为；版本支持必须实测。

## S5
OpenAI 官方配置层级说明：
https://developers.openai.com/codex/config-basic/
本次实际转至 https://learn.chatgpt.com/docs/config-file/config-basic
适用：项目、用户、系统等配置层级及覆盖风险。只做本地配置隔离不能宣传为系统级安全隔离。

## S6
RFC 8259，JSON：
https://www.rfc-editor.org/rfc/rfc8259.html
适用：对象成员重复、编码和互操作问题。本项目主动采取更严格的重复键拒绝，不把自己的工程政策写成 RFC 的一律强制要求。

## 源码事实

本轮补丁由实际 v6 基线比较产生；完整旧哈希在 base-manifest.json，实际路径、符号与新哈希在 code-map.json。源文件定位是本轮快照，实际工作区更晚时必须先比 hash。所有性能、配置、权限和可用性结论都以 VALIDATION.md 的实测层级为准。
