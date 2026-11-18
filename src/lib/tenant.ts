import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export type Tenant = { tenant_id: string; tenant_name: string; country_code: string; currency_code: string; timezone: string; role: string }

export async function getMyTenants(): Promise<Tenant[]> {
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('list_my_tenants')
  if (error) throw new Error(`No se pudieron cargar tus empresas: ${error.message}`)
  return (data ?? []) as Tenant[]
}

// Cookie solo selecciona; nunca autoriza. La membresía se vuelve a comprobar
// consultando list_my_tenants en el servidor en cada resolución.
export async function requireActiveTenant() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const tenants = await getMyTenants()
  if (!tenants.length) redirect('/onboarding')
  const cookieStore = await cookies()
  const selected = cookieStore.get('mc_active_tenant')?.value
  const tenant = tenants.find(t => t.tenant_id === selected) ?? tenants[0]
  return { user, tenant, tenants }
}
