# Companion 接收链路探针

这是**合成身份的真实回环 TCP 测试**，不是原生 iPhone Remote 兼容声明。不会访问钥匙串、保存配对身份、发布 Bonjour、连接手机或发送助手任务。

```sh
bash tools/probes/companion-channel/run.sh --loopback-self-test
```

显式参数才运行。探针绑定 `127.0.0.1` 的随机端口，只接受一个连接；10 秒超时关闭。服务端使用产品目录中的 `WS2CompanionTCPTransport`、`WS2CompanionChannel`、`WS2CompanionCrypto` 和 `WS2OPACK`。独立合成客户端验证服务端签名，再发自己的签名；发送一个加密事件和相同密文的重放。验收条件是恰好投递一次事件、重放后关闭服务端通道。所有密钥仅存内存。

正常结果：

```text
PASS real loopback TCP: signed M1–M4, authenticated OPACK delivery, replay closes connection
```

若工具沙箱禁止本地端口，会返回 `Operation not permitted`；不能改成跳过监听器并记成功。可在允许本机回环的环境执行同一个命令。

不需要端口的格式、握手和失败路径检查：

```sh
bash tests/run-companion-channel-tests.sh
```

构建产物在 `.build/companion-channel/`。没有改动日常 App 的指挥开关。后续实际接收器还需要首次配对工厂与原生本地授权、真实服务 profile、会话请求/响应、触摸与按键的实测映射和 Conductor 后端效果接线；不能把 `_fixture` 合成事件改名就当作这些已实现。
