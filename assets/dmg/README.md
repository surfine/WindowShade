# DMG 安装窗口美术

来源：`docs/design-drafts/1.0.18 新表面 小样.html` 第 4 节（`dmgArt()` 照抄成 `background.svg`）。背景里不写字，三种语言共用；图标名字压在中灰 `#6C7686` 上，浅色外观黑字 4.57 : 1、深色外观白字 4.59 : 1。

| 文件 | 用途 |
| --- | --- |
| `background.svg` | 源，600 x 400 pt |
| `background.png` / `background@2x.png` | 600 x 400（72 dpi）、1200 x 800（144 dpi） |
| `background.tiff` | `tiffutil -cathidpicheck background.png background@2x.png -out background.tiff`；`make-dmg.sh` 拷到卷宗的 `.background/background.tiff` |

重新生成：

```sh
cd assets/dmg
rsvg-convert -w 600 -h 400 background.svg -o background.png
rsvg-convert -w 1200 -h 800 background.svg -o background@2x.png
sips -s dpiWidth 72 -s dpiHeight 72 background.png
sips -s dpiWidth 144 -s dpiHeight 144 background@2x.png
tiffutil -cathidpicheck background.png background@2x.png -out background.tiff
```

## Finder 窗口参数（给 scripts/make-dmg.sh）

- 内容区 600 x 400 pt（`bounds` 的高度要再加标题栏 28，即窗口 600 x 428），隐藏工具栏、路径栏、状态栏；图标视图，图标 128，字号 13，不自动排列。
- 图标中心：`WindowShade.app` 在 (150, 200)；`Applications` 符号链接在 (450, 200)。AppleScript 里用 `set position of item ... to {150, 200}`（Finder 的 position 就是图标中心，内容区坐标）。
- 图标上沿 y = 136，卷帘那一截（0 到 131）只在图标上方。
- 卷宗图标 `.VolumeIcon.icns` = `assets/app-icon/WindowShade.icns`，`SetFile -a C`。
- 窗口打开在屏幕中间偏上。
