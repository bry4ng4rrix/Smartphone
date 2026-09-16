import type { Metadata } from 'next'
import { Geist, Geist_Mono } from 'next/font/google'
import { Analytics } from '@vercel/analytics/next'
import { ThemeProvider } from '@/components/theme-provider'
import { Toaster } from '@/components/ui/sonner'
import { GlobalErrorBoundary } from '@/components/global-error-boundary'
import './globals.css'

const _geist = Geist({ subsets: ["latin"] });
const _geistMono = Geist_Mono({ subsets: ["latin"] });

export const metadata: Metadata = {
  // Identité Smartphone.Mg : même logo que l'icône de l'application mobile
  // (smartcross/assets/logo.png) — public/logo.jpeg pour le sidebar, favicon
  // et icônes déclinés du même fichier.
  title: 'Smartphone.Mg',
  description: 'Smartphone.Mg — Osez la qualité ! Gestion des commandes, du stock et des livraisons.',
  applicationName: 'Smartphone.Mg',
  icons: {
    icon: [
      { url: '/favicon.ico', sizes: 'any' },
      { url: '/icon-light-32x32.png', type: 'image/png', sizes: '32x32' },
    ],
    apple: '/apple-icon.png',
  },
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <html lang="fr" suppressHydrationWarning>
      <body className="font-sans antialiased">
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          {children}
          {/* Toast global — visible sur toutes les pages */}
          <Toaster
            position="top-right"
            richColors
            closeButton
            expand
            toastOptions={{
              duration: 5000,
            }}
          />
        </ThemeProvider>
        {process.env.NODE_ENV === 'production' && <Analytics />}
      </body>
    </html>
  )
}
