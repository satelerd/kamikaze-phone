import type { Metadata, Viewport } from 'next';
import { Inter } from 'next/font/google';
import dynamic from 'next/dynamic';
import './globals.css';

const inter = Inter({ subsets: ['latin'] });

const FlashOverlay = dynamic(() => import('@/components/FlashOverlay'), { ssr: false });
const NarratorDock = dynamic(() => import('@/components/NarratorDock'), { ssr: false });

export const metadata: Metadata = {
  title: 'Kamikaze Phone',
  description: 'Throw your phone. Land tricks. Trust the towel.',
};

export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
  themeColor: '#09090b',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className={`${inter.className} bg-zinc-950 text-zinc-100 antialiased`}>
        {children}
        <FlashOverlay />
        <NarratorDock />
      </body>
    </html>
  );
}
