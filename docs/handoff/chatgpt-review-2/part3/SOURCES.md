# 来源与版本边界

资料以上传快照为主。外部页面查阅日期：2026-10-03；页面可能比提供的CLI更新，因此不能代替固定schema。

- 项目：`docs/menu-bar.md`、`docs/blueprint.md`、`docs/copy-guide.md`、`docs/handoff/deepseek-*.md`、`docs/handoff/reference/mac-facts-2026-10-03.md`。本包对相关行号做了只读核对。
- Codex：上传的 `docs/handoff/reference/codex-app-server-schema-0.153.0/`。实际304份JSON；原readme的39不是完整目录计数。resume的字段以其中 `v2/ThreadResumeParams.json` 为准。
- Claude hooks 官方：https://code.claude.com/docs/en/hooks 。用于核对 JSON嵌套、stdin事件和 PermissionRequest 拒绝结果格式。当前文档不是对2.1.283全部事件的实测保证。样机仅使用已列出的六类事件，生产接线仍须原版本fixture验证。
- Apple NSMenuItem：https://developer.apple.com/documentation/appkit/nsmenuitem ，NSMenu：https://developer.apple.com/documentation/appkit/nsmenu 。候选代码仍待Mac SDK编译和Option行为实测。
- Apple CryptoKit：https://developer.apple.com/documentation/cryptokit/chachapoly 及 https://developer.apple.com/documentation/cryptokit/curve25519 。这些仅说明原语API；本包未实现、也未声称完成Companion密码学握手。

新增Swift和Python为本次原创；前两份原样保留以供追溯。用户上传的source、skill、shotcraft许可不因装进交接包而改变。未附商业音频或字体文件。
