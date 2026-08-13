import type { Metadata } from 'next';
import TrickLab from '@/modes/trick-lab/TrickLab';

export const metadata: Metadata = {
  title: 'Trick Lab | Kamikaze Phone',
  description: 'Slow-mo video + 3D trajectory reconstruction of every trick.',
};

export default function TrickLabPage() {
  return <TrickLab />;
}
