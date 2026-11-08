#!/usr/bin/env python3
"""符號疊圖比對（重寫版）。

前一版為什麼是廢圖：比對「我們的向量」時，我自己寫的 SVG 光柵器把
`Image.new('1')` + `ImageDraw.polygon(fill=1)` 的結果拿去 `logical_xor`，
輸出只剩一條斜線；官方的 PNG 那份也被同一個 bbox 正規化吃掉了。圖讀不出東西，
就等於沒驗。現在改成：

  1. 「我們的」那一半由 Remotion 畫（`WS2FutureSymbolOverlay`，走 `<Sym>` 這條生產路）。
  2. 「官方的」那一半是 AppKit 直接點陣出來的 PNG（`tools/official-symbol.swift`）。
  3. 這支 Python 只做「切圖、二值化、等比縮放、貼色」——不做任何幾何換算。

判讀：黑＝兩邊重合、紅＝只有官方、藍＝只有我們。紅藍越少越像。
"""
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'out' / 'future' / 'symbols'
RENDER = OUT / 'overlay-render'
SYMS = ['faceid', 'checkmark', 'checkmark.circle.fill', 'xmark.circle.fill', 'iphone', 'lock.fill', 'lock.open.fill']
N = 256
BOX = 512


def mask(img: Image.Image) -> Image.Image:
    """暗＝墨跡（兩格都是白底黑字）。裁到墨跡框。"""
    m = img.convert('L').point(lambda v: 255 if v < 128 else 0)
    bb = m.getbbox()
    if bb is None:
        raise SystemExit('空白遮罩：渲染出來的圖裡沒有墨跡')
    return m.crop(bb)


def fit(m: Image.Image) -> Image.Image:
    """等比縮放到高 256（NEAREST，不插值），水平置中放進 256×256。"""
    h = N
    w = max(1, round(m.width * h / m.height))
    m = m.resize((w, h), Image.NEAREST)
    c = Image.new('L', (N, N), 0)
    c.paste(m, (max(0, (N - w) // 2), 0))
    return c


def both_ink(a: Image.Image, b: Image.Image) -> tuple:
    ap, bp = a.load(), b.load()
    ov = Image.new('L', (N, N), 0)
    op = ov.load()
    for y in range(N):
        for x in range(N):
            op[x, y] = 255 if (ap[x, y] and bp[x, y]) else 0
    return ov


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for i, name in enumerate(SYMS):
        f = RENDER / f'f{i}.png'
        if not f.exists():
            raise SystemExit(f'缺渲染圖：{f}')
        im = Image.open(f).convert('RGB')
        if im.size != (BOX, BOX * 2):
            raise SystemExit(f'{f} 尺寸 {im.size}，預期 {BOX}×{BOX*2}')
        # 渲染是 512×1024：上＝官方、下＝我們。
        W, H = im.size
        top = im.crop((0, 0, W, H // 2))
        bot = im.crop((0, H // 2, W, H))

        off, ours = mask(top), mask(bot)
        print(f'{name:24s} 官方墨跡框 {off.size} 比例 {off.width/off.height:.4f} | '
              f'我們墨跡框 {ours.size} 比例 {ours.width/ours.height:.4f}')

        a, b = fit(ours), fit(off)
        inter = sum(1 for y in range(N) for x in range(N) if a.load()[x, y] and b.load()[x, y])
        uni = sum(1 for y in range(N) for x in range(N) if a.load()[x, y] or b.load()[x, y])
        iou = inter / uni if uni else 0.0

        # 紅＝官方、藍＝我們、黑＝重合。
        canvas = Image.new('RGB', (N, N), (255, 255, 255))
        cp, ap, bp = canvas.load(), a.load(), b.load()
        for y in range(N):
            for x in range(N):
                o, u = ap[x, y] > 0, bp[x, y] > 0
                if o and u:
                    cp[x, y] = (0, 0, 0)
                elif u:
                    cp[x, y] = (0, 90, 255)
                elif o:
                    cp[x, y] = (230, 0, 0)
        canvas.save(OUT / f'overlay-{name}.png')
        rows.append({'symbol': name, 'iou': iou,
                     'official_ink': list(off.size), 'ours_ink': list(ours.size)})
        print(f'{name:24s} IoU(等比、以高對齊) = {iou:.4f}')

    (OUT / 'overlay-scores.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    print('\n寫出：')
    for r in rows:
        print(f"  overlay-{r['symbol']}.png  IoU {r['iou']:.4f}")


if __name__ == '__main__':
    sys.exit(main())
