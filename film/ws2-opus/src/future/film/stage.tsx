// 兩台實機網格在同一個 three.js 場景裡。螢幕畫面貼在各自的顯示網格上。
//
// USDZ → GLB（只換載入格式，不改網格）：Blender 4.5.14
//   /Volumes/Blender/Blender.app/Contents/MacOS/Blender -b -P /tmp/gg/convert_future.py -- \
//     /tmp/gg/usdz/neo-web.usdz public/mesh/macbook-neo.glb
//   /Volumes/Blender/Blender.app/Contents/MacOS/Blender -b -P /tmp/gg/convert_future.py -- \
//     /tmp/gg/usdz/air15-midnight.usdz public/mesh/macbook-air-15in-midnight.glb
// 匯出器：Khronos glTF Blender I/O v4.5.51。import_usd_preview、不合併變換、不減面。
import { useLoader, useThree } from '@react-three/fiber';
import { useLayoutEffect, useMemo, useRef } from 'react';
import { staticFile, useCurrentFrame, useDelayRender } from 'remotion';
import { ThreeCanvas, useOffthreadVideoTexture } from '@remotion/three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import * as THREE from 'three';
import { MACHINES, type MachineId } from './machines';
import { SEAT, shotAt } from './shot';
import { USD_DIFFUSE } from './usdColor';

type V3 = [number, number, number];

const NEO_DISPLAY = 'rvnQqsVlUxgRHpf';
const NEO_GLASS = 'iGKSuTNlIlEGpLp';
const AIR_DISPLAY = 'IcBMnlsGrUWaSql';
const AIR_GLASS = 'XgjLAuVkJXGeLII';
const MESH: Record<MachineId, string> = {
  neo: 'mesh/macbook-neo.glb',
  air: 'mesh/macbook-air-15in-midnight.glb',
};
const NEO_LID_FACE = 'LUMtYvTEVNmTHoQ';
/** 機蓋外殼（機背那一片鋁殼）的網格。名字來自匯入的 glb，用外框尺寸認出來的。 */
const NEO_LID_SHELL = 'LTxTFlhLWoHyhvo';
const AIR_LID_SHELL = 'DfagnPckvlSyqkE';
const AIR_LID_FACE = 'kQLiJXhNjkYSkuM';
const CUTS: Record<MachineId, { display: string; glass: string; face: string; shell: string }> = {
  neo: { display: NEO_DISPLAY, glass: NEO_GLASS, face: NEO_LID_FACE, shell: NEO_LID_SHELL },
  air: { display: AIR_DISPLAY, glass: AIR_GLASS, face: AIR_LID_FACE, shell: AIR_LID_SHELL },
};
// 洞裡的鏡頭、鏡片、小玻璃。藏起來，黑才是一整塊。
// 洞裡的鏡頭、鏡片、小玻璃。藏起來，黑才是一整塊。
const AIR_LENS = new Set(['YqlffYwjhhmumhY', 'fDzEyWEhhOFmtMj', 'oRTVMKHRStYekKU', 'QLPttZezYGCnUHU']);

// 顯示面的 USDZ 帶 0.25 清漆，環境光會把暗色介面抬灰。只關這一面的受光，鍵盤和機身不動。
function unlightDisplay(mesh: THREE.Mesh) {
  const src = mesh.material as THREE.MeshPhysicalMaterial;
  const mat = src.clone();
  mat.color.set(0x000000);
  mat.metalness = 0;
  mat.roughness = 1;
  mat.envMapIntensity = 0;
  mat.clearcoat = 0;
  mat.clearcoatRoughness = 1;
  mat.specularIntensity = 0;
  mat.emissive.set(0xffffff);
  mat.emissiveIntensity = 1;
  mat.map = null;
  mat.emissiveMap = null;
  mat.toneMapped = false;
  mat.needsUpdate = true;
  // 玻璃這回是不透明黑（見下），顯示面落在玻璃後面。關掉深度測試、排在後面畫，
  // 螢幕才會蓋在玻璃上，而不是被玻璃擋掉。
  mat.depthTest = false;
  mesh.material = mat;
  mesh.renderOrder = 2;
}

