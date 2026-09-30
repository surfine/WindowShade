# 行为影子小样

独立原生实验，不进主 App。不读取文字，不触发锁屏、拒绝登录或解锁。
论文、算法取舍与学习条件见 [研究记录](../../docs/behavior-risk-research.md)。

```sh
bash tools/behavior-lab/run.sh --capabilities
bash tools/behavior-lab/run.sh --observe
bash tests/run-behavior-feature-tests.sh
bash tests/run-behavior-risk-tests.sh
```

默认只查询 Input Monitoring 和安全输入状态。`--observe` 明确启动 30 秒只读监听，
用 CoreGraphics `.listenOnly`，不吞/修改输入；结束后输出计数与四维数值摘要，不保存文件。
安全输入或监听中断时丢弃样本。输入权限不足时退出，不自行索取权限。
短采样未核定本人归属，不能自动进入训练集。

纯模型按情境和键盘/指针模态分开，以独立时间段训练/校准。
它是 median/MAD Manhattan 变体，不是论文性能复现。
默认 `BehaviorShadowGate` 仅记录；三窗连续偏离、成熟验证报告、建议模式和独立风险佐证齐全才建议系统认证。
代码没有锁机或拒绝动作。实验元数据真实性、可靠身份标签、加密持久化和数天学习仍待接线。

本轮验证：本机输入监控能力可用；44 条特征边界检查、25 条风险门槛检查通过。
另完成一次本机 30 秒只读采样：按住 14、击键间隔 12、指针速度/转向各 128 个样本。
键盘不足返回未知，指针输出四维统计；未保存、未训练或触发认证。
合成测试只证明时序和状态转换，不能证明真实识别率或误报率。
