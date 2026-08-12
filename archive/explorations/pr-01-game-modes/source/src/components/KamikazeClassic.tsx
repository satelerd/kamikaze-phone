'use client';

import React, { useState, useEffect, useRef } from 'react';

const KamikazeClassic = () => {
  const [permissionGranted, setPermissionGranted] = useState(false);
  const [hasMotion, setHasMotion] = useState(true);
  const [maxHeight, setMaxHeight] = useState(0);
  const [running, setRunning] = useState(false);

  const velocityRef = useRef(0);
  const heightRef = useRef(0);
  const lastTimeRef = useRef<number | null>(null);
  const timerRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    if (typeof window === 'undefined') return;
    if (typeof (DeviceMotionEvent as any).requestPermission === 'function') {
      (DeviceMotionEvent as any).requestPermission().then((perm: string) => {
        setPermissionGranted(perm === 'granted');
      }).catch(() => setHasMotion(false));
    } else {
      setPermissionGranted(true);
    }
  }, []);

  const startGame = () => {
    if (!permissionGranted) return;
    setRunning(true);
    setMaxHeight(0);
    velocityRef.current = 0;
    heightRef.current = 0;
    lastTimeRef.current = null;

    const handleMotion = (e: DeviceMotionEvent) => {
      const acc = e.accelerationIncludingGravity?.z ?? 0;
      const now = e.timeStamp;
      if (lastTimeRef.current === null) lastTimeRef.current = now;
      const dt = (now - lastTimeRef.current) / 1000;
      lastTimeRef.current = now;
      velocityRef.current += acc * dt;
      heightRef.current += velocityRef.current * dt;
      if (heightRef.current > maxHeight) setMaxHeight(heightRef.current);
    };

    window.addEventListener('devicemotion', handleMotion);
    timerRef.current = setTimeout(() => {
      window.removeEventListener('devicemotion', handleMotion);
      setRunning(false);
    }, 5000);
  };

  const resetGame = () => {
    if (timerRef.current) clearTimeout(timerRef.current);
    setRunning(false);
    setMaxHeight(0);
  };

  if (!permissionGranted) {
    return <p className="text-center">Permiso para acceder al acelerómetro denegado o no disponible.</p>;
  }

  if (!hasMotion) {
    return <p className="text-center">No se detectó acelerómetro en este dispositivo.</p>;
  }

  return (
    <div className="flex flex-col items-center gap-4">
      <p>Altura máxima: {maxHeight.toFixed(2)} m</p>
      <button
        onClick={startGame}
        disabled={running}
        className="px-4 py-2 bg-blue-500 text-white rounded disabled:bg-gray-400"
      >{running ? 'Lanzando...' : 'Iniciar Lanzamiento'}</button>
      {running && (
        <button
          onClick={resetGame}
          className="px-4 py-2 bg-red-500 text-white rounded"
        >Cancelar</button>
      )}
    </div>
  );
};

export default KamikazeClassic;
