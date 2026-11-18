import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function GET(request: Request) {
  const url = new URL(request.url)
  const code = url.searchParams.get('code')
  if (!code) {
    const target = new URL('/login', url.origin)
    target.searchParams.set('error', 'No se recibió el código de confirmación')
    return NextResponse.redirect(target)
  }

  const supabase = await createClient()
  const { error } = await supabase.auth.exchangeCodeForSession(code)
  if (error) {
    const target = new URL('/login', url.origin)
    target.searchParams.set('error', 'El enlace de confirmación no es válido o ha caducado')
    return NextResponse.redirect(target)
  }

  return NextResponse.redirect(new URL('/onboarding', url.origin))
}
