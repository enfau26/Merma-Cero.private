'use server'
import { cookies } from 'next/headers'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getMyTenants } from '@/lib/tenant'

export async function createTenant(formData: FormData) {
  const name = String(formData.get('name') ?? '').trim()
  const country = String(formData.get('country') ?? '').trim().toUpperCase()
  const returnTo = String(formData.get('return_to') ?? '') === '/dashboard/companies/new' ? '/dashboard/companies/new' : '/onboarding'
  if (name.length < 2 || name.length > 100 || !['PE','ES'].includes(country)) redirect(`${returnTo}?error=Datos%20no%20validos`)
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  const { data, error } = await supabase.rpc('create_tenant_with_default_warehouse', { p_name: name, p_country_code: country })
  if (error || !data) redirect(`${returnTo}?error=No%20se%20pudo%20crear%20la%20empresa`)
  const cookieStore = await cookies()
  cookieStore.set('mc_active_tenant', String(data), { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/', maxAge: 60 * 60 * 24 * 30 })
  redirect('/dashboard')
}

export async function switchTenant(formData: FormData) {
  const requested = String(formData.get('tenant_id') ?? '')
  const tenants = await getMyTenants()
  const allowed = tenants.some(t => t.tenant_id === requested)
  if (!allowed) redirect('/dashboard?error=Empresa%20no%20autorizada')
  const cookieStore = await cookies()
  cookieStore.set('mc_active_tenant', requested, { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/', maxAge: 60 * 60 * 24 * 30 })
  redirect('/dashboard')
}
