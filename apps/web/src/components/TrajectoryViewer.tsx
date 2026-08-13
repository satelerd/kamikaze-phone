'use client';

// 3D trajectory viewer, DA3-viewer style (nano-world-model video_to_3d):
// glowing flight tube, phone marker animated with gyro-integrated quaternions,
// and video frames rendered as small camera-frustum cards posed along the path
// at their timestamps. Plain imperative three.js, no react-three-fiber.
//
// - `playheadMs` (external getter) syncs the 3D playhead with the slow-mo video
// - without it (desktop demo / trajectory-only) the viewer self-animates
// - handles WebGL context loss and disposes everything on unmount
import { useEffect, useRef } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import type { TrajectoryPoint } from '@/lib/types';

export interface ViewerFrame {
  /** ms since launch */
  tMs: number;
  image: HTMLCanvasElement;
}

interface TrajectoryViewerProps {
  trajectory: TrajectoryPoint[];
  frames?: ViewerFrame[];
  /** External playhead getter (ms since launch). Omit to self-animate. */
  playheadMs?: () => number;
  className?: string;
}

const BG = 0x09090b; // zinc-950
const AMBER = 0xfbbf24; // amber-400

function samplePose(
  traj: TrajectoryPoint[],
  tMs: number,
  outPos: THREE.Vector3,
  outQuat: THREE.Quaternion,
  qa: THREE.Quaternion,
  qb: THREE.Quaternion,
): void {
  if (traj.length === 0) return;
  const first = traj[0];
  const last = traj[traj.length - 1];
  if (tMs <= first.t || traj.length === 1) {
    outPos.set(first.x, first.y, first.z);
    outQuat.set(first.qx, first.qy, first.qz, first.qw);
    return;
  }
  if (tMs >= last.t) {
    outPos.set(last.x, last.y, last.z);
    outQuat.set(last.qx, last.qy, last.qz, last.qw);
    return;
  }
  let i = 1;
  while (i < traj.length - 1 && traj[i].t < tMs) i++;
  const a = traj[i - 1];
  const b = traj[i];
  const f = (tMs - a.t) / Math.max(1e-6, b.t - a.t);
  outPos.set(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f, a.z + (b.z - a.z) * f);
  qa.set(a.qx, a.qy, a.qz, a.qw);
  qb.set(b.qx, b.qy, b.qz, b.qw);
  outQuat.copy(qa).slerp(qb, f);
}

function buildPhoneMarker(): THREE.Group {
  const group = new THREE.Group();
  const body = new THREE.Mesh(
    new THREE.BoxGeometry(0.075, 0.16, 0.009),
    new THREE.MeshBasicMaterial({ color: 0x27272a }),
  );
  const edges = new THREE.LineSegments(
    new THREE.EdgesGeometry(new THREE.BoxGeometry(0.075, 0.16, 0.009)),
    new THREE.LineBasicMaterial({ color: AMBER }),
  );
  const screen = new THREE.Mesh(
    new THREE.PlaneGeometry(0.064, 0.144),
    new THREE.MeshBasicMaterial({ color: 0x38bdf8, transparent: true, opacity: 0.9 }),
  );
  screen.position.z = 0.0055;
  const lens = new THREE.Mesh(
    new THREE.CircleGeometry(0.008, 12),
    new THREE.MeshBasicMaterial({ color: 0xfafafa }),
  );
  lens.position.set(-0.02, 0.06, -0.0055);
  lens.rotation.y = Math.PI;
  group.add(body, edges, screen, lens);
  return group;
}

interface FrustumCard {
  group: THREE.Group;
  plane: THREE.Mesh<THREE.PlaneGeometry, THREE.MeshBasicMaterial>;
  lines: THREE.LineSegments<THREE.BufferGeometry, THREE.LineBasicMaterial>;
  tMs: number;
}

