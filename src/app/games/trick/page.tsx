'use client';
import dynamic from 'next/dynamic';

const TrickThrowGame = dynamic(() => import('../../../components/TrickThrowGame'), { ssr: false });

export default function TrickPage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-gray-900 text-white p-4 gap-4">
      <h1 className="text-2xl font-bold">Flip Frenzy</h1>
      <TrickThrowGame />
    </main>
  );
}
