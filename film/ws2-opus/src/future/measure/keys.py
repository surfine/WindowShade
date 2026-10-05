"""从 USDA 读键帽网格（点 + 面），按面连通分出每颗键，量尺寸、间距、圆角、行。"""
import json
import re
import sys

import numpy as np
import scipy.sparse as sp
from scipy.sparse.csgraph import connected_components
from scipy.spatial import ConvexHull


def mesh(path, name):
    t = open(path).read()
    i = t.index(f'def Mesh "{name}"')
    j = t.index('\n                            def ', i + 10) if '\n                            def ' in t[i + 10:] else len(t)
    blk = t[i:i + 40_000_000]
    end = blk.find('xformOpOrder')
    blk = blk[:end]
    cnt = np.array(re.search(r'faceVertexCounts = \[([^\]]*)\]', blk).group(1).split(','), dtype=int)
    idx = np.array(re.search(r'faceVertexIndices = \[([^\]]*)\]', blk).group(1).split(','), dtype=int)
    pts = re.search(r'point3f\[\] points = \[([^\]]*)\]', blk).group(1)
    p = np.array(re.findall(r'\(([^)]*)\)', pts)[0:], dtype=object)
    p = np.array([list(map(float, s.split(','))) for s in p])
    return p, cnt, idx


def components(p, cnt, idx):
    rows, cols = [], []
    k = 0
    for c in cnt:
        f = idx[k:k + c]
        for a in range(c):
            rows.append(f[a]); cols.append(f[(a + 1) % c])
        k += c
    m = sp.coo_matrix((np.ones(len(rows)), (rows, cols)), shape=(len(p), len(p)))
    n, lab = connected_components(m, directed=False)
    return n, lab


def corner_r(q):
    """顶面外轮廓的四个角：切线长度（直边在哪开始弯）。"""
    h = q[ConvexHull(q).vertices]
    out = []
    for sx in (1, -1):
        for sy in (1, -1):
            X, Y = h[:, 0] * sx, h[:, 1] * sy
            xm, ym = X.max(), Y.max()
            onx = np.abs(X - xm) < 0.003
            ony = np.abs(Y - ym) < 0.003
            tx = xm - X[ony].max() if ony.any() else np.nan
            ty = ym - Y[onx].max() if onx.any() else np.nan
            out.append((tx + ty) / 2)
    return float(np.nanmedian(out))


def run(path, name, label):
    p, cnt, idx = mesh(path, name)
    n, lab = components(p, cnt, idx)
    ks = []
    for i in range(n):
        q = p[lab == i]
        if len(q) < 6:
            continue
        top = q[q[:, 1] > q[:, 1].max() - 0.01]
        ks.append(dict(x0=q[:, 0].min(), x1=q[:, 0].max(), z0=q[:, 2].min(), z1=q[:, 2].max(), h=np.ptp(q[:, 1]),
                       top_w=np.ptp(top[:, 0]), top_d=np.ptp(top[:, 2]), r=corner_r(q[:, [0, 2]]) if len(q) > 8 else np.nan))
    # 分行：按 z 中心聚
    ks.sort(key=lambda k: (k['z0'] + k['z1']) / 2)
    rows = []
    for k in ks:
        zc = (k['z0'] + k['z1']) / 2
        if rows and abs(zc - rows[-1][-1]['zc']) < 0.45:
            k['zc'] = zc; rows[-1].append(k)
        else:
            k['zc'] = zc; rows.append([k])
    print(f'== {label}: {len(ks)} keys, {len(rows)} rows, x [{p[:,0].min():.3f}, {p[:,0].max():.3f}] z [{p[:,2].min():.3f}, {p[:,2].max():.3f}]')
    out = []
    for r in rows:
        r.sort(key=lambda k: k['x0'])
        gaps = [round(b['x0'] - a['x1'], 3) for a, b in zip(r, r[1:])]
        print(f"  row z [{min(k['z0'] for k in r):.3f}, {max(k['z1'] for k in r):.3f}] n={len(r)} widths={[round(k['x1']-k['x0'],3) for k in r]} depths={sorted(set(round(k['z1']-k['z0'],3) for k in r))} gaps~{np.median(gaps) if gaps else None} r~{np.nanmedian([k['r'] for k in r]):.3f} h~{np.median([k['h'] for k in r]):.3f}")
        out.append([dict(x0=round(k['x0'], 3), x1=round(k['x1'], 3), z0=round(k['z0'], 3), z1=round(k['z1'], 3), r=round(k['r'], 3)) for k in r])
    return out


res = {}
res['neo'] = run('/tmp/gg/usdz/neo-payload.usda', 'AqcQCwqkepkmIxJ', 'Neo keycaps')
res['air'] = run('/tmp/gg/usdz/air15-silver.usda', 'zzYGGBkSUWTdyUk', 'Air keycaps')
json.dump(res, open('/tmp/gg/usdz/keys.json', 'w'))
