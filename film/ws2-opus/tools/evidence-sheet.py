#!/usr/bin/env python3
"""把符號方向的三項證據拼成一張可交付的圖（`out/future/symbols/evidence-sheet.png`）。

三項：
  A 疊圖（紅＝AppKit 官方、藍＝本專案向量、黑＝重合）：勾與圓勾各一張，×3 放大。
  B 成品緊凑裁切：片子那支 `IslandLayers` 的綠格勾（f660）與純勾（f1500），NEAREST ×8。
  C 真 Face ID 符號：片子解鎖那一格（f440）裡的 `faceid`，NEAREST ×8。

不重畫、不示意：A 是 `WS2FutureSymbolOverlay` 渲出來的，B/C 是 `WS2FutureIslandQA`
那一張驗收台（用的就是片子那支 `IslandLayers`）裁下來的。
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SYM = ROOT / 'out' / 'future' / 'symbols'
QA = SYM / 'islandqa.png'
OUT = SYM / 'evidence-sheet.png'
M = '"PingFang SC","Heiti SC",sans-serif'

BG = (16, 17, 20)
PANEL = (26, 28, 33)
WHITE = (238, 240, 244)
DIM = (150, 158, 170)


def label(draw, xy, text, fill=WHITE):
    draw.text(xy, text, fill=fill, font=None)


def main() -> None:
    import json

    qa = Image.open(QA).convert('RGB')
    scores = {r['symbol']: r['iou'] for r in json.loads((SYM / 'overlay-scores.json').read_text())}

    # ---- A：疊圖 ----
    ov = []
    for name, cap in [('checkmark', '勾 checkmark'), ('checkmark.circle.fill', '圓勾 checkmark.circle.fill')]:
        im = Image.open(SYM / f'overlay-{name}.png').convert('RGB')
        im = im.resize((im.width * 3, im.height * 3), Image.NEAREST)
        ov.append((im, f'{cap}   與官方重合 IoU {scores.get(name, 0):.4f}'))

    # ---- B：成品裁切 ----
    live = [
        (qa.crop((884, 324, 946, 382)), 'film f660　綠格裡的勾'),
        (qa.crop((860, 932, 918, 992)), 'film f1500　純勾'),
    ]
    live = [(im.resize((im.width * 8, im.height * 8), Image.NEAREST), cap) for im, cap in live]

    # ---- C：真 Face ID ----
    face = [(qa.crop((880, 40, 1040, 150)).resize((160 * 5, 110 * 5), Image.NEAREST), 'film f440　faceid + iphone 真符號')]

    GAP = 28
    top = 56 + 34
    # 版面：第一列 A（兩張 768 方），第二列 B+C
    row2 = live + face
    w1 = sum(im.width for im, _ in ov) + GAP * (len(ov) - 1)
    w2 = sum(im.width for im, _ in row2) + GAP * (len(row2) - 1)
    W = max(w1, w2) + GAP * 2
    h2 = max(im.height for im, _ in row2) if row2 else 0
    H = top + ov[0][0].height + 60 + 30 + h2 + 40

    sheet = Image.new('RGB', (W, H), BG)
    d = ImageDraw.Draw(sheet)
    label(d, (GAP, 20), '符號方向驗收：紅＝AppKit 官方、藍＝本專案向量、黑＝重合（×3 放大）')

    y = top
    x = GAP
    for im, cap in ov:
        # 棋盤底，方便看紅藍
        sheet.paste(im, (x, y))
        d.rectangle([x, y, x + im.width, y + im.height], outline=(70, 74, 82))
        label(d, (x, y - 22), cap, DIM)
        x += im.width + GAP

    y2 = y + ov[0][0].height + 56
    d.text((GAP, y2 - 30), '成品緊凑裁切（NEAREST ×8）', fill=WHITE)
    x = GAP
    for im, cap in row2:
        sheet.paste(im, (x, y2))
        d.rectangle([x, y2, x + im.width, y2 + im.height], outline=(70, 74, 82))
        label(d, (x, y2 + im.height + 8), cap, DIM)
        x += im.width + GAP

    sheet.save(OUT)
    print(f'寫出 {OUT}  {sheet.size}')


if __name__ == '__main__':
    main()
