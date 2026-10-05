"""从 USDZ 导出的网格顶点量 Neo 与 15 英寸 Air 的实物几何（厘米，Y 向上，-Z 是背面）。"""
import json
import sys

import numpy as np
from scipy.spatial import ConvexHull
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree

ROOT = '/tmp/gg/usdz'


def V(d, n):
    a = np.fromfile(f'{ROOT}/{d}/v_{n}.f32', dtype=np.float32).reshape(-1, 3).astype(float)
    return a


def fit_circle(p):
    x, y = p[:, 0], p[:, 1]
    A = np.c_[2 * x, 2 * y, np.ones(len(x))]
    b = x * x + y * y
    c, *_ = np.linalg.lstsq(A, b, rcond=None)
    r = np.sqrt(c[2] + c[0] ** 2 + c[1] ** 2)
    return float(r), (float(c[0]), float(c[1]))


def corner(pts2, sx, sy):
    """二维点集某个角（sx, sy = ±1）：返回切线长度（圆角从哪开始离开直边）与拟合圆半径。"""
    h = pts2[ConvexHull(pts2).vertices]
    X = h[:, 0] * sx
    Y = h[:, 1] * sy
    xm, ym = X.max(), Y.max()
    tol = 0.004
    # 直边上的点：贴着 x = xm 或 y = ym
    onx = np.abs(X - xm) < tol
    ony = np.abs(Y - ym) < tol
    # 圆角从直边哪里离开
    tx = xm - X[ony].max() if ony.any() else np.nan  # 顶边最靠角的那个点离侧边多远
    ty = ym - Y[onx].max() if onx.any() else np.nan
    sel = (~onx) & (~ony) & (X > xm - max(tx, ty) - 0.01) & (Y > ym - max(tx, ty) - 0.01)
    q = np.c_[X[sel], Y[sel]]
    r = fit_circle(q)[0] if len(q) >= 4 else float('nan')
    return dict(tangent_x=round(float(tx), 3), tangent_y=round(float(ty), 3), circle_r=round(r, 3), n=int(sel.sum()))


def lid_frame(active):
    """显示区四角定盖子坐标：u 沿盖子向上，原点在显示区下沿（x=0）。"""
    y0, y1 = active[:, 1].min(), active[:, 1].max()
    z_at_y0 = active[active[:, 1] < y0 + 0.01][:, 2].mean()
    z_at_y1 = active[active[:, 1] > y1 - 0.01][:, 2].mean()
    d = np.array([y1 - y0, z_at_y1 - z_at_y0])
    L = np.linalg.norm(d)
    u = d / L
    lean = float(np.degrees(np.arctan2(-u[1], u[0])))
    return u, lean


def to_lid(p, u, origin):
    """(x, y, z) → (x, s 沿盖子, n 垂直盖子，朝前为正)。"""
    yz = p[:, 1:] - origin
    s = yz @ u
    nrm = np.array([-u[1], u[0]])  # 旋转 90°：朝前（+z）
    if nrm[1] < 0:
        nrm = -nrm
    n = yz @ nrm
    return np.c_[p[:, 0], s, n]


def keys(p, tri, eps=0.002):
    """三角形连通 + 位置焊接（eps 内的顶点算同一个）→ 每颗键一个连通块。"""
    import scipy.sparse as sp
    t = cKDTree(p)
    pairs = t.query_pairs(eps, output_type='ndarray')
    tri = tri.reshape(-1, 3)
    e = np.r_[pairs, tri[:, [0, 1]], tri[:, [1, 2]]]
    m = sp.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(len(p), len(p)))
    n, lab = connected_components(m, directed=False)
    out = []
    for i in range(n):
        q = p[lab == i]
        if len(q) < 8:
            continue
        out.append(dict(x0=q[:, 0].min(), x1=q[:, 0].max(), z0=q[:, 2].min(), z1=q[:, 2].max(), ytop=q[:, 1].max(), n=len(q)))
    out.sort(key=lambda k: (round(k['z0'], 1), k['x0']))
    return out


