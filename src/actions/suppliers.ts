'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { requireActiveTenant } from '@/lib/tenant';

export async function createSupplierAction(formData: FormData) {
  const { tenant, user } = await requireActiveTenant();
  const legalName = String(formData.get('legal_name') ?? '').trim();
  if (legalName.length < 2 || legalName.length > 180) throw new Error('Nombre legal no válido');

  const supabase = await createClient();
  const payload = {
    tenant_id: tenant.tenant_id,
    legal_name: legalName,
    trade_name: String(formData.get('trade_name') ?? '').trim() || null,
    tax_id: String(formData.get('tax_id') ?? '').trim() || null,
    country_code: tenant.country_code,
    currency_code: tenant.currency_code,
    email: String(formData.get('email') ?? '').trim() || null,
    phone: String(formData.get('phone') ?? '').trim() || null,
    payment_terms_days: Math.max(0, Number(formData.get('payment_terms_days') ?? 0)),
    created_by: user.id,
  };
  if (!Number.isInteger(payload.payment_terms_days)) throw new Error('Plazo de pago no válido');
  const { data, error } = await supabase.from('suppliers').insert(payload).select('id').single();
  if (error) throw new Error(error.message);
  revalidatePath('/dashboard/suppliers');
  return data.id as string;
}
