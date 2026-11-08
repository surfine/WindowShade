# 声音提示表（未接音源）

当前两个MP4均无音轨。没有把未提供的音效写成已经试听或获准使用。

候选A是前作 `promo/scripts/audio.ts` 的120 bpm原创程序配乐，先沿用节拍结构做一条“WindowShade 2 pulse”试混，不能把56秒音频直接循环拼到126秒而不听接缝。候选B是参考记录里的Kevin MacLeod《Inspired》，只作为较安静版本的对照；参考记录说明它此前被嫌过于舒缓，不能作为默认胜出曲。两条都没有在本样片里试听，本次不决定最终BGM。来源边界见原repo的音频脚本及 `reference/sound-design.md` §2。

参考包的`bgm-tech-house.mp3`缺少可逐曲对回的来源，暂不准入；`pop.mp3`来源待考，也不选。不得把“Mixkit”网站名当作单文件授权证明。

|帧|候选文件（shotcraft原路径）|音量|淡入/淡出帧|截断时长帧|
|---|---|---|---|---|
|840|assets/audio/sfx/transition/transition-soft.mp3|0.22|0/12|90|
|1800|assets/audio/sfx/transition/swoosh-quick.mp3|0.18|0/12|90|
|3240|assets/audio/sfx/text/keyboard.mp3|0.16|3/8|36|
|3840|assets/audio/sfx/transition/swoosh-quick.mp3|0.18|0/12|90|
|4500|assets/audio/sfx/text/typewriter-hit-single.mp3|0.12|0/6|18|
|5880|assets/audio/sfx/transition/transition-soft.mp3|0.2|0/12|90|
|6960|assets/audio/sfx/riser/riser-cine.mp3|0.18|8/20|180|
|7140|assets/audio/sfx/impact/impact-deep-whoosh.mp3|0.25|0/30|180|

这些文件只在清单里出现，未包含音频字节。将每条授权、原URL、作者、散列、试听结果登记后，才复制进public/audio并接Soundtrack。表内时间是动作起点；实际峰值与动作钉点要根据音频波形校准，不能把文件起点当响度峰值。正式版同时出有BGM/无BGM两版，单声道与耳机各试听。响度建议-16LUFS、真峰不高于-1.5dBTP，属于本片目标，未实测。
