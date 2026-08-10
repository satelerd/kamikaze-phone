import { useCallback, useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { ExpoWebGLRenderingContext, GLView } from 'expo-gl';
import { Renderer } from 'expo-three';
import * as THREE from 'three';

import type { ReplayFrame } from '../motion/types';
import { colors, fonts } from '../theme';

export type OrbitCamera = {
  azimuth: number;
  elevation: number;
  distance: number;
};

type PhoneScene3DProps = {
  camera: OrbitCamera;
  comparisonFrame?: ReplayFrame;
  frame: ReplayFrame;
  restOrientation?: 'flat' | 'screen';
  shellColor?: string;
  tone: 'blue' | 'coral';
  variant?: 'calibration' | 'flight' | 'game' | 'pose';
};

const PHONE_BLUE = new THREE.Color(colors.cobalt);
const PHONE_CORAL = new THREE.Color(colors.coral);

function roundedRectangle(width: number, height: number, radius: number): THREE.Shape {
  const x = -width / 2;
  const y = -height / 2;
  const shape = new THREE.Shape();
  shape.moveTo(x + radius, y);
  shape.lineTo(x + width - radius, y);
  shape.quadraticCurveTo(x + width, y, x + width, y + radius);
  shape.lineTo(x + width, y + height - radius);
  shape.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
  shape.lineTo(x + radius, y + height);
  shape.quadraticCurveTo(x, y + height, x, y + height - radius);
  shape.lineTo(x, y + radius);
  shape.quadraticCurveTo(x, y, x + radius, y);
  return shape;
}

function createPhone(): { group: THREE.Group; shellMaterial: THREE.MeshStandardMaterial } {
  const group = new THREE.Group();
  const shellMaterial = new THREE.MeshStandardMaterial({
    color: PHONE_BLUE,
    metalness: 0.48,
    roughness: 0.32,
  });
  const shell = new THREE.Mesh(
    new THREE.ExtrudeGeometry(roundedRectangle(1.02, 1.94, 0.18), {
      bevelEnabled: true,
      bevelSegments: 3,
      bevelSize: 0.045,
      bevelThickness: 0.035,
      curveSegments: 8,
      depth: 0.13,
      steps: 1,
    }),
    shellMaterial,
  );
  shell.geometry.center();
  group.add(shell);

  const screen = new THREE.Mesh(
    new THREE.ShapeGeometry(roundedRectangle(0.91, 1.79, 0.14), 10),
    new THREE.MeshStandardMaterial({ color: 0x0b0c0a, metalness: 0.08, roughness: 0.24 }),
  );
  screen.position.z = 0.112;
  group.add(screen);

  const screenGlow = new THREE.Mesh(
    new THREE.PlaneGeometry(0.58, 0.018),
    new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.62 }),
  );
  screenGlow.position.set(0, 0.58, 0.116);
  group.add(screenGlow);

  const island = new THREE.Mesh(
    new THREE.BoxGeometry(0.4, 0.48, 0.045),
    new THREE.MeshStandardMaterial({ color: 0x20221d, metalness: 0.35, roughness: 0.32 }),
  );
  island.position.set(-0.23, 0.57, -0.112);
  group.add(island);

  const lensGeometry = new THREE.CylinderGeometry(0.105, 0.105, 0.055, 24);
  const lensMaterial = new THREE.MeshStandardMaterial({ color: 0x050605, metalness: 0.75, roughness: 0.18 });
  [[-0.32, 0.68], [-0.14, 0.47]].forEach(([x, y]) => {
    const lens = new THREE.Mesh(lensGeometry, lensMaterial);
    lens.rotation.x = Math.PI / 2;
    lens.position.set(x, y, -0.16);
    group.add(lens);
  });

  const buttonMaterial = new THREE.MeshStandardMaterial({ color: 0xd8d8cf, metalness: 0.6, roughness: 0.28 });
  const button = new THREE.Mesh(new THREE.BoxGeometry(0.025, 0.34, 0.055), buttonMaterial);
  button.position.set(0.535, 0.18, 0);
  group.add(button);

  group.scale.setScalar(0.86);
  return { group, shellMaterial };
}

