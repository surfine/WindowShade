# 本次新用例与证据边界

测试 ID 原样来自实际执行记录。旧回归、原缺陷复现和源文本检查不混入本表。

## regression

|场景|断言|结果|
|---|---:|---|
|FENCE01-current|1|PASS|
|FENCE02-replaced-transaction|1|PASS|
|FENCE03-reused-pid-or-window|2|PASS|
|FENCE04-strategy-changed|1|PASS|
|FENCE05-lock-unlock-epoch|2|PASS|
|FENCE06-boot-and-display|2|PASS|
|FENCE07-expiry-boundary|3|PASS|
|FENCE08-clock-regression|2|PASS|
|FENCE09-nonfinite|12|PASS|
|FENCE10-invalid-budget|2|PASS|
|BOOL01-explicit-true-false|2|PASS|
|BOOL02-absence-not-false|1|PASS|
|BOOL03-numbers-not-booleans|3|PASS|
|BOOL04-strings-not-booleans|2|PASS|
|VERIFY01-hidden|3|PASS|
|VERIFY02-unknown-then-hidden|3|PASS|
|VERIFY03-stays-unknown|3|PASS|
|VERIFY04-visible-then-unknown|3|PASS|
|VERIFY05-visible-retry-succeeds|3|PASS|
|VERIFY06-visible-retry-unknown|3|PASS|
|VERIFY07-visible-retry-visible|3|PASS|
|VERIFY08-no-cross-strategy-write|3|PASS|
|VERIFY-cancel-at-0.0|2|PASS|
|VERIFY-cancel-at-0.2|2|PASS|
|VERIFY-cancel-at-0.7|2|PASS|
|VERIFY12-revoke-inside-observe|1|PASS|
|VERIFY13-revoke-inside-write|1|PASS|
|VERIFY14-revoke-inside-final-read|1|PASS|
|VERIFY15-no-fast-screen-shortcut|2|PASS|
|WAIT01-replacement-keeps-new-waiter|4|PASS|
|WAIT02-first-settlement-wins|2|PASS|
|WAIT03-unbound-token-not-acknowledged|2|PASS|
|WAIT04-rebind-refused|2|PASS|
|WAIT05-whole-batch-drained-before-callback|1|PASS|
|WAIT06-reentrant-register-preserved|2|PASS|
|WAIT07-duplicates-and-wrong-window|2|PASS|
|WAIT08-deleted-before-bind|1|PASS|
|WAIT09-many-generations|2|PASS|
|WAIT10-context-changes-before-delivery|1|PASS|
|WAIT11-lock-cycle-before-delivery|1|PASS|
|WAIT12-cross-cancel-after-batch-drained|1|PASS|
|WAIT13-delivery-deadline|1|PASS|

## frame

|场景|断言|结果|
|---|---:|---|
|FRAME01-main-actor-nonsendable-value|1|PASS|
|FRAME02-independent-actor|1|PASS|
|FRAME03-unisolated-caller|1|PASS|
|FRAME04-replaced-inside-getter|1|PASS|
|FRAME05-deadline-inside-getter|1|PASS|
|FRAME06-revoked-during-pause|1|PASS|
|FRAME07-timeout-zero|1|PASS|
|FRAME07-timeout-negative|1|PASS|
|FRAME07-timeout-nan|1|PASS|
|FRAME07-timeout-infinite|1|PASS|
|FRAME08-nonfinite-clock|1|PASS|
|FRAME09-clock-goes-backward|1|PASS|
|FRAME10-deadline-overflow|1|PASS|
|FRAME11-deadline-does-not-advance|1|PASS|
|FRAME12-task-cancelled|1|PASS|
