#!/usr/bin/env python3
"""呼叫點緊凑裁切（驗收證據用）。

為什麼要這支：片子裡鏡頭常退得很遠，島在 1920×1080 裡只有幾十像素，
勾是正是反肉眼分不出來；舊的 `callsites-sheet.png` 又是「整格畫面縮小」，
等於把證據抽掉。這支的規矩：

  1. 只用 **NEAREST** 放大（不插值、不模糊），預設 8～10 倍。
  2. 裁切框由**墨跡實測**決定（先量 bbox），不用「找最亮的方塊」再猜位置。
  3. 一張符號一張圖，檔名寫清楚是哪個呼叫點。

輸入是 `WS2FutureSymbolCallsites`（1:1、走片子同一條渲染路）的渲圖，
外加片子實際的 `after-223.png` 做對照。
"""
import json
import sys
from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'out' / 'future' / 'symbols'
RENDER = OUT / 'callsite-render'
DEST = OUT / 'evidence'


def ink_bbox(im, region, pred):
    px = im.load()
    x0, y0, x1, y1 = region
    xs, ys = [], []
    for y in range(max(0, y0), min(y1, im.height)):
        for x in range(max(0, x0), min(x1, im.width)):
            if pred(px[x, y]):
                xs.append(x); ys.append(y)
    return (min(xs), min(ys), max(xs), max(ys)) if xs else None


def biggest_blob(im, region, pred, minpts=60):
    """回傳範圍內最大的一塊連通墨跡的 bbox。
    一定要挑最大塊：島上還有別的綠東西（iPhone 旁那顆 9×9 綠點），
    用整區 bbox 會把那顆點也框進去，裁出來就變成一大條、勾反而很小。"""
    px = im.load()
    x0, y0, x1, y1 = region
    pts = set()
    for y in range(max(0, y0), min(y1, im.height)):
        for x in range(max(0, x0), min(x1, im.width)):
            if pred(px[x, y]):
                pts.add((x, y))
    best = None
    while pts:
        s = pts.pop(); q = deque([s]); comp = [s]
        while q:
            cx, cy = q.popleft()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (cx + dx, cy + dy)
                    if n in pts:
                        pts.discard(n); q.append(n); comp.append(n)
        if best is None or len(comp) > len(best):
            best = comp
    if not best or len(best) < minpts:
        return None
    xs = [p[0] for p in best]; ys = [p[1] for p in best]
    return (min(xs), min(ys), max(xs), max(ys)), len(best)


green = lambda p: p[1] > 110 and p[1] > p[0] + 25 and p[1] > p[2] + 25


def crop(im, box, name, zoom, pad):
    x0, y0, x1, y1 = box
    x0 = max(0, x0 - pad); y0 = max(0, y0 - pad)
    x1 = min(im.width, x1 + pad + 1); y1 = min(im.height, y1 + pad + 1)
    c = im.crop((x0, y0, x1, y1))
    out = c.resize((c.width * zoom, c.height * zoom), Image.NEAREST)
    out.save(DEST / name)
    return {'file': name, 'crop': [x0, y0, x1, y1], 'zoom': zoom, 'out': list(out.size)}