function buildFrustumCard(
  frame: ViewerFrame,
  traj: TrajectoryPoint[],
  qa: THREE.Quaternion,
  qb: THREE.Quaternion,
): FrustumCard {
  const pos = new THREE.Vector3();
  const quat = new THREE.Quaternion();
  samplePose(traj, frame.tMs, pos, quat, qa, qb);

  const w = 0.26;
  const h = Math.max(0.06, (frame.image.height / Math.max(1, frame.image.width)) * w);
  const depth = 0.17;

  const group = new THREE.Group();
  group.position.copy(pos);
  group.quaternion.copy(quat);

  const tex = new THREE.CanvasTexture(frame.image);
  tex.colorSpace = THREE.SRGBColorSpace;
  const plane = new THREE.Mesh(
    new THREE.PlaneGeometry(w, h),
    new THREE.MeshBasicMaterial({
      map: tex,
      side: THREE.DoubleSide,
      transparent: true,
      opacity: 0.85,
      depthWrite: false,
    }),
  );
  // Device camera looks out the back of the phone: local -z, DA3 frusta style.
  plane.position.z = -depth;
  group.add(plane);

  // Frustum wireframe: apex (device) to the four image-plane corners + border.
  const x = w / 2;
  const y = h / 2;
  const z = -depth;
  // prettier-ignore
  const verts = new Float32Array([
    0, 0, 0, -x, -y, z,
    0, 0, 0, x, -y, z,
    0, 0, 0, x, y, z,
    0, 0, 0, -x, y, z,
    -x, -y, z, x, -y, z,
    x, -y, z, x, y, z,
    x, y, z, -x, y, z,
    -x, y, z, -x, -y, z,
  ]);
  const lineGeo = new THREE.BufferGeometry();
  lineGeo.setAttribute('position', new THREE.BufferAttribute(verts, 3));
  const lines = new THREE.LineSegments(
    lineGeo,
    new THREE.LineBasicMaterial({ color: AMBER, transparent: true, opacity: 0.35 }),
  );
  group.add(lines);

  return { group, plane, lines, tMs: frame.tMs };
}

