#!/usr/bin/env python3
"""H3: per-pixel dE between an sRGB capture and a displayP3 capture of the same content.

Usage: python3 -I compare-srgb-p3.py capsule-raw-sRGB.png capsule-raw-displayP3.png

Two readings are reported (CIEDE2000, D65, pure Python + PIL, no numpy):
  tagged   P3 pixels decoded as Display P3, converted to sRGB-linear, compared with the sRGB capture.
           This is what a colour-managed display layer (AVSampleBufferDisplayLayer) shows.
  untagged P3 numbers compared as if they were sRGB numbers. This is what happens when a patch
           detected / pasted back with sRGB assumptions meets a P3 frame (the "negative cast").
"""
import math
import sys
from PIL import Image

def lin(c):
    c /= 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

# Display P3 (D65) linear -> XYZ ; sRGB linear -> XYZ
M_P3 = ((0.4865709, 0.2656677, 0.1982173), (0.2289746, 0.6917385, 0.0792869), (0.0, 0.0451134, 1.0439444))
M_S = ((0.4124564, 0.3575761, 0.1804375), (0.2126729, 0.7151522, 0.0721750), (0.0193339, 0.1191920, 0.9503041))
WP = (0.95047, 1.0, 1.08883)

def xyz(m, rgb):
    r, g, b = (lin(v) for v in rgb)
    return tuple(row[0] * r + row[1] * g + row[2] * b for row in m)

def lab(x):
    def f(t):
        return t ** (1 / 3) if t > 216 / 24389 else (24389 / 27 * t + 16) / 116
    fx, fy, fz = (f(x[i] / WP[i]) for i in range(3))
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))

def de2000(a, b):
    L1, a1, b1 = a; L2, a2, b2 = b
    C1 = math.hypot(a1, b1); C2 = math.hypot(a2, b2)
    Cm = (C1 + C2) / 2
    G = 0.5 * (1 - math.sqrt(Cm ** 7 / (Cm ** 7 + 25 ** 7)))
    ap1 = (1 + G) * a1; ap2 = (1 + G) * a2
    Cp1 = math.hypot(ap1, b1); Cp2 = math.hypot(ap2, b2)
    hp1 = math.degrees(math.atan2(b1, ap1)) % 360 if Cp1 else 0.0
    hp2 = math.degrees(math.atan2(b2, ap2)) % 360 if Cp2 else 0.0
    dL = L2 - L1; dC = Cp2 - Cp1
    if Cp1 * Cp2 == 0: dh = 0.0
    else:
        dh = hp2 - hp1
        if dh > 180: dh -= 360
        elif dh < -180: dh += 360
    dH = 2 * math.sqrt(Cp1 * Cp2) * math.sin(math.radians(dh / 2))
    Lm = (L1 + L2) / 2; Cpm = (Cp1 + Cp2) / 2
    if Cp1 * Cp2 == 0: hm = hp1 + hp2
    elif abs(hp1 - hp2) <= 180: hm = (hp1 + hp2) / 2
    else: hm = (hp1 + hp2 + 360) / 2 if hp1 + hp2 < 360 else (hp1 + hp2 - 360) / 2
    T = (1 - 0.17 * math.cos(math.radians(hm - 30)) + 0.24 * math.cos(math.radians(2 * hm))
         + 0.32 * math.cos(math.radians(3 * hm + 6)) - 0.20 * math.cos(math.radians(4 * hm - 63)))
    dtheta = 30 * math.exp(-(((hm - 275) / 25) ** 2))
    Rc = 2 * math.sqrt(Cpm ** 7 / (Cpm ** 7 + 25 ** 7))
    Sl = 1 + 0.015 * (Lm - 50) ** 2 / math.sqrt(20 + (Lm - 50) ** 2)
    Sc = 1 + 0.045 * Cpm; Sh = 1 + 0.015 * Cpm * T
    Rt = -math.sin(math.radians(2 * dtheta)) * Rc
    return math.sqrt((dL / Sl) ** 2 + (dC / Sc) ** 2 + (dH / Sh) ** 2 + Rt * (dC / Sc) * (dH / Sh))

def stats(name, pairs_count, total):
    vals = sorted(pairs_count)  # list of (de, n)
    mean = sum(d * n for d, n in vals) / total
    def pct(p):
        k = p * total; acc = 0
        for d, n in vals:
            acc += n
            if acc >= k: return d
        return vals[-1][0]
    over = lambda t: sum(n for d, n in vals if d > t) / total * 100
    print(f"{name:9s} mean {mean:6.2f}  p50 {pct(.5):6.2f}  p95 {pct(.95):6.2f}  p99 {pct(.99):6.2f}  max {vals[-1][0]:6.2f}  >1: {over(1):5.1f}%  >2.3: {over(2.3):5.1f}%  >5: {over(5):5.1f}%")

def main():
    sp, pp = sys.argv[1], sys.argv[2]
    a = Image.open(sp).convert("RGB"); b = Image.open(pp).convert("RGB")
    assert a.size == b.size, (a.size, b.size)
    n = a.size[0] * a.size[1]
    pa, pb = list(a.tobytes()), list(b.tobytes())
    pa = [tuple(pa[i:i + 3]) for i in range(0, len(pa), 3)]
    pb = [tuple(pb[i:i + 3]) for i in range(0, len(pb), 3)]
    cache = {}
    lab_s, lab_p = {}, {}
    hist = {"tagged": {}, "untagged": {}}
    for s, p in zip(pa, pb):
        k = (s, p)
        r = cache.get(k)
        if r is None:
            ls = lab_s.get(s) or lab_s.setdefault(s, lab(xyz(M_S, s)))
            lp_t = lab(xyz(M_P3, p))                     # P3 decoded as P3
            lp_u = lab_p.get(p) or lab_p.setdefault(p, lab(xyz(M_S, p)))  # P3 numbers read as sRGB
            r = cache[k] = (round(de2000(ls, lp_t), 3), round(de2000(ls, lp_u), 3))
        for key, v in zip(("tagged", "untagged"), r):
            hist[key][v] = hist[key].get(v, 0) + 1
    print(f"size {a.size}, {n} px, {len(cache)} distinct pairs, CIEDE2000")
    ident = sum(1 for s, p in zip(pa, pb) if s == p) / n * 100
    print(f"byte-identical pixels: {ident:.1f}%")
    for key in ("tagged", "untagged"):
        stats(key, list(hist[key].items()), n)
    # The two captures are separate runs; pixels with dE > 5 are content that moved between
    # runs (text, caret, animation), not colour space. Report the colour-only remainder too.
    for key in ("tagged", "untagged"):
        kept = [(d, c) for d, c in hist[key].items() if d <= 5]
        stats(key + "<=5", kept, sum(c for _, c in kept))
    moved = sum(c for d, c in hist["tagged"].items() if d > 5)
    print(f"content-mismatch pixels (tagged dE>5): {moved} = {moved / n * 100:.2f}%")

if __name__ == "__main__":
    main()
