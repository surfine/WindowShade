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

/** 機蓋外殼（機背那一片鋁殼）。鏡頭只看正面，唯一掃到它的是機蓋上緣的掠射角：
 *  天花板燈把它打成一片亮灰（實測 198），貼著黑顯示面就是一道路邊的灰縫。
 *  午夜色本來就深，這裡壓暗，上緣就併進黑邊框。 */
function darkShell(mesh: THREE.Mesh) {
  const list = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
  const next = list.map((mat) => {
    const src = mat as THREE.MeshStandardMaterial;
    if (!('color' in src)) return mat;
    const copy = src.clone();
    copy.color.multiplyScalar(0.16);
    copy.metalness = 0.85;
    copy.roughness = 0.52;
    copy.envMapIntensity = 0.45;
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
    const src = mat as THREE.MeshStandardMaterial;
    if (!('color' in src)) return mat;
    const copy = src.clone();
    const usd = USD_DIFFUSE[src.name];
    if (usd) copy.color.setRGB(usd[0], usd[1], usd[2], THREE.LinearSRGBColorSpace);
    const d = (c: THREE.Color) => Math.abs(copy.color.r - c.r) + Math.abs(copy.color.g - c.g) + Math.abs(copy.color.b - c.b);
    if (d(keys) < 0.03) {
      copy.metalness = 0.05;
      copy.roughness = 0.62;
    } else if (d(deck) < 0.05) {
      copy.metalness = 1;
      copy.roughness = 0.3;
    } else if (copy.metalness >= 0.5) {
      copy.roughness = Math.min(copy.roughness, 0.38);
    } else {
      copy.roughness = Math.min(copy.roughness, 0.72);
    }
    copy.envMapIntensity = 1;
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

function Laptop({ m, texture, x }: { m: MachineId; texture: THREE.Texture | null; x: number }) {
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
  const grad = g.createRadialGradient(120, 150, 30, 200, 330, 620);
  grad.addColorStop(0, '#1b3a63');
  grad.addColorStop(0.5, '#0b1626');
  grad.addColorStop(1, '#05070b');
  g.fillStyle = grad;
  g.fillRect(0, 0, PHONE_CARD.w, PHONE_CARD.h);
  // 狀態列：只有時間。
  g.fillStyle = 'rgba(255,255,255,.92)';
  g.textAlign = 'left';
  g.font = '600 21px "SF Pro Text", "PingFang SC", sans-serif';
  g.fillText(lock ? '9:41' : '21:41', 40, 56);
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
  if (f >= 1760 && f < 2260) {
    const food = f >= 2000;
    return { dx: -0.23, title: food ? '外卖到了' : '车快到了', sub: food ? '放到门口' : '2 分钟', lock: false };
  }
  if (f >= 2880 && f < 3290) {
    const t = Math.max(0, Math.min(1, (f - 2980) / 180));
    const away = t * t * (3 - 2 * t);
    return { dx: -0.22 - away * 0.28, title: '', sub: '', lock: true };
  }
  return null;
}

/** Apple 的 iPhone 18 Pro AR 模型（e-sim 版）。實測（模型自己的座標，公尺）：
 *  正面那支的螢幕面在 z = +0.004，中心 x = −0.0145、y = +0.007，面板 0.073 × 0.158。
 *  這個檔裡有兩支手機（正面與背面），節點名帶 .001 的是背面那支，不畫。 */
const PHONE_MESH = 'mesh/iphone-18-pro.glb';
/** 官方轉出來的 glb 裡，同一個機身有兩份殼（前後各一），這一份是背向的。 */
const PHONE_BACK_SIDE = 'UBGArkKGrAMRRnj';
const PHONE_FACE = { x: -0.0145, y: 0.007, z: 0.004, w: 0.073, h: 0.158 };

function Phone({ f }: { f: number }) {
  const spec = phoneAt(f);
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
        const src = mat as THREE.MeshStandardMaterial;
        const copy = src.clone();
        // 螢幕那一層不自己發光（它本來是給 AR 用的白），內容由上面那塊板畫。
        if (copy.emissive && copy.emissive.r + copy.emissive.g + copy.emissive.b > 0.5) copy.emissive.setRGB(0, 0, 0);
        if (copy.metalness >= 0.5) copy.roughness = Math.min(copy.roughness, 0.38);
        copy.envMapIntensity = 1;
        copy.needsUpdate = true;
        return copy;
      });
      mesh.material = Array.isArray(mesh.material) ? out : out[0];
    });
    return next;
  }, [gltf]);
  if (!spec) return null;
  return (
    <group position={[SEAT.air + spec.dx, 0.15, -0.062]} rotation={[0.1, 0.42, 0]}>
      <group position={[-PHONE_FACE.x, -PHONE_FACE.y, -PHONE_FACE.z]}>
        <primitive object={scene} />
      </group>
      <mesh position={[0, 0, 0.0004]}>
        <planeGeometry args={[PHONE_FACE.w, PHONE_FACE.h]} />
        <meshBasicMaterial map={tex} toneMapped={false} />
      </mesh>
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
  const pmrem = new THREE.PMREMGenerator(gl);
  const env = pmrem.fromScene(s, 0.02, 0.1, 40).texture;
  pmrem.dispose();
  return env;
}

function Studio() {
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
