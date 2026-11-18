'use client'

export default function InventoryError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return <main className="dashboard"><section className="section"><h1>No se pudo completar la operación</h1><p>{error.message || 'Se produjo un error inesperado.'}</p><button className="btn" onClick={() => reset()}>Volver a intentar</button></section></main>
}
