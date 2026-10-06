// 疊圖驗收：把「我們抽出來的向量」跟「AppKit 自己畫的官方版本」放在同一個基準上比。
//
// 為什麼要這樣驗：先前只憑肉眼看對照表，漏掉了上下鏡射——對稱的符號（faceid、iphone、
// lock、xmark）鏡射後看不出差，只有 `checkmark` 這種上下不對稱的才露餡。
// 這張疊圖對每一顆都有效。
//
// 做法：兩邊都**正規化到自己的墨跡框**再縮成 256×256 比較，完全避開縮放與留白的差異。
//   - 我們這邊：用一支極簡 SVG path 光柵器畫（只支援 M/L/Q/C/Z，本專案產物就只用這幾種），
//     不經瀏覽器，少一層不確定。
//   - 官方那邊：AppKit 直接畫（tools/official-symbol.swift），不經過我自己的轉換。
//   同時跑 `noflip` 與 `flip` 兩種 y 方向，**讓 IoU 決定**要用哪一種：
//     IoU(不翻) 高 → `CUINamedVectorGlyph.CGPath` 本來就是 y 向下，不該再翻
//     IoU(上下翻) 高 → 原始路徑是 y 向上，該翻
//
// 用法：node tools/overlay-symbols.mjs [weight] [symbol...]
import { execFileSync } from 'node:child_process';
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, '..');
const OUT = resolve(ROOT, 'out/future/symbols');
const TMP = resolve(ROOT, 'tools/.symbol-cache');
mkdirSync(OUT, { recursive: true });
mkdirSync(TMP, { recursive: true });

const WEIGHT = process.argv[2] ?? 'semibold';
const SYMS = process.argv.slice(3).length
  ? process.argv.slice(3)
  : ['faceid', 'checkmark', 'checkmark.circle.fill', 'xmark.circle.fill', 'iphone', 'lock.fill', 'lock.open.fill'];

for (const name of SYMS) {
  for (const mode of ['noflip', 'flip']) {
    const stdout = execFileSync('swift',
      [resolve(HERE, 'extract-symbol.swift'), name, WEIGHT, '160', '100', resolve(TMP, `${name}.${mode}.svg`), mode],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });
    const [boxJSON, d] = stdout.split('\t');
    writeFileSync(resolve(TMP, `${name}.${mode}.json`), JSON.stringify({ name, mode, box: JSON.parse(boxJSON), d }));
  }
  execFileSync('swift', [resolve(HERE, 'official-symbol.swift'), name, WEIGHT, resolve(TMP, `official-${name}.png`)],
    { stdio: ['ignore', 'ignore', 'inherit'] });
}

