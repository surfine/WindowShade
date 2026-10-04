# WindowShade 2 · 动态分镜 v2

画面依据：[设计稿](../../docs/design-drafts/README.md)。画界面、刘海形状和动效之前先打开对应的稿。

交付口径：126秒，60fps主时间线7560帧；横版1920×1080、竖版1080×1920。随包的离线动态样片分别960×540与540×960，24fps。真机素材尚未录制，声音尚未授权、试听和混音。

一个共享刘海连接九章。既有功能只使用 `public/footage/` 登记并人工核准的素材。未核准时保留具名占位，不自动找图填空，不画假界面。抽象概念段始终带说明，不使用Face ID图案、模拟密码和CarPlay界面。

|章|全局帧 [起,止)|时间|文案|落实|
|---|---|---|---|---|
|0|0–840|14秒|开盖，认出你|见 shots/ch0.md|
|1|840–1800|16秒|刘海，活了|见 shots/ch1.md|
|2|1800–2880|18秒|看不见的，都在这里|见 shots/ch2.md|
|3|2880–3840|16秒|点一下，所有 App|见 shots/ch3.md|
|4|3840–4440|10秒|任何输入，同一套动作|见 shots/ch4.md|
|5|4440–5880|24秒|画一笔，说一句|见 shots/ch5.md|
|6|5880–6600|12秒|长按，换一种用法|见 shots/ch6.md|
|7|6600–6960|6秒|专注时安静，走开就锁|见 shots/ch7.md|
|8|6960–7560|10秒|WindowShade 2|见 shots/ch8.md|

四种刘海：quiet 195×58 r18；compact480×58 r18；alert545×102 r28；expanded820×260 r40。坐标、尺寸为影片布局值，不当作真实Mac硬件测量。横版中心960，顶108。末帧与下一章首帧同轮廓；内容从同一个中心(960,140)收回。

`src/timeline.json` 记录可读时间线；`src/picture.mjs` 为实际图片渲染的确定性函数；`Film.tsx` 以九个Series.Sequence挂载，并用全局Notch避免多实例断裂。`Footage.tsx`要求manifest、approved、reviewer、sha256、containsSecrets=false和有效时长同时满足才上真实图像。视频按60fps合成时基填写sourceInFrames/sourceFrames，入库前转码并验首尾。

读 `REVIEW.md` 的未完项目。代码中120 bpm只是编辑网格，还没拿真实音乐做节拍检测，不能称音乐卡拍已验收。
