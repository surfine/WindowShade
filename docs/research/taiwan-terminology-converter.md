# 台湾用语转换器：taiwan.md 的做法与我们的借鉴（2026-10-14 调查）

调查对象：<https://taiwan.md/terminology/converter/>（台湾用语转换器）与它的开源仓库
`frank890417/taiwan-md`。目的是看别人怎么把「大陆用语」稳定地换成台湾说法，
把可借鉴的做法落进我们自己的繁体流水线（`tools/localize/zh-hant.py` 等）。

## 1. 他们是什么

- 站点自称「把中國用語轉換為台灣用語：字形、詞彙、語感的完整對應」，页面上写「3451 條轉換規則」。
- 仓库是**一个词条一个 YAML**：`data/terminology/<台灣用語>.yaml`（约 2,334 个文件），
  另有生成物 `.china-terms.detection.tsv`（首行写着 `DO NOT EDIT MANUALLY`，
  由 `scripts/core/extract-china-terms.py` 从 YAML 的 detection 块生成）。
- 许可：内容 CC BY-SA 4.0（页脚），仓库公开（GitHub `frank890417/taiwan-md`）。
  **这一条对我们最重要**：数据不能整表抄进 MIT 的 WindowShade，只能借鉴方法、
  把他们的清单当核对用的清单（见 §5）。

## 2. 他们的数据长什么样（词条 schema）

`data/terminology/_template.yaml` 的字段（节选）：

```yaml
id: ''                 # 英文 slug
category: ''           # daily / education / tech / media / business / transport / culture / names / internet
fork_type: ''          # A / B / C / D / E / F / semantic / orthographic
auto_convert:          # 選填，預設 true。見 §4
display: { taiwan, china, hongkong?, southeast_asia? }
english: ''
etymology: { origin, taiwan_path, china_path, fork_point, fork_cause }
usage: { taiwan_formal, taiwan_casual, exceptions }
status: ''             # stable / shifting / emerging
detection:             # 選填；「無 detection 區塊 = 不偵測」（保守 opt-in）
  severity: A          # A=紅燈（必換，計分）；B=黃燈（提示不計分，作者自判）
  false_positives: [ { pattern, note } ]
sources: [ ... ]
added/updated: ...
```

分歧类型（他们在 README 里给出的完整定义）：

| 代码 | 类型 | 例子 |
| --- | --- | --- |
| A | 日語遺產 | 便當 / 盒飯 |
| B | 1949 分流 | 計程車 / 出租車 |
| C | 網路時代新生 | 影片 / 視頻、網紅 / 博主 |
| D | 台客語底層 | 阿莎力 |
| E | 正在分歧中 | 人設、躺平 |
| F | 同詞不同語感 | 領導、水平 |
| semantic / orthographic | 語義差異 / 字形差異 | — |

分类目录（`category`）：daily / education / tech / media / business / transport / culture /
names / internet。词条来源也逐条记了「来源 / 词对数 / 强项 / URL」：藍光濾波研究所（約 1,089 對，
IT）、ThunderKO C2T（約 500 對）、1997《大陸用語檢索手冊》（約 250 對）等。

## 3. 转换算法（`src/pages/terminology/converter.astro`，构建期）

1. **字形与词汇分开做**：字形走 OpenCC-js，而且**故意用 `cn → tw` 而不是 `cn → twp`**。
   文件里写明理由：`twp` 会把「视频」直接整词换成「影片」，那就没得做词级对照与标注了。
   他们要让「字形归字形、词汇归词汇」，两个信号别互相吃掉。
2. **一条词条生成一条规则**，source 是 china 列、target 是 taiwan 列；
   并且**同时生成繁体 source 与简体 source 两条**（`id` 加 `_simp` 后缀），
   这样无论输入是简是繁都能命中，也不依赖前端 OpenCC 是否加载完成。
3. **替换前按 source 长度降序排序**（注释原文：*longer matches first to avoid partial
   replacement*）——我们这边同样按 key 长度降序，一致。
4. **卫生过滤**（他们踩过坑之后加的）：
   - 值里的括注 `（簡）（中國）` 一类要清掉，否则会连注释一起塞进用户文本；
     目标值也要清（他们有一条真实事故：`網紅.yaml` 的 taiwan 写成
     「網紅（已通用；早期說「部落客」「網路名人」）」，用户文本被替换后带出一串说明）。
   - 斜线并陈保留（「存檔 / 儲存」是建议选项，不是注解）。
   - 目标值是「無對應」这类说明句时**不生成规则**（否则「偷感」会被换成「無公認對應」五个字）。
   - 每条 source 用 `seenSources` 去重；逆方向还要跳过
     「某条 taiwan 与另一条 china 撞车」的 YAML 字段写反条目。
