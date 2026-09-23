# WindowShade 官网

独立静态产品站，中文首页与 `/en/` 英文页共用模板和交互。在 Cloudflare Pages 通过 Wrangler Direct Upload 发布，不影响主应用的 swiftc 构建。

```sh
cd site
npm ci
npm run build
npm run check
npm run dev
```

本地预览地址 `http://127.0.0.1:4318`。部署前运行构建与检查；首次登录使用 `npx wrangler login`。项目存在后运行：

```sh
npm run deploy
```

部署固定到 `windowshade` 项目的 `main` 生产分支。仅上传 `dist/`。身份由本机 Wrangler OAuth 管理，不在仓库中保存凭据。换域名时，通过 `SITE_ORIGIN` 传入公开站点 origin 后构建，并相应更新 Pages 域名设置。

本项目已创建。Wrangler 4.131.1 创建新项目默认尝试转到 Workers；本次按用户指定的 Pages 使用 `npx wrangler pages project create windowshade --production-branch main --force` 创建。这个参数只用于首次创建，后续正常运行 `npm run deploy`，不要添加 `--force`。

## 维护

- `scripts/content.mjs`：中英文文案；`scripts/build.mjs`：页面模板、SEO、404、安全响应头。
  首页按一条主线排：“收起窗口，留下位置”。Hero 是可双击、可拖动的网页桌面；接着是“三种让开的办法”（关掉 / 最小化 / 收起）对比、
  窗口往事的入口（封面用考古页的四个年代标题栏，章节目录与史料数取自 `history.mjs` 的 `historyIndex`，两页共用一份，不另写摘要）、
  置顶、窗口浏览、合盖彩蛋（可拖动滑块合盖、切换三种质感）、快捷键、隐私与问答。
- `style.css`：冷白/石墨主题、单一蓝色、首页与考古页共用的页眉/按钮/页脚。示意桌面（`.stage`）内部尺寸全用 `cqw`，
  随宽度整体缩放；窗口红绿灯、间距、圆角按本机真实窗口实测比例缩小。
- `app.js`：主题切换、滚动后页眉细线、首次进入的轻量浮现；Hero 收起/展开与拖动（按下即捕获指针，边缘回弹）、
  首次看到时自动演示一次；三种方式的对比动画；置顶与窗口浏览示意；合盖动画。演示不操纵真实窗口；
  窗口浏览示意默认展开、指针移开收起、点一下留着，和真实面板一样只读；合盖动画第一次看到时演示一次，之后由滑块控制。
  所有动效在“减少动态效果”下退回静态。
- `public/media/`：发布素材，独立保存在官网目录，不依赖被 Git 忽略的 `assets/` 或 `video/`。产品媒体均本地加载，没有追踪脚本或远程字体；考古页的旧系统模拟器仅在点击启动后连接 Infinite Mac。
- 下载按钮链接到 GitHub 最新 Release 页面，避免固定到过期 ZIP。

## 素材来源

- `desk*.webp`：窗口往事结尾的“今天”配图，和首页首屏同一张网页桌面（收起状态，中英、浅深色各一张），由 README 的 `assets/readme-desk*.png` 转成 WebP。
- `icon.png`（192px）/ `icon-256.png`：由 `assets/app-icon/windowshade-app-icon.png` 去掉白色底角后缩小，深色外观下不再露出白方块；`apple-touch-icon.png` 保留不透明原图（iOS 自己裁圆角）。
- 分享卡片（聊天软件和社交网站的链接预览）：每页一张 1200 × 630 JPEG。`og.jpg` / `og-en.jpg` 是首页首屏，`og-history.jpg` / `og-history-en.jpg` 是窗口往事封面（标题 + 四个年代的标题栏）；改了对应首屏后用无头 Chrome 以 1200 宽重截。元数据集中在 `scripts/chrome.mjs` 的 `shareMeta`（标题、描述、尺寸、替代文字、站点名、Twitter 卡片），`npm run check` 会检查每页的卡片图片存在且是 JPEG。
- `share-square.jpg`：512 × 512 的不透明图标。有些聊天软件（如微信）不读 og:image，而是取页面里第一张大图，所以每页开头放一张隐藏、延迟加载的它：浏览器不会下载，解析网页的程序能看到。
- 首页不再使用旧的 `hero.webp`（窗口选择面板渲染）和 `settings.webp`（1.0.12 设置截图）：两张图里还是“窗口选择”“已折叠”“折叠”等旧词，已删除。
- 合盖彩蛋是网页动画（`app.js` 的 lid 部分），不再用录屏：触发点、弹簧与三种质感的角度 / 模糊 / 变暗取自 `prototype/Effects/FoldDriver.swift`。README 里的 `assets/windowshade-lid*.gif` 就是逐帧截下的这段动画。

源码 MIT 许可沿用上级仓库。网页里不添加未经核实的用户量、媒体背书、性能数字或付费计划。

## 互动考古

`/history/` 与 `/en/history/` 是原创七章互动长文，首页导航和专题入口与之相连。它和首页共用页眉、页脚、配色、窗口外观与控件（`scripts/chrome.mjs`、`style.css`），自己只保留书宋标题和更慢的阅读节奏；页眉底边有阅读进度。`scripts/history.mjs` 维护中英文正文、史料条目与模板，`history.css` / `history.js` 管理四个轻量实验与旧系统实验室。

依据原手册重绘的界面均标注为示意。年代以原始手册和 Apple 发布资料核对；1989–92 版权区间不作为首发日期，2001 OS X 和 2003 Exposé 分开。13 条史料与致谢随页面交付，不部署下载的研究 PDF。

Infinite Mac 官方 `/embed` 接口按需加载 System 7.5、Mac OS 8.0、Mac OS X 10.1，一次只挂载一个 iframe；统一使用 640×480 原始画布并等比例适配，避免小屏裁掉 Dock；切换/关闭会释放，`auto_pause` 处理离屏与标签页切换。原站在独立链接下始终可访问，45 秒未收到启动信号会给出重试提示。完成复选框是读者自记，不伪称检测了机内操作。CSP 仅增加 `frame-src https://infinitemac.org`。

### 时代外观校准

`era.css` 单独负责历史界面的字体、标题栏和控件；`history.css` 保留文章布局。参考 AI System 6 的 `00-foundation.css`、`65-appearance-themes.css` 与 `67-aqua-appearance.css`，保留 Classic/Platinum 各自的尺寸、像素边框与独立 Zoom/Collapse 图形。Aqua 以本文 10.1 为边界，不复制参考项目 10.2 的定年或产品自定义灯位。

`public/fonts/ChicagoFLF.woff2`、三枚 Classic 控件 SVG 来自 AI System 6 的 System.css 参考资源（Sakun Acharige，MIT，随附 `system-css-LICENSE.txt`）；`Asap-Variable.woff2` 是该项目已有的 Charcoal 回退（Omnibus-Type，SIL OFL，随附 `Asap-OFL.txt`）。复刻与替代字体不标为 Apple 原始字体；Charcoal/Lucida Grande 优先读取本地已安装版本。标题栏组合与控制面板在布局、字体载入后对齐整像素，防止细条纹混成灰色。
