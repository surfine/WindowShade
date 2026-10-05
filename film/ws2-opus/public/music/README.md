# 配乐

| 项 | 内容 |
| --- | --- |
| 曲目 | Voxel Revolution |
| 作者 | Kevin MacLeod（incompetech.com） |
| 授权 | Creative Commons Attribution 4.0（CC BY 4.0）。发布时需署名：「Voxel Revolution」Kevin MacLeod (incompetech.com)，Licensed under Creative Commons: By Attribution 4.0 License，http://creativecommons.org/licenses/by/4.0/ |
| 下载 | https://incompetech.com/music/royalty-free/mp3-royaltyfree/Voxel%20Revolution.mp3（2.6 MB，129.9 秒） |
| BPM | 122.00（librosa beat_track，tightness 800，再用固定拍距拟合；253 拍平均偏差 3.8 ms、最大 13.5 ms） |
| 第 0 拍 | 曲中 0.056 秒；拍距 0.4918 秒 = 60fps 下 29.51 帧，一小节 118.0 帧 |
| 小节线 | 第 2、6、10……拍（k ≡ 2 mod 4），与 audiomap 的乐句起点（1.045、8.916、16.788 秒……）一致 |

`voxel-revolution.audiomap.json` 是 `~/.claude/skills/music-to-video/scripts/analyze-beatgrid.py` 的输出（能量段、乐句、关键时刻）。
它自带的拍点有约 90 ms 抖动，所以拍子用上面的固定拍距；能量段与乐句照它。

## 段落（曲中秒 → 拍号）

| 曲中 | 拍 | 是什么 |
| --- | --- | --- |
| 1.04 | 2 | 第一个小节线，开头就是满的 |
| 14.8 | 30 | 进入铺垫 |
| 46.3 | 94 | 第二段铺垫 |
| 62.0 | 126 | 第一次推高（能量 ×1.39） |
| 77.8 | 158 | 全曲最大的一次推高（×1.43） |
| 85.6 | 174 | 落下去之前最后一个重拍 |
| 87.6 | 178 | 能量落下（analyzer 的 hard stop 87 秒） |
| 102–103 | — | 一秒静音，之后再起 |
| 126–130 | — | 尾音静音 |

## 拍点公式

曲中第 k 拍 = 0.056 + k × 60/122 秒。WS2Opus B 站版（第二稿，53.6 秒）的对位写在 `src/music.ts`（成片第 0 帧 = 曲中第 70 拍，34.48 秒）。

## 片子实际放的一轨：`ws2-opus-mix.flac`

由 `scripts/score.py` 生成（事件表来自 `scripts/score-events.ts`，即 `src/cut.ts` 的常数），不要手改：

```sh
npx esbuild scripts/score-events.ts --bundle --platform=node --log-level=warning | node > /tmp/score-events.json
~/.venvs/onetake/bin/python scripts/score.py /tmp/score-events.json
```

- 配乐：上面那首，从曲中 34.48 秒起放；从头到尾不断：`UNDER` 两段（读口型 28.5–32.5 秒、锁上到面容 ID 打勾 39.8–43.3 秒）低 4 dB、滤到 1.2 kHz 以下；
  片尾 51.6 秒起一路淡到最后一帧。不做真静音（Aaron 听成「声音时断时续」）。
- 音效：15 声（全片 108 拍），一个房间（合成混响 T60 0.9 秒）、四种材质（气流、玻璃、木头、低音），自己合成，无外部素材。
  每一声下配乐让开约 5 dB。
- 母带：−16 LUFS 整合响度，真峰值 −4 dBTP（loudnorm 两遍）。改了剪辑就重跑上面两行。
