'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { requireActiveTenant } from '@/lib/tenant';

type PurchaseLine = {
  product_id: string;
  description?: string | null;
  quantity_ordered: number;
  unit_cost: number;
  tax_rate?: number;
};

type ReceiptLine = {
  purchase_order_item_id: string;
  quantity_received: number;
  quantity_accepted: number;
  quantity_rejected: number;
  rejection_reason?: string | null;
  expires_on?: string | null;
  lot_code?: string | null;
};

export async function createPurchaseOrderAction(input: {
  supplierId: string;
  orderNumber: string;
  orderDate?: string;
  expectedDate?: string | null;
  notes?: string;
  lines: PurchaseLine[];
}) {
  const { tenant } = await requireActiveTenant();
  if (!input.supplierId || !input.orderNumber.trim() || !input.lines.length || input.lines.length > 200) {
    throw new Error('Completa proveedor, número de orden y al menos una línea (máximo 200)');
  }
  for (const line of input.lines) {
    if (!line.product_id || !Number.isFinite(line.quantity_ordered) || line.quantity_ordered <= 0
      || !Number.isFinite(line.unit_cost) || line.unit_cost < 0
      || !Number.isFinite(line.tax_rate ?? 0) || (line.tax_rate ?? 0) < 0 || (line.tax_rate ?? 0) > 100) {
      throw new Error('Revisa los productos, cantidades, costes e impuestos de la orden');
    }
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('create_purchase_order_atomic', {
    p_tenant_id: tenant.tenant_id,
    p_supplier_id: input.supplierId,
    p_order_number: input.orderNumber.trim(),
    p_order_date: input.orderDate || null,
    p_expected_date: input.expectedDate || null,
    p_notes: input.notes?.trim() || null,
    p_lines: input.lines,
  });
  if (error) throw new Error(error.message);
  revalidatePath('/dashboard/purchases');
  revalidatePath('/dashboard/suppliers');
  return data as string;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function milliUnits(value: number) {
  return Math.round(value * 1000);
}

function hasAtMostThreeDecimals(value: number) {
  return Number.isFinite(value) && Math.abs(value * 1000 - milliUnits(value)) < 0.000001;
}

function isCalendarDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

export async function receivePurchaseOrderAction(input: {
  purchaseOrderId: string;
  warehouseId: string;
  receiptNumber: string;
  notes?: string;
  lines: ReceiptLine[];
}) {
  if (!input || typeof input !== 'object') throw new Error('Datos de recepción no válidos');
  const { tenant } = await requireActiveTenant();
  const receiptNumber = typeof input.receiptNumber === 'string' ? input.receiptNumber.trim() : '';
  const notes = typeof input?.notes === 'string' ? input.notes.trim() : '';
  if (!UUID_RE.test(input.purchaseOrderId) || !UUID_RE.test(input.warehouseId)
    || !receiptNumber || receiptNumber.length > 60 || notes.length > 2000
    || !Array.isArray(input.lines) || input.lines.length < 1 || input.lines.length > 200) {
    throw new Error('Completa una orden, almacén, número de recepción y entre 1 y 200 líneas válidas');
  }

  const seenItems = new Set<string>();
  const normalizedLines: ReceiptLine[] = [];
  for (const line of input.lines) {
    if (!line || typeof line !== 'object' || typeof line.purchase_order_item_id !== 'string'
      || !UUID_RE.test(line.purchase_order_item_id) || seenItems.has(line.purchase_order_item_id)) {
      throw new Error('La recepción contiene una línea inválida o repetida');
    }
    seenItems.add(line.purchase_order_item_id);

    const received = line.quantity_received;
    const accepted = line.quantity_accepted;
    const rejected = line.quantity_rejected;
    if (![received, accepted, rejected].every(hasAtMostThreeDecimals)
      || received <= 0 || accepted < 0 || rejected < 0
      || milliUnits(received) !== milliUnits(accepted) + milliUnits(rejected)) {
      throw new Error('Las cantidades deben ser positivas, usar hasta 3 decimales y cuadrar: recibida = aceptada + rechazada');
    }

    const rejectionReason = typeof line.rejection_reason === 'string' ? line.rejection_reason.trim() : '';
    const lotCode = typeof line.lot_code === 'string' ? line.lot_code.trim() : '';
    const expiresOn = typeof line.expires_on === 'string' ? line.expires_on.trim() : '';
    if (rejected > 0 && (!rejectionReason || rejectionReason.length > 500)) {
      throw new Error('Indica un motivo de rechazo de hasta 500 caracteres para cada cantidad rechazada');
    }
    if (lotCode.length > 120 || (expiresOn && !isCalendarDate(expiresOn))) {
      throw new Error('Revisa el código de lote y la fecha de caducidad');
    }

    normalizedLines.push({
      purchase_order_item_id: line.purchase_order_item_id,
      quantity_received: received,
      quantity_accepted: accepted,
      quantity_rejected: rejected,
      rejection_reason: rejectionReason || null,
      lot_code: lotCode || null,
      expires_on: expiresOn || null,
    });
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('receive_purchase_order_atomic', {
    p_tenant_id: tenant.tenant_id,
    p_purchase_order_id: input.purchaseOrderId,
    p_warehouse_id: input.warehouseId,
    p_receipt_number: receiptNumber,
    p_lines: normalizedLines,
    p_notes: notes || null,
  });
  if (error) throw new Error(error.message);
  revalidatePath('/dashboard/purchases');
  revalidatePath('/dashboard/purchases/receipts');
  revalidatePath('/dashboard/inventory');
  revalidatePath('/dashboard/reports');
  return data as string;
}
