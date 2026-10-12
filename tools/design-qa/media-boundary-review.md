# 播放器与文件架：下一批样件的输入边界

状态：准备记录，未验视觉或交互。DeepSeek 提供初稿；主模型复核后删除未证实的“差异”，纠正其把同一已授权文件的未读取段落称为“范围外”的说法。原稿和 SHA 保留在本轮证据。此文件不能作为产品缺陷清单或验收通过声明。

播放器的实际入口是 `NowPlayingCard.init(geometry:)`（App/NowPlayingCard.swift:275）和 `update(_:artwork:)`（:393）。用合成 `NowPlayingCardContent`，固定 `clock`，在任何输出设备动作前将 `loadRoutes` 替换为合成设备；默认值会读实际音频设备（:192）。`onCommand`、`onSeek`、`onSelectRoute` 只能记录本地回调，不能接真实媒体命令。第一组画面应覆盖播放、暂停、无封面、长歌名、无时长及空输出设备列表。播放器封面类型的构造器尚未复核。

文件架实际入口是 `FileShelfView.init(controller:hasNotch:strip:)`（App/FileShelfView.swift:828），控制器必须显式传 `FileShelfStore(root:undoDelay:isEnabled:)`（App/FileShelfStore.swift:91）。默认目录为用户真实文件架，默认开关读取 UserDefaults；样件必须使用独有系统临时目录和固定开关闭包。控制器行数据由 store 更新，并非可直接赋值；controller.start() 与 apply(_:) 另外读取 FileShelf.enabled（App/FileShelfView.swift:118、140），所以只注入 store 的 isEnabled 还不够。不能调用 controller.setEnabled(_:) 为样件改用户持久偏好；后续需采用进程内 volatile domain，并验证独有 store 的异步启动／清理。`image(for:)`（App/FileShelfView.swift:164）可退到类型图标，但启动过程可能生成 QuickLook 缩略图，不能假定只传假路径就不会读磁盘。只能使用自造资料，不能点击打开、显示位置、系统预览、隔空投送或剪贴板动作。第一组画面应覆盖空架、一项、多项、长文件名、失效项及移出后撤销。

目前没有认定新的生产缺陷：

- 歌手取色已实际接在 `setArtwork` 中（App/NowPlayingCard.swift:429），初稿所述“取色缺口”撤销。
- `isSeekable` 的流健康限制是源码明确的运行约束（Core/NowPlayingCardLogic.swift:198），不能因静态稿省略这层条件就称为设计偏差。
- 无歌手的判据只裁 `.whitespaces`（同文件:195），换行字符边界可作为后续数据用例；目前没有播放器实际样本，不称为用户已遇到的缺陷。
- 空设备列表高度、失效项按钮和清空撤销还需实际控件及原生画面，不能用源码猜测代替结果。

设计依据为 docs/design-drafts/正在播放.html、文件架.html；稿是画面约束，不嵌进工程。本批不改播放器或文件架产品代码，不动真实媒体和用户文件。
