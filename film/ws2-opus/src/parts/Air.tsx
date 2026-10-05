// 15 吋 MacBook Air 的網格來自 Apple 的 USDZ，經 Blender 4.5.14 一次轉成 GLB（只換載入格式）。
// 命令：Blender --background --python film/ws2-opus/tools/convert-air-usdz.py
// 蓋子角度、鍵帽、觸控板、圓角、劉海都是這份網格在透視相機下的樣子。畫面貼在顯示網格自己的 UV 上。
import { useLayoutEffect, useMemo, useRef, type RefObject } from 'react';
import { useLoader, useThree } from '@react-three/fiber';
import { ThreeCanvas } from '@remotion/three';
import { staticFile, useDelayRender } from 'remotion';
import { NoReactInternals } from 'remotion/no-react';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import * as THREE from 'three';
import { cameraAt } from '../camera';
import type { Layout } from '../layout';
import { FPS } from '../motion/site';
import { fingerAt } from '../scene';

const GLB = 'mesh/macbook-air-15in-silver.glb';
const DISPLAY = 'OQzaQDtbMVhhlAr';
const PAD = 'tPJiWzJmqJeHzUX';

type Fit = {
  center: THREE.Vector3;
  right: THREE.Vector3;
  up: THREE.Vector3;
  normal: THREE.Vector3;
  width: number;
  height: number;
  pad: THREE.Box3;
};

function findMesh(root: THREE.Object3D, name: string): THREE.Mesh | null {
  let found: THREE.Mesh | null = null;
  root.traverse((o) => {
    if ((o as THREE.Mesh).isMesh && o.name === name) found = o as THREE.Mesh;
  });
  return found;
}

const solve3 = (A: number[][], b: number[]) => {
  const M = A.map((row, i) => [...row, b[i]]);
  for (let col = 0; col < 3; col++) {
    let piv = col;
    for (let r = col + 1; r < 3; r++) if (Math.abs(M[r][col]) > Math.abs(M[piv][col])) piv = r;
    [M[col], M[piv]] = [M[piv], M[col]];
    const div = M[col][col] || 1e-12;
    for (let c = col; c < 4; c++) M[col][c] /= div;
    for (let r = 0; r < 3; r++) {
      if (r === col) continue;
      const f = M[r][col];
      for (let c = col; c < 4; c++) M[r][c] -= f * M[col][c];
    }
  }
  return [M[0][3], M[1][3], M[2][3]];
};

function measure(root: THREE.Object3D): Fit {
  root.updateWorldMatrix(true, true);
  const display = findMesh(root, DISPLAY);
  const pad = findMesh(root, PAD);
  if (!display || !pad) throw new Error(`GLB is missing ${DISPLAY} or ${PAD}`);
  const pos = display.geometry.getAttribute('position');
  const uv = display.geometry.getAttribute('uv');
  const v = new THREE.Vector3();
  let n = 0;
  let su = 0, sv = 0, suu = 0, svv = 0, suv = 0;
  const sp = new THREE.Vector3();
  const spu = new THREE.Vector3();
  const spv = new THREE.Vector3();
  for (let i = 0; i < pos.count; i++) {
    v.fromBufferAttribute(pos, i).applyMatrix4(display.matrixWorld);
    const u = uv.getX(i);
    const t = uv.getY(i);
    n++;
    su += u; sv += t; suu += u * u; svv += t * t; suv += u * t;
    sp.add(v);
    spu.addScaledVector(v, u);
    spv.addScaledVector(v, t);
  }
  const A = [[n, su, sv], [su, suu, suv], [sv, suv, svv]];
  const xs = solve3(A, [sp.x, spu.x, spv.x]);
  const ys = solve3(A, [sp.y, spu.y, spv.y]);
  const zs = solve3(A, [sp.z, spu.z, spv.z]);
  const Su = new THREE.Vector3(xs[1], ys[1], zs[1]);
  const Sv = new THREE.Vector3(xs[2], ys[2], zs[2]);
  const C = new THREE.Vector3(xs[0], ys[0], zs[0]);
  const center = C.clone().addScaledVector(Su, 0.5).addScaledVector(Sv, 0.5);
  const right = Su.clone();
  const width = right.length() || 1;
  right.normalize();
  const vertical = Sv.clone();
  if (vertical.y < 0) vertical.negate();
  const height = Sv.length() || 1;
  vertical.addScaledVector(right, -vertical.dot(right)).normalize();
  const normal = new THREE.Vector3().crossVectors(right, vertical);
  const padBox = new THREE.Box3().setFromObject(pad);
  const padCenter = padBox.getCenter(new THREE.Vector3());
  if (normal.dot(padCenter.clone().sub(center)) < 0) normal.negate();
  unlightPanel(display.material as THREE.MeshPhysicalMaterial);
  flattenNotch(root);
  return { center, right, up: vertical, normal, width, height, pad: padBox };
}