/** 機蓋正面最外面那一張片（比顯示面大一圈：實測 Neo 29.21×18.71、Air 33.66×22.13 公分，
 *  顯示面各是 27.82×17.43、32.60×21.08）。劉海是從顯示面整片挖掉的（量到洞口 u 0.4412–0.5588、
 *  v 0–0.030），所以洞口與顯示面上緣那一圈露出來的就是這一張片。以前它是陽極鋁的打磨面，
 *  環境光一照就是灰的，對比之下劉海周圍缺一塊（V16-01）。真機這一圈是黑玻璃，這裡直接鋪黑。
 *  顯示面 `depthTest = false`、`renderOrder = 2`，永遠壓在上面；只在顯示面沒有面的地方（洞口、
 *  邊框）才看得到這片黑。 */
function blackGlass(mesh: THREE.Mesh) {
  const mat = new THREE.MeshBasicMaterial({ color: 0x000000, toneMapped: false, side: THREE.DoubleSide });
  mat.depthWrite = true;
  mesh.material = mat;
}

/** 機蓋外殼（機背那一片鋁殼）與機蓋四周那一圈側壁。鏡頭只看正面，掃到它的是機蓋上緣／左右
 *  的掠射角。這一圈是這支片最刺眼的一處破綻：實測整條邊**刷成純白 255**、寬達 33 px、
 *  外緣還是一格一格的鋸齒。原因有兩個，都不是顏色太淺：
 *    1. USDZ 的材質帶 0.25 清漆。清漆那層高光是白色的，跟 baseColor 無關——所以「把顏色乘小」
 *       根本壓不掉它，掠射角照樣整片白。
 *    2. 金屬的回應幾乎全是環境反射。上面的柔光板亮度是 `0xfff1e0 × 7`，乘 0.45 進來還是爆表。
 *  午夜色的邊只該是一道冷灰的暗光，所以這裡不要金屬、不要清漆、環境反射收到最低，
 *  讓它幾乎只剩 baseColor。 */
function darkShell(mesh: THREE.Mesh) {
  const list = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
  const next = list.map((mat) => {
    const src = mat as THREE.MeshPhysicalMaterial;
    if (!('color' in src)) return mat;
    const copy = src.clone();
    copy.color.multiplyScalar(0.22);
    copy.metalness = 0.18;
    copy.roughness = 0.62;
    copy.envMapIntensity = 0.10;
    if ('clearcoat' in copy) {
      copy.clearcoat = 0;
      copy.clearcoatRoughness = 1;
    }
    if ('specularIntensity' in copy) copy.specularIntensity = 0.22;
    if ('map' in copy) copy.map = null;
    copy.needsUpdate = true;
    return copy;
  });
  mesh.material = Array.isArray(mesh.material) ? next : next[0];
}

// 劉海的黑不另外鋪蓋板：挖掉的那塊由機蓋正面那張黑片補上（見上）。貼在顯示面上方補洞的做法
// 會因為兩個面不同平面而在斜看時露邊（舊版 A16-01 的台階就是這樣來的）。

/** 匯入的材質把粗糙度丟了（glTF 省掉的 roughness 就是 1），金屬因此被環境光洗成一整片灰。
 *  照顏色家族把機身、鍵帽各歸一類，補回量到的光澤：機身是陽極鋁，鍵帽是霧面塑膠。 */
