import Link from 'next/link'
import { requireActiveTenant } from '@/lib/tenant'
import { createClient } from '@/lib/supabase/server'
import PurchaseOrderForm from './purchase-order-form'

export const dynamic = 'force-dynamic'

export default async function PurchasesPage() {
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const [suppliersRes, productsRes, ordersRes] = await Promise.all([
    supabase.from('suppliers').select('id,legal_name').eq('tenant_id', tenant.tenant_id).eq('is_active', true).order('legal_name'),
    supabase.from('products').select('id,name,sku,unit').eq('tenant_id', tenant.tenant_id).eq('is_active', true).order('name'),
    supabase.from('purchase_orders').select('id,order_number,status,order_date,expected_date,total,currency_code,suppliers(legal_name)').eq('tenant_id', tenant.tenant_id).order('created_at', { ascending: false }).limit(100),
  ])
  const error = suppliersRes.error || productsRes.error || ordersRes.error
  return <><header className="top"><Link href="/dashboard" className="brand">🌿 MERMA <span>CERO</span></Link><div className="row"><Link className="btn secondary" href="/dashboard/suppliers">Proveedores</Link><Link className="btn secondary" href="/dashboard/purchases/receipts">Recepciones</Link><Link className="btn secondary" href="/dashboard">Panel</Link></div></header>
    <main className="dashboard"><p className="eyebrow">COMPRAS · {tenant.country_code === 'PE' ? 'PERÚ' : 'ESPAÑA'}</p><h1>Órdenes de compra</h1><p>Empresa: {tenant.tenant_name}. Los registros se aíslan mediante RLS y las órdenes se crean mediante una transacción en PostgreSQL.</p>
      {error && <p className="error">No se pudieron cargar todos los datos: {error.message}</p>}
      {['owner','admin','manager'].includes(tenant.role) && <PurchaseOrderForm suppliers={suppliersRes.data ?? []} products={productsRes.data ?? []} currency={tenant.currency_code}/>}
      <section className="section"><h2>Historial de órdenes</h2><div className="table-wrap"><table><thead><tr><th>Orden</th><th>Proveedor</th><th>Fecha</th><th>Entrega prevista</th><th>Estado</th><th>Total</th></tr></thead><tbody>{(ordersRes.data ?? []).map(o => <tr key={o.id}><td>{o.order_number}</td><td>{o.suppliers && !Array.isArray(o.suppliers) ? o.suppliers.legal_name : '—'}</td><td>{o.order_date}</td><td>{o.expected_date || '—'}</td><td>{({draft:'Borrador',submitted:'Enviada',partially_received:'Parcialmente recibida',received:'Recibida',cancelled:'Cancelada'} as Record<string,string>)[o.status] || o.status}</td><td>{Number(o.total).toFixed(2)} {o.currency_code}</td></tr>)}{!(ordersRes.data?.length) && <tr><td colSpan={6} className="empty">Todavía no hay órdenes de compra.</td></tr>}</tbody></table></div></section>
      <p className="muted footnote">Las órdenes nuevas se envían para recepción. Registra las entregas parciales o completas desde <Link href="/dashboard/purchases/receipts">Recepciones</Link>.</p>
    </main></>
}
