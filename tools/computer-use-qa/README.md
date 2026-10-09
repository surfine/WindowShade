# Computer Use QA 工具

唯一操作手册：[docs/computer-use-qa.md](../../docs/computer-use-qa.md)。先配置独立 Mac VM，再运行：

```sh
python3 tools/computer-use-qa/qa.py prepare --config /absolute/local-config.json --companion
python3 -m unittest discover -s tools/computer-use-qa -p 'tests_*.py'
```

Python 3.9+，标准库；动态夹具另需本机 Swift。配置样例见 `config.example.json`；真实配置、原始截图、日志与载荷留在仓库外。不要提交 SSH 凭据或签名材料。

公开命令：doctor、prepare、capture、verify、report、cleanup；observe 和 act 提供受约束的单步观察/输入。每个命令有 `--help`。配置中的 close_menu / finder_close_menu 可指定来宾语言对应的精确菜单路径，默认英语 File → Close / Close Window。路径不匹配就阻塞，不回退猜坐标。

验收结果接口：review-template.json 的 attempts 保存每次尝试，scenario 使用 evidence.SCENARIOS 中的 ID；status 是 pass/fail/blocked/inconclusive/not_run。每项 checks 必须有判断、原因和本次事件 label。实时场景还需 measurements.counter_before / counter_after。verify 输出 results、evidence_errors、cleanup、cleanup_history、all_passed；缺项不会自动通过。

退出码 2 也用于如实表达未测或证据不足。输入成功后的观察失败同样返回 2 并锁住后续输入；不要忽略它继续操作。工具不替代视觉复核，不批准发布。

cleanup 必须带 `--review`，其中 restore 已经视觉复核通过；故障恢复使用 `capture --recovery-view` 和 `cleanup --restore-basis … --restore-x … --restore-y …`，只恢复、不直接关闭，复核新画面后再清理。该恢复通道不解除 HALTED。
