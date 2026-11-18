'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { requireActiveTenant } from '@/lib/tenant'

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

type SaleLine = { product_id: string; quantity: number; unit_price: number; tax_rate: number; discount_amount: number }

export async function createSaleAction(input: {
  warehouseId: string; saleNumber: string; notes?: string; lines: SaleLine[];
  paymentMethod: 'cash' | 'card' | 'transfer' | 'other'; paymentAmount: number; paymentReference?: string
}) {
  const { tenant } = await requireActiveTenant()
  if (!input || typeof input !== 'object' || typeof input.warehouseId !== 'string' || !UUID_RE.test(input.warehouseId)
    || typeof input.saleNumber !== 'string' || !/^[\p{L}\p{N}._/-]{1,60}$/u.test(input.saleNumber.trim())
    || (input.notes !== undefined && typeof input.notes !== 'string')
    || (input.paymentReference !== undefined && typeof input.paymentReference !== 'string')) throw new Error('Almacén o datos de venta no válidos')
  if (!Array.isArray(input.lines) || input.lines.length < 1 || input.lines.length > 200) throw new Error('La venta debe contener entre 1 y 200 líneas')
  const seen = new Set<string>()
  const lines = input.lines.map((line) => {
    if (!line || !UUID_RE.test(line.product_id) || seen.has(line.product_id)) throw new Error('Producto inválido o repetido')
    seen.add(line.product_id)
    const { quantity, unit_price, tax_rate, discount_amount } = line
    if (![quantity, unit_price, tax_rate, discount_amount].every(Number.isFinite) || quantity <= 0 || quantity > 1e9 || unit_price < 0 || unit_price > 1e9 || tax_rate < 0 || tax_rate > 100 || discount_amount < 0 || discount_amount > 1e9) throw new Error('Revisa cantidades, precios, impuestos y descuentos')
    if (Math.abs(quantity * 1000 - Math.round(quantity * 1000)) > 1e-6) throw new Error('La cantidad admite como máximo tres decimales')
    return { product_id: line.product_id, quantity, unit_price, tax_rate, discount_amount }
  })
  if (!['cash','card','transfer','other'].includes(input.paymentMethod) || !Number.isFinite(input.paymentAmount) || input.paymentAmount <= 0 || input.paymentAmount > 1e9) throw new Error('Método o importe de pago no válido')
  const total = lines.reduce((sum, line) => {
    const base = Math.round((line.quantity * line.unit_price - line.discount_amount) * 100) / 100
    if (base < 0) throw new Error('El descuento supera el importe de la línea')
    return sum + base + Math.round(base * line.tax_rate) / 100
  }, 0)
  if (Math.abs(Math.round(total * 100) - Math.round(input.paymentAmount * 100)) > 0) throw new Error('El pago debe coincidir exactamente con el total calculado')
  const supabase = await createClient()
  const { data, error } = await supabase.rpc('create_sale_atomic', {
    p_tenant_id: tenant.tenant_id, p_warehouse_id: input.warehouseId,
    p_sale_number: input.saleNumber.trim(), p_lines: lines,
    p_payments: [{ method: input.paymentMethod, amount: input.paymentAmount, reference: input.paymentReference?.trim() || null }],
    p_notes: input.notes?.trim().slice(0, 2000) || null,
  })
  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/sales')
  revalidatePath('/dashboard/inventory')
  revalidatePath('/dashboard/reports')
  revalidatePath('/dashboard/cash')
  return data as string
}

export async function createSaleReturnAction(input: {
  saleId: string; saleItemId: string; quantity: number; reason: string;
  paymentMethod: 'cash' | 'card' | 'transfer' | 'other'; paymentReference?: string; notes?: string
}) {
  const { tenant } = await requireActiveTenant()
  if (!input || !UUID_RE.test(input.saleId) || !UUID_RE.test(input.saleItemId)
    || !Number.isFinite(input.quantity) || input.quantity <= 0 || input.quantity > 1e9
    || Math.abs(input.quantity * 1000 - Math.round(input.quantity * 1000)) > 1e-6
    || typeof input.reason !== 'string' || !input.reason.trim() || input.reason.trim().length > 500
    || !['cash', 'card', 'transfer', 'other'].includes(input.paymentMethod)
    || (input.paymentReference !== undefined && typeof input.paymentReference !== 'string')
    || (input.notes !== undefined && typeof input.notes !== 'string')) {
    throw new Error('Datos de devolución no válidos')
  }
  const supabase = await createClient()
  const { data: item, error: itemError } = await supabase.from('sale_items')
    .select('id,quantity,line_total').eq('tenant_id', tenant.tenant_id)
    .eq('sale_id', input.saleId).eq('id', input.saleItemId).maybeSingle()
  if (itemError) throw new Error(itemError.message)
  if (!item) throw new Error('No se encontró la línea de venta')
  const { data: returned, error: returnedError } = await supabase.from('sale_return_items')
    .select('quantity')
    .eq('tenant_id', tenant.tenant_id).eq('sale_item_id', input.saleItemId)
  if (returnedError) throw new Error(returnedError.message)
  const alreadyReturned = (returned ?? []).reduce((sum, row) => sum + Number(row.quantity), 0)
  const remaining = Number(item.quantity) - alreadyReturned
  if (input.quantity > remaining + 1e-9) throw new Error(`La cantidad supera lo pendiente de devolver (${remaining.toFixed(3)})`)
  const refund = Math.round(Number(item.line_total) * input.quantity / Number(item.quantity) * 100) / 100
  if (refund <= 0) throw new Error('El importe calculado del reembolso debe ser positivo')
  const returnNumber = `D-${Date.now()}-${Math.random().toString(36).slice(2, 7).toUpperCase()}`
  const { data, error } = await supabase.rpc('create_sale_return_atomic', {
    p_tenant_id: tenant.tenant_id, p_sale_id: input.saleId, p_return_number: returnNumber,
    p_lines: [{ sale_item_id: input.saleItemId, quantity: input.quantity }],
    p_payments: [{ method: input.paymentMethod, amount: refund, reference: input.paymentReference?.trim() || null }],
    p_reason: input.reason.trim(), p_notes: input.notes?.trim().slice(0, 1000) || null,
  })
  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/sales')
  revalidatePath('/dashboard/inventory')
  revalidatePath('/dashboard/reports')
  revalidatePath('/dashboard/cash')
  return { id: data as string, refund }
}
