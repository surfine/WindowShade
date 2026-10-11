# ID-07 · 镜头与 AirPods 转头符号（真机）

`HeadMotionCrossCheck`（`prototype/Core/HeadMotionCrossCheck.swift`）要求挑战窗口里镜头 yaw 和耳机 yaw 同向、同时；它只能否决，从不放行，没戴耳机就不参与。符号约定还没在真机上量过：`cameraToHeadSign` 是占位的 1，`signMeasured` 是 false。量之前不要把它接进挑战。

## 怎么跑

1. `bash tools/probes/head-motion-crosscheck/run.sh --check` 只编译，不开相机和耳机。
2. 戴上支持头部追踪的 AirPods（Pro、三代、Max），正对相机，画面里只有一张脸。
3. `bash tools/probes/head-motion-crosscheck/run.sh [--rounds 3] [--camera UNIQUE_ID]`。第一次会弹相机和“动作与健身”授权，Aaron 亲自点允许。
4. 按提示做：先看正前方，然后每轮“向你自己的左边转、停一下、回正”，再右边。“左右”都是你自己的左右，不是屏幕的。

## 输出怎么看

每次转头打印一行 JSON：两路的原始峰值和符号（镜头是 Vision yaw 弧度，耳机是 CMAttitude yaw 弧度）、换成 WS2 约定后的耳机符号、耳机减镜头的起转时差（毫秒，“转到一半”的时刻），以及用当前常量跑 `HeadMotionCrossCheck.verdict` 的结论。

最后的汇总直接告诉你三件事是“matches”还是“REVERSED”：

- `FaceGestureTracker` 的向左是不是镜头 yaw 变小；
- `WS2HeadMotionMath` 的耳机 yaw 是不是向左为正；
- `HeadMotionCrossCheck.cameraToHeadSign` 的建议值，以及起转时差的 min / median / max（对照 `maximumOnsetLag` 的 300 ms）。

两次独立运行结论一致才改常量，同一个提交里把 `signMeasured` 改成 true，并在提交说明附上汇总行。没戴耳机时耳机那几列为空，镜头那一半照样能用来核对 `FaceGestureTracker`。

不存图像、不写文件、不记耳机名字或标识；程序结束就停相机和耳机。
