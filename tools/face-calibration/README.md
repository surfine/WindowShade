# 刷脸门槛标定

把 D11 闸门的 `uncalibrated` 拿掉：用他人脸（FFHQ 128px 缩略图，CC BY-NC-SA 4.0，只在本机标定用、不随产品发布）估出他人分数的尾巴，
再用你自己的本人样本算误拒率。全部数据放 `/Users/aaron/Documents/WindowShade-models/`，不进 git。

1. 他人脸：官方脚本 `download_ffhq.py --thumbs` 下载到 `WindowShade-models/ffhq/thumbnails128x128/`。
2. 嵌入：`tools/face-calibration/run.sh embed`（和 App 同一条检测、对齐、Vision 特征管线）→ `calibration/ffhq-embeddings.{f32,json}`。
3. 本人样本（你来录）：`WindowShade.app/Contents/MacOS/windowshade --face-calibrate-record`，点“开始”，约 60 秒。只存特征数字，写到 `calibration/genuine.json`（0600）。
4. 标定：`tools/face-calibration/run.sh calibrate` → `calibration/calibration-report.{json,md}` 和 `calibration.json`（没有本人样本时是 `calibration.provisional.json`，别导入）。
5. 导入：`windowshade --face-calibration-import calibration/calibration.json`（存进钥匙串；需要签名构建）。
6. 自检（不要图片、不开相机）：`tools/face-calibration/run.sh self-test`；数学部分的单元测试是 `tests/run-face-threshold-calibration-tests.sh`。

诚实的限制：约 7 万个不同的脸，直接只能证明到 3/N ≈ 4.3e-5；2e-5 和 1e-6 是尾部外推。FFHQ（Flickr 肖像、对齐过、128px）和 Mac 相机的画面有域差距。
