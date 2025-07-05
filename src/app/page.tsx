import dynamic from 'next/dynamic';

const KamikazeGame = dynamic(() => import('../components/KamikazeGame'), { ssr: false });

export default function Home() {
  return (
    <main className="min-h-screen bg-black text-white overflow-hidden">
      <KamikazeGame />
    </main>
  );
}
