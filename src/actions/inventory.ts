'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { requireActiveTenant } from '@/lib/tenant';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requiredUuid(formData: FormData, key: string): string {
  const value = String(formData.get(key) ?? '').trim();
  if (!UUID_RE.test(value)) throw new Error(`El campo ${key} no contiene un identificador válido`);
  return value;
}

function positiveQuantity(formData: FormData): number {
  const raw = String(formData.get('quantity') ?? '').trim();
  const quantity = Number(raw);
  if (!raw || !Number.isFinite(quantity) || quantity <= 0 || quantity > 1_000_000_000) {
    throw new Error('La cantidad debe ser un número positivo válido');
  }
  return quantity;
}

function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function boundedText(formData: FormData, key: string, max: number, fallback = ''): string {
  const value = String(formData.get(key) ?? fallback).trim();
  if (value.length > max) throw new Error(`El campo ${key} supera el máximo de ${max} caracteres`);
  return value;
}

export async function receiveLotAction(formData: FormData) {
  const productId = requiredUuid(formData, 'product_id');
  const warehouseId = requiredUuid(formData, 'warehouse_id');
  const quantity = positiveQuantity(formData);
  const rawCost = String(formData.get('unit_cost') ?? '0').trim();
  const unitCost = Number(rawCost || '0');
  if (!Number.isFinite(unitCost) || unitCost < 0 || unitCost > 1_000_000_000) {
    throw new Error('El coste unitario no es válido');
  }
  const expiresOn = boundedText(formData, 'expires_on', 10) || null;
  if (expiresOn && !isCalendarDate(expiresOn)) {
    throw new Error('La fecha de caducidad no es válida');
  }
  const lotCode = boundedText(formData, 'lot_code', 120);
  const supplierName = boundedText(formData, 'supplier_name', 180);
  const { tenant } = await requireActiveTenant();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('receive_lot', {
    p_tenant_id: tenant.tenant_id,
    p_product_id: productId,
    p_warehouse_id: warehouseId,
    p_quantity: quantity,
    p_unit_cost: unitCost,
    p_expires_on: expiresOn,
    p_lot_code: lotCode,
    p_supplier_name: supplierName,
  });
  if (error) throw new Error(error.message);
  revalidatePath('/dashboard/inventory');
  revalidatePath('/dashboard/reports');
  return data as string;
}

export async function consumeFefoAction(formData: FormData) {
  const productId = requiredUuid(formData, 'product_id');
  const warehouseId = requiredUuid(formData, 'warehouse_id');
  const quantity = positiveQuantity(formData);
  const reason = boundedText(formData, 'reason', 500, 'Salida de mercancía') || 'Salida de mercancía';
  const reference = boundedText(formData, 'reference', 120) || null;
  const { tenant } = await requireActiveTenant();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('consume_stock_fefo', {
    p_tenant_id: tenant.tenant_id,
    p_product_id: productId,
    p_warehouse_id: warehouseId,
    p_quantity: quantity,
    p_reason: reason,
    p_reference: reference,
  });
  if (error) throw new Error(error.message);
  revalidatePath('/dashboard/inventory');
  revalidatePath('/dashboard/reports');
  return data;
}

export async function recordWasteAction(formData: FormData) {
  const lotId = requiredUuid(formData, 'lot_id');
  const quantity = positiveQuantity(formData);
  const reason = boundedText(formData, 'reason', 500);
  if (reason.length < 2) throw new Error('Indica el motivo de la merma');
  const { tenant } = await requireActiveTenant();
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('record_waste', {
    p_tenant_id: tenant.tenant_id,
    p_lot_id: lotId,
    p_quantity: quantity,
    p_reason: reason,
  });
  if (error) throw new Error(error.message);
  revalidatePath('/dashboard/inventory');
  revalidatePath('/dashboard/reports');
  return data as string;
}
