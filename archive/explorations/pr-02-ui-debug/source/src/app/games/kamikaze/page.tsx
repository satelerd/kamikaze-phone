'use client';
import dynamic from 'next/dynamic';

const KamikazeClassic = dynamic(() => import('../../../components/KamikazeClassic'), { ssr: false });

export default function KamikazePage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-gray-900 text-white p-4 gap-4">
      <h1 className="text-2xl font-bold">Kamikaze Clásico</h1>
      <KamikazeClassic />
    </main>
  );
}
