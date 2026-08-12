import { useEffect, useMemo, useRef } from 'react';
import { type GestureResponderEvent, PanResponder } from 'react-native';

import type { OrbitCamera } from './PhoneScene3D';
import { useScrollLock } from './ScrollLock';

type SpatialGesture = {
  camera: OrbitCamera;
  centerX: number;
  centerY: number;
  pinchDistance: number;
  touchCount: number;
};

type OrbitLimits = {
  maximumDistance?: number;
  minimumDistance?: number;
};

const clamp = (value: number, minimum: number, maximum: number) =>
  Math.min(maximum, Math.max(minimum, value));

function readSpatialGesture(
  event: GestureResponderEvent,
  camera: OrbitCamera,
): SpatialGesture | null {
  const touches = event.nativeEvent.touches;
  if (touches.length === 0) return null;

  const first = touches[0];
  const second = touches[1];
  if (!second) {
    return {
      camera,
      centerX: first.pageX,
      centerY: first.pageY,
      pinchDistance: 0,
      touchCount: 1,
    };
  }

  const deltaX = second.pageX - first.pageX;
  const deltaY = second.pageY - first.pageY;
  return {
    camera,
    centerX: (first.pageX + second.pageX) / 2,
    centerY: (first.pageY + second.pageY) / 2,
    pinchDistance: Math.max(1, Math.hypot(deltaX, deltaY)),
    touchCount: touches.length,
  };
}

export function useOrbitResponder(
  camera: OrbitCamera,
  onChange: (camera: OrbitCamera) => void,
  {
    maximumDistance = 11.5,
    minimumDistance = 3.6,
  }: OrbitLimits = {},
) {
  const cameraRef = useRef(camera);
  const onChangeRef = useRef(onChange);
  const spatialGestureRef = useRef<SpatialGesture | null>(null);
  const setScrollLocked = useScrollLock();

  cameraRef.current = camera;
  onChangeRef.current = onChange;

  useEffect(() => () => setScrollLocked(false), [setScrollLocked]);

  return useMemo(() => {
    const beginGesture = (event: GestureResponderEvent) => {
      setScrollLocked(true);
      spatialGestureRef.current = readSpatialGesture(event, cameraRef.current);
    };
    const endGesture = () => {
      spatialGestureRef.current = null;
      setScrollLocked(false);
    };

    return PanResponder.create({
      onMoveShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponderCapture: () => true,
      onPanResponderGrant: beginGesture,
      onPanResponderMove: (event) => {
        const touches = event.nativeEvent.touches;
        if (touches.length === 0) return;

        if (!spatialGestureRef.current || spatialGestureRef.current.touchCount !== touches.length) {
          beginGesture(event);
          return;
        }

        const start = spatialGestureRef.current;
        const current = readSpatialGesture(event, start.camera);
        if (!current) return;

        const nextCamera: OrbitCamera = {
          azimuth: start.camera.azimuth - (current.centerX - start.centerX) * 0.01,
          elevation: clamp(
            start.camera.elevation + (current.centerY - start.centerY) * 0.0065,
            -0.18,
            1.12,
          ),
          distance: start.camera.distance,
        };

        if (current.touchCount >= 2 && start.pinchDistance > 0) {
          nextCamera.distance = clamp(
            start.camera.distance * start.pinchDistance / current.pinchDistance,
            minimumDistance,
            maximumDistance,
          );
        }

        cameraRef.current = nextCamera;
        onChangeRef.current(nextCamera);
      },
      onPanResponderRelease: endGesture,
      onPanResponderTerminate: endGesture,
      onPanResponderTerminationRequest: () => false,
      onShouldBlockNativeResponder: () => true,
      onStartShouldSetPanResponder: () => true,
    });
  }, [maximumDistance, minimumDistance, setScrollLocked]);
}
