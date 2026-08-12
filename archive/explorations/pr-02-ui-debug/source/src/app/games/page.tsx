'use client';
import Link from 'next/link';

export default function GamesPage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-gray-900 text-white p-4 gap-6">
      <h1 className="text-3xl font-bold mb-6">Selecciona un modo de juego</h1>
      <div className="flex flex-col gap-4 w-full max-w-xs">
        <Link href="/games/kamikaze" className="px-6 py-3 bg-blue-500 rounded text-center text-lg hover:bg-blue-600">Kamikaze Clásico</Link>
        <Link href="/games/trick" className="px-6 py-3 bg-blue-500 rounded text-center text-lg hover:bg-blue-600">Flip Frenzy</Link>
      </div>
    </main>
  );
}
