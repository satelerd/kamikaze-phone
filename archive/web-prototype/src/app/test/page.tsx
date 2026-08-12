import dynamic from 'next/dynamic';

const GyroscopeMeasurement = dynamic(() => import('@/components/GyroscopeMeasurement'), { ssr: false });

export default function TestPage() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center bg-gray-900 text-white p-4">
      <h1 className="text-2xl font-bold mb-4">Prueba de Medición de Giroscopio</h1>
      <GyroscopeMeasurement />
    </main>
  );
}