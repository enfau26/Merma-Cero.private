'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { requireActiveTenant } from '@/lib/tenant'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const text = (fd: FormData, key: string, max: number) => { const value = String(fd.get(key) ?? '').trim(); if (value.length > max) throw new Error(`${key} supera ${max} caracteres`); return value }
const amount = (fd: FormData, key: string, allowZero = false) => { const raw = text(fd,key,40); const n = Number(raw); if (!raw || !Number.isFinite(n) || n < (allowZero ? 0 : 0.01) || n > 1e9) throw new Error('Importe no válido'); return n }

export async function openCashRegisterAction(fd: FormData) {
  const { tenant } = await requireActiveTenant(); const warehouseId = text(fd,'warehouse_id',36); const name = text(fd,'register_name',100); const opening = amount(fd,'opening_amount',true)
  if (!UUID_RE.test(warehouseId) || name.length < 2) throw new Error('Selecciona almacén e indica el nombre de caja')
  const supabase = await createClient(); const { error } = await supabase.rpc('open_cash_register_atomic',{p_tenant_id:tenant.tenant_id,p_warehouse_id:warehouseId,p_register_name:name,p_opening_amount:opening,p_opening_note:text(fd,'opening_note',500)||null})
  if(error) throw new Error(error.message); revalidatePath('/dashboard/cash')
}

export async function cashMovementAction(fd: FormData) {
  const { tenant } = await requireActiveTenant(); const sessionId=text(fd,'session_id',36); const type=text(fd,'movement_type',20); const value=amount(fd,'amount'); const reason=text(fd,'reason',500)
  if(!UUID_RE.test(sessionId)||!['cash_in','cash_out'].includes(type)||reason.length<2) throw new Error('Movimiento de caja no válido')
  const supabase=await createClient(); const {error}=await supabase.rpc('record_cash_register_movement_atomic',{p_tenant_id:tenant.tenant_id,p_session_id:sessionId,p_movement_type:type,p_amount:value,p_reason:reason,p_reference:text(fd,'reference',120)||null})
  if(error) throw new Error(error.message); revalidatePath('/dashboard/cash')
}

export async function closeCashRegisterAction(fd: FormData) {
  const { tenant } = await requireActiveTenant(); const sessionId=text(fd,'session_id',36); const counted=amount(fd,'counted_amount',true)
  if(!UUID_RE.test(sessionId)) throw new Error('Sesión de caja no válida')
  const supabase=await createClient(); const {error}=await supabase.rpc('close_cash_register_atomic',{p_tenant_id:tenant.tenant_id,p_session_id:sessionId,p_counted_amount:counted,p_closing_note:text(fd,'closing_note',500)||null})
  if(error) throw new Error(error.message); revalidatePath('/dashboard/cash')
}