function finish(mesh: THREE.Mesh, m: MachineId) {
  const M = MACHINES[m];
  const deck = new THREE.Color(M.color.edge[0] / 255, M.color.edge[1] / 255, M.color.edge[2] / 255).convertSRGBToLinear();
  const keys = new THREE.Color(M.color.keys).convertSRGBToLinear();
  const list = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
  const next = list.map((mat) => {
    const src = mat as THREE.MeshPhysicalMaterial;
    if (!('color' in src)) return mat;
    const copy = src.clone();
    const usd = USD_DIFFUSE[src.name];
    if (usd) copy.color.setRGB(usd[0], usd[1], usd[2], THREE.LinearSRGBColorSpace);
    // USDZ 每張材質都帶 0.25 清漆。清漆高光是白的，掠射角會把機身側壁刷成一條白邊，
    // 跟 baseColor 無關，壓顏色壓不掉——這裡一律關掉，光澤交給 roughness。
    if ('clearcoat' in copy) {
      copy.clearcoat = 0;
      copy.clearcoatRoughness = 1;
    }
    const d = (c: THREE.Color) => Math.abs(copy.color.r - c.r) + Math.abs(copy.color.g - c.g) + Math.abs(copy.color.b - c.b);
    if (d(keys) < 0.03) {
      copy.metalness = 0.05;
      copy.roughness = 0.62;
    } else if (d(deck) < 0.05) {
      // 陽極鋁：有光澤但不是鏡子（roughness 0.3 的鏡面金屬會把柔光板原樣反射成白）。
      copy.metalness = 0.9;
      copy.roughness = 0.42;
    } else if (copy.metalness >= 0.5) {
      copy.roughness = Math.min(Math.max(copy.roughness, 0.34), 0.6);
    } else {
      copy.roughness = Math.min(copy.roughness, 0.72);
    }
    // 環境是「鏡頭看得到的一間房」，反射強度統一收一階：金屬的暗反射與高光都還在，
    // 但不會爆到 255。
    copy.envMapIntensity = 0.65;
    copy.needsUpdate = true;
    return copy;
  });
  mesh.material = Array.isArray(mesh.material) ? next : next[0];
}

function paint(root: THREE.Object3D, m: MachineId) {
  const { display, glass, face, shell } = CUTS[m];
  root.traverse((obj) => {
    const mesh = obj as THREE.Mesh;
    if (!mesh.isMesh) return;
    if (AIR_LENS.has(mesh.name)) {
      mesh.visible = false;
      return;
    }
    if (mesh.name === display) {
      unlightDisplay(mesh);
      return;
    }
    if (mesh.name === glass || mesh.name === face) {
      blackGlass(mesh);
      return;
    }
    if (mesh.name === shell) {
      darkShell(mesh);
      return;
    }
    finish(mesh, m);
  });
}

export function Laptop({ m, texture, x }: { m: MachineId; texture: THREE.Texture | null; x: number }) {
  const { display } = CUTS[m];
  const gltf = useLoader(GLTFLoader, staticFile(MESH[m]));
  const advance = useThree((s) => s.advance);
  const frame = useCurrentFrame();
  const { delayRender, continueRender } = useDelayRender();
  const waiting = useRef<number | null>(null);
  const scene = useMemo(() => {
    const next = gltf.scene.clone(true);
    paint(next, m);
    return next;
  }, [gltf, m]);
  // 貼圖是非同步載入的。先按住這一幀，貼上之後再畫一次，否則快照會拍到白屏。
  useLayoutEffect(() => {
    const handle = delayRender(`screen ${display} ${frame}`);
    waiting.current = handle;
    return () => {
      if (waiting.current !== null) {
        continueRender(waiting.current);
        waiting.current = null;
      }
    };
  }, [frame, display, delayRender, continueRender]);
  useLayoutEffect(() => {
    if (!texture || waiting.current === null) return;
    texture.flipY = false;
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.needsUpdate = true;
    scene.traverse((obj) => {
      const mesh = obj as THREE.Mesh;
      if (!mesh.isMesh || mesh.name !== display) return;
      const mat = mesh.material as THREE.MeshPhysicalMaterial;
      mat.emissiveMap = texture;
      mat.emissive.set(0xffffff);
      mat.emissiveIntensity = 1;
      mat.envMapIntensity = 0;
      mat.clearcoat = 0;
      mat.specularIntensity = 0;
      mat.toneMapped = false;
      mat.needsUpdate = true;
    });
    advance(performance.now());
    continueRender(waiting.current);
    waiting.current = null;
  }, [texture, scene, display, advance, continueRender]);
  return <primitive object={scene} position={[x, 0, 0]} />;
}

