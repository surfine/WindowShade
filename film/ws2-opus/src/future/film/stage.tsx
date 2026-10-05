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
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import * as THREE from 'three';
import { islandAt, islandRect } from './island';
import { HOLE, NOTCH_UV } from './notchPath';
import { SEAT, shotAt } from './shot';
import { USD_DIFFUSE } from './usdColor';

const NEO_DISPLAY = 'rvnQqsVlUxgRHpf';
const NEO_GLASS = 'iGKSuTNlIlEGpLp';
const AIR_DISPLAY = 'IcBMnlsGrUWaSql';
const AIR_GLASS = 'XgjLAuVkJXGeLII';
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
  mesh.material = mat;
  mesh.renderOrder = 2;
}

// 匯入的玻璃片是不透明黑，蓋在畫面前面。透射材質又會把介面洗灰，所以這一片不參與著色。
function hideGlass(mesh: THREE.Mesh) {
  const src = mesh.material as THREE.MeshPhysicalMaterial;
  const mat = src.clone();
  mat.transparent = true;
  mat.opacity = 0;
  mat.depthWrite = false;
  mat.envMapIntensity = 0;
  mat.transmission = 0;
  mat.toneMapped = false;
  mat.needsUpdate = true;
  mesh.material = mat;
}

// 洞裡沒有三角形，後面的鋁被環境光照成灰。用洞自己的 UV 折線鋪一塊黑，蓋住鏡頭。頂邊再伸進邊框，不留一條縫。
function notchCap(display: THREE.Mesh) {
  const pos = display.geometry.getAttribute('position');
  const uv = display.geometry.getAttribute('uv');
  const hit = new THREE.Vector3();
  const outline: { p: THREE.Vector3; v: number }[] = [];
  for (const [u, v] of NOTCH_UV) {
    let best = Infinity;
    for (let i = 0; i < uv.count; i++) {
      const du = uv.getX(i) - u;
      const dv = uv.getY(i) - v;
      const d = du * du + dv * dv;
      if (d < best) {
        best = d;
        hit.fromBufferAttribute(pos, i);
      }
    }
    outline.push({ p: hit.clone(), v });
  }
  if (outline.length < 3) return;
  const c = outline.reduce((s, o) => s.add(o.p), new THREE.Vector3()).multiplyScalar(1 / outline.length);
  const shape = new THREE.Shape();
  outline.forEach((o, i) => {
    const dir = o.p.clone().sub(c);
    const x = c.x + dir.x * 1.012;
    const z = c.z + dir.z * 1.012 - (o.v < 0.004 ? 0.06 : 0);
    if (i === 0) shape.moveTo(x, z);
    else shape.lineTo(x, z);
  });
  shape.closePath();
  const cap = new THREE.Mesh(
    new THREE.ShapeGeometry(shape),
    new THREE.MeshBasicMaterial({ color: 0x000000, toneMapped: false, side: THREE.DoubleSide }),
  );
  cap.name = 'notch-cap';
  cap.rotation.x = Math.PI / 2;
  cap.position.y = Math.max(...outline.map((o) => o.p.y)) + 0.12;
  display.add(cap);

  const xs = outline.map((o) => o.p.x);
  const zs = outline.map((o) => o.p.z);
  const blank = new THREE.Shape();
  blank.moveTo(0, 0);
  blank.lineTo(0.001, 0);
  blank.lineTo(0, 0.001);
  blank.closePath();
  const cover = new THREE.Mesh(
    new THREE.ShapeGeometry(blank),
    new THREE.MeshBasicMaterial({
      color: 0x000000,
      toneMapped: false,
      side: THREE.DoubleSide,
      depthWrite: false,
      depthTest: false,
    }),
  );
  cover.name = 'island-cover';
  cover.rotation.x = Math.PI / 2;
  // 緊貼顯示面。抬太高會因透視顯得比貼圖島更寬，重新長出台階（審片 C10-01）。
  cover.position.y = Math.max(...outline.map((o) => o.p.y)) + 0.08;
  cover.renderOrder = 20;
  cover.frustumCulled = false;
  cover.visible = false;
  // UV 外緣含兩肩；與 grownPill 的 half = max(w/2, HOLE.w/2+rs) 同一套點單位。
  const holeOuter = Math.max(...xs) - Math.min(...xs);
  const holeOuterPt = HOLE.w + 2 * HOLE.rs;
  cover.userData = {
    cx: (Math.min(...xs) + Math.max(...xs)) / 2,
    perPt: holeOuter / holeOuterPt,
    zTop: Math.min(...zs),
    zHoleBot: Math.max(...zs),
    key: '',
  };
  display.add(cover);
}