# 每個呼叫點：(來源檔, 量測範圍, 檔名, 倍率, 邊距, 說明, 量測模式)
#   mode='stroke'：綠筆畫本身就是勾，直接量最高點。
#   mode='disc'  ：綠的是整塊圓餅、勾是挖空的黑洞，要量「洞」的最高點。
SITES = [
    ('c0.png', (600, 0, 1400, 200), 'crop-1-Island-check-ring.png', 10, 26,
     'Island.tsx f320「欢迎回来」：綠圓餅 + 挖空的黑勾（checkmark.circle.fill）', 'disc'),
    ('c1.png', (800, 0, 1200, 160), 'crop-2-FilmUnlock-check.png', 10, 24,
     'Screen.tsx Unlock f460：刷臉認出來，綠勾（裸 checkmark）', 'stroke'),
    ('c2.png', (800, 0, 1200, 200), 'crop-3-Neo-check.png', 8, 22,
     'NeoScreen.tsx 已確認：綠勾（裸 checkmark）', 'stroke'),
]


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    rep = []
    for src, region, name, zoom, pad, label, mode in SITES:
        im = Image.open(RENDER / src).convert('RGB')
        found = biggest_blob(im, region, green)
        if not found:
            raise SystemExit(f'{src} 在 {region} 找不到夠大的綠墨跡')
        bb, n = found
        r = crop(im, bb, name, zoom, pad)
        r.update({'site': label, 'source': f'callsite-render/{src}', 'mode': mode,
                  'measured_bbox': list(bb), 'blob_px': n})
        rep.append(r)
        print(f'{name}\n    來源 {src}  最大綠塊 {bb}  {bb[2]-bb[0]+1}×{bb[3]-bb[1]+1}px / {n} 點')
        print(f'    裁切 {r["crop"]} ×{zoom} → {r["out"]}')

    # 片子實際的 after-223.png：同一個 Unlock 元件，但鏡頭退得遠。
    im = Image.open(OUT / 'after-223.png').convert('RGB')
    found = biggest_blob(im, (600, 0, 1400, 420), green)
    if found:
        bb, n = found
        r = crop(im, bb, 'crop-4-film-after223-green.png', 10, 10)
        r.update({'site': 'Concept 片 after-223.png：這裡的綠是「淡出中的 faceid 外框」，不是勾（見 README）',
                  'source': 'after-223.png', 'measured_bbox': list(bb), 'blob_px': n})
        rep.append(r)
        print(f'\ncrop-4-film-after223-green.png\n    最大綠塊 {bb}  {bb[2]-bb[0]+1}×{bb[3]-bb[1]+1}px / {n} 點 → 裁切 {r["crop"]} ×10')

    (DEST / 'crops.json').write_text(json.dumps(rep, indent=2), encoding='utf-8')
    print('\n寫出到 out/future/symbols/evidence/')

    # ── 第二意見：方向判別式（只對「綠筆畫本身就是勾」的那幾張有意義）──────
    # 正的勾 ✓：最高點在右端（短臂在左下）。倒的勾 ^：最高點在中間。
    print('\n方向判別：最高點的橫向位置（0=最左、1=最右）。0.7 以上＝右端＝正的勾；')
    print('          0.5 附近＝中間＝倒的勾。以**勾自己的墨跡框**為分母（不是圓餅、也不是裁切留白）。')
    for r in rep:
        im = Image.open(DEST / r['file']).convert('L')
        x0, y0, x1, y1 = r['measured_bbox']
        z = r['zoom']
        cx0 = max(0, int((x0 - r['crop'][0]) * z)); cy0 = max(0, int((y0 - r['crop'][1]) * z))
        cx1 = min(im.width, int((x1 - r['crop'][0] + 1) * z)); cy1 = min(im.height, int((y1 - r['crop'][1] + 1) * z))
        px = im.load()
        if r.get('mode') == 'disc':
            # 圓餅上的勾是挖空的黑：某欄裡第一個黑點，且它上下都還有綠（否則抓到的是圓餅外的黑底）。
            pts = []
            for x in range(cx0, cx1):
                gys = [y for y in range(cy0, cy1) if px[x, y] > 140]
                if len(gys) < 3:
                    continue
                hole = [y for y in range(gys[0] + 1, gys[-1]) if px[x, y] < 140]
                if hole:
                    pts.append((x, hole[0]))
            what = '挖空的勾'
        else:
            pts = [(x, min([y for y in range(cy0, cy1) if px[x, y] > 140]))
                   for x in range(cx0, cx1) if any(px[x, y] > 140 for y in range(cy0, cy1))]
            what = '綠筆畫'
        if not pts:
            continue
        # 用「勾自己的 bbox」當分母，否則圓餅的半徑會把比例稀釋掉。
        gx0 = min(p[0] for p in pts); gx1 = max(p[0] for p in pts)
        top = min(pts, key=lambda p: p[1])
        rel = (top[0] - gx0) / max(1, gx1 - gx0)
        verdict = '正的勾 ✓' if rel > 0.7 else ('中間＝可能倒的' if 0.35 < rel < 0.65 else '偏左')
        print(f"  {r['file']:38s} {what}框 x{gx0}–{gx1}（{gx1-gx0+1}px）　最高點在 {rel:.3f}  → {verdict}")


if __name__ == '__main__':
    sys.exit(main())