// 劉海洞後面的玻璃帶 0.25 清漆，打光後是一塊灰，和螢幕上不發光的 #000 對不上。
// 只把這幾片改成和島同一個黑。相機殼的材質和機身別處共用，要先複製再改。
const BEZEL_MATERIALS = new Set(['ZvlnNWnCtBWCjYa', 'NXfCxXWtcjrIlRh']);
const BEZEL_MESHES = new Set(['eSdMhlXkmSqQAea']);
// 藍色鏡片會在洞裡變成第二個點，島就不是一整塊黑。
const HIDE_LENS = new Set(['EJoLfqyXwgkVSrS', 'soepNneYNHLBQgD', 'eSdMhlXkmSqQAea', 'yJcYkdpBvjzGhrI']);

function killLight(mat: THREE.MeshPhysicalMaterial) {
  mat.color.set(0x000000);
  mat.metalness = 0;
  mat.roughness = 1;
  mat.envMapIntensity = 0;
  mat.clearcoat = 0;
  mat.clearcoatRoughness = 1;
  mat.specularIntensity = 0;
  mat.emissive.set(0x000000);
  mat.emissiveIntensity = 0;
  mat.toneMapped = false;
  mat.needsUpdate = true;
}

function flattenNotch(root: THREE.Object3D) {
  root.traverse((o) => {
    const mesh = o as THREE.Mesh;
    if (!mesh.isMesh) return;
    const base = mesh.name.replace(/_\d+$/, '');
    if (HIDE_LENS.has(mesh.name) || HIDE_LENS.has(base)) mesh.visible = false;
    const list = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
    const next = list.map((m) => {
      const mat = m as THREE.MeshPhysicalMaterial;
      if (BEZEL_MESHES.has(mesh.name) || BEZEL_MESHES.has(base)) {
        const clone = mat.clone();
        killLight(clone);
        return clone;
      }
      if (mat.name && BEZEL_MATERIALS.has(mat.name)) killLight(mat);
      return mat;
    });
    mesh.material = Array.isArray(mesh.material) ? next : next[0];
  });
}

function LensCap({ root, normal }: { root: THREE.Object3D; normal: THREE.Vector3 }) {
  const cap = useMemo(() => {
    const box = new THREE.Box3();
    const tmp = new THREE.Box3();
    let hit = false;
    root.traverse((o) => {
      const base = o.name.replace(/_\d+$/, '');
      if (!HIDE_LENS.has(base)) return;
      tmp.setFromObject(o);
      if (tmp.isEmpty()) return;
      box.union(tmp);
      hit = true;
    });
    if (!hit) return null;
    const center = box.getCenter(new THREE.Vector3()).addScaledVector(normal, 0.0015);
    const size = box.getSize(new THREE.Vector3());
    return { center, radius: Math.max(size.x, size.y, size.z) * 0.72 };
  }, [normal, root]);
  if (!cap) return null;
  return (
    <mesh position={cap.center}>
      <sphereGeometry args={[cap.radius, 20, 16]} />
      <meshBasicMaterial color="#000000" toneMapped={false} />
    </mesh>
  );
}

const project = (camera: THREE.Camera, p: THREE.Vector3, L: Layout) => {
  const v = p.clone().project(camera);
  return { x: (v.x * 0.5 + 0.5) * L.width, y: (-v.y * 0.5 + 0.5) * L.height };
};

