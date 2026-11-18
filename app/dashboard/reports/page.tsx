import Link from 'next/link'
import { requireActiveTenant } from '@/lib/tenant'
import { createClient } from '@/lib/supabase/server'

export const dynamic = 'force-dynamic'

type Product = { id:string; name:string; sku:string|null; unit:string; min_stock:number; is_active:boolean }
type Lot = { id:string; lot_code:string|null; expires_on:string|null; quantity_available:number; unit_cost:number; products: {id:string;name:string;unit:string}|null; warehouses:{name:string}|null }
type Waste = { quantity:number; estimated_loss:number; reason:string; created_at:string; lots:{products:{name:string}|null;lot_code:string|null}|null }

export default async function ReportsPage() {
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const today = new Date().toLocaleDateString('en-CA',{timeZone:tenant.timezone})
  const in30 = new Date(new Date(`${today}T12:00:00`).getTime()+30*86400000).toLocaleDateString('en-CA',{timeZone:tenant.timezone})
  const [productsRes,lotsRes,wasteRes] = await Promise.all([
    supabase.from('products').select('id,name,sku,unit,min_stock,is_active').eq('tenant_id',tenant.tenant_id).eq('is_active',true).order('name'),
    supabase.from('lots').select('id,lot_code,expires_on,quantity_available,unit_cost,products(id,name,unit),warehouses(name)').eq('tenant_id',tenant.tenant_id).gt('quantity_available',0).order('expires_on',{ascending:true,nullsFirst:false}).limit(1000),
    supabase.from('waste_records').select('quantity,estimated_loss,reason,created_at,lots(products(name),lot_code)').eq('tenant_id',tenant.tenant_id).order('created_at',{ascending:false}).limit(100),
  ])
  const products = (productsRes.data ?? []) as unknown as Product[]
  const lots = (lotsRes.data ?? []) as unknown as Lot[]
  const wastes = (wasteRes.data ?? []) as unknown as Waste[]
  const stockByProduct = new Map<string,number>()
  for (const lot of lots) if (lot.products?.id) stockByProduct.set(lot.products.id,(stockByProduct.get(lot.products.id)??0)+Number(lot.quantity_available))
  const lowStock = products.map(p=>({...p,stock:stockByProduct.get(p.id)??0})).filter(p=>p.stock<=Number(p.min_stock))
  const expired = lots.filter(l=>l.expires_on && l.expires_on<today)
  const expiring = lots.filter(l=>l.expires_on && l.expires_on>=today && l.expires_on<=in30)
  const wasteLoss = wastes.reduce((sum,w)=>sum+Number(w.estimated_loss??0),0)
  const currency = new Intl.NumberFormat(tenant.country_code==='PE'?'es-PE':'es-ES',{style:'currency',currency:tenant.currency_code})
  const dateFormat = new Intl.DateTimeFormat(tenant.country_code==='PE'?'es-PE':'es-ES',{dateStyle:'medium',timeZone:tenant.timezone})
  const queryError = [productsRes.error,lotsRes.error,wasteRes.error].find(Boolean)?.message
  return <>
    <header className="top"><Link href="/dashboard" className="brand">🌿 MERMA <span>CERO</span></Link><Link href="/dashboard/inventory" className="btn secondary">Volver al inventario</Link></header>
    <main className="dashboard inventory-page">
      <p className="eyebrow">CONTROL Y RENTABILIDAD · {tenant.country_code==='PE'?'PERÚ':'ESPAÑA'}</p>
      <div className="split"><div><h1>Alertas e informes</h1><p>Resumen de existencias, caducidades y pérdidas registradas.</p></div><span className="tenant-chip">{tenant.tenant_name} · {tenant.currency_code}</span></div>
      {queryError && <div className="error">No se pudieron cargar todos los informes: {queryError}</div>}
      <div className="metricgrid">
        <div className="metric"><span className="muted">Productos bajo mínimo</span><b>{lowStock.length}</b></div>
        <div className="metric"><span className="muted">Lotes que caducan en 30 días</span><b>{expiring.length}</b></div>
        <div className="metric"><span className="muted">Lotes caducados con stock</span><b>{expired.length}</b></div>
      </div>
      <section className="section"><div className="section-heading"><div><h2>Alertas de stock mínimo</h2><p>Se compara la suma de existencias disponibles con el mínimo definido en cada producto.</p></div></div>
        <div className="table-wrap"><table><thead><tr><th>Producto</th><th>SKU</th><th>Existencias</th><th>Stock mínimo</th><th>Estado</th></tr></thead><tbody>{lowStock.map(p=><tr key={p.id}><td>{p.name}</td><td>{p.sku||'—'}</td><td>{p.stock} {p.unit}</td><td>{p.min_stock} {p.unit}</td><td><span className="status-warn">Reponer</span></td></tr>)}{!lowStock.length&&<tr><td colSpan={5} className="empty">No hay productos por debajo del mínimo.</td></tr>}</tbody></table></div>
      </section>
      <section className="section"><div className="section-heading"><div><h2>Caducidades próximas</h2><p>Lotes con existencia y fecha de caducidad dentro de los próximos 30 días.</p></div><span className="tag">Hasta {dateFormat.format(new Date(`${in30}T12:00:00`))}</span></div>
        <div className="table-wrap"><table><thead><tr><th>Producto</th><th>Almacén</th><th>Lote</th><th>Caducidad</th><th>Disponible</th></tr></thead><tbody>{expiring.map(l=><tr key={l.id}><td>{l.products?.name??'—'}</td><td>{l.warehouses?.name??'—'}</td><td>{l.lot_code||'—'}</td><td>{l.expires_on}</td><td>{l.quantity_available} {l.products?.unit??''}</td></tr>)}{!expiring.length&&<tr><td colSpan={5} className="empty">No hay lotes próximos a caducar en los siguientes 30 días.</td></tr>}</tbody></table></div>
      </section>
      <section className="section"><div className="section-heading"><div><h2>Lotes caducados con existencias</h2><p>Requieren revisión antes de cualquier salida o venta.</p></div></div>
        <div className="table-wrap"><table><thead><tr><th>Producto</th><th>Lote</th><th>Caducidad</th><th>Disponible</th><th>Valor de coste estimado</th></tr></thead><tbody>{expired.map(l=><tr key={l.id}><td>{l.products?.name??'—'}</td><td>{l.lot_code||'—'}</td><td>{l.expires_on}</td><td>{l.quantity_available} {l.products?.unit??''}</td><td>{currency.format(Number(l.quantity_available)*Number(l.unit_cost))}</td></tr>)}{!expired.length&&<tr><td colSpan={5} className="empty">No hay lotes caducados con existencias.</td></tr>}</tbody></table></div>
      </section>
      <section className="section"><div className="section-heading"><div><h2>Resumen de mermas</h2><p>Hasta 100 registros más recientes; no representa necesariamente el histórico completo.</p></div></div>
        <div className="metric"><span className="muted">Pérdida económica estimada en los registros mostrados</span><b>{currency.format(wasteLoss)}</b></div>
        <div className="table-wrap"><table><thead><tr><th>Fecha</th><th>Producto</th><th>Lote</th><th>Motivo</th><th>Cantidad</th><th>Pérdida estimada</th></tr></thead><tbody>{wastes.map((w,i)=><tr key={`${w.created_at}-${i}`}><td>{dateFormat.format(new Date(w.created_at))}</td><td>{w.lots?.products?.name??'—'}</td><td>{w.lots?.lot_code||'—'}</td><td>{w.reason}</td><td>{w.quantity}</td><td>{currency.format(Number(w.estimated_loss??0))}</td></tr>)}{!wastes.length&&<tr><td colSpan={6} className="empty">Todavía no hay mermas registradas.</td></tr>}</tbody></table></div>
      </section>
      <p className="muted footnote">Los informes son de consulta y se limitan a la empresa activa. El valor de los lotes caducados es una estimación al coste unitario registrado, no una valoración contable.</p>
    </main>
  </>
}
