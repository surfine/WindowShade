# 配乐与音效（D4：两首 96–108 BPM 的已授权曲子，各剪一版）

| 版 | 曲目 | 来源 | 授权 | BPM | 对位 |
| --- | --- | --- | --- | --- | --- |
| A | **Tonight** — Michael Ramir C. | Mixkit，`https://assets.mixkit.co/music/841/841.mp3`；本机副本 `~/.claude/skills/video-shotcraft/assets/audio/bgm/tonight-hiphop.mp3`（md5 `58591e7b1a15714a8c1a0a4a6d7fc87d`，113.5 秒），来源登记在该目录 `ATTRIBUTION.md` | Mixkit Stock Music Free License（免署名，可商用） | 104.99（librosa beat_track + 固定拍距拟合，平均偏差 7.3 ms） | 从曲中 25.218 秒起放；曲中 51.218 秒（第 88 拍）的抬升对上片子 26.0 秒的「解开」 |
| B | **原创**（mgaudio `ambient`，flavor `glass`，纯合成；`product` 需要的钢琴采样在本机安装里缺文件） | 本机生成：`scripts/score.py` | 代码 MIT（mg-styles-15），glass 不用采样；成品归本项目 | 100 | drop 放在 26.0 秒（解开），outro 44.0 秒（字标） |

两版共用同一组音效（全部 mgaudio 合成，无外部素材）：接住、放回、启动台图标、拖放、实时活动、倒数、上锁、两次打勾、解开、点头确认、窗口滑走、拉远、字标。
读唇段（28.8–33.4 秒）配乐低 2 dB，只此一次；46.2 秒起淡出。母带 −14 LUFS、真峰 −2 dBTP（AAC 编码后仍在 −1 dBFS 以内）。

这次没有下载任何新曲子：A 是本机已登记授权的曲库里唯一落在 96–108 BPM 的一首，B 是本机生成。
若要换成别的授权曲（例如 Kevin MacLeod 的 CC BY 曲目），需要 Aaron 同意下载，并在发布简介里署名。
