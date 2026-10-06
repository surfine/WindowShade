// 直接解析 GLB 的二進位 JSON chunk，用 accessor 的 min/max 算每顆 mesh 的世界外框。
// 不透過 three.js，免得 node 端沒有 Image 載不了貼圖。
import { readFileSync } from 'node:fs';

const file = process.argv[2] ?? 'public/mesh/iphone-18-pro.glb';
const buf = readFileSync(file);
if (buf.readUInt32LE(0) !== 0x46546c67) throw new Error('不是 GLB');
let off = 12, json = null, bin = null;
while (off < buf.length) {
  const len = buf.readUInt32LE(off), type = buf.readUInt32LE(off + 4);
  const data = buf.subarray(off + 8, off + 8 + len);
  if (type === 0x4e4f534a) json = JSON.parse(data.toString('utf8'));
  else if (type === 0x004e4942) bin = data;
  off += 8 + len + ((4 - (len % 4)) % 4);
}
const g = json;

// --- 4x4 矩陣工具（column-major，跟 glTF 一致）---
const I = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
const mul = (a, b) => {
  const o = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) { let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k]; o[c * 4 + r] = s; }
  return o;
};
const trs = (n) => {
  if (n.matrix) return n.matrix.slice();
  const [tx, ty, tz] = n.translation ?? [0, 0, 0];
  const [qx, qy, qz, qw] = n.rotation ?? [0, 0, 0, 1];
  const [sx, sy, sz] = n.scale ?? [1, 1, 1];
  const x2 = qx + qx, y2 = qy + qy, z2 = qz + qz;
  const xx = qx * x2, xy = qx * y2, xz = qx * z2, yy = qy * y2, yz = qy * z2, zz = qz * z2;
  const wx = qw * x2, wy = qw * y2, wz = qw * z2;
  return [
    (1 - (yy + zz)) * sx, (xy + wz) * sx, (xz - wy) * sx, 0,
    (xy - wz) * sy, (1 - (xx + zz)) * sy, (yz + wx) * sy, 0,
    (xz + wy) * sz, (yz - wx) * sz, (1 - (xx + yy)) * sz, 0,
    tx, ty, tz, 1,
  ];
};
const xform = (m, p) => [
  m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
  m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
  m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14],
];

// --- 走訪 ---
const rows = [];
const named = new Map();
function walk(idx, parent, depth) {
  const n = g.nodes[idx];
  const world = mul(parent, trs(n));
  if (n.mesh !== undefined) {
    const mesh = g.meshes[n.mesh];
    let mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
    let tris = 0;
    for (const prim of mesh.primitives) {
      const acc = g.accessors[prim.attributes.POSITION];
      if (prim.indices !== undefined) tris += g.accessors[prim.indices].count / 3;
      // accessor min/max 是 8 個角就夠了
      for (const xs of [acc.min[0], acc.max[0]]) for (const ys of [acc.min[1], acc.max[1]]) for (const zs of [acc.min[2], acc.max[2]]) {
        const p = xform(world, [xs, ys, zs]);
        for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], p[k]); mx[k] = Math.max(mx[k], p[k]); }
      }
    }
    rows.push({ name: n.name ?? mesh.name ?? `node${idx}`, idx, depth, mn, mx, w: mx[0] - mn[0], h: mx[1] - mn[1], d: mx[2] - mn[2], tris });
    named.set(n.name ?? `node${idx}`, rows[rows.length - 1]);
  }
  for (const c of n.children ?? []) walk(c, world, depth + 1);
}
for (const rootIdx of g.scenes[g.scene ?? 0].nodes) walk(rootIdx, I, 0);

const mm = (v) => (v * 1000).toFixed(2).padStart(9);
rows.sort((a, b) => b.w * b.h - a.w * a.h);
console.log('=== iPhone GLB：世界座標外框（mm），按正面面積排序 ===');
console.log(`${'node name'.padEnd(20)} ${'idx'.padStart(5)} ${'W'.padStart(9)} ${'H'.padStart(9)} ${'D'.padStart(9)} ${'x'.padStart(9)} ${'y'.padStart(9)} ${'z'.padStart(9)}`);
for (const r of rows.slice(0, 26)) {
  console.log(`${r.name.padEnd(20)} ${String(r.idx).padStart(5)} ${mm(r.w)} ${mm(r.h)} ${mm(r.d)} ${mm(r.mn[0])} ${mm(r.mn[1])} ${mm(r.mn[2])}  tris=${Math.round(r.tris)}`);
}
const allMn = [0, 1, 2].map((k) => Math.min(...rows.map((r) => r.mn[k])));
const allMx = [0, 1, 2].map((k) => Math.max(...rows.map((r) => r.mx[k])));
console.log('\n整體外框 (mm):', `W=${mm(allMx[0] - allMn[0])}`, `H=${mm(allMx[1] - allMn[1])}`, `D=${mm(allMx[2] - allMn[2])}`);
console.log('整體 x:', mm(allMn[0]), '..', mm(allMx[0]));
console.log('整體 y:', mm(allMn[1]), '..', mm(allMx[1]));
console.log('整體 z:', mm(allMn[2]), '..', mm(allMx[2]));

console.log('\n=== 指定的幾個節點 ===');
for (const nm of process.argv.slice(3)) {
  const r = named.get(nm);
  if (!r) { console.log(`${nm}: 找不到（或不是 mesh）`); continue; }
  console.log(`${nm}: node ${r.idx}  W=${mm(r.w)} H=${mm(r.h)} D=${mm(r.d)}  x=${mm(r.mn[0])}..${mm(r.mx[0])} y=${mm(r.mn[1])}..${mm(r.mx[1])} z=${mm(r.mn[2])}..${mm(r.mx[2])}`);
}
