// 印出 iPhone GLB 的節點樹（含 group），每棵子樹的世界外框。用來確定
// 「哪一份殼屬於哪一支手機」「程式藏掉的那個節點到底是哪一支」。
import { readFileSync } from 'node:fs';

const file = process.argv[2] ?? 'public/mesh/iphone-18-pro.glb';
const target = process.argv[3] ? Number(process.argv[3]) : null;
const buf = readFileSync(file);
let off = 12, g = null;
while (off < buf.length) {
  const len = buf.readUInt32LE(off), type = buf.readUInt32LE(off + 4);
  if (type === 0x4e4f534a) g = JSON.parse(buf.subarray(off + 8, off + 8 + len).toString('utf8'));
  off += 8 + len + ((4 - (len % 4)) % 4);
}
const I = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
const mul = (a, b) => { const o = new Array(16).fill(0); for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) { let s = 0; for (let k = 0; k < 4; k++) s += a[k * 4 + r] * b[c * 4 + k]; o[c * 4 + r] = s; } return o; };
const trs = (n) => {
  if (n.matrix) return n.matrix.slice();
  const [tx, ty, tz] = n.translation ?? [0, 0, 0];
  const [qx, qy, qz, qw] = n.rotation ?? [0, 0, 0, 1];
  const [sx, sy, sz] = n.scale ?? [1, 1, 1];
  const x2 = qx + qx, y2 = qy + qy, z2 = qz + qz;
  const xx = qx * x2, xy = qx * y2, xz = qx * z2, yy = qy * y2, yz = qy * z2, zz = qz * z2;
  const wx = qw * x2, wy = qw * y2, wz = qw * z2;
  return [(1 - (yy + zz)) * sx, (xy + wz) * sx, (xz - wy) * sx, 0, (xy - wz) * sy, (1 - (xx + zz)) * sy, (yz + wx) * sy, 0, (xz + wy) * sz, (yz - wx) * sz, (1 - (xx + yy)) * sz, 0, tx, ty, tz, 1];
};
const xf = (m, p) => [m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12], m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13], m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]];

// 先算每個 node 子樹的外框
const box = new Map();
function computeBox(idx, parent) {
  const n = g.nodes[idx];
  const world = mul(parent, trs(n));
  let mn = [Infinity, Infinity, Infinity], mx = [-Infinity, -Infinity, -Infinity];
  if (n.mesh !== undefined) {
    for (const prim of g.meshes[n.mesh].primitives) {
      const a = g.accessors[prim.attributes.POSITION];
      for (const xs of [a.min[0], a.max[0]]) for (const ys of [a.min[1], a.max[1]]) for (const zs of [a.min[2], a.max[2]]) {
        const p = xf(world, [xs, ys, zs]);
        for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], p[k]); mx[k] = Math.max(mx[k], p[k]); }
      }
    }
  }
  for (const c of n.children ?? []) {
    computeBox(c, world);
    const cb = box.get(c);
    for (let k = 0; k < 3; k++) { mn[k] = Math.min(mn[k], cb.mn[k]); mx[k] = Math.max(mx[k], cb.mx[k]); }
  }
  box.set(idx, { mn, mx });
}
for (const r of g.scenes[g.scene ?? 0].nodes) computeBox(r, I);

const mm = (v) => (v * 1000).toFixed(1).padStart(8);
function walk(idx, depth) {
  const n = g.nodes[idx];
  const b = box.get(idx);
  const w = b.mx[0] - b.mn[0], h = b.mx[1] - b.mn[1], d = b.mx[2] - b.mn[2];
  const isMesh = n.mesh !== undefined;
  const tris = isMesh ? g.meshes[n.mesh].primitives.reduce((s, p) => s + (p.indices !== undefined ? g.accessors[p.indices].count / 3 : 0), 0) : 0;
  if (depth <= 4 || isMesh) {
    console.log(`${'  '.repeat(depth)}#${String(idx).padStart(3)} ${(n.name ?? '').padEnd(20)} ${isMesh ? 'MESH' : 'grp '} W${mm(w)} H${mm(h)} D${mm(d)}  x${mm(b.mn[0])}..${mm(b.mx[0])} z${mm(b.mn[2])}..${mm(b.mx[2])}${isMesh ? ` tris=${Math.round(tris)}` : ''}`);
  }
  for (const c of n.children ?? []) walk(c, depth + 1);
}
if (target !== null) {
  // 只印到 target 那條路徑
  const path = [];
  (function find(idx) { const n = g.nodes[idx]; path.push(idx); if (idx === target) return true; for (const c of n.children ?? []) if (find(c)) return true; path.pop(); return false; })(g.scenes[0].nodes[0]);
  for (const i of path) {
    const n = g.nodes[i]; const b = box.get(i);
    console.log(`#${String(i).padStart(3)} ${(n.name ?? '').padEnd(22)} children=[${(n.children ?? []).join(', ')}] W${mm(b.mx[0] - b.mn[0])} H${mm(b.mx[1] - b.mn[1])} D${mm(b.mx[2] - b.mn[2])} x${mm(b.mn[0])}..${mm(b.mx[0])} z${mm(b.mn[2])}..${mm(b.mx[2])}`);
  }
} else {
  walk(g.scenes[g.scene ?? 0].nodes[0], 0);
}
