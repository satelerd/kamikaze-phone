'use client';
import React, { useState, useRef } from 'react';
import useSensorPermissions from '../hooks/useSensorPermissions';

const TrickThrowGame = () => {
  const { granted, request } = useSensorPermissions();
  const [running, setRunning] = useState(false);
  const [flips, setFlips] = useState(0);
  const [score, setScore] = useState(0);
  const [debug, setDebug] = useState<{rot:number;height:number}[]>([]);

  const velocityRef = useRef(0);
  const heightRef = useRef(0);
  const lastTimeRef = useRef<number | null>(null);
  const rotXRef = useRef(0);
  const lastOrientationRef = useRef<{beta:number} | null>(null);

  const startGame = async () => {
    if (!granted) {
      await request();
      if (!granted) return;
    }
    setRunning(true);
    setFlips(0);
    setScore(0);
    velocityRef.current = 0;
    heightRef.current = 0;
    rotXRef.current = 0;
    lastTimeRef.current = null;
    lastOrientationRef.current = null;
    setDebug([]);

    const handleMotion = (e: DeviceMotionEvent) => {
      const acc = e.acceleration?.y ?? 0;
      const now = e.timeStamp;
      if (lastTimeRef.current === null) lastTimeRef.current = now;
      const dt = (now - lastTimeRef.current) / 1000;
      lastTimeRef.current = now;
      velocityRef.current += acc * dt;
      heightRef.current += velocityRef.current * dt;
    };

    const handleOrientation = (e: DeviceOrientationEvent) => {
      if (lastOrientationRef.current === null) {
        lastOrientationRef.current = { beta: e.beta || 0 };
        return;
      }
      const diff = (e.beta || 0) - lastOrientationRef.current.beta;
      rotXRef.current += diff;
      lastOrientationRef.current = { beta: e.beta || 0 };
      if (Math.abs(rotXRef.current) >= 360) {
        setFlips(f => f + 1);
        rotXRef.current = 0;
      }
      setDebug((d) => [...d.slice(-20), {rot: rotXRef.current, height: heightRef.current}]);
    };

    window.addEventListener('devicemotion', handleMotion);
    window.addEventListener('deviceorientation', handleOrientation);
    setTimeout(() => {
      window.removeEventListener('devicemotion', handleMotion);
      window.removeEventListener('deviceorientation', handleOrientation);
      setRunning(false);
      setScore(Math.max(heightRef.current, 0) + flips * 100);
    }, 5000);
  };

  return (
    <div className="flex flex-col items-center gap-4">
      <p>Flips: {flips}</p>
      <p>Puntuación: {score.toFixed(0)}</p>
      <button onClick={startGame} disabled={running} className="px-4 py-2 bg-blue-500 rounded disabled:bg-gray-400">
        {running ? 'Jugando...' : 'Iniciar'}
      </button>
      {debug.length > 0 && (
        <div className="w-full max-w-sm text-xs bg-gray-800 p-2 rounded">
          {debug.map((d, i) => (
            <p key={i}>r:{d.rot.toFixed(1)} h:{d.height.toFixed(2)}</p>
          ))}
        </div>
      )}
    </div>
  );
};

export default TrickThrowGame;