/** 手機那塊畫面：符號帶頭、字少。狀態列只有時間，島在正中，活動卡一枚符號加四個字。 */
const PHONE_CARD = { w: 366, h: 792 };

function carGlyph(g: CanvasRenderingContext2D, cx: number, cy: number, s: number, color: string) {
  g.save();
  g.translate(cx, cy);
  g.scale(s, s);
  g.strokeStyle = color;
  g.lineWidth = 1.5;
  g.lineJoin = 'round';
  g.lineCap = 'round';
  g.beginPath();
  g.moveTo(-8, 1.8);
  g.lineTo(-6.6, -2.4);
  g.quadraticCurveTo(-6.2, -3.4, -5, -3.4);
  g.lineTo(5, -3.4);
  g.quadraticCurveTo(6.2, -3.4, 6.6, -2.4);
  g.lineTo(8, 1.8);
  g.closePath();
  g.stroke();
  g.beginPath();
  g.moveTo(-5.9, -2.2);
  g.lineTo(5.9, -2.2);
  g.stroke();
  g.beginPath();
  g.arc(-4.4, 2.4, 1.35, 0, Math.PI * 2);
  g.moveTo(5.75 + 1.35, 2.4);
  g.arc(4.4, 2.4, 1.35, 0, Math.PI * 2);
  g.stroke();
  g.restore();
}

function bagGlyph(g: CanvasRenderingContext2D, cx: number, cy: number, s: number, color: string) {
  g.save();
  g.translate(cx, cy);
  g.scale(s, s);
  g.strokeStyle = color;
  g.lineWidth = 1.5;
  g.lineJoin = 'round';
  g.lineCap = 'round';
  g.beginPath();
  g.moveTo(-6.2, -2.4);
  g.lineTo(6.2, -2.4);
  g.lineTo(4.8, 6.6);
  g.lineTo(-4.8, 6.6);
  g.closePath();
  g.stroke();
  g.beginPath();
  g.arc(0, -4.3, 2.5, Math.PI, 0);
  g.stroke();
  g.restore();
}

function phoneCard(title: string, sub: string, lock: boolean) {
  const c = document.createElement('canvas');
  c.width = PHONE_CARD.w;
  c.height = PHONE_CARD.h;
  const g = c.getContext('2d');
  if (!g) return new THREE.CanvasTexture(c);
  // 先照顯示面的外輪廓裁切，四角才不會露出機身圓角外。
  g.beginPath();
  PHONE_SCREEN_OUTLINE.forEach(([u, v], i) => {
    const x = u * PHONE_CARD.w;
    const y = v * PHONE_CARD.h;
    if (i === 0) g.moveTo(x, y);
    else g.lineTo(x, y);
  });
  g.closePath();
  g.clip();
  const grad = g.createRadialGradient(120, 150, 30, 200, 330, 620);
  grad.addColorStop(0, '#1b3a63');
  grad.addColorStop(0.5, '#0b1626');
  grad.addColorStop(1, '#05070b');
  g.fillStyle = grad;
  g.fillRect(0, 0, PHONE_CARD.w, PHONE_CARD.h);
  // 狀態列：只有時間。片裡的時鐘是 10月4日 21:41，手機也必須同一支錶——
  // 之前鎖屏寫死 9:41（蘋果宣傳稿那個時間），跟 Mac 對不上。
  g.fillStyle = 'rgba(255,255,255,.92)';
  g.textAlign = 'left';
  g.font = '600 21px "SF Pro Text", "PingFang SC", sans-serif';
  g.fillText('21:41', 40, 56);
  // 動態島。
  g.fillStyle = '#000';
  roundRect(g, 118, 24, 130, 38, 19);
  g.fill();
  if (lock) {
    g.textAlign = 'center';
    g.fillStyle = 'rgba(255,255,255,.9)';
    g.font = '600 21px "PingFang SC", sans-serif';
    g.fillText('10月4日 星期日', 183, 160);
    g.font = '700 116px "SF Pro Display", "PingFang SC", sans-serif';
    g.fillStyle = 'rgba(255,255,255,.94)';
    g.fillText(title || '21:41', 183, 280);
  } else {
    g.fillStyle = 'rgba(255,255,255,.14)';
    roundRect(g, 24, 96, 318, 96, 30);
    g.fill();
    g.fillStyle = '#1f2937';
    roundRect(g, 44, 116, 56, 56, 18);
    g.fill();
    if (title === '外卖到了') bagGlyph(g, 72, 144, 1.55, '#ffb340');
    else carGlyph(g, 72, 144, 1.55, '#64D2FF');
    g.textAlign = 'left';
    g.fillStyle = '#fff';
    g.font = '600 30px "PingFang SC", sans-serif';
    g.fillText(title, 116, 142);
    g.fillStyle = 'rgba(255,255,255,.62)';
    g.font = '500 21px "PingFang SC", sans-serif';
    g.fillText(sub, 116, 172);
  }
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.needsUpdate = true;
  return tex;
}

