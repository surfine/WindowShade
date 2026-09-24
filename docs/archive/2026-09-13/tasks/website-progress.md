> 历史归档：记录的是 2026-09-13 的判断与进度，不代表当前缺陷或执行指令。后续实现以 Git 历史、现行文档和 [1.0.15 发布说明](../../../releases/v1.0.15.md) 为准。

# WindowShade 产品官网

用户要求：借鉴 Bendy 的演示优先思路，像 AI System 6 一样在 Cloudflare Pages 建成并发布有审美、善于包装的产品官网。

方向：原生 Mac 小工具，冷白/石墨、单一蓝色、纸面卷帘意象；中英文静态页面。真实素材和网页交互示意明确区分。主线是窗口原位收起，合盖动效作为第二个记忆点。

已确认：AI System 6 官网 `aisystem6.pages.dev` 使用独立静态 site/ 和 Pages Direct Upload。本机 Wrangler OAuth 具有 Pages 写权限。WindowShade 暂无 Pages 项目。用户已授权建设和发布，不需要另问。

约束：主项目存在大量已有未提交改动，官网放独立 site/，不碰 Swift 和应用 bundle。早期 social 截图带聊天内容，不可直接发布。最新设置截图是隔离预览、尚未发布的新设置外观，页面需如实标注。GitHub 最新发行版已核验为 v1.0.10。

已完成：独立 site/ 中英文静态官网、冷白/石墨主题、卷帘纸面主视觉（内置 image_gen）、可双击与键盘操作的窗口卷帘/置顶示意、手动播放实录、真实设置截图、FAQ、下载、SEO 与 404。桌面和 390px 手机实查，无横向溢出，切换语言和主题、收起/展开/置顶、双击、回车和 FAQ 均通过；录屏播放 currentTime 推进且 readyState=4。

验证：`npm run build`、`npm run check` 通过；本地移动 Lighthouse 性能/无障碍/最佳实践/SEO 均 100，LCP 1.9s，报告 `.build/website-review/lighthouse.json`。减少动态效果通过 CSS 媒体查询关闭动画，录屏本来就不自动播放。没有运行无关的主应用构建。

部署完成：2026-09-13（台北），正式地址 https://windowshade.pages.dev/ ，英文 https://windowshade.pages.dev/en/ ，部署 https://8041d1cf.windowshade.pages.dev 。Wrangler 4.131.1 默认把新项目委派到 Workers，首次普通创建失败；按 CLI 提示仅在首次创建追加 --force，成功创建独立 Pages 项目，后续正常 pages deploy 成功。没有创建额外 Worker。维护说明在 site/README.md，素材提示词 site/hero-prompt.txt，部署文件哈希在 site/deployment.json。

线上验证：首页、英文页和媒体返回 200，真实 Pages CSP 下卷帘交互运行、动态卷轴距离正确。主应用原有改动未触碰；此次站点源码和任务记录尚未提交 Git。

剩余：无必需实现工作。未来可按用户反馈调整文案、素材或域名；正式应用发布新设置后更新截图说明。

## 当前扩展：互动考古（2026-09-13）
用户要求结合 WindowShade 历史，参考 Marcin Wichary《Frame of preference》，做全面而引人入胜的互动考古并纳入现有 Pages 官网。沿用发布授权。方向：独立中英 /history/ 与 /en/history/，首页显著入口；史料旁注、可操作对照实验、按需启动 Infinite Mac 真模拟器，连接当代独立项目（不宣称历史软件直接继承）。
证据：Apple System 7.5 Upgrade Guide 印刷48/PDF53有控制面板；Mac OS 8 HIG collapse box；Mac OS X实际2001-03-24，Exposé随Panther2003-10-24，不能混为1999或2001同次替换；当前Apple Stickies文档仍说明双击收起；早期1989首发暂未获得原公告，版权年份不能代替首发日期。
研究文件 .build/history-research/ 不部署。参考叙事，不转载参考文章图文。旧主应用脏改动保持不动。待完成：史料核验、长文与实验实现、桌面/移动/无障碍检查、部署与公网验证。