def rows_of(ks):
    rows = []
    for k in sorted(ks, key=lambda k: k['z0']):
        for r in rows:
            if abs(r[0]['z0'] - k['z0']) < 0.3 or abs(r[0]['z1'] - k['z1']) < 0.3:
                r.append(k)
                break
        else:
            rows.append([k])
    for r in rows:
        r.sort(key=lambda k: k['x0'])
    return rows


def machine(d, m):
    R = {}
    base = V(d, m['base'])
    R['base'] = dict(w=np.ptp(base[:, 0]), depth=np.ptp(base[:, 2]), top=base[:, 1].max(), bottom=base[:, 1].min(),
                     front=base[:, 2].max(), back=base[:, 2].min())
    bot = np.vstack([V(d, n) for n in m['bottom']])
    feet = V(d, m['feet'])
    R['base']['bottom_case'] = float(bot[:, 1].min())
    R['base']['feet_bottom'] = float(feet[:, 1].min())
    R['base']['feet'] = dict(w=float(np.ptp(feet[:, 0])), depth=float(np.ptp(feet[:, 2])))
    R['base']['corner_plan'] = corner(base[:, [0, 2]], 1, 1)
    # 厚度沿前后：每 1 cm 一段的顶、底
    prof = []
    allb = np.vstack([base, bot])
    for z in np.arange(allb[:, 2].min(), allb[:, 2].max(), 2.0):
        s = allb[(allb[:, 2] >= z) & (allb[:, 2] < z + 2.0) & (np.abs(allb[:, 0]) < 10)]
        if len(s):
            prof.append((round(float(z), 1), round(float(s[:, 1].max()), 3), round(float(s[:, 1].min()), 3)))
    R['base']['profile_z_top_bottom'] = prof
    # 开盖凹口：前沿中段顶面的高度 vs 两侧
    fr = base[base[:, 2] > R['base']['front'] - 0.6]
    bins = []
    for x in np.arange(-6, 6.01, 0.5):
        s = fr[np.abs(fr[:, 0] - x) < 0.25]
        if len(s):
            bins.append((round(float(x), 1), round(float(s[:, 1].max()), 3), round(float(s[:, 2].max()), 3)))
    R['base']['front_edge_x_top_z'] = bins

    act = V(d, m['active'])
    u, lean = lid_frame(act)
    origin = np.array([act[:, 1].min(), act[act[:, 1] < act[:, 1].min() + 0.01][:, 2].mean()])
    R['lid_lean_deg'] = lean
    R['lid_open_deg'] = 90 + lean
    for k in ['active', 'glass', 'lid', 'chin', 'hinge', 'inner']:
        if k not in m:
            continue
        p = to_lid(V(d, m[k]), u, origin)
        e = dict(w=float(np.ptp(p[:, 0])), s0=float(p[:, 1].min()), s1=float(p[:, 1].max()), n0=float(p[:, 2].min()), n1=float(p[:, 2].max()))
        if k in ('lid', 'glass', 'active'):
            e['corner_top'] = corner(p[:, [0, 1]], 1, 1)
            e['corner_bottom'] = corner(p[:, [0, 1]], 1, -1)
        R[k] = e
    if m.get('notch'):
        p = to_lid(act, u, origin)
        top = p[:, 1].max()
        dip = p[(p[:, 1] < top - 0.05) & (np.abs(p[:, 0]) < 2.0) & (p[:, 1] > top - 0.6)]
        R['notch'] = dict(w=float(np.ptp(dip[:, 0])) if len(dip) else None, depth=float(top - dip[:, 1].min()) if len(dip) else None, n=len(dip))
    # 铰链：原点（显示区下沿）在世界坐标，以及铰链网格中心
    hg = V(d, m['hinge'])
    R['hinge_world'] = dict(y=float(hg[:, 1].mean()), z=float(hg[:, 2].mean()), w=float(np.ptp(hg[:, 0])), dia=float(np.ptp(hg[:, 1])))
    R['active_bottom_world'] = dict(y=float(origin[0]), z=float(origin[1]))

    kc = V(d, m['keycaps'])
    ks = keys(kc, np.fromfile(f'{ROOT}/{d}/i_{m["keycaps"]}.u32', dtype=np.uint32).astype(np.int64))
    R['keycaps'] = dict(n=len(ks), w=float(np.ptp(kc[:, 0])), depth=float(np.ptp(kc[:, 2])), x0=float(kc[:, 0].min()), z0=float(kc[:, 2].min()), z1=float(kc[:, 2].max()), ytop=float(kc[:, 1].max()))
    rows = rows_of(ks)
    R['key_rows'] = [[(round(k['x0'], 3), round(k['x1'], 3), round(k['z0'], 3), round(k['z1'], 3)) for k in r] for r in rows]
    # 一颗字母键的圆角
    letter = [k for k in ks if 1.4 < k['x1'] - k['x0'] < 1.7 and 1.4 < k['z1'] - k['z0'] < 1.7]
    if letter:
        k = letter[len(letter) // 2]
        q = kc[(kc[:, 0] >= k['x0'] - 1e-4) & (kc[:, 0] <= k['x1'] + 1e-4) & (kc[:, 2] >= k['z0'] - 1e-4) & (kc[:, 2] <= k['z1'] + 1e-4)]
        R['letter_key'] = dict(w=k['x1'] - k['x0'], d=k['z1'] - k['z0'], corner=corner(q[:, [0, 2]], 1, 1), height=float(np.ptp(q[:, 1])))
    well = V(d, m['well'])
    R['well'] = dict(w=float(np.ptp(well[:, 0])), z0=float(well[:, 2].min()), z1=float(well[:, 2].max()), corner=corner(well[:, [0, 2]], 1, 1))
    tp = V(d, m['pad'])
    R['pad'] = dict(w=float(np.ptp(tp[:, 0])), z0=float(tp[:, 2].min()), z1=float(tp[:, 2].max()), corner=corner(tp[:, [0, 2]], 1, 1))
    return R


NEO = dict(base='IYjUsjnVPLevabB', bottom=['AHewMMzHKsIFykK', 'ubZKAAJmPSUZVHj'], feet='JcBLefbhAcSFtfV', active='rvnQqsVlUxgRHpf',
           glass='iGKSuTNlIlEGpLp', lid='LTxTFlhLWoHyhvo', chin='LlJbyrEiirReHbD', hinge='uNhUfzsDZIJkbzT', inner='LUMtYvTEVNmTHoQ',
           keycaps='AqcQCwqkepkmIxJ', well='RGLDQJKTekftnoB', pad='TJrncXRMBNoKueV')
AIR = dict(base='XqeRgCAwdOOhsbZ', bottom=['HxUKIIujZnaJxkY'], feet='HHSbgccZelReeDP', active='OQzaQDtbMVhhlAr',
           glass='awCetlAgwzdhTcS', lid='coYTbBAwZivAZjX', chin='DSEIYMJUmJHpioT', hinge='vaBhpNllfchyjsq', inner='mwMOgOJFeLwwRrb',
           keycaps='zzYGGBkSUWTdyUk', well='XuEaiEYyDrTRLJC', pad='tPJiWzJmqJeHzUX', notch=True)


def clean(o):
    if isinstance(o, dict):
        return {k: clean(v) for k, v in o.items()}
    if isinstance(o, (list, tuple)):
        return [clean(v) for v in o]
    if isinstance(o, (float, np.floating)):
        return round(float(o), 3)
    if isinstance(o, np.integer):
        return int(o)
    return o


res = dict(neo=machine('vneo', NEO), air=machine('vair', AIR))
json.dump(clean(res), open(f'{ROOT}/measured.json', 'w'), ensure_ascii=False, indent=1)
for k in ('neo', 'air'):
    r = clean(res[k])
    rows = r.pop('key_rows')
    print(k, json.dumps(r, ensure_ascii=False))
    print(' rows:', [len(x) for x in rows])