export function PhoneScene3D({
  camera,
  comparisonFrame,
  frame,
  restOrientation = 'flat',
  shellColor,
  tone,
  variant = 'flight',
}: PhoneScene3DProps) {
  const [ready, setReady] = useState(false);
  const frameRef = useRef(frame);
  const cameraRef = useRef(camera);
  const comparisonFrameRef = useRef(comparisonFrame);
  const restOrientationRef = useRef(restOrientation);
  const shellColorRef = useRef(shellColor);
  const toneRef = useRef(tone);
  const variantRef = useRef(variant);
  const mountedRef = useRef(true);

  frameRef.current = frame;
  cameraRef.current = camera;
  comparisonFrameRef.current = comparisonFrame;
  restOrientationRef.current = restOrientation;
  shellColorRef.current = shellColor;
  toneRef.current = tone;
  variantRef.current = variant;

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  const handleContextCreate = useCallback((gl: ExpoWebGLRenderingContext) => {
    if (!mountedRef.current) return;

    const renderer = new Renderer({
      alpha: true,
      antialias: true,
      gl: gl as unknown as WebGLRenderingContext,
    });
    renderer.setSize(gl.drawingBufferWidth, gl.drawingBufferHeight);
    renderer.setPixelRatio(1);
    renderer.setClearColor(colors.asphalt, 0.22);
    renderer.outputColorSpace = THREE.SRGBColorSpace;

    const scene = new THREE.Scene();
    scene.fog = new THREE.Fog(colors.asphalt, 7.2, 12);
    const viewCamera = new THREE.PerspectiveCamera(
      42,
      gl.drawingBufferWidth / gl.drawingBufferHeight,
      0.05,
      50,
    );

    scene.add(new THREE.HemisphereLight(0xffffff, 0x23251f, 2.1));
    const keyLight = new THREE.DirectionalLight(0xffffff, 3.4);
    keyLight.position.set(-3, 5, 4);
    scene.add(keyLight);
    const rimLight = new THREE.DirectionalLight(0x4967ff, 2.1);
    rimLight.position.set(4, 1, -4);
    scene.add(rimLight);

    const grid = new THREE.GridHelper(12, 18, 0x4b4d45, 0x30312c);
    grid.position.y = -1.025;
    scene.add(grid);

    const axes = new THREE.AxesHelper(1.35);
    axes.position.set(-1.95, -0.93, 0.2);
    scene.add(axes);

    const { group: phone, shellMaterial } = createPhone();
    scene.add(phone);
    const { group: comparisonPhone, shellMaterial: comparisonMaterial } = createPhone();
    comparisonMaterial.color.copy(PHONE_CORAL);
    comparisonPhone.traverse((object) => {
      const mesh = object as THREE.Mesh;
      const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
      materials.filter(Boolean).forEach((material) => {
        material.transparent = true;
        material.opacity = material === comparisonMaterial ? 0.34 : 0.16;
        material.depthWrite = false;
      });
    });
    comparisonPhone.scale.multiplyScalar(1.035);
    comparisonPhone.visible = false;
    scene.add(comparisonPhone);
    if (mountedRef.current) setReady(true);

    let animationFrame = 0;
    const lookAt = new THREE.Vector3(0, -0.72, 0);
    const restPosition = new THREE.Vector3(0, -0.82, 0);
    const baseOrientation = new THREE.Quaternion().setFromAxisAngle(
      new THREE.Vector3(1, 0, 0),
      -Math.PI / 2,
    );
    const screenOrientation = new THREE.Quaternion();
    const measuredOrientation = new THREE.Quaternion();
    const comparisonOrientation = new THREE.Quaternion();
    const render = () => {
      if (!mountedRef.current) {
        cancelAnimationFrame(animationFrame);
        scene.traverse((object) => {
          const mesh = object as THREE.Mesh;
          mesh.geometry?.dispose?.();
          const materials = Array.isArray(mesh.material) ? mesh.material : [mesh.material];
          materials.filter(Boolean).forEach((material) => material.dispose());
        });
        renderer.dispose();
        return;
      }

      const currentFrame = frameRef.current;
      const isPoseMonitor = variantRef.current === 'pose';
      const isGameStage = variantRef.current === 'game';
      const isCalibration = variantRef.current === 'calibration';
      grid.visible = !isGameStage && !isCalibration;
      axes.visible = !isGameStage && !isCalibration;
      lookAt.y = isGameStage || isCalibration ? -0.08 : -0.72;
      restPosition.y = isGameStage || isCalibration ? -0.08 : -0.82;
      phone.position.copy(restPosition);
      const { x, y, z, w } = currentFrame.quaternion;
      measuredOrientation.set(x, y, z, w);
      phone.quaternion
        .copy(restOrientationRef.current === 'screen' ? screenOrientation : baseOrientation)
        .multiply(measuredOrientation);
      const comparison = comparisonFrameRef.current;
      comparisonPhone.visible = (isPoseMonitor || isCalibration) && Boolean(comparison);
      if (comparison && (isPoseMonitor || isCalibration)) {
        if (isPoseMonitor) {
          phone.position.x = -0.72;
          comparisonPhone.position.set(0.72, restPosition.y, restPosition.z);
        } else {
          comparisonPhone.position.copy(restPosition);
        }
        comparisonOrientation.set(
          comparison.quaternion.x,
          comparison.quaternion.y,
          comparison.quaternion.z,
          comparison.quaternion.w,
        );
        comparisonPhone.quaternion
          .copy(isCalibration && restOrientationRef.current === 'screen' ? screenOrientation : baseOrientation)
          .multiply(comparisonOrientation);
      }
      shellMaterial.color.set(
        shellColorRef.current ?? (toneRef.current === 'blue' ? colors.cobalt : colors.coral),
      );
      rimLight.color.set(
        shellColorRef.current ?? (toneRef.current === 'blue' ? colors.cobalt : colors.coral),
      );

      const orbit = cameraRef.current;
      const horizontalDistance = orbit.distance * Math.cos(orbit.elevation);
      viewCamera.position.set(
        horizontalDistance * Math.sin(orbit.azimuth),
        lookAt.y + orbit.distance * Math.sin(orbit.elevation),
        horizontalDistance * Math.cos(orbit.azimuth),
      );
      viewCamera.lookAt(lookAt);

      renderer.render(scene, viewCamera);
      gl.endFrameEXP();
      animationFrame = requestAnimationFrame(render);
    };
    render();
  }, []);

  return (
    <View style={styles.shell}>
      <GLView msaaSamples={2} onContextCreate={handleContextCreate} style={styles.canvas} />
      {!ready && (
        <View pointerEvents="none" style={styles.loading}>
          <Text style={styles.loadingText}>BUILDING 3D REPLAY…</Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  shell: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'transparent',
  },
  canvas: {
    backgroundColor: 'transparent',
    flex: 1,
  },
  loading: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    backgroundColor: 'rgba(15,17,22,0.54)',
    justifyContent: 'center',
  },
  loadingText: {
    color: colors.concrete,
    fontFamily: fonts.monoBold,
    fontSize: 8,
    letterSpacing: 1.2,
  },
});
