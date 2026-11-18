'use server'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export async function signIn(formData: FormData) {
  const email = String(formData.get('email') ?? '').trim().toLowerCase()
  const password = String(formData.get('password') ?? '')
  if (!email || !password) redirect('/login?error=Completa%20todos%20los%20campos')
  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) redirect('/login?error=No%20se%20pudo%20iniciar%20sesion')
  redirect('/dashboard')
}

export async function signUp(formData: FormData) {
  const email = String(formData.get('email') ?? '').trim().toLowerCase()
  const password = String(formData.get('password') ?? '')
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || password.length < 10 || password.length > 128) {
    redirect('/register?error=Usa%20un%20correo%20válido%20y%20una%20contraseña%20de%2010%20a%20128%20caracteres')
  }
  const configuredAppUrl = process.env.NEXT_PUBLIC_APP_URL ?? (process.env.NODE_ENV === 'production' ? '' : 'http://localhost:3000')
  let emailRedirectTo: string | null = null
  try {
    const baseUrl = new URL(configuredAppUrl)
    if (process.env.NODE_ENV !== 'production' || baseUrl.protocol === 'https:') {
      emailRedirectTo = new URL('/auth/callback', baseUrl).toString()
    }
  } catch {
    emailRedirectTo = null
  }
  if (!emailRedirectTo) redirect('/register?error=Configura%20NEXT_PUBLIC_APP_URL%20con%20la%20URL%20HTTPS%20de%20la%20aplicación')
  const supabase = await createClient()
  const { error } = await supabase.auth.signUp({
    email, password,
    options: { emailRedirectTo },
  })
  if (error) redirect('/register?error=No%20se%20pudo%20crear%20la%20cuenta')
  redirect('/register?message=Revisa%20tu%20correo%20para%20confirmar%20la%20cuenta')
}

export async function signOut() {
  const supabase = await createClient()
  await supabase.auth.signOut()
  redirect('/login')
}