function frameCamera(camera: THREE.PerspectiveCamera, L: Layout, out: number, fit: Fit) {
  const c = cameraAt(out, L);
  const S = L.screen;
  const cx = c.tx + c.z * (S.x + S.w / 2 - c.ax);
  const cy = c.ty + c.z * (S.y + S.h / 2 - c.ay);
  const desiredW = Math.max(48, c.z * S.w);
  const t = Math.min(1, Math.max(0, (c.ay - S.y) / S.h));
  const look = fit.center.clone().addScaledVector(fit.up, (0.5 - t) * fit.height);
  const wide = L.name === 'landscape' ? 0.42 : 0.55;
  const mag = Math.max(0.25, c.z / wide);
  const elevate = 0.5 / Math.pow(mag, 0.55);
  const dir = fit.normal.clone().add(new THREE.Vector3(0, elevate, 0)).normalize();
  const fov = (camera.fov * Math.PI) / 180;
  const visWPerDist = 2 * Math.tan(fov / 2) * (L.width / L.height);
  let dist = THREE.MathUtils.clamp(fit.width / (desiredW / L.width) / visWPerDist, 0.08, 4);
  camera.aspect = L.width / L.height;
  camera.near = 0.01;
  camera.far = 20;
  camera.up.set(0, 1, 0);
  const left = new THREE.Vector3();
  const right = new THREE.Vector3();
  for (let k = 0; k < 4; k++) {
    camera.position.copy(look).addScaledVector(dir, dist);
    camera.lookAt(look);
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld();
    const pC = project(camera, fit.center, L);
    const got = Math.hypot(
      project(camera, left.copy(fit.center).addScaledVector(fit.right, -fit.width / 2), L).x - project(camera, right.copy(fit.center).addScaledVector(fit.right, fit.width / 2), L).x,
      project(camera, left, L).y - project(camera, right, L).y,
    );
    if (got > 1) dist = THREE.MathUtils.clamp(dist * (got / desiredW), 0.08, 4);
    const visH = 2 * Math.tan(fov / 2) * dist;
    const visW = visH * (L.width / L.height);
    const camRight = new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld, 0);
    const camUp = new THREE.Vector3().setFromMatrixColumn(camera.matrixWorld, 1);
    look.addScaledVector(camRight, ((pC.x - cx) / L.width) * visW);
    look.addScaledVector(camUp, (-(pC.y - cy) / L.height) * visH);
  }
}

const padPoint = (fit: Fit, xPct: number, yPct: number) => {
  const { pad, center } = fit;
  const x = pad.min.x + (xPct / 100) * (pad.max.x - pad.min.x);
  const zNear = Math.abs(pad.min.z - center.z) < Math.abs(pad.max.z - center.z) ? pad.min.z : pad.max.z;
  const zFar = zNear === pad.min.z ? pad.max.z : pad.min.z;
  const z = zNear + (yPct / 100) * (zFar - zNear);
  return new THREE.Vector3(x, pad.max.y + 0.0025, z);
};

function Studio() {
  const gl = useThree((s) => s.gl);
  const scene = useThree((s) => s.scene);
  useLayoutEffect(() => {
    const pmrem = new THREE.PMREMGenerator(gl);
    const env = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
    scene.environment = env;
    scene.environmentIntensity = 0.9;
    return () => {
      env.dispose();
      pmrem.dispose();
    };
  }, [gl, scene]);
  return (
    <>
      <ambientLight intensity={0.28} />
      <directionalLight position={[0.4, 1.05, 0.55]} intensity={2.6} />
      <directionalLight position={[-0.55, 0.4, 0.35]} intensity={0.75} />
    </>
  );
}

