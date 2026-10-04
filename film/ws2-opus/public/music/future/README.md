# 未来版的声音

`ws2-future-mix.wav`（48 kHz / 24 bit，60.0 秒）是配乐 + 音效一次混好的母带，由 `score.py` 生成，`src/future/Future.tsx` 直接放。

## 配乐

- 曲目：**Floating Cities** — Kevin MacLeod（incompetech.com）
- 来源：<https://incompetech.com/music/royalty-free/mp3-royaltyfree/Floating%20Cities.mp3>
- 授权：**Creative Commons: By Attribution 4.0**（<https://creativecommons.org/licenses/by/4.0/>），可商用，须署名。
- 署名文本（发布时放进简介）：

  > "Floating Cities" Kevin MacLeod (incompetech.com)
  > Licensed under Creative Commons: By Attribution 4.0 License
  > http://creativecommons.org/licenses/by/4.0/

- 速度：120.00 BPM（`analyze-beatgrid.py` 读成 117.5，是 23 毫秒帧长量化的误差；onset 自相关在 119.9 / 120 / 120.1 BPM 的得分是 52 / 125 / 51，拍点相位 0.036 秒）。
- 取段：曲子 110.536–170.536 秒（第 55 小节强拍起）。曲子 148.536 秒低音整段进来（每小节 150 Hz 以下能量 7.5 → 11.3），落在片子 38 秒 = 第 2280 帧，刘海展开成 CarPlay。
- 曲子原文件不入库，`score.py` 缺文件时自己下载到 `/tmp/wsmusic/`。

## 音效

- 材质只有一套：**Kenney Interface Sounds**（CC0，`sfx/License-kenney.txt`）的 14 段录音，加 onetake `sfx_palette` 合成的低音（`sub`）、气流（`air`）、按键木头声（`wood`）。
- 一个房间：全部过 `sfx_palette.impulse(0.9)`，按距离 12–55 % 送混响。
- 事件表在 `src/future/sfx.ts`，直接引用画面的常量（`HIT`、`POCKET`、`CP_*`、`LP_*`），`score.py` 用 esbuild 现导，不手抄帧号。
- 25 个事件对 120 拍；同一个动作同一个声音（三次确认都是 `confirmation_002`）。

## 混音与母带

- 音乐是一条不断的床：开头 0.2 秒淡入、片尾 1.5 秒淡出，中间只在落拍前压 −10 dB 0.2 秒（`sfx.ts` 的 `DIPS`）。
  曾把冷开场、读唇、锁后做成静音（共约 10.6 秒），Aaron 听来「时断时续」，已拿掉；`silencedetect -45dB d=0.08` 现在只剩最后 0.16 秒的淡出尾巴。
- 音乐先压到 −20.5 LUFS，每个音效前 30 毫秒开始让 3.7–5.2 dB（上限 6 dB），保持到声音结束（最多 0.35 秒），0.45 秒放回。
- 音效整体按「事件窗口 120 毫秒里比让过之后的音乐响 4 dB（中位数）」定电平。
- 母带：整合响度 **−16.0 LUFS**，真峰值 **−4.1 dBTP**（4 倍过采样，前视 5 毫秒的限幅）；ffmpeg `ebur128` 复核一致。

重做：在 `film/ws2-opus` 下跑 `/tmp/wsaudio/bin/python public/music/future/score.py`（numpy、scipy、soundfile、librosa）。
