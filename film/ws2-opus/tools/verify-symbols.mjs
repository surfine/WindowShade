// SF Symbol 抽取結果的獨立驗收：我們抽出來的向量 vs AppKit 自己畫的參考圖，逐像素疊圖。
//
// 為什麼需要這個：這一輪的 bug 就是「只靠肉眼看對照表」看不出來的——上下鏡射對
// 對稱符號沒有影響，只有 `checkmark` 會露餡。所以每一顆都跟參考圖疊，用數字判讀。
//
// 我們的向量用自己寫的 SVG path 光柵器畫（只支援 M/L/Q/C/Z，本專案產物就只用這幾種），
// 不經瀏覽器；參考圖由 `tools/ref-symbol.swift` 用 AppKit 畫，兩者都是「螢幕方向」。
//
// 用法：node tools/verify-symbols.mjs [weight] [symbol...]
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

const S = 384;
const WEIGHT = process.argv[2] ?? 'semibold';
const ALL = ['faceid', 'checkmark', 'checkmark.circle.fill', 'xmark.circle.fill', 'iphone', 'lock.fill', 'lock.open.fill'];
const SYMS = process.argv.slice(3).length ? process.argv.slice(3) : ALL;

// 抽兩種：原樣（正式）與 flip（故意做錯的對照組）
const paths = {};
for (const name of SYMS) {
  paths[name] = {};
  for (const mode of ['asis', 'flip']) {
    const args = [resolve(HERE, 'extract-symbol.swift'), name, WEIGHT, '160', '100', resolve(TMP, `${name}.${mode}.svg`)];
    if (mode === 'flip') args.push('flip');
    const stdout = execFileSync('swift', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });
    const [boxJSON, d] = stdout.split('\t');
    paths[name][mode] = { box: JSON.parse(boxJSON), d };
  }
  execFileSync('swift', [resolve(HERE, 'ref-symbol.swift'), name, WEIGHT, String(S), resolve(TMP, `ref-${name}.png`)], { stdio: ['ignore', 'ignore', 'inherit'] });
}