/** 展開時用與 grownPill 同寬的蓋板蓋住實體洞肩。只蓋洞高，字仍在螢幕貼圖上。 */
function syncCover(root: THREE.Object3D, f: number) {
  const cover = root.getObjectByName('island-cover') as THREE.Mesh | undefined;
  const cap = root.getObjectByName('notch-cap') as THREE.Mesh | undefined;
  if (!cover) return;
  const meta = cover.userData as { cx: number; perPt: number; zTop: number; zHoleBot: number; key: string };
  const rect = islandRect('air', f);
  const name = islandAt(f).name;
  // 長高的展開態蓋住實體洞。tick 用左右翼排字，不加蓋板（避免橫條台階）。
  const grown = name === 'alert' || name === 'share' || name === 'row' || name === 'face';
  cover.visible = grown;
  if (cap) cap.visible = !grown;
  if (!grown || !(meta.perPt > 0)) return;
  // 與 notchPath.grownPill 同一半寬；再收一點抵消蓋板略高出顯示面時的透視放大。
  const halfPt = Math.max(rect.w / 2, HOLE.w / 2 + HOLE.rs);
  const half = halfPt * meta.perPt * 0.93;
  const z0 = meta.zTop;
  const z1 = meta.zHoleBot;
  const key = `${half.toFixed(3)}:${z0.toFixed(3)}:${z1.toFixed(3)}`;
  if (meta.key === key) return;
  meta.key = key;
  const shape = new THREE.Shape();
  shape.moveTo(meta.cx - half, z0);
  shape.lineTo(meta.cx - half, z1);
  shape.lineTo(meta.cx + half, z1);
  shape.lineTo(meta.cx + half, z0);
  shape.closePath();
  cover.geometry.dispose();
  cover.geometry = new THREE.ShapeGeometry(shape);
}

function paint(root: THREE.Object3D, display: string, glass: string, seal: boolean) {
  root.traverse((obj) => {
    const mesh = obj as THREE.Mesh;
    if (!mesh.isMesh) return;
    if (AIR_LENS.has(mesh.name)) {
      mesh.visible = false;
      return;
    }
    if (mesh.name === display) {
      unlightDisplay(mesh);
      if (seal) notchCap(mesh);
      return;
    }
    if (mesh.name === glass) {
      hideGlass(mesh);
      return;
    }
    const list = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    const next = list.map((mat) => {
      const usd = USD_DIFFUSE[mat.name];
      if (!usd || !('color' in mat)) return mat;
      const copy = (mat as THREE.MeshStandardMaterial).clone();
      copy.color.setRGB(usd[0], usd[1], usd[2], THREE.LinearSRGBColorSpace);
      return copy;
    });
    mesh.material = Array.isArray(mesh.material) ? next : next[0];
  });
}

function Laptop({ url, display, glass, texture, x, f, seal = false }: { url: string; display: string; glass: string; texture: THREE.Texture | null; x: number; f: number; seal?: boolean }) {
  const gltf = useLoader(GLTFLoader, url);
  const advance = useThree((s) => s.advance);
  const frame = useCurrentFrame();
  const { delayRender, continueRender } = useDelayRender();
  const waiting = useRef<number | null>(null);
  const scene = useMemo(() => {
    const next = gltf.scene.clone(true);
    paint(next, display, glass, seal);
    return next;
  }, [gltf, display, glass, seal]);
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
  useLayoutEffect(() => {
    if (seal) syncCover(scene, f);
  }, [seal, scene, f]);
  return <primitive object={scene} position={[x, 0, 0]} />;
}