5. **反向（TW→CN）另建一套**，source/target 对调，并且**不带 note**——
   注释是限定 CN 词的适用范围（「僅動詞用法屬中國網路用語」），反向读会变成胡话。

## 4. 他们最值得借鉴的一点：`auto_convert: false`

模板里的原文：

> `auto_convert`（選填，預設 true）：這對詞能不能給轉換器做找字取代。
> 設 false 的時機：中國側那個詞在台灣另有正當用法，盲目取代會改壞正確文字
> （挺胸→蠻胸、力挺→力蠻、網路流量→網路點閱率、值得肯定→值得一定）。

也就是说：**「这个说法该不该换成台湾用词」和「能不能对全文做字符串替换」是两件事**。
词条照常收录、照常解释语感，转换器只是跳过它。配套的还有 `false_positives`
（列出「含 china 字串但其实是台湾合法写法」的 pattern，例如「算法」在台湾也是合法词，
只在「演算法 / 算法」这对里才是提示项）。

再配一个**双档强度**：severity A = 红灯（必换，pre-commit 挡下），B = 黄灯（提示不挡，
作者看上下文）。这条把「一部分词换了更好」和「不换就错」区分开，避免一刀切。

## 5. 我们怎么用（已落地 / 待办）

**已落地（本批）**：

- `tools/localize/zh-hant.py` 的词表**加了元数据**：每条记 `kind`（apple / product / occc-fix）、
  理由，并引入 **`SKIP: …` 标记**——命中「盲替换会改坏」的词就不做全局字符串替换
  （对应他们的 `auto_convert: false`）。配套加了 `FALSE_POSITIVES` 表，
  记录「出现在台湾其实是合法写法」的情形。
- 长度降序、简繁双源、去重这几条我们本来就一致；现在在脚本注释里写明出处与理由。

**待办（下一步）**：

- 逐条过一遍我们的词表，把「挺胸 / 力挺 / 值得肯定」这类**同形异义**的词按 `SKIP` 标出来
  （我们的文案是自家写的，风险低于他们面对的开放文本，但 `屏 → 螢幕` 这种单字全局替换
  风险最高：`屏蔽`、`屏東`、`屏風` 都不该动）。
- 借鉴他们的 `false_positives` 思路，给我们的正则式替换加保护 pattern 与一个自检：
  转换前后跑 `--audit`，把「疑似被误换」的片段列出来人工过。
- **不抄数据**：他们的词表是 CC BY-SA 4.0，整表搬进 MIT 仓库会有 share-alike 牵连。
  正确用法是把它当**核对清单**：拿他们的词条对我们的目录跑一遍，看我们有哪个词漏转或转错，
  然后按我们自己的话写进 `TAIWAN_TERMS`，并在 copy-guide 的台湾用词一节里注明「对照
  taiwan.md（CC BY-SA 4.0）核对过用词，未复制其数据」。
- 他们那条 Unicode 教训值得抄进纪律：**别用 CJK 兼容表意字**（他们踩到 U+F906 的「句」，
  渲染一样但和 U+53E5 不是同一个码位，导致编辑静默失败）。我们的目录是 JSON 存的，
  加一条自检：zh-Hant 值里若出现 U+F900–U+FAFF / U+2F800–U+2FA1F 的兼容字就报错。

## 6. 一句话对照

| 维度 | taiwan.md | 我们（第39/40批） |
| --- | --- | --- |
| 数据组织 | 一词条一 YAML，带分类/词源/来源/状态 | 一张 xcstrings 目录 + 脚本里的词表 |
| 字形 | OpenCC-js `cn→tw`（刻意不用 twp） | OpenCC CLI `s2twp` + 词表覆盖 |
| 词级替换 | 长度降序、简繁双源、去重、卫生过滤 | 同为长度降序；双层（词表 + 整页兜底） |
| 误替换防护 | `auto_convert:false` + `false_positives` + A/B 档 | 本批引入 `SKIP` + `FALSE_POSITIVES`（起步） |
| 强度分级 | A 红灯必换 / B 黄灯提示 | 未分档（全部按「换了更好」处理） |
| 来源与许可 | 三个语料库逐条记来源，CC BY-SA 4.0 | 用词取自 Apple 台湾官方写法，自建 |
| 校验 | 生成物 DO NOT EDIT、pre-commit 检测、Unicode 正規化 | `check-localizable.py` 挡简体字、脚本可复跑 |

## 来源

- 转换器页：<https://taiwan.md/terminology/converter/?dir=cn2tw>
- 词条说明：`data/terminology/README.md`、`data/terminology/_template.yaml`
- 转换器实现：`src/pages/terminology/converter.astro`
- 演进备忘：`docs/semiont/memory/2026-06-13-164000-converter-evolution.md`
- 生成物与来源清单：`data/terminology/.china-terms.detection.tsv`、`data/terminology/_sources/`