function roundRect(g: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  g.beginPath();
  g.moveTo(x + r, y);
  g.arcTo(x + w, y, x + w, y + h, r);
  g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r);
  g.arcTo(x, y, x + w, y, r);
  g.closePath();
}

function phoneAt(f: number): { dx: number; title: string; sub: string; lock: boolean } | null {
  // 擺位是量出來的，不是猜的。用片子同一套鏡頭數學投影（`shot.ts` 的 shotAt）算過：
  //   dx = -0.12 → 手機正面壓到 Air 顯示區 101–243 px 寬（每一幀都壓），
  //                就是 Aaron 看到的「擋住 MacBook 螢幕」。
  //   dx = -0.18 → 手機落在顯示區左緣之外（f1840 x216–526 vs 螢幕 x651 起；f2960 x454–673
  //                vs 螢幕 x712 起），整台仍在畫內。立在 Air 左前側、不壓螢幕。
  if (f >= 1760 && f < 2260) {
    const food = f >= 2000;
    return { dx: -0.18, title: food ? '外卖到了' : '车快到了', sub: food ? '放到门口' : '2 分钟', lock: false };
  }
  if (f >= 2880 && f < 3290) {
    const t = Math.max(0, Math.min(1, (f - 2980) / 180));
    const away = t * t * (3 - 2 * t);
    // 飄出去的幅度收到 0.10（原本 0.30）：原本走到 -0.42，f2960 就整台飛出畫面左緣
    //（同一個投影：dx = -0.42 時 x0 約 -0.19 幀寬）。收到 -0.28 為止，全程留在畫內。
    return { dx: -0.18 - away * 0.10, title: '', sub: '', lock: true };
  }
  return null;
}

/** Apple 的 iPhone 18 Pro AR 模型（e-sim 版）。實測（模型自己的座標，公尺）：
 *  正面那支的螢幕面在 z = +0.004，中心 x = −0.0145、y = +0.007，面板 0.07279 × 0.15826。
 *  這個檔裡有兩支手機（正面與背面），節點名帶 .001 的是背面那支，不畫。 */
const PHONE_MESH = 'mesh/iphone-18-pro.glb';
/** 官方轉出來的 glb 裡，同一個機身有兩份殼（前後各一），這一份是背向的。 */
const PHONE_BACK_SIDE = 'UBGArkKGrAMRRnj';
const PHONE_FACE = { x: -0.0145, y: 0.007, z: 0.004, w: 0.07279, h: 0.15826 };

/** 真機 iPhone 18 Pro 的鈦邊框約 1.4–1.7 mm。`PHONE_FACE.w = 0.07279 m` 換算下來，
 *  每邊要內縮 1.9%–2.3%（取中值 2.1%，v 方向同比例）。
 *  這一圈不是裝飾：沒內縮，貼圖平面就跟顯示面一樣大，從邊到邊蓋滿整個正面，
 *  邊框零空間——不管打光調多亮，都只是一張貼上去的截圖（Aaron 點出的平面卡片）。 */
const PHONE_BEZEL = 0.021;
/** 貼圖平面與裁切輪廓一起縮的比例（每邊內縮 `PHONE_BEZEL`）。 */
const PHONE_CARD_SCALE = 1 - 2 * PHONE_BEZEL;

