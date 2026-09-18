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
  首页现有四块功能主体：卷帘、置顶、窗口浏览、合盖动态效果（外加互动考古）。
- `style.css`：冷白/石墨主题、单一蓝色、桌面和手机布局、减少动态效果。
- `app.js`：网页卷帘/置顶/窗口浏览交互示意、主题切换、实录播放。演示不操纵真实窗口；
  窗口浏览示意默认展开、指针移开收起、点一下钉住，和真实面板一样只读，直到你按下动作按钮；
  录屏默认不自动播放，离开视口时暂停。
- `public/media/`：发布素材，独立保存在官网目录，不依赖被 Git 忽略的 `assets/` 或 `video/`。产品媒体均本地加载，没有追踪脚本或远程字体；考古页的旧系统模拟器仅在点击启动后连接 Infinite Mac。
- 下载按钮链接到 GitHub 最新 Release 页面，避免固定到过期 ZIP。

## 素材来源

- `hero.webp`：使用内置 image_gen 生成的品牌纸面作品；不是应用截图。完整提示词见 `hero-prompt.txt`。生成后用 Sharp 转 WebP，1536 × 1024。
- `icon.png`：项目原有 `assets/app-icon/windowshade-app-icon.png` 的 192px 版本。
- `settings.webp`：项目真实原生设置截图（作者提供，v1.0.12 的“效果”页），压缩为 WebP 1440 × 1088。之前的深色截图已删除：新截图只有浅色外观，页面说明也相应改成不再声称跟随系统明暗。
- `duo.mp4` 与 `duo-poster.webp`：项目现有 `assets/windowshade-demo.gif` 的无声 H.264 转码和首帧，约 7 秒。已检查整段内容，没有采用含私人聊天的早期 social 截图。

源码 MIT 许可沿用上级仓库。网页里不添加未经核实的用户量、媒体背书、性能数字或付费计划。

## 互动考古

`/history/` 与 `/en/history/` 是原创七章互动长文，首页导航和专题入口与之相连。`scripts/history.mjs` 维护中英文正文、史料条目与模板，`history.css` / `history.js` 管理四个轻量实验与旧系统实验室。

依据原手册重绘的界面均标注为示意。年代以原始手册和 Apple 发布资料核对；1989–92 版权区间不作为首发日期，2001 OS X 和 2003 Exposé 分开。13 条史料与致谢随页面交付，不部署下载的研究 PDF。

Infinite Mac 官方 `/embed` 接口按需加载 System 7.5、Mac OS 8.0、Mac OS X 10.1，一次只挂载一个 iframe；统一使用 640×480 原始画布并等比例适配，避免小屏裁掉 Dock；切换/关闭会释放，`auto_pause` 处理离屏与标签页切换。原站在独立链接下始终可访问，45 秒未收到启动信号会给出重试提示。完成复选框是读者自记，不伪称检测了机内操作。CSP 仅增加 `frame-src https://infinitemac.org`。

### 时代外观校准

`era.css` 单独负责历史界面的字体、标题栏和控件；`history.css` 保留文章布局。参考 AI System 6 的 `00-foundation.css`、`65-appearance-themes.css` 与 `67-aqua-appearance.css`，保留 Classic/Platinum 各自的尺寸、像素边框与独立 Zoom/Collapse 图形。Aqua 以本文 10.1 为边界，不复制参考项目 10.2 的定年或产品自定义灯位。

`public/fonts/ChicagoFLF.woff2`、三枚 Classic 控件 SVG 来自 AI System 6 的 System.css 参考资源（Sakun Acharige，MIT，随附 `system-css-LICENSE.txt`）；`Asap-Variable.woff2` 是该项目已有的 Charcoal 回退（Omnibus-Type，SIL OFL，随附 `Asap-OFL.txt`）。复刻与替代字体不标为 Apple 原始字体；Charcoal/Lucida Grande 优先读取本地已安装版本。标题栏组合与控制面板在布局、字体载入后对齐整像素，防止细条纹混成灰色。
