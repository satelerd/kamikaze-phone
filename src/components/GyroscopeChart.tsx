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
  const [dataPoints, setDataPoints] = useState<{x: number, y: number, z: number}[]>([]);
  const [permissionAttempted, setPermissionAttempted] = useState(false);
  const [hasGyroscope, setHasGyroscope] = useState(true);
  const [isLoading, setIsLoading] = useState(true);
  const [chartRange, setChartRange] = useState({ min: -360, max: 360 });
  const [activeAxes, setActiveAxes] = useState({ x: true, y: true, z: true });

  const checkGyroscopeAvailability = useCallback(() => {
    if (typeof window !== 'undefined' && 'DeviceOrientationEvent' in window) {
      const checkOrientation = (event: DeviceOrientationEvent) => {
        if (event.alpha !== null && event.beta !== null && event.gamma !== null) {
          setHasGyroscope(true);
          setIsLoading(false);
          window.removeEventListener('deviceorientation', checkOrientation);
        }
      };

      window.addEventListener('deviceorientation', checkOrientation);

      setTimeout(() => {
        window.removeEventListener('deviceorientation', checkOrientation);
        setIsLoading(false);
        setHasGyroscope(false);
      }, 2000);
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
    checkGyroscopeAvailability();
  };

  useEffect(() => {
    requestGyroscopePermission();
  }, []);

  const updateGyroData = useCallback((x: number, y: number, z: number) => {
    setGyroData({ x, y, z });
    setDataPoints(prev => {
      const newPoint = { x, y, z };
      const newPoints = [...prev, newPoint];
      
      if (newPoints.length > 500) {
        newPoints.shift();
      }
      
      if (newPoints.length % 10 === 0) {
        const activeAxes = [
          x !== null ? 'x' : null,
          y !== null ? 'y' : null,
          z !== null ? 'z' : null
        ].filter(Boolean) as ('x' | 'y' | 'z')[];

        const allValues = newPoints.flatMap(p => 
          activeAxes.map(axis => p[axis])
        );

        const minValue = Math.min(...allValues);
        const maxValue = Math.max(...allValues);
        setChartRange(prevRange => ({
          min: Math.min(prevRange.min, minValue, -10),
          max: Math.max(prevRange.max, maxValue, 10)
        }));
      }

      return newPoints;
    });
  }, []);

  useEffect(() => {
    if (!permissionGranted || !hasGyroscope) return;

    let lastUpdateTime = Date.now();
    let heartbeatInterval: NodeJS.Timeout;
    let checkInterval: NodeJS.Timeout;

    const handleOrientation = (event: DeviceOrientationEvent) => {
      lastUpdateTime = Date.now();
      updateGyroData(event.beta || 0, event.gamma || 0, event.alpha || 0);
      console.log('Gyroscope data updated:', { beta: event.beta, gamma: event.gamma, alpha: event.alpha });
    };

    const checkGyroscopeStatus = () => {
      const timeSinceLastUpdate = Date.now() - lastUpdateTime;
      console.log('Checking gyroscope status:', { timeSinceLastUpdate });
      if (timeSinceLastUpdate > 5000) {
        console.log('Gyroscope potentially disconnected, attempting to reactivate');
        window.removeEventListener('deviceorientation', handleOrientation);
        window.addEventListener('deviceorientation', handleOrientation);
      }
      if (timeSinceLastUpdate > 10000) {
        console.log('Gyroscope disconnected');
        setHasGyroscope(false);
        window.removeEventListener('deviceorientation', handleOrientation);
        clearInterval(heartbeatInterval);
        clearInterval(checkInterval);
      }
    };

    const gyroscopeHeartbeat = () => {
      if ('DeviceMotionEvent' in window) {
        window.dispatchEvent(new DeviceMotionEvent('devicemotion'));
      }
    };

    window.addEventListener('deviceorientation', handleOrientation);
    heartbeatInterval = setInterval(gyroscopeHeartbeat, 500);
    checkInterval = setInterval(checkGyroscopeStatus, 1000);

    return () => {
      window.removeEventListener('deviceorientation', handleOrientation);
      clearInterval(heartbeatInterval);
      clearInterval(checkInterval);
    };
  }, [permissionGranted, hasGyroscope, updateGyroData]);

  const handleJoystickMove = (x: number, y: number, z: number) => {
    if (!hasGyroscope) {
      const simulatedX = y * 180; // -90 a 90 grados
      const simulatedY = x * 180; // -90 a 90 grados
      const simulatedZ = z * 360; // 0 a 360 grados
      updateGyroData(simulatedX, simulatedY, simulatedZ);
    }
  };

  const chartData = {
    datasets: [
      { 
        label: 'X', 
        data: activeAxes.x ? dataPoints.map((p, index) => ({ x: index, y: p.x })) : [],
        borderColor: 'rgb(255, 99, 132)', 
        tension: 0.1 
      },
      { 
        label: 'Y', 
        data: activeAxes.y ? dataPoints.map((p, index) => ({ x: index, y: p.y })) : [],
        borderColor: 'rgb(54, 162, 235)', 
        tension: 0.1 
      },
      { 
        label: 'Z', 
        data: activeAxes.z ? dataPoints.map((p, index) => ({ x: index, y: p.z })) : [],
        borderColor: 'rgb(75, 192, 192)', 
        tension: 0.1 
      },
    ],
  };

  const options = {
    responsive: true,
    scales: {
      x: {
        type: 'linear' as const,
        position: 'bottom' as const,
        min: 0,
        max: Math.max(100, dataPoints.length),
        ticks: {
          stepSize: 10,
        },
      },
      y: {
        beginAtZero: false,
        min: chartRange.min,
        max: chartRange.max,
      },
    },
    animation: {
      duration: 0,
    },
    plugins: {
      legend: {
        position: 'top' as const,
      },
    },
    maintainAspectRatio: false,
  };

  const retryGyroscopeConnection = useCallback(() => {
    console.log('Retrying gyroscope connection');
    setIsLoading(true);
    setHasGyroscope(true);
    setPermissionAttempted(false);
    checkGyroscopeAvailability();
    requestGyroscopePermission();
  }, [checkGyroscopeAvailability, requestGyroscopePermission]);

  useEffect(() => {
    if (!hasGyroscope && permissionGranted) {
      const retryTimer = setTimeout(() => {
        retryGyroscopeConnection();
      }, 3000);

      return () => clearTimeout(retryTimer);
    }
  }, [hasGyroscope, permissionGranted, retryGyroscopeConnection]);

  const toggleAxis = (axis: 'x' | 'y' | 'z') => {
    setActiveAxes(prev => ({ ...prev, [axis]: !prev[axis] }));
  };

  if (isLoading) {
    return <div className="text-center">Cargando...</div>;
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
        <p>{!permissionGranted 
          ? "No se concedieron permisos para acceder al giroscopio." 
          : "No se detectó giroscopio. Usando controles virtuales."}
        </p>
        {!permissionGranted && (
          <button 
            onClick={requestGyroscopePermission}
            className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
          >
            Intentar de nuevo
          </button>
        )}
        <button 
          onClick={retryGyroscopeConnection}
          className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
        >
          Volver a intentar conexión con giroscopio
        </button>
        {permissionGranted && !hasGyroscope && <VirtualControls onMove={handleJoystickMove} />}
        <div className="mt-4">
          <div style={{ height: '400px' }}>
            <Line data={chartData} options={options} />
          </div>
          <div className="mt-4 text-center">
            <p>X: {gyroData.x.toFixed(2)}° <button onClick={() => toggleAxis('x')}>{activeAxes.x ? 'Desactivar' : 'Activar'}</button></p>
            <p>Y: {gyroData.y.toFixed(2)}° <button onClick={() => toggleAxis('y')}>{activeAxes.y ? 'Desactivar' : 'Activar'}</button></p>
            <p>Z: {gyroData.z.toFixed(2)}° <button onClick={() => toggleAxis('z')}>{activeAxes.z ? 'Desactivar' : 'Activar'}</button></p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="w-full max-w-2xl">
      <div style={{ height: '400px' }}>
        <Line data={chartData} options={options} />
      </div>
      <div className="mt-4 text-center">
        <p>X: {gyroData.x.toFixed(2)}° <button onClick={() => toggleAxis('x')}>{activeAxes.x ? 'Desactivar' : 'Activar'}</button></p>
        <p>Y: {gyroData.y.toFixed(2)}° <button onClick={() => toggleAxis('y')}>{activeAxes.y ? 'Desactivar' : 'Activar'}</button></p>
        <p>Z: {gyroData.z.toFixed(2)}° <button onClick={() => toggleAxis('z')}>{activeAxes.z ? 'Desactivar' : 'Activar'}</button></p>
      </div>
      <button 
        onClick={retryGyroscopeConnection}
        className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
      >
        Volver a intentar conexión con giroscopio
      </button>
      {!hasGyroscope && <VirtualControls onMove={handleJoystickMove} />}
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