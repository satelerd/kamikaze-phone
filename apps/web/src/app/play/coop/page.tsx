import { Suspense } from 'react';
import CoopGame from '@/modes/coop/CoopGame';

// CoopGame reads the ?join=CODE invite via useSearchParams, which Next 14
// requires to sit inside a Suspense boundary for static builds.
export default function CoopPage() {
  return (
    <Suspense
      fallback={
        <main className="flex min-h-screen items-center justify-center text-zinc-400">
          Paddling out... 🤝
        </main>
      }
    >
      <CoopGame />
    </Suspense>
  );
}