const py = resolve(TMP, 'verify.py');
writeFileSync(py, `
import json
from PIL import Image, ImageDraw, ImageChops

S = ${S}
SYMS = ${JSON.stringify(SYMS)}
paths = ${JSON.stringify(paths)}
CACHE = '${TMP}'
OUT = '${OUT}'

# ---- 最小 SVG path 光柵器：M/L/Q/C/Z，even-odd ----
def tokens(d):
    out, cur = [], ''
    i = 0
    while i < len(d):
        c = d[i]
        if c.isalpha():
            if cur: out.append(cur); cur = ''
            out.append(c); i += 1
        elif c in ' ,\\n\\t':
            if cur: out.append(cur); cur = ''
            i += 1
        else:
            j = i
            while j < len(d) and (d[j].isdigit() or d[j] in '-.eE'): j += 1
            if j == i: i += 1
            else: out.append(d[i:j]); i = j
    if cur: out.append(cur)
    return out

def sample(p0, ctrl, n=64):
    pts = []
    for k in range(1, n + 1):
        t = k / n; mt = 1 - t
        if len(ctrl) == 1: p = ctrl[0]
        elif len(ctrl) == 2:
            a, b = ctrl
            p = (mt*mt*p0[0] + 2*mt*t*a[0] + t*t*b[0], mt*mt*p0[1] + 2*mt*t*a[1] + t*t*b[1])
        else:
            a, b, c = ctrl
            p = (mt**3*p0[0] + 3*mt*mt*t*a[0] + 3*mt*t*t*b[0] + t**3*c[0],
                 mt**3*p0[1] + 3*mt*mt*t*a[1] + 3*mt*t*t*b[1] + t**3*c[1])
        pts.append(p)
    return pts

def subpaths(d):
    t = tokens(d); i = 0; cur = None; subs = []
    while i < len(t):
        k = t[i]
        if k == 'M': cur = [(float(t[i+1]), float(t[i+2]))]; subs.append(cur); i += 3
        elif k == 'L': cur.append((float(t[i+1]), float(t[i+2]))); i += 3
        elif k == 'Q':
            cur += sample(cur[-1], [(float(t[i+1]), float(t[i+2])), (float(t[i+3]), float(t[i+4]))]); i += 5
        elif k == 'C':
            cur += sample(cur[-1], [(float(t[i+1]), float(t[i+2])), (float(t[i+3]), float(t[i+4])), (float(t[i+5]), float(t[i+6]))]); i += 7
        elif k == 'Z':
            if cur: cur.append(cur[0])
            i += 1
        else: i += 1
    return subs

def raster(box, d):
    # viewBox 就是墨跡框 → 直接等比填滿 S×S（跟參考圖的處置一致）
    vx, vy, vw, vh = box['minX'], box['minY'], box['w'], box['h']
    k = min(S / vw, S / vh)
    ox, oy = (S - vw * k) / 2, (S - vh * k) / 2
    acc = None
    for sub in subpaths(d):
        pts = [((x - vx) * k + ox, (y - vy) * k + oy) for x, y in sub]
        if len(pts) < 3: continue
        m = Image.new('1', (S, S), 0)
        ImageDraw.Draw(m).polygon(pts, fill=1)
        acc = m if acc is None else ImageChops.logical_xor(acc, m)
    return acc if acc is not None else Image.new('1', (S, S), 0)

def ref_mask(path):
    im = Image.open(path).convert('RGBA')
    bg = Image.new('RGBA', im.size, (255, 255, 255, 255))
    g = Image.alpha_composite(bg, im).convert('L').resize((S, S), Image.LANCZOS)
    return [[1 if g.getpixel((x, y)) < 160 else 0 for x in range(S)] for y in range(S)]

def iou(a, b):
    inter = union = 0
    for y in range(S):
        for x in range(S):
            o, f = a[y][x], b[y][x]
            if o and f: inter += 1
            if o or f: union += 1
    return (inter / union) if union else 0.0

def vflip(a):
    return [a[S - 1 - y] for y in range(S)]

rows = []
for n in SYMS:
    ref = ref_mask(f'{CACHE}/ref-{n}.png')
    asis = raster(paths[n]['asis']['box'], paths[n]['asis']['d'])
    flip = raster(paths[n]['flip']['box'], paths[n]['flip']['d'])
    A = [[1 if asis.getpixel((x, y)) else 0 for x in range(S)] for y in range(S)]
    F = [[1 if flip.getpixel((x, y)) else 0 for x in range(S)] for y in range(S)]
    i_asis, i_flip = iou(A, ref), iou(F, ref)
    # 參考圖自己上下翻一次再比：用來確認「鏡射」真的是唯一的差
    i_asis_vs_flipped_ref = iou(A, vflip(ref))
    img = Image.new('RGB', (S, S), (255, 255, 255)); po = img.load()
    for y in range(S):
        for x in range(S):
            o, f = A[y][x], ref[y][x]
            if o and f: po[x, y] = (120, 40, 160)
            elif o: po[x, y] = (220, 40, 40)
            elif f: po[x, y] = (40, 80, 220)
    img.save(f'{OUT}/overlay-{n}.png')
    rows.append((n, i_asis, i_flip, i_asis_vs_flipped_ref))

print(f'{"符號":24s} {"原樣 IoU":>10s} {"flip IoU":>10s} {"原樣 vs 上下翻的參考":>20s}  判讀')
for n, a, f, av in rows:
    if a > 0.93: v = '✅ 與 AppKit 參考圖重合'
    elif av > 0.93: v = '❌ 上下鏡射（要改成原樣輸出）'
    elif f > a + 0.1: v = '❌ 原樣是鏡射的'
    else: v = '⚠️ 不重合，需人工看疊圖'
    print(f'{n:24s} {a:10.4f} {f:10.4f} {av:20.4f}  {v}')
`);
console.log(execFileSync('python3', [py], { encoding: 'utf8' }));
console.log('疊圖（紅＝我們抽的向量、藍＝AppKit 參考、紫＝重合）→', OUT);
