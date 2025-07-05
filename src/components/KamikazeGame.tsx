'use client';

import React, { useState, useEffect, useCallback, useRef } from 'react';

interface DebugInfo {
  accelerometerData: { x: number; y: number; z: number };
  gyroscopeData: { x: number; y: number; z: number };
  deviceOrientation: { alpha: number; beta: number; gamma: number };
  lastUpdate: number;
  permissionStatus: string;
  sensorStatus: string;
  throwDetected: boolean;
  flipCount: number;
  maxHeight: number;
}

interface GameState {
  mode: 'menu' | 'kamikaze' | 'flip' | 'debug';
  isPlaying: boolean;
  score: number;
  highScore: number;
  gameStartTime: number;
  throwStartTime: number;
  isThrowActive: boolean;
}

interface SensorData {
  acceleration: { x: number; y: number; z: number };
  rotation: { x: number; y: number; z: number };
  orientation: { alpha: number; beta: number; gamma: number };
}

const KamikazeGame: React.FC = () => {
  const [gameState, setGameState] = useState<GameState>({
    mode: 'menu',
    isPlaying: false,
    score: 0,
    highScore: parseInt(localStorage.getItem('kamikazeHighScore') || '0'),
    gameStartTime: 0,
    throwStartTime: 0,
    isThrowActive: false,
  });

  const [sensorData, setSensorData] = useState<SensorData>({
    acceleration: { x: 0, y: 0, z: 0 },
    rotation: { x: 0, y: 0, z: 0 },
    orientation: { alpha: 0, beta: 0, gamma: 0 },
  });

  const [debugInfo, setDebugInfo] = useState<DebugInfo>({
    accelerometerData: { x: 0, y: 0, z: 0 },
    gyroscopeData: { x: 0, y: 0, z: 0 },
    deviceOrientation: { alpha: 0, beta: 0, gamma: 0 },
    lastUpdate: 0,
    permissionStatus: 'pending',
    sensorStatus: 'checking',
    throwDetected: false,
    flipCount: 0,
    maxHeight: 0,
  });

  const [permissions, setPermissions] = useState({
    deviceMotion: false,
    deviceOrientation: false,
  });

  const [logs, setLogs] = useState<string[]>([]);
  const [flipData, setFlipData] = useState({
    totalFlips: 0,
    flipTypes: [] as string[],
    maxRotationSpeed: 0,
  });

  const gameLoopRef = useRef<number | null>(null);
  const sensorDataRef = useRef<SensorData>(sensorData);
  const throwDetectionRef = useRef({
    isThrowActive: false,
    throwStartTime: 0,
    maxAcceleration: 0,
    initialOrientation: { alpha: 0, beta: 0, gamma: 0 },
  });

  const addLog = useCallback((message: string) => {
    const timestamp = new Date().toLocaleTimeString();
    setLogs((prev: string[]) => [`[${timestamp}] ${message}`, ...prev.slice(0, 19)]);
  }, []);

  const requestPermissions = useCallback(async () => {
    addLog('Solicitando permisos de sensores...');
    
    try {
             // Request DeviceMotionEvent permission (iOS 13+)
       if (typeof (DeviceMotionEvent as any).requestPermission === 'function') {
         const motionPermission = await (DeviceMotionEvent as any).requestPermission();
         setPermissions((prev: any) => ({ ...prev, deviceMotion: motionPermission === 'granted' }));
         addLog(`Permiso DeviceMotion: ${motionPermission}`);
       } else {
         setPermissions((prev: any) => ({ ...prev, deviceMotion: true }));
         addLog('DeviceMotion: Granted (no permission needed)');
       }

       // Request DeviceOrientationEvent permission (iOS 13+)
       if (typeof (DeviceOrientationEvent as any).requestPermission === 'function') {
         const orientationPermission = await (DeviceOrientationEvent as any).requestPermission();
         setPermissions((prev: any) => ({ ...prev, deviceOrientation: orientationPermission === 'granted' }));
         addLog(`Permiso DeviceOrientation: ${orientationPermission}`);
       } else {
         setPermissions((prev: any) => ({ ...prev, deviceOrientation: true }));
         addLog('DeviceOrientation: Granted (no permission needed)');
       }

       setDebugInfo((prev: DebugInfo) => ({ ...prev, permissionStatus: 'granted' }));
         } catch (error) {
       addLog(`Error solicitando permisos: ${error}`);
       setDebugInfo((prev: DebugInfo) => ({ ...prev, permissionStatus: 'denied' }));
     }
  }, [addLog]);

  const detectThrow = useCallback((accel: { x: number; y: number; z: number }) => {
    const totalAcceleration = Math.sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z);
    
    // Detectar inicio de lanzamiento (aceleración alta)
    if (totalAcceleration > 15 && !throwDetectionRef.current.isThrowActive) {
      throwDetectionRef.current.isThrowActive = true;
      throwDetectionRef.current.throwStartTime = Date.now();
      throwDetectionRef.current.maxAcceleration = totalAcceleration;
      throwDetectionRef.current.initialOrientation = { ...sensorDataRef.current.orientation };
      
      setDebugInfo(prev => ({ ...prev, throwDetected: true }));
      addLog(`🚀 Lanzamiento detectado! Aceleración: ${totalAcceleration.toFixed(2)} m/s²`);
      
      setGameState(prev => ({
        ...prev,
        throwStartTime: Date.now(),
        isThrowActive: true,
      }));
    }
    
    // Detectar fin de lanzamiento (aceleración baja, caída libre)
    if (totalAcceleration < 5 && throwDetectionRef.current.isThrowActive) {
      const throwDuration = Date.now() - throwDetectionRef.current.throwStartTime;
      const heightScore = Math.floor(throwDetectionRef.current.maxAcceleration * throwDuration / 100);
      
      setGameState(prev => ({
        ...prev,
        score: prev.score + heightScore,
        isThrowActive: false,
      }));
      
      setDebugInfo(prev => ({ 
        ...prev, 
        throwDetected: false,
        maxHeight: Math.max(prev.maxHeight, heightScore)
      }));
      
      addLog(`✅ Lanzamiento completado! Puntos: ${heightScore} (Duración: ${throwDuration}ms)`);
      
      throwDetectionRef.current.isThrowActive = false;
      throwDetectionRef.current.maxAcceleration = 0;
    }
    
    // Actualizar máxima aceleración durante el lanzamiento
    if (throwDetectionRef.current.isThrowActive) {
      throwDetectionRef.current.maxAcceleration = Math.max(
        throwDetectionRef.current.maxAcceleration,
        totalAcceleration
      );
    }
  }, [addLog]);

  const detectFlips = useCallback((rotation: { x: number; y: number; z: number }) => {
    const rotationSpeed = Math.sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z);
    
    if (rotationSpeed > 200) { // Umbral para detectar flip
      setFlipData(prev => {
        const newFlipCount = prev.totalFlips + 1;
        const flipTypes = [...prev.flipTypes];
        
        // Determinar tipo de flip basado en el eje dominante
        if (Math.abs(rotation.x) > Math.abs(rotation.y) && Math.abs(rotation.x) > Math.abs(rotation.z)) {
          flipTypes.push(rotation.x > 0 ? 'Frontside Flip' : 'Backside Flip');
        } else if (Math.abs(rotation.y) > Math.abs(rotation.z)) {
          flipTypes.push(rotation.y > 0 ? 'Kickflip' : 'Heelflip');
        } else {
          flipTypes.push(rotation.z > 0 ? '360 Spin' : 'Reverse 360');
        }
        
        setDebugInfo(prev => ({ ...prev, flipCount: newFlipCount }));
        addLog(`🔄 Flip detectado! Tipo: ${flipTypes[flipTypes.length - 1]} (Total: ${newFlipCount})`);
        
        return {
          totalFlips: newFlipCount,
          flipTypes: flipTypes.slice(-5), // Mantener solo los últimos 5
          maxRotationSpeed: Math.max(prev.maxRotationSpeed, rotationSpeed),
        };
      });
      
      // Puntaje por flip
      setGameState(prev => ({
        ...prev,
        score: prev.score + Math.floor(rotationSpeed / 10),
      }));
    }
  }, [addLog]);

  const initializeSensors = useCallback(() => {
    if (!permissions.deviceMotion || !permissions.deviceOrientation) {
      addLog('❌ Permisos no otorgados, no se pueden inicializar sensores');
      return;
    }

    addLog('🔧 Inicializando sensores...');

    // DeviceMotionEvent para acelerómetro y giroscopio
    const handleDeviceMotion = (event: DeviceMotionEvent) => {
      const acceleration = event.accelerationIncludingGravity || { x: 0, y: 0, z: 0 };
      const rotation = event.rotationRate || { alpha: 0, beta: 0, gamma: 0 };
      
      const newSensorData = {
        ...sensorDataRef.current,
        acceleration: {
          x: acceleration.x || 0,
          y: acceleration.y || 0,
          z: acceleration.z || 0,
        },
        rotation: {
          x: rotation.beta || 0,
          y: rotation.gamma || 0,
          z: rotation.alpha || 0,
        },
      };
      
      sensorDataRef.current = newSensorData;
      setSensorData(newSensorData);
      
      setDebugInfo(prev => ({
        ...prev,
        accelerometerData: newSensorData.acceleration,
        gyroscopeData: newSensorData.rotation,
        lastUpdate: Date.now(),
        sensorStatus: 'active',
      }));
      
      // Detección de lanzamiento en modo Kamikaze
      if (gameState.mode === 'kamikaze' && gameState.isPlaying) {
        detectThrow(newSensorData.acceleration);
      }
      
      // Detección de flips en modo Flip
      if (gameState.mode === 'flip' && gameState.isPlaying) {
        detectFlips(newSensorData.rotation);
      }
    };

    // DeviceOrientationEvent para orientación
    const handleDeviceOrientation = (event: DeviceOrientationEvent) => {
      const orientation = {
        alpha: event.alpha || 0,
        beta: event.beta || 0,
        gamma: event.gamma || 0,
      };
      
      sensorDataRef.current = {
        ...sensorDataRef.current,
        orientation,
      };
      
      setDebugInfo(prev => ({
        ...prev,
        deviceOrientation: orientation,
      }));
    };

    window.addEventListener('devicemotion', handleDeviceMotion);
    window.addEventListener('deviceorientation', handleDeviceOrientation);

    setDebugInfo(prev => ({ ...prev, sensorStatus: 'active' }));
    addLog('✅ Sensores inicializados correctamente');

    return () => {
      window.removeEventListener('devicemotion', handleDeviceMotion);
      window.removeEventListener('deviceorientation', handleDeviceOrientation);
      addLog('🔌 Sensores desconectados');
    };
  }, [permissions, gameState.mode, gameState.isPlaying, detectThrow, detectFlips, addLog]);

  const startGame = useCallback((mode: 'kamikaze' | 'flip') => {
    setGameState(prev => ({
      ...prev,
      mode,
      isPlaying: true,
      score: 0,
      gameStartTime: Date.now(),
    }));
    
    setFlipData({
      totalFlips: 0,
      flipTypes: [],
      maxRotationSpeed: 0,
    });
    
    addLog(`🎮 Iniciando juego en modo ${mode.toUpperCase()}`);
  }, [addLog]);

  const stopGame = useCallback(() => {
    setGameState(prev => {
      const newHighScore = Math.max(prev.highScore, prev.score);
      localStorage.setItem('kamikazeHighScore', newHighScore.toString());
      
      return {
        ...prev,
        mode: 'menu',
        isPlaying: false,
        highScore: newHighScore,
      };
    });
    
    addLog('🏁 Juego terminado');
  }, [addLog]);

  const enterDebugMode = useCallback(() => {
    setGameState(prev => ({ ...prev, mode: 'debug' }));
    addLog('🔍 Modo debug activado');
  }, [addLog]);

  // Inicializar sensores cuando se otorgan permisos
  useEffect(() => {
    if (permissions.deviceMotion && permissions.deviceOrientation) {
      const cleanup = initializeSensors();
      return cleanup;
    }
  }, [permissions, initializeSensors]);

  // Renderizar pantalla de inicio
  if (gameState.mode === 'menu') {
    return (
      <div className="min-h-screen bg-gradient-to-br from-purple-900 via-blue-900 to-indigo-900 flex flex-col items-center justify-center p-4">
        <div className="text-center mb-8 animate-pulse">
          <h1 className="text-6xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-yellow-400 to-red-500 mb-4">
            KAMIKAZE
          </h1>
          <h2 className="text-3xl font-bold text-white mb-2">PHONE</h2>
          <p className="text-gray-300">¡El juego más extremo para tu celular!</p>
        </div>
        
        <div className="space-y-4 w-full max-w-md">
          <button
            onClick={() => startGame('kamikaze')}
            disabled={!permissions.deviceMotion || !permissions.deviceOrientation}
            className="w-full py-4 px-6 bg-gradient-to-r from-red-500 to-pink-500 text-white font-bold text-xl rounded-lg shadow-lg hover:from-red-600 hover:to-pink-600 transform hover:scale-105 transition-all duration-200 disabled:opacity-50"
          >
            🚀 KAMIKAZE NORMAL
          </button>
          
          <button
            onClick={() => startGame('flip')}
            disabled={!permissions.deviceMotion || !permissions.deviceOrientation}
            className="w-full py-4 px-6 bg-gradient-to-r from-blue-500 to-cyan-500 text-white font-bold text-xl rounded-lg shadow-lg hover:from-blue-600 hover:to-cyan-600 transform hover:scale-105 transition-all duration-200 disabled:opacity-50"
          >
            🔄 KAMIKAZE FLIP
          </button>
          
          <button
            onClick={enterDebugMode}
            className="w-full py-3 px-6 bg-gray-700 text-white font-bold rounded-lg shadow-lg hover:bg-gray-600 transform hover:scale-105 transition-all duration-200"
          >
            🔧 Revisa antihiroscopio
          </button>
        </div>
        
        <div className="mt-8 text-center">
          <p className="text-gray-400 mb-4">Record: {gameState.highScore} puntos</p>
          
          {(!permissions.deviceMotion || !permissions.deviceOrientation) && (
            <button
              onClick={requestPermissions}
              className="py-3 px-6 bg-yellow-500 text-black font-bold rounded-lg shadow-lg hover:bg-yellow-400 transform hover:scale-105 transition-all duration-200"
            >
              🔒 Activar permisos de sensores
            </button>
          )}
        </div>
      </div>
    );
  }

  // Renderizar modo debug
  if (gameState.mode === 'debug') {
    return (
      <div className="min-h-screen bg-black text-green-400 p-4 font-mono">
        <div className="max-w-4xl mx-auto">
          <div className="flex justify-between items-center mb-6">
            <h1 className="text-3xl font-bold">🔧 DEBUG MODE</h1>
            <button
              onClick={() => setGameState(prev => ({ ...prev, mode: 'menu' }))}
              className="py-2 px-4 bg-red-600 text-white rounded hover:bg-red-700"
            >
              ← Volver
            </button>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div className="bg-gray-900 p-4 rounded-lg">
              <h2 className="text-xl font-bold mb-4">📱 Estado de Sensores</h2>
              <div className="space-y-2">
                <p>Permisos Motion: {permissions.deviceMotion ? '✅' : '❌'}</p>
                <p>Permisos Orientación: {permissions.deviceOrientation ? '✅' : '❌'}</p>
                <p>Estado: {debugInfo.sensorStatus}</p>
                <p>Última actualización: {debugInfo.lastUpdate ? new Date(debugInfo.lastUpdate).toLocaleTimeString() : 'N/A'}</p>
              </div>
            </div>
            
            <div className="bg-gray-900 p-4 rounded-lg">
              <h2 className="text-xl font-bold mb-4">🎯 Detección de Juego</h2>
              <div className="space-y-2">
                <p>Lanzamiento detectado: {debugInfo.throwDetected ? '✅' : '❌'}</p>
                <p>Flips detectados: {debugInfo.flipCount}</p>
                <p>Altura máxima: {debugInfo.maxHeight}</p>
              </div>
            </div>
            
            <div className="bg-gray-900 p-4 rounded-lg">
              <h2 className="text-xl font-bold mb-4">📊 Acelerómetro</h2>
              <div className="space-y-2">
                <p>X: {debugInfo.accelerometerData.x.toFixed(2)}</p>
                <p>Y: {debugInfo.accelerometerData.y.toFixed(2)}</p>
                <p>Z: {debugInfo.accelerometerData.z.toFixed(2)}</p>
              </div>
            </div>
            
            <div className="bg-gray-900 p-4 rounded-lg">
              <h2 className="text-xl font-bold mb-4">🔄 Giroscopio</h2>
              <div className="space-y-2">
                <p>X: {debugInfo.gyroscopeData.x.toFixed(2)}</p>
                <p>Y: {debugInfo.gyroscopeData.y.toFixed(2)}</p>
                <p>Z: {debugInfo.gyroscopeData.z.toFixed(2)}</p>
              </div>
            </div>
            
            <div className="bg-gray-900 p-4 rounded-lg">
              <h2 className="text-xl font-bold mb-4">🧭 Orientación</h2>
              <div className="space-y-2">
                <p>Alpha: {debugInfo.deviceOrientation.alpha.toFixed(2)}°</p>
                <p>Beta: {debugInfo.deviceOrientation.beta.toFixed(2)}°</p>
                <p>Gamma: {debugInfo.deviceOrientation.gamma.toFixed(2)}°</p>
              </div>
            </div>
            
            <div className="bg-gray-900 p-4 rounded-lg">
              <h2 className="text-xl font-bold mb-4">📝 Logs</h2>
              <div className="h-48 overflow-y-auto text-xs space-y-1">
                {logs.map((log, index) => (
                  <div key={index} className="text-gray-300">{log}</div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  // Renderizar juego activo
  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-black to-gray-900 flex flex-col items-center justify-center p-4">
      <div className="text-center mb-8">
        <h1 className="text-4xl font-bold text-transparent bg-clip-text bg-gradient-to-r from-yellow-400 to-red-500 mb-2">
          {gameState.mode === 'kamikaze' ? '🚀 KAMIKAZE MODE' : '🔄 FLIP MODE'}
        </h1>
        <p className="text-white text-xl">Puntuación: {gameState.score}</p>
        <p className="text-gray-400">Record: {gameState.highScore}</p>
      </div>
      
      <div className="bg-gray-800 p-6 rounded-lg shadow-xl mb-6 w-full max-w-md">
        <h2 className="text-xl font-bold text-white mb-4">📊 Estado del Juego</h2>
        <div className="space-y-2 text-sm">
          <p className="text-gray-300">
            Lanzamiento activo: {gameState.isThrowActive ? '✅ SÍ' : '❌ NO'}
          </p>
          
          {gameState.mode === 'kamikaze' && (
            <div className="space-y-1">
              <p className="text-gray-300">
                Altura máxima: {debugInfo.maxHeight}
              </p>
              <p className="text-gray-300">
                Aceleración: {Math.sqrt(
                  debugInfo.accelerometerData.x ** 2 + 
                  debugInfo.accelerometerData.y ** 2 + 
                  debugInfo.accelerometerData.z ** 2
                ).toFixed(2)} m/s²
              </p>
            </div>
          )}
          
          {gameState.mode === 'flip' && (
            <div className="space-y-1">
              <p className="text-gray-300">
                Flips totales: {flipData.totalFlips}
              </p>
              <p className="text-gray-300">
                Último flip: {flipData.flipTypes[flipData.flipTypes.length - 1] || 'Ninguno'}
              </p>
              <p className="text-gray-300">
                Velocidad máxima: {flipData.maxRotationSpeed.toFixed(2)} °/s
              </p>
            </div>
          )}
        </div>
      </div>
      
      <div className="bg-gray-800 p-4 rounded-lg shadow-xl mb-6 w-full max-w-md">
        <h3 className="text-lg font-bold text-white mb-3">🔧 Debug Info</h3>
        <div className="text-xs text-gray-400 space-y-1 max-h-32 overflow-y-auto">
          {logs.slice(0, 6).map((log, index) => (
            <div key={index}>{log}</div>
          ))}
        </div>
      </div>
      
      <div className="flex space-x-4">
        <button
          onClick={stopGame}
          className="py-3 px-6 bg-red-600 text-white font-bold rounded-lg shadow-lg hover:bg-red-700 transform hover:scale-105 transition-all duration-200"
        >
          🏁 Terminar Juego
        </button>
        
        <button
          onClick={enterDebugMode}
          className="py-3 px-6 bg-gray-600 text-white font-bold rounded-lg shadow-lg hover:bg-gray-700 transform hover:scale-105 transition-all duration-200"
        >
          🔍 Debug
        </button>
      </div>
      
      <div className="mt-8 text-center text-gray-400">
        <p className="text-sm">
          {gameState.mode === 'kamikaze' 
            ? '💡 Lanza tu teléfono hacia arriba para obtener puntos' 
            : '💡 Gira tu teléfono para hacer flips y obtener puntos'
          }
        </p>
      </div>
    </div>
  );
};

export default KamikazeGame;