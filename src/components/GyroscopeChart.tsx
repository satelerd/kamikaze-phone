import React, { useState, useEffect } from 'react';
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

  const requestGyroscopePermission = async () => {
    if (typeof (DeviceOrientationEvent as any).requestPermission === 'function') {
      try {
        const permission = await (DeviceOrientationEvent as any).requestPermission();
        setPermissionGranted(permission === 'granted');
      } catch (error) {
        console.error('Error requesting gyroscope permission:', error);
      }
    } else {
      setPermissionGranted(true);
    }
    setPermissionAttempted(true);
  };

  useEffect(() => {
    requestGyroscopePermission();
  }, []);

  useEffect(() => {
    if (!permissionGranted) return;

    const handleOrientation = (event: DeviceOrientationEvent) => {
      setGyroData({
        x: event.beta || 0,
        y: event.gamma || 0,
        z: event.alpha || 0,
      });

      setDataPoints(prev => {
        const newPoints = prev.map((axis, i) => [
          ...axis,
          [event.beta, event.gamma, event.alpha][i] || 0
        ].slice(-20));
        return newPoints;
      });
    };

    window.addEventListener('deviceorientation', handleOrientation);
    return () => window.removeEventListener('deviceorientation', handleOrientation);
  }, [permissionGranted]);

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

  if (!permissionGranted) {
    return (
      <div className="text-center">
        <p>No se concedieron permisos para acceder al giroscopio.</p>
        <button 
          onClick={requestGyroscopePermission}
          className="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
        >
          Intentar de nuevo
        </button>
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

export default GyroscopeChart;