// 顯示網格的 USDZ 材質帶 0.25 清漆、環境高光會加在發光貼圖上，暗色視窗就被抬成一塊灰。
// 只關掉這一面的受光，機身仍用原來的材質。
function unlightPanel(mat: THREE.MeshPhysicalMaterial) {
  mat.color.set(0x000000);
  mat.metalness = 0;
  mat.roughness = 1;
  mat.envMapIntensity = 0;
  mat.clearcoat = 0;
  mat.clearcoatRoughness = 1;
  mat.specularIntensity = 0;
  mat.emissive.set(0xffffff);
  mat.emissiveIntensity = 1;
  mat.toneMapped = false;
  mat.needsUpdate = true;
}

function paintScreen(mat: THREE.MeshPhysicalMaterial, map: THREE.Texture) {
  unlightPanel(mat);
  mat.emissiveMap = map;
  mat.needsUpdate = true;
}

const PLATE = staticFile('screen/plate.mp4');

function ScreenCapture({ revision, display, onReady }: { revision: number; display: THREE.Mesh; onReady: () => void }) {
  const { gl, scene, advance } = useThree();
  const live = useThree((s) => s.camera);
  const liveRef = useRef(live);
  liveRef.current = live;
  const onReadyRef = useRef(onReady);
  onReadyRef.current = onReady;
  const url = NoReactInternals.getOffthreadVideoSource({
    src: PLATE,
    currentTime: Math.max(0, revision) / FPS,
    transparent: false,
    toneMapped: false,
  });
  const { delayRender, continueRender } = useDelayRender();
  useLayoutEffect(() => {
    const handle = delayRender(`screen ${revision}`);
    const loader = new THREE.TextureLoader();
    let dead = false;
    loader.load(url, (tex) => {
      if (dead) {
        tex.dispose();
        continueRender(handle);
        return;
      }
      tex.colorSpace = THREE.SRGBColorSpace;
      tex.flipY = false;
      tex.anisotropy = gl.capabilities.getMaxAnisotropy();
      const mat = display.material as THREE.MeshPhysicalMaterial;
      paintScreen(mat, tex);
      requestAnimationFrame(() => {
        if (!dead) {
          paintScreen(display.material as THREE.MeshPhysicalMaterial, tex);
          advance(performance.now());
          gl.render(scene, liveRef.current);
          onReadyRef.current();
        }
        continueRender(handle);
      });
    }, undefined, (err) => {
      console.error(err);
      continueRender(handle);
      onReadyRef.current();
    });
    return () => {
      dead = true;
    };
  }, [advance, continueRender, delayRender, display, gl, revision, scene, url]);
  return null;
}

/** 觸控板上的一筆：等寬、圓頭，像 Markup。沿板面法線擠出，不跟手指拖一截粒子。 */
function inkGeometry(points: THREE.Vector3[], width: number) {
  const half = width / 2;
  const up = new THREE.Vector3(0, 1, 0);
  const pos: number[] = [];
  const idx: number[] = [];
  const push = (p: THREE.Vector3) => {
    pos.push(p.x, p.y, p.z);
    return pos.length / 3 - 1;
  };
  const sides = points.map((_, i) => {
    const a = points[Math.max(0, i - 1)];
    const b = points[Math.min(points.length - 1, i + 1)];
    const dir = b.clone().sub(a);
    dir.y = 0;
    if (dir.lengthSq() < 1e-12) dir.set(1, 0, 0);
    return new THREE.Vector3().crossVectors(up, dir).normalize();
  });
  for (let i = 0; i < points.length; i++) {
    push(points[i].clone().addScaledVector(sides[i], half));
    push(points[i].clone().addScaledVector(sides[i], -half));
  }
  for (let i = 0; i < points.length - 1; i++) {
    const a = i * 2;
    idx.push(a, a + 1, a + 2, a + 1, a + 3, a + 2);
  }
  const cap = (at: number, outward: number) => {
    const center = points[at];
    const side = sides[at];
    const tangent = new THREE.Vector3().crossVectors(side, up).normalize();
    const hub = push(center);
    const steps = 8;
    let prev = -1;
    for (let k = 0; k <= steps; k++) {
      const ang = (k / steps) * Math.PI;
      const off = side.clone().multiplyScalar(Math.cos(ang) * half).addScaledVector(tangent, Math.sin(ang) * half * outward);
      const id = push(center.clone().add(off));
      if (prev >= 0) idx.push(hub, outward > 0 ? prev : id, outward > 0 ? id : prev);
      prev = id;
    }
  };
  cap(0, -1);
  cap(points.length - 1, 1);
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  geo.setIndex(idx);
  return geo;
}

