import dynamic from 'next/dynamic';

const GyroscopeChart = dynamic(() => import('../components/GyroscopeChart'), { ssr: false });

export default function Home() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-gray-900 text-white p-4">
      <h1 className="text-2xl font-bold mb-4">Giroscopio en Tiempo Real</h1>
      <GyroscopeChart />
    </main>
  );
}
