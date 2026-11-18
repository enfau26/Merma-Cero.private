import Link from 'next/link'
import { requireActiveTenant } from '@/lib/tenant'
import { createClient } from '@/lib/supabase/server'
import { createCategoryAction, createProductAction, createWarehouseAction, updateProductAction, deactivateProductAction, deactivateWarehouseAction } from '@/actions/catalog'
import { receiveLotAction, consumeFefoAction, recordWasteAction } from '@/actions/inventory'

export const dynamic = 'force-dynamic'

function Field({ label, name, type = 'text', required = false, step, placeholder }: {label:string;name:string;type?:'text'|'number'|'date';required?:boolean;step?:string;placeholder?:string}) {
  return <label className="field"><span>{label}</span><input name={name} type={type} required={required} step={step} placeholder={placeholder}/></label>
}

export default async function InventoryPage() {
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const [productsRes, categoriesRes, warehousesRes, lotsRes, movementsRes] = await Promise.all([
    supabase.from('products').select('id,name,sku,unit,min_stock,is_perishable,is_active').eq('tenant_id', tenant.tenant_id).eq('is_active', true).order('name'),
    supabase.from('categories').select('id,name').eq('tenant_id', tenant.tenant_id).order('name'),
    supabase.from('warehouses').select('id,name').eq('tenant_id', tenant.tenant_id).eq('is_active', true).order('name'),
    supabase.from('lots').select('id,lot_code,received_on,expires_on,quantity_available,unit_cost,products(name,unit),warehouses(name)').eq('tenant_id', tenant.tenant_id).gt('quantity_available', 0).order('expires_on', { ascending: true, nullsFirst: false }).limit(100),
    supabase.from('stock_movements').select('id,movement_type,quantity,reason,created_at,lots(lot_code,products(name))').eq('tenant_id', tenant.tenant_id).order('created_at', { ascending: false }).limit(12),
  ])
  const products = productsRes.data ?? []
  const categories = categoriesRes.data ?? []
  const warehouses = warehousesRes.data ?? []
  const lots = lotsRes.data ?? []
  const movements = movementsRes.data ?? []
  const canManage = ['owner','admin','manager'].includes(tenant.role)
  const canOperate = ['owner','admin','manager','operator'].includes(tenant.role)
  const queryError = [productsRes.error,categoriesRes.error,warehousesRes.error,lotsRes.error,movementsRes.error].find(Boolean)?.message
  return <>
    <header className="top"><Link href="/dashboard" className="brand">🌿 MERMA <span>CERO</span></Link><div className="row"><Link className="btn secondary" href="/dashboard/reports">Alertas e informes</Link><Link className="btn secondary" href="/dashboard">Volver al panel</Link></div></header>
    <main className="dashboard inventory-page">
      <div className="split"><div><p className="eyebrow">OPERACIONES · {tenant.country_code === 'PE' ? 'PERÚ' : 'ESPAÑA'}</p><h1>Inventario y almacenes</h1><p>Controla catálogo, entradas, existencias, salidas FEFO y mermas.</p></div><span className="tenant-chip">{tenant.tenant_name} · {tenant.currency_code}</span></div>
      {queryError && <div className="error">No se pudieron cargar todos los datos: {queryError}. Comprueba que las migraciones 0001–0003 estén aplicadas.</div>}
      <div className="metricgrid"><div className="metric"><span className="muted">Productos activos</span><b>{products.length}</b></div><div className="metric"><span className="muted">Almacenes activos</span><b>{warehouses.length}</b></div><div className="metric"><span className="muted">Lotes con existencias</span><b>{lots.length}</b></div></div>

      <section className="section"><div className="section-heading"><div><h2>Catálogo</h2><p>Productos y categorías de esta empresa.</p></div></div>
        <div className="two-col">
          {canManage && <form action={createProductAction} className="form-card"><h3>Nuevo producto</h3><Field label="Nombre" name="name" required placeholder="Ej. Leche entera 1 L"/><div className="form-grid"><Field label="SKU" name="sku" placeholder="Opcional"/><Field label="Unidad" name="unit" placeholder="unidad, kg, L"/></div><div className="form-grid"><label className="field"><span>Categoría</span><select name="category_id" defaultValue=""><option value="">Sin categoría</option>{categories.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label><Field label="Stock mínimo" name="min_stock" type="number" step="0.001"/></div><label className="checkline"><input type="checkbox" name="is_perishable" defaultChecked/> Producto perecedero (controlar caducidad)</label><button className="btn" type="submit">Guardar producto</button></form>}
          {canManage && <form action={createCategoryAction} className="form-card"><h3>Nueva categoría</h3><Field label="Nombre de categoría" name="name" required placeholder="Ej. Lácteos"/><button className="btn" type="submit">Crear categoría</button><div className="tag-list">{categories.map(c=><span className="tag" key={c.id}>{c.name}</span>)}</div></form>}
        </div>
        <div className="table-wrap"><table><thead><tr><th>Producto</th><th>SKU</th><th>Unidad</th><th>Stock mínimo</th><th>Tipo</th><th>Gestión</th></tr></thead><tbody>{products.map(p=><tr key={p.id}><td>{p.name}</td><td>{p.sku || '—'}</td><td>{p.unit}</td><td>{p.min_stock}</td><td>{p.is_perishable ? 'Perecedero' : 'No perecedero'}</td><td>{canManage && <details><summary className="action-summary">Editar</summary><div className="row action-row"><form action={updateProductAction} className="compact-edit"><input type="hidden" name="id" value={p.id}/><input name="name" aria-label="Nombre" defaultValue={p.name} required/><input name="sku" aria-label="SKU" defaultValue={p.sku||''}/><input name="unit" aria-label="Unidad" defaultValue={p.unit}/><input name="min_stock" aria-label="Stock mínimo" type="number" min="0" step="0.001" defaultValue={p.min_stock}/><label className="checkline"><input type="checkbox" name="is_perishable" defaultChecked={p.is_perishable}/> Perecedero</label><button className="btn" type="submit">Guardar</button></form><form action={deactivateProductAction}><input type="hidden" name="id" value={p.id}/><button className="btn danger" type="submit">Desactivar</button></form></div></details>}</td></tr>)}{!products.length && <tr><td colSpan={6} className="empty">Todavía no hay productos.</td></tr>}</tbody></table></div>
      </section>

      <section className="section"><div className="section-heading"><div><h2>Almacenes</h2><p>Ubicaciones donde se controla el stock.</p></div></div>
        {canManage && <form action={createWarehouseAction} className="inline-form"><div className="grow"><Field label="Nombre del almacén" name="name" required placeholder="Ej. Almacén principal"/></div><button className="btn" type="submit">Crear almacén</button></form>}
        <div className="tag-list">{warehouses.map(w=><div className="tag" key={w.id}>▣ {w.name}{canManage && <form action={deactivateWarehouseAction} className="tag-form"><input type="hidden" name="id" value={w.id}/><button type="submit" aria-label={`Desactivar ${w.name}`} title="Desactivar almacén">×</button></form>}</div>)}{!warehouses.length && <span className="empty">No hay almacenes activos.</span>}</div>
      </section>

      <section className="section"><div className="section-heading"><div><h2>Movimientos de inventario</h2><p>Las cantidades se modifican exclusivamente mediante operaciones transaccionales.</p></div></div>
        {canOperate && <div className="three-col">
          <form action={receiveLotAction} className="form-card"><h3>Registrar entrada</h3><label className="field"><span>Producto</span><select name="product_id" required defaultValue=""><option value="" disabled>Selecciona</option>{products.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label><label className="field"><span>Almacén</span><select name="warehouse_id" required defaultValue=""><option value="" disabled>Selecciona</option>{warehouses.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></label><Field label="Cantidad recibida" name="quantity" type="number" step="0.001" required/><div className="form-grid"><Field label="Coste unitario" name="unit_cost" type="number" step="0.0001"/><Field label="Caducidad" name="expires_on" type="date"/></div><Field label="Código de lote" name="lot_code"/><Field label="Proveedor" name="supplier_name"/><button className="btn" type="submit" disabled={!products.length || !warehouses.length}>Registrar entrada</button></form>
          <form action={consumeFefoAction} className="form-card"><h3>Salida FEFO</h3><p className="small-help">El sistema descuenta primero los lotes que caducan antes.</p><label className="field"><span>Producto</span><select name="product_id" required defaultValue=""><option value="" disabled>Selecciona</option>{products.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label><label className="field"><span>Almacén</span><select name="warehouse_id" required defaultValue=""><option value="" disabled>Selecciona</option>{warehouses.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></label><Field label="Cantidad a retirar" name="quantity" type="number" step="0.001" required/><Field label="Motivo" name="reason" placeholder="Venta / consumo"/><Field label="Referencia" name="reference" placeholder="Pedido o documento (opcional)"/><button className="btn" type="submit" disabled={!products.length || !warehouses.length}>Confirmar salida FEFO</button></form>
          <form action={recordWasteAction} className="form-card"><h3>Registrar merma</h3><label className="field"><span>Lote</span><select name="lot_id" required defaultValue=""><option value="" disabled>Selecciona</option>{lots.map(l=><option key={l.id} value={l.id}>{l.products && !Array.isArray(l.products) ? l.products.name : 'Producto'} · {l.lot_code || l.id.slice(0,8)} · disp. {l.quantity_available}</option>)}</select></label><Field label="Cantidad perdida" name="quantity" type="number" step="0.001" required/><label className="field"><span>Motivo</span><select name="reason" required defaultValue=""><option value="" disabled>Selecciona</option><option>Caducidad</option><option>Deterioro</option><option>Rotura</option><option>Error de manipulación</option><option>Otro</option></select></label><button className="btn" type="submit" disabled={!lots.length}>Registrar merma</button></form>
        </div>}
        {!canOperate && <p className="notice">Tu rol permite consultar el inventario, pero no registrar operaciones.</p>}
      </section>

      <section className="section"><div className="section-heading"><div><h2>Existencias por lote</h2><p>Ordenadas por fecha de caducidad (FEFO). Máximo 100 lotes visibles.</p></div></div><div className="table-wrap"><table><thead><tr><th>Producto</th><th>Almacén</th><th>Lote</th><th>Caducidad</th><th>Disponible</th><th>Coste unitario</th></tr></thead><tbody>{lots.map(l=><tr key={l.id}><td>{l.products && !Array.isArray(l.products) ? l.products.name : '—'}</td><td>{l.warehouses && !Array.isArray(l.warehouses) ? l.warehouses.name : '—'}</td><td>{l.lot_code || '—'}</td><td>{l.expires_on || 'Sin fecha'}</td><td><strong>{l.quantity_available} {l.products && !Array.isArray(l.products) ? l.products.unit : ''}</strong></td><td>{Number(l.unit_cost).toFixed(4)} {tenant.currency_code}</td></tr>)}{!lots.length && <tr><td colSpan={6} className="empty">No hay existencias registradas.</td></tr>}</tbody></table></div></section>

      <section className="section"><div className="section-heading"><div><h2>Actividad reciente</h2><p>Últimos 12 movimientos registrados.</p></div></div><div className="table-wrap"><table><thead><tr><th>Fecha</th><th>Tipo</th><th>Producto / lote</th><th>Cantidad</th><th>Motivo</th></tr></thead><tbody>{movements.map(m=><tr key={m.id}><td>{new Date(m.created_at).toLocaleString(tenant.country_code === 'PE' ? 'es-PE' : 'es-ES', {dateStyle:'short',timeStyle:'short',timeZone:tenant.timezone})}</td><td>{({receipt:'Entrada',sale:'Salida FEFO',waste:'Merma',adjustment_in:'Ajuste +',adjustment_out:'Ajuste −',return:'Devolución',transfer_in:'Transferencia +',transfer_out:'Transferencia −'} as Record<string,string>)[m.movement_type] || m.movement_type}</td><td>{m.lots && !Array.isArray(m.lots) && m.lots.products && !Array.isArray(m.lots.products) ? m.lots.products.name : '—'} · {m.lots && !Array.isArray(m.lots) ? m.lots.lot_code || '—' : '—'}</td><td>{m.quantity}</td><td>{m.reason || '—'}</td></tr>)}{!movements.length && <tr><td colSpan={5} className="empty">Todavía no hay movimientos.</td></tr>}</tbody></table></div></section>
      <p className="muted footnote">Los formularios requieren que las migraciones SQL estén aplicadas en Supabase. Las acciones se ejecutan en servidor y respetan RLS; la base de datos valida permisos y stock.</p>
    </main>
  </>
}
