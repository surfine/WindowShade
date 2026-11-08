// 屏幕平面在世界里的位置（从 glb 的显示网格量出来），相机位姿，以及把整块屏幕网页贴上去的投影矩阵。
// 显示网格 IcBMnlsGrUWaSql（macbook-air-15in-midnight.glb）：下沿 y 0.01352 z −0.12489，上沿 y 0.21163 z −0.197，
// 左右 ±0.16298 m。1710×1107 pt 铺满这块面。
import * as THREE from 'three';
import { mix } from './motion';
import { type Cam } from './plan';

export const W = 1920, H = 1080, FOV = 30;
const TL = new THREE.Vector3(-0.16298, 0.21163, -0.197);
const RIGHT = new THREE.Vector3(0.32596 / 1710, 0, 0);
const DOWN = new THREE.Vector3(0, (0.01352 - 0.21163) / 1107, (-0.12489 + 0.197) / 1107);
export const SCREEN_UP = DOWN.clone().normalize().negate();
export const SCREEN_N = new THREE.Vector3(1, 0, 0).cross(SCREEN_UP).normalize(); // 朝向观众
const M_PER_PT = 0.32596 / 1710;
const TAN = Math.tan(((FOV / 2) * Math.PI) / 180);

export const ptToWorld = (x: number, y: number) => TL.clone().addScaledVector(RIGHT, x).addScaledVector(DOWN, y);
/** s（px/pt）对应的相机到屏幕距离。 */
export const distFor = (s: number) => (M_PER_PT * H) / (2 * TAN * s);

/** 片尾两台并排：Neo 在左后方，略转向镜头。 */
export const NEO_POS: [number, number, number] = [-0.6, 0, -0.22];
export const NEO_ROT = 0.2;
const FINAL = { aim: new THREE.Vector3(-0.29, 0.09, -0.19), dist: 1.4, elev: 13, yaw: 7 };

export type Pose = { pos: THREE.Vector3; aim: THREE.Vector3; up: THREE.Vector3 };
export function pose(c: Cam, q: number): Pose {
  const aim0 = ptToWorld(c.ax, c.ay);
  const d0 = distFor(c.s);
  if (q <= 0) return { aim: aim0, pos: aim0.clone().addScaledVector(SCREEN_N, d0), up: SCREEN_UP.clone() };
  const el = (FINAL.elev * Math.PI) / 180, yw = (FINAL.yaw * Math.PI) / 180;
  const dirF = new THREE.Vector3(Math.sin(yw) * Math.cos(el), Math.sin(el), Math.cos(yw) * Math.cos(el));
  // 先退后、再转向：距离走得比方向快，Neo 进画时已经在远处，不会贴着画面左缘扫进来。
  const qd = 1 - (1 - q) * (1 - q);
  const dir = SCREEN_N.clone().lerp(dirF, q * q * (3 - 2 * q)).normalize();
  const dist = Math.exp(mix(Math.log(d0), Math.log(FINAL.dist), qd));
  const aim = aim0.clone().lerp(FINAL.aim, q);
  const up = SCREEN_UP.clone().lerp(new THREE.Vector3(0, 1, 0), q).normalize();
  return { aim, pos: aim.clone().addScaledVector(dir, dist), up };
}

export function camera(p: Pose) {
  const cam = new THREE.PerspectiveCamera(FOV, W / H, 0.01, 50);
  cam.position.copy(p.pos);
  cam.up.copy(p.up);
  cam.lookAt(p.aim);
  cam.updateMatrixWorld(true);
  cam.updateProjectionMatrix();
  return cam;
}

/** 世界点 → 画面像素。 */
export function project(cam: THREE.PerspectiveCamera, v: THREE.Vector3): [number, number] {
  const n = v.clone().project(cam);
  return [((n.x + 1) / 2) * W, ((1 - n.y) / 2) * H];
}

/** 把 (0,0)–(w,h) 的网页贴到屏幕四角的投影上。正对屏幕时是纯仿射，用 2D matrix，文字按最终尺寸栅格化。 */
export function screenTransform(cam: THREE.PerspectiveCamera, w: number, h: number): string {
  const q = [ptToWorld(0, 0), ptToWorld(1710, 0), ptToWorld(1710, 1107), ptToWorld(0, 1107)].map((v) => project(cam, v));
  const [x0, y0] = q[0], [x1, y1] = q[1], [x2, y2] = q[2], [x3, y3] = q[3];
  const dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3;
  const dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3;
  let a, b, c, d, e, f, g, hh;
  if (Math.abs(dx3) < 1e-6 && Math.abs(dy3) < 1e-6) {
    a = x1 - x0; b = x3 - x0; c = x0; d = y1 - y0; e = y3 - y0; f = y0; g = 0; hh = 0;
  } else {
    const det = dx1 * dy2 - dx2 * dy1;
    g = (dx3 * dy2 - dx2 * dy3) / det;
    hh = (dx1 * dy3 - dx3 * dy1) / det;
    a = x1 - x0 + g * x1; b = x3 - x0 + hh * x3; c = x0;
    d = y1 - y0 + g * y1; e = y3 - y0 + hh * y3; f = y0;
  }
  const A = a / w, B = b / h, D = d / w, Ee = e / h, G = g / w, Hh = hh / h;
  const n = (x: number) => x.toFixed(9);
  if (Math.abs(G) * w + Math.abs(Hh) * h < 1e-5) return `matrix(${n(A)},${n(D)},${n(B)},${n(Ee)},${n(c)},${n(f)})`;
  return `matrix3d(${n(A)},${n(D)},0,${n(G)},${n(B)},${n(Ee)},0,${n(Hh)},0,0,1,0,${n(c)},${n(f)},0,1)`;
}