function phoneCard(title: string, sub: string, lock: boolean) {
  const c = document.createElement('canvas');
  c.width = 360;
  c.height = 720;
  const g = c.getContext('2d');
  if (!g) return new THREE.CanvasTexture(c);
  // 与 B 站 Remote 同级：钛边内的黑玻璃 + 灵动岛 + 活动条（审片 C10-06）。
  const grad = g.createRadialGradient(110, 120, 20, 180, 280, 420);
  grad.addColorStop(0, '#1d3b66');
  grad.addColorStop(0.55, '#0b1626');
  grad.addColorStop(1, '#05070b');
  g.fillStyle = grad;
  g.fillRect(0, 0, 360, 720);
  g.fillStyle = '#000';
  roundRect(g, 118, 22, 124, 34, 17);
  g.fill();
  if (lock) {
    g.fillStyle = 'rgba(255,255,255,.9)';
    g.font = '600 22px PingFang SC, sans-serif';
    g.textAlign = 'center';
    g.fillText('10月4日 星期日', 180, 110);
    g.font = '700 92px SF Pro Display, -apple-system, sans-serif';
    g.fillStyle = 'rgba(255,255,255,.92)';
    g.fillText(title || '9:41', 180, 210);
  } else {
    g.fillStyle = 'rgba(28,28,30,.92)';
    roundRect(g, 28, 90, 304, 118, 28);
    g.fill();
    g.fillStyle = '#fff';
    g.font = '600 34px PingFang SC, sans-serif';
    g.textAlign = 'left';
    g.fillText(title, 52, 142);
    g.font = '500 22px PingFang SC, sans-serif';
    g.fillStyle = 'rgba(255,255,255,.62)';
    g.fillText(sub, 52, 176);
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
    return { dx: -0.23, title: food ? '外卖到了' : '车快到了', sub: food ? '放在门口了' : '还有 2 分钟', lock: false };
  }
  if (f >= 2880 && f < 3290) {
    const t = Math.max(0, Math.min(1, (f - 2980) / 180));
    const away = t * t * (3 - 2 * t);
    return { dx: -0.22 - away * 0.28, title: '9:41', sub: '', lock: true };
  }
  return null;
}

function Phone({ f }: { f: number }) {
  const spec = phoneAt(f);
  const title = spec?.title ?? '';
  const sub = spec?.sub ?? '';
  const lock = spec?.lock ?? false;
  const tex = useMemo(() => phoneCard(title, sub, lock), [title, sub, lock]);
  const body = useMemo(() => new RoundedBoxGeometry(0.078, 0.162, 0.0086, 6, 0.0062), []);
  if (!spec) return null;
  const w = 0.078, h = 0.162, d = 0.0086;
  const metal = { color: '#8d8a86', metalness: 0.9, roughness: 0.28 };
  return (
    <group position={[SEAT.air + spec.dx, 0.15, -0.06]} rotation={[0.12, 0.55, 0]}>
      <mesh geometry={body}>
        <meshStandardMaterial {...metal} />
      </mesh>
      <mesh position={[-w * 0.5 - 0.0009, h * 0.14, 0]}>
        <boxGeometry args={[0.0015, 0.026, 0.0036]} />
        <meshStandardMaterial color="#5a5855" metalness={0.75} roughness={0.4} />
      </mesh>
      <mesh position={[-w * 0.5 - 0.0009, h * 0.04, 0]}>
        <boxGeometry args={[0.0015, 0.016, 0.0036]} />
        <meshStandardMaterial color="#5a5855" metalness={0.75} roughness={0.4} />
      </mesh>
      <mesh position={[w * 0.5 + 0.0009, h * 0.08, 0]}>
        <boxGeometry args={[0.0015, 0.022, 0.0036]} />
        <meshStandardMaterial color="#5a5855" metalness={0.75} roughness={0.4} />
      </mesh>
      <mesh position={[0, 0, d * 0.48]}>
        <planeGeometry args={[w * 0.9, h * 0.93]} />
        <meshBasicMaterial color="#050505" toneMapped={false} />
      </mesh>
      <mesh position={[0, 0, d * 0.56]}>
        <planeGeometry args={[w * 0.86, h * 0.9]} />
        <meshBasicMaterial map={tex} toneMapped={false} />
      </mesh>
    </group>
  );
}

function Studio() {
  const gl = useThree((s) => s.gl);
  const scene = useThree((s) => s.scene);
  useLayoutEffect(() => {
    const pmrem = new THREE.PMREMGenerator(gl);
    const env = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    scene.environment = env;
    return () => {
      env.dispose();
      pmrem.dispose();
    };
  }, [gl, scene]);
  return (
    <>
      <color attach="background" args={['#12141a']} />
      <ambientLight intensity={0.55} />
      <directionalLight position={[1.6, 3.4, 2.2]} intensity={2.6} />
      <directionalLight position={[-2.4, 1.4, 1.6]} intensity={0.7} />
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
      <Laptop url={staticFile('mesh/macbook-neo.glb')} display={NEO_DISPLAY} glass={NEO_GLASS} texture={neoTex} x={SEAT.neo} f={f} />
      <Laptop url={staticFile('mesh/macbook-air-15in-midnight.glb')} display={AIR_DISPLAY} glass={AIR_GLASS} texture={airTex} x={SEAT.air} f={f} seal />
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
