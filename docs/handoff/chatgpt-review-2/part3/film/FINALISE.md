# F3–F5 最终交接

九章分镜、TSX、相机、声音提示表继续使用第二份 `film/`。本份没有新成片，不再把旧静音动态分镜重复计为第三份成果。

## 固定施工顺序

1. 把17份真机素材放入第2份 `film/public/footage/`；逐个填写capture-registry的sha256、reviewer、containsSecrets、license、sourceInFrames、sourceFrames。没有素材的条目保持false，不批量勾选。
2. 沿用第2份 AUDIO-CUES.md 的帧号和音量，逐首记录原文件授权、作者、原URL、SHA256与试听意见。BGM默认先试前作原创程序配乐；另一候选只作对照。未取得音频字节和授权时不出有声正式版。
3. 在有网络的开发工作区进入第2份film目录，执行 `npm ci`、`npm run typecheck`、`npm run render`、`npm run render:portrait`。每条保存命令、退出码、工具版本与stdout/stderr；失败不生成PASS。
4. 以shots/ch0–ch8抽帧表核对横竖两版、章节边界前后8帧、文字落定1秒、单刘海carry和真实素材的静止段。不得拿SVG几何相等当全片像素检测。
5. `qc_gate.py`与`carry_flow.py`并未包含于输入包；实际机器上先定位已安装工具并执行 `--help`，保留help与工具hash，再按真实CLI运行。不可在此捏造参数。无工具时手工逐帧复核并标MANUAL，不写工具PASS。
6. 把实际证据写到第2份film目录的final-evidence.json，字段见下文。最后运行本份 `python3 film/release-gate.py --film /第2份/film --report /验收目录/final-gate.json`。当前缺素材预期退出2、BLOCKED；这是正确拒绝，不是发行通过。

## 证据格式

`{"remotion-typecheck":{"status":"PASS","path":"validation/typecheck.txt","sha256":"实际64位摘要"}}`。其他键固定为landscape-render、portrait-render、audio-rights、audio-listen、loudness、visual-review、carry-review、qc-review。不要复制这个例子伪造成功。即使门禁退出0，也只表示登记证据齐全，仍须主模型复核报告内容；不能用布尔值证明片子好看。

本环境没有真实17项素材、音源授权、最终混音、Mac功能录屏或完成Remotion安装。它们属于实际未完成交付，不是修改一个JSON就能补上的。
