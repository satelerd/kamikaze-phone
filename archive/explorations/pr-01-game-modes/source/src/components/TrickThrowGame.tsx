'use client';

import React, { useState, useEffect, useRef } from 'react';

const TrickThrowGame = () => {
  const [permissionGranted, setPermissionGranted] = useState(false);
  const [hasSensors, setHasSensors] = useState(true);
  const [score, setScore] = useState(0);
  const [flips, setFlips] = useState(0);
  const [running, setRunning] = useState(false);

  const velocityRef = useRef(0);
  const heightRef = useRef(0);
  const lastTimeRef = useRef<number | null>(null);
  const rotXRef = useRef(0);
  const rotYRef = useRef(0);
  const rotZRef = useRef(0);
  const lastOrientationRef = useRef<{alpha:number;beta:number;gamma:number}|null>(null);

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const request = async () => {
      try {
        if (typeof (DeviceOrientationEvent as any).requestPermission === 'function') {
          const perm = await (DeviceOrientationEvent as any).requestPermission();
          setPermissionGranted(perm === 'granted');
        } else {
          setPermissionGranted(true);
        }
      } catch {
        setHasSensors(false);
      }
    };
    request();
  }, []);

  const startGame = () => {
    if (!permissionGranted) return;
    setRunning(true);
    setFlips(0);
    setScore(0);
    velocityRef.current = 0;
    heightRef.current = 0;
    rotXRef.current = 0;
    rotYRef.current = 0;
    rotZRef.current = 0;
    lastTimeRef.current = null;
    lastOrientationRef.current = null;

    const handleMotion = (e: DeviceMotionEvent) => {
      const acc = e.accelerationIncludingGravity?.z ?? 0;
      const now = e.timeStamp;
      if (lastTimeRef.current === null) lastTimeRef.current = now;
      const dt = (now - lastTimeRef.current) / 1000;
      lastTimeRef.current = now;
      velocityRef.current += acc * dt;
      heightRef.current += velocityRef.current * dt;
    };

    const handleOrientation = (e: DeviceOrientationEvent) => {
      if (lastOrientationRef.current === null) {
        lastOrientationRef.current = {alpha:e.alpha||0,beta:e.beta||0,gamma:e.gamma||0};
        return;
      }
      const prev = lastOrientationRef.current;
      const dA = ((e.alpha||0) - prev.alpha);
      const dB = ((e.beta||0) - prev.beta);
      const dG = ((e.gamma||0) - prev.gamma);
      rotXRef.current += dB;
      rotYRef.current += dG;
      rotZRef.current += dA;
      lastOrientationRef.current = {alpha:e.alpha||0,beta:e.beta||0,gamma:e.gamma||0};
      if (Math.abs(rotXRef.current) >= 360 || Math.abs(rotYRef.current) >= 360) {
        setFlips(f => f + 1);
        rotXRef.current = 0;
        rotYRef.current = 0;
      }
    };

    window.addEventListener('devicemotion', handleMotion);
    window.addEventListener('deviceorientation', handleOrientation);

    setTimeout(() => {
      window.removeEventListener('devicemotion', handleMotion);
      window.removeEventListener('deviceorientation', handleOrientation);
      setRunning(false);
      const points = Math.max(heightRef.current, 0) + flips * 100;
      setScore(points);
    }, 5000);
  };

  if (!permissionGranted) {
    return <p className="text-center">Se requieren permisos de sensores.</p>;
  }

  if (!hasSensors) {
    return <p className="text-center">Sensores no disponibles.</p>;
  }

  return (
    <div className="flex flex-col items-center gap-4">
      <p>Flips: {flips}</p>
      <p>Puntuación: {score.toFixed(0)}</p>
      <button
        onClick={startGame}
        disabled={running}
        className="px-4 py-2 bg-blue-500 text-white rounded disabled:bg-gray-400"
      >{running ? 'Jugando...' : 'Iniciar'}</button>
    </div>
  );
};

export default TrickThrowGame;
