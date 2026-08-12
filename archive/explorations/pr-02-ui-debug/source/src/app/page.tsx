'use client';
import Link from 'next/link';
import useSensorPermissions from '../hooks/useSensorPermissions';

export default function Home() {
  const { granted, attempted, request } = useSensorPermissions();

  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-gray-900 text-white p-4 gap-6">
      <h1 className="text-4xl font-bold">Kamikaze Phone</h1>
      <p className="text-center max-w-md">Lanza tu teléfono al cielo y realiza flips para conseguir la mejor puntuación.</p>
      {!granted && (
        <button onClick={request} className="px-4 py-2 bg-purple-600 rounded hover:bg-purple-700">
          {attempted ? 'Reintentar permisos' : 'Permitir sensores'}
        </button>
      )}
      {granted && <p className="text-green-400">Permisos concedidos</p>}
      <div className="flex gap-4 mt-4">
        <Link href="/games" className="px-6 py-3 bg-blue-500 rounded text-lg hover:bg-blue-600">Jugar</Link>
        <Link href="/gyroscope" className="px-4 py-2 bg-gray-700 rounded text-sm hover:bg-gray-600 self-end">Ver giroscopio</Link>
      </div>
    </main>
  );
}
