# WindowShade 2 · 第二回合第五份

入口为 [交给执行模型](00-交给执行模型.md)。本份集中处理首次配对、Keychain/网络、owned 助手进程、设备动作宿主、番茄钟窗口事务。`overlay/` 是要合入第四份候选的源码；`optional-srp/` 是隔离的外部依赖候选，不自动接入 App。`docs/` 解释为什么这样实现；`workorders/` 指定改哪里、按什么顺序、怎么验收；`reference/` 提供人工测试向量与纯 Python 参考，不用于真实身份。

运行入口：
```sh
bash tests/run-core.sh /第四份/candidate-repo
bash tests/run-process.sh
python3 tests/crypto-reference.py
# 暂存第五份后：
bash tests/check-foundation.sh /第五份/candidate-repo
bash tests/run-regressions.sh /第五份/candidate-repo /统一交接包
python3 tools/stage.py --base /第四份/candidate-repo --out /全新目录/candidate-repo
# 以下只在 Mac 上执行；Linux 会明确返回 78：
bash tests/run-mac-crypto.sh /第四份/candidate-repo
# 隔离准备，不访问网络、不改原工程：
python3 tools/prepare-srp-probe.py --out /全新目录/srp-probe
```

Swift 工具链按原工程 Swift 6 严格并发要求；Python 加密参考使用 cryptography，实际版本在 validation/environment.json。不要把网络依赖安装、代签名、钥匙串重置或版本发布塞入上述测试命令。完整本轮结果见 VALIDATION.md。

本份不是可以直接发布的整应用。特别是实际 Runtime 工厂/项目范围、OPACK/Bonjour/session 服务、重新配对与墓碑清理 UI、HID/鼠标桥、最终窗口效果端口仍有明确源码工作；Mac API 文件尚未通过 SDK 编译。已给出可执行的中间层，不用无效回调伪装这些调用者已存在。