/** 螢幕貼圖是一張矩形的畫布，但顯示面是圓角的。以前直接把矩形貼上去，
 *  四個角就從機身的圓角外露出來（Aaron 指出：iPhone 是圓角，卻丟了一張直角的截圖上去）。
 *  這份輪廓取自官方 USDZ 顯示面的凸包，歸一到 0..1、v = 0 在頂端，貼圖照它裁切。
 *  刻意不畫成圓角矩形：Apple 的連續圓角比同半徑的圓弧更「方」，用 `roundRect` 近似會看得出來
 *  （左上角/右上角會少一角）。 */
export const PHONE_SCREEN_OUTLINE: ReadonlyArray<readonly [number, number]> = [
  [0.2209, 0.0], [0.1486, 0.0004], [0.1113, 0.0025], [0.0776, 0.0077],
  [0.0625, 0.0116], [0.0487, 0.0164], [0.0364, 0.022], [0.0259, 0.0283],
  [0.0173, 0.0352], [0.0079, 0.0466], [0.004, 0.0547], [0.0016, 0.0633],
  [0.0005, 0.0723], [0.0, 0.0908], [0.0, 0.9092], [0.0005, 0.9277],
  [0.0026, 0.941], [0.0057, 0.9494], [0.0106, 0.9573], [0.0173, 0.9648],
  [0.0259, 0.9717], [0.0424, 0.9809], [0.0554, 0.9861], [0.0699, 0.9905],
  [0.0939, 0.9953], [0.1295, 0.9989], [0.2197, 1.0], [0.8108, 1.0],
  [0.8705, 0.9989], [0.8975, 0.9965], [0.9144, 0.9939], [0.9375, 0.9884],
  [0.9513, 0.9836], [0.9636, 0.978], [0.9741, 0.9717], [0.9827, 0.9648],
  [0.9921, 0.9534], [0.996, 0.9453], [0.9984, 0.9367], [0.9995, 0.9277],
  [1.0, 0.9092], [1.0, 0.0908], [0.9995, 0.0723], [0.9984, 0.0633],
  [0.996, 0.0547], [0.9921, 0.0466], [0.9863, 0.0389], [0.9787, 0.0316],
  [0.9691, 0.025], [0.9576, 0.0191], [0.9375, 0.0116], [0.9144, 0.0061],
  [0.8797, 0.0017], [0.8415, 0.0002],
];

