'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { requireActiveTenant } from '@/lib/tenant'

function value(data: FormData, key: string) { return String(data.get(key) ?? '').trim() }
function fail(message: string): never { throw new Error(message) }

export async function createCategoryAction(data: FormData) {
  const name = value(data, 'name')
  if (name.length < 2 || name.length > 80) fail('La categoría debe tener entre 2 y 80 caracteres.')
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const { error } = await supabase.from('categories').insert({ tenant_id: tenant.tenant_id, name })
  if (error) fail(error.message)
  revalidatePath('/dashboard/inventory')
}

export async function createWarehouseAction(data: FormData) {
  const name = value(data, 'name')
  if (name.length < 2 || name.length > 100) fail('El almacén debe tener entre 2 y 100 caracteres.')
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const { error } = await supabase.from('warehouses').insert({ tenant_id: tenant.tenant_id, name })
  if (error) fail(error.message)
  revalidatePath('/dashboard/inventory')
}

export async function createProductAction(data: FormData) {
  const name = value(data, 'name')
  const sku = value(data, 'sku') || null
  const unit = value(data, 'unit') || 'unidad'
  const categoryId = value(data, 'category_id') || null
  const minStock = Number(value(data, 'min_stock') || 0)
  if (name.length < 2 || name.length > 140) fail('El nombre del producto debe tener entre 2 y 140 caracteres.')
  if (!Number.isFinite(minStock) || minStock < 0) fail('El stock mínimo no es válido.')
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const { error } = await supabase.from('products').insert({
    tenant_id: tenant.tenant_id, name, sku, unit, category_id: categoryId,
    is_perishable: data.get('is_perishable') === 'on', min_stock: minStock,
  })
  if (error) fail(error.message)
  revalidatePath('/dashboard/inventory')
}

export async function updateProductAction(data: FormData) {
  const id = value(data, 'id')
  const name = value(data, 'name')
  const sku = value(data, 'sku') || null
  const unit = value(data, 'unit') || 'unidad'
  const minStock = Number(value(data, 'min_stock') || 0)
  if (!id) fail('Producto no identificado.')
  if (name.length < 2 || name.length > 140) fail('El nombre debe tener entre 2 y 140 caracteres.')
  if (!Number.isFinite(minStock) || minStock < 0) fail('El stock mínimo no es válido.')
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const { error } = await supabase.from('products').update({ name, sku, unit, min_stock: minStock, is_perishable: data.get('is_perishable') === 'on' }).eq('id', id).eq('tenant_id', tenant.tenant_id)
  if (error) fail(error.message)
  revalidatePath('/dashboard/inventory')
  revalidatePath('/dashboard/reports')
}

export async function deactivateProductAction(data: FormData) {
  const id = value(data, 'id')
  if (!id) fail('Producto no identificado.')
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const { error } = await supabase.from('products').update({ is_active: false }).eq('id', id).eq('tenant_id', tenant.tenant_id)
  if (error) fail(error.message)
  revalidatePath('/dashboard/inventory')
  revalidatePath('/dashboard/reports')
}

export async function deactivateWarehouseAction(data: FormData) {
  const id = value(data, 'id')
  if (!id) fail('Almacén no identificado.')
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const { error } = await supabase.from('warehouses').update({ is_active: false }).eq('id', id).eq('tenant_id', tenant.tenant_id)
  if (error) fail(error.message)
  revalidatePath('/dashboard/inventory')
}
