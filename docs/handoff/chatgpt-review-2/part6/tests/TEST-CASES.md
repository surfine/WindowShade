# 第六份测试索引

详细断言在同名 Swift 源码；下列条目直接来自本次输出，不把循环、重复运行或旧回归算作新场景。

## 新纯逻辑：42 场景 / 95 断言

- ARB01 opened page cannot evict review
- ARB02 exact opened lease replacement cancels once
- ARB03 same priority without explicit navigation busy
- ARB04 stale replacement cannot evict newer page
- ARB05 authorization preempts opened page
- ARB06 equal authorization never replaces review
- ARB07 synchronous disable barrier aborts replacement
- ARB08 reentrant acquire in cancellation refused
- ARB09 invalid request does not remove existing page
- ARB10 clock rollback safety invalidation still works
- ARB11 display removal during callback aborts replacement
- ARB12 expired expected handle is not resurrected
- SCP01 cannot begin before local enable and unlock
- SCP02 project switch invalidates queued work
- SCP03 relock and unlock never restores old ticket
- SCP04 path replacement and connection restart rejected
- SCP05 backend session validation and epoch binding
- SCP06 disabled state and explicit clear reject
- DIR01 actual symlink and directory replacement observations
- DIR02 containment uses path boundary not string prefix
- DIR03 non-directory and missing path fail
- SEL01 stable selection survives reorder
- SEL02 disabled rows skipped and no wrap
- SEL03 stale events rejected after snapshot
- SEL04 activation consumed exactly once
- SEL05 selection movement invalidates activation
- SEL06 duplicate snapshot fails closed
- SEL07 disabled selection chooses enabled row and empty is valid
- SEL08 revoke invalidates queued activation
- SEL09 snapshot size and identifier bounds
- NET01 unauthenticated connections globally bounded
- NET02 pair setup requires local window and cannot extend deadline
- NET03 one connection per verified peer
- NET04 deadline rejects promotion and stale generation
- NET05 per-connection and aggregate queue bounds
- NET06 total connection cap includes authenticated sessions
- NET07 clock rollback halts and clears buffers
- NET08 close releases allocation and stale handle fails
- DIAG01 bounded suffix and observed versus retained bytes
- DIAG02 control sequences cannot act as terminal escapes
- DIAG03 invalid UTF8 and clear bounded memory
- DIAG04 large append never retains more than capacity

## 新进程管道：9 场景 / 27 断言

- PROC01 explicit bounded diagnostic tail does not block stdout
- PROC02 default diagnostics stays disabled
- PROC03 direct child exit status is separate from protocol outcome
- PROC05 partial final frame rejected
- PROC06 coalesced trailing frames retain ordering
- PROC07 stop closes transport once and waits for independent exit evidence
- PROC08 diagnostic buffer can be explicitly cleared
- PROC09 invalid diagnostic limit rejected before spawning
- PROC10 late scope change blocks an admitted frame

## 新固定权限编码：5 场景 / 11 断言


## 独立未通过要求

PROC04 继承描述符退出通知探针：本次仍返回 2 / BLOCKED，见 `validation/exit-inheritance-probe.json`。其记录不是第 57 个通过场景，也不是预期拒绝通过的负例。

## 工具检查

readiness 的 18 个 Python unittest 仅检验记录格式、路径、日志哈希、版本与环境匹配。stage 的三个拒绝用例检查不覆盖输出、不接受错误基线和不写进输入目录。与 Swift 功能测试分别统计。

