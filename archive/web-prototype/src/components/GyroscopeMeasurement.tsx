'use client';

import React, { useState, useEffect, useCallback } from 'react';
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

const GyroscopeMeasurement = () => {
  const [gyroData, setGyroData] = useState<{x: number, y: number, z: number}[]>([]);
  const [isMeasuring, setIsMeasuring] = useState(false);
  const [permissionGranted, setPermissionGranted] = useState(false);
  const [hasGyroscope, setHasGyroscope] = useState(true);
  const [activeAxes, setActiveAxes] = useState({ x: true, y: true, z: true });

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
  };

  useEffect(() => {
    requestGyroscopePermission();
  }, []);

  const startMeasurement = useCallback(() => {
    setGyroData([]);
    setIsMeasuring(true);

    const handleOrientation = (event: DeviceOrientationEvent) => {
      setGyroData(prev => [...prev, {
        x: event.beta || 0,
        y: event.gamma || 0,
        z: event.alpha || 0
      }]);
    };

    window.addEventListener('deviceorientation', handleOrientation);

    setTimeout(() => {
      window.removeEventListener('deviceorientation', handleOrientation);
      setIsMeasuring(false);
    }, 2500);
  }, []);

  const toggleAxis = (axis: 'x' | 'y' | 'z') => {
    setActiveAxes(prev => ({ ...prev, [axis]: !prev[axis] }));
  };

  const chartData = {
    labels: gyroData.map((_, index) => index),
    datasets: [
      {
        label: 'X',
        data: activeAxes.x ? gyroData.map(d => d.x) : [],
        borderColor: 'rgb(255, 99, 132)',
        tension: 0.1
      },
      {
        label: 'Y',
        data: activeAxes.y ? gyroData.map(d => d.y) : [],
        borderColor: 'rgb(54, 162, 235)',
        tension: 0.1
      },
      {
        label: 'Z',
        data: activeAxes.z ? gyroData.map(d => d.z) : [],
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
        max: gyroData.length - 1,
      },
      y: {
        beginAtZero: false,
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

  if (!permissionGranted) {
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

  if (!hasGyroscope) {
    return (
      <div className="text-center">
        <p>No se detectó giroscopio en este dispositivo.</p>
      </div>
    );
  }

  return (
    <div className="w-full max-w-2xl mx-auto">
      <button 
        onClick={startMeasurement}
        disabled={isMeasuring}
        className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:bg-gray-400"
      >
        {isMeasuring ? 'Midiendo...' : 'Iniciar medición (2,5 segundos)'}
      </button>
      <div className="mt-4">
        <div style={{ height: '400px' }}>
          <Line data={chartData} options={options} />
        </div>
        <div className="mt-4 text-center">
          <button onClick={() => toggleAxis('x')} className="mx-2">
            {activeAxes.x ? 'Desactivar X' : 'Activar X'}
          </button>
          <button onClick={() => toggleAxis('y')} className="mx-2">
            {activeAxes.y ? 'Desactivar Y' : 'Activar Y'}
          </button>
          <button onClick={() => toggleAxis('z')} className="mx-2">
            {activeAxes.z ? 'Desactivar Z' : 'Activar Z'}
          </button>
        </div>
      </div>
    </div>
  );
};

export default GyroscopeMeasurement;