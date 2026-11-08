// 机身：15 英寸 Air（午夜色）与 Neo 的 glb，材质处理与摄影棚光照照搬 ws2-opus/src/future/film/stage.tsx（draft21），
// 只改两处：Air 的显示面画成纯黑（整块屏幕是叠在上面的网页，见 Film.tsx），Neo 的显示面贴一张静态桌面。
import { useLoader, useThree } from '@react-three/fiber';
import { useLayoutEffect, useMemo } from 'react';
import { staticFile } from 'remotion';
import { ThreeCanvas } from '@remotion/three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import * as THREE from 'three';
import { USD_DIFFUSE } from './usdColor';
import { NEO_POS, NEO_ROT, type Pose } from './rig';

type MachineId = 'neo' | 'air';
type V3 = [number, number, number];
const MACHINES: Record<MachineId, { color: { edge: [number, number, number]; keys: string } }> = {
  neo: { color: { edge: [207, 208, 211], keys: '#f9fbff' } },
  air: { color: { edge: [75, 80, 88], keys: '#17191f' } },
};

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


function Laptop({ m, position, rotationY = 0 }: { m: MachineId; position: V3; rotationY?: number }) {
  const { display } = CUTS[m];
  const gltf = useLoader(GLTFLoader, staticFile(MESH[m]));
  const neoTex = useLoader(THREE.TextureLoader, staticFile('ui/neo-screen.jpg'));
  const scene = useMemo(() => {
    const next = gltf.scene.clone(true);
    paint(next, m);
    next.traverse((obj) => {
      const mesh = obj as THREE.Mesh;
      if (!mesh.isMesh || mesh.name !== display) return;
      const mat = mesh.material as THREE.MeshPhysicalMaterial;
      if (m === 'air') {
        mat.emissive.set(0x000000);
      } else {
        neoTex.flipY = false;
        neoTex.colorSpace = THREE.SRGBColorSpace;
        mat.emissiveMap = neoTex;
        mat.emissive.set(0xffffff);
      }
      mat.needsUpdate = true;
    });
    return next;
  }, [gltf, m, display, neoTex]);
  return <primitive object={scene} position={position} rotation={[0, rotationY, 0]} />;
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

function Rig({ p }: { p: Pose }) {
  const camera = useThree((s) => s.camera) as THREE.PerspectiveCamera;
  camera.fov = 30;
  camera.near = 0.01;
  camera.far = 50;
  camera.position.copy(p.pos);
  camera.up.copy(p.up);
  camera.lookAt(p.aim);
  camera.updateProjectionMatrix();
  return null;
}

export function Stage({ p, neo, W, H }: { p: Pose; neo: boolean; W: number; H: number }) {
  return (
    <ThreeCanvas width={W} height={H} dpr={1} gl={{ antialias: true, toneMapping: THREE.ACESFilmicToneMapping, toneMappingExposure: 1 }} camera={{ fov: 30, near: 0.01, far: 50, position: [0, 0.4, 1] }}>
      <Rig p={p} />
      <Studio />
      <Laptop m="air" position={[0, 0, 0]} />
      {neo ? <Laptop m="neo" position={NEO_POS} rotationY={NEO_ROT} /> : null}
    </ThreeCanvas>
  );
}