export function Phone({ f, dxOverride, hideCard, hideBody, debugBody }: { f: number; dxOverride?: number; hideCard?: boolean; hideBody?: boolean; debugBody?: boolean }) {
  const base = phoneAt(f);
  const spec = base && dxOverride !== undefined ? { ...base, dx: dxOverride } : base;
  const gltf = useLoader(GLTFLoader, staticFile(PHONE_MESH));
  const title = spec?.title ?? '';
  const sub = spec?.sub ?? '';
  const lock = spec?.lock ?? false;
  const tex = useMemo(() => phoneCard(title, sub, lock), [title, sub, lock]);
  const scene = useMemo(() => {
    const next = gltf.scene.clone(true);
    // 這個檔裡同一個機身有兩份殼（節點樹各自獨立：`UBGArkKGrAMRRjn` 與 `wUOhcMgiBmCgGaw`），
    // 背向那一份要整棵收掉。以前是照節點名挑 `.001` 收，但兩份殼的名字是交叉的
    // （同一對裡 A 用無後綴、B 用 `.001`），結果兩份都各被切掉一半，畫面上就是一堆飄著的碎片。
    const back = next.getObjectByName(PHONE_BACK_SIDE);
    if (back) back.visible = false;
    next.traverse((obj) => {
      const mesh = obj as THREE.Mesh;
      if (!mesh.isMesh) return;
      const list = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
      const out = list.map((mat) => {
        const src = mat as THREE.MeshPhysicalMaterial;
        const copy = src.clone();
        // 螢幕那一層不自己發光（它本來是給 AR 用的白），內容由上面那塊板畫。
        if (copy.emissive && copy.emissive.r + copy.emissive.g + copy.emissive.b > 0.5) copy.emissive.setRGB(0, 0, 0);
        // 跟機殼同一個病：官方 USDZ 帶清漆、機身又是鏡面金屬，邊框在掠射角整條刷白、
        // 邊緣還硬得像貼紙。清漆關掉、粗糙度補回來、環境反射收一階，邊只剩一道冷灰。
        if ('clearcoat' in copy) {
          copy.clearcoat = 0;
          copy.clearcoatRoughness = 1;
        }
        if (copy.metalness >= 0.5) {
          // 金屬沒有漫反射，顏色全靠反射。原本 rough 0.34–0.55 + envMap 0.62，
          // 這顆環境又是近黑底（#0a0d12）只有幾片燈板，手機的反射方向多半落在黑底上，
          // 整支機身就讀成一塊剪影（Aaron 看到的「平面黑卡片」就是這樣來的）。
          // 收緊粗糙度讓燈板的反射聚成一道形，金屬度降一點讓鈦本身的底色透出來。
          copy.metalness = 0.78;
          copy.roughness = Math.min(Math.max(copy.roughness, 0.26), 0.42);
        }
        if ('specularIntensity' in copy) copy.specularIntensity = Math.min(copy.specularIntensity ?? 1, 0.85);
        copy.envMapIntensity = 1.45;
        copy.needsUpdate = true;
        return copy;
      });
      mesh.material = Array.isArray(mesh.material) ? out : out[0];
    });
    if (debugBody) {
      // 診斷用：整台機身換成法線材質。看得見形狀＝幾何在、只是材質/打光讓它讀不出來。
      next.traverse((obj) => {
        const mesh = obj as THREE.Mesh;
        if (mesh.isMesh) mesh.material = new THREE.MeshNormalMaterial();
      });
    }
    return next;
  }, [gltf, debugBody]);
  if (!spec) return null;
  return (
    // y = 0.084：機身下緣落在筆電底座那一層（桌面 ≈ 0.006 m）。原本 0.095 讓下緣懸空約 11 mm，
    // 讀起來像浮著的一張卡；現在有實際的接觸點。旋轉是俯 0.1 rad + 偏 0.42 rad，才看得到鈦側邊。
    <group position={[SEAT.air + spec.dx, 0.084, -0.038]} rotation={[0.1, 0.42, 0]}>
      {!hideBody && (
        <group position={[-PHONE_FACE.x, -PHONE_FACE.y, -PHONE_FACE.z]}>
          <primitive object={scene} />
        </group>
      )}
      {!hideCard && (
      <mesh position={[0, 0, 0.0004]}>
        {/* 貼圖平面（連它對應的裁切輪廓）每邊內縮 `PHONE_BEZEL`：鈦邊框那一圈才露得出來。
            沒內縮的話貼圖從邊到邊蓋滿整個正面，打光再亮也只是一張貼在機身上的截圖。 */}
        <planeGeometry args={[PHONE_FACE.w * PHONE_CARD_SCALE, PHONE_FACE.h * PHONE_CARD_SCALE]} />
        {/* 畫布四角已是透明（照顯示面輪廓裁切），所以這裡要開透明，讓機身的圓角透出來。 */}
        <meshBasicMaterial map={tex} toneMapped={false} transparent alphaTest={0.02} />
      </mesh>
      )}
    </group>
  );
}

/** 攝影棚：上面一塊大柔光板、左右兩條窄光管、螢幕後面一條矮光帶，其餘近黑。
 *  鋁是鏡面金屬，看到的是環境本身；中性灰房間（`RoomEnvironment`）只會把它洗成一整片灰。
 *  這裡的環境亮暗差得開，機身才有暗反射與乾淨的高光。 */