const script = `
import json
from PIL import Image, ImageChops, ImageDraw

N = 256
CACHE = '/Users/aaron/Documents/WindowShade/film/ws2-opus/tools/.symbol-cache'
OUT = '/Users/aaron/Documents/WindowShade/film/ws2-opus/out/future/symbols'
names = ${JSON.stringify(SYMS)}
RED, BLUE, PUR = (220, 40, 40), (40, 80, 220), (120, 40, 160)

def parse(d):
    toks, i, cur = [], 0, ''
    while i < len(d):
        c = d[i]
        if c.isalpha():
            if cur: toks.append(cur); cur = ''
            toks.append(c); i += 1
        elif c in ' ,':
            if cur: toks.append(cur); cur = ''
            i += 1
        else:
            j = i
            while j < len(d) and (d[j].isdigit() or d[j] in '-.eE'): j += 1
            if j == i: i += 1
            else: toks.append(d[i:j]); i = j
    return toks

def bez(p0, pts, n=48):
    out = []
    for k in range(1, n + 1):
        t = k / n; mt = 1 - t
        if len(pts) == 1: p = pts[0]
        elif len(pts) == 2:
            c, e = pts
            p = (mt*mt*p0[0] + 2*mt*t*c[0] + t*t*e[0], mt*mt*p0[1] + 2*mt*t*c[1] + t*t*e[1])
        else:
            c1, c2, e = pts
            p = (mt**3*p0[0] + 3*mt*mt*t*c1[0] + 3*mt*t*t*c2[0] + t**3*e[0],
                 mt**3*p0[1] + 3*mt*mt*t*c1[1] + 3*mt*t*t*c2[1] + t**3*e[1])
        out.append(p)
    return out

def subpaths(d):
    toks, i, cur, subs = parse(d), 0, None, []
    while i < len(toks):
        t = toks[i]
        if t == 'M': cur = [(float(toks[i+1]), float(toks[i+2]))]; subs.append(cur); i += 3
        elif t == 'L': cur.append((float(toks[i+1]), float(toks[i+2]))); i += 3
        elif t == 'Q': cur += bez(cur[-1], [(float(toks[i+1]), float(toks[i+2])), (float(toks[i+3]), float(toks[i+4]))]); i += 5
        elif t == 'C': cur += bez(cur[-1], [(float(toks[i+1]), float(toks[i+2])), (float(toks[i+3]), float(toks[i+4])), (float(toks[i+5]), float(toks[i+6]))]); i += 7
        elif t == 'Z':
            if cur: cur.append(cur[0])
            i += 1
        else: i += 1
    return subs

def our_mask(box, d):
    """把路徑畫在它自己的墨跡框上（1000×1000），回傳裁到墨跡的 L 圖。"""
    vx, vy, vw, vh = box['minX'], box['minY'], box['w'], box['h']
    K = 1000
    k = min(K / vw, K / vh)
    ox, oy = (K - vw * k) / 2, (K - vh * k) / 2
    acc = Image.new('1', (K, K), 0)
    for sub in subpaths(d):
        pts = [((x - vx) * k + ox, (y - vy) * k + oy) for x, y in sub]
        if len(pts) < 3: continue
        m = Image.new('1', (K, K), 0)
        ImageDraw.Draw(m).polygon(pts, fill=1)
        acc = ImageChops.logical_xor(acc, m)          # even-odd
    bb = acc.getbbox()
    return acc.convert('L').crop(bb)

def official_mask(p):
    im = Image.open(p).convert('RGBA')
    a = im.getchannel('A').point(lambda v: 255 if v > 96 else 0).convert('L')
    return a.crop(a.getbbox())

def norm(im):
    return im.resize((N, N), Image.NEAREST).point(lambda v: 255 if v > 127 else 0)

def iou(a, b):
    i = ImageChops.darker(a, b).histogram()[255]
    u = ImageChops.lighter(a, b).histogram()[255]
    return i / u if u else 0.0

def overlay(a, b, path):
    img = Image.new('RGB', (N, N), (255, 255, 255))
    img.paste(BLUE, mask=b)
    img.paste(PUR, mask=ImageChops.darker(a, b))
    img.paste(RED, mask=ImageChops.darker(a, ImageChops.invert(b)))
    img.save(path)

print(f'{"符號":24s} {"IoU(不翻)":>10s} {"IoU(上下翻)":>12s}  判讀')
for n in names:
    offi = norm(official_mask(f'{CACHE}/official-{n}.png'))
    rows = {}
    for mode in ('noflip', 'flip'):
        j = json.load(open(f'{CACHE}/{n}.{mode}.json'))
        rows[mode] = norm(our_mask(j['box'], j['d']))
    a, b = iou(rows['noflip'], offi), iou(rows['flip'], offi)
    if a > 0.90 and a > b: verdict = '不翻＝重合（這條路徑本來就是 y 向下）'
    elif b > 0.90 and b > a: verdict = '上下翻才重合（原始路徑是 y 向上）'
    elif abs(a - b) < 0.03: verdict = '★ 上下對稱：鏡射驗不出來，改用形狀／寬度剖面'
    else: verdict = '兩者都不重合，要再查'
    print(f'{n:24s} {a:10.4f} {b:12.4f}  {verdict}')
    overlay(rows['noflip'], offi, f'{OUT}/overlay-{n}.png')
    overlay(rows['flip'], offi, f'{OUT}/overlay-flipped-{n}.png')
print('疊圖（紅＝我們的向量、藍＝AppKit 官方、紫＝重合）→', OUT)
`;
const py = resolve(TMP, 'overlay.py');
writeFileSync(py, script);
console.log(execFileSync('python3', [py], { encoding: 'utf8' }));