function Finger({ fit, frame }: { fit: Fit; frame: number }) {
  const finger = fingerAt(frame);
  const flick = useMemo(() => new THREE.Line(new THREE.BufferGeometry(), new THREE.LineBasicMaterial({ color: 0x0a84ff, transparent: true })), []);
  const ink = useMemo(() => new THREE.Mesh(new THREE.BufferGeometry(), new THREE.MeshBasicMaterial({ color: 0x1d1d1f, toneMapped: false, transparent: true, depthWrite: false, side: THREE.DoubleSide })), []);
  useLayoutEffect(() => {
    const flickMat = flick.material as THREE.LineBasicMaterial;
    const inkMat = ink.material as THREE.MeshBasicMaterial;
    flick.visible = false;
    ink.visible = false;
    if (!finger || finger.trail.length < 2) return;
    const pts = finger.trail.map((p) => padPoint(fit, p.x, p.y));
    if (finger.ink) {
      ink.geometry.dispose();
      ink.geometry = inkGeometry(pts, 0.0032);
      inkMat.opacity = finger.opacity;
      ink.visible = true;
      return;
    }
    flick.geometry.setFromPoints(pts);
    flickMat.opacity = 0.55 * finger.opacity;
    flick.visible = true;
  }, [finger, fit, flick, ink]);
  if (!finger) return <primitive object={flick} visible={false} />;
  const at = padPoint(fit, finger.x, finger.y);
  return (
    <>
      <primitive object={flick} />
      <primitive object={ink} />
      {!finger.ink && (
        <mesh position={at} visible={finger.opacity > 0}>
          <sphereGeometry args={[0.008, 18, 18]} />
          <meshBasicMaterial color={0x0a84ff} transparent opacity={0.85 * finger.opacity} />
        </mesh>
      )}
    </>
  );
}

function Rig({ L, out, frame, onReady }: { L: Layout; out: number; frame: number; onReady: () => void }) {
  const gltf = useLoader(GLTFLoader, staticFile(GLB));
  const root = useMemo(() => gltf.scene.clone(true), [gltf]);
  const fit = useMemo(() => measure(root), [root]);
  const display = findMesh(root, DISPLAY);
  const camRef = useRef<THREE.PerspectiveCamera>(null);
  useLayoutEffect(() => {
    const cam = camRef.current;
    if (!cam) return;
    frameCamera(cam, L, out, fit);
  });
  if (!display) return null;
  return (
    <>
      <perspectiveCamera ref={camRef} fov={30} near={0.01} far={20} position={[0, 0.28, 0.75]} />
      <primitive object={root} />
      <Studio />
      <ScreenCapture revision={out} display={display} onReady={onReady} />
      <LensCap root={root} normal={fit.normal} />
      <Finger fit={fit} frame={frame} />
      <UseCamera camRef={camRef} />
    </>
  );
}

function UseCamera({ camRef }: { camRef: RefObject<THREE.PerspectiveCamera | null> }) {
  const set = useThree((s) => s.set);
  useLayoutEffect(() => {
    const cam = camRef.current;
    if (cam) set({ camera: cam });
  }, [camRef, set]);
  return null;
}

export function Air({ L, out, frame, onReady }: { L: Layout; out: number; frame: number; onReady: () => void }) {
  return (
    <ThreeCanvas
      width={L.width}
      height={L.height}
      dpr={1}
      gl={{ preserveDrawingBuffer: true, antialias: true, alpha: true }}
      onCreated={({ gl }) => {
        gl.setClearColor(0x000000, 0);
        gl.outputColorSpace = THREE.SRGBColorSpace;
      }}
      style={{ position: 'absolute', inset: 0, background: 'transparent' }}
    >
      <Rig L={L} out={out} frame={frame} onReady={onReady} />
    </ThreeCanvas>
  );
}