export default function TrajectoryViewer({
  trajectory,
  frames,
  playheadMs,
  className,
}: TrajectoryViewerProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const playheadRef = useRef<(() => number) | undefined>(playheadMs);
  playheadRef.current = playheadMs;

  useEffect(() => {
    const container = containerRef.current;
    if (!container || trajectory.length < 2) return;

    // --- renderer -----------------------------------------------------------
    const renderer = new THREE.WebGLRenderer({ antialias: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setClearColor(BG);
    renderer.domElement.style.width = '100%';
    renderer.domElement.style.height = '100%';
    renderer.domElement.style.display = 'block';
    renderer.domElement.style.borderRadius = '1rem';
    renderer.domElement.style.touchAction = 'none';
    container.appendChild(renderer.domElement);

    let contextLost = false;
    const onContextLost = (e: Event) => {
      e.preventDefault(); // allow the browser to restore the context
      contextLost = true;
    };
    const onContextRestored = () => {
      contextLost = false;
    };
    renderer.domElement.addEventListener('webglcontextlost', onContextLost);
    renderer.domElement.addEventListener('webglcontextrestored', onContextRestored);

    // --- scene --------------------------------------------------------------
    const scene = new THREE.Scene();
    scene.fog = new THREE.FogExp2(BG, 0.045);

    const qa = new THREE.Quaternion();
    const qb = new THREE.Quaternion();

    const pts = trajectory.map((p) => new THREE.Vector3(p.x, p.y, p.z));
    const bbox = new THREE.Box3().setFromPoints(pts);
    const center = bbox.getCenter(new THREE.Vector3());
    const size = bbox.getSize(new THREE.Vector3());
    const groundY = Math.min(0, bbox.min.y) - 0.02;

    const grid = new THREE.GridHelper(12, 24, 0x3f3f46, 0x27272a);
    grid.position.y = groundY;
    scene.add(grid);

    // glowing flight tube (core + additive halo)
    const curve = new THREE.CatmullRomCurve3(pts);
    const tubeSegments = Math.min(240, Math.max(32, pts.length * 2));
    const core = new THREE.Mesh(
      new THREE.TubeGeometry(curve, tubeSegments, 0.012, 8, false),
      new THREE.MeshBasicMaterial({ color: AMBER }),
    );
    const halo = new THREE.Mesh(
      new THREE.TubeGeometry(curve, tubeSegments, 0.034, 8, false),
      new THREE.MeshBasicMaterial({
        color: 0xf59e0b,
        transparent: true,
        opacity: 0.16,
        blending: THREE.AdditiveBlending,
        depthWrite: false,
      }),
    );
    scene.add(core, halo);

    // launch / land markers
    const launchDot = new THREE.Mesh(
      new THREE.SphereGeometry(0.03, 16, 12),
      new THREE.MeshBasicMaterial({ color: 0x34d399 }),
    );
    launchDot.position.copy(pts[0]);
    const landDot = new THREE.Mesh(
      new THREE.SphereGeometry(0.03, 16, 12),
      new THREE.MeshBasicMaterial({ color: 0xf87171 }),
    );
    landDot.position.copy(pts[pts.length - 1]);
    scene.add(launchDot, landDot);

    // phone marker animated along the path
    const marker = buildPhoneMarker();
    scene.add(marker);

    // frame cards as camera frusta
    const cards: FrustumCard[] = (frames ?? []).map((f) => buildFrustumCard(f, trajectory, qa, qb));
    cards.forEach((c) => scene.add(c.group));

    // --- camera + controls --------------------------------------------------
    const width = container.clientWidth || 320;
    const height = container.clientHeight || 320;
    const camera = new THREE.PerspectiveCamera(50, width / height, 0.01, 200);
    const radius = Math.max(size.length() * 0.75, 0.8);
    camera.position.set(center.x + radius * 1.3, center.y + radius * 0.9, center.z + radius * 1.5);
    renderer.setSize(width, height, false);

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.target.copy(center);
    controls.enableDamping = true;
    controls.dampingFactor = 0.08;
    controls.minDistance = 0.25;
    controls.maxDistance = 30;
    controls.update();

    const resizeObserver = new ResizeObserver(() => {
      const w = container.clientWidth || 320;
      const h = container.clientHeight || 320;
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
      renderer.setSize(w, h, false);
    });
    resizeObserver.observe(container);

    // --- animation loop -----------------------------------------------------
    const maxT = trajectory[trajectory.length - 1].t;
    const highlightWindow = Math.max(90, maxT / Math.max(1, cards.length));
    const markerPos = new THREE.Vector3();
    const markerQuat = new THREE.Quaternion();
    const clock = new THREE.Clock();
    let selfT = 0;
    let raf = 0;

    const animate = () => {
      raf = requestAnimationFrame(animate);
      const dt = clock.getDelta();
      if (contextLost) return;

      let tMs: number;
      const external = playheadRef.current;
      if (external) {
        tMs = Math.max(0, Math.min(external(), maxT));
      } else {
        // self-play at 0.4x with a little pause at the end of each lap
        selfT = (selfT + dt * 1000 * 0.4) % (maxT + 500);
        tMs = Math.min(selfT, maxT);
      }

      samplePose(trajectory, tMs, markerPos, markerQuat, qa, qb);
      marker.position.copy(markerPos);
      marker.quaternion.copy(markerQuat);

      for (const card of cards) {
        const active = Math.abs(card.tMs - tMs) <= highlightWindow;
        const targetOpacity = active ? 1 : 0.55;
        const targetScale = active ? 1.14 : 1;
        card.plane.material.opacity += (targetOpacity - card.plane.material.opacity) * 0.25;
        card.lines.material.opacity = active ? 0.8 : 0.3;
        const s = card.group.scale.x + (targetScale - card.group.scale.x) * 0.25;
        card.group.scale.setScalar(s);
      }

      controls.update();
      renderer.render(scene, camera);
    };
    animate();

    // --- cleanup ------------------------------------------------------------
    return () => {
      cancelAnimationFrame(raf);
      resizeObserver.disconnect();
      controls.dispose();
      renderer.domElement.removeEventListener('webglcontextlost', onContextLost);
      renderer.domElement.removeEventListener('webglcontextrestored', onContextRestored);
      scene.traverse((obj) => {
        const mesh = obj as THREE.Mesh;
        if (mesh.geometry) mesh.geometry.dispose();
        const material = mesh.material as THREE.Material | THREE.Material[] | undefined;
        const mats = Array.isArray(material) ? material : material ? [material] : [];
        for (const m of mats) {
          const tex = (m as THREE.MeshBasicMaterial).map;
          if (tex) tex.dispose();
          m.dispose();
        }
      });
      renderer.dispose();
      renderer.forceContextLoss();
      renderer.domElement.remove();
    };
  }, [trajectory, frames]);

  if (trajectory.length < 2) {
    return (
      <div
        className={`flex items-center justify-center rounded-2xl border border-zinc-700 bg-zinc-900 text-sm text-zinc-500 ${className ?? ''}`}
      >
        No trajectory yet. Throw something. 🌀
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      className={`overflow-hidden rounded-2xl border border-zinc-700 bg-zinc-900 ${className ?? ''}`}
    />
  );
}
