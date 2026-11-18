import Link from 'next/link'
import { requireActiveTenant } from '@/lib/tenant'
import { createClient } from '@/lib/supabase/server'
import SaleForm from './sale-form'
import ReturnForm from './return-form'

export const dynamic = 'force-dynamic'

export default async function SalesPage() {
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const [productsRes, warehousesRes, salesRes] = await Promise.all([
    supabase.from('products').select('id,name,sku,unit').eq('tenant_id', tenant.tenant_id).eq('is_active', true).order('name'),
    supabase.from('warehouses').select('id,name').eq('tenant_id', tenant.tenant_id).eq('is_active', true).order('name'),
    supabase.from('sales').select('id,sale_number,sold_at,status,subtotal,tax_total,discount_total,total,currency_code').eq('tenant_id', tenant.tenant_id).order('sold_at', { ascending: false }).limit(100),
  ])
  const saleIds = (salesRes.data ?? []).map(s => s.id)
  const [itemsRes, returnsRes] = saleIds.length ? await Promise.all([
    supabase.from('sale_items').select('id,sale_id,product_id,quantity,line_total').eq('tenant_id', tenant.tenant_id).in('sale_id', saleIds),
    supabase.from('sale_return_items').select('sale_item_id,quantity').eq('tenant_id', tenant.tenant_id),
  ]) : [{ data: [], error: null }, { data: [], error: null }]
  const productIds = [...new Set((itemsRes.data ?? []).map(item => item.product_id))]
  const { data: itemProducts } = productIds.length ? await supabase.from('products').select('id,name,sku').eq('tenant_id', tenant.tenant_id).in('id', productIds) : { data: [] }
  const productMap = new Map((itemProducts ?? []).map(product => [product.id, `${product.name}${product.sku ? ` · ${product.sku}` : ''}`]))
  const returnedByItem = new Map<string, number>()
  for (const row of returnsRes.data ?? []) returnedByItem.set(row.sale_item_id, (returnedByItem.get(row.sale_item_id) ?? 0) + Number(row.quantity))
  const itemsBySale = new Map<string, { id: string; label: string; quantity: number; remaining: number; line_total: number }[]>()
  for (const item of itemsRes.data ?? []) {
    const quantity = Number(item.quantity)
    const remaining = Math.max(0, quantity - (returnedByItem.get(item.id) ?? 0))
    const rows = itemsBySale.get(item.sale_id) ?? []
    rows.push({ id: item.id, label: productMap.get(item.product_id) ?? 'Producto', quantity, remaining, line_total: Number(item.line_total) })
    itemsBySale.set(item.sale_id, rows)
  }
  const error = productsRes.error || warehousesRes.error || salesRes.error || itemsRes.error || returnsRes.error
  return <>
    <header className="top"><Link href="/dashboard" className="brand">🌿 MERMA <span>CERO</span></Link><div className="row"><Link className="btn secondary" href="/dashboard/cash">Caja</Link><Link className="btn secondary" href="/dashboard">Panel</Link></div></header>
    <main className="dashboard"><p className="eyebrow">VENTAS Y TPV · {tenant.country_code === 'PE' ? 'PERÚ' : 'ESPAÑA'}</p><h1>Ventas</h1><p>Empresa: {tenant.tenant_name}. Las existencias se descuentan con asignación FEFO dentro de una transacción de PostgreSQL.</p>
      {error && <p className="error">No se pudieron cargar todos los datos: {error.message}</p>}
      {['owner','admin','manager','operator'].includes(tenant.role) && <SaleForm products={productsRes.data ?? []} warehouses={warehousesRes.data ?? []} currency={tenant.currency_code}/>}
      <section className="section"><h2>Historial de ventas</h2><div className="table-wrap"><table><thead><tr><th>Número</th><th>Fecha</th><th>Estado</th><th>Base</th><th>Impuestos</th><th>Descuento</th><th>Total</th></tr></thead><tbody>{(salesRes.data ?? []).map(s=><tr key={s.id}><td>{s.sale_number}</td><td>{new Date(s.sold_at).toLocaleString(tenant.country_code === 'PE' ? 'es-PE' : 'es-ES', { timeZone: tenant.timezone })}</td><td>{s.status === 'completed' ? 'Completada' : 'Anulada'}</td><td>{Number(s.subtotal).toFixed(2)}</td><td>{Number(s.tax_total).toFixed(2)}</td><td>{Number(s.discount_total).toFixed(2)}</td><td><strong>{Number(s.total).toFixed(2)} {s.currency_code}</strong></td></tr>)}{!(salesRes.data?.length) && <tr><td colSpan={7} className="empty">Todavía no hay ventas registradas.</td></tr>}</tbody></table></div></section>
      {['owner','admin','manager','operator'].includes(tenant.role) && <section className="section"><h2>Devoluciones</h2><p>Las devoluciones parciales reponen existencias en los lotes originales y registran el reembolso declarado.</p>{(salesRes.data ?? []).filter(s => s.status === 'completed').map(s => <details className="panel" key={s.id}><summary><strong>{s.sale_number}</strong> · {new Date(s.sold_at).toLocaleDateString(tenant.country_code === 'PE' ? 'es-PE' : 'es-ES', { timeZone: tenant.timezone })} · {Number(s.total).toFixed(2)} {s.currency_code}</summary><ReturnForm saleId={s.id} items={itemsBySale.get(s.id) ?? []} currency={s.currency_code}/></details>)}{!(salesRes.data?.length) && <p className="empty">No hay ventas que puedan devolverse.</p>}</section>}
      <p className="muted footnote">El TPV registra cobros declarados; no procesa tarjetas ni transferencias reales. La emisión de comprobantes fiscales electrónicos para Perú y España requiere una integración tributaria posterior.</p>
    </main>
  </>
}
