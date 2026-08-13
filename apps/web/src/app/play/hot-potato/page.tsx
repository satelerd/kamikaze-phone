import type { Metadata } from 'next';
import HotPotatoMode from '@/modes/hot-potato/HotPotatoMode';

export const metadata: Metadata = {
  title: 'Hot Potato · Kamikaze Phone',
  description: 'Pass it before it blows. Wrap it in a towel. Trust the towel.',
};

export default function HotPotatoPage() {
  return <HotPotatoMode />;
}