function studioEnv(gl: THREE.WebGLRenderer) {
  const s = new THREE.Scene();
  s.add(new THREE.Mesh(new THREE.BoxGeometry(12, 12, 12), new THREE.MeshBasicMaterial({ color: 0x0a0d12, side: THREE.BackSide })));
  const panel = (w: number, h: number, color: number, gain: number, pos: V3, rot: V3) => {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(gain), toneMapped: false }));
    m.position.set(pos[0], pos[1], pos[2]);
    m.rotation.set(rot[0], rot[1], rot[2]);
    s.add(m);
  };
  panel(7, 5, 0xfff1e0, 7, [0, 5, 0.8], [Math.PI / 2, 0, 0]); // 柔光板（上）
  panel(0.6, 8, 0xe8f1ff, 9, [-4.6, 1.8, -0.5], [0, Math.PI / 2, 0]); // 左光管
  panel(0.6, 8, 0xe8f1ff, 5, [4.6, 1.8, -0.5], [0, -Math.PI / 2, 0]); // 右光管（弱一階）
  panel(6, 0.5, 0xd6e4ff, 4, [0, 0.7, -5.4], [0, 0, 0]); // 螢幕後面一條：上邊框一道亮帶
  // 前方柔光幕（主要在下半）：手機那一圈鈦邊框與機身正面讀得出來，靠的就是這一塊。
  // 相機在機身上方俯看，金屬正面反射出去的光是往**下前方**走的（把相機方向對正面法線
  // 取鏡射，y 分量是負的）；只留上方那塊柔光板，反射方向落進近黑底，整支就讀成剪影。
  // 位置就是照那個鏡射方向擺、往下壓，讓機身正面（含內縮後露出的邊框）吃到反射。
  panel(9, 4.4, 0xdfe9f5, 1.7, [1.2, -0.6, 3.2], [0, Math.PI, 0]);
  // 邊框高光條：窄窄一條，正對機身右前側。金屬看到的是「有形的亮源」，
  // 這一條在機身左右緣與內縮露出的邊框上拉出一道可讀的亮線，不是一整片灰。
  panel(0.35, 3.0, 0xf2f7ff, 12, [1.85, 0.5, 1.6], [0, -Math.PI / 2, 0]);
  const pmrem = new THREE.PMREMGenerator(gl);
  const env = pmrem.fromScene(s, 0.02, 0.1, 40).texture;
  pmrem.dispose();
  return env;
}

export function Studio() {
  const gl = useThree((s) => s.gl);
  const scene = useThree((s) => s.scene);
  useLayoutEffect(() => {
    const env = studioEnv(gl);
    scene.environment = env;
    return () => {
      env.dispose();
    };
  }, [gl, scene]);
  return (
    <>
      <color attach="background" args={['#12141a']} />
      <ambientLight intensity={0.16} />
      <directionalLight position={[1.6, 3.4, 2.2]} intensity={1.5} />
      <directionalLight position={[-2.4, 1.4, 1.6]} intensity={0.35} />
    </>
  );
}

function Rig({ f }: { f: number }) {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  const pose = shotAt(f);
  camera.fov = pose.fov;
  camera.near = 0.02;
  camera.far = 40;
  camera.position.set(pose.pos[0], pose.pos[1], pose.pos[2]);
  camera.lookAt(pose.aim[0], pose.aim[1], pose.aim[2]);
  camera.updateProjectionMatrix();
  return null;
}

function World({ f }: { f: number }) {
  const neoTex = useOffthreadVideoTexture({ src: staticFile('future/plates/neo.mp4'), toneMapped: false });
  const airTex = useOffthreadVideoTexture({ src: staticFile('future/plates/air.mp4'), toneMapped: false });
  return (
    <>
      <Rig f={f} />
      <Studio />
      <Laptop m="neo" texture={neoTex} x={SEAT.neo} />
      <Laptop m="air" texture={airTex} x={SEAT.air} />
      <Phone f={f} />
    </>
  );
}

export function Stage({ f, W, H }: { f: number; W: number; H: number }) {
  return (
    <ThreeCanvas width={W} height={H} dpr={1} gl={{ antialias: true, toneMapping: THREE.ACESFilmicToneMapping, toneMappingExposure: 1 }} camera={{ fov: 30, near: 0.02, far: 40, position: [0, 0.4, 1] }}>
      <World f={f} />
    </ThreeCanvas>
  );
}
