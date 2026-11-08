"""把 measured.json + keys.json 写成 src/future/film/measured.ts（键位、键盘区、触控板……全部厘米）。"""
import json
import sys

M = json.load(open('/tmp/gg/usdz/measured.json'))
K = json.load(open('/tmp/gg/usdz/keys.json'))
OUT = sys.argv[1]

# 世界坐标里键帽整体的范围（SceneKit 读出来的，套过节点变换）
WORLD = {'neo': dict(x0=-13.617, x1=13.617, z0=-9.313, z1=1.567), 'air': dict(x0=-13.614, x1=13.614, z0=-9.364, z1=1.486)}
BACK = {'neo': M['neo']['base']['back'], 'air': M['air']['base']['back']}
TOUCH = {'neo': (11.969, 13.617, -9.313, -7.708), 'air': (11.968, 13.614, -9.364, -7.764)}

LABELS = [
    ['esc'] + [f'F{i}' for i in range(1, 13)],
    ['~\n`', '!\n1', '@\n2', '#\n3', '$\n4', '%\n5', '^\n6', '&\n7', '*\n8', '(\n9', ')\n0', '_\n-', '+\n=', 'delete'],
    ['tab', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{\n[', '}\n]', '|\n\\'],
    ['中/英', 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':\n;', '"\n\'', 'return'],
    ['', ''],
    ['shift', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<\n,', '>\n.', '?\n/', 'shift'],
    ['fn', 'control', 'option', 'command', '', 'command', 'option', '◀', '▲', '▼', '▶'],
]


def keyset(m):
    rows = K[m]
    allk = [k for r in rows for k in r]
    px0 = min(k['x0'] for k in allk); px1 = max(k['x1'] for k in allk)
    pz0 = min(k['z0'] for k in allk); pz1 = max(k['z1'] for k in allk)
    w = WORLD[m]
    sx = (w['x1'] - w['x0']) / (px1 - px0); sz = (w['z1'] - w['z0']) / (pz1 - pz0)
    X = lambda x: w['x0'] + (x - px0) * sx
    Z = lambda z: w['z0'] + (z - pz0) * sz - BACK[m]
    out = []
    for ri, r in enumerate(rows):
        if ri == 6:
            r = sorted(r, key=lambda k: (round(k['x0'], 1), k['z0']))
        labels = LABELS[ri]
        assert len(labels) == len(r), (m, ri, len(r), len(labels))
        for k, lab in zip(r, labels):
            kind = 'bump' if ri == 4 else ('mod' if len(lab) > 2 and '\n' not in lab and lab not in ('esc',) and not lab.startswith('F') else 'key')
            out.append((round(X(k['x0']), 3), round(Z(k['z0']), 3), round((k['x1'] - k['x0']) * sx, 3), round((k['z1'] - k['z0']) * sz, 3), lab, kind, round(k['r'], 3)))
    t = TOUCH[m]
    out.append((t[0], round(t[2] - BACK[m], 3), round(t[1] - t[0], 3), round(t[3] - t[2], 3), '', 'touch', out[1][6]))
    return out


lines = [
    '// 由 src/future/measure/gen_ts.py 生成，别手改。单位厘米。',
    '// 来源：Apple 的 AR 模型（Y 向上，metersPerUnit 0.01），用 measure/dump.swift + measure/keys.py 量出：',
    '//   Neo   https://www.apple.com/105/media/us/macbook-neo/2026/eee281c9-06d4-45d9-9a37-ef16ad413279/ar/macbook-neo.usdz',
    '//         （与 AI System 6 assets/cmf/macbook-neo-open.usdz 同一套网格）',
    '//   Air   https://www.apple.com/105/media/us/macbook-air/2025/0833fe28-c438-4dc4-8edc-e39ef30df5f9/ar/macbook-air-15in-silver.usdz',
    '//         （午夜色同目录 macbook-air-15in-midnight.usdz，只取颜色）',
    '// 键：[左沿离中线 x, 上沿离底座后沿 z, 宽, 深, 字, 类别, 顶面圆角]。',
    '',
    "export type KeyCap = readonly [number, number, number, number, string, 'key' | 'mod' | 'bump' | 'touch', number];",
    '',
]
for m in ('neo', 'air'):
    ks = keyset(m)
    lines.append(f'export const KEYS_{m.upper()}: readonly KeyCap[] = [')
    for k in ks:
        lines.append(f'  [{k[0]}, {k[1]}, {k[2]}, {k[3]}, {json.dumps(k[4], ensure_ascii=False)}, \'{k[5]}\', {k[6]}],')
    lines.append('];')
    lines.append('')
open(OUT, 'w').write('\n'.join(lines))
print('keys', {m: len(keyset(m)) for m in ('neo', 'air')})
