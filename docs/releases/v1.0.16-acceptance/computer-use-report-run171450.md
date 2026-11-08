# Computer Use 验收报告

运行：20261012T171450-f9445d3d
构建类别：candidate；二进制 SHA256：2d9a6e8b5f678d9741dde8ac8cc6ddd1346552a1a5cb9318018480fffcd52e96
源码与二进制关联：unverified: source snapshot is not a build provenance attestation

| 场景 | 结果 | 原因 | 证据 |
| --- | --- | --- | --- |
| fold-companion | pass | 状态菜单「收起窗口」作用于前台文档（本 run 目标窗口 QA-171450）；伴随窗口 doc-B 与 Finder 在场。m12 实看：目标正文消失、原位只剩标题胶囊条（画面上部 doc-B 标题下方 y≈130 处 QA-171450 条）；journal id=190 stage=folded hide=minimized；list_windows 复核 190 仍在 WindowServer 记录（已知保留编号行为）。； | [m10-menu-open](events/m10-menu-open/png.png) / [m12-menu-fold-settled](events/m12-menu-fold-settled/png.png) |
| restore | pass | 双击卷帘条恢复。m14 实看：窗口完整展开、正文可见、光标在文中。AX 复核 frame 176/115/673/439 与 target.json baseline 逐值相等；list_windows window_id=190 bounds 相同。； | [m13](events/m13/png.png) / [m14-restore-bar-after](events/m14-restore-bar-after/png.png) |
| fold-solo | not_run | 本 run 全程有伴随窗口（doc-B/Finder），单窗口收起在 run 20261012T170536-e2936f5d 完成（fold-double-click→fold-settled→restore 闭环，AX frame 与基线逐值相等），但该 run 已按合同关闭；本 run 未重复该场景。； |  |
| peek-static | not_run | 1.0.16 发布关门内不含 peek 场景（runbook Phase 1 只含收起/恢复/菜单/外观）；未测。； |  |
| peek-live | not_run | 同上：发布关门内不含。； |  |
| peek-cancel | not_run | 同上：发布关门内不含。； |  |
| target-change | not_run | 发布关门内不含。； |  |
| observation-failure | not_run | 本轮实际发生过两次输入被拒（截图时效/参数缺失，均在早前 run，本 run 无）；场景合同要求的构造性验证未执行。； |  |

清理：pass
证据完整性：[]

视觉结论来自具名复核；哈希证明归档一致性，不自动证明画面语义。
所有尝试保留；一次后续成功不能抹掉早先失败。

清理历史：
{'file': 'cleanup-1791798005290234000.json', 'status': 'pass', 'reason': None}
