import type { Metadata } from 'next'
import './globals.css'
export const metadata: Metadata = { title: 'MERMA CERO · ERP', description: 'Inventario inteligente, lotes, FEFO y control de mermas.' }
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="es"><body>{children}</body></html> }
