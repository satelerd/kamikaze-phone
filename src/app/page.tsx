import Link from 'next/link';

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-gray-900 text-white p-4 gap-4">
      <h1 className="text-3xl font-bold">Kamikaze Phone</h1>
      <p className="text-center max-w-md">Experimenta con el giroscopio y juega a lanzar tu teléfono en distintos modos.</p>
      <Link href="/games" className="px-4 py-2 bg-blue-500 rounded">Ir a los Juegos</Link>
      <Link href="/gyroscope" className="px-4 py-2 bg-blue-500 rounded">Ver Giroscopio</Link>
    </main>
  );
}
