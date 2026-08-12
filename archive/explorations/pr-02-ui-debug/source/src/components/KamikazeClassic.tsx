'use client';
import React, { useState, useRef } from 'react';
import useSensorPermissions from '../hooks/useSensorPermissions';

const KamikazeClassic = () => {
  const { granted, request } = useSensorPermissions();
  const [running, setRunning] = useState(false);
  const [maxHeight, setMaxHeight] = useState(0);
  const [debugInfo, setDebugInfo] = useState<{acc:number;vel:number;height:number}[]>([]);

  const velocityRef = useRef(0);
  const heightRef = useRef(0);
  const lastTimeRef = useRef<number | null>(null);

  const startGame = async () => {
    if (!granted) {
      await request();
      if (!granted) return;
    }
    setRunning(true);
    setMaxHeight(0);
    velocityRef.current = 0;
    heightRef.current = 0;
    lastTimeRef.current = null;
    setDebugInfo([]);

    const handleMotion = (e: DeviceMotionEvent) => {
      const acc = e.acceleration?.y ?? 0; // y axis usually vertical
      const now = e.timeStamp;
      if (lastTimeRef.current === null) lastTimeRef.current = now;
      const dt = (now - lastTimeRef.current) / 1000;
      lastTimeRef.current = now;
      const netAcc = acc;
      velocityRef.current += netAcc * dt;
      heightRef.current += velocityRef.current * dt;
      if (heightRef.current > maxHeight) setMaxHeight(heightRef.current);
      setDebugInfo((info) => [...info.slice(-20), {acc: netAcc, vel: velocityRef.current, height: heightRef.current}]);
    };

    window.addEventListener('devicemotion', handleMotion);
    setTimeout(() => {
      window.removeEventListener('devicemotion', handleMotion);
      setRunning(false);
    }, 5000);
  };

  return (
    <div className="flex flex-col items-center gap-4">
      <p className="text-lg">Altura máxima: {maxHeight.toFixed(2)} m</p>
      <button onClick={startGame} disabled={running} className="px-4 py-2 bg-blue-500 rounded disabled:bg-gray-400">
        {running ? 'Midiendo...' : 'Iniciar'}
      </button>
      {debugInfo.length > 0 && (
        <div className="w-full max-w-sm text-xs bg-gray-800 p-2 rounded">
          {debugInfo.map((d, i) => (
            <p key={i}>a:{d.acc.toFixed(2)} v:{d.vel.toFixed(2)} h:{d.height.toFixed(2)}</p>
          ))}
        </div>
      )}
    </div>
  );
};

export default KamikazeClassic;
