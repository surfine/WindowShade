# WindowShade 2 · 第二回合第2份

先看 `film/out/WS2-animatic-landscape.mp4` 与 `film/out/WS2-animatic-portrait.mp4`：两条126秒无声动态分镜，分别960×540、540×960，24fps。已做功能的真机素材尚未提供，画面明确保留待录位置，不是正式宣传片。

本包新增共享交互租约实现、Codex固定协议模拟核、远端准入门、蓝牙读期限、S1设置文案/说明气泡补丁、T2一次性计时宿主与原生卡片，以及5个macOS探针源码。22个场景86断言通过；8条输出载荷通过上传Codex schema核验，另检查1条初始化通知；电影时间线186项断言通过。具体命令和范围见VALIDATION.md。

## 使用顺序

1. 看 `VALIDATION.md`、`REMAINING.md`。这份没有把所有剩余App包做完；不把材料已交等同于已接入和真机通过。
2. 主模型审 `contracts/InteractionCoordinator-WORKORDER.md`、S1.diff与各已交包WORKORDER。T2依赖的T1源码在dependencies内原样保留。
3. `bash tests/run-core.sh` 重跑纯核。`python tools/stage.py --repo 原repo绝对路径 --out 全新输出目录` 生成独立暂存目录，不覆盖原仓库。
4. 只在审查分支做宿主接线；读probes/README再跑独立探针。任何私有ABI、身份或配置项不确定时停对应动作，不“先让演示跑起来”。

入口：`film/REVIEW.md`是分镜审查，`film/BRIEF.md`是新简报，`film/shots/ch0.md`至`ch8.md`是章节施工源。`answers.md`处理Mac事实和协议已确认/未确认问题。`CHANGELOG.md`说明与前两份的替换关系。

原上传repo、用户home和真实设备没有被本包修改。没有commit、push、签名或发布。没有附字体、商业音频、人脸模板、私钥或密码。

合并part1时，Contracts.swift与暂存目录中的WS2Contracts.swift是同一份合同，目标中只能保留一份，不能重复加入。
