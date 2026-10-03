# 出片闸门

## 本包可复现

从film目录执行 `node scripts/check-timeline.mjs`，预期退出0，status PASS。它覆盖时间线无洞、静止段、完整SVG的静止段首尾相等、连续刘海几何和重复seek的确定性。并不加载Remotion或真实视频。

`python scripts/render-offline.py --scale .5 --out out/WS2-animatic-landscape.mp4`；竖版加 `--portrait`。需要Python Playwright、Chromium和ffmpeg。输出126秒24fps动态分镜，不能充当Remotion编译证据。

有网络和Node依赖后：`npm ci`、`npm run typecheck`、`npm run render`、`npm run render:portrait`。预期都退出0。当前环境依赖安装遇到DNS不可用，没有实际完成Remotion/TypeScript语义编译；仅完成TS/TSX语法transpile检查。

## 主模型逐项检查

- [ ] 两个主Composition为60fps/7560帧、尺寸1920×1080和1080×1920；草稿24fps不是目标主规格。
- [ ] 按shots/ch0–ch8抽帧；标题清楚、人物和设备不被裁切；竖版占位块不能代替真实素材的可读性检查。
- [ ] 17份素材的文件/散列、授权、源入点、帧率、时长、无秘密检查都完成。任何false保持具名占位，并阻断正式发布。
- [ ] 真机功能使用真机录屏；没有模拟密码填入、Face ID图形或CarPlay界面。身份段勾选不能被解释成已完成系统解锁。
- [ ] 章界前后各8帧检查，只有一个刘海；没有整屏裸切、突然变宽、漏出两份边框。
- [ ] 真素材接入后重跑完整静止段；Hold必须包含解码帧，不仅是相机不动。
- [ ] 字标落定至少1秒。全黑最后2秒是设计尾卡；其他连续黑场需报告。
- [ ] 逐条核音源授权，试听混音，测LUFS/真峰，测真实音乐拍点；目前无音轨不能勾选声音通过。

`qc_gate.py`和`carry_flow.py`没有附在上传包中，此环境也没有运行它们，不编造它们的CLI参数或PASS。主模型在实际工具路径先执行`--help`，再把成片传给其公开入口。carry先喂一条已知不连续的负例；本包刘海几何相等只能证明一个局部条件，不能代替全片像素光流carry结果。

本片没有获得审美总分，也没有以静止比例宣称“高级感”已达标。可公开发布前的硬阻断是缺真实素材、声音未批准、Remotion未编译与真机演示边界未验。