## 考古里程碑：已实现并发布
- 原创七章中英长文：`site/scripts/history.mjs`，含 13 条史料与致谢；`/history/`、`/en/history/`，首页入口已接通。
- 四个轻量展品：卷起/最小化/总览对照、2/3次点击与修饰键偏好、Platinum卷起与位置、便笺首行留存。均有键盘替代与reduced-motion支持，明确标成重绘。
- Infinite Mac按需运行System7.5、MacOS8.0、OSX10.1；通过官方API，一次一个iframe，关闭/切换释放，自动离屏暂停；有独立链接、45秒状态提示和自记任务。
- 史料原文核查：1994 Mini’app’les PDF明确Rob Johnston/Interactive Technologies与1989–92版权标记；Apple System7.5手册印刷48/PDF53已渲染目检；1997 MacOS8 HIG103–104页；Apple2000/2001/2003/2011发布文稿；现行Stickies手册。
- CUA验证：桌面1280、手机390，中英文均无整页横向溢出；浅色/深色、三击不被双击触发、Off不触发、最小化恢复、移动后展开、便笺收起、模拟器切换卸载。控件在dark主题下强制历史面板light色系并修复fieldset折行。
- 公网预览System7.5和MacOS8均已启动进入桌面；OSX10.1收到emulator_loaded并显示Happy Mac启动画面，启动较慢，尚未验证到Finder桌面。没有把loaded误标为boot完成。
- localhost嵌入在此WebKit环境空白，公网HTTPS嵌入正常。已通过公网预览核验实际功能；CLI/静态检查通过19资产。
- Lighthouse中文本地100/100/100/100，公网英文预览P/A/BP100，SEO69是Pages预览站强制noindex；正式站独立验证无X-Robots-Tag。
- 原生主应用既有未提交改动均未触碰，没有运行无关Swift构建。研究PDF仅在.build/history-research，不部署。

### 完成交付
- 三台系统最终都已目检到桌面：System7.5、MacOS8.0、OSX10.1（后者启动需数分钟，已显示Finder和Aqua）。前述OSX未进桌面的状态作废。
- 最终将模拟器统一为640×480，CSS等比缩放到容器，避免Dock/菜单被窄画面裁切；公网测得604×453画布装入607×453容器，启动信号正常。
- 正式Lighthouse报告`.build/website-review/history-production-lighthouse.json`：性能98，无障碍100，最佳实践100，SEO100，LCP1.3秒。最后的正文说明、目录入口与模拟器画布修正已再次通过静态检查。
- 最终生产部署 https://c11923dd.windowshade.pages.dev，公开入口 https://windowshade.pages.dev/history/ 和 /en/history/。`site/deployment.json`记录最终资产哈希。已验证正式站无noindex与资源哈希一致。
- 原目标已完成，无剩余必须工作。后续如需继续，可以扩展史料深度或为模拟器制作引导磁盘；这不属于本次尚未完成项。

## 用户纠正：时代外观必须准确，参考 AI System 6 源码
用户指出初版年代外观失真，要求读 AI System 6 代码。已读取该项目 AGENTS/CLAUDE 入口以及 00-foundation、65-appearance-themes、67-aqua-appearance 相关参数和控件规则。关键区别：Classic 像素标题栏；Platinum 19px标题栏、11px独立Zoom与Collapse、双横线卷起图形、Charcoal字体目标；Aqua参考项目以10.2为界且有自定义红左绿右灯位，不可冒充本文10.1。
修正：新增 site/era.css，引用项目已有ChicagoFLF、Asap回退与Classic控件SVG并保留许可文件；恢复黑白条纹、11px关闭/缩放/卷起控件、Aqua左侧三灯与右侧工具栏胶囊；控制面板恢复像素单选框/X勾选、紧凑尺寸；历史字体不被手机规则缩成8–10px；历史条纹容器对齐整像素，避免半像素混成灰色。原项目文件未改。
验证：27项静态资产检查通过；CUA桌面标题栏、控制面板选中状态、Platinum折叠与390px英文布局通过；Lighthouse无障碍和最佳实践100。补充本地服务器SVG/woff2 MIME，否则本地SVG控件为空白（生产Cloudflare MIME正常）。保留文中重绘与替代字体说明，不声称像素级原系统复刻。

- 修正版已发布 https://7f695878.windowshade.pages.dev；正式站中英文历史页、era.css、history.js、两套字体及SVG控件均200且与本地构建SHA-256一致。部署清单已更新。

## 官网内容具体化与置顶补充 — 已发布
用户要求按 WindowShade.md 去除空泛文案，并参考 Top.it 补充置顶。已用真实资料遮挡正文场景重写中英文首页，增加四种窗口管理方式对照、两种卷帘外观、隐藏/恢复机制与限制；保留历史入口。读取本地 Topit README、WindowShade PinnedPreview 交互接管与菜单源码，添加独立置顶章节和置顶/切回正文/取消置顶层级演示，不将 Topit 任意窗口承诺套用于本项目。手机390中英文无溢出，对照表和置顶效果截图验收，层级2/3→4/3→2/3通过；27资产检查通过。最终部署 https://ed24add5.windowshade.pages.dev ，生产双语首页/app.js/style.css哈希吻合。仅网站变更，未改原生应用或发布标签。
