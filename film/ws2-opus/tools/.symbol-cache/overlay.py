
import json
from PIL import Image, ImageChops, ImageDraw

N = 256
CACHE = '/Users/aaron/Documents/WindowShade/film/ws2-opus/tools/.symbol-cache'
OUT = '/Users/aaron/Documents/WindowShade/film/ws2-opus/out/future/symbols'
names = ["faceid","checkmark","checkmark.circle.fill","xmark.circle.fill","iphone","lock.fill","lock.open.fill"]
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
