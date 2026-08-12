import Link from 'next/link';

export default function GamesPage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-gray-900 text-white p-4 gap-4">
      <h1 className="text-2xl font-bold mb-4">Modos de Juego</h1>
      <Link href="/games/kamikaze" className="px-4 py-2 bg-blue-500 rounded">Kamikaze Clásico</Link>
      <Link href="/games/trick" className="px-4 py-2 bg-blue-500 rounded">Flip Frenzy</Link>
    </main>
  );
}
