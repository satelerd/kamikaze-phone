'use client';

import React, { useState, useEffect, useCallback, useRef } from 'react';
import { Line } from 'react-chartjs-2';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
} from 'chart.js';

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
);

const GyroscopeChart = () => {
  const [gyroData, setGyroData] = useState({ x: 0, y: 0, z: 0 });
  const [permissionGranted, setPermissionGranted] = useState(false);
  const [dataPoints, setDataPoints] = useState<number[][]>([[], [], []]);
  const [permissionAttempted, setPermissionAttempted] = useState(false);
  const [hasGyroscope, setHasGyroscope] = useState(true);
  const [isLoading, setIsLoading] = useState(true);

  const checkGyroscopeAvailability = useCallback(() => {
    if (typeof window !== 'undefined' && 'DeviceOrientationEvent' in window) {
      // Intentar acceder al evento de orientación
      window.addEventListener('deviceorientation', function(event) {
        if (event.alpha !== null && event.beta !== null && event.gamma !== null) {
          setHasGyroscope(true);
        } else {
          setHasGyroscope(false);
        }
        setIsLoading(false);
      }, { once: true });

      // Si después de 1 segundo no se ha detectado el evento, asumimos que no hay giroscopio
      setTimeout(() => {
        setIsLoading(false);
        setHasGyroscope(false);
      }, 1000);
    } else {
      setHasGyroscope(false);
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    checkGyroscopeAvailability();
  }, [checkGyroscopeAvailability]);

  const requestGyroscopePermission = async () => {
    if (typeof (DeviceOrientationEvent as any).requestPermission === 'function') {
      try {
        const permission = await (DeviceOrientationEvent as any).requestPermission();
        setPermissionGranted(permission === 'granted');
      } catch (error) {
        console.error('Error requesting gyroscope permission:', error);
        setHasGyroscope(false);
      }
    } else {
      setPermissionGranted(true);
    }
    setPermissionAttempted(true);
  };

  useEffect(() => {
    requestGyroscopePermission();
  }, []);

  const updateGyroData = useCallback((x: number, y: number, z: number) => {
    setGyroData({ x, y, z });
    setDataPoints(prev => {
      const newPoints = [
        [...prev[0], x],
        [...prev[1], y],
        [...prev[2], z]
      ].map(axis => axis.slice(-20));
      return newPoints;
    });
  }, []);

  useEffect(() => {
    if (!permissionGranted || !hasGyroscope) return;

    const handleOrientation = (event: DeviceOrientationEvent) => {
      updateGyroData(event.beta || 0, event.gamma || 0, event.alpha || 0);
    };

    window.addEventListener('deviceorientation', handleOrientation);
    return () => window.removeEventListener('deviceorientation', handleOrientation);
  }, [permissionGranted, hasGyroscope, updateGyroData]);

  const handleJoystickMove = (x: number, y: number, z: number) => {
    const simulatedX = y * 90; // -90 a 90 grados
    const simulatedY = x * 90; // -90 a 90 grados
    const simulatedZ = z * 360; // 0 a 360 grados
    updateGyroData(simulatedX, simulatedY, simulatedZ);
  };

  const chartData = {
    labels: Array(20).fill(''),
    datasets: [
      { label: 'X', data: dataPoints[0], borderColor: 'rgb(255, 99, 132)', tension: 0.1 },
      { label: 'Y', data: dataPoints[1], borderColor: 'rgb(54, 162, 235)', tension: 0.1 },
      { label: 'Z', data: dataPoints[2], borderColor: 'rgb(75, 192, 192)', tension: 0.1 },
    ],
  };

  const options = {
    responsive: true,
    scales: {
      y: {
        beginAtZero: true,
        max: 360,
        min: -360,
      },
    },
    animation: {
      duration: 0,
    },
  };

  if (isLoading) {
    return <div className="text-center">Cargando...</div>;
  }

  if (!hasGyroscope) {
    return (
      <div className="text-center">
        <p>No se detectó giroscopio. Usando controles virtuales.</p>
        <VirtualControls onMove={handleJoystickMove} />
        <div className="mt-4">
          <Line data={chartData} options={options} />
          <div className="mt-4 text-center">
            <p>X: {gyroData.x.toFixed(2)}°</p>
            <p>Y: {gyroData.y.toFixed(2)}°</p>
            <p>Z: {gyroData.z.toFixed(2)}°</p>
          </div>
        </div>
      </div>
    );
  }

  if (!permissionAttempted) {
    return (
      <div className="text-center">
        <p>Se requieren permisos para acceder al giroscopio.</p>
        <button 
          onClick={requestGyroscopePermission}
          className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
        >
          Solicitar permisos
        </button>
      </div>
    );
  }

  if (!permissionGranted || !hasGyroscope) {
    return (
      <div className="text-center">
        <p>{hasGyroscope ? "No se concedieron permisos para acceder al giroscopio." : "No se detectó giroscopio. Usando joystick virtual."}</p>
        {hasGyroscope && (
          <button 
            onClick={requestGyroscopePermission}
            className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
          >
            Intentar de nuevo
          </button>
        )}
        {!hasGyroscope && <VirtualControls onMove={handleJoystickMove} />}
      </div>
    );
  }

  return (
    <div className="w-full max-w-2xl">
      <Line data={chartData} options={options} />
      <div className="mt-4 text-center">
        <p>X: {gyroData.x.toFixed(2)}°</p>
        <p>Y: {gyroData.y.toFixed(2)}°</p>
        <p>Z: {gyroData.z.toFixed(2)}°</p>
      </div>
    </div>
  );
};

const VirtualControls = ({ onMove }: { onMove: (x: number, y: number, z: number) => void }) => {
  const [position, setPosition] = useState({ x: 0, y: 0, z: 0 });
  const joystickRef = useRef<HTMLDivElement>(null);

  const handleMouseMove = useCallback((e: MouseEvent) => {
    if (!joystickRef.current) return;
    const rect = joystickRef.current.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width * 2 - 1;
    const y = -((e.clientY - rect.top) / rect.height * 2 - 1);
    const newPosition = { 
      x: Math.max(-1, Math.min(1, x)), 
      y: Math.max(-1, Math.min(1, y)), 
      z: position.z 
    };
    setPosition(newPosition);
    onMove(newPosition.x, newPosition.y, newPosition.z);
  }, [onMove, position.z]);

  const handleMouseUp = useCallback(() => {
    document.removeEventListener('mousemove', handleMouseMove);
    document.removeEventListener('mouseup', handleMouseUp);
    setPosition(prev => ({ x: 0, y: 0, z: prev.z }));
    onMove(0, 0, position.z);
  }, [handleMouseMove, onMove, position.z]);

  const handleMouseDown = useCallback(() => {
    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
  }, [handleMouseMove, handleMouseUp]);

  const handleZChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newZ = parseFloat(e.target.value);
    setPosition(prev => ({ ...prev, z: newZ }));
    onMove(position.x, position.y, newZ);
  };

  return (
    <div className="flex flex-col items-center">
      <div 
        ref={joystickRef}
        className="w-48 h-48 bg-gray-200 rounded-full relative cursor-pointer mb-4"
        onMouseDown={handleMouseDown}
      >
        <div 
          className="w-12 h-12 bg-blue-500 rounded-full absolute"
          style={{
            left: `${(position.x + 1) * 50 - 12}%`,
            top: `${(-position.y + 1) * 50 - 12}%`,
          }}
        />
      </div>
      <div className="w-48 flex items-center">
        <span className="mr-2">Z:</span>
        <input 
          type="range" 
          min="0" 
          max="1" 
          step="0.01" 
          value={position.z} 
          onChange={handleZChange}
          className="w-full"
        />
        <span className="ml-2">{(position.z * 360).toFixed(0)}°</span>
      </div>
    </div>
  );
};

export default GyroscopeChart;