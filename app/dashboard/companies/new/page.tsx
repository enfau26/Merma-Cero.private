import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { createTenant } from '@/actions/tenant'

export default async function NewCompanyPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const query = await searchParams

  return (
    <>
      <header className="top">
        <div className="brand">🌿 MERMA <span>CERO</span></div>
        <small>Gestión multiempresa</small>
      </header>
      <main>
        <section className="panel">
          <h1>Añadir otra empresa</h1>
          <p>La nueva empresa tendrá sus propios productos, almacenes, lotes y movimientos. Tu usuario quedará registrado como propietario.</p>
          {query.error && <div className="error">{query.error}</div>}
          <form action={createTenant}>
            <input type="hidden" name="return_to" value="/dashboard/companies/new" />
            <div className="field">
              <label htmlFor="name">Nombre comercial</label>
              <input id="name" name="name" minLength={2} maxLength={100} required placeholder="Mi nuevo negocio" />
            </div>
            <div className="field">
              <label htmlFor="country">País de operación</label>
              <select id="country" name="country" required defaultValue="">
                <option value="" disabled>Selecciona un país</option>
                <option value="PE">Perú · PEN · America/Lima</option>
                <option value="ES">España · EUR · Europe/Madrid</option>
              </select>
            </div>
            <button className="btn" type="submit">Crear empresa</button>
          </form>
        </section>
      </main>
    </>
  )
}
