# 本次用例索引

这是实际测试输出的目录，不增加场景数。硬件/AX替身边界见VALIDATION。

## input

|用例|断言|本轮结果|
|---|---:|---|
|INPUT01 discovery does not enable or install|2|PASS|
|INPUT02 explicit enable and fresh release|2|PASS|
|INPUT03 held A before enable must become neutral|2|PASS|
|INPUT04 navigation uses stable item|1|PASS|
|INPUT05 previous at beginning is not failure|2|PASS|
|INPUT06 next at end is not failure|2|PASS|
|INPUT07 hold A then navigate does not activate new row|2|PASS|
|INPUT08 mouse change invalidates pending A|1|PASS|
|INPUT09 same-row click invalidates pending A|1|PASS|
|INPUT10 list reorder revokes context|2|PASS|
|INPUT11 page lease change cancels|1|PASS|
|INPUT12 backend epoch change cancels|1|PASS|
|INPUT13 lock revokes without auto reenabling|1|PASS|
|INPUT14 foreground loss revokes|1|PASS|
|INPUT15 sink unavailable or IME guard revokes|1|PASS|
|INPUT16 approvals cannot reuse list device|2|PASS|
|INPUT17 detach invalidates pending target|1|PASS|
|INPUT18 identical label is not attachment identity|2|PASS|
|INPUT19 enabling second device disables first|3|PASS|
|INPUT20 replayed end cannot select twice|1|PASS|
|INPUT21 repeated down does not duplicate|1|PASS|
|INPUT22 unknown controls cannot activate|1|PASS|
|INPUT23 cancel opens no model|1|PASS|
|INPUT24 mismatched release control fails closed|1|PASS|
|INPUT25 stop releases all resources|2|PASS|
|INPUT26 reentrant model action may stop host|1|PASS|
|INPUT27 duplicate ids revoke selection|2|PASS|
|INPUT28 disabled rows skipped|1|PASS|
|INPUT29 absent attachment cannot enable|2|PASS|
|INPUT30 cancelled press cannot activate|1|PASS|
|INPUT31 armed indication tracks captured target|3|PASS|
|INPUT32 reentrant revoke while preparing is safe|1|PASS|
|INPUT33 chosen model invalidation during prepare fails closed|1|PASS|

## fold

|用例|断言|本轮结果|
|---|---:|---|
|FOLD01 admission is not evidence|2|PASS|
|FOLD02 hidden needs physical attempt and bound transaction|2|PASS|
|FOLD03 exactly one ordinary completion|4|PASS|
|FOLD04 wrong transaction cannot complete|2|PASS|
|FOLD05 deadline before hide proves not started|2|PASS|
|FOLD06 deadline after hide remains unknown|2|PASS|
|FOLD07 late success is marked separately|2|PASS|
|FOLD08 early failure means no hiding attempt|2|PASS|
|FOLD09 failure after mutation not called cancelled|2|PASS|
|FOLD10 error cannot turn into notStarted after write|2|PASS|
|FOLD11 visible observation can later confirm hidden|2|PASS|
|FOLD12 repeated unknown is silent|2|PASS|
|FOLD13 window-id reuse cannot consume old ticket|2|PASS|
|FOLD14 duplicate live window refused|2|PASS|
|FOLD15 bounded observer capacity|2|PASS|
|FOLD16 bad time and identifiers refused|5|PASS|
|FOLD17 exact deadline prevents mutation|3|PASS|
|FOLD18 second transaction cannot overwrite binding|3|PASS|
|FOLD19 callback after bounded release is inert|2|PASS|
|FOLD20 forged ticket cannot use matching request UUID|2|PASS|
|FOLD21 backward time cannot start mutation|2|PASS|

## flow

|用例|断言|本轮结果|
|---|---:|---|
|IFLOW01 real pipe catalogue supplies selection rows|7|PASS|
|IFLOW02 device chooses model without sending work|3|PASS|
|IFLOW03 separate local send uses selected model|6|PASS|
|IFLOW04 late release after local capability loss cannot change model|3|PASS|
|IFLOW05 reconnect uses a new backend epoch|5|PASS|
|IFLOW06 project replacement rejected by actual model selector|3|PASS|
